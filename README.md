# PowerPC 603e-compatible CPU

A SystemVerilog CPU working toward the machine described in [the original design brief](docs/plans/current/ORIGINAL_DESIGN_BRIEF.md). It is **not yet a complete or cycle-faithful 603e**.

## Repository layout

This directory is the standalone Git repository. The original parent workspace,
reference checkouts and downloaded manuals are not included. Current capability
and remaining gaps are indexed in [the system scorecard](docs/SYSTEM_COMPLETION.md).

From this repository root, use `make -C sim <target>`. Reference
comparison targets require a separate `dingusppc` checkout alongside this
repository; it is not vendored or registered as a submodule here. Generated
build directories, logs, reports and dated FPGA evidence archives are local
development artifacts and are excluded from version control. Historical
documentation may reference those local archives; they are not shipped here.

## Run

Requires Verilator (tested with 5.020), GNU Make, Python 3, Git and g++ with C++20. The aggregate includes the reference comparison and requires the existing sibling `dingusppc` checkout. No cross compiler, Docker image or external downloads are needed for this workspace regression.

```sh
make -C sim all    # from the workspace root: strict RTL lint + core and focused unit simulations
make -C sim lint
make -C sim test
make -C sim check-spec     # source metadata and checker tests
make -C sim test-recovery  # proposed recovery policy model, not RTL
make -C sim test-recovery-select  # standalone prefix-selector RTL prototype
make -C sim test-core-recovery    # actual-core redirect/drain checks
make -C sim clean-cache          # after builds finish: discard compiler header caches
```

Each Verilator test build can retain large precompiled headers. Run `clean-cache` after a regression round to reclaim those regenerable files while preserving executables, reference traces and manifests. Do not run cleanup concurrently with compilation. `make -C sim clean` removes the entire build directory, including those results.

The self-checking simulation compares 768 integer results with a sequential reference model. It checks fetch/retirement order, dependent and repeated GPR writes, r0 semantics, immediate extension, queue pressure, variable memory latency, stalled retirement, reset recovery, and rejection of unsupported opcodes and add forms. A watchdog fails stalled runs. Focused completion and execution benches check tagged ownership, out-of-order finishes, operand wakeup and result backpressure. A full-core stage probe also checks issue/finish/retirement boundaries and same-edge RAW forwarding. These tests establish only the implemented foundation behavior.

## Implemented

A single-issue, big-endian integer core with tagged rename, ordered retirement and precise recovery.
Opt-in profiles add supervisor exceptions, interrupts, time base/decrementer, BAT and segment/page
translation with software TLB refill, and scalar or instruction-cached 60x bus wrappers. Floating point,
data cache, dual dispatch and timing closure are open. See the [system scorecard](docs/SYSTEM_COMPLETION.md)
for accepted behavior and gaps.

`DISPATCH_WIDTH=1` is the only supported setting and the default. Other values fail elaboration-time simulation checks. Dual dispatch remains the delivery target. `RESET_PC` defaults to `0xfff00100`; this configurable start address does not implement MSR/reset-vector semantics.

## Work remaining

See the [current plan](docs/plans/current/PLAN.md) for priorities, completion status and remaining work.
