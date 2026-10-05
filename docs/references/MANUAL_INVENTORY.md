# Manual design inventory, 2026-10-05

Recorded: `make -C sim check-spec`, commit f2de279 plus this record, 2026-10-05.

[SOURCE_RECONCILIATION.md](SOURCE_RECONCILIATION.md) checked the claims our docs
make against the manuals. This inventory goes the other way: it lists what the
manuals define and records whether the design has it. Sources are those in
[SOURCES.md](SOURCES.md): the 603e UM (MPC603EUM/AD 11/97), the PEM (MPCFPE/AD
Rev. 1) and the 602 UM (MPC602UM/AD 11/95, SHA-256 `77c0fc4a…e6b1e3`). Page
numbers are one-based physical PDF pages. Documentation only: nothing was
built or simulated.

## Method

Each chapter was read in `pdftotext -layout` text. Every distinct feature,
signal, register bit, mode, exception condition, instruction form and timing
rule is one row. Status comes from grepping `rtl/`, `tb/`, `sim/Makefile` and
`docs/`, reading targeted lines only:

| Status | Meaning |
|---|---|
| tested | Implemented, and the named target exercises it |
| untested | Implemented; no bench exercises it |
| partial | Part implemented; the row says what is missing |
| missing | Not implemented |
| out of scope | A named doc defers or excludes it |
| n/a | Not meaningful in an FPGA core; the row says why |

"Tested" means a bench drives the behaviour, not that the bench was rerun for
this record. Opcode coverage is summarised by the generated
[ISA matrix](ISA_MATRIX.md) rather than one row per instruction.

## Summary

SUMMARY_PLACEHOLDER

## Likely missed

LIKELY_PLACEHOLDER

CHAPTERS_PLACEHOLDER

## 602 differences (602 UM)

Variant rounds V6–V12 and V14 in [CPU_VARIANTS.md](../CPU_VARIANTS.md#status) own this
area; most rows are tested at module level or on the `ppc602` top.

| Item | Manual | Status | Evidence |
|---|---|---|---|
| Single dispatch, one retire per cycle | 602UM §1.1.1, PDF 39 | tested | Core is single-issue for every variant; `variant-full-decode-4` |
| Four-entry IQ, four GPR renames | 602UM §1.1.1, PDF 39 | partial | `IQ_DEPTH` 6 and `GPR_RENAME_DEPTH` 5 are global (`rtl/ppc_pkg.sv:7-8`); timing-only difference |
| Branch folding, static prediction | 602UM §1.1.1, PDF 39 | tested | Shared with the 603e (ch. 6 rows) |
| SP FPU, 32-bit FPRs, DP emulation trap (0x1600) | 602UM §1.1.1, PDF 39; §4.5.18, PDF 221 | tested | `test-fpu-602`, `test-core-fpu-602`; FPU_602_CONTRACT.md |
| stfd/lfd save-restore rules, SP bit | 602UM §2.1.3, PDF 101 | tested | `test-fpu-602`; FPU_602_CONTRACT.md |
| Imprecise FP modes run precise | 602UM §4.1, PDF 65 | tested | FPU is precise in every mode; FPU_CONTRACT.md |
| Non-IEEE mode | 602UM §1.1.1, PDF 39 | tested | FPSCR[NI] in `test-fpu-602` vectors |
| 4 KiB two-way I and D caches | 602UM §1.1.1, PDF 40 | tested | `variant-icache-602`; `tb_core_602` 64 sets × 2 ways |
| No HID0[ICE]: I-cache always on | 602UM Table 2-7, PDF 89 | tested | `variant-icache-602` (best-effort reading, CPU_VARIANTS.md) |
| 32-entry two-way ITLB/DTLB (16 sets) | 602UM §1.1.1, PDF 40; Fig. 5-9 | tested | `test-tlb-geometry-16` |
| NE bit on IBATs and TLB pages | 602UM §5.1.1.1, PDF 228 | tested | `variant-mmu-602-4`, `tb_micro_tlb_router` at 602 |
| SE bit and esa gating; SEBR/SER | 602UM §5.1.1.2, PDF 228 | tested | `variant-mmu-602-4`; `tb_mmu_602` |
| esa, dsa, ESASRR, MSR[SA] | 602UM §2.3.9.2.2, PDF 150; MSR table, PDF 193 | tested | `variant-exception-602-4` |
| MSR[AP] supervisor-space limit | 602UM §1.1.1, PDF 40 | tested | `variant-mmu-602-4` |
| Protection-only mode, HID0[PO] | 602UM §5.6, PDF 280; Table 2-7, PDF 89 | tested | `variant-mmu-602-4` (module level) |
| HID0[WIMG] defaults in real/PO mode | 602UM Table 2-7, PDF 89 | tested | `variant-mmu-602-4` |
| mfrom | 602UM §2.3, PDF 144 | tested | `variant-icache-602` (`tb/tb_core_602.sv:213`) |
| IBR vector prefix | 602UM Table 2-15, PDF 99-100 | tested | `variant-exception-602-4` |
| Watchdog 0x1500, TCR (WIE, NWE, CRE, L2E) | 602UM §4.5.17, PDF 219; PDF 98 | tested | `variant-watchdog-602`; `tb_special_watchdog` |
| RESETO pin from watchdog | 602UM §7.2.9.6.3, PDF 346 | tested | `test-chip602-pins` |
| IABR IE bit (bit 30), SPR 1010 | 602UM Table 2-16, PDF 101 | untested | `rtl/ppc_core.sv:661` uses bit 30; no 602 IABR bench |
| SMI 0x1400 | 602UM §4.5.16, PDF 218 | untested | Shared exception path tested on the 603e; the 602 bench never asserts SMI |
| HID0[EMCP] masks MCP | 602UM Table 2-7, PDF 88 | tested | Shared with the 603e; `test-core-bat-machine-check` |
| HID0[NHR] | 602UM Table 2-7, PDF 89 | untested | In `HID0_MASK_602` (`rtl/ppc_pkg.sv:607`); no bench reads it after soft reset |
| HID0[SL] out-of-order bus loads | 602UM Table 2-7, PDF 89 | n/a | Stored; the bus never reorders loads, which SL only permits |
| HID0[SBCLK]/[ECLK], CLK_OUT | 602UM Table 2-7, PDF 88; §7.2.11.2, PDF 349 | n/a | Test clock output; held high-Z (CHIP_PACKAGE_602.md) |
| HID0[DPM] | 602UM §9.1, PDF 411 | n/a | Clock gating is invisible to software and bus |
| Doze, nap, sleep, QREQ/QACK | 602UM §9.2, PDF 411-414 | tested | `test-chip602-pins`; POWER_MANAGEMENT.md |
| Multiplexed 64-bit A/D bus, BB | 602UM §7.1.1, PDF 324 | tested | `test-chip602-pins` |
| T32 dynamic 32-bit data mode | 602UM §7.2.7.2, PDF 342 | tested | `test-chip602-pins` |
| PFADDR line-fill broadcast on castout | 602UM §7.2.3.1.3, PDF 328 | tested | `test-chip602-pins` |
| BE0–BE7 byte enables | 602UM §7.2.4.3, PDF 331 | tested | `test-chip602-pins` byte/half stores |
| Only kill broadcast as address-only | 602UM Table 8-3, PDF 367-368 | untested | `rtl/ppc602_bus.sv` completes others locally; no bench drives a kill snoop |
| Reservation snooped regardless of GBL | 602UM §8.4.2, PDF 378 | partial | Shared core snooper; not exercised on the 602 top |
| Injected snoops between burst-read beats | 602UM §8.4.2, PDF 378; §8.5.4.7, PDF 406 | missing | `rtl/ppc602_bus.sv` has no injected-snoop window; an injected TS would be taken as an ordinary snoop |
| 602 may not assert ARTRY before third cycle | 602UM §8.3.2.3, PDF 374 | tested | CHIP_PACKAGE_602.md; `test-chip602-pins` retry |
| Core:bus 2:1 and 3:1 | 602UM §1.1.1, PDF 41; §8.1.3, PDF 357 | missing | CHIP_PACKAGE_602.md "Not modelled"; core runs at SYSCLK |
| PLL_CFG strap | 602UM §7.2.11.3, PDF 350 | tested | Non-build code checkstops; `test-chip602-pins` |
| TBEN | 602UM §7.2.9.9, PDF 347 | untested | Bench ties `tben_i` high (`tb/tb_chip602_pins.sv:44`) |
| CKSTP_IN / CKSTP_OUT | 602UM §7.2.9.4-5, PDF 344-345 | untested | Ports exist; no 602 bench toggles CKSTP_IN |
| JTAG/COP | 602UM §7.2.10, PDF 347 | n/a | Boundary scan belongs to the FPGA; COP debug is absent (CHIP_PACKAGE_602.md) |
| 602 multiply timing | 602UM Table 6-2, PDF 311-313 | tested | `variant-multiply-timing-4` |
