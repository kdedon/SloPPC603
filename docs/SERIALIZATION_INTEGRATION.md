# Bounded architectural serialization

The optional integration profile now executes exact 603e `isync`, `sync`, and
`eieio` instructions. They share the existing
`ENABLE_SUPERVISOR_EXCEPTIONS` parameter because that parameter already gates
the core's context-control integration. It defaults to zero, so the established
168-form default decoder and reference profile remain unchanged.

| Instruction | Exact word | Local action |
|---|---:|---|
| `isync` | `0x4c00012c` | Commit-time refetch redirect to `PC + 4` |
| `sync` | `0x7c0004ac` | Conservative full drain of implemented older work |
| `eieio` | `0x7c0006ac` | Conservative ordering of the implemented uncached transport |

All operand, reserved, XO, and Rc bits are fixed by these exact words. The
forms are user-level and have no GPR, CR, XER, LR, CTR, MSR, SRR, or memory
write permission.

MTMSR remains unsupported. This core cannot yet honor its possible translation,
endian, interrupt, floating-point, trace, or machine-check mode changes, and an
execution-synchronizing write without those execution semantics would create a
false architectural success.

## Sources

The processor-specific source is *MPC603e & EC603e RISC Microprocessors User's
Manual* (1997), local file
`../1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf`, SHA-256
`6bad9fb8a3a13792f93a8593d795e0b03d3ab0349846c62fe28008a1b22e63c7`:

- PDF 98, printed 2-20, Section 2.3.2.4.2 says SYNC and ISYNC wait for
  previously initiated instructions before the synchronization completes.
- PDF 118, printed 2-40, Section 2.3.5.2 says ISYNC discards prefetched
  instructions and branches to the next sequential instruction. It also says
  the 603e treats EIEIO as a no-op because its cache-inhibited accesses are
  already strictly ordered.
- PDF 151, printed 3-25, Sections 3.7.7 and 3.7.9 give the 603e EIEIO and ISYNC
  behavior. ISYNC has no effect on other processors or their caches.
- PDF 259, printed 6-13, Section 6.3.3.2 classifies SYNC/ISYNC as dispatch
  serialized and ISYNC as refetch serialized: subsequent instructions are
  forced to refetch after retirement.
- PDF 269, printed 6-23, Table 6-2 lists ISYNC, SYNC, and EIEIO in the SRU.
  The current serialized lane is functional and does not claim those cycle
  timings.
- Appendix A rows on PDFs 362, 364, and 368 plus X/XL form tables A-36/A-37
  establish primary opcodes 31/19, XO854/150/598, and the fixed fields.

The architectural cross-check is *PowerPC Microprocessor Family: The
Programming Environments, Rev. 1*, local file `../MPCFPE.pdf`, SHA-256
`0600de0a3cb81636b9d511aa6b185e2fccc02f895ce4630411725634ef8e7eee`:

- PDF 159, printed 4-9 through 4-10, Section 4.1.5 distinguishes ISYNC context
  synchronization from SYNC execution synchronization.
- PDF 209, Section 4.2.6 states that completed SYNC makes older memory effects
  visible to the mechanisms that access those locations.
- PDF 213, Section 4.3.2 says ISYNC discards prefetched instructions and
  refetches subsequent instructions in the established context.
- PDFs 228-229, printed 5-2 through 5-3, Sections 5.1.1.1 and 5.1.1.2
  distinguish EIEIO ordering from stronger SYNC ordering. EIEIO may complete
  before earlier accesses are performed with respect to system memory, while
  SYNC waits for the coherent effects described by the architecture.

## Implemented ordering boundary

All three instructions use `ppc_special`. Dispatch is admitted only after the
completion queue is empty, the normal reservation station/IU are idle, and the
one-outstanding special/memory lane is idle. Once dispatched, the special lane
blocks younger dispatch through accepted retirement. Therefore:

- every older load has received and consumed its response and retired;
- every older store has received its response and retired;
- no younger load or store request is offered before the barrier retires; and
- a stalled barrier retirement remains stable and continues to block younger
  state and requests.

This is stronger than the ordering required of EIEIO for the implemented
transport, but it is safe. The data interface has one uncached outstanding
request and preserves program order already, matching the 603e reason for
treating EIEIO as a no-op. SYNC also drains this transport, but the interface
has no signal for second-level caches, coherent completion in another agent,
alternate bus masters, cache management, or global broadcast. A retired SYNC
therefore proves ordering only over the implemented CPU transport.

## ISYNC refetch edge

ISYNC captures its instruction PC at dispatch. When its exact completion entry
is accepted at retirement, it asserts the existing internal branch-class
redirect with target `PC + 4` modulo 32 bits. The completion recovery uses
`keep_pivot` on the simultaneous commit edge. Serialization guarantees the
pivot is the only CQ entry, so there is no younger CQ state to preserve.

That accepted recovery clears the instruction queue and invokes the fetch
recovery contract. Any already offered old instruction request remains stable;
an accepted old response is drained and discarded. Fetch then requests PC+4
again. This gives changed backing instruction memory a fresh request, but it
does not invalidate an instruction cache or make modified code coherent. Cache
maintenance remains separate system work.

The internal ISYNC redirect wins over a concurrent external redirect, and the
public external `redirect_accepted_o` remains false on that edge. Before CQ
finish, an accepted external all-cut may cancel ISYNC and select its own target;
the stale result is suppressed and cannot redirect later. Once ISYNC is the
finished offered head, the normal completion irrevocability rule rejects a cut
that would remove it. Reset withdraws the special result/redirect and clears
the in-flight barrier state.

## Verification

`tb_serialization_decode` checks 168 conditions across the three exact words,
all low 26 fixed-bit mutations, permission normalization, default-profile
rejection, and neighboring MTMSR/TLBSYNC exclusions.

`tb_core_serialization` checks 124 conditions in an actual core:

- delayed older load response, SYNC stall, and a dependent younger store;
- delayed older store acknowledgement, EIEIO stall, and a younger load;
- absence of younger requests and GPR effects across both stalled barriers;
- an old PC+4 instruction response discarded and changed code refetched by
  ISYNC without an external redirect;
- concurrent external/ISYNC redirect priority and one internal redirect;
- `0xffff_fffc + 4` target wrap;
- pre-finish ISYNC cancellation and stale-finish suppression; and
- reset of a held barrier followed by clean restart.

Run from `ppc603e/` after the parent Make wiring is present:

```sh
make -C sim test-serialization-decode
make -C sim test-core-serialization
(cd sim && verilator --lint-only -Wall --top-module ppc_core -f ../rtl/files.f)
python3 sim/tools/isa_generate.py --check
python3 sim/tools/test_isa.py
```

The focused direct Verilator 5.020 runs reported `PASS (168 checks)` and
`PASS (124 checks)`. Strict core lint passed. The ISA validator reports 178
reviewed entries: 168 default implemented, seven supervisor opt-in, and three
serialization opt-in. All 35 ISA metadata tests pass, including the unchanged
default compiled decoder probe of 26,048 words with 935 accepted.

## Remaining scope

This milestone does not establish 603e synchronization timing or complete
system memory ordering. It has no cache coherency, WIMG, instruction-cache
invalidation, bus broadcast/acknowledgement, alternate requester, reservation,
TLB synchronization, or multiprocessor observation model. MTMSR and other
context-changing instructions remain diagnostics. A future cached integration
must define explicit instruction-cache invalidation and modified-code
coherency instead of treating the fresh backing-memory request here as a full
self-modifying-code protocol.
