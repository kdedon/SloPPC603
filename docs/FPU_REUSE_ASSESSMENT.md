# FPU reuse assessment and implementation plan

Reviewed 2026-09-22. Scope: [MiSTer-devel/N64_MiSTer](https://github.com/MiSTer-devel/N64_MiSTer/tree/eb5554af01bb97bdf3d295aed02a989ac10ccee4) and [Grabulosaure/ss](https://github.com/Grabulosaure/ss/tree/70203e26e981069710e934600fd55b9d866a9e5b) as FPU donors for this CPU. Two GPT-6 Sol agents independently investigated one donor each. The parent agent reviewed the decisive source paths and owns the conclusions below. This is an investigation and proposed plan; it does not implement an FPU or change the current integer MVP scope.

## Decision

**Neither donor is a drop-in 603e FPU. Use SS as the starting candidate for arithmetic code reuse and N64 as a source of size-oriented implementation techniques.** Reuse may save work on mantissa arithmetic, normalization and rounding, but does not remove the need for PPC state, fused arithmetic, exception semantics, estimates, memory support or precise retirement. No measured schedule saving is established.

Do not import either complete CPU-facing FPU. The user explicitly authorized SS code reuse during this review; no further licensing approval is a task gate. Qualify its `fpu_calc` boundary and low-level multiply/divide blocks before selecting a production implementation. Combine suitable SS arithmetic with the N64 sharing patterns below where measurements show a benefit. If qualification fails, replace the affected arithmetic component rather than assume the entire donor is unusable.

## Reproducibility and evidence limits

| Tree | Reviewed HEAD | Working-tree qualification |
| --- | --- | --- |
| PPC | `6f50ccd5ad8e90e8ef225410fcefb788af08b418` | Substantial existing uncommitted implementation/docs changes; assessment reads the working tree, not HEAD alone. |
| N64_MiSTer | `eb5554af01bb97bdf3d295aed02a989ac10ccee4` | Clean when inspected. |
| SS | `70203e26e981069710e934600fd55b9d866a9e5b` | Existing board-project/build changes and generated reports; not an immutable whole-system baseline. |

Donor paths below are relative to those repositories at the listed commits. Donor trees were not modified. Static RTL inspection establishes the interfaces and explicit policies described here, not arithmetic conformance. Existing whole-system synthesis evidence cannot establish standalone FPU area, throughput or timing. A fresh isolated synthesis and independent numeric test suite are implementation gates.

## What is available

| Area | N64_MiSTer | SS/TACUS |
| --- | --- | --- |
| Main sources | `rtl/cpu_FPU.vhd`, `cpu_FPU_sqrt.vhd`, external `cpu_mul.vhd` | `src/cpu/fpu_calc.vhd`, `fpu_pack.vhd`, `fpu_mul.vhd`, `fpu_div.vhd`; CPU-facing `fpu.vhd`, `fpu_simple.vhd`, `fpu_multi.vhd`, `fpu_regs_2r1w.vhd` |
| Arithmetic present | SP/DP add, subtract, multiply, divide, sqrt, compares, conversions and bit operations | SP/DP add, subtract, multiply, divide, sqrt, compares, conversions and bit operations |
| Useful boundary | Arithmetic procedures inside a MIPS COP1 controller; external 128-bit multiplication result | `fpu_calc`: two 64-bit inputs, result, opcode, rounding direction, five exception flags, unfinished flag, request/ready/finish/flush/stall |
| Missing target functions | Fused multiply-add family, PPC estimates and PPC architectural state | Same; no third arithmetic operand or FMA opcode |
| Numeric mismatch | MIPS NaNs, subnormal-input unimplemented exceptions, underflow flush/unimplemented policy, packed SP result | NaN payload loss, SPARC exception semantics, underflow TODO, no detailed PPC FPSCR metadata |
| Best use | Reference for algorithms and Cyclone V integration; selective extraction only if independently justified | Conditional arithmetic prototype, preferably below the SPARC state/decode wrappers |

### N64 findings

* `cpu_FPU.vhd:6-43` exposes decoded instruction/transfer controls, COP1 status and register-write signals. `:48-83` lists operations; `:88-107` defines MIPS CSR fields. This is not a stateless arithmetic service suitable for direct attachment to tagged PPC completion.
* `cpu_FPU.vhd:504-535` raises exceptions on subnormal inputs and applies MIPS-specific NaN rules. `:902-920` generates default DP NaN `0x7FF7FFFFFFFFFFFF`; this cannot be carried into PPC unmodified. `:567-568` and `:951-975` implement underflow policies requiring replacement for the PPC contract.
* `cpu_FPU.vhd:925-933` packs SP results in the low 32 bits. PPC needs its own FPR format/conversion rules; merely zero-extending that result is insufficient.
* `cpu_FPU.vhd:1400-1429` consumes an external product. `cpu.vhd:3418-3425` and `:3467` connect it; `cpu_mul.vhd:5-6` and `:26-33` depend on Intel `altera_mf`/`altera_mult_add`. The FPU file alone is not a complete multiplier implementation.
* `cpu_FPU.vhd:1163-1202` and `cpu_FPU_sqrt.vhd:49-101` contain iterative divide/sqrt machinery. The divider counter runs from 26/55 through zero (27/56 recurrence cycles); sqrt runs from 26/55 through one (26/55 recurrence cycles). Neither count includes launch/rounding/hand-off, and neither establishes 603e instruction timing. The 603e does not implement architectural `fsqrt/fsqrts`; its `frsqrte` estimate requires a separate contract.
* The checkout contains GPL version 3 text in `LICENSE`. No independent permissive license was found on these FPU files. Record the selected reuse/distribution terms before vendoring; the nested `powerpc_fpga` license does not establish a license for `ppc603e`.
* No standalone N64 FPU conformance suite or FPU-specific fitted area/timing evidence was located.

### SS findings

* `fpu_calc.vhd:45-79` is the useful extraction boundary. Preserve its arithmetic structure only after validating the handshake; its CPU wrappers implement SPARC control and are unsuitable PPC state owners.
* `fpu_pack.vhd:29-41` defines SPARC FSR; `:89-103` lists operations without FMA. Five IEEE exception flags cannot directly supply PPC invalid-cause distinctions, FR/FI, FPRF, sticky/summary fields and enabled-exception behavior.
* `fpu_pack.vhd:13-14` explicitly says NaN contents are not preserved, nor NaN sign for subtraction. `:989` contains an underflow TODO. These are reasons for focused tests and changes, not proof that every operation fails.
* `fpu_div.vhd:14` flags SRT-divider bugs. Its non-restoring, SRT2 and SRT4 alternatives must not be treated as equally qualified; begin with the non-restoring branch for the functional experiment, then verify it independently. Its 25/54 iteration counts also mean it is not a ready-made 603e cycle-accurate divider.
* `fpu_mul.vhd:208-231` has a direct 53-by-53 multiply path with a 106-bit temporary, but exports only 55 product bits plus sticky. A fused operation cannot reuse that narrowed interface unchanged: cancellation can make discarded product bits significant.
* Denormal generics (`DENORM_HARD`, `DENORM_FTZ`, `DENORM_ITER`) exist in `fpu_calc`; configuration names are not proof of PPC denormal/NI behavior. Qualify explicit settings and exception-enable interactions.
* Relevant source headers state copyrighted/all rights reserved and refer to `lic.txt`; that file was not located in the checked-out/tracked source. The user explicitly confirmed that SS code is fine to use. Proceed on that authorization, preserve existing notices and record provenance; this investigation does not assign a new license to the files.

## Reusable implementation techniques

Architectural incompatibilities do **not** negate N64's value as a size-oriented design reference. Reuse resource sharing and precision management independently of MIPS status/exception behavior. These are observed source structures; comparative savings remain unmeasured.

| Pattern and evidence (paths relative to donor) | Benefit and PPC application |
| --- | --- |
| **Common SP/DP arithmetic.** N64 `rtl/cpu_FPU.vhd:289-315`; SS `src/cpu/fpu_calc.vhd:248-281`, `:556-584`, `:715-729`. | Avoid separate binary32/binary64 units by sharing wide arithmetic, classification and rounding. Introduce explicit input/result precision. PPC SP operands cannot simply be unpacked from low FPR bits as N64 does; PPC FPR representation and rounding rules still govern. |
| **Shared post-operation shifter/rounder.** N64 `cpu_FPU.vhd:1031-1114`, fed by add `:1323-1353`, multiply `:1400-1435`, divide `:1485-1513`, conversions `:1581-1748`. | Strongest immediately useful N64 sharing pattern: a registered 57-bit-input shift path, sticky logic and common round/pack backend. Use tagged result packets with sign, extended exponent, precision, rounding and exception metadata; arbitrate simultaneous finishes and hold under backpressure. ADD still has a separate alignment shifter at `:1120-1123`; this is not literally one shifter for the entire FPU. |
| **Shared integer/FP multiplier.** N64 `rtl/cpu.vhd:2687-2734`, `:3418-3425`, `:3467`; `cpu_mul.vhd:26-33`. | One registered 64×64→128 Intel multiplier serves integer and FP operations. Evaluate a right-sized PPC 32-bit-integer/53-bit-significand shared engine with signedness, ownership and arbitration. Keep separate units for first integration, then measure sharing: it couples IU/FPU issue, recovery and overlap. N64's 64-bit width is not inherently optimal for PPC. This is not a custom partial-product multiplier. |
| **Serial division.** N64 `cpu_FPU.vhd:1163-1202`. | A 56-bit compare/subtract, shifted remainder and quotient reuse arithmetic over 27/56 recurrence cycles. Useful small-area baseline; investigate more work per cycle to meet 18/33-cycle 603e targets. These counts exclude launch/round/hand-off. Compare and subtract syntax does not prove one physical carry chain after synthesis. |
| **Guard/round/sticky compression.** N64 `:1037-1045`, `:1052-1062`, `:1400-1429`; SS `fpu_mul.vhd:191-200`, `:227-230`. | Replace provably irrelevant low bits by sticky to reduce storage and shifting widths. Compression must occur late enough: FMA cancellation can make low product bits significant. Preserve the full product or an equivalently proven representation until after fused addition; export round increment/discard information for FR/FI. |
| **Special-case bypass.** N64 `:1315-1320`, `:1373-1382`, `:1459-1470`, common bypass writeback `:883-900`. | Zero/infinity outcomes can bypass long arithmetic. Rebuild classifier/result metadata for PPC NaN precedence, signed zero and invalid causes. Primarily activity/latency savings; arithmetic hardware remains. A late bypass does not prove a multiplier stopped toggling. Hold early answers if target timing requires it. |
| **Serialization permits shared control.** N64 `cpu.vhd:2785-2793`, `cpu_FPU.vhd:146-150`. | Waiting for command completion lets sign/precision/rounding state be global and reduces arbitration complexity. Useful for an explicitly limited functional profile. A pipelined PPC design needs per-instruction control fields and backend reservations; a younger operation must not overwrite older rounding state. |
| **DSP-width partial products across cycles.** SS `src/cpu/fpu_mul.vhd:63-204`, especially `:131-201`; direct alternative `:208-232`. | Split 53-bit significands into three 17-bit limbs plus two-bit tails; multiplex partial products over one SP/two DP phases. Candidate for fewer multiplier resources, compared with direct 53×53 multiplication. Measure suitable limb sizes on Cyclone V. Existing output narrows to 55 bits plus sticky and needs redesign for FMA. The donor's extra DP phase is not automatically compatible with PPC pipeline occupancy. |
| **Iterative denormal handling.** SS `fpu_calc.vhd:293-387`, `:593-655`; defaults `fpu_simple.vhd:102-108`. | Configurable trap, one-cycle normalization/denormalization or repeated 8-bit/1-bit shifts. Iterative shifts are a plausible way to reduce variable-shift logic for rare operands/results while preserving gradual underflow. Require correct sticky accumulation and variable-latency ownership; no flush-to-zero substitution unless PPC mode semantics permit it. Exceptional-operand timing needs a separate contract. |
| **Selectable divide algorithms.** SS `fpu_div.vhd:233`, `:309`, `:451`. | Stable outer interface with non-restoring, SRT2 and SRT4 implementations enables area/latency experiments. Start with non-restoring; SRT code carries an explicit bug warning. Qualify each configuration rather than assume a faster branch is correct. |
| **Stage readiness and held results.** SS `fpu_calc.vhd:184-220`, `:777-803`. | Reuse valid/ready stage propagation and stall-result capture to integrate a shared backend. Add PPC producer identity and selective cancellation. Donor flush and output flags do not themselves provide precise FPSCR retirement. |
| **RAM replication for FPR read ports.** SS `fpu_regs_2r1w.vhd:42-48`, `:62-101`, `:106-144`. | Two replicated 32×64 RAM banks provide two synchronous read ports with common writes and bypass. Evaluate this against flops for PPC; fused arithmetic needs three operands, so additional replication or an explicit staged read schedule is necessary. Keep four FPR rename slots/forwarding separate. Do not import SPARC half-word register addressing or its scoreboard unchanged. |

N64 sqrt is a **separate** 57-bit add/sub recurrence (`cpu_FPU_sqrt.vhd:49-101`), not a shared divide/sqrt unit. It runs 26/55 recurrence cycles, unlike divide's 27/56. It illustrates iterative reuse but is not required hardware for the 603e's unsupported architectural sqrt instructions.

### Measured donor evidence

SS's saved `src/board/mister/SS_MiSTer/output_files/ss5.map.rpt:997` defines hierarchy columns; `:1147-1151` attributes **3,202 combinational ALUTs, 1,522 registers, 4,096 memory bits and 11 DSP blocks** to the FPU hierarchy. The `fpu_calc` child is 2,689 ALUTs/1,053 registers/11 DSP. These are synthesis hierarchy figures, **not fitted ALMs** or the marginal cost of adding FP to PPC.

Board source `src/board/mister/ss_core.vhd:294` selects `TECH => 0`; `cpu_conf_pack.vhd:193-204` maps this to split multiplication and non-restoring division. Thus the saved configuration is a useful split-multiplier data point, not a measured comparison with direct multiplication. The full-system fit is 20,430/41,910 ALMs and 43 DSP (`ss5.fit.summary:4-14`); `ss5.sta.summary:5-15` reports negative setup slack. Source/report correspondence was not reconstructed by a fresh build. No N64 FPU-specific fit or comparative area result was found.

### Concrete area experiment within F1

1. **A: SS extraction baseline.** Split multiplier, non-restoring divider and explicit denormal configuration; exclude SPARC architectural ownership from the measured boundary.
2. **B: shared backend.** Same accepted semantics with N64-inspired shared post-operation normalize/round and SP/DP representation. Include tagged buffering/arbitration. Compare split/direct multiplication and iterative/single-cycle denormal handling as controlled subvariants.
3. **C: optional CPU-level sharing.** Measure the better standalone variant with shared versus separate IU/FP multipliers, including contention, recovery and integer throughput. DSP count alone cannot choose the winner.

Use identical target, clock constraints, register boundaries, loads, semantics and numeric corpus. Record ALMs, DSPs, memory, setup/hold, operation latency/initiation interval and exceptional-operand latency. Include FMA's full-product storage and all required buffering; omitting them biases the comparison. Select the smallest configuration meeting the chosen profile and explicitly retain any gap to full 603e timing.

### Validation performed in this investigation

GHDL 4.1 successfully analyzed SS `base_pack.vhd`, `cpu_conf_pack.vhd` and `fpu_pack.vhd` under VHDL-2008. The parent independently reproduced that package-only result. A dependency-ordered broader analysis reached ambiguous `To_HString` overloads in `disas_pack.vhd`; the parent reproduced this too. A referenced `fpu_sim_pack` was not found. These are extraction/build issues, not evidence of arithmetic failure. No complete FPU elaboration, numerical execution suite or fresh synthesis was run.

## PPC requirements that remain ours

The controlling local requirements are `TASK_PLAN.md:226-242` (P23–P25), `SOURCES.md:70` and `:88` (capabilities), and `TIMING_SPEC.md:86-101` (timing). The original root implementation plan contains historical assumptions and is not the conformance authority.

1. **State and transport:** 32 64-bit FPRs, the planned four FPR rename slots, FP source dependencies including a third FMA operand, result/completion metadata, FPSCR, CR1/compare effects and FP loads/stores. Current `rtl/ppc_pkg.sv:13-33` has 32-bit operand/results and `rtl/ppc_core.sv:46-50` has a 32-bit data transport. Both require deliberate FP extension.
2. **PPC arithmetic semantics:** single/double rounding rules, NaN selection/payload rules, signed zero, subnormal and NI behavior, conversions, exception reasons and destination suppression. Returning five generic flags is insufficient.
3. **Fusion:** use one final rounding for the fused family. As a discriminating DP nearest-even case, `(1 + 2^-27) * (1 - 2^-27) - 1` is exactly `-2^-54`; separately rounding the product gives zero after subtraction. Chaining existing multiply and add results is therefore invalid.
4. **Precise state:** capture instruction identity and control state; hold results under backpressure; suppress all killed/stale destination and FPSCR effects; commit architectural state at the accepted retirement boundary. A donor's global flush is not a substitute for exact producer ownership.
5. **Timing and estimates:** `fdivs/fres` have 18 execute cycles, `fdiv` 33; double multiply/fused rows have `[2,1,1]` stage occupancy; ordinary staged rows including `frsqrte` have `[1,1,1]`, with documented serialization qualifications. A functional serialized prototype earns no pipeline/cycle-conformance credit. A slower donor cannot meet a shorter target latency by adding a counter.

The current [`SYSTEM_COMPLETION.md`](SYSTEM_COMPLETION.md) explicitly excludes FPU from the integer MVP. This proposal belongs to the full-603e workstream and does not silently change that MVP's acceptance criteria.

## Implementation plan and acceptance gates

### F0 — Freeze contract and donor provenance

Deliver `FPU_CONTRACT.md` with legal opcodes, FPR representations, all rounding/NaN/subnormal/NI/exception rules, FPSCR update/suppression rules, MSR FP/FE behavior, memory semantics and source locators. Map work to P23–P25. Record hashes, existing notices and the user-authorized SS reuse decision for any imported files and dependencies. Keep `fsqrt/fsqrts` unsupported and 602 behavior outside this contract.

**Exit:** reviewed capability/status matrix and an explicit extraction boundary for SS arithmetic. No blanket IEEE-754 label substitutes for a PPC contract.

### F1 — Qualify an isolated arithmetic backend

Start with the authorized SS `fpu_calc` extraction candidate and compare its baseline against the N64-inspired sharing options above. Minimize base/config/arithmetic package dependencies; exclude SPARC FSR/register-file/trap ownership. Pin multiplier/divider technology choices and gradual-underflow settings. Expose raw result plus the metadata needed by F0, including rounding increment/discard information and differentiated invalid causes. Replace NaN selection and incomplete numeric behavior as necessary.

Use a temporary standalone GHDL harness for donor characterization. Production must have one reproducible simulation/synthesis source flow: the current CPU regressions use SystemVerilog/Verilator, so decide explicitly between an audited SV port and a supported mixed-language/translation flow. Compile the chosen flow in both simulation and Quartus before integration; two independently maintained arithmetic implementations are undesirable.

**Exit:** reproducible bit-exact results for the accepted operation subset under all four rounding modes, explicit exceptions, adversarial subnormal/NaN/overflow/conversion tests, and a standalone Cyclone V resource/timing report. Reject a candidate requiring pervasive repair with no demonstrated advantage. Passing compilation alone does not pass this gate.

### F2 — P23: architectural FP shell

Add FPR storage, FP destination ownership and trace fields; define the path to four rename slots and three-source arithmetic. A first opt-in serialized lane may simplify bring-up, but record its limitations. Extend decode, MSR FP enable and unavailable exceptions, FPSCR access/CR effects, bit-preserving moves and FP memory support. Unsupported arithmetic must remain explicitly rejected.

For 64-bit FP memory operations on the current 32-bit transport, specify beat order, alignment, fault/cancel behavior, store authorization and destination/base-update commitment before implementing split transactions. Do not accidentally partially commit an FPR or replay an externally visible store.

**Exit:** actual CPU tests for dependencies, enable/disable, raw bits, memory faults, update forms, backpressure, recovery and retirement-only state changes. Correct instructions never bypass completion ownership.

### F3 — P24: basic arithmetic and fused datapath

Integrate only the F1-qualified add/subtract/multiply/compare/conversion subset. Add a dedicated fused datapath retaining the full product through alignment/addition/normalization and rounding once; do not compose rounded donor results. Add FPSCR invalid subcauses, FR/FI/FPRF, enabled-exception behavior and CR1 effects according to F0. Check SP operand/result rules independently from DP, especially double-rounding hazards.

**Exit:** raw-bit arithmetic and complete architectural-state comparison; cancellation and fused-rounding counterexamples; consecutive FPSCR writers, exception suppression, killed completion and reset/stall tests. Successful functional execution remains distinct from timing acceptance.

### F4 — P25: divide and estimates

Qualify divide independently. Use a verified donor algorithm only where it meets the chosen functional milestone; redesign iteration rate/scheduling as required for 18/33-cycle target execution. Implement `fres/frsqrte` from their PPC approximation requirements; donor sqrt followed by division is neither a proven estimate implementation nor a timing shortcut.

**Exit:** source-backed estimate bounds/required behavior, special values, rounding/status checks and separate latency/throughput acceptance. No architectural sqrt opcode is added as a side effect of donor availability.

### F5 — integrated verification and FPGA acceptance

Extend the reference trace to all FPR bits, FPSCR, CR and exception outcomes. Existing `sim/cosim` parsing of FP CSVs is not an executable FP oracle. Adapt audited DingusPPC vectors while encoding special values directly as bits; `ppctests.cpp:173-176` uses host `numeric_limits` for NaNs. The vector `0x7FFC...` after an `snan` operation is a quieted result, not a signaling-NaN input encoding. Triangulate software results with independent exact arithmetic/edge vectors and the primary manual; neither donor nor host floating arithmetic is its own correctness oracle.

Run prior integer regressions as well as FP integration tests. Measure isolated and integrated ALM/DSP/M10K usage, setup/hold, initiation interval and exceptional-operand behavior with pinned source hashes and constraints. Preserve existing synthesis archives. Reconcile results against the actual Table 6-5 rows and qualifications.

**Exit:** reviewed numeric/architectural coverage, reproducible mixed-language or SV build, clean integer regression, and separately recorded functional and timing acceptance. No donor game/OS success or whole-system fit substitutes for these gates.

## Recommended next implementation task

Complete F0 and a tightly bounded F1 feasibility experiment before scheduling a wholesale FPU port. The concrete deliverable is a raw-bit arithmetic harness, a semantics-gap table, a source/provenance manifest and an area/latency comparison of the implementations below. SS reuse is authorized; N64 contributes valuable resource-sharing techniques without requiring adoption of its MIPS control or numeric policies. The largest unavoidable new blocks are the PPC architectural shell and fused arithmetic.
