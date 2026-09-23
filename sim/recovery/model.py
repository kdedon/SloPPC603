"""Executable recovery policy proposal; not an emulator or RTL verification model.

State transitions use pre-edge eligibility. Producer tokens model the lifetime
contract that future cancellation/drain RTL must enforce.
"""
from dataclasses import dataclass, replace

MASK32 = (1 << 32) - 1


@dataclass(frozen=True, order=True)
class Tag:
    slot: int
    generation: int


@dataclass
class Entry:
    tag: Tag
    serial: int
    dst: int | None
    rename: int | None
    done: bool = False
    value: int = 0
    fault: bool = False
    issued: bool = False


@dataclass(frozen=True)
class Redirect:
    target: int
    pivot: Tag | None = None  # None is an explicit all-speculation cut.
    keep_pivot: bool = True

    def __post_init__(self):
        if not 0 <= self.target <= MASK32 or self.target % 4:
            raise ValueError("redirect target must be an aligned 32-bit PC")


@dataclass(frozen=True)
class Events:
    allocated: Tag | None = None
    finished: Tag | None = None
    committed: tuple[int, int | None, int] | None = None
    killed: tuple[Tag, ...] = ()
    redirect_accepted: bool = False
    redirect_rejected: str | None = None
    issue_accepted: bool = False
    result_consumed: bool = False


class RecoveryModel:
    def __init__(self, depth=5, rename_depth=5, generation_bits=8):
        if min(depth, rename_depth, generation_bits) < 1:
            raise ValueError("positive resource dimensions required")
        self.depth, self.rename_depth = depth, rename_depth
        self.generation_mask = (1 << generation_bits) - 1
        self.reset()

    def reset(self):
        """Environment must cancel every external token when applying reset."""
        self.entries: list[Entry] = []
        self.generations = [0] * self.depth
        self.tail = 0
        self.tokens: dict[Tag, str] = {}
        self.arch = [0] * 32
        self.mapping: dict[int, Tag] = {}
        self.next_serial = 0
        self.retired: list[tuple[int, int | None, int]] = []

    def candidate(self):
        return Tag(self.tail, (self.generations[self.tail] + 1) & self.generation_mask)

    def operand(self, reg):
        """Pre-edge read; caller captures this before step's destination updates."""
        if not 0 <= reg < 32:
            raise ValueError("GPR index out of range")
        tag = self.mapping.get(reg)
        if tag is None:
            return True, self.arch[reg], None
        entry = next(e for e in self.entries if e.tag == tag)
        return entry.done, entry.value, tag

    def step(self, *, allocate=False, dst=None, fault=False, issue=None,
             producer_kind="local", result=None, redirect=None, retire_ready=False):
        if dst is not None and not 0 <= dst < 32:
            raise ValueError("GPR index out of range")
        if producer_kind not in ("local", "external"):
            raise ValueError("unknown producer cancellation kind")
        pre = [replace(e) for e in self.entries]
        pre_tokens = dict(self.tokens)
        survivors = [replace(e) for e in pre]
        accepted, rejected = False, None
        if redirect is not None:
            if redirect.pivot is None:
                cut = 0
            else:
                found = next((i for i, e in enumerate(pre) if e.tag == redirect.pivot), None)
                cut = None if found is None else found + int(redirect.keep_pivot)
            if cut is None:
                rejected = "inactive_pivot"
            elif cut == 0 and pre and pre[0].done:
                # Existing retirement interface has no offer-cancellation signal.
                rejected = "irrevocable_retirement_head"
            else:
                accepted = True
                survivors = [replace(e) for e in pre[:cut]]
        keep = {e.tag for e in survivors}
        killed = tuple(e.tag for e in pre if e.tag not in keep)
        if accepted:
            if survivors:
                self.tail = (survivors[-1].tag.slot + 1) % self.depth
            elif pre:
                self.tail = pre[0].tag.slot
            for tag in killed:
                if self.tokens.get(tag) == "local":
                    del self.tokens[tag]
        # Finish qualification is evaluated against pre-edge ownership and tokens.
        finished = None
        if result is not None:
            tag, value = result
            self.tokens.pop(tag, None)  # Transport consumes even a killed response.
            entry = next((e for e in survivors if e.tag == tag), None)
            if entry is not None and not entry.done and tag in pre_tokens:
                entry.done, entry.value = True, value & MASK32
                finished = tag
        committed = None
        if pre and pre[0].done and pre[0].tag in keep and retire_ready:
            head = survivors.pop(0)
            if head.dst is not None:
                self.arch[head.dst] = head.value
            committed = (head.serial, head.dst, head.value)
            self.retired.append(committed)
        issue_accepted = False
        if issue is not None:
            entry = next((e for e in survivors if e.tag == issue), None)
            if entry is not None and not entry.issued and not entry.done:
                entry.issued = True
                self.tokens[issue] = producer_kind
                issue_accepted = True
        # Allocation uses pre-edge capacity: no same-edge reclaim, even at full.
        allocated = None
        used_rename = {e.rename for e in pre if e.rename is not None}
        free_rename = next((i for i in range(self.rename_depth) if i not in used_rename), None)
        needs_rename = dst is not None and not fault
        candidate = self.candidate()
        if (allocate and not accepted and len(pre) < self.depth
                and (not needs_rename or free_rename is not None)
                and candidate not in pre_tokens):
            allocated = candidate
            survivors.append(Entry(candidate, self.next_serial, None if fault else dst,
                                   free_rename if needs_rename else None, done=fault, fault=fault))
            self.next_serial += 1
            self.generations[candidate.slot] = candidate.generation
            self.tail = (self.tail + 1) % self.depth
        self.entries = survivors
        self.mapping = {e.dst: e.tag for e in survivors if e.dst is not None}
        self.check_invariants()
        return Events(allocated, finished, committed, killed, accepted, rejected,
                      issue_accepted, result is not None)

    def check_invariants(self):
        assert len(self.entries) <= self.depth
        assert len({e.tag.slot for e in self.entries}) == len(self.entries)
        assert len({e.serial for e in self.entries}) == len(self.entries)
        assert [e.serial for e in self.entries] == sorted(e.serial for e in self.entries)
        renames = [e.rename for e in self.entries if e.rename is not None]
        assert len(renames) == len(set(renames)) <= self.rename_depth
        assert self.mapping == {e.dst: e.tag for e in self.entries if e.dst is not None}
        for older, younger in zip(self.entries, self.entries[1:]):
            assert younger.tag.slot == (older.tag.slot + 1) % self.depth
        if self.entries:
            assert self.tail == (self.entries[-1].tag.slot + 1) % self.depth
        active = {e.tag for e in self.entries}
        assert all(kind == "external" for tag, kind in self.tokens.items() if tag not in active)
        assert all(not e.done or e.tag not in self.tokens for e in self.entries)


@dataclass(frozen=True)
class FetchEvents:
    request: int | None = None
    request_accepted: bool = False
    response_consumed: bool = False
    packet: tuple[int, int] | None = None


class FetchDrainModel:
    """Explicit offer capture preserves valid/ready promises across redirect."""
    def __init__(self, reset_pc=0xFFF00100):
        self.reset_pc = reset_pc
        self.reset()

    def reset(self):
        self.pc = self.reset_pc
        self.offered: int | None = None
        self.pending: int | None = None
        self.target: int | None = None

    def offer(self):
        if self.pending is not None:
            return None
        if self.offered is None and self.target is None:
            self.offered = self.pc
        return self.offered

    def step(self, *, request_ready=False, response=None, packet_ready=False, redirect=None):
        if redirect is not None and (not 0 <= redirect <= MASK32 or redirect % 4):
            raise ValueError("redirect target must be an aligned 32-bit PC")
        request = self.offer()
        was_pending = self.pending
        if redirect is not None:
            self.target = redirect
        request_accepted = request is not None and request_ready
        if request_accepted:
            self.pending, self.offered = request, None
        consumed = was_pending is not None and response is not None and (
            self.target is not None or packet_ready)
        packet = None
        if consumed:
            if self.target is None:
                packet = (was_pending, response & MASK32)
                self.pc = (was_pending + 4) & MASK32
            self.pending = None
        if self.pending is None and self.offered is None and self.target is not None:
            self.pc, self.target = self.target, None
        return FetchEvents(request, request_accepted, consumed, packet)
