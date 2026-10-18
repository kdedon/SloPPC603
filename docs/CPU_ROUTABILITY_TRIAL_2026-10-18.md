# CPU-only routability comparison

Recorded: `quartus/chip/build.sh --docker --mister --no-fpu --jobs 2 --sys-mhz 66 --routability auto`, commit `ddf9df12e3b684700fed59e2b2ca5bfc21d6d107`, 2026-10-18. Measurement completed; this configuration is rejected for the matched CPU-only profile.

The chip build forces aggressive routability whenever the LSU pipeline is enabled. That congestion workaround was introduced for the larger MiSTer FPU configuration and also applies to CPU-only fits. The new optional `--routability auto|always|never` switch permits a controlled comparison. Omitting it preserves existing build behavior.

The first trial compares `Automatically` with the retained `Always` setting, using the IU implementation measured at 44.65/44.50 MHz. All RTL, instruction cycles, synthesis settings, seed and interface constraints remain identical. The rejected P1 EA and raw-BI changes are excluded.

```sh
quartus/chip/build.sh --docker --mister --no-fpu --jobs 2 --sys-mhz 66 --routability auto
```

Set `ENABLE_FETCH_HINTS` to 1 in the chip project for this matched DW2/LSU1/FPU0/seed1 measurement. Use the global Quartus lock and the existing CPU/memory caps. The final run QSF must show exactly one effective `AUTOMATICALLY` assignment; normalize only the run-local SDC archive path when comparing the remaining settings with the retained IU run.

Quartus Prime Lite 17.0.2 Build 602's own `get_assignment_name_info FITTER_AGGRESSIVE_ROUTABILITY_OPTIMIZATION` reports legal values Always/Automatically/Never. Its description states that aggressive routability may decrease speed while reducing wire use and routing time. Automatically chooses according to routing and timing needs, retaining the fallback. This registry query establishes the option, not a successful fit or frequency gain.

Before measurement, validate shell syntax and invalid-argument rejection and confirm all RTL/test/toolchain inputs match the retained IU cohort. Identical-input simulation evidence may be inherited explicitly; it is not a fresh test run. Compare every setup/hold corner, unconstrained-path category, resources and detailed paths after the complete physical job exits. Keep any configuration that regresses separate from integration. Full merged-batch acceptance remains a separate gate.

## Completed comparison

Auto measures **43.86 MHz hot / 43.49 MHz cold**, compared with retained Balanced/Always **44.65 / 44.50 MHz**. Both slow corners regress; limiting Fmax falls 1.01 MHz (about 2.3%). **66 MHz does not close.** Reject Auto for this matched profile and retain Always. The new optional command-line switch leaves existing default build behavior unchanged.

Setup slack at 66 MHz is -7.650 / -7.844 / +2.452 / +4.353 ns (slow hot, slow cold, fast hot, fast cold). Hold margins are +0.152 / +0.158 / +0.131 / +0.116 ns; all unconstrained-path categories are zero. Fit/detail completion is measurement evidence, not frequency acceptance.

Resources are 23,863 ALMs (+232) and 16,222 registers (+97). M10K46, MLAB54/26,624 bits, block-memory292,608 bits and DSP2 are unchanged. The effective fitter report confirms Automatically, while synthesis remains Balanced. The remaining QSF is byte-identical to the retained run after normalizing only the run-local SDC directory and the single Always-to-Automatically assignment; the run SDC is identical.

All 53 consumed SystemVerilog sources match retained IU645. All 80 detailed paths were checked against the four-corner summaries. The complete 1,177-file candidate was independently compared with the recorded Git tree, and all 87 imported/driver input hashes remained stable. These are one-seed CPU-only results, not a conclusion about all fitter policies, the full FPU or a board build.

Functional evidence is explicitly inherited from the identical IU645 RTL/test/toolchain inputs and its completed focused/manual/public-cycle cohort. Fresh trial setup checks cover shell syntax, two invalid-argument/QSF-preservation cases and actual IU source preparation with six negative guards; no new HDL runtime is claimed for this configuration-only trial. Merged-batch acceptance remains separate.

The next controlled setting comparison uses the retained Always policy and changes only the synthesis objective from Balanced to Speed. Its result is pending.
