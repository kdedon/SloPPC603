# CPU variant contract

One elaboration parameter, `CPU_VARIANT`, selects the part the core models:
**PID7v-603e** (default), **PID6-603e**, **EC603e**, **603** or **602**. This
document fixes what differs between them, what main implements today, how the
difference is parameterized, and how each variant is verified. Rounds V0–V3
are implemented ([status](#status)); the "Main:" notes below describe the tree
before V1 unless they say otherwise.

EC603e is the PID7v-603e without the FPU: same PVR, divide latency and HID0,
and every FP instruction takes FP-unavailable. The UM covers both parts; the
shared PVR is a best-effort reading.

## Sources

| Tag | Document | Page convention |
|---|---|---|
| UM | MPC603EUM/AD 11/97, *MPC603e & EC603e User's Manual* (with 603 supplement, Appendix C), per [references/SOURCES.md](references/SOURCES.md) | PDF page, then printed page. Printed `k-n` = PDF `b+n` with b = 40, 78, 126, 158, 196, 246, 276, 308, 354 for chapters 1–9, 412 for Appendix C |
| 602UM | MPC602UM/AD 11/95, *PowerPC 602 RISC Microprocessor User's Manual*, [pinned scan](https://zxgit.org/RomanRom2/awesome-cpus/raw/commit/8115b6c97d547c13037b0cfcb0125d09a3e90543/PowerPC/PowerPC_602/manual.pdf), SHA-256 `77c0fc4a7c4f0cbec82940d45e4dca0186404b46fbb431ce247818af05e6b1e3` (488 pages, text-searchable). Not committed. | PDF page, then printed. Printed `k-n` = PDF `b+n` with b = 36, 76, 152, 182, 222, 288, 320, 352, 410 for chapters 1–9 |
| 602HW | MPC602EC/D 5/96 hardware specifications | Per SOURCES.md |
| PEM | MPCFPE/AD, *Programming Environments Manual* | Architecture only |

The 602 floating-point personality is already specified in
[`docs/FPU_602_CONTRACT.md` on branch `fpu-f0-f1`](https://github.com/kdedon/SloPPC603/blob/83259ce3a429752edd550bb5e5c220a575238a32/docs/FPU_602_CONTRACT.md);
this document does not restate it.

## 1. Differences by block

"=" means same as PID7v-603e. Citations are PDF/printed pages.

### 1.1 Identification

| | PID7v-603e | PID6-603e | 603 | 602 |
|---|---|---|---|---|
| PVR version | `0x0007` | `0x0006` | `0x0003` | `0x0005` |
| PVR revision | from `0x0100`; PID7v bits need level `0x0200` | from `0x0100` | not given | from `0x0100` |
| Source | UM §1.3.1.1 PDF 58 / 1-18; §2.1.1 PDF 84 / 2-6 | same | UM §C.2 PDF 428 / C-16 | 602UM §2.1.1.3 PDF 85 / 2-9 |

Main: `PVR_VALUE = 32'h0007_0200` in `ppc_core.sv`, `ppc_special.sv` and the
wrappers. The reference runner uses `0x00070101` (DingusPPC `MPC603EV`), so
PVR reads differ from the reference today.

### 1.2 Caches

| | PID7v-603e | PID6-603e | 603 | 602 |
|---|---|---|---|---|
| I/D size, ways | 16 KiB, 4-way each | = | 8 KiB, 2-way each | 4 KiB, 2-way each |
| Sets × line | 128 × 32 B | = | 128 × 32 B | 64 × 32 B |
| Index / tag | A20–A26 / PA0–PA19 | = | A20–A26 / PA0–PA19 | A21–A26 / PA0–PA20 |
| Replacement | LRU | = | strict LRU | LRU |
| I-fill | blocked only until critical load; hit under reload | blocked for whole fill | as PID6 (inferred) | not established |
| D-fill | critical DW written and forwarded together | forwarded, then written | as PID6 (inferred) | not established |
| HID0 cache bits | ICE, DCE, ILOCK, DLOCK, ICFI, DCFI, ABE | no ABE | as PID6 (inferred) | DCE, ILOCK, DLOCK, ICFI, DCFI; **no ICE** (bit 16 "not used") |
| Pin | CSE0–1 | = | CSE (one bit) | none |
| Source | UM §1.1 PDF 43–44 / 1-3–1-4; §1.3.3 PDF 66 / 1-26; §3.x PDF 127–131 | UM PDF 44, 127 | UM §C.1.3 PDF 424 / C-12; §C.1.5 PDF 425–427 / C-13–C-15 | 602UM §1.1.1 PDF 40 / 1-4; §3.2.1, §3.3.1 PDF 156, 158 / 3-4, 3-6; §2.1.2.1.1 PDF 88–89 / 2-12–2-13 |

PID7v only: HID0[ABE] (bit 28) broadcasts dcbf/dcbi/dcbst as address-only
transactions; HID0[IFEM] (bit 24) drives the M attribute on instruction fetches
(UM Table 1-3 PDF 58 / 1-18; Table 2-2 PDF 86 / 2-8; PDF 133, 148–150, 288).

602 only: HID0[WIMG] (bits 28–31) are the default attributes in real and
protection-only mode (602UM PDF 89 / 2-13). A miss to a locked cache runs
cache-inhibited (602UM §3.2.3.2 PDF 157 / 3-5), as on the 603e.

Main: `ppc_icache.sv` and `ppc_dcache.sv` take `SET_COUNT` and `WAY_COUNT`
(V4); tag, index and LRU widths follow, and the core tops set them from
`cpu_cfg()`. Lines are 32 bytes. The D-cache forwards the critical double word on the first
beat ([DATA_CACHE.md](DATA_CACHE.md)), which is PID7v behavior. `HID0_WMASK`
in `ppc_pkg.sv` is the PID7v mask.

### 1.3 MMU

| | PID7v-603e | PID6-603e | 603 | 602 |
|---|---|---|---|---|
| I/D TLB | 64 entries, 2-way (32 sets) each | = | = | 32 entries, 2-way (16 sets, EA16–EA19) each |
| BAT | 4 IBAT + 4 DBAT | = | = | 4 + 4; IBATL adds NE (bit 21) and SE (bit 22) |
| Segments | 16 SRs, T=1 → DSI | = | T=1 selects the **direct-store** bus protocol (XATS) | 16 SRs; SR[N] also gates fetch |
| Page protection extras | — | — | — | per-page NE/SE (I) and WE (D) bits; `esa` gating |
| Protection-only mode | — | — | — | HID0[PO] (bit 24): EA=PA, TLB entries hold 32 per-page NE or WE bits |
| SRR1[KEY] on TLB miss | yes | = | **no** | yes (bit 12, WAY bit 14) |
| tlbld / tlbli | yes | = | = | yes; 3& cycles |
| tlbsync | TLBISYNC pin | = | = | no-op, no pin |
| Source | UM PDF 43, 73 / 1-3, 1-33 | = | UM §C.2 PDF 428 / C-16; §C.2.1 PDF 428–431 / C-16–C-19 | 602UM §1.1.1 PDF 38–40 / 1-2–1-4; Table 2-4 PDF 86 / 2-10; §2.1.1.2 PDF 84 / 2-8; §5.1.1 PDF 228–229 / 5-6–5-7; §5.4.4 PDF 255–256 / 5-33–5-34; §5.6 PDF 280+ / 5-58+; PDF 141 / 2-65 |

Main: `ppc_tlb_service.sv` takes `TLB_SETS` from `cfg.tlb_sets` (V6): 32 sets
indexed by `ea[16:12]`, or 16 indexed by `ea[15:12]`; `ppc_bat_translate.sv` has four entries; `ppc_completion.sv`
raises `DATA_DSI_DIRECT_STORE` for T=1; `ppc_exception_state.sv` forms
SRR1[KEY].

### 1.4 Exceptions and MSR

| | PID7v-603e | PID6-603e | 603 | 602 |
|---|---|---|---|---|
| 0x1300 IABR | yes | = | yes (App. C heading says 0x01400; body cites §4.5.15 at 0x1300) | yes |
| 0x1400 SMI | yes | = | = | yes |
| 0x1500 | reserved | = | = | **watchdog** (TCR) |
| 0x1600 | reserved | = | = | **emulation trap**: DP FP, strings, FP tag misses |
| Vector prefix | MSR[IP] ? `0xFFF` : `0x000` | = | = | MSR[IP] ? `0xFFF0` : **IBR** (16 bits), except reset, machine check, IABR use `0x0000`; Table 2-15 covers 0x1000–0x1600 |
| Misaligned single load/store with MSR[LE]=1 | handled in hardware | **alignment exception** | as PID6 (inferred) | alignment exception |
| Misaligned eciwx/ecowx | alignment exception | handled | as PID6 (inferred) | n/a (program exception) |
| Extra MSR bits | — | — | — | AP (bit 8), SA (bit 9) |
| Source | UM §1.3 vector table PDF 72 / 1-32; PDF 44, 70, 162 / 1-4, 1-30, 4-4 | UM PDF 70, 162 | UM §C.2.5 PDF 433 / C-21 | 602UM §2.1.1.1 PDF 83–84 / 2-7–2-8; §2.1.2.4.3 Table 2-15 PDF 98–99 / 2-22–2-23; §4.5.16–18 PDF 218–221 / 4-36–4-39; PDF 67, 186 |

Main: little-endian mode is excluded ([RELEASE.md](RELEASE.md)); `MSR[LE]`
is only copied from ILE on entry. The misaligned-LE split therefore has no
consumer yet. Vectors 0x1500/0x1600 and IBR do not exist. A misaligned
eciwx/ecowx takes the alignment exception on every variant, PID6 included:
splitting an external-control transfer needs LSU and BIU work, deferred to
V13 with the misaligned-LE split (`cfg.misaligned_ecxwx_hw` has no consumer).

### 1.5 Special-purpose registers

| SPR | PID7v-603e | PID6-603e | 603 | 602 |
|---|---|---|---|---|
| HID0 (1008) | Table 2-2 bits incl. IFEM, ABE | no IFEM/ABE | as PID6 (inferred) | EMCP, SBCLK, ECLK, DOZE, NAP, SLEEP, DPM, NHR, DCE, ILOCK, DLOCK, ICFI, DCFI, PO, SL, WIMG |
| HID1 (1009) | PC0–PC3 | = | **absent** | PC0–PC3 |
| IABR (1010) | yes | = | = | yes |
| EAR (282) | yes | = | = | **absent** |
| DMISS/DCMP/HASH1/HASH2/IMISS/ICMP/RPA (976–982) | yes | = | = | yes; RPA redefined in protection-only mode |
| TCR 984, IBR 986, ESASRR 987, SEBR 990, SER 991 | — | — | — | yes |
| SP 1021, LT 1022 | — | — | — | yes (FP tags) |
| Run_N (COP) | 32-bit | 16-bit | — | — |
| Source | UM Tables 2-2, 2-3 PDF 86–87 / 2-8–2-9; PDF 59 / 1-19 | = | UM PDF 48, 428 | 602UM Table 2-6 PDF 87 / 2-11; PDF 82 / 2-6; §2.1.2 PDF 88–99 |

Unimplemented SPRs follow the PEM rule (illegal-instruction program exception)
in every variant.

Main (V3): `ppc_decode.sv` accepts HID1 only when `cfg.has_hid1` and EAR,
eciwx and ecowx only when `cfg.has_ear`; otherwise they take the
illegal-instruction program exception (privileged-instruction in problem
state, as for any undefined supervisor SPR). `ppc_exception_state.sv` writes
SRR1[KEY] only when `cfg.has_srr1_key`. HID0 IFEM and ABE are not stored on
PID6, and the ABE broadcast pin status is tied off there (V2).

### 1.6 Instruction set

| | PID7v-603e | PID6-603e | 603 | 602 |
|---|---|---|---|---|
| lswi/lswx/stswi/stswx | hardware | = | = | **emulation trap 0x1600** |
| lmw/stmw | hardware | = | = | hardware |
| eciwx/ecowx | hardware | = | = (no-op or DSI with T=1) | **program exception** |
| esa, dsa, mfrom | — | — | — | **602 only** (XO 596, 628, 265) |
| FP | DP hardware; fsqrt/fsqrts/tlbia illegal | = | = | SP hardware, DP → 0x1600; see FPU_602 contract |
| Cache ops, T=1 segment | DSI | = | lwarx/stwcx./eciwx/ecowx DSI; dcb*/icbi no-ops | n/a |
| Dispatch | 2 per cycle, SRU executes add/cmp | = | no add/cmp in SRU | **1 per cycle**, 4-entry IQ, no SRU |
| Source | UM App. B PDF 407–410 | = | UM §C.2.1.4–5 PDF 430–431; §C.2.3 PDF 432 | 602UM §1.2.3 PDF 61 / 1-25; §2.3.4.3.6 PDF 126–127 / 2-50–2-51; §2.3.7 PDF 141–144 / 2-65–2-68; App. A PDF 416–428; PDF 212, 316 |

Main: [ISA_MATRIX.md](references/ISA_MATRIX.md) already carries a `Variants`
column (`603:pending_reconciliation`, `602:pending_missing_primary`), generated
from `sim/spec/isa.json`. `ppc_decode.sv` has one table.

### 1.7 Integer and LSU timing

| | PID7v-603e | PID6-603e | 603 | 602 |
|---|---|---|---|---|
| divw/divwu | **20** | 37 | 37 (Table 6-4; App. C silent) | 37 |
| mulli | 2, 3 | = | = | `1, 1-1` |
| mullw | 2–5 | = | = | `1-1, 2-1, 3-1` |
| mulhw | 2–5 | = | = | `1-1, 2-1, 3-1` |
| mulhwu | 2–6 | = | = | `1-1 … 4-1` |
| Store | 2:1 | = | **2:2** | 2:1 |
| Source | UM PDF 45, 74, 251 / 1-5, 1-34, 6-5; Table 6-4 PDF 270–272 / 6-24–6-26 | = | UM §C.2.2 PDF 431–432 / C-19–C-20 | 602UM Table 6-2 PDF 311–313 / 6-23–6-25; Table 6-6 PDF 316–318 |

The 602 multiply entries are in stage notation; read as totals they are one
cycle shorter than the 603e sets for mullw/mulhw. Treat this reading as
best-effort.

Main: `DIV_LATENCY` (default 20, `$fatal` below 17) in `ppc_iu.sv` and every
wrapper; `test-core-divider-timing-pid6` already runs with 37. Multiply latency
is a datapath property ([MULTIPLY_TIMING.md](MULTIPLY_TIMING.md)), with no
parameter.

### 1.8 Bus, pins and clocks

| | PID7v-603e | PID6-603e | 603 | 602 |
|---|---|---|---|---|
| Bus | 60x: 32-bit A, 64/32-bit D, split tenures | = | = + XATS direct-store | **one 64-bit time-multiplexed A/D bus**; T32 selects 32-bit data per transfer |
| Signals absent | — | — | — | ABB, DBB, DBG, DRTRY, DBWO, DBDIS, AP/DP, APE/DPE, TLBISYNC, CSE, XATS |
| Signals added | — | — | XATS | PFADDR0–20 (line-fill address in castout address phase), T32, RESETO |
| TBEN, QREQ/QACK, SMI | yes | = | = | yes |
| Core:bus ratios | 2–6 (halves); no 1:1 or 1.5:1 | 1–4 (halves) | 1, 2, 3, 4 (Table C-4) | 2, 3 |
| Snoop quirk | — | — | burst loads not snooped between beats 3–4 (64-bit) or 6–8 (32-bit) | injected snoops during burst reads |
| Source | UM PDF 44–45 / 1-4–1-5; Ch. 7–8 | = | UM §C.1.1 PDF 413–414; Table C-4 PDF 424–425; §C.1.7–8 PDF 427–428 | 602UM PDF 38, 41 / 1-2, 1-5; §7.1–7.1.1 Fig. 7-1 PDF 321–324 / 7-1–7-4; §8.1.2 PDF 357 / 8-5 |

Main: `rtl/ppc603e.sv` is the 60x package top ([CHIP_PACKAGE.md](CHIP_PACKAGE.md));
the core runs 1:1 from SYSCLK and `PLL_CFG` must be the 1:1 or bypass code.
PID7v lists no 1:1 ratio, so today's default top is a PID7v programming model on
a PID6-style clock. The 602 cannot reuse `ppc603e.sv`: it needs a separate
`ppc602` package top with a mux/demux adapter over the internal bus.

Main (V2): `ppc603e.sv` rejects at elaboration a `PLL_CFG` that is not a code
of the variant (`pll_cfg_legal()`: PID6 UM Table 7-10; PID7v and EC603e the
same without 1:1 and 1.5:1, UM §1.1; 603 Table C-4; 602 602HW Table 11) or
that does not run the bus 1:1 (`pll_cfg_bus_1to1()`). The default
(`pll_cfg_default()`) is PLL bypass `0011` on PID7v and EC603e, their only
code with a 1:1 bus, and `0000` on PID6. The PID7v 4.5:1–6:1 codes are not
in the UM and are rejected. Core wrappers below the pin top keep
`PLL_CFG = 0` for HID1 read-back only.

### 1.9 Power management

| | PID7v-603e | PID6-603e | 603 | 602 |
|---|---|---|---|---|
| Modes | DPM, doze, nap, sleep (HID0 8–11, MSR[POW]) | = | = | = (602UM §9 PDF 411–414) |
| Wake sources | INT, SMI, DEC, reset, MCP | = | = | INT, SMI, MCP, DEC, reset; watchdog |
| Source | UM Ch. 9 PDF 355–360 | = | = | 602UM Ch. 9 |

Main: excluded ([RELEASE.md](RELEASE.md)). Not variant-specific except the 602
watchdog.

## 2. Parameterization plan

### 2.1 Package

`ppc_pkg.sv` holds one enum and one derived record; nothing else selects a
variant. As implemented in V0:

```systemverilog
typedef enum logic [2:0] {
  CPU_PID7V_603E = 3'd0, CPU_PID6_603E = 3'd1, CPU_EC603E = 3'd2,
  CPU_603 = 3'd3, CPU_602 = 3'd4
} cpu_variant_e;

typedef enum logic [1:0] { FPU_NONE, FPU_DP, FPU_602_SP } fpu_kind_e;

typedef struct packed {
  logic [31:0] pvr;
  logic [5:0]  div_latency;
  logic [7:0]  icache_sets, dcache_sets;   // 128 or 64
  logic [2:0]  icache_ways, dcache_ways;   // 4 or 2
  logic [5:0]  tlb_sets;                   // 32 or 16
  logic [31:0] hid0_wmask, hid0_rmask;
  logic [31:0] hid1_rmask;                 // PLL_CFG bits; 0 on the 603
  logic        has_hid1, has_ear, has_srr1_key, has_abe_ifem;
  logic        misaligned_le_hw, misaligned_ecxwx_hw;
  logic        store_two_cycle;            // 603 2:2 stores
  logic        mul_602_timing;
  logic        has_602_ext;                // esa/dsa/mfrom, IBR, TCR, ESA SPRs, AP/SA, PO
  logic        string_emulation_trap;
  logic        has_direct_store;           // 603 XATS on T=1
  fpu_kind_e   fpu;
} cpu_cfg_t;

function automatic cpu_cfg_t cpu_cfg(cpu_variant_e v);  // PID7v defaults, one case
function automatic bit cpu_variant_supported(cpu_variant_e v);
```

The 602 HID0 masks are zero until its layout is encoded (V7); its build is
rejected before then.

Consumers copy the record into a local `localparam` at the top of the module, as
`hdl-design-organization` §2 prescribes. Structural sizes (sets, ways, TLB sets)
go through `generate if` or localparam arithmetic; no file-list selection.

V1 retired `PVR_VALUE` outright (no bench overrode it). `DIV_LATENCY` stays on
`ppc_core` only, default 0 meaning "from the variant"; a nonzero value overrides
it for benches that stretch the divider (`tb_core_interrupt` uses 37). The
wrappers dropped `DIV_LATENCY` and pass `CPU_VARIANT`. `HID0_RESET` stays: it
encodes the wrapper's cache reset mode and is masked by the variant's HID0
mask. `ENABLE_*` profile parameters stay orthogonal.

Verilator cannot set an enum parameter from `-G`, so benches and the lint top
take `parameter int VARIANT` and cast it to `cpu_variant_e`.

### 2.2 Files and behavior per difference

| Difference | Files | Behavior |
|---|---|---|
| PVR | `ppc_special.sv`, wrappers | `cfg.pvr` |
| Divide | `ppc_iu.sv` | `cfg.div_latency`; keep the `$fatal` bound |
| Multiply (602) | `ppc_iu.sv` | one cycle less per class when `mul_602_timing` |
| HID0/HID1/EAR masks | `ppc_pkg.sv`, `ppc_special.sv`, `ppc_decode.sv` | per-variant WMASK/RMASK; absent SPR → illegal |
| ABE/IFEM | `ppc_special.sv`, BIU pin status | tied 0 unless `has_abe_ifem` |
| Cache geometry | `ppc_icache.sv`, `ppc_dcache.sv`, `ppc_dcache_pkg.sv`, `ppc_ram_*` | sets/ways/tag width from cfg; LRU width follows ways; 602 has no ICE |
| CSE width | `ppc603e.sv` | 1 bit for 603 |
| TLB geometry | `ppc_tlb_service.sv`, `ppc_tlb_ram.sv`, miss-derive/HASH | 16 sets, index `ea[15:12]` for 602 |
| SRR1[KEY] | `ppc_exception_state.sv` | forced 0 when `!has_srr1_key` |
| Store 2:2 | LSU issue in `ppc_core.sv` | extra busy cycle when `store_two_cycle` |
| Direct-store (603) | `ppc_completion.sv`, BIU | see open questions; until decided, a 603 build `$fatal`s unless a named `ALLOW_603_NO_DIRECT_STORE` parameter accepts DSI on T=1 |
| Misaligned LE | LSU, alignment path | gated by `misaligned_le_hw` when LE lands |
| Strings (602) | `ppc_decode.sv`, `ppc_lsu_sequence.sv` | decode to emulation trap |
| eciwx/ecowx (602) | `ppc_decode.sv` | program exception |
| esa/dsa/mfrom, AP/SA, IBR, TCR, ESA SPRs | `ppc_decode.sv`, `ppc_special.sv`, `ppc_exception_state.sv`, `ppc_pkg.sv` | new decode entries, MSR mask, vector prefix mux, new exceptions 0x1500/0x1600 |
| 602 NE/SE/WE, protection-only | `ppc_bat_translate.sv`, `ppc_tlb_service.sv`, fetch/data fault paths | new permission bits; PO bypasses PA formation |
| FPU | FPU integration (after FPU work lands) | `cfg.fpu`; see FPU_602 contract |
| 602 bus | new `ppc602.sv`, new mux adapter | separate top, own `chip602_files.f` |
| Dispatch width | future dual-dispatch | forced single for 602 |

### 2.3 Verification matrix

Variant-neutral benches (integer ALU, recovery, rename) run on the default only.
Variant-sensitive checks run on each variant through one make target,
`make -C sim variant-matrix` (part of `regression`). The table is the target
matrix; [status](#status) lists what the target runs today.

| Check | PID7v | PID6 | 603 | 602 |
|---|---|---|---|---|
| `lint` with `-GCPU_VARIANT=` | ✓ | ✓ | ✓ | ✓ |
| `check-spec` (ISA matrix variant column vs decode) | ✓ | ✓ | ✓ | ✓ |
| `test-core-divider-timing` | 20 | 37 | 37 | 37 |
| `test-core-multiply-timing` | ✓ | — | — | 602 table |
| `test-core-full-decode`, `test-decode-sweep` | ✓ | ✓ | ✓ (HID1 illegal) | ✓ (602 table) |
| new SPR mask bench (PVR/HID0/HID1/EAR read-back) | ✓ | ✓ | ✓ | ✓ |
| `test-icache`, `test-dcache`, `test-core-dcache` | ✓ | ✓ | 8 KiB/2-way | 4 KiB/2-way |
| `test-tlb-service`, `test-core-tlb-miss`, `test-core-tlb-load` | ✓ | ✓ | no KEY | 16 sets |
| `test-core-bat*`, `test-core-cache-control` | ✓ | ✓ (no ABE) | ✓ | NE/SE |
| `test-chip-pins`, `test-chip-dcache-coherence` | ✓ | ✓ | CSE 1 bit | 602 top bench |
| `test-reference*` (DingusPPC) | `MPC603EV` | `MPC603E` (`test-reference-pid6`) | `MPC603` | none: self-checking only |
| `make -C toolchain rtl-all` | ✓ | subset | subset | 602 firmware set |
| `release-check` | ✓ | — | — | — |
| Quartus fit | release | — | area only | area + pin top |

DingusPPC has no 602 model; 602 acceptance is manual-derived self-checking
firmware and directed benches. Reference agreement is consistency, not
correctness, for every variant.

## 3. Phased implementation

Each round fits about 100 tool calls and lands with its tests. Order keeps
early rounds away from files that the cache, BIU, snoop and SoC work is
editing; cache and bus rounds wait for those branches to merge.

| Round | Scope | Touches | Depends on |
|---|---|---|---|
| V0 | `cpu_variant_e`, `cpu_cfg_t`, `cpu_cfg()`, elaboration checks; lint for all four values | `ppc_pkg.sv` only | — |
| V1 | Thread `CPU_VARIANT` through `ppc603e.sv` and core wrappers; derive PVR, `DIV_LATENCY`, HID0 masks; resolve the PVR revision; `variant-matrix` target with lint + divider timing | wrappers, `ppc_core.sv`, `ppc_special.sv`, `ppc_iu.sv`, `sim/Makefile` | V0 |
| V2 | PID6 complete: no IFEM/ABE, PID6 reference model in `test-reference`; PLL_CFG legality per variant | `ppc_special.sv`, cosim runner args | V1 |
| V3 | SPR presence: HID1 absent (603), EAR absent (602), SRR1[KEY] (603); ISA-matrix variant column filled for 603 | `ppc_decode.sv`, `ppc_special.sv`, `ppc_exception_state.sv`, `sim/spec/isa.json` | V1 |
| V4 | Cache geometry parameters (sets, ways, tag width, LRU width) at PID7v values, no behavior change | `ppc_icache.sv`, `ppc_dcache*.sv` | cache/BIU/snoop merges |
| V5 | 603 caches (8 KiB/2-way, CSE width), 603 store 2:2, 603 reference runs; direct-store per user decision | caches, `ppc603e.sv`, LSU | V3, V4 |
| V6 | TLB geometry parameter; 602 16-set TLB and HASH/miss derivation | `ppc_tlb_service.sv`, `ppc_miss_derive.sv` | V1 |
| V7 | 602 decode: strings and FP-less DP → 0x1600, eciwx/ecowx → program, esa/dsa/mfrom, MSR AP/SA, 602 SPR storage (TCR/IBR/ESASRR/SER/SEBR, SP/LT) | `ppc_decode.sv`, `ppc_special.sv`, `ppc_pkg.sv` | V3 |
| V8 | 602 exceptions: IBR vector prefix, emulation trap 0x1600, watchdog 0x1500 from TCR | `ppc_exception_state.sv`, `ppc_timer.sv` | V7 |
| V9 | 602 MMU: IBAT NE/SE, TLB NE/SE/WE, esa gating, protection-only mode, HID0[WIMG] defaults | BAT/TLB/fault paths | V6, V7 |
| V10 | 602 caches (4 KiB/2-way, no ICE) and 602 multiply timing | caches, `ppc_iu.sv` | V4 |
| V11 | `ppc602` package top: multiplexed A/D bus, T32, PFADDR, RESETO; pin bench; fit | new files | V10, BIU merge |
| V12 | 602 FPU personality | FPU integration | FPU F-rounds on main |
| V13 | Misaligned-LE split (PID7v hardware, others alignment) | LSU | LE mode on main |
| V14 | Power modes (all variants) | `ppc_special.sv`, clocking | power work in plan |

Rounds V0–V3 and V6–V8 avoid cache and BIU files and can start now.

### Best-effort items

Where the manuals are silent or inconsistent, the variant carries a documented
choice and a test of that choice, not a fidelity claim:

- 603 divide latency (37 from generic Table 6-4) and 603 HID0 bit set (App. C
  names only HID1 as absent).
- PID6/603 cache fill blocking and critical-word write timing (stated only as
  PID7v improvements).
- 602 multiply latencies (stage notation in Table 6-2).
- 602 ICE: §3.2.3 speaks of disabling the I-cache, but Table 2-7 (PDF 89) marks bit 16
  unused.
- 603 IABR vector: App. C heading 0x01400 versus body reference to 0x1300.
- PID7v "cache control instructions require HID0[ABE]" (UM PDF 44): read as
  "broadcast requires ABE", not as an execution gate.
- 602 SP SPR number (Table 2-6 prints 102; resolved as 1021 in the FPU_602
  contract).
- PVR revision fields for all variants (manuals give only starting levels).
- 602 TLB index: Figure 5-9 and two tables give EA16–19 and 16 `tlbie`s; §2.3.6.3.3
  prose and the `tlbld`/`tlbli` pseudocode say EA15–19 and 32. V6 follows the figure.

## Status

| Round | State |
|---|---|
| V0 | Done: `cpu_variant_e`, `cpu_cfg_t`, `cpu_cfg()`, `cpu_variant_supported()`; `ppc_core` fails elaboration for `CPU_603` and `CPU_602` with a message naming the missing work |
| V1 | Done: `CPU_VARIANT` on `ppc603e`, every core wrapper and measurement top, down to `ppc_core` and `ppc_special`; PVR, divide latency and HID0/HID1 read and write masks come from `cpu_cfg()`; PID7v PVR is `0x00070101` in RTL, reference runner, ISA metadata and firmware |
| V2 | Done: PID6 stores neither HID0[IFEM] nor HID0[ABE], and its ABE broadcast pin status is tied off; `ppc603e` rejects a `PLL_CFG` outside the variant's table or not running the bus 1:1, and defaults to PLL bypass on PID7v and EC603e; `test-reference-pid6` runs the reference corpus with the RTL at PID6 against DingusPPC `MPC603E`. Open: PID6 misaligned eciwx/ecowx in hardware (deferred to V13, see §1.4) |
| V3 | Done: `cfg.has_hid1`, `cfg.has_ear` and `cfg.has_srr1_key` gate decode (HID1; EAR, eciwx, ecowx) and SRR1[KEY]; absent SPRs take the illegal-instruction program exception; ISA-matrix 603 column is `legal` for all 335 reviewed forms (UM App. C lists no ISA difference) |
| V6 | Done: `TLB_SETS` (32 or 16, other values fail elaboration) sizes `ppc_tlb_service`, its entry RAMs, the router's micro-TLB set flush and `tlbie`/`tlbld`/`tlbli` set selection; `ppc_core_bat` derives it from `cfg.tlb_sets` unless a bench overrides it. 16 sets index EA16–19 and tag EA4–15 (602UM Figure 5-9; the manual's EA15–19 prose is a 603e copy, see [TLB_SERVICE.md](TLB_SERVICE.md#geometry-parameter)). Miss derivation (IMISS/DMISS, ICMP/DCMP, HASH1/HASH2) and SRR1[WAY] need no change. The 602 NE/SE/WE bits and protection-only mode stay for V9 |
| V4 | Done: `ppc_icache`, `ppc_icache_managed` and `ppc_dcache` take `SET_COUNT` (128 or 64) and `WAY_COUNT` (4 or 2), other values fail elaboration; tag, index, way-valid, dirty/valid state and LRU widths (ways × log2 ways) follow, strict LRU seeds way w at rank w, flash invalidate clears one flop per set, and HID0 lock bits are geometry independent. The core tops take the geometry from `cpu_icache_sets()` etc. unless `ICACHE_SETS`/`ICACHE_WAYS`/`DCACHE_SETS`/`DCACHE_WAYS` override it. CSE carries the way number zero-extended to two bits; the 603 one-bit pin stays for V5 |
| V5, V7 onward | Not started |

EC603e differs from PID7v only in `cfg.fpu`; with no FPU on main both builds
behave the same. DingusPPC distinguishes PID6 from PID7v only by PVR, and
the reference corpus does not read PVR, so the PID6 reference run shows
consistency of the integer path at PID6, not any PID6-specific behavior.
The 603 and 602 still fail elaboration of the core; their SPR presence,
SRR1[KEY] and PLL tables are checked at unit level (`tb_variant_config`,
`tb_exception_tlb_miss`).

Recorded: `make -C sim -j2 ci` (includes `regression`, `variant-matrix` and `cache-geometry`), commit bbe98eb, 2026-09-29.
Pass (V4): 635 PASS lines, 37 compiled-firmware RTL profiles, rtl/ line coverage
76.4% (1771/2319). The default targets run 128 × 4; `cache-geometry` builds the
same benches with `-GSETS -GWAYS` and `cache-geo-reject` checks that 128 × 8,
32 × 2 and 256 × 4 fail elaboration. Per geometry:

| Bench | 128 × 4 | 128 × 2 | 64 × 2 |
| --- | --- | --- | --- |
| `tb_icache` | 60883 checks | 31854 | 17646 |
| `tb_icache_managed` | 267 checks | 267 | 267 |
| `tb_icache_bus60x` | 3805 checks | 3602 | 3602 |
| `tb_dcache` seed 1 (seeds 1–3 run) | 555653 checks | 561881 | 636237 |
| `tb_biu_dcache_snoop` seeds 1–5 | pass | pass | pass |
| `tb_core_dcache` | 219150 checks, 2374 retires | same | same |
| `tb_core_bat_cached_bus60x_coherence` | 2144 checks | 2144 | 2144 |
| `tb_chip_dcache_coherence` seeds 1–3 | pass (189 read bursts, seed 1) | pass (1246) | pass (1246) |

At 128 × 4 the rewritten I-cache benches give the same check counts as before
V4 and the D-cache random streams are unchanged. D-cache and BIU mutations were
rejected at all three geometries when the benches were written; the negative
targets in `ci` run at 128 × 4. This does not establish a 603 or 602 core build,
the 603 CSE pin width, or the 602's missing ICE.

Recorded: `./quartus/translated/build.sh --docker`, `./quartus/chip/build.sh --docker` and `./quartus/report-target-paths.sh <top> --docker` for both, commit bbe98eb, 2026-09-29.
Both fits succeed. Translated: 50 MHz met at every corner (worst setup +5.194 ns,
hold +0.103 ns), slow-corner Fmax 67.54 MHz, 0 failing endpoints at 66 MHz;
10,403 ALMs, 52 RAM blocks. Chip: worst setup +3.305 ns, hold +0.115 ns,
slow-corner Fmax 68.35 MHz, 0 failing endpoints at 66 MHz; 11,426 ALMs, 52 RAM
blocks. Both tops build the 603e geometry, so this shows the parameterization
costs no timing at 128 × 4, not the 2-way fits.

Recorded: `make -C sim -j2 ci` (includes `regression`, `variant-matrix` and `test-tlb-geometry-16`), commit 72c9781, 2026-09-29.
Pass (V6): 601 PASS lines, 37 compiled-firmware RTL profiles, rtl/ line coverage
76.5% (1771/2315, 14 waived arms, 21 runs). Per geometry:

| Bench | 32 sets | 16 sets |
| --- | --- | --- |
| `tb_tlb_service` direct | 876 transactions, 5345 checks | 588, 3617 |
| `tb_tlb_service` + `tlb_vectors.py` oracle | 17364 transactions | 16964 transactions |
| `tb_tlb_prepared_refill` (inv=1 fill=1) | 419 checks | 419 checks |
| `tb_tlb_runtime_fill_router` | 1235 checks | 723 checks |
| `tb_micro_tlb_router` seed 2, 900 random ops | 3519 checks | 3519 checks |
| `tb_core_page_translation` (`ppc_core_bat`) | 928 checks | 928 checks |

The 32-set oracle corpus is byte-identical to the one before V6. `TLB_SETS=64`
fails elaboration. A mutation indexing the 16-set TLB with `EA[16:13]` fails the
direct bench. `tb_core_tlb_load` and `tb_core_tlb_miss` instantiate `ppc_core`
without TLB storage, so geometry does not reach them; they run once. This does
not establish a 602 core build, 602 page protection or protection-only mode, or
the compiled MMU firmware at 16 sets.

Recorded: `./quartus/translated/build.sh --docker` and `./quartus/report-target-paths.sh translated --docker`, commit 72c9781, 2026-09-29.
Fit succeeds; 50 MHz met at every corner (worst setup +5.194 ns, hold +0.103 ns);
slow-corner Fmax 67.54 MHz; at 15.152 ns (66 MHz) 0 failing endpoints. 11,426
ALMs, 52 RAM blocks, 2 DSP blocks. Before this round the variant code did not
analyze in Quartus 18.1 (module-scope `$fatal` generate blocks, `inside`, struct
member select in a parameter); V6 fixed those.

Recorded: `make -C sim -j2 ci` (includes `regression` and `variant-matrix`), commit 9d5b8ff, 2026-09-29.
Pass: 593 PASS lines, 37 compiled-firmware RTL profiles, rtl/ line coverage
76.5% (1771/2315, 14 waived arms, 21 runs). `variant-matrix` adds to the V1
set: `tb_variant_config` 33 checks on each of variants 0–4 (cpu_cfg flags,
HID0 IFEM/ABE masks, all 16 PLL_CFG codes, HID1/EAR/eciwx/ecowx decode);
`tb_exception_tlb_miss` 194 checks on each of 0–4 (SRR1[KEY] cleared on the
603); PLL_CFG `0000` rejected on PID7v, `0100` and `0111` rejected and
`0011` accepted on PID6; `tb_core_full_decode` 8817 checks, 729 retirements
on 0–2 (ABE broadcast seen only on PID7v and EC603e); `test-reference-pid6`
8500 snapshots, 142 encoding groups against DingusPPC `MPC603E` 5b292af4d7b3.
`test-chip-pins` passes with the PLL-bypass default. This does not establish
PID6 misaligned eciwx/ecowx, any 603/602 core build, or non-1:1 clock ratios.

Recorded: `make -C sim -j2 ci` (includes `regression` and `variant-matrix`), commit 22a007b plus an uncommitted edit to this document, 2026-09-29.
Pass: 560 PASS lines, 37 compiled-firmware RTL profiles, rtl/ line coverage
75.8% (1752/2311, 14 waived arms, 21 runs). `variant-matrix`: chip lint on
variants 0 (PID7v), 1 (PID6) and 2 (EC603e); variants 3 (603) and 4 (602)
rejected at elaboration; `tb_core_divider_timing` at 20, 37 and 20 cycles
(58, 92, 58 checks); `tb_core_full_decode` 8816 checks, 729 retirements on
each. This establishes that the variant parameter elaborates, selects PVR,
divide latency and HID0 masks, and leaves the PID7v gates green. It does not
establish PID6 reference agreement (V2) or any 603/602 behavior.

## Open questions

Settled by the [decisions](#decisions-2026-09-28) below; kept for context.

1. PVR revisions: keep `0x00070200` (PID7v level with IFEM/ABE) or match the
   reference's `0x00070101`? Values for PID6 (`0x00060100`?), 603 (`0x00030100`?)
   and 602 (`0x00050100`?).
2. 603 direct-store (T=1, XATS protocol): implement it, or build the 603
   without it behind a named parameter that keeps the 603e DSI?
3. 602 pins: a separate `ppc602` top with the multiplexed bus (V11), or a
   602 programming model on 60x pins only?
4. Clock ratio: every variant runs 1:1 today; PID7v has no 1:1 ratio. Accept
   as a documented deviation, or model the PID7v ratio range?
5. Include EC603e (no FPU, FP-unavailable on every FP form) as a fifth value?
   It is cheap once `cfg.fpu` exists.

## Decisions (2026-09-28)

The user settled the open questions:

- **602 pins:** a separate `ppc602` pin top with the 602's multiplexed 64-bit
  address/data bus.
- **603 direct-store:** implement the XATS protocol for T=1 segments on the 603.
- **PVR:** PID7v reports `0x00070101`, matching the reference model; PID6
  `0x00060101`, 603 `0x00030101`, 602 `0x00050101`, chosen as first revisions.
- **EC603e:** a fifth variant (603e without the FPU; FP instructions take
  FP-unavailable).
- **Clock ratios:** model the core-to-bus clock ratios the silicon supports,
  with the BIU on a bus clock enable, instead of running every variant 1:1.
