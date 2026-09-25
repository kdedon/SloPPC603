# PowerPC 603e CPU scaffold

An executable starting point for the CPU described in [the original design brief](docs/plans/current/ORIGINAL_DESIGN_BRIEF.md). This is an initial implementation, **not a complete or cycle-faithful 603e**. The original reference projects and downloaded manuals are unchanged.

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

- Abstract instruction request/response transport with one outstanding request.
- Six-entry instruction queue, single dispatch lane, one IU reservation station and registered integer execution.
- 32 architectural GPRs and five pending/value-holding rename registers with a latest-writer map and tagged wakeup.
- Five-entry completion queue with ownership-checked tagged finishes and one ordered architectural retirement per cycle.
- `addi`, `addis`, `ori`, `oris`, `xori`, `xoris`, plus `add`, `addc`, `adde`, `addme`, and `addze` with all OE/Rc combinations.
- Register `and`, `andc`, `or`, `orc`, `xor`, `nand`, `nor`, and `eqv` with Rc=0 or Rc=1; record forms commit CR0 with their GPR result.
- `rlwinm` and `rlwnm` with both Rc values, wrapped masks and five-bit rotate counts.
- `slw` and `srw` with both Rc values and six-bit register counts.
- Serialized branches, LR/CTR moves and comparisons to any CR field.
- Aligned big-endian scalar loads/stores (D and indexed), with store authorization and cancelled-load draining.
- Explicit identity-based recovery control with CQ/rename restoration, local cancellation, IQ clearing and fetch draining.
- Ordered diagnostic halt on unsupported instructions; reset restarts the machine.

`DISPATCH_WIDTH=1` is the only supported setting and the default. Other values fail elaboration-time simulation checks. Dual dispatch remains the delivery target. `RESET_PC` defaults to `0xfff00100`; this configurable start address does not implement MSR/reset-vector semantics.

## Work remaining

See the [current plan](docs/plans/current/PLAN.md) for priorities, completion status and remaining work.
