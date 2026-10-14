# MiSTer 66 MHz review, 2026-10-13

Recorded: `mister/build.sh --fpu-compact --dual --lsu-pipe --sys-mhz 66 --seed 2 --jobs 2`, commit b9f52ae8ef3b52159c341c7aa2ecaa565074da76 plus uncommitted changes, 2026-10-13.

One full MiSTer build used the pinned Quartus 17.0.2 image, two CPU cores, an
8 GiB memory ceiling with swap disabled, and the repository Quartus lock.
The configuration includes the DDR3 framebuffer, COMPACT FPU, dual dispatch
and pipelined LSU. The 45 MHz published build and default clock remain intact.

## Result

Analysis and synthesis passed. Fitting failed with errors 170143 and 11802: the
design could not route in the Cyclone V. Quartus reported excessive routing
demand from hold-time delay insertion (message 188005). TimeQuest did not run;
there is no fresh setup/hold result, Fmax, or usable 66 MHz bitstream.

| Resource | Failed-fit estimate | Device capacity |
|---|---:|---:|
| ALMs | 40,180 (96%) | 41,910 |
| Registers | 40,730 | — |
| M10K blocks | 232 (42%) | 553 |
| DSP blocks | 20 (18%) | 112 |

The CPU-clock hold-delay summary totals 4,629.7 ns of inserted delay across
paths; this is an aggregate routing cost, not a path delay or slack. Memory
and DSP capacity are not the exhausted resources. The failed fit's entity
estimates identify these large direct logic consumers:

| Entity | Direct ALMs, approximate |
|---|---:|
| Core integration/control | 4,007 |
| Instruction queue | 3,702 |
| Pipelined LSU | 2,738 |
| Completion queue | 2,614 |
| Rename storage/control | 2,497 |
| Special unit, excluding children | 2,466 |

These figures exclude each entity's children and do not establish achievable
area savings. Start the next pass with instruction-queue payload/storage and
completion/rename metadata, then the short control paths that require hold
padding. Preserve dispatch width, ownership, cancellation, ordered retirement
and documented cycle behavior. A seed sweep cannot establish the cause.

Synthesis also reported an existing framework integration warning: `ascal.mode`
expects five bits while its connection supplies four. It needs review before
a future board acceptance claim; the dispatch change does not touch it.
The later [candidate review](IQ_RENAME_REVIEW_2026-10-13.md) records the maintained
framework fix and a successful synthesis without that width warning. It also
records rejection of the IQ/rename candidates due to increased logic.

## Changes and verification

The dispatch operand mux uses parallel masks while preserving source priority,
completion qualification and exact producer identity. Its timing and area
benefit remain unmeasured: there was no same-source baseline fit. The
[execution record](EXECUTION_CONTRACT.md#operand-mux-review-2026-10-13) records
the passing focused tests, dual-width trace comparison, strict lint and spec
checks. Full CI, the x-random sweep and the full FPU suite were not rerun; this
is not a release acceptance round and changes no completion percentage.

Doom and Quake retain 320 × 200 rendering and now copy at 1×; the
[benchmark description](BENCHMARKS.md#doom) explains comparison limits. The
changed presentation objects compiled for Doom BE/LE and smoke variants and
Quake BE/LE/soft-float with the pinned cross-compiler and strict warnings.
The build also rebuilt the loadable images. No new FPS or frame-CRC result
was measured. Four canonical skills now cite the reference at fixed commit
8697f64edee5d19eaeeca59542bb7262659f0efb and all pass skill validation.

The failed-fit reports are retained in the project's output directory for
inspection; this record's reproduction command and counts are the evidence.
Temporary Quartus databases were removed after the run.
