<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
<!-- Copyright (c) 2026 Kevin Dedon -->
# CI and release tooling

Everything a clean GitHub runner needs is here; the workflows are in
`.github/workflows/`.
Release gates and the configuration of record are in [RELEASE.md](RELEASE.md).

| File | Purpose |
| --- | --- |
| `ci/pins.env` | Container pins, sourced by every Quartus, MiSTer and toolchain script |
| `ci/setup.sh` | Fetches DingusPPC, benchmark sources and the MiSTer framework at their pins |
| `quartus/fit_summary.py` | Writes one JSON summary per Quartus build |
| `ci/summary_table.py` | Renders summaries as a markdown table |
| `ci/release_notes.py` | Writes release notes from summaries, pins and git metadata |
| `ci/source-archive.sh` | Corresponding source of a benchmark image (repository plus fetched sources) |
| `ci/free-disk.sh` | Frees runner disk for the Quartus image |
| `ci/step.sh` | Runs a workflow step; on failure posts its error lines and the end of its output as an annotation, readable without login |
| `.github/workflows/` | Workflows: `quick`, `mister-unstable`, `release` |

## Pins

`ci/pins.env` is plain `KEY=value`: shell scripts source it, Python reads it, and
a workflow can append it to `$GITHUB_ENV`. `QUARTUS_IMAGE` and `TOOLCHAIN_IMAGE`
still override the defaults for local experiments.

| Key | Value | Local state (2026-09-30) |
| --- | --- | --- |
| `QUARTUS_IMAGE_PIN` | `theypsilon/quartus-lite-c5@sha256:f638634d…` (tag `17.0.2.docker0`) | present, 11.2 GB unpacked |
| `TOOLCHAIN_BASE_IMAGE` | `debian:bookworm-20250811-slim@sha256:b1a74148…` | absent; pulled by the next `build-container.sh` |
| `TOOLCHAIN_DEBIAN_SNAPSHOT` | `20250811T000000Z` | |
| `TOOLCHAIN_IMAGE_PIN` | `ppc603e-cross:bookworm-20250811`, built locally, never pulled | present, image ID `sha256:5461ed74…` |

Other pins stay beside the code that uses them: DingusPPC `LAST_VERIFIED` in
`sim/cosim/reference_checkout.py`, the framework commit and tree digest in
`mister/fetch-framework.sh`, and per-file SHA-256s in
`toolchain/demo/fetch-benchmarks.sh`.

To move a container pin:

1. `docker pull <image>:<tag>` and read the digest with
   `docker image inspect --format '{{json .RepoDigests}}' <image>:<tag>`.
2. Replace the value in `ci/pins.env`. For the Debian base, also move
   `TOOLCHAIN_DEBIAN_SNAPSHOT` and the package versions in `toolchain/Dockerfile`.
3. Rebuild (`toolchain/build-container.sh`, or a Quartus fit) and record the
   result in the owning document; a new Quartus image needs fresh fits of every top.

## Build summaries

These builds write `<revision>.summary.json` in their `output_files/`:

| Build | Summary |
| --- | --- |
| `quartus/{translated,integrated,timer-bat,chip,chip602}/build.sh` | `output_files/<revision>.summary.json`, and `summary.json` in the evidence directory |
| `quartus/report-target-paths.sh <top>` | adds the `target` entry to that top's summary |
| `quartus/fpu-production/synthesize.sh --docker fullfit` (and `full602fit`) | `output_files/<variant>/reports/summary.json` |
| `mister/build.sh` | `mister/output_files/mister[-<suite>][-native].summary.json`; a published build also gets `build/mister/<rbf name>.json` |

Schema 1:

| Field | Meaning |
| --- | --- |
| `name`, `revision`, `top`, `device`, `quartus`, `image`, `note` | build label, Quartus revision, top entity, device, Quartus version, container image, free text (MiSTer: firmware and video) |
| `commit`, `dirty`, `date` | `HEAD` and whether tracked files differed when the summary was written; UTC time |
| `resources` | `alms`, `registers`, `m10k`, `mlab_labs`, `mlab_bits`, `block_memory_bits`, `dsp`, `pins`; `null` when the report lacks it |
| `clocks_ns` | SDC period per clock (from the STA report; empty when only the `.sta.summary` survives) |
| `slack` | `{clock: {setup/hold/recovery/removal: {corner: ns}}}`; corners `slow_100c`, `slow_-40c`, `fast_100c`, `fast_-40c`, or `default` for the FPU harness |
| `timing_met` | every listed slack is non-negative |
| `pass_50mhz` | `timing_met` when every clock is constrained at 20 ns, else `null` |
| `target` | re-timing by `report-target-paths.sh`: `period_ns`, `mhz`, `worst_setup_slack` per corner, `failing_endpoints`, `met`; `null` until it runs |
| `rbf` | MiSTer only: `name` and `sha256` of the bitstream |

Example, shortened to one corner per analysis. Resources and slack are from a chip fit;
the `commit`, `date` and `target` values are illustrative:

```json
{
  "schema": 1, "name": "chip", "commit": "93f121b…", "dirty": false,
  "date": "2026-09-30T12:25:40Z", "revision": "ppc603e_chip",
  "top": "ppc603e_measure", "device": "5CSEBA6U23I7",
  "quartus": "17.0.2 Build 602 07/19/2017 SJ Lite Edition",
  "image": "theypsilon/quartus-lite-c5@sha256:f638634d…", "note": null,
  "resources": {"alms": 10528, "registers": 12176, "m10k": 36, "mlab_labs": 56,
                "mlab_bits": 27648, "block_memory_bits": 270080, "dsp": 2, "pins": 0},
  "clocks_ns": {"core_clk": 20.0},
  "slack": {"core_clk": {"setup": {"slow_100c": 4.667}, "hold": {"fast_-40c": 0.12}}},
  "timing_met": true, "pass_50mhz": true,
  "target": {"period_ns": 15.152, "mhz": 66.0, "worst_setup_slack": {"slow_100c": -0.159},
             "failing_endpoints": 7, "met": false},
  "rbf": null
}
```

A summary records a build; it is not verification evidence. Cite the command
and commit as [AGENTS.md](../AGENTS.md#recording-evidence) requires.

```sh
python3 ci/summary_table.py quartus/*/output_files/*.summary.json            # one row per build
python3 ci/summary_table.py --detail mister/output_files/*.summary.json       # plus slack per clock and corner
```

`worst_setup_slack` comes from `<out>.worst.txt`, which `target_paths.tcl` writes
for every clock and corner. Without it (older runs), only corners with failing
endpoints appear.

## Setup on a clean runner

```sh
ci/setup.sh                        # dingusppc, benchmarks, framework
ci/setup.sh benchmarks framework   # MiSTer build only
```

DingusPPC is fetched at `LAST_VERIFIED` into `../dingusppc` (or
`DINGUSPPC_DIR`) and checked by commit id; the others check SHA-256s. Nothing is
vendored.

## Release notes

```sh
python3 ci/release_notes.py --tag v1.0 --since v0.9 <summary.json>... > notes.md
```

The notes name the commit, carry the fit and timing table, list the pins with
the MiSTer framework revision and its GPL-2.0 source, and warn when a summary
comes from another commit or a modified tree. A `mister-embench` summary adds
the GPL-3.0 source offer, which points at the `ppc603e-embench-source.tar.gz` asset
written by `ci/source-archive.sh`; a `mister-nbench` summary adds a
no-redistribution warning ([BENCHMARKS.md](BENCHMARKS.md#sources-and-licences)).
`--images <file>...` lists the published program images with their SHA-256 and applies
the same two notices to an Embench or nbench image. `--embench-source <file>` also
writes `ppc603e-embench.SOURCE.txt`: the Embench image's source pointer (the pinned
Embench-IoT commit and this repository at the release commit, as permalinks).

## Workflows

| Workflow | Trigger | Does |
| --- | --- | --- |
| `quick.yml` | push, pull request | Verilator 5.020 from Ubuntu 24.04; `lint`, `check-spec`, five focused benches |
| `mister-unstable.yml` | push to `main`, except docs-only pushes | MiSTer build of the test core (`--fpu-compact --dual --lsu-pipe`, fitter seeds 2–5 until timing passes); replaces the `unstable` prerelease with the `.rbf`, its summary, the self-test, Embench and Whetstone program images, the Embench source pointer and archive, and notes |
| `release.yml` | tag `v*` | five measurement fits with 66 MHz re-timing, two FPU fits, MiSTer builds (the test core, or `vars.MISTER_SUITES`) with the self-test, Embench and Whetstone program images (plus `vars.MISTER_IMAGES`), then a release with notes, the Embench source pointer and archive |

Runner limits (GitHub-hosted `ubuntu-24.04`, public repository):

- About 14 GB free disk. The Quartus image is 11.2 GB unpacked, so every Quartus
  job first runs `ci/free-disk.sh`, which removes preinstalled SDKs.
- 6 h per job; the workflows cap jobs at 5 h. The first green `mister-unstable` run
  (commit `28e5531`, 2026-10-03) took 33 min end to end; the other fits are
  unmeasured on a runner. Each job pulls the image again, which takes minutes and counts
  against Docker Hub's pull limits.
- 10 GB of Actions cache per repository: too small to cache the Quartus image.

The simulation gates (`make -C sim ci`, `reference-acceptance`, `xrand-sweep`)
are not in the workflows: they need DingusPPC, take hours, and stay the
maintainer's pre-tag gate via `make -C sim release-check`.

Repository settings the workflows need:

1. Settings → Actions: allow Actions and give `GITHUB_TOKEN` write access to
   contents (the release jobs use `gh release`).
2. Optional: set the repository variable `MISTER_SUITES` (JSON list; `test` is the
   test core, `default` the core without options, any other entry a `--suite` core),
   or `MISTER_IMAGES` (space-separated image names, e.g. `embench`), to publish more;
   review the licence notes above first. nbench images are never published by default.
3. Run `mister-unstable` once by hand (`workflow_dispatch`) and check the disk
   and time headroom in its log before relying on it.
