# Source reconciliation, 2026-10-05

Recorded: `make -C sim check-spec`, commit b52eb4f plus this record, 2026-10-05.

A fresh check of the distilled contracts against the manuals named in
[SOURCES.md](SOURCES.md): the 603e UM (MPC603EUM/AD 11/97), the PEM (MPCFPE/AD
Rev. 1) and the 602 UM (MPC602UM/AD 11/95, SHA-256 `77c0fc4a…e6b1e3`). Page
numbers are one-based physical PDF pages, as in SOURCES.md. Documentation only:
no RTL changed, no simulation ran. `check-spec` passes and validates the
regenerated ISA matrix.

## Method

Manual text was extracted with `pdftotext -layout` and every cited page read
in that text. Each claim that cites a table, section or figure, or states a
manual value, was classed as *match*, *wrong citation*, *wrong value* or
*missing coverage* (a manual statement, often a self-contradiction, the doc did
not record). RTL was spot-checked for the same facts by grep; contradictions
are logged in [AUDIT.md](../AUDIT.md), not fixed.

Mechanical checks:

- All 190 rows of `sim/spec/timing.json` against UM Tables 6-1..6-6 (PDF
  269-276): primary and extended opcode, mnemonic and cycle string. 190 match.
- All 335 `sim/spec/isa.json` decode entries: the primary/extended opcode in
  each mask/value against its bound timing row. 335 match; every Table 6-x row
  binds to at least one decode entry.
- UM Table B-1 (`fsqrt`, `fsqrts`, `tlbia`) and Table B-3 (53 FP rows plus
  `tlbia`, PDF 409-410) against `appendix_b_exclusions`. Match.

## Results

| Area | Docs | Claims | Match | Wrong citation | Wrong value | Missing coverage |
|---|---|---:|---:|---:|---:|---:|
| Timing and ISA tables | TIMING_SPEC, ISA_MATRIX, timing/isa JSON | 537 | 536 | 0 | 0 | 1 |
| Source anchors | SOURCES (vectors, reset, divide, PVR, B-1, App. C) | 10 | 10 | 0 | 0 | 0 |
| Exceptions and interrupts | 15 contracts | 62 | 55 | 2 | 1 | 4 |
| MMU | 19 contracts | 75 | 69 | 3 | 0 | 3 |
| Cache, LSU, 60x bus | 14 contracts, bus JSON | 74 | 64 | 6 | 1 | 3 |
| FPU, dispatch, variants, SPRs | 13 contracts | 78 | 71 | 2 | 2 | 3 |
| **Total** | | **836** | **805** | **13** | **4** | **14** |

The FP, multiply and divide latencies, dispatch/completion limits (IQ 6, CQ 5,
5 GPR / 4 FPR renames), exception vectors, SRR1/DSISR masks, MSR and HID0 bit
positions, SPR numbers, BAT/segment/SDR1/PTE/miss-register formats, TLB
geometry, TT/TSIZ/TBST encodings and cache geometries all match.

Doc fixes applied: the wrong citations, the wrong values (snoop class of a
burst read, alignment DAR/DSISR reset, PID6 SRU dispatch, stale PVR text) and
notes for every missing-coverage item except where marked open below. Stale
statements that predated the PEM and 602 UM were updated in SOURCES.md,
CR_XER_CONTRACT.md and the ISA open-gap list. The UM Table A-6 rotate-opcode
conflict is closed: PEM Tables A-1/A-2 (PDF 688, 692) agree with 20/21/23 and
PEM Table A-3 (PDF 701) repeats the same 22/20/21 misprint.

Manual self-contradictions now recorded where the docs rely on one side:
Table 4-16 and Table 5-10 against Table 4-4 on TLB-miss SRR1 bit 15; Tables
4-3 and 4-10 on machine-check SRR1; §1.3.1.10.2/§5.5.2.1.1 against §2.1.2.2 on
DMISS/IMISS writability; §3.5 against Table 5-3 on IBAT G; PDF 45 against PDF
48 on PID6 SRU add/compare and single-cycle store; PEM §2.3.14.1 against the
TBEN-gates-TB-only profile.

## RTL contradictions

| ID | Where | Manual | Expected |
|---|---|---|---|
| AUD-75 | `rtl/ppc_exception_state.sv:349` | UM §4.5.16, Tables 4-7, 4-19 (PDF 176, 195) | SMI taken whenever EE=1, clearing TGPR. Fixed |
| AUD-76 | `rtl/ppc_pkg.sv:610` | UM §1.3.1.2 (PDF 58) | PID7v PVR revision ≥ 0x0200 |
| AUD-77 | `rtl/ppc_dcache.sv:361` | UM Tables 3-6, 7-2 (PDF 146, 287) | Burst read snoops flush (E → I, M → push, I). Fixed |
| AUD-78 | `rtl/ppc_bus60x_cache_master.sv:243`, `rtl/ppc_dcache.sv` | UM Tables 7-6, 8-8; §8.1.1 (PDF 290, 328, 312) | TC=01 on touch loads; fill before castout |
| AUD-79 | `rtl/ppc_bat_translate.sv:146` | UM §3.5 vs Table 5-3 (PDF 136, 211) | Decide whether IBAT G is honoured. Decided: ignored (§3.5) |
| AUD-87 | `rtl/ppc_decode.sv:65` | UM Table B-3, footnote 7, §4.5.8 (PDF 409, 368, 189) | EC603e `fsqrt`/`fsqrts` take FP unavailable. Fixed |

## ISA metadata

Recorded: `make -C sim check-spec`, commit 663c413 plus this record, 2026-10-05.

All 226 Table A-1 rows (UM PDF 361-368) now carry metadata in
`sim/spec/isa_sources.json`, validated by `sim/tools/isa_generate.py` and
rendered in [ISA_MATRIX.md](ISA_MATRIX.md#appendix-a-row-metadata). Each row gives
its Table A-1 fields, primary and extended opcode, Table A-46 form (PDF 399-405),
OE/Rc/AA/LK modifiers and concrete forms, privilege from the footnotes (PDF 368),
the decode entries its opcode key matches, their timing rows and validation
markers, bench references, and a legality status per variant with a cited rule.
The 124 rows that held only a primary opcode are closed: 84 bind to decode
entries, 40 (Tables B-1 and B-2) are undecoded and illegal on every variant.

Variant legality: PID6/PID7v from Tables A-1, B-1, B-2; EC603e FP rows take
floating-point unavailable (Table B-3, PDF 409-410); the 603 follows the 603e
(Appendix C, PDF 413) except the HID1 moves; the 602 from its Tables A-1, B-1,
B-2 (602 UM PDF 415-422, 461-462), §2.3.5.4 for eciwx/ecowx (PDF 137), string
and double-precision emulation traps and tag-checked SP forms (PDF 116-129), and
no EAR (PDF 82). The 602 Table A-1 matches the 603e's row for row, adding only
`dsa`, `esa` and `mfrom`.

Corrections from the cross-check: 51 FP decode entries had EC603e `legal`
(now `fp_unavailable`); `mfear`/`mtear` had 602 `legal` and `mfhid1`/`mthid1`
had 603 `legal` (now `illegal`, matching the RTL); `mtfsf` is XFL-form, not X.

The validator also checks that no decode entry falls outside every row, that
each decoded row covers its concrete forms, and that bound entries agree with
the row on form, privilege and legality.

Remaining gaps:

- 602-only `dsa`, `esa`, `mfrom` and the 602-only SPRs have no Appendix A row.
- EC603e `tlbia` stays pending editorial reconciliation (Table B-3, PDF 410).
- EC603e `fsqrt`/`fsqrts`: decode disagrees with the manual (AUD-87).
- Table A-1 footnote 7 marks `fcfid`, `fctid`, `fctidz` as FP, but Table B-3
  omits them; they are recorded illegal on the EC603e under Table B-2.
- Bench references are grep-derived; 67 SPR, segment, TLB and timer entries
  carry no validation marker.
- Table A-1 shading is not machine-readable; implemented status follows
  Tables B-1 and B-2.

## Not checked

- Test benches; only RTL was compared with the manual.
- `BUS_SPEC.md` cycle tables against figure geometry, `bus_signals.json`
  per-signal fields, DBWO ordering (§8.10), Table 8-5/8-7 lane anomalies.
- Chapter 6 figure cell transcription (TIMING_SPEC worked schedules).
- PEM per-instruction pages (chapter 8) beyond the rotate opcodes and the
  little-endian rules; FPU_CONTRACT PEM table page numbers.
- 602 vectors, MMU modes and bus signal timing in CHIP_PACKAGE_602.md and
  CPU_VARIANTS.md; 602HW pinout.
- RTL hash/PTEG computation; DSISR[6] for cache-op DSI; Table 5-4 W=1
  `lwarx`/`stwcx.` DSI.
- About 50 feature documents without manual citations (verification records,
  firmware records, integration protocols).
- Stale non-manual text noted but left: CACHE_CONTROL.md and
  ICACHE_CONTROL.md describe the scalar profile ("No data cache", "HID0 is not
  decoded"); SUPERVISOR_INTEGRATION.md:172 says machine checks need later work.
