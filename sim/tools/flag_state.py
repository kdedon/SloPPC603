#!/usr/bin/env python3
"""Independent CR0/XER masked-commit and one-owner lifecycle reference."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Iterable

import add_family
import logical_family
import shift_family

MASK32 = 0xFFFF_FFFF
CR0_MASK = 0xF000_0000
XER_SO_MASK = 0x8000_0000
XER_OV_MASK = 0x4000_0000
XER_CA_MASK = 0x2000_0000
OWNER_DEPTH = 5
GENERATION_MODULUS = 256


class FlagStateError(ValueError):
    pass


def _bit(value: int | bool, name: str) -> int:
    if value not in (0, 1, False, True):
        raise FlagStateError(f"{name} must be 0 or 1")
    return int(value)


def _word(value: int, name: str) -> int:
    if not isinstance(value, int) or not 0 <= value <= MASK32:
        raise FlagStateError(f"{name} must be a 32-bit unsigned value")
    return value


@dataclass(frozen=True)
class OwnerTag:
    index: int
    generation: int

    def __post_init__(self) -> None:
        if not isinstance(self.index, int) or not 0 <= self.index < OWNER_DEPTH:
            raise FlagStateError("owner index must select one of five completion slots")
        if not isinstance(self.generation, int) or not 0 <= self.generation < GENERATION_MODULUS:
            raise FlagStateError("owner generation must be an eight-bit value")


@dataclass(frozen=True)
class WritePermissions:
    read_ca: bool = False
    read_so: bool = False
    write_ca: bool = False
    write_ov_so: bool = False
    write_cr0: bool = False

    def __post_init__(self) -> None:
        for name in ("read_ca", "read_so", "write_ca", "write_ov_so", "write_cr0"):
            if type(getattr(self, name)) is not bool:
                raise FlagStateError(f"{name} must be bool")
        if (self.write_ov_so or self.write_cr0) and not self.read_so:
            raise FlagStateError("OV/SO or CR0 writers must capture incoming SO")

    @property
    def needs_flags(self) -> bool:
        return self.read_ca or self.read_so or self.write_ca or self.write_ov_so or self.write_cr0

    @property
    def cr_mask(self) -> int:
        return CR0_MASK if self.write_cr0 else 0

    @property
    def xer_mask(self) -> int:
        return (XER_CA_MASK if self.write_ca else 0) | (
            (XER_SO_MASK | XER_OV_MASK) if self.write_ov_so else 0
        )


@dataclass(frozen=True)
class CompletionPayload:
    value: int
    ca: int = 0
    ov: int = 0
    so: int = 0
    cr0: int = 0

    def __post_init__(self) -> None:
        _word(self.value, "result value")
        for name in ("ca", "ov", "so"):
            _bit(getattr(self, name), name)
        if not isinstance(self.cr0, int) or not 0 <= self.cr0 <= 0xF:
            raise FlagStateError("cr0 must be a four-bit value")


@dataclass(frozen=True)
class ArchitecturalState:
    cr: int = 0
    xer: int = 0
    gprs: tuple[int, ...] = field(default_factory=lambda: (0,) * 32)

    def __post_init__(self) -> None:
        _word(self.cr, "cr")
        _word(self.xer, "xer")
        if len(self.gprs) != 32:
            raise FlagStateError("gprs must contain exactly 32 values")
        for index, value in enumerate(self.gprs):
            _word(value, f"gprs[{index}]")


@dataclass(frozen=True)
class CommitPacket:
    permissions: WritePermissions
    payload: CompletionPayload
    gpr_write: bool = False
    gpr: int = 0

    def __post_init__(self) -> None:
        if type(self.gpr_write) is not bool:
            raise FlagStateError("gpr_write must be bool")
        if not isinstance(self.gpr, int) or not 0 <= self.gpr < 32:
            raise FlagStateError("gpr must be a five-bit register index")


@dataclass(frozen=True)
class AllocationRequest:
    tag: OwnerTag
    permissions: WritePermissions
    gpr_write: bool = True
    gpr: int = 0

    def __post_init__(self) -> None:
        if type(self.gpr_write) is not bool:
            raise FlagStateError("gpr_write must be bool")
        if not isinstance(self.gpr, int) or not 0 <= self.gpr < 32:
            raise FlagStateError("gpr must be a five-bit register index")


@dataclass(frozen=True)
class CapturedAllocation:
    request: AllocationRequest
    ca_in: int
    so_in: int

    def __post_init__(self) -> None:
        _bit(self.ca_in, "ca_in")
        _bit(self.so_in, "so_in")
        if not self.request.permissions.needs_flags:
            raise FlagStateError("flag-free allocation cannot own the flag token")


@dataclass(frozen=True)
class PreparedOperation:
    permissions: WritePermissions
    payload: CompletionPayload


@dataclass(frozen=True)
class EdgeOutcome:
    retired: bool = False
    finished: bool = False
    wake: bool = False
    killed: bool = False
    acquired: bool = False
    captured: CapturedAllocation | None = None


def apply_commit(state: ArchitecturalState, packet: CommitPacket) -> ArchitecturalState:
    """Atomically apply the GPR write and allocated CR/XER write masks."""
    # Dataclass construction validates the complete packet before this pure update.
    permissions, payload = packet.permissions, packet.payload
    cr_candidate = payload.cr0 << 28
    xer_candidate = (payload.so << 31) | (payload.ov << 30) | (payload.ca << 29)
    cr = (state.cr & ~permissions.cr_mask) | (cr_candidate & permissions.cr_mask)
    xer = (state.xer & ~permissions.xer_mask) | (xer_candidate & permissions.xer_mask)
    gprs = state.gprs
    if packet.gpr_write:
        updated = list(gprs)
        updated[packet.gpr] = payload.value
        gprs = tuple(updated)
    return ArchitecturalState(cr=cr, xer=xer, gprs=gprs)


def check_commit_transition(
    before: ArchitecturalState,
    packet: CommitPacket,
    after: ArchitecturalState,
) -> None:
    """Reject any split, missing, or extra effect relative to one atomic commit."""
    expected = apply_commit(before, packet)
    if after != expected:
        raise FlagStateError("architectural transition is not the allocated atomic commit")


def validate_completion(allocation: CapturedAllocation, payload: CompletionPayload) -> None:
    """Check cross-field invariants derivable from allocation and captured SO."""
    permissions = allocation.request.permissions
    if permissions.write_ov_so:
        expected_so = allocation.so_in | payload.ov
        if payload.so != expected_so:
            if allocation.so_in and not payload.so:
                raise FlagStateError("sticky SO cannot clear an incoming one")
            raise FlagStateError("SO must equal incoming SO OR current OV")
    if permissions.write_cr0:
        relation = payload.cr0 & 0xE
        expected_relation = 0x8 if payload.value & 0x8000_0000 else (0x2 if payload.value == 0 else 0x4)
        if relation != expected_relation:
            raise FlagStateError("CR0 LT/GT/EQ must describe the signed result value")
        final_so = payload.so if permissions.write_ov_so else allocation.so_in
        if (payload.cr0 & 1) != final_so:
            raise FlagStateError("CR0.SO must use the instruction's final SO")


def prepare_add(
    family: str,
    a: int,
    b: int = 0,
    *,
    ca_in: int = 0,
    oe: int = 0,
    rc: int = 0,
    ov_in: int = 0,
    so_in: int = 0,
    old_cr0: int = 0,
) -> PreparedOperation:
    """Use the reviewed ADD reference to make one complete result packet."""
    if family not in add_family.XO:
        raise FlagStateError(f"unknown ADD family: {family}")
    oe, rc = _bit(oe, "oe"), _bit(rc, "rc")
    ca_in, ov_in, so_in = (_bit(value, name) for value, name in (
        (ca_in, "ca_in"), (ov_in, "ov_in"), (so_in, "so_in")
    ))
    result = add_family.evaluate(
        family, a, b, ca=ca_in, oe=oe, rc=rc,
        old_ov=ov_in, old_so=so_in, old_cr0=old_cr0,
    )
    permissions = WritePermissions(
        read_ca=family in {"adde", "addme", "addze"},
        read_so=bool(oe or rc),
        write_ca=family != "add",
        write_ov_so=bool(oe),
        write_cr0=bool(rc),
    )
    return PreparedOperation(
        permissions,
        CompletionPayload(result.value, result.ca, result.ov, result.so, result.cr0),
    )


def prepare_shift(
    family: str,
    source: int,
    count: int,
    *,
    rc: int = 0,
    ca_in: int = 0,
    ov_in: int = 0,
    so_in: int = 0,
    old_cr0: int = 0,
) -> PreparedOperation:
    """Use the reviewed shift reference while deriving allocation permissions here."""
    if family not in shift_family.XO:
        raise FlagStateError(f"unknown shift family: {family}")
    rc = _bit(rc, "rc")
    result = shift_family.evaluate(
        family, source, count, rc=rc, ca=ca_in, ov=ov_in, so=so_in, old_cr0=old_cr0,
    )
    writes_ca = family in {"sraw", "srawi"}
    permissions = WritePermissions(
        read_so=bool(rc), write_ca=writes_ca, write_cr0=bool(rc)
    )
    return PreparedOperation(
        permissions,
        CompletionPayload(result.value, result.ca, result.ov, result.so, result.cr0),
    )


def prepare_logical(
    family: str,
    source: int,
    operand: int,
    *,
    rc: int = 0,
    ca_in: int = 0,
    ov_in: int = 0,
    so_in: int = 0,
    old_cr0: int = 0,
) -> PreparedOperation:
    """Prepare a logical result; only record forms need flag ownership."""
    if family not in logical_family.XO:
        raise FlagStateError(f"unknown logical family: {family}")
    rc = _bit(rc, "rc")
    result = logical_family.evaluate(
        family, source, operand, rc=rc, ca=ca_in, ov=ov_in, so=so_in, old_cr0=old_cr0,
    )
    permissions = WritePermissions(read_so=bool(rc), write_cr0=bool(rc))
    return PreparedOperation(
        permissions,
        CompletionPayload(result.value, result.ca, result.ov, result.so, result.cr0),
    )


class FlagOwnerModel:
    """One speculative flag owner with exact identity and registered finish state."""

    def __init__(self, state: ArchitecturalState | None = None) -> None:
        self.state = state if state is not None else ArchitecturalState()
        self.owner: CapturedAllocation | None = None
        self.finished: CompletionPayload | None = None

    @property
    def busy(self) -> bool:
        return self.owner is not None

    def advance(
        self,
        *,
        retire: OwnerTag | None = None,
        finish: tuple[OwnerTag, CompletionPayload] | None = None,
        allocate: AllocationRequest | None = None,
        post_commit_survivors: Iterable[OwnerTag] | None = None,
    ) -> EdgeOutcome:
        """Apply one edge using pre-edge availability/readiness and exact tags.

        A non-None survivor collection denotes an accepted redirect and blocks
        allocation. This list contains only surviving flag-owner identities,
        not every CQ survivor, and describes post-commit state.
        """
        pre_owner = self.owner
        pre_finished = self.finished
        pre_busy = pre_owner is not None
        recovery = post_commit_survivors is not None
        survivor_list = tuple(post_commit_survivors or ())
        retired = bool(
            retire is not None and pre_owner is not None and pre_finished is not None
            and retire == pre_owner.request.tag
        )
        if recovery:
            if len(survivor_list) != len(set(survivor_list)):
                raise FlagStateError("recovery flag-owner list contains a duplicate")
            if len(survivor_list) > 1:
                raise FlagStateError("at most one flag owner may survive recovery")
            if pre_owner is None and survivor_list:
                raise FlagStateError("recovery names a flag owner when none is allocated")
            if pre_owner is not None and survivor_list and survivor_list[0] != pre_owner.request.tag:
                raise FlagStateError("recovery survivor is not the exact allocated flag owner")
            if retired and survivor_list:
                raise FlagStateError("retiring flag owner must be absent from post-commit survivors")

        survivors = frozenset(survivor_list)
        if retired:
            validate_completion(pre_owner, pre_finished)
            packet = CommitPacket(
                permissions=pre_owner.request.permissions,
                payload=pre_finished,
                gpr_write=pre_owner.request.gpr_write,
                gpr=pre_owner.request.gpr,
            )
            self.state = apply_commit(self.state, packet)
            self.owner = None
            self.finished = None

        killed = False
        if recovery and self.owner is not None and self.owner.request.tag not in survivors:
            self.owner = None
            self.finished = None
            killed = True

        finished = False
        if finish is not None and self.owner is not None and self.finished is None:
            tag, payload = finish
            if tag == self.owner.request.tag:
                validate_completion(self.owner, payload)
                self.finished = payload
                finished = True

        acquired = False
        captured = None
        if allocate is not None and not recovery:
            if not allocate.permissions.needs_flags:
                acquired = True
            elif not pre_busy:
                captured = CapturedAllocation(
                    request=allocate,
                    ca_in=int(bool(self.state.xer & XER_CA_MASK)),
                    so_in=int(bool(self.state.xer & XER_SO_MASK)),
                )
                self.owner = captured
                self.finished = None
                acquired = True

        return EdgeOutcome(
            retired=retired,
            finished=finished,
            wake=bool(finished and self.owner is not None and self.owner.request.gpr_write),
            killed=killed,
            acquired=acquired,
            captured=captured,
        )
