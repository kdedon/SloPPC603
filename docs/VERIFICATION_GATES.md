# Verification gates: CI, coverage and reference acceptance

Recorded: `make -C sim -j2 ci` then `make -C sim clean-cache`, commit 4560b1a plus uncommitted documentation and waiver-reason edits, 2026-09-27.
Recorded: `make -C sim -j2 reference-acceptance`, commit 4560b1a plus the same edits, 2026-09-27.

| Gate | Result | Wall time |
| --- | --- | ---: |
| `ci` | Pass. Regression (274 Python checks: 231 + 28 + 15), firmware built in the container, 27 compiled-firmware profiles, coverage 74.2% (1,251 of 1,686 `rtl/` points) with 15 waived control arms over 15 runs | 54 min |
| `reference-acceptance` | Pass. Reference 8,500 snapshots; memory, BAT and three cached profiles 9,881 retirements each; stress suites of 32 seeds at 512 blocks with 130,492 and 130,251 snapshots | 7 min |

Times are on the shared development machine with `-j2`; `ci` shares it with
other jobs. The coverage step alone rebuilds two benches and runs 15 images.

## `make -C sim ci`

One command for the continuous gate, in order:

1. `regression`: strict lint, spec checks, recovery model and the full test set.
2. `ci-firmware`: `make -C toolchain firmware-all` with the host
   cross-compiler, else the same build in the pinned container through
   `toolchain/build-in-container.sh`.
3. `make -C toolchain rtl-all`: every compiled-firmware profile, including
   `rtl-mmu-stress-cached` and `rtl-mmu-stress-retry`.
4. `coverage`: the coverage build, runs and summary below.

Run it as `make -C sim -j2 ci`, then `make -C sim clean-cache`. It needs
Docker (or the cross-compiler) and the sibling DingusPPC checkout that
`regression` uses.

## `make -C sim coverage`

Builds `tb_compiled_mmu_stress_firmware` and `tb_compiled_cacheops_firmware`
with Verilator `--coverage-line` (through `toolchain/run-rtl-smoke.py
--coverage`), runs all fourteen `mmu-stress-retry` modes and the cacheops
image, and writes one coverage file per run under `sim/build/coverage/`.
`make -C sim coverage-summary` reruns only the summary.

`sim/tools/coverage_summary.py` merges the runs by source location (a point
counts as covered if any run and any instance reached it), prints points and
coverage per `rtl/` file, and fails when:

- total `rtl/` line coverage is below `COVERAGE_MIN` (72%, set a little
  under the measured value to absorb RTL churn), or
- a case arm in a control module (bus masters, line reader, two-master
  select, BAT/page router, I-cache and its manager, TLB service, fetch) is
  unreached and not listed in `sim/coverage_waivers.txt`.

A waiver names the file, the source line and the reason. It also reports
waivers that no longer match an uncovered arm.

### Review of uncovered control arms

Arms this gate reached only after the stimulus was extended:

- `LANE_WAIT` (router, both lanes): a translation miss arriving while the
  other side's translation is in flight. Reached by the micro-TLB contention
  loop in the MMU stress image.
- `BUS_READ_REPLACEMENT`, `LINE_BEAT_REPLACEMENT`: DRTRY held without a
  same-edge TA. Reached by the retry target's one- to three-cycle DRTRY.
- The scalar master's halfword-at-offset-0 lane decode: reached by a `sth`/
  `lhz` pair in the image.

Waived arms (reasons in the waiver file):

| Arm | Why unreached |
| --- | --- |
| `default` arms (6 files) | Every enum value has an arm. |
| `LANE_FATAL`, `ROUTE_IFETCH_FATAL`, `LINE_DATA_ERROR_RELEASE` | Need TEA or an instruction transport error. Directed benches cover them; the stress TEA hook is reserved for the machine-check work. |
| `BUS_ADDR_ABORT`, `LINE_ADDR_ABORT` | Need AACK in the TS cycle, a target protocol violation; `tb_bus60x` and `tb_bus60x_line_read` cover them. |
| `IC_REFILL_DRAIN` | Flash invalidate while an accepted refill waits for data; the managed wrapper sequences invalidation after the refill. `tb_icache` covers it. |
| `TLB_REFILL`, `TLB_INVALIDATE_SET`, reserved kind | External TLB management requests; this top ties the port off and CPU loads and `tlbie` use the prepared path. |

Whole-file figures below the total (decode, divider, IU, special) reflect
instruction mix: the firmware does not execute every opcode or divide edge.
Those units have their own directed and reference suites; line coverage here
is a measure of the combined translated cached path, not of ISA breadth.

## `make -C sim reference-acceptance`

The long DingusPPC comparison, outside `regression` and `ci`: every reference
profile (`test-reference`, `-memory`, `-bat`, `-cached`, `-managed`,
`-cache-disabled`) and two `run_reference_stress.py` suites of 32 seeds each
at the generator's 512-block maximum. DingusPPC is a consistency reference,
not a source of truth. The compiled firmware corpus is not compared against
DingusPPC; its benches check their own results.
