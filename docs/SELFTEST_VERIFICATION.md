# Opcode self-test verification

Records for [SELFTEST.md](SELFTEST.md).

## 603e image on the demo SoC

Recorded: `make -C sim test-selftest`, commit 9dce465, 2026-09-30.

Pass. The image prints `selftest 603e PVR 00070101: 1047 cases, 1047 pass, 0
fail` and exits 0; the bench reports 56,189,226 cycles and 15,117,283 retirements,
including 14 pages drawn at 320 × 240.

| Group | Cases |
|---|---:|
| INT | 456 |
| ROT | 194 |
| CMP/BR | 133 |
| LD/ST | 108 |
| SPR | 31 |
| EXC | 68 |
| CACHE | 16 |
| FP | 41 |

`check_enc.py` matched all 1226 instruction words of the 603e cases, and all 1223 of
the 602 cases, against the cross assembler.

This establishes that the processor in the demo SoC agrees with the model in
`gen.py` on every case: results, CR/XER/LR/CTR, memory, and for the exception cases
the vector, SRR0, SRR1, entry MSR, DAR and DSISR. It does not establish agreement
with DingusPPC (not run: the reference firmware runner has no model of the demo
SoC's registers and framebuffer), the 602 image's behaviour (no demo SoC for the 602
package), or anything listed under [Not covered](SELFTEST.md#not-covered). The
interactive paging on the MiSTer input register is not exercised in simulation (the
bench ties `INPUT` to 0).

### Triage of the first runs

Every disagreement in the first RTL runs was on the model or test side; none needed
an RTL change:

| Symptom | Cause | Resolution |
|---|---|---|
| User-mode cases took ITLB misses at their first instruction | The demo start-up BATs are supervisor-only (Vp = 0) | `selftest.c` sets Vp on IBAT0/DBAT0 |
| Taken forward `bc` expected ISI | Model treated the case-relative target as absolute | Model fix |
| Hang at `eciwx` with EAR[E] = 0 after the EAR case | The EAR case left E = 1; the demo SoC's 60x target takes the `eciwx` tenure (TT 11100, TT3 = 0) as address-only, so the data tenure never ends | The case clears E again; a demo SoC limitation, not a processor fault |

No processor bug was found. One reading was settled from the manual before the
case ran: a misaligned `lmw`/`stmw` puts EA + 4 in DAR (UM 4.5.6, the note after
Table 4-14) where Table 4-13 says EA; the model follows the note and the RTL agrees.

Recorded: `make -C sim test-selftest`, commit 6afc6ea, 2026-09-30.

Pass after the FP cases were added: `selftest 603e PVR 00070101 no FPU: 1047 cases,
1047 pass, 0 fail`, 62,632,886 cycles, 16,386,305 retirements, 14 pages. The 171 cases
that need the FPU are skipped and the FP group is the 41 FP-unavailable cases, as
before.

## 603e image on the demo SoC with the FPU

Recorded: `make -C sim test-selftest-fpu`, commit 31f7d4f, 2026-09-30.

Pass, on the first run. The same `selftest.hex` on the SoC built with `ENABLE_FPU`
prints `selftest 603e PVR 00070101 FPU: 1218 cases, 1218 pass, 0 fail` and exits 0;
the bench reports 73,605,507 cycles, 19,088,576 retirements and 17 pages drawn.
Groups as above, except FP 212: the 41 FP-unavailable cases (MSR[FP] clear) and the
171 cases with MSR[FP] set ([SELFTEST.md](SELFTEST.md#floating-point)). Every case
compares all 32 FPRs and the FPSCR as well. `check_enc.py` matched all 1406
instruction words of the 603e cases and all 1223 of the 602 cases.

This establishes that the serialized FPU lane in the demo SoC agrees with the FPU
reference model and `gen.py`'s own FP model on those cases, including FPSCR updates,
CR1 and CR fields, enabled program exceptions (SRR0, SRR1 bit 11) and FP alignment
DAR/DSISR. It does not establish the estimates of finite values, imprecise exception
modes, FP accesses that fault in translation, or timing.

## MiSTer build

MISTER
