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
| AUD-01 | H | E | `rtl/ppc_core.sv:223-314,445-551`, `rtl/ppc_completion.sv:88-127`, `rtl/ppc_rename.sv:135-170` | `retire_ready_i` → commit → redirect search → recovery → `iq_ready`/dispatch, and IQ head → decode → regfile → rename wake → special EA adder, in one cycle. Recorded worst setup −5.324 ns ([INTEGRATED_SYNTHESIS_BASELINE.md](INTEGRATED_SYNTHESIS_BASELINE.md)). Arbitrary-pivot recovery serves only the test `redirect_valid_i` port. | `cpu-decode-control` §2, `cpu-precise-exceptions` §4, `cpu-fmax-critical-paths` | Predecode indexes at IQ push; registered dispatch stage; register branch/isync redirect; put arbitrary-pivot recovery behind a test parameter. | fixed (integrated meets 50 MHz setup at all corners; 54.37 MHz; 66 MHz is the aspirational target) |
| AUD-02 | M | C | `rtl/ppc_special.sv:712`, `rtl/ppc_exception_state.sv:6` | Reset MSR is 0; UM §4.5.1 gives `0x0000_0040`. Boot-time exceptions vector to `0x0000_0x00` instead of `0xfff0_0x00`. | [SOURCES.md](references/SOURCES.md) line 65 | Pass `RESET_MSR(32'h0000_0040)`; update [EVENT_RESET_CONTRACT.md](EVENT_RESET_CONTRACT.md). | fixed |
| AUD-03 | H | C | `quartus/timer-bat/ppc603e_timer_bat.qsf` | QSF omits `ppc_segment_registers.sv` and `ppc_tlb_service.sv`, which the router instantiates. Lint uses `files.f` and passes; Quartus cannot elaborate; the manifest hashes sources Quartus never compiled. | AGENTS "Recording evidence" | Generate QSF sources from `files.f` or fail the build on mismatch. | fixed (QSF sources generated/checked from files.f; not fitted) |
| AUD-04 | M | C | `sim/Makefile:22`, `toolchain/Makefile` | The 23 `tb_compiled_*` benches are outside `regression` and have no aggregate target, yet the scorecard credits them. | AGENTS "Working rules" | Add an aggregate firmware target that fails loudly without the toolchain. | fixed (make -C toolchain rtl-all; 24/24 pass) |
| AUD-05 | H | E | `rtl/ppc_icache.sv:46,55-57,185-189` | Tags and LRU are reset flop arrays: about 11.9k registers, 8.7k ALMs estimated, 0 MLAB (local map report). The integrated core is 13.7k ALMs. | CODING_CONVENTIONS (no reset of large RAMs), `cpu-cache-design` §1, §6 | Tags in MLAB/M10K; keep only valid bits as flops; walk-clear if zeroed tags are required. | fixed (tags/valid/LRU in MLAB, data in per-way M10K; synthesis 8,695 -> 1,072 ALMs) |
| AUD-06 | H | E | `rtl/ppc_bat_memory_router.sv:213-225,603-619,899-1017` | One serial FSM translates every I and D access: ≥3 cycles to the physical request, ~7 on the page path. The I-cache sits behind it, so hits pay translation and data stalls fetch. | `cpu-mmu-tlb` §1-2 | Registered µTLB with BAT compare per side; keep the serial path for misses and CSR work. | fixed (4-entry registered micro-TLB per side; 64 page fetches 641 -> 137 cycles; data no longer blocks fetch) |
| AUD-07 | M | E | `rtl/ppc_iu.sv:94-96` | Multiplier is combinational on the single-cycle wake loop with no multicycle constraint; signed and unsigned products infer two multipliers. | `cpu-execution-units` §3 | Iterative 33×9 product into a registered accumulator; latency from rB bytes ([MULTIPLY_TIMING.md](MULTIPLY_TIMING.md)). | fixed (translated fit recorded) |
| AUD-08 | M | C | `sim/cosim/run_reference.py:155` and siblings | DingusPPC HEAD is recorded but never checked against the reviewed commit `cf951f69…`; a different checkout silently changes the comparison reference. | AGENTS "Recording evidence" | Fail unless HEAD matches the pinned commit and the tree is clean; explicit override flag. | fixed (tracks latest DingusPPC; runs record HEAD/dirty and print the log range since LAST_VERIFIED) |
| AUD-09 | M | C | `quartus/*.sdc`, `quartus/*/*.sdc` | No SDC calls `derive_clock_uncertainty`; root SDC I/O delays lack `-min`. Reported slack is optimistic. | `hdl-coding-guidelines` SDC minimum, Gate 7 | Add it to all three; add `-max`/`-min` pairs. | fixed (not fitted; recorded slack predates it) |
| AUD-10 | H | C | `docs/plans/current/TASK_PLAN.md:7,180-206,282`, `docs/ARCHITECTURE.md:1-30`, `README.md:1,30-45` | Current docs call segment/page/TGPR/refill work open or scaffold-level, contradicting the scorecard; TASK_PLAN points to stale WORK_QUEUE for status. | AGENTS "Documentation" | Rewrite the summaries or reduce them to scorecard links. | fixed (uncommitted) |
| AUD-11 | M | C | e.g. `docs/REFERENCE_BAT.md:31`, `docs/REFERENCE_CACHED.md:40`, `docs/SYSTEM_COMPLETION.md:572,610,634` | Evidence cites build manifests and source-hash counts; almost no verification record names a commit; some lack command or date. | AGENTS "Recording evidence" | One-line record header per doc (target, commit, date, counts); drop manifest and hash citations. | fixed (uncommitted) |
| AUD-12 | M | C | `sim/tools/isa_check_rtl.py:128-133`, `sim/spec/isa.json` | ISA-vs-RTL check probes the default decode profile only; opt-in forms are never checked and several implemented supervisor/MMU forms are absent from `isa.json`. | CODING_CONVENTIONS (independent checks) | Probe each profile against its status set; add missing forms. | fixed (11 decode profiles probed; 64 opt-in forms added; mtdmiss/mtimiss stay rejected: the UM conflicts, see CPU_TLB_MISS.md) |
| AUD-13 | L | C | `rtl/ppc_decode.sv:554-563` | `mftb` legality depends on `ENABLE_RUNTIME_BAT`/`ENABLE_TIMERS`, contradicting the adjacent comment. | 603e UM (MFTB/MFSPR equivalence) | One rule independent of unrelated profiles. | fixed |
| AUD-14 | L | C | `rtl/ppc_exception_state.sv:146`, `rtl/ppc_special.sv:332-356` | `rfi` stores reserved MSR bits 31, 26:22; `mfmsr` hides them but the next exception copies them into SRR1. | `hdl-design-organization` §4 | Apply the implemented-bit mask on every MSR write. | fixed |
| AUD-15 | M | E | `rtl/ppc_icache.sv:145`, `rtl/ppc_fetch.sv` | Ready requires `!rsp_valid_q`: at most one fetch every two cycles. Undocumented. | `cpu-memory-interface` §1 | Accept on the consuming edge with a RAM-output hold register. | fixed (one hit per cycle; consume-edge offers) |
| AUD-16 | M | E | `rtl/ppc_regfile_gpr.sv:21-30` | GPR array is reset and has two write ports: all flops, three 32:1 read muxes on the AUD-01 path. | CODING_CONVENTIONS, `cpu-register-files` §1, §4 | Drop reset; retire the update write through one port; MLAB copies. | fixed (one write port, three MLAB copies; 32-cycle zeroing walk after reset) |
| AUD-17 | M | E | `rtl/ppc_tlb_service.sv:69,204,236` | TLB array (~7.9 kbit) has two write addresses and an async read, so it cannot infer RAM. PLAUSIBLE: no fit covers it. | `cpu-mmu-tlb` §1 | Funnel writes to one port; RAM wrapper with registered read. | fixed (per-way 64x62 RAM with registered read; one added cycle on the page path) |
| AUD-18 | M | C | all Verilator builds | No `--x-assign unique --x-initial unique` or random reset seed; a missing reset is invisible. | CODING_CONVENTIONS (independent reset checks) | Add the flags; run core benches with a recorded seed. | fixed (sim benches and reference runners X-randomized at XRAND_SEED; XRAND=0 disables) |
| AUD-19 | M | K | `AGENTS.md` Commands, `sim/Makefile` | AGENTS says only `test-reference*` need `../dingusppc`, but `regression` includes them; a missing checkout fails as a buried g++ error. | — | Correct the text; add a precheck with a clear message. | fixed |
| AUD-20 | L | S | `sim/cosim/README.md:8-23`, `quartus/README.md:11`, `toolchain/README.md:16`, cosim script defaults, `tb/tb_stage_timing.sv:132` | Leftover `ppc603e/` workspace commands and `/tmp` paths. | AGENTS "Recording evidence" | Repo-relative commands; default scratch to `sim/build/`. | fixed |
| AUD-74 | M | E | `rtl/ppc_bat_memory_router.sv:629-651`, `rtl/ppc_bat_service.sv` | Timer-bat worst setup (-5.952 ns, slow 100 C, 2026-09-26 refit) runs from `router|running_q` (fan-out 5,272) through the BAT request mux and write validation into `bat|upper_q`. Only the startup write port and runtime BAT CSR writes use it; it worsened after AUD-43 put the validating instance on the write side. | `cpu-fmax-critical-paths` | Register the BAT write request and validation result, and replicate or register the `running_q` select. | fixed (registered BAT write stage; timer-bat meets 50 MHz setup and hold) |

### Fetch, decode, dispatch

| ID | Sev | Cat | Where | Problem | Fix | Status |
|---|---|---|---|---|---|---|
| AUD-21 | M | E | `rtl/ppc_dispatch.sv:31-55` | RS wake compare feeds ALU operands and `dispatch_ready`. | Snoop-capture wake; issue next cycle. | fixed (IU result bypassed by a select registered at capture; dependent ops still issue back to back, CPI unchanged; IU-operand path slack +3.3 → +8.1 ns) |
| AUD-22 | M | E | `rtl/ppc_fetch.sv:29-44`, `rtl/ppc_fifo.sv:21` | Fetch outputs carry the recovery cone; `rsp_ready_o` reduces to `pending`; `!redirect_i` in `packet_valid_o` is redundant. | Simplify as stated. | fixed |
| AUD-23 | M | K | `rtl/ppc_core.sv:250-269`, `rtl/ppc_decode.sv:536-563`, `rtl/ppc_special.sv` | Privileged-SPR list duplicated in three modules; privilege is SPR bit 4. | Use `spr[4]`; SPR numbers once in `ppc_pkg`. | fixed (privilege = SPR bit 4; SPR numbers in ppc_pkg) |
| AUD-24 | L | C | `rtl/ppc_fetch.sv:86-94` | Discarding a response under `stop_i` still advances the PC; safe only by an unstated invariant. PLAUSIBLE. | Hold PC or assert the invariant. | fixed (sim assertion) |
| AUD-25 | L | E | `rtl/ppc_pkg.sv:62-67` | Each IQ entry carries a 69-bit `page_miss` record including an EA equal to the PC. | Side register for the oldest fault; drop `ea`. | fixed (IQ entries keep the cause; one side register holds the oldest miss record) |
| AUD-26 | L | S | `rtl/ppc_dispatch.sv`, `rtl/ppc_core.sv:466-496` | RS and CQ payloads are loose signals copied field by field; allocation masks applied twice. | Struct payloads; sanitize once. | fixed (rs_entry_t/issue_packet_t; allocation sanitized once in completion) |
| AUD-27 | L | K | `rtl/ppc_pkg.sv:150`, `rtl/ppc_decode.sv` | `write_cr0` means "write CR field `cr_field`". | Rename `write_cr_field`. | fixed |
| AUD-28 | L | K | `rtl/ppc_decode.sv:127-145,287-342` | `addme`/`addze` not normalized like `subfme`/`subfze`; SH passed two ways; long equality-OR chains. | Normalize; flat nested case. | fixed |
| AUD-87 | L | C | `rtl/ppc_decode.sv:65-73`, `tb/tb_core_full_decode.sv:216-217` | EC603e `fsqrt`/`fsqrts` take the illegal-instruction program exception: `fp_a_form` omits XO 22 on every variant. UM Table B-3 prose (PDF 409, printed B-3), Table A-1 footnote 7 (PDF 368) and §4.5.8 (PDF 189) trap every EC603e FP instruction, these two included, to floating-point unavailable; Table B-1 (PDF 407) makes them illegal only on the FPU-equipped 603e. | Decode XO 22 as FP class when the variant has no FPU; check 0x800 in the EC603e full-decode bench. | fixed (XO 22 is FP class only on the EC603e; `variant-full-decode-2` expects 0x800, the other variants 0x700) |
| AUD-90 | L | C | `rtl/ppc_core.sv:876-906` (`lr_mt_q`, `lr_disp_q`, `lr_front_q`), `rtl/ppc_core.sv:1109` | A `bclr` behind `mtlr` resolves from the move's source, fed two cycles after the `mtlr` dispatches, before the move retires. Seen at width 1, and at both widths with branch removal, where the `bclr` is removed at dispatch. UM §6.4.1.1 (PDF 261): after `mtspr(LR)`, a `bclr` waits and fetching stops until the `mtspr` executes; UM §6.3.3.2 (PDF 259): a move to LR or CTR is completion-serialized, held until everything older retires, and its result is not forwarded before it retires. Dhrystone width 1 (`fff02efc mtlr`, `fff02f00 blr`): `4828468 D1 mtlr`, `4828470 D1 blr`, `4828473 R1 fff02ef8` (last older), `4828474 D1 fff0481c` (the target), `4828476 R1 mtlr`; with removal, `464494 D1 fff02f00*` while two older loads are in flight. | Feed the shadow LR when the move retires. Changes Dhrystone cycles (the early feed gained 835 to 806 cycles/run at width 1 with the other redirect changes); deferred. `test-dispatch-rules` accepts it with `--early-move` (`DISPATCH_RULES_ARGS=` checks the manual). | fixed (94c2815: the branch reads LR or CTR after the move retires, linking branches wait for an older linking branch, no fetch-stop branch folds; `test-dispatch-rules` checks the manual rule; Dhrystone 766 to 769 and 639 to 641 cycles/run, w1 and w2) |

### Execution units and register files

| ID | Sev | Cat | Where | Problem | Fix | Status |
|---|---|---|---|---|---|---|
| AUD-29 | L | E | `rtl/ppc_iu.sv:111-168` | Five barrel shifters; SRAW carry via a 32-iteration loop. | One rotator, mask, sign fill. | fixed |
| AUD-30 | L | E | `rtl/ppc_iu.sv:29,91-93` | Second adder for overflow, misnamed `unused_add_low_sum`. | `ov = (a[31]==b[31]) && (sum[31]!=a[31])`. | fixed |
| AUD-31 | L | E | `rtl/ppc_iu.sv:135-140` | `cntlzw` is a 32-deep priority loop on the result mux. | Log-depth LZC. | fixed |
| AUD-32 | L | E | `rtl/ppc_iu.sv:79-86,154-161` | Carry-in and inversion decoded in execute; five enum values compute one add. | Carry select fields in the issue packet. | fixed (invert_a and carry_in in the issue packet; seven ALU ops removed) |
| AUD-33 | L | E | `rtl/ppc_special.sv:411-416` | `cmp` uses a separate comparator and serializes the machine. | Route through the IU subtract as a renamed op. | fixed (compares on the IU adder as renamed flag ops; no CQ drain) |
| AUD-34 | L | E | `rtl/ppc_divider.sv:62-95`, `rtl/ppc_iu.sv:193` | ~160 datapath bits reset and cleared on cancel. | Reset control only. | fixed |
| AUD-88 | L | C | `rtl/ppc_core.sv:2767-2769`, `rtl/ppc_special.sv:2137` | The 603e completes a result that newly sets a disabled FPSCR sticky exception bit without delay. UM §4.5.7.1 (PDF 188): with the exception disabled and MSR[FE]=0, that update is completion-serialized for one or two cycles, only when the bit changes. Only the 602 models the stall. | Apply the existing 602 hold to the FPU-equipped 603e and update the core FP timing tables; the manual gives no rule for two cycles. Changes cycle counts; deferred. | open |
| AUD-89 | L | C | `rtl/fpu/ppc_fpu.sv`, `rtl/ppc_special.sv` | Single-precision denormal results round in the normal latency, and `lfs`/`stfs` of a single denormal convert in the normal access time. UM §2.3.4.2 implementation note (PDF 103): denormal single results take two more cycles to round; the LSU may take up to 24 cycles to convert a single denormal on load or store. | Add the two rounding cycles to the single-precision denormal result path; record a per-case conversion count or an upper-bound policy for the LSU. Changes cycle counts; deferred. | open |

### Load/store, cache, bus

| ID | Sev | Cat | Where | Problem | Fix | Status |
|---|---|---|---|---|---|---|
| AUD-35 | M | E | `rtl/ppc_icache.sv:93-121,237-244` | Hit way feeds the data RAM address and LRU update in the compare cycle. PLAUSIBLE. | Per-way RAMs with late select, or register the hit. | fixed (parallel way read, registered one-hot select) |
| AUD-36 | L | E | `rtl/ppc_bus60x_line_read.sv:72-73,157-159,286-293` | Two 256-bit line registers; needless zeroing and datapath reset. | Use `line_work_q` as the response. | fixed |
| AUD-37 | L | C | `rtl/ppc_bus60x.sv:243-249`, `rtl/ppc_bus60x_line_read.sv:202-208` | AACK in the TS cycle is accepted, not flagged (BUS_SPEC Figure 8-6). | Protocol error in the TS cycle. | fixed |
| AUD-38 | L | C | `rtl/ppc_icache_managed.sv:55,194-197` | `default:` enters `MANAGED_INVALID`, which has no exit; busy stays high. | Return to `MANAGED_RUN` with sticky error. | fixed |
| AUD-39 | M | K | `rtl/ppc_core_cached_bus60x.sv:291-387`, `rtl/ppc_core_cached_bus60x_managed.sv:348-444`, `rtl/ppc_core_bat_cached_bus60x.sv:520-616` | ~100 identical lines of 60x pin glue in three wrappers; pins as loose ports. | Pin structs; one two-master module. | fixed |
| AUD-40 | L | S | `rtl/ppc_bus60x.sv:156-163`, `rtl/ppc_bus60x_line_read.sv:118-121`, `rtl/ppc_icache.sv:46,61-63,110-112` | TT/TSIZ codes and cache widths are literals. | Package enums; `$clog2` widths. | fixed |
| AUD-41 | L | S | `rtl/ppc_bus60x_line_read.sv:63`, `rtl/ppc_bus60x_master_select.sv:24` | Dead enum states. | Remove. | fixed |

### MMU

| ID | Sev | Cat | Where | Problem | Fix | Status |
|---|---|---|---|---|---|---|
| AUD-42 | M | E | `rtl/ppc_bat_memory_router.sv:1026`, `rtl/ppc_special.sv:606-617` | True miss always reports SRR1.WAY=0, so the TLB acts direct-mapped (documented in [CPU_TLB_MISS.md](CPU_TLB_MISS.md)). | Per-set LRU bit returned in the capsule. | fixed (per-set LRU bit returned as SRR1 WAY on true misses, UM Table 5-10) |
| AUD-43 | L | E | `rtl/ppc_bat_translate.sv:54-110` | Bank config and overlap checks run per translation but cannot fire there. | Validate on write only; AND-OR result. | fixed (VALIDATE_BANK parameter; one-hot AND-OR select) |
| AUD-44 | L | C | `rtl/ppc_bat_translate.sv:116-119` vs `rtl/ppc_tlb_service.sv:150-151` | BAT PP=00 with G=1 halts; the page path prioritizes and raises ISI (documented terminal in [LIVE_BAT_CONTEXT.md](LIVE_BAT_CONTEXT.md)). | Same protection-before-guarded rule. | fixed (PP=00 with G=1 raises protection ISI) |
| AUD-45 | L | K | `rtl/ppc_bat_memory_router.sv:1222-1234` | Lint sinks list used signals; comment false. | Sink only unused fields. | fixed |
| AUD-46 | M | S | router 206-211 and literals; `ppc_bat_service.sv:47-52`; `ppc_tlb_service.sv:41-43`; `ppc_segment_registers.sv:211-214` | Request kinds re-declared and hard-coded across four modules. | Package enums. | fixed |
| AUD-47 | L | S | router 159-205; `rtl/ppc_core_bat.sv:136,251,261` | Ports `logic [68:0]`/`[2:0]` although `page_miss_t` and fault enums exist. | Typed ports, named struct literal. | fixed |
| AUD-48 | M | K | router 273-416,603-608,867-886 | Five near-identical offer equations and six owner flops for one exclusive owner. | One `owner_t`, one priority encoder. | fixed (one owner_t register and priority encoder) |
| AUD-49 | L | K | router 931-940,1027-1045,1118 | Sticky fault outputs set by recoverable misses; `fault_miss_o` disagrees with `page_miss_o`. | Set on fatal paths only. | fixed (sticky outputs fire on diagnostics only) |

### Exceptions and completion

| ID | Sev | Cat | Where | Problem | Fix | Status |
|---|---|---|---|---|---|---|
| AUD-50 | M | S | `rtl/ppc_special.sv:757-1128,139-145` | One `always_ff` owns ~60 state elements across branch, SPR, LSU, MMU CSR and exceptions; `S_BAT_*` reused for other MMU ops. | Split by concern; rename `S_MMU_*`. | fixed (per-concern owner blocks; lock-step shadow matched 43 benches cycle for cycle) |
| AUD-51 | M | S | `rtl/ppc_special.sv`, `rtl/ppc_exception_state.sv:62`, `rtl/ppc_timer.sv` | No MSR/SRR1/DSISR/SDR1 definitions with masks; `0x87c0ffff` duplicated; `rfi_prospective` re-implements `rfi_msr`. | Package structs and masks; one `rfi_msr()`. | fixed (SDR1 reserved bits masked; DSISR and SPRGs need no mask) |
| AUD-52 | L | S | `rtl/ppc_exception_state.sv:48-59,214-219`, `rtl/ppc_special.sv:358-369` | Event codes duplicated as localparams; ISI cause compared to raw integers. | Package enum; typed port. | fixed |
| AUD-53 | L | C | `rtl/ppc_special.sv:1115-1121` | Unsupported exception result redirects to 0 in synthesis (unreachable today). | Diagnostic halt. | fixed (reported on halted_o; unreachable in every profile) |
| AUD-54 | L | E | `rtl/ppc_special.sv:392-394,461,503`, `rtl/ppc_completion.sv:118-169`, `rtl/ppc_core.sv:131-133,445`, `rtl/ppc_fifo.sv`, `rtl/ppc_fetch.sv`, `rtl/ppc_dispatch.sv` | `rst_ni` in combinational outputs (recorded −0.084 ns hold path); raw IRQ pin gates dispatch. | Drop reset terms where state is reset; register the IRQ. | fixed (listed reset terms removed; external_irq_i registered, one added cycle) |
| AUD-55 | L | K | `rtl/ppc_special.sv:147` | Live micro-op named `unused_uop_q`. | Rename `uop_q`. | fixed |
| AUD-56 | L | S | `rtl/ppc_special.sv:724,738`, `rtl/ppc_exception_state.sv:24-26,289`, `rtl/ppc_core.sv:3,195` | Dead ports and parameters (`rfi_pending_exception_i`, `result_is_exception_o`, `DISPATCH_WIDTH`). | Remove. | fixed |
| AUD-75 | M | C | `rtl/ppc_exception_state.sv:349` | SMI requires `!MSR[TGPR]`; the pin selector (`ppc_special.sv:1484`) does not, so SMI with EE=1, TGPR=1 commits then reports unsupported. UM §4.5.16 and Tables 4-7/4-19 (PDF 176, 195; printed 4-18, 4-37) take SMI whenever EE=1 and clear TGPR. | Drop the TGPR term, as `EVENT_EXTERNAL` does; add a bench case. | fixed: SMI taken with TGPR=1, entry clears TGPR. `test-exception-state` TGPR-mode SMI case |
| AUD-76 | L | C | `rtl/ppc_pkg.sv:610` | PID7v PVR is `0x0007_0101`, chosen to match DingusPPC, while PID7v-only HID0 bits (IFEM, ABE) are enabled. UM §1.3.1.2 (PDF 58, printed 1-18) designates PID7v by PVR level 0x0200. | Use a revision ≥ 0x0200 (e.g. `0x0007_0200`) with the reference runner and firmware, or document the deviation. | fixed: PVR `0x0007_0200` (PID7v and EC603e); every DingusPPC runner sets the same PVR after init; `variant-config-0`/`-2` check it |
| AUD-77 | M | C | `rtl/ppc_dcache.sv:361`, `rtl/ppc_bus60x_snoop.sv:56` | Snooped `TT_READ`/`TT_READ_ATOM` are always clean class; TBST is not forwarded. UM Table 3-6 (PDF 146, printed 3-20, §3.6.7) and Table 7-2 (PDF 287, printed 7-11) snoop burst reads as writes: hit E → I, hit M → push, I. Only single-beat reads keep E. Seen only with a foreign master issuing burst reads. | Carry TBST to the snoop class; flush on burst reads; add a coherence case. | fixed: TBST reaches the snoop class; burst Read/Read-atomic flush. `test-dcache` D2b, `test-biu-dcache-snoop`, mutation 8 |
| AUD-78 | L | C | `rtl/ppc_bus60x_cache_master.sv:243`, `rtl/ppc_dcache.sv` | Touch-load fills drive TC=00, and a dirty victim is cast out before its fill. UM Table 7-6 (PDF 290, printed 7-14) and Table 8-8 (PDF 328) give TC=01 for touch loads; §8.1.1 (PDF 312, printed 8-4) and §3.6.3 (PDF 143) read the fill first, castout after. Not software-visible. | Drive TC=01 for dcbt/dcbtst; reorder or document the castout choice. | open |
| AUD-79 | L | C | `rtl/ppc_bat_translate.sv:146-147` | IBAT hits with IBATL[G]=1 raise a guarded ISI (UM Table 5-3, PDF 211). UM §3.5 (PDF 136, printed 3-10) says IBATs have no G bit and IBAT accesses are not guarded; PEM Figures 7-11/12 (PDF 322) mark IBAT W/G reserved. Manual conflict, not a clear error. | Choose and record one reading; test it. | fixed: follows §3.5; IBAT G is ignored and reads as 0 (BAT_TRANSLATION.md). `test-bat`, `test-bat-service` |

### Manual inventory

Gaps from [MANUAL_INVENTORY.md](references/MANUAL_INVENTORY.md), 2026-10-05: features the manuals define that the design lacks or leaves untested.

| ID | Sev | Cat | Where | Problem | Fix | Status |
|---|---|---|---|---|---|---|
| AUD-80 | M | C | `rtl/ppc603e.sv:186-204`, `rtl/ppc_bus60x_dbw32.sv`, `rtl/ppc_biu.sv` | 32-bit data bus mode (TLBISYNC strap; DH only, 1/2/8 beats, Tables 8-3, 8-5–8-7) and reduced-pinout mode (QACK strap) checkstop at HRESET instead of running. UM §8.6.1, §8.6.3 (PDF 346-349); §1.1.6 (PDF 54). A board wired for either mode cannot use the core. | Implement 32-bit beats in the BIU and line paths, then reduced pinout on top; or record the exclusion in CHIP_PACKAGE.md. | fixed. TLBISYNC asserted at HRESET negation latches `dbw32`; QACK negated latches reduced pinout, which implies it (UM §8.6.1, §8.6.3, PDF 346-349). `ppc_bus60x_dbw32` sits between each BIU master (scalar, line read, cache master, push engine) and the pins: DH only, DL and DP[4:7] low, one beat on the A[30:31] lanes for four bytes or less, two beats per doubleword (high word first) for eight-byte transfers and bursts in 64-bit doubleword order; the master sees its TA at the second beat, so DBB release and the late-cancel window follow it; a first-beat DRTRY is resolved in the adapter. Reduced pinout drives AP, DP and RSRV low, releases APE/DPE and checks no parity. With the strap negated every signal passes through. Late ARTRY inside a data tenure cannot occur: data starts after AACK+1. `test-chip-pins` 32-bit, DRTRY and reduced-pinout cases; `test-chip-fpu` runs the FPU program (eight-byte transfers) with `+DBW32`. See [CHIP_PACKAGE.md](CHIP_PACKAGE.md#32-bit-data-bus-and-reduced-pinout) and [CHIP_PACKAGE_VERIFICATION.md](CHIP_PACKAGE_VERIFICATION.md). |
| AUD-81 | M | C | `rtl/ppc_bus60x_line_read.sv:172`, `rtl/ppc_pkg.sv:600` | PID7v HID0[IFEM] is stored but read by nothing; instruction fetches always drive GBL negated. UM Table 2-2 (PDF 86), PDF 44: IFEM reflects the M bit onto the bus for fetches. | Drive fetch GBL from M when IFEM=1; add a pin bench case. | fixed: line fills and caching-inhibited single-beat fetches drive GBL from the fetch's M when IFEM=1 (`test-chip-pins` `case_ifem`, WIMG 0010 and 0110) |
| AUD-82 | M | C | `rtl/ppc602_bus.sv:167` | 602 injected snoops are not modelled: a target may assert TS with TA negated between burst-read beats, and the 602 must answer ARTRY on a hit without a push, or invalidate on kill. An injected TS is handled as an ordinary snoop. 602UM §8.4.2 (PDF 378), §8.5.4.7 (PDF 406). | Snoop window from the third cycle after BB to the last beat; hit gives ARTRY only; bench case on `test-chip602-pins`. | fixed: an injected snoop (TS during the 602's own burst-read data tenure) gets an internal AACK on the second cycle after TS and reaches the cache as a query: a hit the snoop would act on gives ARTRY with no push and no state change; a kill invalidates. Window taken as any data cycle after the first; ARTRY may assert up to the third cycle after TS (8.3.2.3), later than Figure 8-35 shows (`test-chip602-pins` inject cases) |
| AUD-83 | L | C | `rtl/ppc_special.sv:1720` | SRESET leaves the I-cache enabled. UM §4.5.1.2 (PDF 178): unlike hard reset, soft reset disables the instruction cache. Table 4-9 names no HID0 change, so the mechanism is unstated. | Clear HID0[ICE] on soft reset, or record the reading; add a `test-chip-pins` SRESET check. | fixed: soft reset clears HID0[ICE] (the only I-cache disable the manual defines, §3.1.3.2) without invalidating; fetches bypass the cache until software next changes ICE. `test-chip-pins` `case_sreset_icache` |
| AUD-84 | L | C | `tb/` | UM Table 4-2 (PDF 165-166) priority is checked only pairwise (trace over EXT/DEC, IABR over trace, SMI over INT). No bench raises a synchronous fault together with MCP, SRESET, SMI or DEC in one cycle. | Directed simultaneous-event cases per Table 4-2 row. | fixed: `ppc_special` S_HOLD abandons a faulting instruction when MCP (ME=1), an asynchronous TEA/APE/DPE or SRESET is pending at its commit and takes the pin event with SRR0 at it (no DAR/DSISR/miss-state write); it re-executes after the handler. `test-chip-pins` sweeps MCP, SRESET, SMI and DEC (EE=1) around a trap, an eciwx DSI and a misaligned lwarx and checks vector, SRR0/SRR1, re-execution and that SMI/DEC follow |
| AUD-85 | L | C | `rtl/ppc603e.sv:407,415`, `tb/chip_harness.svh:13,106` | DBDIS and the 603e's two-bit CSE are driven but unchecked: every bench ties DBDIS high, and CSE is checked only on the 603. UM §7.2.7.4 (PDF 297), §7.2.4.8 (PDF 291). | Add both to `test-chip-pins`. | fixed: `test-chip-pins` `case_dbdis` (no data drive the cycle after DBDIS, write beats still terminate) and `case_cse` (four fills into one set give CSE 0-3) |
| AUD-86 | L | C | `rtl/ppc_bus60x_direct_store.sv:44`, `rtl/ppc603e.sv:225-228` | 603 checkstop sources are incomplete: an extended transfer protocol error never reaches CKSTP_OUT (UM §4.5.2.2, PDF 180), and a fetch TEA's refetch TEA with the machine check pending does not checkstop (UM §C.2.4, PDF 433). | Route the direct-store protocol error to checkstop; model or document the double-TEA rule. | fixed: on the 603 a bus protocol error (including direct-store) and a fetch TEA with MSR[ME]=1 checkstop (`test-chip-603` `+ds_protocol`, `+fetch_tea`). A fetch TEA is refetched in its own tenure; a second TEA checkstops, a successful refetch takes the machine check (`+fetch_tea_once`) |

### Whole RTL

| ID | Sev | Cat | Where | Problem | Fix | Status |
|---|---|---|---|---|---|---|
| AUD-57 | L | S | all `rtl/*.sv` | No `` `default_nettype none``; `unique case` without `default:` in `ppc_icache.sv:81-90`, `ppc_bus60x_line_read.sv:88-93`. | Add both. | fixed |
| AUD-58 | L | S | `rtl/ppc_flags.sv:120-123`, `rtl/ppc_rename.sv:138-139,150-153` | Assertions not under `translate_off`. | Guard them. | fixed |
| AUD-59 | L | S | ~20 module headers and comments (e.g. `ppc_core.sv:1`, `ppc_fetch.sv:1`, `ppc_special.sv:1-2,161,163`, router 1-3) | "does not…", "scaffold", "future hash unit", doc-file references. | Trim to current behavior (`concise-writing`). | fixed |
| AUD-60 | L | S | `rtl/ppc_core.sv:283,322-353`, `rtl/ppc_flags.sv:62` | Raw MSR/XER bit indices and masks. | Named package constants. | fixed |

### Tests and tooling

| ID | Sev | Cat | Where | Problem | Fix | Status |
|---|---|---|---|---|---|---|
| AUD-61 | M | E | `sim/Makefile` (34 `tb_core_add_recovery` targets), cosim runners | Stimulus-only parameters rebuild the full core 34 times; 148 full-core builds; DingusPPC runner built six times. | Plusarg case selection; shared runner prerequisite. | fixed (one add-recovery binary; shared reference runner) |
| AUD-62 | M | E | `tb/tb_compiled_*.sv`, 10 benches with private `ta_n` responders | Firmware harness copied ~20 times; responders bypass `tb/bfm/`. | Shared harness; move to the BFM. | fixed (all bench responders on shared BFMs except the two deliberately independent pin-level checkers) |
| AUD-63 | L | K | `toolchain/run-rtl-smoke.py:103-197`, `tb/tb_core_add_recovery.sv:4-21` | Profile selection by overlapping flags and ternary chains. | One table; enum with `$fatal` on conflicts. | fixed |
| AUD-64 | L | C | `sim/tools/test_isa.py`, `sim/tools/test_bus_scenarios.py`, `sim/tools/*_family.py` | ~120 asserts check prose in JSON yet count as evidence; "independent" family models feed no RTL bench. | Wire models into vectors or relabel; stop counting prose asserts. | fixed (prose asserts in *Prose classes; rotate model drives tb_rotate_execution; other models relabeled) |
| AUD-65 | L | S | `quartus/build.sh:7`, `quartus/collect-reports.sh:10,33` | Mutable image tag; undeclared `rg`; hardcoded pin count. | Pin digest; use grep. | fixed |

### Docs and skills

| ID | Sev | Cat | Where | Problem | Fix | Status |
|---|---|---|---|---|---|---|
| AUD-66 | M | K | `docs/SYSTEM_COMPLETION.md:144-157` | Round table stops at 74%; later rounds exist only as prose duplicated in the MVP plan. | One row per round to the current one. | fixed (uncommitted) |
| AUD-67 | L | K | `docs/plans/current/MVP_EXECUTION_PLAN.md:403-424` | Waves lack status markers; Wave 5 reads as future work. | Status line per wave. | fixed (uncommitted) |
| AUD-68 | M | K | `.agents/skills/` (untracked) | Real copy of `skills/`; will drift. | Symlink to `../skills` or remove. | fixed 2026-10-03: replaced by a symlink to `../skills` (local, untracked) |
| AUD-69 | L | C | `skills/hdl-coding-guidelines/references/source/02-source-map.md:117`, `17-era-faithful-microarchitecture.md:347`, `32-arithmetic-patterns-and-operator-cost.md:232`, `skills/mister-framework/references/source/30-sdram.md:289` | URLs not pinned to a full commit. | Pin 40-character SHAs. | fixed (uncommitted) |
| AUD-70 | L | S | `docs/SYSTEM_COMPLETION.md:602,621`, `docs/plans/current/MVP_EXECUTION_PLAN.md:711,722`, `docs/FPU_REUSE_ASSESSMENT.md:3` | Agent names ("Sol", "GPT-6 Sol") in records. | Delete. | fixed (uncommitted) |
| AUD-71 | L | S | `docs/SYSTEM_COMPLETION.md:404-405,548-549`, `docs/plans/current/MVP_EXECUTION_PLAN.md:681-728` | Missing spaces ("MVP80.81%"). | Restore. | fixed (uncommitted) |
| AUD-72 | L | S | `skills/concise-writing/SKILL.md:8-18` | Rules repeated; no checklist; README row omits docs. | Merge bullets; add checklist. | fixed (uncommitted) |
| AUD-73 | L | K | `AGENTS.md` "Recording evidence" | Bans citing `build/`, but reproduction commands legitimately write there. | Separate evidence citations from command output directories. | fixed (uncommitted) |
