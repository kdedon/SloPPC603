# FPU core integration

`ppc_core` parameter `ENABLE_FPU` attaches the standalone 603e FPU
([interface](FPU_INTERFACE.md), [contract](FPU_CONTRACT.md)). The default,
`ENABLE_FPU=0`, keeps the previous behavior: FP-class opcodes take FP
unavailable and MSR[FP] never sets under full decode. `ENABLE_FPU=1` requires
`ENABLE_FULL_DECODE` and `ENABLE_LIVE_CONTEXT` (MSR[FP] and MSR[FE0/FE1] change
only through `mtmsr` and `rfi`) and a variant whose `cpu_cfg().fpu` is
`FPU_DP`, and `ENABLE_TEST_REDIRECT=0` (a pivot recovery would need tagged
FPU aborts); elaboration fails otherwise. `ppc_core_bat`, `ppc_core_bat_bus60x`,
`ppc_core_bat_cached_bus60x` and the `ppc603e` pin top pass the parameter
through with default 0. Builds with the FPU add `rtl/ppc_ram_lut.sv` (already
in the cache lists) and `rtl/fpu_files.f`; every other list carries only
`ppc_fpu_pkg.sv`. `FPU_IMPL` selects `ppc_fpu` (FULL, the default and the
timing below) or `ppc_fpu_compact` ([COMPACT](FPU_COMPACT.md): same results,
one instruction in flight, longer latencies).

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

FP loads and stores keep the serialized lane (below). They wait for an empty
CQ, so the FPU is empty when one issues, and the lane and the pipelined path
never hold FPU work together. Plain integer loads and stores do not dispatch
while pipelined FP work is in flight; an FP instruction may dispatch behind
an overlapping plain access.

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
| `fmr`, `fsel` | 3 / 1 | 3 | 3 | 9 (3 each) |
| `mffs`, `mtfsf`, `mtfsfi`, `mcrfs` | 3, blocking | 3 | 4 (`mffs`, `mtfsfi` pairs) | — |
| `lfs` / `lfd` (serialized lane) | 2 / 1 | 8 / 10 | — | — |
| `stfs`, `stfiwx` / `stfd` (serialized lane) | 2 / 1 | 9 / 11 | — | — |
| `add` (integer reference) | 1 | 3 | — | — |

`fmr`, `fsel` and the FPSCR instructions retire one cycle early in
isolation: the standalone FPU returns them after two cycles (its timing
record owns that schedule), while a dependent `fmr` or `fsel` still waits the
Table 6-5 three cycles. Mixed streams (`fadd`, `addi`, `fmuls`, `addi`,
`fmadd`, `addi`) dispatch one per cycle; each `addi` retires the cycle after
the older FP instruction. Memory rows include the bench's one-cycle memory:
each word is a separate request and response.

## Lane sequence (loads and stores)

1. Dispatch captures the instruction word, the committed GPR values of rA and
   rB and the MSR, then offers the FPU issue packet.
2. An FP load's memory request becomes a word load (`SPECIAL_LOAD`) at the
   FPU's EA; a doubleword is two word accesses, EA then EA+4, returned to the
   FPU as one 64-bit response. Faults are classified exactly as for integer
   loads (DSI, TLB miss, machine check, transport diagnostic).
3. A store's preparation request is answered at once without an access. When
   the FPU result arrives without an exception, the lane waits for the queue
   head with retirement authorized (the integer store rule), commits the FPU
   to obtain the store descriptor, then writes one or two words. Write faults
   are precise: the instruction has not retired.
4. Any other result finishes the completion entry and is held until
   retirement, where the FPU commit applies FPR and FPSCR updates. CR1 or
   crfD comes from the FPU's CR proposal; the update-form base comes from its
   GPR proposal.

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

A doubleword whose second word faults reports DAR = EA+4 (the faulting word),
as the split integer accesses do. Its first word has been read but nothing is
written. A doubleword store whose second word faults after the first word was
written leaves that word written; the 603e never splits an aligned
doubleword, so this can only occur for a word-aligned doubleword crossing a
page, a case the integer split stores share.

## Limits

- FP loads and stores are serialized (empty CQ, younger dispatch blocked);
  the FPU's second issue lane and second retirement lane stay unused. The
  integer core retires one instruction per cycle.
- FP exceptions pay a refetch and a serialized replay.
- A doubleword access is two 32-bit bus transactions; another bus master can
  observe or change memory between them.
- An `mtmsr` or `rfi` that sets FE0/FE1 while FPSCR[FEX]=1 does not raise the
  deferred FP enabled exception.
- Not tested: page-changed faults and machine checks on FP accesses. DTLB
  load and store misses on `lfd`/`stfd` are tested on the pin top only.
- The standalone FPU returns `fmr`, `fsel` and the FPSCR instructions one
  cycle before Table 6-5 (their isolated latency is 3, not 4); FPSCR
  instructions let the next FP instruction issue only after they retire.
- FP loads and stores do not meet Table 6-6 (2-cycle hit latency, 1-cycle
  interval).
- The 602 personality (V12) is rejected at elaboration; see below.

## 602 personality (V12)

Attaching `ppc_fpu #(.CPU_602(1))` to the 602 core needs:

- Decode: route every FP form to the FPU as `SPECIAL_FPU`; the FPU owns the
  emulation-trap decision (double-precision forms and operand SP/LT tags), so
  `SPECIAL_FPU_EMULATE` and the core's 602 emulation split go away.
- SP and LT (SPR 1021/1022) move from the special lane's SPR file to the FPU's
  tagged path: `mtspr` data travels as `gpr_b`, and `mfspr` needs a GPR
  destination allocated at dispatch and written from the FPU's GPR proposal.
- Unaligned FP loads are legal on the 602: the lane must split a 4- or 8-byte
  access at any byte offset (the unaligned integer datapath does up to two
  words; a misaligned doubleword needs three).
- The completion controller must add the 602's variable stall when a disabled
  sticky exception sets with MSR[FE]=0 (602 UM §4.5.7.1).
- `FPU_EMULATION_TRAP` and `FPU_PRIVILEGED` already map to the `0x1600` and
  privileged program events.
