# FPU core integration

`ppc_core` parameter `ENABLE_FPU` attaches the standalone 603e FPU
([interface](FPU_INTERFACE.md), [contract](FPU_CONTRACT.md)). The default,
`ENABLE_FPU=0`, keeps the previous behavior: FP-class opcodes take FP
unavailable and MSR[FP] never sets under full decode. `ENABLE_FPU=1` requires
`ENABLE_FULL_DECODE` and `ENABLE_LIVE_CONTEXT` (MSR[FP] and MSR[FE0/FE1] change
only through `mtmsr` and `rfi`) and a 603e variant (`cpu_cfg().fpu` is
`FPU_DP`) or the 602 ([below](#602-personality)), and `ENABLE_TEST_REDIRECT=0` (a pivot recovery would need tagged
FPU aborts); elaboration fails otherwise. `ppc_core_bat`, `ppc_core_bat_bus60x`,
`ppc_core_bat_cached_bus60x` and the `ppc603e` and `ppc602` pin tops pass the
parameter through with default 0. Builds with the FPU add `rtl/ppc_ram_lut.sv` (already
in the cache lists) and `rtl/fpu_files.f`; every other list carries only
`ppc_fpu_pkg.sv`. `FPU_IMPL` selects `ppc_fpu` (FULL, the default and the
timing below) or `ppc_fpu_compact` ([COMPACT](FPU_COMPACT.md): same results,
one instruction in flight, longer latencies).

`ppc_core` parameter `DMEM_BITS` (32 or 64, 64 only with the FPU) sets the
data port width. At 64 a doubleword-aligned `lfd`/`stfd` is one access: all
eight strobes, the word at EA in the upper half; other accesses keep the low
half and four strobes. `ppc_core_bat`, the router and `ppc_dcache_slot`
(`LSU_BITS`) carry the width to the data cache, whose 64-bit lanes and
single-beat bus requests already take eight bytes (one 60x tenure, TSIZ
000). `ppc_core_bat_cached_bus60x` selects 64 when both the FPU and the data
cache are present; every other build keeps 32 and splits a doubleword into
two word accesses.

## Execution model

FP arithmetic, move, select, compare and FPSCR instructions (primary opcodes
59 and 63) issue into the FPU in the dispatch cycle. They read no GPR, so
dispatch needs only a CQ entry and FPU issue readiness; they dispatch behind
and ahead of integer work, one instruction per cycle like everything else.
The FPU resolves FPR dependencies, forwarding, initiation intervals and
FPSCR barriers itself. The CQ entry allocates finished; it retires when the
FPU's oldest held result carries its tag and no exception, and the FPU
commits in the same cycle. So the core adds nothing to Table 6-5: an
instruction dispatched in cycle n retires in cycle n + latency + 1, the
completion cycle of UM Figure 6-3.

FP loads and stores other than update forms go the way of plain integer
accesses ([PERFORMANCE.md](PERFORMANCE.md#pipelined-loadstore-path)): outside
trace mode and replay, with MSR[FP]=1, they dispatch into the load/store lane
without draining the CQ once rA (unless zero) and, for indexed forms, rB have
no uncommitted producer, and issue into the FPU in the same cycle. Younger
integer work dispatches behind them. Ordering and speculation:

- A load dispatches only when every older FP instruction in flight is a
  released load, so its access is in the execution path. While it holds the
  lane no FP instruction dispatches, which keeps FPU results in CQ order. On
  a fault-free result the lane finishes its CQ entry and releases; the FPU
  commit then happens at retirement through the pipelined port, and the next
  access dispatches on the release edge.
- A store may dispatch behind FP work that can still fault, because it writes
  only at the CQ head. Younger FP instructions may dispatch behind it. If an
  older FP instruction replays, the recovery cancels the store, which has
  neither committed in the FPU nor been offered.
- Plain integer accesses wait only for FP work that can still fault.
- Update forms, trace mode and a replayed access keep the serialized lane.

CR updates (`fcmpu`, `fcmpo`, `mcrfs`, Rc=1) come from the FPU's result at
retirement. FP CR writers do not take the flag token; CR writes apply in
retirement order, and a branch reading CR waits while any FP CR writer is in
flight. Integer CR readers other than branches already drain the CQ.

Trace mode, and the one FP instruction that follows an FP exception replay,
use the serialized lane instead.

Measured without retirement stalls
([verification](FPU_CORE_INTEGRATION_VERIFICATION.md)). Latency is
dispatch-to-retirement of an isolated instruction; spacing is between the
retirement of the first and last of a group issued back to back after a
`sync` (four instances and three intervals; two instances for divides,
estimates and FPSCR instructions).

| Instruction | Table 6-5 latency / interval | Latency | Independent spacing | Dependent spacing |
| --- | --- | --- | --- | --- |
| `fadd(s)`, `fmuls`, `fmadds`, `frsp`, `fctiw`, `frsqrte` | 3 / 1 | 4 | 3 (1 each) | 9 (3 each) |
| `fcmpu` (distinct crfD) | 3 / 1 | 4 | 3 | — |
| `fmul`, `fmadd` (double) | 4 / 2 | 5 | 6 (2 each) | 12 (4 each) |
| `fdivs`, `fres` | 18 / 18 | 19 | 18 | — |
| `fdiv` | 33 / 33 | 34 | 33 | — |
| `fmr`, `fsel` | 3 / 1 | 4 | 3 | 9 (3 each) |
| `mffs`, `mtfsf`, `mtfsfi`, `mcrfs` | 3, blocking | 4 | 5 (`mffs`, `mtfsfi` pairs) | — |
| `lfs`, `lfd` | 2 / 1 | 6 | 15 (5 each) | — |
| `stfs`, `stfiwx`, `stfd` | 2 / 1 | 7 | 18 (6 each) | — |
| `stfd` of an `fadd` result | — | — | 6 (`fadd` to `stfd` retirement) | — |
| `lwz`, `stw` (integer reference) | 2 / 1 | 5 | — | — |
| `add` (integer reference) | 1 | 3 | — | — |

Moves, selects and FPSCR instructions finish in their third stage, as Table
6-5 lists them (1-1-1): they retire from the FPU's registered result like
arithmetic, while a dependent `fmr` or `fsel` still sees the value after three
cycles. Mixed streams (`fadd`, `addi`, `fmuls`, `addi`, `fmadd`, `addi`)
dispatch one per cycle; each `addi` retires the cycle after the older FP
instruction; an `lfd` followed by three `addi` dispatches them on
consecutive cycles. Memory rows include the bench's one-cycle memory with
`DMEM_BITS=64`; with 32 an `lfd` takes 8 and an `stfd` 9, and four take 21
and 24. Spacing for memory rows is between the dispatches, and equally the
retirements, of the first and last of four independent accesses.

Through the lane, Table 6-6's 2-cycle latency and 1-cycle interval are not
met by any access: the lane holds one access at a time (offer, translate,
cache, result). FP accesses add the FPU's issue-to-request cycle and, for
stores, the commit at the CQ head before the write. With `ENABLE_LSU_PIPE`
plain FP accesses run in the pipelined unit instead: `lfs`, `lfd` and the
stores retire at dispatch + 3 (two execute cycles, as FP rows count), and
loads stream one per cycle
([LSU_PIPELINE.md](LSU_PIPELINE.md#fp-accesses)).

### Data-dependent timing

Three rare cases add cycles on the 603e and 603; ordinary operands keep the
rows above.

- Sticky serialization (UM §4.5.7.1, PDF 188). With MSR[FE0/FE1] clear, a
  result whose FPSCR update newly sets an exception sticky bit (OX, UX, ZX,
  XX or a VX cause) completes one cycle late, and alone. The manual allows
  one or two cycles without a rule; §6.3.3.2 (PDF 259) limits serialized
  instructions to one completion per cycle, so at width 2 a younger
  instruction that would complete beside it waits a second cycle. Later
  results setting the same bit do not stall. The first `fadds` setting XX
  retires at dispatch + 5, the next at + 4.
- Single-precision denormal results (UM §2.3.4.2, PDF 103). The FULL FPU
  holds a single-precision result that the rounder denormalizes (tiny
  before rounding, with NI=0 and UE=0) two more cycles in its third stage,
  and the stages behind it wait: `fmuls` 2^-70 × 2^-70 finishes in 5, an
  `fadds` accepted the next cycle in 5, a single divide in 20. Double
  results are not affected. COMPACT keeps its own timing.
- `lfs`/`stfs` of a single denormal (same note). The manual bounds the
  conversion at 24 cycles and gives no rule. The unit converts in one cycle
  per significand bit position shifted, plus one: 2 cycles for fraction
  bit 22 set, 24 for 2^-149. A load takes its response, and a store offers
  its data, that many cycles later, in the lane and in the pipelined unit.
  `stfiwx` stores no single and is not affected. A store's response carries
  no load data and is never held: a data cache store hit answers only in
  the cycle it is taken (`test-chip-fpu-lsu-pipe`).

## Lane sequence (loads and stores)

1. Dispatch captures the instruction word, the committed GPR values of rA and
   rB and the MSR, then offers the FPU issue packet.
2. An FP load's memory request becomes a load (`SPECIAL_LOAD`) at the FPU's
   EA. A doubleword is one eight-byte access when `DMEM_BITS=64` and EA is
   doubleword aligned; otherwise two word accesses, EA then EA+4, returned
   to the FPU as one 64-bit response. Faults are classified exactly as for
   integer loads (DSI, TLB miss, machine check, transport diagnostic). The
   lane takes the FPU's result in the cycle the FPU accepts the response.
3. A store's preparation request is answered at once without an access. When
   the FPU result arrives without an exception, the lane waits for the queue
   head with retirement authorized (the integer store rule), commits the FPU
   to obtain the store descriptor, then writes one or two words. Write faults
   are precise: the instruction has not retired.
4. Any other result finishes the completion entry and is held until
   retirement, where the FPU commit applies FPR and FPSCR updates. CR1 or
   crfD comes from the FPU's CR proposal; the update-form base comes from its
   GPR proposal. An overlapped load that completes without a fault releases
   the lane here instead (see above).

The FPU interface asks the LSU to prepare a store (translate and check) before
the FPU publishes its result. Here the check happens at the write, before
retirement, so exceptions stay precise; the preparation response itself
carries no information.

An instruction that does not write its allocated CR field or update-form base
(an exception, or a form the FPU rejects) rewrites the committed value: the
lane runs alone, so nothing else can have changed it.

The lane also runs any FP arithmetic instruction in trace mode and the one
that follows an FP exception replay.

## Exceptions

A pipelined FP instruction whose result carries an exception does not retire.
One cycle after its result reaches the CQ head, a recovery removes it and
everything younger (the FPU discards its work on the following edge), and
fetch restarts at its address. It then re-executes alone in the serialized
lane, which raises the exception below. Nothing younger has retired and the
FPU commits nothing for the removed instruction, so the replay sees the same
FPRs and FPSCR and reproduces the result. The cost is the refetch and one
serialized execution, only for instructions that take an exception.

An older exception (a DSI on a plain integer load, say) removes younger
pipelined FP work the same way. Branches resolve at dispatch, so an FP
instruction behind a taken branch never dispatches.

FPU results map onto the existing special-lane events; SRR0 is the
instruction's address in every case.

| FPU result | Event | Vector, SRR1 cause | State |
| --- | --- | --- | --- |
| `FPU_ILLEGAL` (reserved fields, invalid forms) | program | `0x700`, bit 12 | none |
| `FPU_UNAVAILABLE` (MSR[FP]=0) | FP unavailable | `0x800` | none |
| `FPU_ALIGNMENT` (EA not word aligned) | alignment | `0x600`; DAR = EA, DSISR from the instruction (UM Table 4-13) | none |
| `FPU_MEMORY_FAULT` | DSI, TLB miss or machine check as for integer accesses | DAR/DSISR as for integer | none |
| `FPU_FP_ENABLED` (`(FE0∨FE1)∧FEX`) | program, new `EVENT_PROGRAM_FP` | `0x700`, bit 11 | FPR, FPSCR and CR1 committed per PEM Tables 3-12–16 |

Decode keeps `fsqrt(s)` and unlisted opcodes illegal before the FPU; the FPU
rejects reserved-field forms ahead of MSR[FP], so illegal outranks FP
unavailable. A late exception fences fetch and waits for fetch and memory
quiescence before its entry, as a data exception does.

A split doubleword whose second word faults reports DAR = EA+4 (the faulting
word), as the split integer accesses do. Its first word has been read but
nothing is written. A split doubleword store whose second word faults after
the first word was written leaves that word written. With `DMEM_BITS=64`
only a word-aligned doubleword that crosses a doubleword boundary splits, and
only one crossing a page can fault on its second word, a case the integer
split stores share.

## Enabling FE0/FE1 with FEX set

With FPSCR[FEX] = 1 and MSR[FE0] = MSR[FE1] = 0, an `mtmsr` that sets FE0 or
FE1 takes the FP enabled program exception (`0x700`) before the next
instruction (PEM Table 6-14; UM 4.5.7 defers to the architecture): SRR0 is
`mtmsr` + 4, SRR1 holds the new MSR with bits 11 and 15 set, and the new MSR
is entered as for any exception. Both personalities. The lane decides at the
`mtmsr`'s retirement from the committed FPSCR, which is final because
`mtmsr` dispatches with older work retired, and raises the exception instead
of installing the context.

An `rfi` from MSR[FE0] = MSR[FE1] = 0 whose SRR1 sets FE0 or FE1 does the
same (`EVENT_RFI_FP_ENABLE`): SRR0 is the `rfi` target, the instruction that
would have executed next, and SRR1 holds the MSR the `rfi` restored with
bits 11 and 15 set. An `rfi` in problem state stays a privileged-instruction
exception. Every exception entry clears FE0/FE1, so a handler that returns
with FE set in SRR1 while FEX is still set takes the exception again; the
handlers must clear FEX, or FE in SRR1, before `rfi`.

## Limits

- The lane holds one access at a time; FP loads and stores do not meet Table
  6-6 (2-cycle latency, 1-cycle interval). Update forms stay serialized. The
  FPU's second issue lane and second retirement lane stay unused. The
  integer core retires one instruction per cycle.
- FP exceptions pay a refetch and a serialized replay.
- Without the data cache (`ppc_core_bat_bus60x`, or `ENABLE_DCACHE=0`) a
  doubleword access is two 32-bit bus transactions; another bus master can
  observe or change memory between them.
- DTLB load and store misses on `lfd`/`stfd` are tested on the pin top
  only. DSI, the C=0 store miss and TEA are tested on every FP access form
  with the core bench's memory; TEA on a store the store queue already
  retired (asynchronous machine check) is not tested for FP stores.
- FPSCR instructions let the next FP instruction issue only after they
  retire.

## 602 personality

With `CPU_VARIANT=CPU_602` the lane attaches the FPU with `CPU_602=1` (FULL or
COMPACT); the execution model above is unchanged.

- Decode sends every FP form to the FPU, which decides the emulation trap
  (`0x1600`): double-precision arithmetic, `fctiw`, a source without its SP
  or LT tag, `lfd` of a value that is no normal binary32, `stfd` of NaN,
  infinity or a denormal, and an enabled numeric exception regardless of
  MSR[FE0/FE1] (602 UM 4.5.7.1, [contract](FPU_602_CONTRACT.md)). `fsqrt(s)`
  stays illegal (4.5.7.2). An FPSCR write that sets FEX with FE0 or FE1 set
  is the FP enabled program exception (Table 4-2).
- SP (SPR 1021) and LT (1022) live in the FPU. `mtspr`, `mfspr` and the
  `mftb` form of them run in the serialized lane: `mtspr` data travels as
  `gpr_b`, and the FPU's GPR proposal writes `mfspr`'s rD at retirement.
  They are privileged, checked at dispatch, and need no MSR[FP]. Without the
  FPU the special lane keeps both registers.
- FP loads are legal at any byte offset (602 UM 2.2.3): the lane reads the
  two words an `lfs` spans, or the three of an `lfd`, and returns the bytes
  at EA. A DSI on the first word reports DAR = EA, on a later word its word
  address, as split integer accesses do. An unaligned access always uses
  word transfers. Unaligned FP stores take the alignment exception.
- With MSR[FE0] = MSR[FE1] = 0, an FP result whose FPSCR proposal sets an
  exception sticky bit (OX, UX, ZX, XX or a VX cause) that the committed
  FPSCR lacks retires one cycle late: the completion serialization of 602
  UM 4.5.7.1 and 6.8.7, which allow one or two cycles and give no rule for
  two. Later results setting the same bit do not stall. FP arithmetic in
  the serialized lane (trace mode) stalls the same way.

602 limits:

- `mtspr` to SP or LT drains the queue and blocks dispatch until it
  retires. 602 UM 6.7.1 completion-serializes it, which the drain meets,
  but 6.7.2 does not dispatch-serialize it. Every FP instruction reads the
  SP/LT tags and must wait for it anyway; only younger integer work could
  overlap, and the lane overlaps memory accesses only. Slower, never faster.
- Table 6-6's FP rows (`lfs`, `stfs`, `stfiwx` 2:1; `lfd`, `stfd` 3:2) are
  met with the pipelined unit over a one-access-per-cycle memory
  ([LSU_PIPELINE.md](LSU_PIPELINE.md#fp-accesses)); the lane is slower.
  COMPACT's latencies are its own ([FPU_COMPACT.md](FPU_COMPACT.md)).
- Without the data cache a doubleword or an unaligned load is several bus
  transactions; another master can change memory between them.
