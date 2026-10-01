# Area survey, 2026-09-30

Dated snapshot. Where the integer CPU spends Cyclone V area, what could shrink it
without changing architecture or cycle behavior, and how much room is left for an FPU.
The survey changed no RTL; [Applied trims](#applied-trims) records the proposals since fitted.

Recorded: `./quartus/chip/build.sh --docker`, `./quartus/translated/build.sh --docker`,
`./quartus/demo/build.sh`, commit 03c594a, 2026-09-30. Quartus 17.0.2 Lite, 5CSEBA6U23I7.
All three exited 0.

| Fit | ALMs | Registers | M10K | DSP | Fmax, slow 100 C | Worst setup / hold |
|---|---|---|---|---|---|---|
| `chip` (`ppc603e` package, virtual pins) | 10,415 | 12,381 | 52 | 2 | 68.54 MHz | +4.975 / +0.116 ns |
| `translated` (core + trace ports) | 11,404 | 13,804 | 52 | 2 | 66.76 MHz | +5.022 / +0.115 ns |
| `demo` (SoC with 2 MiB RAM and framebuffer) | 11,063 | 13,429 | 469 | 2 | 68.22 MHz | +5.342 / +0.097 ns |

Slack is at the 20 ns SDC period. Figures below come from the Fitter "Resource
Utilization by Entity" table of the `chip` fit unless marked otherwise.

## Where the CPU area is

The CPU in the demo SoC (`ppc603e:cpu`) is 9,928 ALMs; in `chip` it is 10,210 ALMs
plus 204 ALMs of measurement wrapper. `translated` is ~990 ALMs larger than `chip`:
its exported retirement trace keeps `pc`, `insn` and deltas alive through the IQ
(+141) and the completion queue (+391), plus a 668-ALM harness. The package top
exports no trace, so synthesis already removes it; the MiSTer build pays nothing for it.

Top entities, `chip` fit. "Self" excludes children listed separately.

| # | Entity | ALMs (self) | Registers | Memory | What it is |
|---|---|---|---|---|---|
| 1 | `ppc_special` | 1,313 | 1,488 | – | SRU: SPRs, LR/CTR, branch, mfspr/mtspr, MMU miss SPRs |
| 2 | `ppc_dcache` | 743 (+240 MLAB tags/LRU/state) | 1,000 | 32 M10K | 16 KiB 4-way D-cache, castout and snoop-push line buffers |
| 3 | `ppc_fifo:iq` | 783 | 1,926 | – | 6-entry IQ, 275-bit entries (fetch packet + predecoded uop) in flops |
| 4 | `ppc_iu` | 569 | 293 | 2 DSP | ALU, rotate, compare, multiplier |
| 5 | `ppc_bat_service` | 477 (+143 translate) | 599 | – | 8 BAT pairs (must be flops: parallel compare) |
| 6 | `ppc_icache` | 445 (+240 MLAB tags) | 361 | 16 M10K | 16 KiB 4-way I-cache |
| 7 | `ppc_tlb_service` | 601 | 502 | 4 M10K | 2 × 64-set TLB, miss and hash state |
| 8 | `ppc_completion` | 482 | 969 | – | 5-entry completion queue, ~250-bit packets |
| 9 | `ppc_core` (glue) | 389 | 325 | – | dispatch, forwarding, recovery glue |
| 10 | `ppc_bat_memory_router` (glue) | 380 | 409 | – | request staging, fault and fill state |
| 11 | `ppc_rename` | 366 | 408 | – | 5 GPR rename values + tags |
| 12 | `ppc_decode:predecode` | 337 | 0 | – | predecode at IQ push |
| 13 | `ppc_divider` | 281 | 184 | – | iterative divider |
| 14 | `ppc_bus60x_cache_master` | 277 | 903 | – | burst master; holds a copy of each castout/push line |
| 15 | `ppc_segment_registers` | 250 | 626 | – | 16 SRs in flops, reset to zero |
| 16 | `ppc_dispatch:station` | 236 | 161 | – | reservation station |
| 17 | `ppc_regfile_gpr` | 129 (+60 MLAB) | 150 | 3 MLAB | GPRs, three 32 × 32 MLAB copies |
| 18 | `ppc_exception_state` | 161 | 125 | – | MSR, SRR0/1 |
| 19 | `ppc_bus60x_two_master` | 131 | 8 | – | outer bus mux |
| 20 | `ppc_micro_tlb` × 2 | 115 + 109 | 384 | – | 4-entry I and D µTLBs |
| – | rest | ~560 | – | – | fetch 103, scalar bus 85, line read 82 (414 regs), flags 77, timer 71, LSU sequence 68, others |

By subsystem: core pipeline 5,444, MMU (router, BAT, TLB, SRs, µTLBs) 2,076,
D-cache 1,126, I-cache 815, BIU 651.

Observations:

- Line buffers dominate the memory-path registers: five 256-bit flop buffers
  (`ppc_dcache` castout and push, their copies in `ppc_bus60x_cache_master`, and
  `ppc_bus60x_line_read` fill assembly), 1,280 registers.
- The IQ is the largest flop array; `ppc_fifo` forces `ramstyle = "logic"`.
- `ppc_ram_sdp_be` (8 byte lanes) is split by Quartus 17 into eight 512 × 8 M10Ks
  per way: 32 M10Ks at 40% fill for the D-cache data, where the I-cache uses 16.
- Structures sized by the 603e (IQ 6, CQ 5, 5 rename buffers, 4-entry µTLBs,
  2 × 64 TLB) are left as they are: resizing changes cycle behavior.
- The completion queue and rename values must stay flops: recovery reads every
  CQ slot in parallel, and operand lookup reads rename values by tag on several ports.
- BAT registers must stay flops (all four entries compared at once); synthesis
  already drops constant reserved bits.

## Proposals

Ordered by savings over risk. None changes architecture or the cycle count of any
instruction. Each needs its focused benches, `check-spec`, lint and a fresh fit.

| # | Proposal | Est. ALMs saved | Other | Risk | Files |
|---|---|---|---|---|---|
| 1 | IQ storage in MLAB; keep `head_q` in flops | 400–480 | −1,650 regs | Medium: the IQ write is the historical critical path (I-cache RAM → decode → `iq|entries`); MLAB write setup must be checked at 66 MHz | `rtl/ppc_fifo.sv` (or a RAM variant used only by the IQ) |
| 2 | D-cache data RAM as four 512 × 16 (2 byte-enable) blocks per way (applied) | 0 | −16 M10K | Low: storage wrapper only | `rtl/ppc_ram_sdp_be.sv` |
| 3 | Segment registers in a 16 × 32 MLAB, read into the existing `rsp_data_q` (applied) | ~200 | −512 regs | Low: the zero reset is a local policy (UM Table 4-8: contents unknown); tests that rely on zeroed SRs need an explicit init or a write-port reset walk | `rtl/ppc_segment_registers.sv`, `docs/SEGMENT_REGISTERS.md` |
| 4 | Line buffers: write the D-cache castout and push buffers as 4 × 64 MLABs and let the burst master read beats from them instead of copying 256 bits | 250–450 | −512 to −1,024 regs | Medium-high: the copy frees the D-cache buffer early; removing it needs an ownership handshake that keeps back-to-back castout timing identical | `rtl/ppc_dcache.sv`, `rtl/ppc_bus60x_cache_master.sv` |
| 5 | Software-only SPRs (SPRG0–3, EAR, RPA, DAR, DSISR) in one MLAB behind the existing single write mux (tried, reverted) | 120–180 | −256 regs | Medium: SPRG reset to zero is architectural (reset walk needed); mfspr read path moves through MLAB | `rtl/ppc_special.sv` |
| 6 | I-cache fill: write beats into the data RAM as they arrive instead of assembling `line_q` | ~100 | −256 regs | High: changes when the line becomes visible; only if refill timing stays identical | `rtl/ppc_bus60x_line_read.sv`, `rtl/ppc_icache.sv` |

CPU total: about 1,100–1,400 ALMs (11–14% of the CPU) and 16 M10K. Proposals 1–3
alone give ~600–680 ALMs at low to medium risk.

Outside the CPU, `soc_perf_counters` costs 383 ALMs (22 × 32-bit counters, 999
registers). The slot counters are mutually exclusive per cycle, so one MLAB
read-modify-write counter bank would save ~250 ALMs; a build parameter could drop
them from a release core. Not recommended now: CPI work depends on them.

Not proposed: smaller µTLBs, IQ, CQ or rename depth (cycle behavior), GPR in
M10K (read latency), dropping the divider or DSP multiplier (instruction latency).

## Applied trims

Proposals 2 and 3 are applied; 5 was tried and reverted. Proposals 1, 4 and 6 are
not attempted.

- **2, D-cache data RAM.** Quartus 17 splits inferred byte-enable RAM into one
  512 × 8 M10K per byte lane, also when the array is written as 16-bit packed
  pairs (tried, still 32 M10K). `ppc_ram_sdp_be` now instantiates `altsyncram`
  with byte enables for synthesis, as `soc_ram_sp_be` does; Verilator keeps the
  original model, so simulation is unchanged. Quartus packs two lanes per block:
  32 → 16 M10K.
- **3, segment registers.** The 16 SRs live in an MLAB with a combinational
  read into the existing `rsp_data_q`; the two writers (direct write, prepared
  commit) are mutually exclusive, so one write port serves both. A 16-bit
  written flag, cleared by `rst_ni`, masks entries not written since reset, so
  every read still returns zero until the first write; no reset walk and no
  added cycle. `docs/SEGMENT_REGISTERS.md` records the storage.
- **5, software-only SPRs.** Only SPRG0–3 qualify: EAR drives the cache-op
  path combinationally, `tlbld` reads RPA in parallel with `mfspr`, and
  exception entry writes DAR and DSISR in the same cycle. SPRG0–3 in a 4 × 32
  MLAB with a written flag cut 156 registers but `ppc_special` grew from
  1,565 to 1,582 ALMs (the flops had packed into ALMs the read mux already
  used), so it was reverted.

Recorded: `./quartus/chip/build.sh --docker` and
`./quartus/report-target-paths.sh chip --docker`, commits 5e86d4b (before) and
af02a68 (after), 2026-09-30. Quartus 17.0.2 Lite; both exited 0.

| `chip` fit | ALMs | Registers | M10K | Fmax, slow 100 C | Worst setup / hold | 66 MHz (15.152 ns) |
|---|---|---|---|---|---|---|
| Before, 5e86d4b | 10,766 | 12,717 | 52 | 65.48 MHz | +4.387 / +0.053 ns | fails: 10 endpoints, −0.121 ns |
| After, af02a68 | 10,597 | 12,182 | 36 | 65.84 MHz | +3.872 / +0.112 ns | fails: 7 endpoints, −0.141 ns |

| Entity | ALMs before → after | Registers before → after | M10K |
|---|---|---|---|
| `ppc_segment_registers` | 241.2 → 87.7 (20 of them MLAB) | 626 → 127 | – |
| `ppc_dcache` | 1,091.3 → 1,095.6 | 1,009 → 999 | 32 → 16 |
| `ppc_special` (unchanged RTL) | 1,565.4 → 1,584.0 | 1,765 → 1,757 | – |
| CPU (`ppc_core_bat_cached_bus60x`) | 10,532.9 → 10,358.8 | 12,423 → 11,888 | 52 → 36 |

The 66 MHz failures before and after are the same D-cache path
(`snp_valid_q` → `rsp_data_q`, plus one LRU MLAB endpoint after); neither
trim touches it, and an intermediate fit (ad99632: this SR change plus the
SPRG change, 32 M10K) met 66 MHz at 67.08 MHz, so the margin there is placement noise. The 20 ns SDC is met
in both fits. The before fit is larger than the survey's 03c594a fit
(10,415 ALMs) because of RTL merged since.

Recorded: `make -C sim lint check-spec` and the focused benches below, commits
5e86d4b and af02a68, 2026-09-30. All pass on both.

- Run with `SIM_ARGS=+verilator+rand+reset+0` on both commits, every summary
  line matches (checks and cycle counts): `test-segment-registers`,
  `test-segment-runtime-service`, `test-segment-runtime-router`,
  `test-core-segment-csr`, `test-core-segment-privilege`, `test-sprg-decode`,
  `test-core-sprg`, `test-exception-state`, `test-core-alignment`,
  `test-core-page-data-exception`, `test-core-page-instruction-exception`,
  `test-core-tlb-miss`, `test-core-tlb-load`, `test-core-dcache`, `test-dcache`,
  `test-biu-dcache-snoop`, `test-chip-dcache-coherence`, `test-chip-pins`
  (1,352 checks, 74,139 cycles), `test-core-bat-cached-bus60x-coherence`,
  `test-core-full-decode`, `test-soc-target-reset`. With
  `+verilator+rand+reset+1` the six core, chip and SR/SPRG benches among them
  also match.
- `test-dcache-mutations`, `test-core-dcache-negative`,
  `test-chip-dcache-coherence-negative`, `test-biu-dcache-snoop-mutations`
  reject every mutation.
- `make -C toolchain rtl-segment rtl-lsu-dcache rtl-chip-mmu-stress rtl-chip-lsu`
  print identical summaries on both commits (segment: 832 retires, 6,089
  cycles; chip-mmu-stress: 774,910 cycles).
- The `xrand-sweep` seeds (1–8, zero, ones) for `soc-target-reset`,
  `core-full-decode` and `chip-pins` pass: 30 runs. The demo and MiSTer
  entries were not run (they need the cross-compiler).

Seeded random initialization (the default `SIM_ARGS`) assigns random values in
design order, so a changed design draws different start values: at 693bcac
(before the SPRG revert) `test-chip-dcache-coherence` cycle counts under the
default seed moved by under 0.5%, and all runs passed.
The benches do not exercise the synthesis `altsyncram` branch of
`ppc_ram_sdp_be`; its behavior rests on the fit and on hardware.

## MiSTer framework share

No fit of the MiSTer core exists on `main`; its build was recorded on another branch
(`docs/MISTER_CORE.md` at 9758fef, commit 64e7929): 17,461 ALMs, 243 M10K, 35 DSP.
Subtracting this survey's demo-SoC fit:

| Part | ALMs | M10K | DSP |
|---|---|---|---|
| MiSTer core total | 17,461 | 243 | 35 |
| CPU (`ppc603e:cpu`, demo fit) | ~9,930 | 52 | 2 |
| SoC glue (target, perf, video, top) | ~1,130 | ~1 + 128 program RAM | 0 |
| `sys/` framework plus MiSTer-only SoC paths (DDR3 framebuffer, screen save) | ~6,400 | ~60 | ~33 |

The framework estimate is a subtraction across two builds and two commits, so treat
it as ±500 ALMs. Most of its DSPs belong to the `ascal` scaler.

## FPU budget

| | ALMs |
|---|---|
| Device | 41,910 |
| MiSTer core today | 17,461 |
| Free today | 24,449 |
| Free at 85% utilization (a practical ceiling for routing and 66 MHz) | ~18,160 |
| With CPU proposals 1–6 | ~19,260–19,560 at 85% |

The standalone FPU (~26.6k ALMs) does not fit beside the core even at 100%
utilization. With every CPU proposal it still needs to shrink by roughly 7,000–8,000
ALMs to land under an 85% device; the FPU datapath, not the integer CPU, is where
that reduction has to come from. DSP (77 free) and M10K (~310 free) are not limiting.
