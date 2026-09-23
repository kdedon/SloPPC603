# PowerPC 603e CPU scaffold

An executable starting point for the CPU described in [the original design brief](docs/ORIGINAL_DESIGN_BRIEF.md). This is an initial implementation, **not a complete or cycle-faithful 603e**. The original reference projects and downloaded manuals are unchanged.

## Repository layout

This directory is the standalone Git repository. The original parent workspace,
reference checkouts and downloaded manuals are not included. Current capability
and remaining gaps are indexed in [the system scorecard](docs/SYSTEM_COMPLETION.md).

From this repository root, use `make -C sim <target>`. Older workspace examples
below use `make -C ppc603e/sim <target>` from the parent directory. Reference
comparison targets require a separate `dingusppc` checkout alongside this
repository; it is not vendored or registered as a submodule here. Generated
build directories, logs, reports and dated FPGA evidence archives are local
development artifacts and are excluded from version control. Historical
documentation may reference those local archives; they are not shipped here.

## Run

Requires Verilator (tested with 5.020), GNU Make, Python 3, Git and g++ with C++20. The aggregate includes the reference comparison and requires the existing sibling `dingusppc` checkout. No cross compiler, Docker image or external downloads are needed for this workspace regression.

```sh
make -C ppc603e/sim all    # from the workspace root: strict RTL lint + core and focused unit simulations
make -C ppc603e/sim lint
make -C ppc603e/sim test
make -C ppc603e/sim check-spec     # source metadata and checker tests
make -C ppc603e/sim test-recovery  # proposed recovery policy model, not RTL
make -C ppc603e/sim test-recovery-select  # standalone prefix-selector RTL prototype
make -C ppc603e/sim test-core-recovery    # actual-core redirect/drain checks
make -C ppc603e/sim clean-cache          # after builds finish: discard compiler header caches
```

Each Verilator test build can retain large precompiled headers. Run `clean-cache` after a regression round to reclaim those regenerable files while preserving executables, reference traces and manifests. Do not run cleanup concurrently with compilation. `make -C ppc603e/sim clean` removes the entire build directory, including those results.

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

Additional execution units, dual dispatch/retirement, branch prediction/folding, remaining integer ISA, overlapping/unaligned memory operations, remaining supervisor state and architectural exceptions, FPU, full MMU, D-cache/coherency, remaining 60x bus modes, endian modes, CPU variants, and final FPGA timing closure remain unimplemented. The bootstrap now has a cross-toolchain and early Quartus measurement flow; see [build status](docs/BUILD_STATUS.md) for actual validation and limits. There are no stub units that report successful execution for those features.

Start with [the task plan](docs/TASK_PLAN.md); [the agent work queue](docs/WORK_QUEUE.md) records assignments and reviewed progress. [Overall completion](docs/PROGRESS.md) records a weighted estimate after each round. [Architecture](docs/ARCHITECTURE.md) describes the actual RTL and its replacement boundaries; [verification](docs/VERIFICATION.md) describes test coverage and commands. [ISA status](docs/ISA_MATRIX.md), [timing contract work](docs/TIMING_SPEC.md), and [bus contract work](docs/BUS_SPEC.md) distinguish implemented behavior from source-verification work still required.

The next-feature preparation includes [ADD, logical, rotate, shift and compare metadata](docs/ISA_MATRIX.md), [bus encoding](docs/BUS_ENCODINGS.md) and [address decomposition](docs/BUS_ADDRESSING.md) query utilities, [stage observations](docs/STAGE_TIMING.md), and an independently reviewed [recovery proposal/model](docs/RECOVERY_CONTRACT.md). Pending ADD/rotate/shift forms remain outside the implemented RTL instruction set.

A [standalone recovery selector](docs/RECOVERY_SELECTOR.md) now tests the prefix-cut decision in RTL; it is not connected to the CPU.

[Sequential recovery backend work](docs/RECOVERY_BACKEND.md) adds CQ/rename recovery and local execution cancellation. The [full-core recovery control](docs/CORE_RECOVERY.md) now connects accepted redirects to fetch drain and IQ/diagnostic cleanup; the opt-in supervisor path below adds selected exception decoding; the [control/memory lane](docs/CONTROL_MEMORY.md) now supplies branch redirects.

The default core profile supports 168 forms across immediate operations, [register logical](docs/LOGICAL_EXECUTION.md), [record logical](docs/RECORD_LOGICAL.md), [ADD/ADDC](docs/ADD_FLAGS.md), [ADDE](docs/ADDE.md), [ADDME/ADDZE](docs/ADD_UNARY.md), [RLWINM/RLWNM](docs/ROTATE_EXECUTION.md), [control/memory operations](docs/CONTROL_MEMORY.md), [logical shifts](docs/LOGICAL_SHIFTS.md), [arithmetic shifts](docs/ARITHMETIC_SHIFTS.md), [RLWIMI](docs/ROTATE_INSERT.md), [SUBF/NEG](docs/SUBTRACT_NEGATE.md), [SUBFC](docs/SUBFC.md), [SUBFE](docs/SUBFE.md), [SUBFME/SUBFZE](docs/SUBTRACT_UNARY.md), [SUBFIC](docs/SUBFIC.md), [ADDIC/ADDIC.](docs/ADD_IMMEDIATE.md), [ANDI./ANDIS.](docs/AND_IMMEDIATE.md), [CNTLZW/EXTSB/EXTSH](docs/UNARY_LOGICAL.md), [MFCR/MTCRF](docs/CR_TRANSFERS.md), [CR logical operations](docs/CR_LOGICAL.md), [MCRF/MCRXR](docs/CR_STATE.md), [low-word multiply](docs/MULTIPLY_LOW.md), [high-word multiply](docs/MULTIPLY_HIGH.md), [unsigned division](docs/DIVIDE_UNSIGNED.md), [signed division](docs/DIVIDE_SIGNED.md), and [14 load/store update forms](docs/LSU_UPDATE.md). Stateful forms use the [CR/XER foundation](docs/FLAGS_STATE.md) for owner-gated dispatch, captured inputs and atomic GPR/flag commitment.

The [CR/XER contract](docs/CR_XER_CONTRACT.md) defines the next stateful execution slices: masked flag results, one in-flight flag owner, atomic retirement and recovery.

The [bounded 60x bus master](docs/BUS_MASTER.md) connects the scalar data port to 64-bit bus pins with grants, waits, retries and errors. `make -C ppc603e/sim test-core-bus60x-update` runs the full-state update-form program through an independent RAM pin responder. The [unified wrapper](docs/BUS_INTEGRATION.md) also routes instruction fetch through that bus with captured instruction/data attributes and fair arbitration. `make -C ppc603e/sim test-core-bus60x-unified-update` exercises both channels through an independent pin responder. The cached wrapper below adds instruction caching; data caching, snooping, parity and full bus timing acceptance remain open.

The [architectural reference runner](docs/REFERENCE_RUNNER.md) compiles original local DingusPPC instruction handlers and compares real RTL retirement traces. Run `make -C ppc603e/sim test-reference`; this requires the sibling DingusPPC source checkout and g++ with C++20. The register-only corpus matches 8,500 retirements. The full-RAM lane (`make -C ppc603e/sim test-reference-memory`) covers all 168 implemented forms across 9,881 retirements and compares every RAM word. Its flat memory backend and adapter-owned decode boundary are explicit.

[Divider timing and reservation](docs/DIVIDER_TIMING.md) supplies a default 20-cycle DIVW/DIVWU execute interval, configurable to 37 for PID6. The IU blocks replacement until finish or cancellation. A synthesizable radix-4 engine now computes the quotient in 16 iteration steps without a division operator in the RTL. Multiply timing and full cycle conformance remain open.

The [burst line-read master](docs/BUS_LINE_READ.md) transfers an actual four-beat, 32-byte line in critical-doubleword-first order, with waits, retries and errors. It is independently tested and supplies cache refills in the cached-core wrappers below.

The [standalone instruction cache](docs/ICACHE.md) adds 16-KiB physical storage, strict four-way LRU and complete-line refill through the burst master. Run `make -C ppc603e/sim test-icache-bus60x` for the independent physical-bus integration test. The cached-core wrapper below adds core routing; translation and architectural cache controls remain open.

Multiply now uses [conservative multi-cycle reservations](docs/MULTIPLY_TIMING.md): MULLI 3 cycles, MULLW/MULHW 5, MULHWU 6. These are the documented maximum latencies; the operand-dependent mapping remains unresolved. [Seeded reference stress](docs/REFERENCE_STRESS.md), run with `make -C ppc603e/sim test-reference-stress`, varies dependencies, memory aliases and bounded branches while comparing full register/RAM state against original handlers. It builds once for the seed suite and retains reproduction manifests.

The [cached-core wrapper](docs/CACHED_BUS_INTEGRATION.md) connects CPU instruction fetch to the cache and burst master, sharing physical pins with scalar data transfers. `make -C ppc603e/sim test-reference-cached` runs the [all-168-form original-handler comparison](docs/REFERENCE_CACHED.md) through this path. Redirects drain outstanding fetch responses; instruction bus errors remain transport diagnostics.

Standalone [BAT translation](docs/BAT_TRANSLATION.md) and [exception state](docs/EXCEPTION_STATE.md) provide tested interfaces for subsequent MMU and supervisor integration. The service and opt-in CPU integrations below build on these foundations; architectural BAT SPR routing remains open.

The [opt-in supervisor profile](docs/SUPERVISOR_INTEGRATION.md) connects actual CPU execution to MSR/SRR state for SC, RFI, MFMSR and SRR0/SRR1 reads/writes. Set `ENABLE_SUPERVISOR_EXCEPTIONS=1` on `ppc_core`; default decode and reference coverage stay at 168 forms. Selected zero-word and privileged-access events vector through the same serialized path. Unsupported return modes retain an explicit diagnostic; full fault priority, interrupts, MTMSR, MMU and physical-wrapper supervisor routing remain open.

The [BAT service](docs/BAT_SERVICE.md) adds both register banks, committed request/response handling, privilege checks and held translation results. It is a standalone integration service with explicit local reset/write-validation policies. The [managed cached wrapper](docs/ICACHE_CONTROL.md) adds full invalidation and scalar instruction bypass. Changed-code execution requires an accepted pipeline restart after maintenance; decoded HID0/icbi and its cached synchronization integration remain open. [Independent reference profiles](docs/REFERENCE_CACHED.md) cover the managed wrapper with its cache enabled and disabled.

The [serialization profile](docs/SERIALIZATION_INTEGRATION.md) adds exact opt-in ISYNC/SYNC/EIEIO. It drains older implemented work, blocks younger memory effects, and refetches after ISYNC retirement. The [BAT CPU wrapper](docs/CORE_BAT.md) routes real CPU fetch/data requests through startup-programmed IBAT/DBAT mappings, with independent [relocated-address reference comparison](docs/REFERENCE_BAT.md). Its context stays fixed until reset. A separate [software-loaded page TLB](docs/TLB_SERVICE.md) provides two 64-entry banks, selected-way refill, indexed invalidation and page permissions; CPU page-miss routing remains open. These are separate bounded integration profiles.

The opt-in supervisor profile also supports [SPRG0–SPRG3](docs/SPRG_INTEGRATION.md) reads and writes: four complete 32-bit registers, writes at accepted retirement, and privilege checks before allocation. Hard reset clears the bank. This adds eight opt-in forms while the default profile remains at 168. The next [segment-register contract](docs/SEGMENT_REGISTER_CONTRACT.md) is reviewed preparation, not implemented MMU coverage.

A [standalone segment-register bank](docs/SEGMENT_REGISTERS.md) now provides sixteen descriptors with direct/indexed selection, privileged management requests and held internal snapshots. It is not yet connected to CPU segment-register instructions or the TLB.
