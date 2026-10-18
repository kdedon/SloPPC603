# Cached Dhrystone dispatch-width comparison

Recorded: `make -C sim demo-soc-model demo-soc-fpu-model` and unchanged `tb_demo_soc +PROFILE` with the configuration below, source commit `ddf9df12e3b684700fed59e2b2ca5bfc21d6d107`, 2026-10-18.

The retained IU implementation was measured with both caches, fetch hints, LSU pipeline, fetch width 2, branch removal 0, fetch-decode register 0 and immediate mispredict fetch 1. Two separate cohorts use CPU-only/cache32 and FULL-FPU/cache64. Only dispatch width changes within each cohort. All four runs use the same firmware HEX (SHA-256 `9e8788c32815aec52ebbad8ea913ecc3afebf8f242ae3ab2663cf04db4eef2a6`), random-initialization seed 1/reset 2 and the existing pre-image zero-RAM option. No firmware, golden value or cycle assertion was changed.

| FPU / data width | Dispatch width | Timed cycles | Timed retirements | Cycles/run printed | DMIPS/MHz printed | Whole-program cycles | Whole-program CPI |
|---|---:|---:|---:|---:|---:|---:|---:|
| Off / 32 | 2 | 1,076,918 | 1,180,116 | 538.3 | 1.057 | 2,066,704 | 1.273 |
| Off / 32 | 1 | 1,396,913 | 1,180,116 | 698.3 | 0.814 | 2,481,494 | 1.529 |
| FULL / 64 | 2 | 1,154,918 | 1,180,116 | 577.3 | 0.985 | 2,195,096 | 1.352 |
| FULL / 64 | 1 | 1,460,923 | 1,180,116 | 730.3 | 0.779 | 2,584,169 | 1.592 |

All four firmware runs pass 23 checks with zero mismatches and exit zero. Bench retirement/performance-counter reconciliation also passes. Strict RTL compilation has zero warnings in all four configurations. Host compilation used one worker and effective `-O1`; source, firmware and tool identities were checked throughout all four runs. Completed models were removed after preserving the results.

Dual dispatch uses 22.91% fewer counted cycles in CPU-only/cache32 (29.71% more work per clock), and 20.95% fewer in FULL-FPU/cache64 (26.50% more work per clock). The equal timed retirement counts support the workload comparison; they do not establish full packet/state identity. The whole-program interval includes boot and reporting, and its retirement counts differ. Only the timed region has equal retirement counts; whole-program CPI is not counted-region CPI.

These are system-clock cycles. `CE_DIV=2` controls video pixel enable and must not divide CPU cycles. There is no matched DW1/DW2 Fmax comparison here. In this workload a dual-dispatch clock below about 77.1% of the single-dispatch clock in CPU-only/cache32, or 79.1% in FULL-FPU/cache64, would erase its counted-region throughput benefit. A matched physical comparison is required before selecting a hardware profile. These are demo-SoC measurements; they do not establish board memory latency or game frame rate.

The existing strict integer/FPU identity test is deliberately data-uncached32. Keep that oracle unchanged. Also, cached `ENABLE_FPU=0` selects a 32-bit data path while cached `ENABLE_FPU=1` selects 64 bits; comparing those existing assemblies cannot isolate the cost of FPU presence.

## Reproduction

Use the firmware hash above and the source commit recorded above. The existing model target does not rebuild firmware. For each FPU setting and width, build and run separately from the repository root:

```sh
width=2 # repeat with 1
fpu=1 # repeat with 0
if [ "$fpu" = 1 ]; then
  target=demo-soc-fpu-model; binary=model-fpu; dmem=64
else
  target=demo-soc-model; binary=model; dmem=32
fi
model=build/cached-dhry-fpu${fpu}-w${width}
flags="+define+PPC_DISPATCH_WIDTH=${width} +define+PPC_BRANCH_REMOVAL=0 +define+PPC_FETCH_DECODE_REG=0 +define+PPC_MISPREDICT_FETCH_NOW=1 -GDISPATCH_WIDTH=${width} -GENABLE_FETCH_HINTS=1'b1 -GENABLE_DCACHE=1'b1 -GENABLE_LSU_PIPE=1'b1"
OBJCACHE= make -C sim -j1 "$target" XRAND=1 \
  BUILD_DIR="$model" PPC_VERILATOR_FLAGS="$flags"
timeout 1800s "sim/$model/demo/$binary/Vtb_demo_soc" \
  +verilator+seed+1 +verilator+rand+reset+2 +INTEGER_PAIR_ZERO_RAM \
  +IMAGE="$(pwd)/toolchain/build/demo/dhrystone.hex" \
  +NAME="dhrystone-cached${dmem}-dw${width}" +PROFILE
```

The stock target permits two host compiler workers; the measurement used a serial host adapter. Host optimization and compilation worker count do not define simulated instruction cycles. Keep the canonical `tools/verilate` wrapper, including its pinned Verilator optimization workaround, strict warnings and independent firmware checks. This finite program/profile result does not establish ISA conformance or replace merged-batch acceptance.
