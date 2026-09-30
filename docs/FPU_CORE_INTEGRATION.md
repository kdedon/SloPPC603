# FPU core integration

`ppc_core` parameter `ENABLE_FPU` attaches the standalone 603e FPU
([interface](FPU_INTERFACE.md), [contract](FPU_CONTRACT.md)). The default,
`ENABLE_FPU=0`, keeps the previous behavior: FP-class opcodes take FP
unavailable and MSR[FP] never sets under full decode. `ENABLE_FPU=1` requires
`ENABLE_FULL_DECODE` and `ENABLE_LIVE_CONTEXT` (MSR[FP] and MSR[FE0/FE1] change
only through `mtmsr` and `rfi`) and a variant whose `cpu_cfg().fpu` is
`FPU_DP`; elaboration fails otherwise. `ppc_core_bat`, `ppc_core_bat_bus60x`,
`ppc_core_bat_cached_bus60x` and the `ppc603e` pin top pass the parameter
through with default 0. Builds with the FPU add `rtl/ppc_ram_lut.sv` (already
in the cache lists) and `rtl/fpu_files.f`; every other list carries only
`ppc_fpu_pkg.sv`.

## Execution model: serialized

Every FP instruction is a special-lane operation. It dispatches only into an
empty completion queue with the IU idle, and blocks younger dispatch until it
retires (or, for a store, until its bus writes complete). The FPU therefore
never holds more than one instruction, and FP work never overlaps integer
work or other FP work.

This is an explicit throughput trade, not a conformance claim. Table 6-5
latencies inside the FPU are preserved; the lane adds four cycles
(issue register, result capture, completion finish, retirement), and the
Table 6-5 initiation intervals (1 or 2 cycles) are not met: back-to-back
independent FP instructions issue one per dispatch-to-retirement latency.
Pipelined overlap needs the FPU's second issue lane, forwarding outputs and
tagged commit connected to a non-serialized dispatch path; that is future work.

Measured dispatch-to-retirement cycles, no retirement stalls, operands normal
([verification](FPU_CORE_INTEGRATION_VERIFICATION.md)):

| Instruction | Table 6-5 latency | Measured | Measured − 4 |
| --- | --- | --- | --- |
| `fadd(s)`, `fmuls`, `fmadds`, `frsp`, `fctiw`, `fcmpu`, `frsqrte` | 3 | 7 | 3 |
| `fmul`, `fmadd` (double) | 4 | 8 | 4 |
| `fdivs`, `fres` | 18 | 22 | 18 |
| `fdiv` | 33 | 37 | 33 |
| `fmr`, `fsel`, `mffs`, `mtfsf`, `mtfsfi`, `mcrfs` | 3 | 6 | 2 |
| `lfs` / `lfd` | 2 | 8 / 10 | — |
| `stfs`, `stfiwx` / `stfd` | 2 | 9 / 11 | — |

The move and FPSCR rows show the FPU returning those results one cycle earlier
than the arithmetic rows; the standalone timing record owns that schedule.
Memory rows include the bench's one-cycle memory: each word is a separate
request and response.

## Lane sequence

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

## Exceptions

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

- Serialized issue, as above; no FP/IU overlap and no second retirement lane.
- A doubleword access is two 32-bit bus transactions; another bus master can
  observe or change memory between them.
- Recovery that cancels the lane (the test-only redirect port) aborts the
  FPU instruction by tag; no bench exercises it.
- An `mtmsr` or `rfi` that sets FE0/FE1 while FPSCR[FEX]=1 does not raise the
  deferred FP enabled exception.
- Not tested at the system level: TLB miss and page-changed faults on FP
  accesses (the classification is the integer path's), and machine checks.
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
