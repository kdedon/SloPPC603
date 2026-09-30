# Opcode self-test verification

Records for [SELFTEST.md](SELFTEST.md).

## 603e image on the demo SoC

Recorded: `make -C sim test-selftest`, commit 786c2cb, 2026-09-30.

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

## MiSTer build

MISTER
