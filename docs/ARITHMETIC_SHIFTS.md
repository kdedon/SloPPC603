# Arithmetic word shifts — round 16

SRAW/SRAWI implement Rc0/Rc1 through the registered integer path, bringing the
executable subset to 88 forms. Exact opcode31 XO792/824 decode maps rS to rA.
SRAW uses the low six bits of real rB; SRAWI supplies its five-bit SH immediate
without an rB dependency. The ALU enum widens from four to five bits.

Counts 32–63 produce all sign bits. CA is replaced on every instruction: it is
one only when the source is negative and at least one discarded bit is one.
Count zero clears CA; 0x80000000 shifted by 31 yields 0xffffffff with CA0,
while count32 yields the same value with CA1. OV/SO are preserved. Rc forms
record the final signed result plus captured SO. Both forms acquire flag
ownership even when Rc is zero; they do not consume old CA.

## Verification

- `test-core-arithmetic-shifts`: independent symbolic interpreter with bit selection,
  2,684 retirements and 206,971 complete architectural-state checks. Eight source
  patterns cover every register count0–63 and immediate count0–31, both Rc forms,
  upper count bits, real r0 and operand aliases. The memory/branch base program
  remains included; initial SO0 and later SO1 are exercised.
- `test-arithmetic-shift-execution`: 91 literal checks for pending source/count,
  captured controls, full result packets and backpressure; CA input is deliberately
  opposite the expected replacement.
- `test-sraw-recovery` and `test-srawi-recovery`: 3,434 checks each across RS/IU/CQ
  cancellation, kept finish and commit/redirect coincidence. Real instructions seed
  CA/OV/SO; a redirected ADDE observes retained or replaced CA.

All 32 prior RTL targets, strict core/wrapper lint and 120 Python tests pass.
Compiled decode validation passes 15,808 probes, 655 accepted.
Targeted independent RTL review found no actionable issues. Source editorial
conflicts and the reviewed semantic contract remain in ISA_MATRIX/CR_XER_CONTRACT.
This is functional coverage of the bounded pipeline; full 603e timing and FPGA
resource/timing measurements remain open. RLWIMI is the next integer slice.

Round17 subsequently accepts [RLWIMI](ROTATE_INSERT.md); all 90 currently reviewed forms execute. Earlier pending/count statements describe their original rounds.
