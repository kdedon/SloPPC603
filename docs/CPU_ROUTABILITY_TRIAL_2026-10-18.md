# CPU-only routability comparison

Implementation checkpoint; physical measurement is pending.

The chip build forces aggressive routability whenever the LSU pipeline is enabled. That congestion workaround was introduced for the larger MiSTer FPU configuration and also applies to CPU-only fits. The new optional `--routability auto|always|never` switch permits a controlled comparison. Omitting it preserves existing build behavior.

The first trial compares `Automatically` with the retained `Always` setting, using the IU implementation measured at 44.65/44.50 MHz. All RTL, instruction cycles, synthesis settings, seed and interface constraints remain identical. The rejected P1 EA and raw-BI changes are excluded.

```sh
quartus/chip/build.sh --docker --mister --no-fpu --jobs 2 --sys-mhz 66 --routability auto
```

Set `ENABLE_FETCH_HINTS` to 1 in the chip project for this matched DW2/LSU1/FPU0/seed1 measurement. Use the global Quartus lock and the existing CPU/memory caps. The final run QSF must show exactly one effective `AUTOMATICALLY` assignment; normalize only the run-local SDC archive path when comparing the remaining settings with the retained IU run.

Quartus Prime Lite 17.0.2 Build 602's own `get_assignment_name_info FITTER_AGGRESSIVE_ROUTABILITY_OPTIMIZATION` reports legal values Always/Automatically/Never. Its description states that aggressive routability may decrease speed while reducing wire use and routing time. Automatically chooses according to routing and timing needs, retaining the fallback. This registry query establishes the option, not a successful fit or frequency gain.

Before measurement, validate shell syntax and invalid-argument rejection and confirm all RTL/test/toolchain inputs match the retained IU cohort. Identical-input simulation evidence may be inherited explicitly; it is not a fresh test run. Compare every setup/hold corner, unconstrained-path category, resources and detailed paths after the complete physical job exits. Keep any configuration that regresses separate from integration. Full merged-batch acceptance remains a separate gate.
