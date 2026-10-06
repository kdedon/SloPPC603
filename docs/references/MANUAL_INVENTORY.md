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

| Chapter | tested | untested | partial | missing | out of scope | n/a | Rows |
|---|---:|---:|---:|---:|---:|---:|---:|
| Chapter 1 | 13 | 0 | 7 | 1 | 0 | 3 | 24 |
| Chapter 2 | 62 | 1 | 6 | 0 | 0 | 5 | 74 |
| Chapter 3 | 43 | 2 | 8 | 1 | 0 | 1 | 55 |
| Chapter 4 | 58 | 3 | 4 | 1 | 1 | 4 | 71 |
| Chapter 5 | 33 | 1 | 0 | 0 | 1 | 1 | 36 |
| Chapter 6 | 15 | 2 | 13 | 0 | 0 | 1 | 31 |
| Chapter 7 | 42 | 3 | 7 | 3 | 0 | 3 | 58 |
| Chapter 8 | 28 | 0 | 5 | 4 | 0 | 2 | 39 |
| Chapter 9 | 9 | 0 | 0 | 0 | 0 | 3 | 12 |
| Appendices A and B | 9 | 0 | 2 | 0 | 0 | 0 | 11 |
| Appendix C | 14 | 1 | 2 | 1 | 0 | 4 | 22 |
| 602 differences | 28 | 6 | 2 | 2 | 0 | 4 | 42 |
| **Total** | 354 | 19 | 56 | 13 | 2 | 31 | 475 |

## Likely missed

Missing and partial rows, ranked by how visible they are to software or to a
60x system. Each has an [AUDIT.md](../AUDIT.md) row.

1. ~~**Burst-read snoop treated as clean** (AUD-77)~~. Fixed: TBST selects
   the flush class.
2. **32-bit data bus and reduced-pinout modes** (AUD-80). UM §8.6.1, §8.6.3,
   PDF 346-349. Their straps checkstop; boards wired that way cannot boot.
3. ~~**HID0[IFEM] partial** (AUD-81)~~. Fixed: line fills and single-beat
   fetches assert GBL for M=1.
4. ~~**SMI refused while MSR[TGPR]=1** (AUD-75)~~. Fixed.
5. ~~**IBAT G=1 raises ISI** (AUD-79)~~. Decided for §3.5: IBAT G ignored.
6. ~~**SRESET leaves the I-cache enabled** (AUD-83)~~. Fixed: SRESET clears HID0[ICE].
7. **602 injected snoops** (AUD-82). 602UM §8.4.2, PDF 378. A 602 system that
   injects snoops during a burst read gets a push the protocol forbids.
8. ~~**PVR revision below PID7v level** (AUD-76)~~. Fixed: 0x00070200.
9. **Touch-load TC and castout order** (AUD-78). UM Table 7-6, PDF 290;
   §8.1.1, PDF 312. Visible to L2 controllers and bus monitors only.
10. **Exception priority untested beyond pairs** (AUD-84). UM Table 4-2, PDF
    165-166. Simultaneous fault and asynchronous events may vector wrongly.
11. ~~**DBDIS and 603e CSE unchecked** (AUD-85); **603 checkstop sources**
    (AUD-86)~~. Fixed; the 603's fetch-TEA refetch tenure is not issued.

Lower: core:bus ratios other than 1:1 (D07 in [SOURCES.md](SOURCES.md); 602
2:1 and 3:1 per [CHIP_PACKAGE_602.md](../CHIP_PACKAGE_602.md)); COP, pipeline
tracking (HID0[EICE]) and CLK_OUT; the no-DRTRY early data forward; one-level
address pipelining of the processor's own tenures; the chapter 6 cycle rules
(dual dispatch, SRU pairing, IQ/CQ/rename occupancy, LSU 2:1) that are opt-in
or uncontracted; the touch-load buffer and I-cache critical double-word
forwarding. These affect performance or debug, not architected results.

Not swept line by line: UM PDF 154-158 (MEI tables), 160-168 and 172-175
(exception classes and priority prose), 197-217 and 227-246 (MMU detail),
247-256 and 263-268 (timing prose), 280-284 and 289-303 (per-signal timing),
340-346 (bus figures) and 352-354 (§8.10 DBWO examples). Those rows rest on
section headings and the repo's own transcriptions; chapter 1 likewise. The
PEM was read only where the UM defers to it.

## Chapter 1: Overview (UM PDF 41-78)

| Item | Manual | Status | Evidence |
|---|---|---|---|
| 32-bit PowerPC, BE integer core, precise completion | UM §1.1, PDF 41 | tested | full regression; test-reference, test-reference-603 |
| Superscalar: up to 3 instr/clk issue+retire, out-of-order exec | UM §1.1, PDF 41-42 | partial | dual dispatch only behind `PPC_DISPATCH_WIDTH=2` (test-core-dual, test-dispatch-rules); chip default 1; no 3-wide retire |
| 6-entry IQ, 2-wide dispatch | UM §1.1.3.1, PDF 49 | partial | `rtl/ppc_iq.sv`; dual-dispatch opt-in only (as above) |
| BPU: static prediction (y bit), branch folding, BTIC-free fetch | UM §1.1.3.2, PDF 49-50 | partial | FULL_CPU_COMPLETION_AUDIT row "Branch prediction and folding" 70%; test-core-branch-fold; CHIP_PACKAGE.md:216 "no branch prediction" in fetch |
| IU (single-cycle ALU, iterative mul/div) | UM §1.1.4.1, PDF 50 | tested | test-core-*, test-divider-timing, test-multiply-timing |
| FPU (pipelined, single-precision madd 1/clk) | UM §1.1.4.2, PDF 50 | partial | implemented, off at chip top (`ENABLE_FPU=0`); test-chip-fpu, test-core-fpu, test-fpu-all; timing per FPU_PIPELINE_DESIGN |
| LSU, SRU, completion unit (5-entry) | UM §1.1.4.3-5, PDF 51 | tested | test-core-lsu-timing, test-completion-ring |
| MMUs: 64-entry 2-way I/D TLBs, 4 IBAT + 4 DBAT, software TLB reload | UM §1.1.5.1, PDF 52 | tested | test-core-tlb-miss, test-core-bat, test-tlb-geometry-16 (outside scope, see MMU chapter sweep) |
| 16 KB 4-way I- and D-caches, 32-byte lines | UM §1.1.5.2, PDF 53 | tested | test-icache, test-dcache, test-chip-icache-real |
| 60x bus: 32-bit addr, 64-bit data, split tenures, 1-level pipelining | UM §1.1.6, PDF 54 | tested | test-bus60x*, test-chip-pins |
| 32-bit data bus mode (TLBISYNC strap) | UM §1.1.6, PDF 54; §1.3.7 PDF 75 | missing | CHIP_PACKAGE.md:129 rejects strap; DATA_CACHE.md:205 "not modelled" |
| CSE1 replaces XATS (PID7v) | UM §1.1.2.1.1, PDF 47 | tested | `rtl/ppc603e.sv:79` cse_o; CHIP_PACKAGE.md:63-68; test-chip-pins |
| Half-clock bus multipliers (2.5:1, 3.5:1 ...) | UM §1.1.2.1.2, PDF 47 | tested | CPU_VARIANTS.md:317 ratios 2-6 in halves; test-chip-ratios, test-core-bat-cached-bus60x-ratios |
| HID1 PLL_CFG readback | UM §1.1.2.2.2, PDF 48 | tested | `ppc_pkg.sv:619` hid1_rmask; tb_variant_config.sv, test-core-full-decode |
| Power management: DOZE/NAP/SLEEP/DPM, QREQ/QACK | UM §1.1.7.1, PDF 55 | partial | test-chip-power; DPM stored without effect (POWER_MANAGEMENT.md:31) |
| Time base / DEC, one tick per 4 bus clocks, TBEN | UM §1.1.7.2, PDF 55 | tested | `rtl/ppc603e.sv:267`; test-timer, test-core-timer-events, test-core-timer-registers |
| JTAG / COP test interface | UM §1.1.7.3, PDF 56 | n/a | CHIP_PACKAGE.md:113,231 absent; no FPGA debug use |
| Clock multiplier / PLL | UM §1.1.7.4, PDF 56 | n/a | FPGA PLL; PLL_CFG only selects ratio (CHIP_PACKAGE.md) |
| PVR value (PID7v level 0x0200+) | UM §1.3.1.1, PDF 58 | yes | `cpu_cfg().pvr` = 0x00070200 (`variant-config-0`) |
| Run_N counter (COP) | UM §1.3.1.3, PDF 59 | n/a | no COP (CPU_VARIANTS.md:224) |
| Implementation exception vectors 0x1000/0x1100/0x1200/0x1300/0x1400 | UM §1.3.4.2, PDF 69-71 | tested | test-core-tlb-miss, test-core-machine-check-trace (IABR), test-chip-pins (SMI) |
| Real-mode WIMG defaults | UM §1.3.5.2, PDF 72; §3.5 PDF 136 | tested | `rtl/ppc_bat_translate.sv:126`: fetch 0001, data 0011 (§3.5 says 0011 for both; differs only in M, which fetch ignores); test-core-bat |
| Instruction timing model | UM §1.3.6, PDF 73 | partial | test-core-lsu-timing, test-multiply-timing; PERFORMANCE_TARGET.md gap list |
| Signal set / configuration (DRTRY, no-DRTRY, fast L2 modes) | UM §1.3.7.2-3, PDF 76-78 | tested | CHIP_PACKAGE.md:125-134; test-chip-pins |

## Chapter 2: Programming model (UM PDF 79-126)

| Item | Manual | Status | Evidence |
|---|---|---|---|
| GPR 32x32, CR, XER, LR, CTR | UM §2.1.1, PDF 79-82 | tested | test-core-xer, test-core-crtransfer, many core benches |
| FPR/FPSCR | UM §2.1.1, PDF 80 | tested | test-fpu-all, test-core-fpu (FPU off at chip top) |
| MSR bits (POW, TGPR, ILE, EE, PR, FP, ME, FE0/1, SE, BE, IP, IR, DR, RI, LE) | UM §2.1.1, PDF 82-83 | tested | EXCEPTION_STATE.md:81; test-exception-state, test-core-le, test-core-machine-check-trace |
| SRs 0-15, mtsr/mfsr/mtsrin/mfsrin | UM §2.1.1, PDF 83 | tested | test-segment-registers, test-core-segment-csr |
| SDR1, DAR, DSISR, SRR0/1, SPRG0-3 | UM §2.1.1, PDF 84 | tested | test-core-sdr1, test-core-sprg, test-core-data-fault |
| BAT SPRs 528-543 | UM §2.1.1, PDF 84 | tested | test-core-runtime-bat |
| TBL/TBU (mftb 268/269, mtspr 284/285), mftb bit-25 ignored | UM §2.1.1 PDF 84; §2.3.5.1 PDF 117 | tested | ISA_MATRIX.md:9; test-timer-decode, test-core-timer-registers |
| DEC, decrement per 4 bus clocks | UM §2.1.1, PDF 85 | tested | TIMER_CONTRACT.md:17; test-core-timer-events |
| EAR, only bits 28-31 + E | UM §2.1.1, PDF 85 | tested | `ppc_special.sv:453-476`; test-chip-ecxwx |
| DABR absent on 603e (SPR 1013 illegal) | UM Fig 2-1, PDF 80 | tested | tb_decode_sweep.sv sweeps all SPRs; test-decode-sweep |
| Implementation SPRs supervisor-only | UM §2.1.2, PDF 85 | tested | test-decode-sweep, test-core-full-decode |
| HID0[EMCP] machine-check pin enable | UM Tbl 2-2, PDF 86 | tested | `ppc_pkg.sv:513`; test-core-bat-machine-check, test-chip-pins |
| HID0[EBA]/[EBD] address/data parity checking | UM Tbl 2-2, PDF 86 | tested | pin_status address/data_parity_enable; test-chip-pins (APE/DPE) |
| HID0[SBCLK]/[ECLK]/[EICE] test-clock/ICE outputs | UM Tbl 2-2, PDF 86 | n/a | stored only (mask 0xbff9fc99); test pins not on FPGA |
| HID0[PAR] disable ARTRY/SHD precharge | UM Tbl 2-2, PDF 86 | n/a | stored only; electrical precharge has no FPGA meaning |
| HID0[DOZE]/[NAP]/[SLEEP] | UM Tbl 2-2, PDF 86 | tested | `ppc_pkg.sv:866-868`; test-chip-power |
| HID0[DPM] dynamic power management | UM Tbl 2-2, PDF 86 | partial | stored, no effect (POWER_MANAGEMENT.md:31); invisible to software |
| HID0[RISEG]/[NHR] reserved/test | UM Tbl 2-2, PDF 86 | n/a | stored read/write only |
| HID0[ICE] I-cache enable (single-beat when off) | UM Tbl 2-2 PDF 86; §3.1.3.2 PDF 130 | tested | test-chip-icache-real (ICE=0/1), test-chip-dcache-coherence |
| HID0[DCE] D-cache enable | UM Tbl 2-2 PDF 86; §3.2.3.2 PDF 132 | tested | tb_dcache.sv, tb_core_dcache.sv; test-dcache, test-core-dcache |
| HID0[ILOCK] | UM Tbl 2-2 PDF 86; §3.1.3.3 PDF 130 | tested | `ppc_icache_managed.sv:27`; tb_chip_pins.sv:10-55 (single beat + CI) |
| HID0[DLOCK] | UM Tbl 2-2 PDF 86; §3.2.3.3 PDF 132 | tested | DATA_CACHE.md:83,90; test-dcache, test-biu-dcache-snoop |
| HID0[ICFI] flash invalidate | UM Tbl 2-2 PDF 86; §3.1.3.1 PDF 130 | tested | test-chip-dcache-coherence, test-core-full-decode |
| HID0[DCFI] flash invalidate | UM Tbl 2-2 PDF 86; §3.2.3.1 PDF 132 | tested | DATA_CACHE.md:70; test-dcache, test-chip-dcache-coherence |
| HID0[IFEM] instruction fetch M/GBL (PID7v) | UM Tbl 2-2, PDF 86 | yes | Burst and CI single-beat fetches drive GBL from M when set (`test-chip-pins` `case_ifem`) |
| HID0[FBIOB] force branch indirect on bus | UM Tbl 2-2, PDF 86 | partial | stored only (`ppc_pkg.sv:600`); no fetch behaviour |
| HID0[ABE] address broadcast for dcbf/dcbi/dcbst (PID7v) | UM Tbl 2-2 PDF 86; §3.2.3.4 PDF 133 | tested | `ppc_special.sv:1514`; DATA_CACHE.md:104; test-dcache, test-core-full-decode; dcbi gated by M (deviation, DATA_CACHE.md:202) |
| HID0[NOOPTI] touch no-op | UM Tbl 2-2 PDF 86; §3.2.4 PDF 133 | tested | DATA_CACHE.md:98; test-dcache, test-core-dcache |
| HID1 PC0-PC3 read-only | UM Tbl 2-3, PDF 87 | tested | `ppc_pkg.sv:589,619`; test-core-full-decode |
| DMISS/IMISS loaded on TLB miss, BE address under LE | UM §2.1.2.2, PDF 87 | tested | CPU_TLB_MISS.md:37-38,100; test-core-tlb-miss, test-core-le |
| DMISS/IMISS software-writable | UM §2.1.2.2, PDF 87 | partial | read-only by decision (manual conflict, CPU_TLB_MISS.md:66-73); `mtdmiss`/`mtimiss` `manual_conflict_rejected` in ISA_MATRIX.md:266-267 |
| DCMP/ICMP auto-built, R/W | UM §2.1.2.3, PDF 87-88 | tested | test-core-tlb-miss, test-miss-derive |
| HASH1/HASH2 read-only, from SDR1 | UM §2.1.2.4, PDF 88 | tested | test-miss-derive, test-core-sdr1 |
| RPA, tlbld/tlbli merge (R ignored) | UM §2.1.2.5, PDF 89 | tested | test-core-tlb-load, test-tlb-load-decode |
| IABR (CEA, IE bit 30), break before completion | UM §2.1.2.6, PDF 89-90 | tested | `ppc_special.sv:1089,1749`; test-core-machine-check-trace |
| Run_N (PID7v, COP) | UM §2.1.2.7, PDF 90 | n/a | no COP port |
| FP execution models (IEEE, single/double rules) | UM §2.2.1, PDF 90-91 | tested | test-fpu-testfloat, test-fpu-arith |
| Data organisation, operand sizes | UM §2.2.2, PDF 91 | tested | test-core-memory-edges |
| Misaligned integer scalars split in hardware | UM §2.2.3, PDF 92 | tested | LOAD_STORE_EXTENSIONS.md:71; test-core-lsu-extensions, test-core-alignment |
| Misaligned page-crossing scalar → alignment exception | UM §2.2.3 PDF 92; §4.5.6.1 | tested | LOAD_STORE_EXTENSIONS.md:71; test-core-lsu-extensions |
| FP load/store not word-aligned → alignment exception | UM §2.2.3, PDF 92 | tested | LITTLE_ENDIAN.md:68; test-core-fpu, test-core-le |
| FP double at word-aligned EA split (extra cycle) | UM §2.2.3, PDF 92 | tested | LITTLE_ENDIAN.md:67; test-core-fpu |
| Instruction classes: defined/illegal/reserved → program exception | UM §2.3.1, PDF 94-96 | tested | FULL_DECODE.md:31; test-core-full-decode, test-decode-sweep |
| Invalid forms (lmw rA in range, store-update rA=0, load-update rA=rD, CR-logical/branch LK forms) | UM PDF 108,110,115 | tested | LOAD_STORE_EXTENSIONS.md:30; FULL_DECODE.md:41; test-core-full-decode (program, SRR1[12]) |
| EA calculation modes (D, X, update, rA-or-0) | UM §2.3.2.3, PDF 97 | tested | test-core-lsu-update, test-lsu-update-edges |
| Context / execution synchronisation | UM §2.3.2.4, PDF 97-98 | tested | SERIALIZATION_INTEGRATION.md; test-core-serialization |
| Integer arithmetic/compare/logical/rotate/shift | UM §2.3.4.1, PDF 99-103 | tested | ISA_MATRIX (168 default forms); test-core-add-flags ... test-core-shifts |
| FP arithmetic, madd, round/convert, compare, FPSCR, move | UM §2.3.4.2, PDF 103-106 | tested | test-fpu-all, test-core-fpu (fsqrt illegal, see App B) |
| Integer load/store incl. update | UM §2.3.4.3.3-4, PDF 107-109 | tested | test-core-lsu-update, test-reference-lsu |
| Byte-reverse lhbrx/lwbrx/sthbrx/stwbrx | UM §2.3.4.3.5, PDF 109 | tested | tb_core_lsu_extensions.sv; test-core-lsu-extensions |
| lmw/stmw, restart after DSI on second page | UM §2.3.4.3.6, PDF 110 | tested | LOAD_STORE_EXTENSIONS.md:85-92; test-core-lsu-extensions |
| lswi/lswx/stswi/stswx, rA/rB in range valid | UM §2.3.4.3.7, PDF 111 | tested | LOAD_STORE_EXTENSIONS.md:33; test-core-lsu-extensions |
| Multiple/string in LE → alignment exception | UM PDF 110-111 | tested | LITTLE_ENDIAN.md:73; test-core-le |
| Multiple/string cycle timing | UM §2.3.4.3.6-7, PDF 110-111 | partial | LOAD_STORE_EXTENSIONS.md:111 each micro-op serialized, not 603e LSU timing |
| FP load/store (single/double, update, stfiwx) | UM §2.3.4.3.8-10, PDF 112 | tested | test-core-fpu, test-core-fpu-split |
| Branches, CR logical, mcrf | UM §2.3.4.4, PDF 113-115 | tested | test-core-branch-recovery, test-core-crlogical |
| tw/twi trap | UM §2.3.4.5, PDF 115 | tested | ISA_MATRIX.md:11 full decode; test-core-full-decode |
| mtcrf, mcrxr, mfcr | UM §2.3.4.6.1, PDF 116 | tested | test-core-crtransfer, test-crtransfer-edges |
| sync (waits for all bus activity, not broadcast) | UM §2.3.4.7, PDF 116 | tested | test-core-serialization, test-core-bat-cached-bus60x-cacheops |
| lwarx/stwcx.: one reservation, store regardless of address match | UM §2.3.4.7, PDF 116-117 | tested | LOAD_STORE_EXTENSIONS.md:94-105; test-core-lsu-extensions |
| Reservation 32-byte granule, lost on another master's write (snoop) | UM §2.3.4.7, PDF 117; PEM §4.2.6 | tested | `ppc_dcache.sv:396-401`; test-chip-mp, test-dcache; RWITM also cancels (legal, DATA_CACHE.md:203) |
| Reservation snoop without D-cache (scalar tops) | UM §2.3.4.7, PDF 117 | partial | `ppc_special.sv:345` "only stwcx. clears it"; matters only for non-cached tops in MP |
| lwarx/stwcx. misaligned → alignment; W=1 no DSI | UM PDF 117 | tested | LOAD_STORE_EXTENSIONS.md:105; test-core-lsu-extensions |
| RSRV pin follows reservation | UM §2.3.4.7, PDF 117; §7.2.9.7.3, PDF 303 | tested | `rtl/ppc603e.sv:458-460`; tb_chip_pins.sv |
| isync discards prefetch; eieio no-op | UM §2.3.5.2, PDF 118 | tested | test-core-serialization, test-serialization-decode |
| User cache ops dcbt/dcbtst/dcbz/dcbst/dcbf/icbi | UM §2.3.5.3, PDF 119 | tested | see Ch 3 table |
| eciwx/ecowx: EAR[E]=0 → DSI, RID on TBST/TSIZ, misaligned → alignment | UM §2.3.5.4, PDF 120 | tested | `ppc_pkg.sv:168`; CPU_VARIANTS.md:190; test-chip-ecxwx |
| eciwx/ecowx with MSR[DR]=0 "programming error" | UM §2.3.5.4, PDF 120 | untested | boundedly undefined; no bench targets DR=0 case (not checked further) |
| sc, rfi | UM §2.3.6.1, PDF 120 | tested | test-core-supervisor, test-exception-state |
| mtmsr/mfmsr, mtspr/mfspr privilege | UM §2.3.6.2, PDF 121-122 | tested | test-supervisor-decode, test-core-supervisor |
| dcbi supervisor-only | UM §2.3.6.3.1, PDF 122 | tested | CACHE_CONTROL.md:24,36; test-core-cache-control |
| tlbie, tlbsync | UM §2.3.6.3.3, PDF 123 | tested | test-core-tlbie, test-tlbie-decode |
| tlbld/tlbli (implementation-specific) | UM §2.3.8, PDF 124 | tested | test-core-tlb-load |
| Simplified mnemonics | UM §2.3.7, PDF 124 | n/a | assembler feature only |

## Chapter 3: Instruction and data cache operation (UM PDF 127-158)

| Item | Manual | Status | Evidence |
|---|---|---|---|
| I-cache 16 KB, 4-way, 128 sets, PA tag, strict LRU | UM §3.1.1, PDF 129 | tested | ICACHE.md:26-59; test-icache, test-icache-bus60x |
| I-fill 4x64 critical-DW first | UM §3.1.2, PDF 130 | tested | `ppc_bus60x_line_read.sv:111,236`; test-bus60x-line-read |
| I-fill: forward critical DW to IQ, sequential fetch during fill | UM §3.1.2, PDF 130 | partial | ICACHE.md:126-130 waits for full line; hits under refill open (performance only) |
| No I-cache snooping | UM §3.1.2, PDF 130 | tested | by design; test-chip-icache-real |
| ICE/ILOCK require preceding isync | UM §3.1.3.2-3, PDF 130 | n/a | software rule; mtspr HID0 is serialized (test-core-serialization) |
| I/D caches invalidated on hard reset, not soft reset | UM §3.1.3.1, §3.2.3.1, PDF 130/132 | untested | ICACHE.md:42-45 hard reset; no bench found asserting SRESET leaves cache contents |
| D-cache 16 KB, 4-way, strict LRU, invalid-way first | UM §3.2.1, PDF 131 | tested | DATA_CACHE.md:20; test-dcache, test-dcache-mutations |
| D-fill 4x64 critical first, forwarded on critical beat (PID7v) | UM §3.2.2, PDF 131 | tested | DATA_CACHE.md:21; test-dcache, test-core-dcache |
| D-fill 8x32 beats (32-bit bus) | UM §3.2.2, PDF 131 | missing | 32-bit mode not modelled (DATA_CACHE.md:205) |
| Cache ops still act with DCE=0 (dcbf on M in disabled cache) | UM §3.2.3.2, PDF 132 | untested | not found in DATA_CACHE.md table; no targeted check seen |
| Weak load/store ordering; I=1 strongly ordered | UM §3.2.3.2, PDF 132 | tested | test-core-lsu-timing-snoop, test-core-bat-cached-bus60x-drain |
| dcbz address-only broadcast (kill) when M=1 | UM §3.2.3.4 PDF 133; §3.7.4 PDF 150 | tested | DATA_CACHE.md:93; test-dcache, test-biu-dcache-snoop |
| ABE broadcasts not snooped by self | UM §3.2.3.4, PDF 133 | tested | DATA_CACHE.md:206; test-biu-dcache-snoop |
| Touch-load buffer (separate one-line buffer, BIU match) | UM §3.2.4, PDF 133 | partial | DATA_CACHE.md:195: dcbt fills straight into cache (E) instead; same software-visible data |
| dcbt no-op for W, I, G, DLOCK, DCE=0, TLB miss, no load permission | UM §3.2.4 PDF 133; §3.7.2 PDF 149 | tested | DATA_CACHE.md:98; CACHE_CONTROL.md:25 never faults; test-dcache, test-core-cache-control |
| Touch load TC=01 on bus | UM §3.2.4; Tbl 7-6 PDF 290 | partial | AUD-78 open: TC=00 for every fill |
| dcbtst fetch as RWITM | UM §3.7.3, PDF 150 | tested | DATA_CACHE.md:189 all fills RWITM; test-dcache |
| Castout of LRU modified victim | UM §3.3.2, PDF 134 | partial | implemented; order castout-before-fill vs manual fill-first (AUD-78) |
| Snoop push (normal) | UM §3.3.3, PDF 134 | tested | test-biu-dcache-snoop, test-chip-dcache-coherence |
| Single-beat for W, I, DCE=0, misaligned | UM §3.4.1, PDF 134 | tested | DATA_CACHE.md:83,90; test-dcache |
| Burst: TBST, DW-aligned critical address; other bursts line order | UM §3.4.2, PDF 134-135 | tested | DATA_CACHE.md:164; test-bus60x-line-read, test-dcache |
| Direct-store segment (T=1) → DSI on 603e | UM §3.4.3, PDF 135 | tested | CPU_VARIANTS.md:92; `ppc_bat_memory_router.sv:33` (XATS only on 603); test-core-page-data-exception |
| WIMG from BAT/PTE; IBAT has no G | UM §3.5, PDF 136 | tested | IBAT G ignored per §3.5 (AUD-79); `test-bat`, `test-bat-service` |
| W: store-through, no combining; W store hit M pushes, stays M | UM §3.5.1 PDF 137; §3.6.4.1 PDF 144 | tested | DATA_CACHE.md:86-90,191; test-dcache |
| I: caching-inhibited, strict order; I=1 hit pushes and invalidates | UM §3.5.2, PDF 137 | tested | DATA_CACHE.md:198; test-dcache |
| M: GBL on bus; M ignored for instruction fetch | UM §3.5.3, PDF 138 | tested | Fetch GBL negated unless HID0[IFEM]; test-chip-mp, `test-chip-pins` `case_ifem` |
| GBL asserted for all data accesses in real mode | UM §3.6.3, PDF 143 | tested | real-mode D WIMG 0011 (`ppc_bat_translate.sv:126`); test-chip-mp |
| G: no speculative/out-of-order access to guarded memory | UM §3.5.4-3.5.5.3, PDF 138-141 | tested | test-core-lsu-timing (spec loads), MMU benches; guarded fetch → ISI |
| Combined accesses / store gathering not implemented | UM §3.5.1-2, PDF 137 | tested | none expected; matches |
| MEI states, RWITM for every fill | UM §3.6-3.6.1, PDF 141 | tested | DATA_CACHE.md:189; test-dcache, test-chip-dcache-coherence |
| Snooped global reads treated as writes (burst read hit E → I, M → push, I) | UM §3.6 PDF 141; Tbl 3-6 PDF 146 | tested | AUD-77 fixed: `test-dcache` D2b, `test-biu-dcache-snoop` |
| CI reads (TT X1010) keep line, M → push then E | UM §3.6, PDF 141 | tested | DATA_CACHE.md:117; test-biu-dcache-snoop |
| Single-ported tags, snoop priority, retry on tag write | UM §3.6.3, PDF 143 | tested | test-core-lsu-timing-snoop, test-biu-dcache-snoop |
| Snoop hit on line in castout buffer → ARTRY, raise castout | UM §3.6.3 PDF 143; §3.6.8 PDF 147 | tested | DATA_CACHE.md:22; test-biu-dcache-snoop |
| Snoop qualified by TS+GBL only | UM §3.6.3, PDF 143 | tested | `ppc_bus60x_snoop.sv:54` (mutation 4); test-biu-dcache-snoop-mutations |
| CSE[0-1] = way replaced, burst reads only | UM §3.6.3 Tbl 3-3, PDF 143 | tested | CHIP_PACKAGE.md:63; test-chip-pins |
| Cache instructions not broadcast (except dcbz, ABE) | UM §3.6.4, PDF 144 | tested | DATA_CACHE.md:104; test-dcache |
| Load/store coherency actions Tbl 3-4/3-5 | UM §3.6.5, PDF 145 | tested | DATA_CACHE.md:82-99; test-dcache (model-checked) |
| Atomic refs: lwarx read-atomic/RWITM-atomic, stwcx. -atomic TTs | UM §3.6.6, PDF 145 | tested | tb_dcache.sv:279; test-dcache |
| Cache reaction to snooped TT (Tbl 3-6) | UM §3.6.7, PDF 145-146 | partial | DATA_CACHE.md:115-120; burst-read row fixed (AUD-77); kill-on-M discards (manual conflict, DATA_CACHE.md:191) |
| ARTRY causes: last-TA collision, post-first-TA, dcbz/dcbf/dcbst tag update | UM §3.6.8, PDF 147 | tested | DATA_CACHE.md:122-130; test-biu-dcache-snoop |
| Enveloped high-priority push / DBWO | UM §3.6.9, PDF 147-148 | tested | CHIP_PACKAGE.md:76,148; test-chip-dcache-coherence, test-core-bat-cached-bus60x-coherence |
| dcbst/sync/icbi/isync self-modifying-code sequence | UM §3.7, PDF 148 | tested | CACHE_CONTROL.md:63-76; test-core-bat-cached-bus60x-cacheops, test-chip-603 |
| Cache op with no TLB entry → TLB miss (data) | UM §3.7, PDF 149 | tested | CACHE_CONTROL.md:29-36; test-core-cache-probe-miss |
| dcbi: invalidate E or M; ABE kill | UM §3.7.1, PDF 149 | tested | test-dcache, test-core-bat-cached-bus60x-cacheops |
| dcbz hit/miss allocate zero line; W or I → alignment | UM §3.7.4, PDF 150 | tested | DATA_CACHE.md:93-94; test-dcache, test-core-dcache |
| dcbz in locked cache → alignment (not stated in UM) | UM §3.7.4, PDF 150 | tested | DATA_CACHE.md:197 decision; test-dcache |
| dcbst: M → write, E; ABE clean broadcast | UM §3.7.5, PDF 150 | tested | test-dcache, test-core-bat-cached-bus60x-cacheops |
| dcbf: M → write-with-kill, I; E → I | UM §3.7.6, PDF 151 | tested | test-dcache, test-core-bat-cached-bus60x-cacheops |
| eieio no-op, CI accesses in program order | UM §3.7.7, PDF 151 | tested | test-core-serialization, test-core-bat-cached-bus60x-cacheops |
| icbi: invalidate all 4 ways of indexed set, no translation | UM §3.7.8, PDF 151 | tested | CACHE_CONTROL.md:20,50; test-core-cache-control, test-icache-managed |
| isync refetch | UM §3.7.9, PDF 151 | tested | test-core-serialization |
| Table 3-7 bus ops for cache instructions | UM §3.8, PDF 152 | tested | DATA_CACHE.md:82-104; test-dcache |
| BIU queues, reservation snoop, touch buffer in BIU | UM §3.9, PDF 153 | partial | BIU built (`ppc_biu.sv`); touch buffer folded into cache (see above) |
| MEI state transaction table | UM §3.10, PDF 154-158 | tested | test-dcache (reference model in tb_dcache.sv) |

## Chapter 4: Exceptions (UM PDF 159-196)

| Item | Manual | Status | Evidence |
|---|---|---|---|
| Vector offsets, all 603e exceptions (0x100-0x1400) | UM §4.1 Table 4-1, PDF 160-164 | tested | rtl/ppc_exception_state.sv:300-420; test-exception-state |
| MSR[IP] vector prefix 0xFFF0_0000 vs 0 | UM Table 4-5, PDF 171 | tested | ppc_exception_state.sv:149 fixed_vector; tb_chip_power, tb_exception_602 |
| Exception priority table (Table 4-2), full matrix | UM §4.1.1, PDF 165-166 | partial | only pairwise cases (trace>EXT/DEC, fetch>IABR, IABR>trace, SMI>INT); EXCEPTION_STATE.md:167 "does not arbitrate simultaneous exceptions" |
| SRR0/SRR1 save, bits 16-31 from MSR, 0-15 cleared | UM §4.2 Table 4-3, PDF 168-169 | tested | exception_srr1(); test-exception-state |
| SRR1 machine-check bits MCP/TEA/DPE/APE (12-15) | UM Table 4-3, PDF 169 | tested | ppc_exception_state.sv:326-336; test-chip-pins |
| SRR1 TLB-miss bits CR0/KEY/I-D/WAY/S-L | UM Table 4-4, PDF 169 | tested | test-exception-tlb-miss (tb_exception_tlb_miss.sv:124,260), test-core-tlb-load (WAY) |
| MSR entry settings (Table 4-7: POW,TGPR,EE,PR,FP,FE,SE,BE,IR,DR,RI cleared; LE<-ILE) | UM Table 4-7, PDF 175-176 | tested | exception_msr() ppc_exception_state.sv:129; test-exception-state |
| MSR[POW] (mtmsr-only, cleared on entry, not in SRR1) | UM Table 4-5, PDF 170 | tested | ppc_special.sv:571-599; test-chip-power |
| MSR[TGPR] set by TLB miss, cleared by rfi/other entries | UM Table 4-5, PDF 170 | tested | ppc_exception_state.sv:303; test-core-tgpr, test-regfile-tgpr |
| MSR[ILE]/MSR[LE] little-endian | UM Table 4-5, PDF 170-171 | tested | test-core-le (tb_core_le); LITTLE_ENDIAN.md |
| MSR[EE] masks INT, SMI, DEC | UM Table 4-5, PDF 170 | tested | test-core-interrupt, test-chip-pins (SMI masked by EE) |
| MSR[PR] privilege | UM Table 4-5, PDF 171 | tested | test-core-supervisor, test-core-segment-privilege |
| MSR[FP] / FP unavailable 0x800 | UM §4.5.8, PDF 189 | tested | test-core-full-decode, test-core-fpu; FPU_CONTRACT.md:80 |
| MSR[ME] gates machine check vs checkstop | UM §4.5.2, PDF 179 | tested | test-chip-pins, test-core-bat-machine-check |
| MSR[FE0]/[FE1]: imprecise modes treated precise | UM §4.5.7.1, PDF 188 | tested | test-fpu-enabled-603 (FPU_CONTRACT.md) |
| MSR[SE] single-step trace (not on rfi/isync/sc/trap) | UM §4.5.11, PDF 190-191 | tested | ppc_core.sv:2920; test-core-machine-check-trace |
| MSR[BE] branch trace | UM §4.5.11.2, PDF 191 | tested | test-core-machine-check-trace (tb:560) |
| MSR[RI] cleared on entry, saved/restored | UM §4.2.3, PDF 173 | tested | EXCEPTION_MACHINE_CHECK_TRACE.md:51-57; test-core-machine-check-trace |
| MSR reserved full-function vs partial-function bits in SRR1 | UM Table 4-5, PDF 170 | untested | MSR_MASK in ppc_pkg.sv; no bench checks bits 0/5-9/24/28-29 round trip |
| rfi restores MSR from SRR1, problem-state rfi = privileged | UM §4.2.4, PDF 174 | tested | ppc_exception_state.sv:367; test-exception-state |
| mtmsr/rfi enabling pending exception taken first | UM §4.2.1, PDF 172 | tested | EXCEPTION_STATE.md:42,133; test-core-interrupt |
| Context sync requirements (isync after mtmsr) | UM §4.2.4/§4.3, PDF 174 | tested | test-core-serialization |
| Exception latencies | UM §4.4, PDF 175 | partial | functional only; no cycle-latency check |
| Hard reset: vector 0xFFF0_0100, MSR=0x40 | UM §4.5.1.1, PDF 177 | tested | ppc_exception_state.sv:170; test-chip-pins, test-soc-target-reset |
| Hard reset register values (Table 4-8: SPRs, DEC=FFFFFFFF, miss regs 0, cache invalid) | UM Table 4-8, PDF 177 | tested | EVENT_RESET_CONTRACT.md:42; test-core-event-reset |
| Hard reset: external checkstops enabled | UM §4.5.1.1, PDF 178 | tested | ckstp_in in ppc603e.sv; test-chip-pins |
| Soft reset (SRESET) 0x100 per IP, recoverable, SRR1[30] | UM §4.5.1.2 Table 4-9, PDF 178 | tested | ppc_exception_state.sv:339; test-chip-pins |
| Soft reset disables I-cache / completed store queue drain | UM §4.5.1.2, PDF 178 | partial | SRESET clears HID0[ICE] (AUD-83, `test-chip-pins`); stores perform before commit (no CSQ) |
| SRESET min 2 bus clocks | UM §4.5.1.2, PDF 178 | n/a | pin timing; edge-detected in ppc603e.sv |
| Machine check on TEA | UM §4.5.2, PDF 179 | tested | test-core-bat-machine-check, test-core-bus60x-ifetch-error |
| Machine check on MCP, gated by HID0[EMCP] | UM §4.5.2, PDF 179 | tested | ppc603e.sv:57; test-chip-pins |
| Machine check on DPE/APE, HID0[EBD]/[EBA] | UM Table 4-3, PDF 169 | tested | test-chip-pins (parity cases) |
| Machine check cancels pending stores in CSQ | UM §4.5.2, PDF 179 | n/a | no completed store queue; stores perform before commit (EXCEPTION_MACHINE_CHECK_TRACE.md:67) |
| sync/load/sync recoverable bus probe | UM §4.5.2, PDF 179 | tested | test-core-bat-machine-check |
| Checkstop: ME=0 machine check, CKSTP_IN; CKSTP_OUT asserted | UM §4.5.2.2, PDF 180 | tested | ppc603e.sv:56; test-chip-pins |
| Checkstop on extended transfer protocol error | UM §4.5.2.2, PDF 180 | tested | 603: a bus protocol error checkstops (`test-chip-603` `+ds_protocol`); 603 fetch TEA with ME=1 checkstops (`+fetch_tea`, UM §C.2.4) |
| Checkstop latch freeze for analysis | UM §4.5.2.2, PDF 180 | n/a | no COP/scan (CHIP_PACKAGE.md:113) |
| DSI: protection violation DSISR[4], store DSISR[6] | UM §4.5.3 Table 4-11, PDF 181-182 | tested | ppc_special.sv:1789; test-core-page-data-exception, test-core-data-fault |
| DSI: direct-store segment access (603e, T=1) | UM §4.5.3, PDF 181 | tested | DATA_DSI_DIRECT_STORE, DSISR 0x0400_0000; test-core-page-data-exception |
| DSI: memory->direct-store segment crossing | UM §4.5.3, PDF 181 | untested | no crossing case found in tb |
| DSI: eciwx/ecowx with EAR[E]=0 (DSISR[11]) | PEM Table 6-9, PDF 273 | tested | ppc_special.sv:1787; test-chip-ecxwx |
| DSI: stwcx. faults without reservation check | UM §4.5.3, PDF 181 | tested | tb_core_full_decode.sv:6 |
| DSI: lswi/stswi with byte count 0 never faults | UM §4.5.3, PDF 181 | tested | FULL_DECODE.md:52; test-core-full-decode |
| DSI: page crossing mid-instruction, DAR in first word of faulting page | UM §4.5.3, PDF 181-182 | tested | LOAD_STORE_EXTENSIONS.md; test-core-lsu-extensions |
| DSI: partial lmw/stmw/string execution, rA not updated | UM §4.5.3, PDF 182 | tested | EXCEPTION_MACHINE_CHECK_TRACE.md "Cracked instructions"; test-core-lsu-extensions |
| DSI from cache ops (dcbi/dcbz/dcbst/dcbf), DAR in block | UM Table 4-11, PDF 182 | tested | CACHE_CONTROL.md; test-core-cache-control |
| ISI: no-execute (SR[N]), guarded (G), T=1 fetch, PP (SRR1[3]/[4]) | UM §4.5.4, PDF 183 | tested | test-core-page-instruction-exception, test-core-fetch-fault |
| External interrupt INT level-sensitive, EE gated | UM §4.5.5, PDF 183-184 | tested | test-core-interrupt, test-chip-pins |
| Alignment: lmw/stmw/lwarx/stwcx. not word aligned | UM §4.5.6, PDF 184,187 | tested | test-core-alignment, test-core-lsu-extensions |
| Alignment: FP load/store not word aligned | UM §4.5.6.2, PDF 187 | tested | tb_chip_603.sv:161, test-core-fpu (LSU_PIPELINE.md) |
| Alignment: misaligned LE access; multiple/string with LE=1 | UM §4.5.6, PDF 184 | tested | LITTLE_ENDIAN.md:73-84; test-core-le |
| Alignment: dcbz to W=1 or I=1 | UM §4.5.6.1.1, PDF 186 | tested | CACHE_CONTROL.md:39; test-core-cache-control |
| Alignment: page-crossing half/word/dword (EA ends 0xFFF/FFD-FFF/FF9-FFF) under DR=1 | UM §4.5.6.1.1, PDF 186 | tested | ENABLE_MISALIGNED_ACCESS (ppc_core.sv:54); test-core-alignment |
| Alignment DSISR (Table 4-13) and DAR; lmw/stmw DAR=EA+4 | UM Table 4-13, PDF 185, 187 | tested | ppc_special.sv:903; test-core-alignment |
| Program: illegal instruction (incl. 64-bit ops, fsqrt, tlbia) | UM §4.5.7.2, PDF 188 | tested | test-core-full-decode, test-decode-sweep |
| Program: privileged instruction; mfspr/mtspr SPR[0]=1 invalid in user mode | UM §4.5.7, PDF 187 | tested | test-core-supervisor, test-core-full-decode |
| Program: trap | UM §4.5.7, PDF 188 | tested | test-core-full-decode |
| Program: FP enabled exception (FE0/FE1 & FPSCR[FEX]) | UM §4.5.7.1, PDF 188 | tested | Precise 0x700 per UM Table 4-1 and PEM; the §4.5.7.1 emulation-trap text is a manual conflict decided in FPU_CONTRACT.md; `test-fpu-enabled-603` |
| FPSCR sticky-bit update serialization penalty | UM §4.5.7.1, PDF 188 | untested | timing only; not checked |
| Decrementer: MSB 0->1 request incl. mtdec; coalesce; held until EE | UM §4.5.9, PDF 189; PEM §2.3.14.1 | tested | ppc_timer.sv:19; test-timer (+NEGATIVE_WRITE), test-core-timer-events |
| System call 0xC00, SRR0 = next | UM §4.5.10, PDF 189 | tested | test-core-supervisor |
| Trace SRR0 = next instruction, SE/BE cleared on entry | UM Table 4-15, PDF 190 | tested | test-core-machine-check-trace |
| Trace/IABR soft stop / hard stop via COP | UM §4.5.11.1-2, PDF 191 | n/a | no JTAG/COP (CHIP_PACKAGE.md:113,231) |
| ITLB miss 0x1000 | UM §4.5.12, PDF 191-192 | tested | test-core-tlb-miss, test-exception-tlb-miss |
| DTLB miss on load 0x1100 | UM §4.5.13, PDF 192 | tested | test-core-tlb-miss |
| DTLB miss on store 0x1200 incl. C=0 store hit | UM §4.5.14, PDF 193 | tested | needs_changed in ppc_bat_memory_router.sv:403; test-core-page-miss-result |
| IABR: IABR[0-29] compare, [30] enable, [31] ignored, trap before execute | UM §4.5.15, PDF 193-194 | tested | ppc_core.sv:655; test-core-machine-check-trace |
| IABR outranks trace on same instruction | UM §4.5.11, PDF 190 | tested | EXCEPTION_MACHINE_CHECK_TRACE.md IABR section |
| SMI 0x1400, EE gated, priority over INT | UM §4.5.16, PDF 194-196 | tested | ppc_exception_state.sv:348; test-chip-pins |
| SMI deferred while MSR[TGPR]=1 | UM §4.5.16, PDF 195 | tested | AUD-75 fixed: SMI taken with TGPR=1; `test-exception-state` |
| Emulation trap 0x1600 | UM §4.5.7.2, PDF 188 | out of scope | 603e decodes these; 0x1600 only for 602 (ppc_exception_state.sv:424, CPU_VARIANTS.md) |

## Chapter 5: Memory management (UM PDF 197-246)

| Item | Manual | Status | Evidence |
|---|---|---|---|
| Real addressing mode (IR/DR=0, EA=PA) | UM §5.2, PDF 218 | tested | test-core-bat, many core benches |
| Real-mode WIMG = 0011 for data and fetch | UM §3.5 PDF 137; §5.2 | tested | DATA_CACHE.md:56; ppc_core_bat_cached_bus60x.sv:483; test-chip-icache-real |
| 4 IBAT + 4 DBAT, BEPI/BL block sizes 128K-256M | UM §5.3, PDF 218-219 | tested | rtl/ppc_bat_translate.sv; test-bat, test-core-bat |
| BAT Vs/Vp per privilege | UM §5.3, PDF 218 | tested | test-core-runtime-bat-privilege |
| BAT PP protection, DSI/ISI on violation | UM §5.1.4, PDF 208 | tested | test-bat-data-fault, test-core-runtime-bat-privilege |
| BAT WIMG (IBAT W/G reserved, G on IBAT -> ISI) | UM §5.3, PDF 218 | tested | test-core-fetch-fault (SRR1[3]) |
| BAT precedence over segment translation | UM §5.1.6.1, PDF 209 | tested | test-bat-memory-router |
| Overlapping BAT hits (boundedly undefined) | PEM §7.4, PDF 316 | untested | no multi-hit case seen |
| 16 segment registers, mtsr/mtsrin/mfsr/mfsrin | UM §5.4, PDF 219 | tested | test-segment-registers, test-core-segment-csr |
| SR Ks/Kp key selection with PP | UM §5.4.2, PDF 223 | tested | test-core-segment-privilege |
| SR[N] no-execute -> ISI | UM §5.1.4, PDF 208 | tested | test-core-page-instruction-exception |
| SR[T]=1 direct-store on 603e -> DSI (data), ISI (fetch) | UM §5.1.7, PDF 212-214 | tested | PAGE_DATA_EXCEPTIONS.md:28; test-core-page-data-exception |
| Page tables: SDR1 HTABORG/HTABMASK | UM §5.5, PDF 226 | tested | test-core-sdr1 |
| Referenced bit: TLB R effectively always 1; software sets PTE[R] | UM §5.4.1.1, PDF 220 | tested | TLB_SERVICE.md:99; firmware table-search benches |
| Changed bit: TLB C=0 store -> DTLB store miss; software updates PTE[C] | UM §5.4.1.2, PDF 221 | tested | needs_changed; test-core-page-miss-result |
| R/C recording rules (Table 5-x scenarios) | UM §5.4.1.3, PDF 221-222 | out of scope | software responsibility on 603e |
| Page protection Ks/Kp x PP table | UM §5.4.2, PDF 223 | tested | test-core-page-data-exception, test-core-page-instruction-exception |
| ITLB/DTLB 64 entries 2-way, 32 sets, EA[15:19] index | UM §5.4.3.1, PDF 223-224 | tested | ppc_tlb_service.sv; test-tlb-service, test-tlb-geometry-16 |
| TLB replacement way hint (LRU) -> SRR1[WAY] | UM §5.4.3.1, PDF 224 | tested | test-core-tlb-load |
| tlbie invalidates both ways at index, both TLBs | UM §5.4.3.2, PDF 225 | tested | test-core-tlbie, test-tlb-runtime-invalidate-service |
| tlbie privilege | UM §5.1.8, PDF 215 | tested | test-core-tlbie-privilege |
| tlbsync waits on TLBISYNC pin | UM §5.4.3.2, PDF 225 | tested | ppc_special.sv:1488; test-chip-pins |
| tlbia not implemented (illegal) | UM §5.1.8, PDF 215 | tested | tb_core_full_decode.sv:218 |
| tlbld / tlbli load from RPA and miss regs | UM §5.5.2, PDF 229-230 | tested | test-core-tlb-load, test-tlb-prepared-refill |
| DMISS/IMISS (miss EA) | UM §5.5.2.1.1, PDF 231 | tested | ppc_miss_derive.sv; test-miss-derive |
| DCMP/ICMP (compare word V/VSID/H/API) | UM §5.5.2.1.2, PDF 231 | tested | test-miss-derive |
| HASH1/HASH2 primary/secondary PTEG addresses | UM §5.5.2.1.3, PDF 232 | tested | test-miss-derive |
| RPA register | UM §5.5.2.1.4, PDF 232 | tested | test-core-tlb-load |
| Software table search handlers (example code) | UM §5.5.2.2, PDF 232-244 | tested | TABLE_SEARCH_HANDLER.md; tb_compiled_table_bus60x_firmware (toolchain rtl-all) |
| TGPR use by miss handlers | UM §5.5.2.2, PDF 233 | tested | test-core-tgpr |
| Synthesized page fault -> ISI/DSI (DSISR[1]) from handler | UM §5.5.2.2, PDF 233; Table 4-11 | tested | tb_compiled_page_dsi/isi firmware (toolchain rtl-all) |
| Page table / SR update sequences (sync, tlbie, tlbsync, isync) | UM §5.5.3-5.5.4, PDF 244 | tested | firmware MMU stress (MMU_STRESS_FIRMWARE.md) |
| Micro-TLB / context invalidation on SR, BAT, MSR change | UM §5.1.2, PDF 199 | tested | test-micro-tlb-router, test-core-live-context |
| Hash table walk in hardware | UM §5.5.1, PDF 226 | n/a | 603e has none; software search only |
| MMU exceptions summary (Table 5-x) | UM §5.1.7, PDF 212-214 | tested | covered by rows above |
| Direct-store segment DSI exceptions to software for lwarx etc. | UM §5.1.7, PDF 213 | tested | test-chip-603 (603 variant) |

## Chapter 6: Instruction timing, prose rules (UM PDF 247-276)

| Item | Manual | Status | Evidence |
|---|---|---|---|
| Latency tables 6-1..6-6 (per-instruction rows) | UM §6.7, PDF 268-276 | partial | `docs/references/SOURCE_RECONCILIATION.md`: 190 rows of `sim/spec/timing.json` reconciled (`check-spec`). The RTL is checked against rows only for mul/div/FPU (`test-multiply-timing`, `test-divider-timing`, `test-fpu-timing-603`). FP loads/stores are not yet at Table 6-6 (SYSTEM_COMPLETION FP row). |
| No BTIC on the 603e; target fetch through the I-cache | UM §6.3.2, §6.4.1, PDF 255-262 | n/a | The manual has no BTIC (grep finds none). `docs/CHIP_PACKAGE.md:216` also says none. |
| Fetch: two instructions per cycle, one-cycle hit | UM §6.3.2.2, PDF 255 | tested | `rtl/ppc603e.sv` FETCH_WIDTH=2. `test-core-fetch2`. `tb_chip_pins` "fetch requests every cycle on hits" |
| Six-entry IQ, refilled on any vacancy | UM §6.3.1, PDF 252-254 | untested | `rtl/ppc_pkg.sv:7` IQ_DEPTH=6. No occupancy check (DUAL_DISPATCH_DESIGN §Dispatch rule check: "Not checked") |
| Cache arbitration (fetch vs reload) | UM §6.3.2.1, PDF 255 | partial | `docs/ICACHE.md:221`: one lookup in flight, no hit-under-miss |
| I-cache miss: critical doubleword forwarded, streaming during reload | UM §6.3.2.3, Fig 6-4, PDF 256-257 | tested | `docs/ICACHE.md:114-128`. `test-icache`, `test-icache-bus60x` |
| Dual dispatch: DQ1 needs a different free unit | UM §6.3.3, §6.6.1.2, PDF 257, 267 | tested | Behind `DISPATCH_WIDTH=2` (default 1). `test-core-dual`, `test-dispatch-rules` TIM-DISP-DQ1 |
| Reservation station per unit; issue on the rename write cycle | UM §6.3.3, PDF 257-258 | partial | IU/LSU stations (DUAL_DISPATCH_DESIGN §Station waits). Operand readiness is not trace-checked. The cycle rule has no contract (PERFORMANCE_TARGET "Timing rules not yet contracts") |
| Five completion buffers; dispatch stalls when full | UM §6.3.3, PDF 258 | untested | `rtl/ppc_pkg.sv:9` CQ_DEPTH=5. CQ occupancy not checked (DUAL_DISPATCH_DESIGN:961) |
| Stores, FPU and SRU retire only from CQ0; up to two retire per cycle | UM §6.3.3, §6.6.1.3, PDF 258, 268 | tested | `test-dispatch-rules` TIM-SER-COMPLETE, TIM-CQ-CQ1, TIM-DISP-WIDTH |
| Writeback limits: 2 GPR, 1 each CR/FPR/LR/CTR per cycle | UM §6.3.3, PDF 258 | tested | `test-dispatch-rules` TIM-WB-LIMITS |
| Rename registers: 5 GPR, 4 FPR, 1 CR/LR/CTR | UM §6.3.3.1, PDF 258-259 | partial | `rtl/ppc_pkg.sv:8` GPR_RENAME_DEPTH=5, `test-rename-pair`. The single CR rename is not modelled as a dispatch stall (PERFORMANCE_TARGET A13) |
| Precise exceptions at the last CQ position | UM §6.3.3, PDF 258 | tested | `ppc_completion`. Exception benches, e.g. `test-core-interrupt`, `test-core-alignment` |
| Completion-serialized class (SRU non-add/cmp, cache/TLB ops, lmw/stmw/string, sync) | UM §6.3.3.2, PDF 259 | tested | `test-core-serialization`, `test-serialization-decode`, `test-dispatch-rules` TIM-SER-COMPLETE |
| Dispatch-serialized class (lmw/lswi/lswx, mtxer/mcrxr, sync/isync/mtmsr/rfi/sc) | UM §6.3.3.2, PDF 259 | tested | `test-dispatch-rules` TIM-DISP-DQ0, TIM-SER-DISPATCH |
| Refetch serialization (isync) | UM §6.3.3.2, PDF 259 | tested | `test-dispatch-rules` TIM-SER-REFETCH |
| Unit busy stalls dispatch | UM §6.3.3.3, PDF 260 | partial | Implemented, but unit busy times are not trace-checked (DUAL_DISPATCH_DESIGN:961) |
| Branch folding (branch removed from the stream) | UM §6.4.1.1, PDF 260-261 | partial | Folded `b`/predicted-taken `bc`/`bclr`/`bcctr` redirect at fetch (`rtl/ppc_core.sv:668`, `test-core-branch-fold`). Removal from the dispatch slot only behind `ENABLE_BRANCH_REMOVAL` (default 0, `rtl/ppc_core.sv:17`). Branches still take a dispatch slot |
| Seven fetch-stop dependency cases (mtlr→bclr, mtctr→bcctr, LK→LK, CR→CR, ...) | UM §6.4.1.1, PDF 261 | partial | The waits exist (CR branch behind a predicted one, LR/CTR writer pending; DUAL_DISPATCH slice 7). They are not enumerated or cycle-checked against the list (PERFORMANCE_TARGET timing rules) |
| Static prediction: backward taken, `y` bit inverts | UM §6.4.1.2, PDF 262 | tested | `rtl/ppc_core.sv:668-669`, ENABLE_BRANCH_SPEC=1 (`ppc_core.sv:102`). `test-core-branch-recovery` |
| One level of prediction; nothing completes past an unresolved branch; flush on mispredict | UM §6.4.1.2, PDF 262 | tested | `docs/CONTROL_MEMORY.md:41`. `test-core-branch-recovery`, `test-dispatch-rules` TIM-CQ-ORDER |
| No prediction when LR/CTR target is pending | UM §6.4.1.2, PDF 262 | tested | `test-core-branch-fold` (fold waits for an older LR/CTR writer, slice 7) |
| Predicted-branch cycle costs (taken target F+2, mispredict redirect R+1) | UM §6.4.1.2.1, Fig 6-3/6-5, PDF 262-263 | partial | Redirect "on the edge after resolution" (PERFORMANCE_TARGET:823). Not replayed against Figs 6-3..6-5 |
| CR forwarded to the BPU at end of execute | UM §6.4.1, Table 6-4 `^`, PDF 264 | tested | `docs/CONTROL_MEMORY.md:41` (resolves when the owner's CR result is captured). `test-core-branch-recovery` |
| IU timing: single-cycle ALU, multiply, divide | UM §6.4.2, PDF 264 | tested | `test-multiply-timing`, `test-divider-timing`, `test-core-divider-timing-pid6` |
| SRU runs add/addi/addis/cmp beside the IU | UM §6.4.5, PDF 264 | partial | Only at width 2 with `--sru` (DUAL_DISPATCH_DESIGN:948). IU+SRU pairing still open (PERFORMANCE_TARGET rank 5) |
| FPU pipeline timing | UM §6.4.3, PDF 264 | tested | `test-fpu-timing-603` (ENABLE_FPU default 0, so not on the chip by default) |
| LSU: two stages, 2-cycle load-use, one access per cycle | UM §6.4.4, PDF 264 | partial | Only with ENABLE_LSU_PIPE (default 0, `rtl/ppc603e.sv:8`). Base snooping behind LSU_BASE_SNOOP (default 0) |
| Copy-back / write-through / cache-inhibited access costs | UM §6.5.1-6.5.3, PDF 264-266 | partial | Works functionally (`test-dcache`). No timing contract (PERFORMANCE_TARGET "Timing rules not yet contracts") |
| sync/isync/eieio timing | UM §6.3.3.2, Table 6-2, PDF 259 | partial | Serialization is tested (above). eieio has no action (`docs/DATA_CACHE_INTEGRATION.md:78`). The cycle cost is not checked |
| Scheduling guidelines (BPU/dispatch/completion resource lists) | UM §6.6, PDF 266-268 | partial | The dispatch/completion lists are trace-checked (`test-dispatch-rules`). The branch-resolution resource list is not |

## Chapter 7: Signal descriptions (UM PDF 277-308)

| Item | Manual | Status | Evidence |
|---|---|---|---|
| BR output | UM §7.2.1.1, PDF 280 | tested | `rtl/ppc603e.sv:391`. `test-chip-pins` (BR negated after a foreign ARTRY) |
| BG input, qualified grant (BG ∧ ¬ABB ∧ ¬ARTRY) | UM §7.2.1.2, PDF 281 | tested | `rtl/ppc_bus60x.sv:290`. `test-chip-mp` checks "TS only after a qualified BG" |
| Parked BG (no BR needed) | UM §7.2.1.2, §8.2.1, PDF 281, 316 | untested | The qualified-grant logic takes a parked BG. No parking case in the benches (grep "park" finds none for 603e) |
| ABB output (half-cycle negation, release) | UM §7.2.1.3.1, PDF 281 | tested | `rtl/ppc603e.sv:392-393`. `test-chip-mp` (shared ABB/DBB) |
| ABB input | UM §7.2.1.3.2, PDF 282 | tested | `test-chip-mp` shared ABB |
| TS output | UM §7.2.2.1.1, PDF 282 | tested | Every chip bench (BFM decodes TS) |
| TS input (snoop start) | UM §7.2.2.1.2, PDF 283 | tested | `test-chip-dcache-coherence`, `test-chip-mp` |
| A[0:31] output | UM §7.2.3.1.1, PDF 283 | tested | Every chip bench |
| A[0:31] input (snoop address) | UM §7.2.3.1.2, PDF 283 | tested | `test-chip-dcache-coherence` |
| AP[0:3] output (odd parity) | UM §7.2.3.2.1, PDF 284 | tested | `rtl/ppc603e.sv:397`. Checked every cycle at `tb/chip_harness.svh:129` |
| AP[0:3] input, checked on a snooped GBL TS | UM §7.2.3.2.2, PDF 284 | tested | `test-chip-pins` case_ape |
| APE output (TS+2, HID0[EBA], MC/checkstop) | UM §7.2.3.3, PDF 284-285 | tested | `test-chip-pins` (APE two cycles after TS, SRR1[15], checkstop, EBA=0) |
| TT[0:4] output (Table 7-1 encodings) | UM §7.2.4.1.1, PDF 285-286 | tested | BFM checks TT legality (`docs/DATA_CACHE_INTEGRATION.md:306`). `test-chip-dcache-coherence` |
| TT[0:4] input, snoop action (Table 7-2) | UM §7.2.4.1.2, PDF 287 | tested | Burst Read/Read-atomic flush (AUD-77 fixed) |
| PID7v HID0[ABE] address-only overlay (Table 7-3) | UM §7.2.4.1, PDF 288 | tested | `rtl/ppc_dcache.sv:554-574`, `rtl/ppc_special.sv:1514`. `test-dcache` ABE directed and random |
| TSIZ[0:2] (no 5-7 byte sizes) | UM §7.2.4.2, Table 7-5, PDF 288 | tested | BFM decodes TSIZ (`tb/bfm/bus60x_coherent_bfm.sv:386`). `docs/references/BUS_ENCODINGS.md` |
| TBST output | UM §7.2.4.3.1, PDF 289 | tested | `tb_chip_icache_real`, `tb_chip_603` burst checks |
| TBST input (snoop) | UM §7.2.4.3.2, PDF 289 | tested | Selects the snoop class of a Read (AUD-77) |
| TC[0:1] (Table 7-6) | UM §7.2.4.4, PDF 290 | partial | Fetch TC=10 checked (`tb_chip_icache_real.sv:70`). AUD-78 open: touch-load fills drive TC=00, not 01 |
| CI output | UM §7.2.4.5, PDF 290 | tested | `test-chip-pins` ILOCK case (misses read with CI) |
| WT output | UM §7.2.4.6, PDF 290 | tested | BFM logs it (`bus60x_coherent_bfm.sv:293`). Write-through in `test-dcache`. Pin value only lightly checked |
| GBL output / input | UM §7.2.4.7, PDF 291 | tested | `test-chip-dcache-coherence`. `test-chip-pins` "GBL negated: no APE" |
| CSE[0:1] (way of the fill/castout) | UM §7.2.4.8, PDF 291 | tested | 603e: `test-chip-pins` `case_cse` (four fills into one set give CSE 0-3); 603 CSE0: `test-chip-603` |
| AACK input | UM §7.2.5.1, PDF 292 | tested | Every bus bench |
| ARTRY input (qualified retry, BG blocked) | UM §7.2.5.2.2, PDF 293 | tested | `test-core-bat-bus60x-retry`, `test-chip-pins`, `test-chip-mp` |
| ARTRY output (snoop window TS+2..AACK+1, precharge) | UM §7.2.5.2.1, PDF 292 | tested | BFM fatal outside a snoop window (`bus60x_coherent_bfm.sv:660`). `test-chip-dcache-coherence` |
| DBG input, qualified (¬DBB ∧ ¬DRTRY ∧ ¬ARTRY) | UM §7.2.6.1, PDF 293 | tested | `rtl/ppc_bus60x.sv:333`. `test-chip-mp` "DBB only after a qualified DBG" |
| DBWO input | UM §7.2.6.2, PDF 294 | tested | `test-chip-dcache-coherence` (`dbwo_push_pct`, n_dbwo_push / n_dbwo_ignored coverage). Not between processors (CHIP_PACKAGE_VERIFICATION:169) |
| DBB output / input | UM §7.2.6.3, PDF 294 | tested | `test-chip-mp` shared DBB |
| DH/DL[0:31] data bus | UM §7.2.7.1, PDF 295-296 | tested | Every chip bench |
| DP[0:7] output (odd parity) | UM §7.2.7.2.1, PDF 296 | tested | `tb/chip_harness.svh:132` |
| DP[0:7] input, HID0[EBD] | UM §7.2.7.2.2, PDF 296 | tested | `test-chip-pins` DPE cases |
| DPE output (TA+2, cancelled by DRTRY) | UM §7.2.7.3, PDF 297 | tested | `test-chip-pins` (SRR1[14], checkstop, EBD=0, DRTRY cancel) |
| DBDIS input | UM §7.2.7.4, PDF 297 | untested | `rtl/ppc603e.sv:415` gates data_oe. No bench drives it low (`tb/chip_harness.svh:13`, `tb_chip_mp.sv:94` tie it to 1) |
| TA input | UM §7.2.8.1, PDF 298 | tested | Every bus bench |
| DRTRY input (normal mode) | UM §7.2.8.2, PDF 298 | tested | `test-chip-mp` (cancel, hold 0-2, replace), `test-core-bat-cached-bus60x-stress` |
| TEA input (priority over TA/DRTRY, MC or checkstop) | UM §7.2.8.3, PDF 299 | tested | `test-chip-mp` (+WRITE_TEA), `test-core-bat-bus60x-errors`, `rtl-chip-machine-check` |
| INT input (level, MSR[EE]) | UM §7.2.9.1, PDF 299 | tested | `test-chip-pins` (`tb_chip_pins.sv:590`), `test-core-interrupt` |
| SMI input (0x1400, above INT) | UM §7.2.9.2, PDF 300 | tested | `test-chip-pins` SMI cases; TGPR=1 entry in `test-exception-state` (AUD-75) |
| MCP input (edge, HID0[EMCP], MC/checkstop) | UM §7.2.9.3, PDF 300 | tested | `test-chip-pins` (taken, ignored with EMCP=0, checkstop) |
| CKSTP_IN input | UM §7.2.9.4, PDF 300 | tested | `test-chip-pins` "checkstop holds after CKSTP_IN negates" |
| CKSTP_OUT output | UM §7.2.9.5, PDF 301 | tested | `test-chip-pins` expect_checkstop |
| HRESET (outputs released, 0xFFF00100, straps sampled) | UM §7.2.9.6.1, PDF 301 | tested | `test-chip-pins` "HRESET releases outputs within five clocks", reset vector |
| SRESET (edge latched, 0x100) | UM §7.2.9.6.2, PDF 302 | tested | `test-chip-pins` SRESET cases, including the HID0[ICE] clear (AUD-83) |
| QREQ output | UM §7.2.9.7.1, PDF 302 | tested | `test-chip-power` (nap/sleep assert QREQ, doze does not) |
| QACK input (and full-pinout strap) | UM §7.2.9.7.2, PDF 302 | tested | `test-chip-power` (snooping stops after QACK) |
| RSRV output | UM §7.2.9.7.3, PDF 303 | tested | `test-chip-pins` (lwarx asserts, stwcx. negates). `test-chip-power` (a kill clears it in doze) |
| TBEN input | UM §7.2.9.7.4, PDF 303 | tested | `test-chip-pins` TBEN cases |
| TLBISYNC input (holds tlbsync) | UM §7.2.9.7.5, PDF 303-304 | tested | `test-chip-pins` "TLBISYNC holds completion at tlbsync" |
| Reset-configuration sampling (DRTRY, TLBISYNC, QACK, PLL_CFG at HRESET negation) | UM §7.2.9.7.5, §8.6, PDF 304, 346-349 | partial | Sampled. The unsupported selections (32-bit, reduced pinout, other PLL codes) checkstop (`test-chip-pins` case_straps, CHIP_PACKAGE.md §Start-up straps) |
| COP debug / BIST | UM §7.2.10, PDF 304 | missing | Absent (CHIP_PACKAGE.md:231). Architected state cannot be read in checkstop |
| JTAG TCK/TMS/TDI/TRST/TDO boundary scan | UM §7.2.10, §8.9, PDF 304, 351 | n/a | Boundary scan tests the package; there is none on an FPGA soft core. Inputs ignored, TDO high-Z (`rtl/ppc603e.sv:470-471`) |
| LSSD TEST[0:2] | UM §7.2.10, PDF 304 | n/a | Manufacturing scan. Ignored (CHIP_PACKAGE.md:115) |
| Pipeline tracking (HID0[EICE] turns AP/DP into outputs, FBIOB) | UM §7.2.11, Table 7-9, PDF 304-305 | missing | HID0[EICE] is stored but has no effect (CHIP_PACKAGE.md §Start-up straps) |
| SYSCLK; core:bus ratio | UM §7.2.12.1, PDF 306 | tested | Ratio modelled with `bus_ce_o` (`rtl/ppc603e.sv:166`). `test-chip-ratios` (2:1..4:1). The analog PLL is n/a |
| CLK_OUT (HID0 SBCLK/ECLK, Table 7-4) | UM §7.2.12.2, PDF 288, 306 | missing | Tied high-Z (`rtl/ppc603e.sv:468-469`). HID0 bits have no effect |
| PLL_CFG[0:3] (Table 7-10), HID1[PC0-3] | UM §7.2.12.3, PDF 306-307 | partial | One build-time code. HID1 reads it. Any other strap checkstops (`test-chip-pins` case_straps). PLL bypass/clock-off are not modelled |
| Power pins VDD/OVDD/AVDD/GND | UM §7.2.13, PDF 308 | n/a | Supplies, not signals (CHIP_PACKAGE.md:116) |

## Chapter 8: System interface operation (UM PDF 309-354)

| Item | Manual | Status | Evidence |
|---|---|---|---|
| Cache/BIU operation: fills, castouts, single-beat for CI/WT | UM §8.1.1-8.1.2, PDF 310-313 | tested | `test-chip-dcache-coherence`, `test-core-bat-cached-bus60x` |
| 32-bit data bus mode (DH only, 1/2/8 beats, DL driven low) | UM §8.1.2.1, §8.6.1, PDF 313, 346-347 | missing | The TLBISYNC strap selecting it checkstops (CHIP_PACKAGE.md strap table, `test-chip-pins`) |
| Direct-store (T=1) access takes DSI on the 603e | UM §8.1.3, PDF 314 | tested | SYSTEM_COMPLETION supervisor row (direct-store T=1). `tb/tb_compiled_dsi_firmware.sv`. The 603 XATS protocol is separate (`test-chip-603`) |
| Split address/data tenures, independent arbitration | UM §8.2, PDF 314-315 | tested | `test-chip-mp` (separate address/data processes) |
| Address-only dcbz kill broadcast | UM §8.2, Table 7-1, PDF 315, 285 | tested | `test-dcache` ("dcbz miss (kill broadcast)"), `test-chip-dcache-coherence` |
| sync/eieio/tlbsync/icbi/TLBI/reservation-set address-only tenures | Table 7-1, PDF 285-286 | n/a | The 603e master never generates them (Table 7-1 "N/A") |
| Qualified BG/DBG arbitration rules | UM §8.2.1, §8.3.1, §8.4.1, PDF 315-319, 330-331 | tested | `test-chip-mp` grant checks |
| Intraprocessor one-level address pipelining | UM §8.2.2, PDF 316-317 | partial | Only a snoop push's address tenure may follow one that still owes data. Other tenures wait (CHIP_PACKAGE.md §DBWO) |
| Interprocessor pipelining; data in address order | UM §8.2.2, PDF 317 | tested | `test-chip-mp` (address pipelining, early BG cancelled by ARTRY) |
| Address transfer: A/attributes driven through AACK, released after | UM §8.3.2, PDF 319-321 | tested | BFM pin checks. `test-chip-mp` "data driven only by the owner" |
| Address bus parity generation/check | UM §8.3.2.1, PDF 321 | tested | `tb/chip_harness.svh:129`. `test-chip-pins` APE |
| TT/TSIZ attribute rules; no 5-7 byte transfers; coherency size 32 B | UM §8.3.2.2, Table 8-1, PDF 321-322 | tested | BFM legality check (`docs/DATA_CACHE_INTEGRATION.md:306`) |
| Burst ordering, 64-bit: reads critical DW first and wrap, writes DW0 first | UM §8.3.2.3, Table 8-2, PDF 322 | tested | `docs/DATA_CACHE.md:21,172`, `docs/ICACHE.md:119-128`. `test-icache-bus60x`, `test-dcache` |
| Burst ordering, 32-bit (Table 8-3) | UM §8.3.2.3, PDF 323 | missing | No 32-bit mode |
| Alignment/lane steering, 64-bit bus (Table 8-4); misaligned split | UM §8.3.2.4, PDF 323-325 | tested | `docs/references/BUS_ADDRESSING.md`. `test-core-alignment`. `rtl-chip-lsu` firmware |
| Alignment, 32-bit bus (Tables 8-5..8-7) | UM §8.3.2.5, PDF 325-327 | missing | No 32-bit mode |
| eciwx/ecowx alignment and TT, EAR resource ID on TBST/TSIZ | UM §8.3.2.5.1, PDF 327 | tested | `test-chip-ecxwx` (PID6/603 split, PID7v alignment, DCE off/on) |
| TC[0:1] codes (Table 8-8) | UM §8.3.2.6, PDF 328 | partial | AUD-78: touch loads give TC=00 (should be 01). A dirty castout runs before its fill |
| Address termination: AACK, qualified ARTRY one cycle after AACK | UM §8.3.3, PDF 328-330 | tested | `test-core-bat-bus60x-retry`, `test-chip-mp` |
| Late ARTRY cancels a started data tenure | UM §8.3.3, PDF 329 | tested | BUS_SPEC §scenario ARTRY. `test-core-bat-cached-bus60x-stress`. Not enumerated for every beat (BUS_SPEC remaining work) |
| BR negated / BG ignored after a foreign qualified ARTRY | UM §8.3.3, PDF 329 | tested | `test-chip-pins` (gap_br, gap_ts) |
| Snoop push priority after own ARTRY | UM §8.3.3, §8.4.5, PDF 329, 338 | tested | `test-chip-dcache-coherence` (pushes, pipelined pushes) |
| Data bus arbitration, DBB use | UM §8.4.1-8.4.1.1, PDF 330-331 | tested | `test-chip-mp` shared DBB |
| DBWO reordering (push data ahead of an owed read) | UM §8.4.2, §8.10, PDF 332, 351-354 | tested | `test-chip-dcache-coherence` DBWO coverage. Not between two CPUs |
| Data transfer beats; write data released after the final TA | UM §8.4.3, PDF 332-333 | tested | Chip harness/BFM driver checks |
| Normal termination; DRTRY one cycle after TA | UM §8.4.4.1, PDF 334-337 | tested | `test-chip-mp`, `test-core-bat-cached-bus60x-stress` |
| TEA termination (truncates the burst, DBB release, MC/checkstop) | UM §8.4.4.2, PDF 337 | tested | `test-chip-mp` (TEA on random fill beat, write TEA), `test-core-bat-bus60x-errors`. TEA on instruction fetch is not established at the chip (CHIP_PACKAGE_VERIFICATION:169). `test-core-bus60x-ifetch-error` is core level |
| MEI protocol, WIM handling, snoop responses | UM §8.4.5, PDF 338-340 | partial | `test-dcache`, `test-chip-dcache-coherence`; burst-read snoops flush (AUD-77 fixed) |
| Timing examples (Figs 8-6..8-23) | UM §8.5, PDF 340-346 | partial | BUS_SPEC: 12 figures have bounded cycle tables, 4 are inventory only, none is a full per-pin waveform |
| No-DRTRY mode (DRTRY asserted at HRESET) | UM §8.6.2, PDF 348 | partial | Accepted. The master stays in normal mode, so loads lose the one-cycle-early forward (CHIP_PACKAGE.md §Start-up straps) |
| Reduced-pinout mode (QACK negated at HRESET) | UM §8.6.3, PDF 348-349 | missing | The strap checkstops (`test-chip-pins` case_straps) |
| External interrupts INT/SMI/MCP | UM §8.7.1, PDF 349 | tested | `test-chip-pins`, `test-exception-state` |
| Checkstop (CKSTP_IN, MCP/TEA with ME=0, parity) | UM §8.7.2, PDF 349 | tested | `test-chip-pins`. Clocks are not gated; the core is held in reset (CHIP_PACKAGE.md §Checkstop) |
| HRESET/SRESET to the 0x100 vector, MSR[IP] | UM §8.7.3, PDF 349 | tested | `test-chip-pins` |
| Quiesce QREQ/QACK; snooping stops in quiescence | UM §8.7.4, PDF 350 | tested | `test-chip-power` (doze/nap/sleep) |
| lwarx/stwcx. 32-byte reservation, RSRV, snoop cancel | UM §8.8.1, PDF 350 | tested | `test-chip-pins` RSRV, `test-dcache` (reservation kept or cancelled by snoops) |
| TLBISYNC holds completion past tlbsync | UM §8.8.2, PDF 350 | tested | `test-chip-pins` |
| IEEE 1149.1 interface | UM §8.9, PDF 351 | n/a | Boundary scan (see ch. 7) |
| Interrupt pin synchronisation/latency | UM §8.7, PDF 349 | tested | Two-flop synchronisers (`rtl/ppc603e.sv:175-186`). Pins are taken at the next instruction boundary (CHIP_PACKAGE.md §Exceptions from pins) |

## Chapter 9: Power management (UM PDF 355-360)

| Item | Manual | Status | Evidence |
|---|---|---|---|
| Dynamic power management HID0[DPM] | UM §9.2.1.2, PDF 357 | n/a | stored and read back; no clock gating in FPGA (POWER_MANAGEMENT.md); test-chip-power |
| MSR[POW] + one of HID0 DOZE/NAP/SLEEP selects mode | UM §9.2, PDF 356-357 | tested | ppc_special.sv:571; test-chip-power |
| POW=1 with no mode bit = full power | UM §9.2, PDF 355 | tested | test-chip-power |
| Multiple mode bits rejected | 602UM §9.2, PDF 411 | tested | diagnostic halt (POWER_MANAGEMENT.md "Rejected"); test-chip-power |
| Doze: snooping on, TB/DEC run, wake on INT/SMI/MCP/DEC/SRESET/HRESET | UM §9.2.1.3, PDF 357 | tested | test-chip-power |
| Nap: QREQ/QACK handshake, snoop off after QACK, TB/DEC run | UM §9.2.1.4, PDF 357-358 | tested | test-chip-power |
| Sleep: TB/DEC stopped, wake on INT/SMI/MCP/resets | UM §9.2.1.5, PDF 358 | tested | test-chip-power |
| Sleep PLL disable / SYSCLK removal | UM §9.2.1.5, PDF 358 | n/a | single FPGA clock (POWER_MANAGEMENT.md "Not modelled") |
| Entry/exit latencies ("several processor clocks") | UM §9.2, PDF 357-358 | n/a | modes are stalls; not modelled |
| Software sequence sync; mtmsr POW; isync | UM §9.3, PDF 359 | tested | test-chip-power |
| Wake clears POW via exception entry | UM Table 4-7, PDF 175-176 | tested | test-chip-power |
| Time base enable TBEN pin | UM §7.2.9.7.4, PDF 303 | tested | test-timer, test-core-timer-registers |

## Appendices A and B: instruction set and omissions (UM PDF 361-412)

| Item | Manual | Status | Evidence |
|---|---|---|---|
| A.1/A.2 all 32-bit mnemonics decode | UM App A, PDF 361-376 | tested | ISA_MATRIX.md:5-11 (335 + 147 opt-in + 63 full-decode); test-core-full-decode, test-decode-sweep |
| A.1 rows with full-mask transcription pending (124-130 rows) | UM App A, PDF 361-368 | partial | ISA_MATRIX.md:421, 487-493: metadata incomplete, decode behaviour covered by full decode sweep |
| A.3 functional tables A-3..A-30 | UM App A, PDF 377-387 | tested | ISA_MATRIX.md table; isa.json validator (make check-spec) |
| A.4 form tables A-31..A-45 (I,B,SC,D,X,XL,XFX,XFL,XS,XO,A,M) | UM App A, PDF 388-404 | partial | ISA_MATRIX.md form table: many forms "pending" in spec metadata; RTL decodes all 32-bit forms; AUD-12 (checker covers default profile only) |
| DS, MD, MDS (64-bit) forms | UM App A, PDF 389,404 | tested | illegal per App B; test-decode-sweep |
| Optional 32-bit implemented: fres, frsqrte, fsel, stfiwx, eciwx/ecowx, tlbie, tlbsync, mfsrin/mtsrin | UM App A, PDF 361-406 | tested | sim/spec/isa.json; test-fpu-estimates, test-chip-ecxwx, test-core-tlbie |
| 603e-specific tlbld/tlbli | UM §2.3.6.3.3, PDF 125-126 | tested | test-core-tlb-load |
| B-1 fsqrt, fsqrts, tlbia → illegal | UM Tbl B-1, PDF 407 | tested | tb_core_full_decode.sv:216-218; test-core-full-decode |
| B-2 64-bit instructions → illegal | UM Tbl B-2, PDF 407-408 | tested | ISA_MATRIX.md:476; test-decode-sweep |
| B-3 EC603e: FP → FP unavailable | UM Tbl B-3, PDF 409-411 | tested | ISA_MATRIX.md:11 (no FPU: MSR[FP] stuck 0); test-core-full-decode no-FPU build; tlbia row editorial conflict noted |
| B-4 SPR 280 (ASR) not implemented | UM Tbl B-4, PDF 412 | tested | test-decode-sweep (whole SPR space) |

## Appendix C: 603 differences (UM PDF 413-434)

| Item | Manual | Status | Evidence |
|---|---|---|---|
| 603 variant selection (PVR 0x0003) | UM §C.2, PDF 428 | tested | ppc_pkg.sv cpu_cfg; variant-config targets, test-chip-603 |
| Direct-store XATS protocol (packets 0/1, XATC) | UM §C.1.1-C.1.2.2, PDF 413-420 | tested | rtl/ppc_bus60x_direct_store.sv; test-chip-603 |
| I/O reply operations, reply error -> DSI DSISR[0] | UM §C.1.2.3, PDF 420-421 | tested | DATA_DSI_DIRECT_STORE_ERROR; test-chip-603 |
| Direct-store TEA -> machine check | UM §C.1.2.4, PDF 422 | tested | CPU_VARIANTS.md "TEA"; test-chip-603 |
| Direct-store FP load/store -> alignment | UM §C.2.1.1, PDF 429-430 | tested | tb_chip_603.sv:161 |
| lwarx/stwcx./eciwx/ecowx in T=1 -> DSI DSISR[5] | UM §C.2.1.4, PDF 431 | tested | tb_chip_603.sv:133 |
| lwarx/stwcx. crossing segment boundary -> alignment | UM §C.2.1.1, PDF 430 | untested | no case found |
| dcbt/dcbtst/dcbf/dcbi/dcbst/dcbz/icbi no-op in T=1 | UM §C.2.1.5, PDF 431 | tested | CPU_VARIANTS.md:143; test-chip-603 |
| Direct-store protection key Ks/Kp in packet 0 | UM §C.2.1.3, PDF 430 | tested | ds_tag; test-chip-603 |
| T=1 fetch -> ISI SRR1[3] | UM §C.2.1, PDF 428-429 | tested | CPU_VARIANTS.md:151 |
| CSE single pin, 2-way 8 KB caches (128 sets) | UM §C.1.3, §C.1.5, PDF 424-427 | tested | CPU_VARIANTS.md:55; test-chip-603 |
| PLL_CFG ratios 1:1-4:1 | UM §C.1.4, Table C-4, PDF 424-425 | tested | test-chip-ratios |
| Burst loads not snooped beats 3-4 / 6-8 | UM §C.1.7, PDF 427-428 | partial | documented quirk (CPU_VARIANTS.md:318); no bench seen reproducing it |
| 1:1 with DBG held asserted corrupts writes (erratum) | UM §C.1.8, PDF 428 | n/a | hardware erratum, not modelled |
| No SRR1[KEY] on 603 | UM §C.2, PDF 428 | tested | cfg.has_srr1_key; tb_variant_config.sv:69 |
| No HID1 on 603 | UM §C.2, PDF 428 | tested | cfg.has_hid1 (CPU_VARIANTS.md:218,256) |
| Store 2:2 timing | UM §C.2.2, Table C-5, PDF 431-432 | partial | listed in CPU_VARIANTS.md:295; no 603-specific timing bench found |
| SRU does not execute add/cmp | UM §C.2.3, PDF 432 | n/a | core has no SRU add/cmp path at all (CPU_VARIANTS.md:283) |
| Fetch TEA refetch double-TEA -> checkstop | UM §C.2.4, PDF 433 | missing | not modelled; core takes one machine check per TEA |
| IABR vector (heading says 0x1400) | UM §C.2.5, PDF 433 | tested | uses 0x1300 per body text (CPU_VARIANTS.md:184) |
| IABR same-cache-line spurious match | UM §C.2.5, PDF 433 | n/a | erratum; exact-match compare |
| dcbz/dcbi snoop performance note; dcbz with M=1 | UM §C.2.6, PDF 433-434 | n/a | performance/software note |

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
