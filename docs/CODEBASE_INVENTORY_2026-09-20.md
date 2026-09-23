# Processor inventory and MVP estimate — 2026-09-20

Current cross-system percentages, gaps and validation boundaries are tracked in
[SYSTEM_COMPLETION.md](SYSTEM_COMPLETION.md). Historical milestones below retain
their original scope and dates; later feature contracts supersede early limitations.


**Historical audit snapshot.** Subsequent implementation and validation are
tracked in [MVP_EXECUTION_PLAN.md](MVP_EXECUTION_PLAN.md). Its integration,
exception and FPGA results supersede the corresponding initial gaps below;
this document preserves the original inventory and forecast assumptions.

This assessment reviews the checkout at `6f50ccd`, with three parallel source audits covering core execution, memory/supervisor integration, and verification/build delivery. The working tree was clean at the start. No RTL or build changes were made. This report distinguishes implemented hardware, standalone components, recorded validation, and freshly executed checks.

The requested MVP is a **supervisor-capable integer processor with interrupts and MMU**. The estimate below assumes a single-issue, big-endian PID7v-oriented CPU core, compiled integer C firmware, precise resumable exceptions, external/decrementer interrupts, BAT and software-loaded page translation, and a representative Cyclone V fit with reviewed 50 MHz constraints. Board bring-up is excluded, as in the original project scope. FPU, dual dispatch, branch prediction, D-cache/coherency, little endian, other CPU variants, and complete 603e cycle fidelity remain later delivery requirements. This is a proposed MVP boundary, not a change to the original full-603e goal and not a claim of arbitrary operating-system compatibility.

## Overall position

There is a working scalar integer CPU foundation with real program execution, tagged state, recovery, physical instruction/data transport, and instruction caching. The main remaining work is architectural integration: separately tested supervisor and translation components do not yet form one live, software-managed system.

The repository's weighted full-scope estimate is **39.40% after round 40** (`PROGRESS.md`). Approximately **35–40% of the original delivery scope** is a reasonable planning description; it is not independently measured completion or a time-remaining ratio. In particular, the recorded 87% integer/pipeline workstream score should not imply that dual dispatch is nearly finished: only single dispatch and retirement are supported. The latest standalone segment bank adds useful groundwork but does not complete CPU MMU integration.

## Repository index

| Location | Role |
| --- | --- |
| `ppc603e/rtl/` | Active processor RTL, integration wrappers, and source lists; 29 SystemVerilog modules |
| `ppc603e/tb/` | 92 testbench files for units, core behavior, recovery and physical bus integrations |
| `ppc603e/sim/` | Verilator Makefile, architectural reference adapters, generated programs, source-contract checks and recovery models |
| `ppc603e/docs/` | Architecture, task plan, progress and feature-specific contracts; 71 documents before this report |
| `ppc603e/toolchain/` | Pinned cross-toolchain container, startup/linker code, BE/LE compile and reproducibility checks |
| `ppc603e/quartus/` | Early measurement wrapper, Quartus scripts, constraints and historical fit evidence |
| `dingusppc/` | Reference emulator submodule; original integer instruction handlers are used by differential tests |
| `powerpc_fpga/` | Separate small reference design, not the active implementation |
| Root PDFs / `IMPLEMENTATION_PLAN.md` | Source manuals and original full processor target; corrections live in `docs/SOURCES.md` |

The active new processor is under `ppc603e`; the two reference submodules should not be counted as additional completed processor features. Git contains one top-level initial commit, so commit history does not provide a reliable development-velocity estimate.

## Major system inventory

Maturity labels describe executable capability, not percentage of elapsed development time.

| System | Current maturity and evidence | Remaining for chosen MVP | Later full-603e work |
| --- | --- | --- | --- |
| Fetch / dispatch | Working six-entry IQ, one outstanding instruction request, single dispatch | Carry precise instruction-fault identity; integrate privilege/translation changes and restart | Dual fetch/dispatch, documented scheduling |
| Rename / completion / recovery | Strong scalar foundation: five GPR rename slots, five-entry CQ, tagged wakeup/finish, ordered commit, prefix restoration | Resumable fault ownership cleanup and event priority | Multiple producers, dual retirement, remaining rename resources |
| Integer ALU / CR / XER effects | Broad tested arithmetic, Boolean, shifts, rotates, compares and flag updates; default profile totals 168 forms across all supported categories | Software-required missing forms and XER SPR access; establish compiler/ABI contract | Complete instruction set and timing fidelity |
| Multiply / divide | Functional multiply; real radix-4 iterative divide; tested 20/37-cycle divide occupancy | Verify synthesis/timing of actual datapaths | Operand-dependent multiply timing and throughput |
| Branches | Direct, conditional, LR/CTR branches and transfers execute; serialized | Validate handler returns/control-state changes in integrated profile | Prediction, folding, dedicated BPU scheduling |
| Load/store | Aligned BE byte/halfword/word accesses, D/indexed/update forms; store authorization and cancelled-load draining | Architectural alignment/access faults; software-required memory forms; precise MMIO behavior | Pipelining, full unaligned/multiple/string/reservation support as required by full ISA |
| Supervisor / exceptions | Opt-in SC/RFI, MFMSR, SRR0/1, SPRG0–3 and selected program events; opt-in barriers | MTMSR, complete needed SPR state, precise instruction/data/protection faults, priority/restart integration | All documented exception/debug/platform cases |
| Interrupts / timebase | Required asynchronous platform behavior is not implemented end to end | External interrupt, DEC/TB, masks, pending-event rules and handler acceptance | Full SMI/MCP/power-management behavior |
| BAT translation | Tested translator/service and actual CPU wrapper with startup-programmed mappings | Live CPU BAT writes and current MSR privilege/IR/DR context | Complete integration/conformance edge cases |
| Page TLB / segments | Standalone two-bank 64-entry TLB service and sixteen-entry segment bank | Instantiate in CPU translation path; segment instructions, miss SPRs/TGPR, software refill, invalidation and return | Complete page-history/variant behavior |
| 60x bus | Working bounded scalar master and four-beat line-read engine; shared I/D pin wrappers, retry/wait/error tests | Integrate translated attributes and architectural error delivery; freeze supported interface | 32-bit mode, two-address pipelining, snooping, parity and full diagram/timing coverage |
| Instruction cache | Working 16-KiB, four-way physical cache, refill, managed invalidate/bypass and CPU wrapper | Translation/cacheability integration, software-visible maintenance and restart ordering | Exact architectural controls/replacement/timing fidelity |
| Data cache / coherence | Not implemented | May remain absent for this MVP, with explicit uncached memory semantics | Writeback cache, MEI, castout/push, snoops, cache-operation bus effects |
| FPU / FPR / FPSCR | Not implemented in canonical RTL | Excluded; compiler/runtime must use an explicit integer/soft-float profile | Hardware arithmetic, rounding, exceptions, registers and scheduling |
| Endian / variants / power | No end-to-end implementation; compiler artifacts and divider parameter are preparation | Fixed BE/reference variant; defined reset behavior | LE/ILE, 602/603 variants, full power/platform behavior |
| Verification | Extensive bounded unit/core tests and original-handler differential checking | Whole supervisor/MMU program tests, interrupt/fault stress, compiled firmware acceptance | Full ISA/vector/reference, bus and cycle-coverage gates |
| FPGA delivery | Historical bootstrap fit only; current integrated CPU has no fit/timing result | Representative synthesis top, resource measurement and setup/hold closure | Final complete-603e release acceptance |

Default instruction coverage and opt-in supervisor coverage are separate profiles. Counts of 168 default forms and 18 additional opt-in forms do not establish a single supported physical CPU configuration.

## Code-quality findings

**The supported scalar subset is built carefully.** Allocation-owned architectural permissions, slot-plus-generation identities, held request stability, explicit cancellation/drain behavior and atomic commit are sound foundations. Tests include independent bus responders and original DingusPPC opcode handlers, rather than only comparing RTL with a direct transliteration. No confirmed functional defect was found in the sampled supported profile. This was a bounded review, not exhaustive proof.

The principal risks and maintenance findings, in priority order:

1. **No unified supervisor/MMU/cache/bus configuration.** `rtl/ppc_core_bat.sv:83`, `rtl/ppc_core_bus60x.sv:74`, and cached wrappers instantiate the core without exposing its supervisor enable. The TLB and segment bank are separate components. The BAT wrapper uses a fixed startup context. Closing this gap requires architectural event/context design, not simply connecting ports.
2. **Memory faults are terminal rather than resumable.** `rtl/ppc_special.sv:445` onward turns alignment/data errors into fault results; the core ultimately halts (`rtl/ppc_core.sv:329`). Instruction transport errors also produce reset-only diagnostics. Faulting rename ownership must be reclaimed when implementing handler entry and retry. This is a known implementation boundary, not a regression.
3. **Current FPGA feasibility is unmeasured.** `docs/BUILD_STATUS.md:3` says the saved fit predates the tagged execution refactor. That seven-form bootstrap fit used 1,390 ALMs but failed placeholder timing, with worst recorded setup slack −0.360 ns and hold slack −2.235 ns. Those results cannot predict current utilization or Fmax. Moreover, `quartus/ppc_core_measure.sv:26` holds data-memory handshakes inactive and the QSF excludes the integrated bus/cache/MMU path. Merely rerunning that project would still not measure the intended MVP.
4. **Multicycle reservations do not guarantee short hardware paths.** `rtl/ppc_iu.sv:92` implements combinational signed/unsigned 32×32 multiplication. The latency counter does not pipeline those products. Synthesis should determine whether DSP registration or further staging is needed.
5. **Parallel regression can race.** Several Makefile targets compile into the same output directory (for example `sim/Makefile:138` and `:147` share `build/control-memory/obj`). There is no shared prerequisite build graph or `.NOTPARALLEL` protection. Serial execution avoids this risk; unconstrained `make -j` is unsafe.
6. **The aggregate gate is incomplete.** `sim/Makefile:17` declares `all: lint test`, while `check-spec` separately runs metadata consistency and Python suites. Add a clear comprehensive check target. No active-project CI, formal flow or collected HDL coverage was found; selected assertions are present.
7. **Documentation mixes historical and current state.** `docs/ARCHITECTURE.md` still says variable IU latency and RLWIMI are absent in early sections, while later sections describe their implementation. Toolchain documentation still claims branches/load-store are missing. Consolidate the current capability matrix and label retained historical snapshots.

Conservative serialization is a deliberate performance limit. `rtl/ppc_core.sv:230` requires an empty CQ and idle IU for special operations, including branches and memory; one owner also serializes flag dependencies. This is acceptable for the selected first MVP if documented, but does not demonstrate 603e throughput.

## Verification boundary for this audit

Freshly completed:

- All 15 strict lint invocations from the aggregate lint target, including default/enabled core, bus, cache, BAT/TLB/segments and measurement tops.
- `make -C ppc603e/sim check-spec test-recovery`: source-contract checks and **241 Python tests** (204 tools, 22 cosim, 15 recovery), all passing.
- Freshly built iterative-divider test: **524 cases / 11,544 checks**, passing.

The full `all check-spec test-recovery` run was intentionally interrupted during simulation artifact rebuilding after the divider passed. It did not complete, and this report does not claim a fresh full-regression pass. The independent Python/spec run completed afterward. Logs for this session are `/tmp/ppc-inventory-regression.log` and `/tmp/ppc-inventory-spec.log`.

Recorded project evidence includes the all-168-form differential corpus (9,881 retirements and every word of a bounded 256-byte RAM), additional physical/cache/BAT profiles, and seeded stress. This is substantial subset evidence. The adapter owns its legality/dispatch boundary, substitutes flat RAM for the reference MMU, and rejects unsupported exceptions. It does not validate supervisor/MMU faults, arbitrary binaries, self-modifying code, floating point or processor timing. The full project's 10^7-instruction reference gate remains open. No new synthesis or compiled-firmware execution was performed for this audit.

## MVP forecast and acceptance gates

**Planning estimate: 10–16 focused weeks to simulation acceptance; 12–20 weeks to an FPGA-fit/timing-checked core.** Assume one experienced RTL engineer working substantially full time with agent assistance, available tool licenses/containers, a fixed software target, and the restricted MVP profile above. These are judgment ranges, not extrapolations from prior “rounds” or promises of agent execution time. Confidence is moderate-to-low until representative synthesis and the first integrated exception/MMU program pass. Significant timing redesign or a newly required OS/binary compatibility target could push the result beyond 20 weeks.

| Work package | Approximate focused effort | Observable acceptance |
| --- | --- | --- |
| Establish one MVP top, compiled-program harness, full regression entry point and representative synthesis | 1–2 engineer-weeks | Current supported C program reaches a mailbox; integrated resource/timing baseline exists |
| Precise exceptions, live supervisor controls, interrupt/DEC/TB behavior | 3–5 engineer-weeks | User/supervisor transitions, instruction/data faults, asynchronous interrupts, saved state and RFI retry work without younger side effects |
| CPU-connected BAT/segment/page translation and software miss handling | 4–6 engineer-weeks | Firmware writes mappings, services I/D TLB misses, enforces permissions, invalidates and resumes faulting instructions |
| Cache/bus attributes, maintenance and remaining software-profile gaps | 2–3 engineer-weeks | Cached/uncached mappings, changed-code maintenance, barriers and adverse bus conditions work in the same top |
| Integrated stress, compiler workloads, representative fit and timing closure | 2–4 engineer-weeks | Repeatable firmware/regression pass, measured resource use, reviewed constraints and no failing setup/hold paths |

The effort ranges overlap: harness and synthesis work should start immediately, while independent tests can proceed alongside subsystem implementation. They are not simply additive calendar commitments. Adding subagents helps implementation and review but does not divide the critical path by the number of agents.

The first two weeks should reduce uncertainty: choose one small supervisor firmware workload; run compiled code through the final-style wrapper; obtain a representative synthesis result; and demonstrate one precise fault/handler/RFI round trip. Then refine the forecast using measured integration and timing results.

Minimum final demonstration: boot compiled BE integer firmware, install mappings, enter user mode, take and return from a syscall, handle external/decrementer interrupts, service software TLB misses, reject unauthorized instruction/data accesses, invalidate a changed mapping, and resume correctly under memory wait/retry/error injection. Validate architectural state and ensure no younger store survives a fault. FPGA acceptance requires an integrated synthesis configuration, rather than the historical instruction-only measurement harness.

The full original 603e target remains a substantially larger project. FPU, dual dispatch/retirement, data-cache coherence, complete bus modes, endian/variants and cycle fidelity are separate major workstreams. A precise full-target calendar estimate is not defensible before the MVP integration and synthesis baselines; it should be budgeted as additional months rather than a small cleanup phase.
