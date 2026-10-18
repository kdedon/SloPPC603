# Cached Dhrystone dispatch-width comparison

Recorded: `make -C sim demo-soc-fpu-model` and unchanged `tb_demo_soc +PROFILE` with the configuration below, source commit `ddf9df12e3b684700fed59e2b2ca5bfc21d6d107`, 2026-10-18.

The retained IU implementation was measured with both caches, fetch hints, LSU pipeline, fetch width 2, branch removal 0, fetch-decode register 0 and immediate mispredict fetch 1. FULL FPU is enabled; the cached assembly therefore uses a 64-bit data path. Only dispatch width changes. Both runs use the same firmware HEX (SHA-256 `9e8788c32815aec52ebbad8ea913ecc3afebf8f242ae3ab2663cf04db4eef2a6`), random-initialization seed 1/reset 2 and the existing pre-image zero-RAM option. No firmware, golden value or cycle assertion was changed.

| Dispatch width | Timed cycles | Timed retirements | Cycles/run printed | DMIPS/MHz printed | Whole-program cycles | Whole-program CPI |
|---|---:|---:|---:|---:|---:|---:|
| 2 | 1,154,918 | 1,180,116 | 577.3 | 0.985 | 2,195,096 | 1.352 |
| 1 | 1,460,923 | 1,180,116 | 730.3 | 0.779 | 2,584,169 | 1.592 |

Both firmware runs pass 23 checks with zero mismatches and exit zero. Bench retirement/performance-counter reconciliation also passes. Strict RTL compilation has zero warnings in both configurations. Host compilation used one worker and effective `-O1`; source, firmware and tool identities were checked throughout both runs. Completed models were removed after preserving the results.

Dual dispatch uses 20.95% fewer cycles in the counted Dhrystone region, or about 26.5% more work per clock for this workload. The equal timed retirement counts support the workload comparison; they do not establish full packet/state identity. The whole-program interval includes boot and reporting, and its retirement counts differ. Only the timed region has equal retirement counts; whole-program CPI is not counted-region CPI.

These are system-clock cycles. `CE_DIV=2` controls video pixel enable and must not divide CPU cycles. There is no measured Fmax for this FULL-FPU cached64 comparison. In this workload a dual-dispatch clock below about 79.1% of the single-dispatch clock would erase the counted-region throughput benefit; a matched physical comparison is required before selecting a hardware profile.

The existing strict integer/FPU identity test is deliberately data-uncached32. Keep that oracle unchanged. Also, cached `ENABLE_FPU=0` selects a 32-bit data path while cached `ENABLE_FPU=1` selects 64 bits; comparing those existing assemblies cannot isolate the cost of FPU presence.

## Reproduction

Use the firmware hash above and the source commit recorded above. The existing model target does not rebuild firmware. For each width, build and run separately from the repository root:

```sh
width=2 # repeat with 1 and a separate build directory
model=build/cached-dhry-w${width}
flags="+define+PPC_DISPATCH_WIDTH=${width} +define+PPC_BRANCH_REMOVAL=0 +define+PPC_FETCH_DECODE_REG=0 +define+PPC_MISPREDICT_FETCH_NOW=1 -GDISPATCH_WIDTH=${width} -GENABLE_FETCH_HINTS=1'b1 -GENABLE_DCACHE=1'b1 -GENABLE_LSU_PIPE=1'b1"
OBJCACHE= make -C sim -j1 demo-soc-fpu-model XRAND=1 \
  BUILD_DIR="$model" PPC_VERILATOR_FLAGS="$flags"
timeout 1800s "sim/$model/demo/model-fpu/Vtb_demo_soc" \
  +verilator+seed+1 +verilator+rand+reset+2 +INTEGER_PAIR_ZERO_RAM \
  +IMAGE="$(pwd)/toolchain/build/demo/dhrystone.hex" \
  +NAME="dhrystone-cached64-dw${width}" +PROFILE
```

The stock target permits two host compiler workers; the measurement used a serial host adapter. Host optimization and compilation worker count do not define simulated instruction cycles. Keep the canonical `tools/verilate` wrapper, including its pinned Verilator optimization workaround, strict warnings and independent firmware checks. This finite program/profile result does not establish ISA conformance or replace merged-batch acceptance.
