# Opcode self-test

A demo-SoC program that runs every instruction group against expected results
computed on the host from the manuals, and shows the outcome as pages of
pass/fail cells. The same image is a Verilator regression target and a MiSTer
core. Like the other demo programs it is a measurement vehicle: the feature
contracts and their verification records stay the authority on processor
behaviour, and a disagreement found here is triaged against the manuals.

Sources: [`toolchain/demo/selftest/`](../toolchain/demo/selftest): `gen.py`
(cases and model), `check_enc.py` (encoding check), `runner.S` (vectors and case
entry), `selftest.c` (compare, report, display), `selftest.ld`.
Results: [SELFTEST_VERIFICATION.md](SELFTEST_VERIFICATION.md).

## Cases and expected values

`gen.py <variant>` builds each case as a short instruction sequence with its input
state, runs it through its own model of the instructions and writes three files:

- `cases.S`: each case's instructions as words, followed by `b st_done`;
- `cases.h`: the case table, the inputs and the expected outputs;
- `check.S`: the same instructions as assembler mnemonics.

`check_enc.py` assembles `check.S` with the cross assembler and requires every word
of `cases.S` to match, so a case runs the instruction its name says. The model is
written from the MPC603e User's Manual (UM) and the Programming Environments Manual
(PEM); the 602 differences come from the ISA matrix
([`sim/spec/isa.json`](../sim/spec/isa.json), 602UM) and
[CPU_VARIANTS.md](CPU_VARIANTS.md). It is independent of the RTL and of DingusPPC.

A case's state is every GPR, CR, XER, LR, CTR, the exception outcome (vector, SRR0,
SRR1, the MSR, DAR, DSISR), a 256-byte data buffer and, on a processor with an FPU,
every FPR and the FPSCR. Inputs not given take a fixed
default (distinct GPR patterns, a byte pattern in the buffer, CR/XER/LR/CTR zero).
The runner compares the whole state: the expected state is the input state with the
case's expected changes applied, each under a mask. Masked bits are the ones the
manuals leave undefined:

| Case | Unchecked | Source |
|---|---|---|
| `divw`, `divwu` by zero, `0x80000000 / -1` | rD; CR0 LT/GT/EQ | PEM `divw`/`divwu` |
| PVR | revision (low half) | UM 2.1.1 |
| `mftb` | the time base values | |
| TLB-miss SRR1 | WAY (bit 14) | UM Table 4-4 |
| Alignment DSISR, non-update forms | bits 27–31 (rA) | PEM Table 6-12 |
| Alignment DSISR, `dcbz` | bits 22–26 | UM Table 4-13 |

Readings of the manuals the model makes where they leave room:

- A misaligned `lmw` or `stmw` puts EA + 4 in DAR (UM 4.5.6, the note after
  Table 4-14), not the EA of Table 4-13. The 602 image uses the EA.
- A scalar that crosses a 4-KB boundary under MSR[DR] takes the alignment exception
  in a BAT area too (UM 4.5.6.1.1: no special handling for BAT regions).
- A load or store to a T = 1 segment takes DSI (UM 3.4.3) before any TLB lookup,
  with DSISR bit 5, and bit 6 for a store, and DAR the EA.

Values relative to the case (branch targets in LR/CTR, SRR0 of an exception inside
the case) are stored as offsets and adjusted by the runner.

### Groups

| Group | Contents |
|---|---|
| INT | add/subtract families with every OE/Rc form and CA/OV/SO/CR0; immediates; multiply, divide; logical, extend, `cntlzw` |
| ROT | `rlwinm`, `rlwnm`, `rlwimi`, `slw`, `srw`, `sraw`, `srawi` with record forms and 6-bit shift counts |
| CMP/BR | the four compares into several fields; the eight CR logicals, `mcrf`, `mcrxr`, `mtcrf`, `mfcr`; `b`/`bl`/`ba`/`bla`, `bc` for every BO class with and without LK, `bclr`/`bcctr` |
| LD/ST | every width, update, indexed and byte-reverse form; unaligned scalars within a page; `lmw`/`stmw`; `lswi`/`lswx`/`stswi`/`stswx`; `lwarx`/`stwcx.` success, failure and SO copy |
| SPR | SPRG0–3, SRR0/1, DAR, DSISR, XER, LR, CTR, PVR, EAR; `mtmsr`/`mfmsr` including a switch to problem state and turning IR/DR off; `mtsr`/`mfsr`/`mtsrin`/`mfsrin`; `rfi` to supervisor and user; `sync`, `isync`, `eieio`, `mftb` |
| EXC | `tw`/`twi` taken and not; illegal encodings; privileged instructions in problem state; `sc`; alignment (`lmw`, `stmw`, `lwarx`, `stwcx.`, page-crossing scalars, `dcbz` to cache-inhibited memory); DSI (store through a read-only BAT, direct-store segment, `eciwx`/`ecowx` with EAR[E] clear); ISI (fetch through a no-access BAT); ITLB/DTLB load/store misses |
| CACHE | `dcbz`, `dcbf`, `dcbst`, `dcbt`, `dcbtst` (data preserved), `dcbi` (discards a modified block), `icbi` (rewritten code runs), `tlbie`, `tlbsync` |
| FP | every FP opcode takes FP unavailable (0x800); `fsqrt`, `fsqrts` are illegal (UM Table B-1); with an FPU, the cases under [Floating point](#floating-point) |

Exception cases check the vector, SRR0, SRR1 (MSR bits and the cause flags), the
handler-entry MSR (ME, IP, and TGPR for TLB misses), and DAR/DSISR where the manual
defines them.

### Variants

One image per variant: `selftest.hex` (PID7v-603e) and `selftest-602.hex`. The
variant sets the expected outcome of opcodes it does not implement: on the 602 the
string instructions take the emulation trap (0x1600) and `eciwx`/`ecowx` and EAR are
illegal. The demo SoC hosts only the 603e package, so the 602 image is built and its
encodings checked but it does not run yet.

### Floating point

The FP-unavailable cases run with MSR[FP] clear, so they hold with or without an FPU.
The 603e image also carries 171 cases with MSR[FP] set (`build_fp_unit` in `gen.py`),
marked as needing the FPU. `selftest.c` reads `MODE` bit 8 (`ENABLE_FPU`,
[DEMO_SOC.md](DEMO_SOC.md#registers)): without an FPU it skips them and leaves the FP
state out of the comparison; with one, `runner.S` loads every FPR and the FPSCR
(`mtfsf 0xff`) before the case and stores them after, and they join the compared
state. One image serves both SoCs.

Expected results of arithmetic, rounding, conversion and compare instructions come
from the FPU's reference model ([`sim/fpu/ppc_reference.py`](../sim/fpu/ppc_reference.py),
exact integer arithmetic, with the FPSCR update of
[`sim/fpu/enabled_vectors.py`](../sim/fpu/enabled_vectors.py)); `gen.py` models the
moves, `fsel`, estimate specials, FPSCR instructions, record forms, loads and stores
itself (PEM chapter 3 and the instruction pages). The groups:

| Kind | Cases |
|---|---|
| Arithmetic | `fadd`, `fsub`, `fmul`, `fdiv` and single forms: exact and inexact results in all four rounding modes, signed zero, QNaN propagation, VXSNAN, VXISI, VXIMZ, VXZDZ, VXIDI, ZX, overflow, underflow, denormal results, NI |
| Fused | `fmadd`, `fmsub`, `fnmadd`, `fnmsub` and single forms, including an operand set whose result is exact only with one rounding; VXIMZ and VXISI |
| Conversion | `frsp` in three rounding modes, overflow, denormal, SNaN; `fctiw`/`fctiwz` with RN, ties, saturation (VXCVI) and NaN |
| Compare | `fcmpu`/`fcmpo` into CR fields 0–7: ordered results, QNaN and SNaN (VXSNAN, VXVC) |
| Move, select, estimate | `fmr`, `fneg`, `fabs`, `fnabs` (NaN payloads kept); `fsel` on positive, negative, −0 and NaN; `fres` and `frsqrte` of ±0, +∞, −1 and SNaN |
| FPSCR | `mffs`, `mtfsf` (all fields, one field, field 0), `mtfsfi`, `mtfsb0`, `mtfsb1` (setting OX also sets FX), `mcrfs` (copies and clears exception bits) |
| Record forms | 17 `.` forms: CR1 from FX, FEX, VX, OX |
| Enabled exceptions | FE0 = FE1 = 1 with VE, ZE, OE, UE or XE: program 0x700 with SRR1 bit 11; FPR, FPSCR and CR1 as the PEM exception tables leave them; VE without FE and FE without VE |
| Load/store | every FP load and store form, update and indexed; single conversion of denormal, zero, infinity and SNaN; `stfs` denormalisation; `stfiwx`; alignment (DAR, DSISR) for four forms; a load in problem state |

Values the manuals leave undefined are masked: the high word after `fctiw`, `fctiwz` and
`mffs`; FPRF after `fctiw`/`fctiwz`; FR after an overflow with OE clear; FR and FI after
an estimate of an infinity or QNaN. Single-precision instructions get only operands
representable in single precision, and estimates only inputs with exact results.

## Runner

`runner.S` owns the vectors (0x200–0x1600, `CRT0_OWN_VECTORS` in `crt0.S`).
`st_enter` saves the caller's registers, loads the whole input state and enters the
case with `rfi` under the case's MSR (supervisor or problem state, translation on).
Every vector stores the full state to the output and returns to the caller; the TLB
miss vectors first clear MSR[TGPR] so the stored r0–r3 are the case's. A case ends
with `b st_done`, whose `sc` the caller recognises by SRR0 and reports as completion.

Memory the cases use, set up by `selftest.c`:

| Address | Mapping | Use |
|---|---|---|
| `0xfff3c000`, 256 B | DBAT0 (RAM) | Data buffer, reset before each case |
| `0xfff3c800` | DBAT0 | `icbi` stub, written by its case |
| `0x10020000`, 128 KiB | DBAT2, read-only alias of `0xfff20000` | DSI on store |
| `0x20020000`, 128 KiB | IBAT2, no access | ISI |
| `0x3xxxxxxx` | SR3 with T = 1 | Direct-store DSI |
| `0x4xxxxxxx` | SR4, no BAT, empty TLB | TLB misses |
| `0xf0100fe0` | DBAT1, cache-inhibited | `dcbz` alignment |

## Display and input

After the run the program prints `selftest <variant> PVR ...: N cases, P pass, F
fail`, the per-group counts and, for each failure, the case, its instructions and each
differing field with expected, actual and mask. Then it draws pages of cells: a check
or cross and the mnemonic. The header shows the total and the page's counts; the
footer `page n/N - press A or Enter`. The layout follows the framebuffer size (four
columns of 19 rows at 320 × 240, eight of 34 at 1920 × 1080); nothing scrolls.

The SoC `INPUT` register ([DEMO_SOC.md](DEMO_SOC.md#registers)) drives the pages when
bit 31 (present) is set, as on the MiSTer: the arrows or d-pad move the selection, the
panel below the grid shows the selected case (instructions, inputs, and for a failure
which of GPR/CR/XER/LR/CTR/VEC/SRR/MSR/DAR/MEM differ with expected and actual values),
A or Enter turns the page and B or Esc turns back. It starts at the first failure. The
exit register is written with the failure count before the first page.

Without an input device (simulation), every page is drawn in turn and the program
exits with the number of failed cases, so the bench passes only when every case does.

## Running

```sh
make -C sim test-selftest                      # 603e image on the demo SoC bench
make -C sim test-selftest-fpu                  # the same image on the SoC with ENABLE_FPU
./toolchain/build-in-container.sh -f demo/Makefile selftest   # both images
mister/build.sh --clean --suite selftest       # MiSTer core, PPC603e_selftest_*.rbf
```

The MiSTer core builds with `MISTER_BENCH` (256 KiB of program RAM, no program menu);
the image is `mister-selftest.hex`, the 603e image.

## Not covered

Page-table translation and `tlbld`/`tlbli` beyond their privilege check, the
decrementer and time base values, HID0/HID1, external interrupts, machine checks,
little-endian mode, FP estimates of finite nonzero values, imprecise FP exception
modes (only FE0 = FE1 = 1), and FP accesses that fault in translation.
