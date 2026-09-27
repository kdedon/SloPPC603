# Repository audit

Audit of commit `835f5c7` on 2026-09-26, covering `rtl/`, `tb/`, `sim/`, `toolchain/`,
`quartus/`, `docs/` and `skills/`. Findings were judged for correctness, efficiency and
clarity against the 603e manuals, the feature contracts, [CODING_CONVENTIONS.md](CODING_CONVENTIONS.md),
the `skills/` rules and [AGENTS.md](../AGENTS.md). Each finding was traced in the source before
it was recorded; PLAUSIBLE marks those that need a fit or a run to confirm.

Update the Status column when a finding is fixed: `fixed` with the commit, `wontfix` with
the reason, or `design` when it needs a planned round rather than a local change.

## Baseline results

| Check | Result |
|---|---|
| `make -C sim lint` | pass, 50 Verilator runs, 0 warnings |
| `make -C sim check-spec` | pass, 206 + 22 Python tests, bus spec OK |
| `make -C sim -j regression` | pass, 416 PASS lines, 0 failures, DingusPPC comparison included |
| MVP score ([SYSTEM_COMPLETION.md](SYSTEM_COMPLETION.md)) | 80.81%, recomputes exactly |
| Full-603e score ([FULL_CPU_COMPLETION_AUDIT.md](FULL_CPU_COMPLETION_AUDIT.md)) | 46.29%, recomputes exactly |
| Doc links | 0 broken, 0 leaving the repo, all docs reachable |

No functional bug was found in the supported instruction subset. Architectural deviations
are limited to AUD-02, AUD-13 and AUD-14.

## Findings

Severity: H high, M medium, L low. Category: C correctness, E efficiency, K clarity, S style.

### Ranked

| ID | Sev | Cat | Where | Problem | Rule | Fix | Status |
|---|---|---|---|---|---|---|---|
| AUD-01 | H | E | `rtl/ppc_core.sv:223-314,445-551`, `rtl/ppc_completion.sv:88-127`, `rtl/ppc_rename.sv:135-170` | `retire_ready_i` → commit → redirect search → recovery → `iq_ready`/dispatch, and IQ head → decode → regfile → rename wake → special EA adder, in one cycle. Recorded worst setup −5.324 ns ([INTEGRATED_SYNTHESIS_BASELINE.md](INTEGRATED_SYNTHESIS_BASELINE.md)). Arbitrary-pivot recovery serves only the test `redirect_valid_i` port. | `cpu-decode-control` §2, `cpu-precise-exceptions` §4, `cpu-fmax-critical-paths` | Predecode indexes at IQ push; registered dispatch stage; register branch/isync redirect; put arbitrary-pivot recovery behind a test parameter. | design |
| AUD-02 | M | C | `rtl/ppc_special.sv:712`, `rtl/ppc_exception_state.sv:6` | Reset MSR is 0; UM §4.5.1 gives `0x0000_0040`. Boot-time exceptions vector to `0x0000_0x00` instead of `0xfff0_0x00`. | [SOURCES.md](references/SOURCES.md) line 65 | Pass `RESET_MSR(32'h0000_0040)`; update [EVENT_RESET_CONTRACT.md](EVENT_RESET_CONTRACT.md). | fixed |
| AUD-03 | H | C | `quartus/timer-bat/ppc603e_timer_bat.qsf` | QSF omits `ppc_segment_registers.sv` and `ppc_tlb_service.sv`, which the router instantiates. Lint uses `files.f` and passes; Quartus cannot elaborate; the manifest hashes sources Quartus never compiled. | AGENTS "Recording evidence" | Generate QSF sources from `files.f` or fail the build on mismatch. | fixed (QSF sources generated/checked from files.f; not fitted) |
| AUD-04 | M | C | `sim/Makefile:22`, `toolchain/Makefile` | The 23 `tb_compiled_*` benches are outside `regression` and have no aggregate target, yet the scorecard credits them. | AGENTS "Working rules" | Add an aggregate firmware target that fails loudly without the toolchain. | fixed (make -C toolchain rtl-all; 24/24 pass) |
| AUD-05 | H | E | `rtl/ppc_icache.sv:46,55-57,185-189` | Tags and LRU are reset flop arrays: about 11.9k registers, 8.7k ALMs estimated, 0 MLAB (local map report). The integrated core is 13.7k ALMs. | CODING_CONVENTIONS (no reset of large RAMs), `cpu-cache-design` §1, §6 | Tags in MLAB/M10K; keep only valid bits as flops; walk-clear if zeroed tags are required. | design |
| AUD-06 | H | E | `rtl/ppc_bat_memory_router.sv:213-225,603-619,899-1017` | One serial FSM translates every I and D access: ≥3 cycles to the physical request, ~7 on the page path. The I-cache sits behind it, so hits pay translation and data stalls fetch. | `cpu-mmu-tlb` §1-2 | Registered µTLB with BAT compare per side; keep the serial path for misses and CSR work. | design |
| AUD-07 | M | E | `rtl/ppc_iu.sv:94-96` | Multiplier is combinational on the single-cycle wake loop with no multicycle constraint; signed and unsigned products infer two multipliers. | `cpu-execution-units` §3 | One signed 33×33 product, registered inside the existing latency. | fixed (no fit yet) |
| AUD-08 | M | C | `sim/cosim/run_reference.py:155` and siblings | DingusPPC HEAD is recorded but never checked against the reviewed commit `cf951f69…`; a different checkout changes the oracle silently. | AGENTS "Recording evidence" | Fail unless HEAD matches the pinned commit and the tree is clean; explicit override flag. | fixed (pinned cf951f69; --allow-unpinned-reference) |
| AUD-09 | M | C | `quartus/*.sdc`, `quartus/*/*.sdc` | No SDC calls `derive_clock_uncertainty`; root SDC I/O delays lack `-min`. Reported slack is optimistic. | `hdl-coding-guidelines` SDC minimum, Gate 7 | Add it to all three; add `-max`/`-min` pairs. | fixed (not fitted; recorded slack predates it) |
| AUD-10 | H | C | `docs/plans/current/TASK_PLAN.md:7,180-206,282`, `docs/ARCHITECTURE.md:1-30`, `README.md:1,30-45` | Current docs call segment/page/TGPR/refill work open or scaffold-level, contradicting the scorecard; TASK_PLAN points to stale WORK_QUEUE for status. | AGENTS "Documentation" | Rewrite the summaries or reduce them to scorecard links. | fixed (uncommitted) |
| AUD-11 | M | C | e.g. `docs/REFERENCE_BAT.md:31`, `docs/REFERENCE_CACHED.md:40`, `docs/SYSTEM_COMPLETION.md:572,610,634` | Evidence cites build manifests and source-hash counts; almost no verification record names a commit; some lack command or date. | AGENTS "Recording evidence" | One-line record header per doc (target, commit, date, counts); drop manifest and hash citations. | fixed (uncommitted) |
| AUD-12 | M | C | `sim/tools/isa_check_rtl.py:128-133`, `sim/spec/isa.json` | ISA-vs-RTL check probes the default decode profile only; opt-in forms are never checked and several implemented supervisor/MMU forms are absent from `isa.json`. | CODING_CONVENTIONS (independent checks) | Probe each profile against its status set; add missing forms. | fixed (11 decode profiles probed; 64 opt-in forms added; mtdmiss/mtimiss writes deviate from UM 2.1.2.2, pending decision) |
| AUD-13 | L | C | `rtl/ppc_decode.sv:554-563` | `mftb` legality depends on `ENABLE_RUNTIME_BAT`/`ENABLE_TIMERS`, contradicting the adjacent comment. | 603e UM (MFTB/MFSPR equivalence) | One rule independent of unrelated profiles. | fixed |
| AUD-14 | L | C | `rtl/ppc_exception_state.sv:146`, `rtl/ppc_special.sv:332-356` | `rfi` stores reserved MSR bits 31, 26:22; `mfmsr` hides them but the next exception copies them into SRR1. | `hdl-design-organization` §4 | Apply the implemented-bit mask on every MSR write. | fixed |
| AUD-15 | M | E | `rtl/ppc_icache.sv:145`, `rtl/ppc_fetch.sv` | Ready requires `!rsp_valid_q`: at most one fetch every two cycles. Undocumented. | `cpu-memory-interface` §1 | Accept on the consuming edge with a RAM-output hold register. | design |
| AUD-16 | M | E | `rtl/ppc_regfile_gpr.sv:21-30` | GPR array is reset and has two write ports: all flops, three 32:1 read muxes on the AUD-01 path. | CODING_CONVENTIONS, `cpu-register-files` §1, §4 | Drop reset; retire the update write through one port; MLAB copies. | design |
| AUD-17 | M | E | `rtl/ppc_tlb_service.sv:69,204,236` | TLB array (~7.9 kbit) has two write addresses and an async read, so it cannot infer RAM. PLAUSIBLE: no fit covers it. | `cpu-mmu-tlb` §1 | Funnel writes to one port; RAM wrapper with registered read. | design |
| AUD-18 | M | C | all Verilator builds | No `--x-assign unique --x-initial unique` or random reset seed; a missing reset is invisible. | CODING_CONVENTIONS (independent reset checks) | Add the flags; run core benches with a recorded seed. | partial: X-randomized seed 1 on all sim benches (XRAND=0 disables); cosim reference builds remain zero-initialized |
| AUD-19 | M | K | `AGENTS.md` Commands, `sim/Makefile` | AGENTS says only `test-reference*` need `../dingusppc`, but `regression` includes them; a missing checkout fails as a buried g++ error. | — | Correct the text; add a precheck with a clear message. | fixed |
| AUD-20 | L | S | `sim/cosim/README.md:8-23`, `quartus/README.md:11`, `toolchain/README.md:16`, cosim script defaults, `tb/tb_stage_timing.sv:132` | Leftover `ppc603e/` workspace commands and `/tmp` paths. | AGENTS "Recording evidence" | Repo-relative commands; default scratch to `sim/build/`. | fixed |

### Fetch, decode, dispatch

| ID | Sev | Cat | Where | Problem | Fix | Status |
|---|---|---|---|---|---|---|
| AUD-21 | M | E | `rtl/ppc_dispatch.sv:31-55` | RS wake compare feeds ALU operands and `dispatch_ready`. | Snoop-capture wake; issue next cycle. | design |
| AUD-22 | M | E | `rtl/ppc_fetch.sv:29-44`, `rtl/ppc_fifo.sv:21` | Fetch outputs carry the recovery cone; `rsp_ready_o` reduces to `pending`; `!redirect_i` in `packet_valid_o` is redundant. | Simplify as stated. | fixed |
| AUD-23 | M | K | `rtl/ppc_core.sv:250-269`, `rtl/ppc_decode.sv:536-563`, `rtl/ppc_special.sv` | Privileged-SPR list duplicated in three modules; privilege is SPR bit 4. | Use `spr[4]`; SPR numbers once in `ppc_pkg`. | fixed (privilege = SPR bit 4; SPR numbers in ppc_pkg) |
| AUD-24 | L | C | `rtl/ppc_fetch.sv:86-94` | Discarding a response under `stop_i` still advances the PC; safe only by an unstated invariant. PLAUSIBLE. | Hold PC or assert the invariant. | fixed (sim assertion) |
| AUD-25 | L | E | `rtl/ppc_pkg.sv:62-67` | Each IQ entry carries a 69-bit `page_miss` record including an EA equal to the PC. | Side register for the oldest fault; drop `ea`. | open |
| AUD-26 | L | S | `rtl/ppc_dispatch.sv`, `rtl/ppc_core.sv:466-496` | RS and CQ payloads are loose signals copied field by field; allocation masks applied twice. | Struct payloads; sanitize once. | open |
| AUD-27 | L | K | `rtl/ppc_pkg.sv:150`, `rtl/ppc_decode.sv` | `write_cr0` means "write CR field `cr_field`". | Rename `write_cr_field`. | open |
| AUD-28 | L | K | `rtl/ppc_decode.sv:127-145,287-342` | `addme`/`addze` not normalized like `subfme`/`subfze`; SH passed two ways; long equality-OR chains. | Normalize; flat nested case. | fixed |

### Execution units and register files

| ID | Sev | Cat | Where | Problem | Fix | Status |
|---|---|---|---|---|---|---|
| AUD-29 | L | E | `rtl/ppc_iu.sv:111-168` | Five barrel shifters; SRAW carry via a 32-iteration loop. | One rotator, mask, sign fill. | fixed |
| AUD-30 | L | E | `rtl/ppc_iu.sv:29,91-93` | Second adder for overflow, misnamed `unused_add_low_sum`. | `ov = (a[31]==b[31]) && (sum[31]!=a[31])`. | fixed |
| AUD-31 | L | E | `rtl/ppc_iu.sv:135-140` | `cntlzw` is a 32-deep priority loop on the result mux. | Log-depth LZC. | fixed |
| AUD-32 | L | E | `rtl/ppc_iu.sv:79-86,154-161` | Carry-in and inversion decoded in execute; five enum values compute one add. | Carry select fields in the issue packet. | open |
| AUD-33 | L | E | `rtl/ppc_special.sv:411-416` | `cmp` uses a separate comparator and serializes the machine. | Route through the IU subtract as a renamed op. | design |
| AUD-34 | L | E | `rtl/ppc_divider.sv:62-95`, `rtl/ppc_iu.sv:193` | ~160 datapath bits reset and cleared on cancel. | Reset control only. | fixed |

### Load/store, cache, bus

| ID | Sev | Cat | Where | Problem | Fix | Status |
|---|---|---|---|---|---|---|
| AUD-35 | M | E | `rtl/ppc_icache.sv:93-121,237-244` | Hit way feeds the data RAM address and LRU update in the compare cycle. PLAUSIBLE. | Per-way RAMs with late select, or register the hit. | design |
| AUD-36 | L | E | `rtl/ppc_bus60x_line_read.sv:72-73,157-159,286-293` | Two 256-bit line registers; needless zeroing and datapath reset. | Use `line_work_q` as the response. | fixed |
| AUD-37 | L | C | `rtl/ppc_bus60x.sv:243-249`, `rtl/ppc_bus60x_line_read.sv:202-208` | AACK in the TS cycle is accepted, not flagged (BUS_SPEC Figure 8-6). | Protocol error in the TS cycle. | fixed |
| AUD-38 | L | C | `rtl/ppc_icache_managed.sv:55,194-197` | `default:` enters `MANAGED_INVALID`, which has no exit; busy stays high. | Return to `MANAGED_RUN` with sticky error. | fixed |
| AUD-39 | M | K | `rtl/ppc_core_cached_bus60x.sv:291-387`, `rtl/ppc_core_cached_bus60x_managed.sv:348-444`, `rtl/ppc_core_bat_cached_bus60x.sv:520-616` | ~100 identical lines of 60x pin glue in three wrappers; pins as loose ports. | Pin structs; one two-master module. | fixed |
| AUD-40 | L | S | `rtl/ppc_bus60x.sv:156-163`, `rtl/ppc_bus60x_line_read.sv:118-121`, `rtl/ppc_icache.sv:46,61-63,110-112` | TT/TSIZ codes and cache widths are literals. | Package enums; `$clog2` widths. | fixed |
| AUD-41 | L | S | `rtl/ppc_bus60x_line_read.sv:63`, `rtl/ppc_bus60x_master_select.sv:24` | Dead enum states. | Remove. | fixed |

### MMU

| ID | Sev | Cat | Where | Problem | Fix | Status |
|---|---|---|---|---|---|---|
| AUD-42 | M | E | `rtl/ppc_bat_memory_router.sv:1026`, `rtl/ppc_special.sv:606-617` | True miss always reports SRR1.WAY=0, so the TLB acts direct-mapped (documented in [CPU_TLB_MISS.md](CPU_TLB_MISS.md)). | Per-set LRU bit returned in the capsule. | design |
| AUD-43 | L | E | `rtl/ppc_bat_translate.sv:54-110` | Bank config and overlap checks run per translation but cannot fire there. | Validate on write only; AND-OR result. | fixed (VALIDATE_BANK parameter; one-hot AND-OR select) |
| AUD-44 | L | C | `rtl/ppc_bat_translate.sv:116-119` vs `rtl/ppc_tlb_service.sv:150-151` | BAT PP=00 with G=1 halts; the page path prioritizes and raises ISI (documented terminal in [LIVE_BAT_CONTEXT.md](LIVE_BAT_CONTEXT.md)). | Same protection-before-guarded rule. | fixed (PP=00 with G=1 raises protection ISI) |
| AUD-45 | L | K | `rtl/ppc_bat_memory_router.sv:1222-1234` | Lint sinks list used signals; comment false. | Sink only unused fields. | fixed |
| AUD-46 | M | S | router 206-211 and literals; `ppc_bat_service.sv:47-52`; `ppc_tlb_service.sv:41-43`; `ppc_segment_registers.sv:211-214` | Request kinds re-declared and hard-coded across four modules. | Package enums. | fixed |
| AUD-47 | L | S | router 159-205; `rtl/ppc_core_bat.sv:136,251,261` | Ports `logic [68:0]`/`[2:0]` although `page_miss_t` and fault enums exist. | Typed ports, named struct literal. | fixed |
| AUD-48 | M | K | router 273-416,603-608,867-886 | Five near-identical offer equations and six owner flops for one exclusive owner. | One `owner_t`, one priority encoder. | open |
| AUD-49 | L | K | router 931-940,1027-1045,1118 | Sticky fault outputs set by recoverable misses; `fault_miss_o` disagrees with `page_miss_o`. | Set on fatal paths only. | fixed (sticky outputs fire on diagnostics only) |

### Exceptions and completion

| ID | Sev | Cat | Where | Problem | Fix | Status |
|---|---|---|---|---|---|---|
| AUD-50 | M | S | `rtl/ppc_special.sv:757-1128,139-145` | One `always_ff` owns ~60 state elements across branch, SPR, LSU, MMU CSR and exceptions; `S_BAT_*` reused for other MMU ops. | Split by concern; rename `S_MMU_*`. | design |
| AUD-51 | M | S | `rtl/ppc_special.sv`, `rtl/ppc_exception_state.sv:62`, `rtl/ppc_timer.sv` | No MSR/SRR1/DSISR/SDR1 definitions with masks; `0x87c0ffff` duplicated; `rfi_prospective` re-implements `rfi_msr`. | Package structs and masks; one `rfi_msr()`. | partial: MSR masks, MSR_RESET and one rfi_msr() in ppc_pkg; DSISR/SDR1/SPRG write masks remain |
| AUD-52 | L | S | `rtl/ppc_exception_state.sv:48-59,214-219`, `rtl/ppc_special.sv:358-369` | Event codes duplicated as localparams; ISI cause compared to raw integers. | Package enum; typed port. | fixed |
| AUD-53 | L | C | `rtl/ppc_special.sv:1115-1121` | Unsupported exception result redirects to 0 in synthesis (unreachable today). | Diagnostic halt. | fixed (halt not yet on core halted_o) |
| AUD-54 | L | E | `rtl/ppc_special.sv:392-394,461,503`, `rtl/ppc_completion.sv:118-169`, `rtl/ppc_core.sv:131-133,445`, `rtl/ppc_fifo.sv`, `rtl/ppc_fetch.sv`, `rtl/ppc_dispatch.sv` | `rst_ni` in combinational outputs (recorded −0.084 ns hold path); raw IRQ pin gates dispatch. | Drop reset terms where state is reset; register the IRQ. | partial: fifo/fetch/dispatch/core reset terms removed; special, completion and IRQ registration remain |
| AUD-55 | L | K | `rtl/ppc_special.sv:147` | Live micro-op named `unused_uop_q`. | Rename `uop_q`. | fixed |
| AUD-56 | L | S | `rtl/ppc_special.sv:724,738`, `rtl/ppc_exception_state.sv:24-26,289`, `rtl/ppc_core.sv:3,195` | Dead ports and parameters (`rfi_pending_exception_i`, `result_is_exception_o`, `DISPATCH_WIDTH`). | Remove. | fixed |

### Whole RTL

| ID | Sev | Cat | Where | Problem | Fix | Status |
|---|---|---|---|---|---|---|
| AUD-57 | L | S | all `rtl/*.sv` | No `` `default_nettype none``; `unique case` without `default:` in `ppc_icache.sv:81-90`, `ppc_bus60x_line_read.sv:88-93`. | Add both. | partial: case defaults added; default_nettype remains |
| AUD-58 | L | S | `rtl/ppc_flags.sv:120-123`, `rtl/ppc_rename.sv:138-139,150-153` | Assertions not under `translate_off`. | Guard them. | fixed |
| AUD-59 | L | S | ~20 module headers and comments (e.g. `ppc_core.sv:1`, `ppc_fetch.sv:1`, `ppc_special.sv:1-2,161,163`, router 1-3) | "does not…", "scaffold", "future hash unit", doc-file references. | Trim to current behavior (`concise-writing`). | partial: bus/cache, execution, front-end, exception and MMU comments trimmed |
| AUD-60 | L | S | `rtl/ppc_core.sv:283,322-353`, `rtl/ppc_flags.sv:62` | Raw MSR/XER bit indices and masks. | Named package constants. | partial: XER constants in ppc_pkg; MSR TGPR bit local to ppc_core |

### Tests and tooling

| ID | Sev | Cat | Where | Problem | Fix | Status |
|---|---|---|---|---|---|---|
| AUD-61 | M | E | `sim/Makefile` (34 `tb_core_add_recovery` targets), cosim runners | Stimulus-only parameters rebuild the full core 34 times; 148 full-core builds; DingusPPC runner built six times. | Plusarg case selection; shared runner prerequisite. | fixed (one add-recovery binary; shared reference runner) |
| AUD-62 | M | E | `tb/tb_compiled_*.sv`, 10 benches with private `ta_n` responders | Firmware harness copied ~20 times; responders bypass `tb/bfm/`. | Shared harness; move to the BFM. | open |
| AUD-63 | L | K | `toolchain/run-rtl-smoke.py:103-197`, `tb/tb_core_add_recovery.sv:4-21` | Profile selection by overlapping flags and ternary chains. | One table; enum with `$fatal` on conflicts. | fixed |
| AUD-64 | L | C | `sim/tools/test_isa.py`, `sim/tools/test_bus_scenarios.py`, `sim/tools/*_family.py` | ~120 asserts check prose in JSON yet count as evidence; "independent" family models feed no RTL bench. | Wire models into vectors or relabel; stop counting prose asserts. | fixed (prose asserts in *Prose classes; rotate model drives tb_rotate_execution; other models relabeled) |
| AUD-65 | L | S | `quartus/build.sh:7`, `quartus/collect-reports.sh:10,33` | Mutable image tag; undeclared `rg`; hardcoded pin count. | Pin digest; use grep. | fixed |

### Docs and skills

| ID | Sev | Cat | Where | Problem | Fix | Status |
|---|---|---|---|---|---|---|
| AUD-66 | M | K | `docs/SYSTEM_COMPLETION.md:144-157` | Round table stops at 74%; later rounds exist only as prose duplicated in the MVP plan. | One row per round to the current one. | fixed (uncommitted) |
| AUD-67 | L | K | `docs/plans/current/MVP_EXECUTION_PLAN.md:403-424` | Waves lack status markers; Wave 5 reads as future work. | Status line per wave. | fixed (uncommitted) |
| AUD-68 | M | K | `.agents/skills/` (untracked) | Real copy of `skills/`; will drift. | Symlink to `../skills` or remove. | open |
| AUD-69 | L | C | `skills/hdl-coding-guidelines/references/source/02-source-map.md:117`, `17-era-faithful-microarchitecture.md:347`, `32-arithmetic-patterns-and-operator-cost.md:232`, `skills/mister-framework/references/source/30-sdram.md:289` | URLs not pinned to a full commit. | Pin 40-character SHAs. | fixed (uncommitted) |
| AUD-70 | L | S | `docs/SYSTEM_COMPLETION.md:602,621`, `docs/plans/current/MVP_EXECUTION_PLAN.md:711,722`, `docs/FPU_REUSE_ASSESSMENT.md:3` | Agent names ("Sol", "GPT-6 Sol") in records. | Delete. | fixed (uncommitted) |
| AUD-71 | L | S | `docs/SYSTEM_COMPLETION.md:404-405,548-549`, `docs/plans/current/MVP_EXECUTION_PLAN.md:681-728` | Missing spaces ("MVP80.81%"). | Restore. | fixed (uncommitted) |
| AUD-72 | L | S | `skills/concise-writing/SKILL.md:8-18` | Rules repeated; no checklist; README row omits docs. | Merge bullets; add checklist. | fixed (uncommitted) |
| AUD-73 | L | K | `AGENTS.md` "Recording evidence" | Bans citing `build/`, but reproduction commands legitimately write there. | Separate evidence citations from command output directories. | fixed (uncommitted) |
