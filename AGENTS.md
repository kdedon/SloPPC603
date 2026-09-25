# Working in this repository

A PowerPC 603e-compatible CPU in SystemVerilog for Cyclone V (MiSTer DE10-Nano),
verified with Verilator. The near-term deliverable is a restricted MVP: single-issue,
big-endian integer CPU with supervisor mode, precise exceptions, interrupts,
software-managed MMU and a cached 60x path. The full 603e (dual dispatch, FPU,
data cache, coherence, modes) is the long-term target.

## Start here

Read in this order before changing anything:

1. [docs/plans/current/PLAN.md](docs/plans/current/PLAN.md): priorities and next acceptance gates.
2. [docs/SYSTEM_COMPLETION.md](docs/SYSTEM_COMPLETION.md): accepted behavior, gaps and MVP score.
3. [docs/FULL_CPU_COMPLETION_AUDIT.md](docs/FULL_CPU_COMPLETION_AUDIT.md): full-603e score.
4. The feature contract for the area you touch (see [Documentation](#documentation)).
5. [docs/CODING_CONVENTIONS.md](docs/CODING_CONVENTIONS.md): project HDL and verification rules.

## Skills

`skills/` holds the shared skills; it is the canonical copy. `.claude/skills` links to it
so Claude Code loads them automatically. Other agents should read the relevant
`skills/<name>/SKILL.md` before starting matching work. [skills/README.md](skills/README.md)
indexes them.

| Work | Load |
|---|---|
| Any RTL, SDC, CDC, BRAM/DSP inference or Quartus report | `hdl-coding-guidelines` |
| File/package structure, structs, config, RAM wrappers, SPR definitions | `hdl-design-organization` |
| MiSTer top level, `hps_io`, SDRAM/DDRAM, video/audio, MiSTer build | `mister-framework` |
| Stall, flush, hazards, forwarding, issue queues | `cpu-pipeline-control` |
| Decode, uop records, microcoded or multi-cycle instructions | `cpu-decode-control` |
| GPR/FPR files, rename storage, port counts | `cpu-register-files` |
| I/D caches, fills, store buffers, cache maintenance, snooping | `cpu-cache-design` |
| BAT, segments, TLB, miss handling, invalidation | `cpu-mmu-tlb` |
| Exceptions, interrupts, commit, recovery, serialization | `cpu-precise-exceptions` |
| ALU, rotate/shift, multiply, divide, XER/CR flags | `cpu-execution-units` |
| Floating point | `cpu-fpu-design` |
| 60x BIU, request queues, ordering, arbitration | `cpu-memory-interface` |
| Timing failures or pre-fit review | `cpu-fmax-critical-paths` |
| Traces, reference comparison, state injection, debug | `cpu-verification-debug` |
| Precedent from other FPGA CPUs | `cpu-reference-cores` |
| Comments, commit messages, docs | `concise-writing` |

Precedence when sources disagree: the 603e manuals (per
[docs/references/SOURCES.md](docs/references/SOURCES.md)), then accepted feature
contracts in `docs/`, then [`docs/CODING_CONVENTIONS.md`](docs/CODING_CONVENTIONS.md), then skills. Skills are
design guidance, not architectural authority.

When adding or editing a skill, keep one topic per skill, cite code as a GitHub
permalink at a fixed commit, and never link local paths or other skills.

## Layout

| Path | Contents |
|---|---|
| `rtl/` | Synthesizable SystemVerilog; `*files.f` lists give compile order per profile |
| `tb/` | Testbenches and bus-functional models |
| `sim/` | Makefile, Python tools/checkers (`tools/`), reference co-simulation (`cosim/`), recovery model |
| `toolchain/` | Pinned PowerPC cross-compiler and firmware builds |
| `quartus/` | Cyclone V projects (`integrated/`, `timer-bat/`, `icache/`) and build scripts |
| `docs/` | Plans, scorecards, references and per-feature contracts |
| `skills/` | Shared agent skills |

Generated output (`sim/build/`, `quartus/db`, `output_files`, evidence archives,
`*.log`, `*.rpt`) is ignored; never commit it.

## Commands

Run from the repository root. Requires Verilator 5.020, GNU Make, Python 3 and g++ (C++20).

```sh
make -C sim regression   # strict lint, spec checks, recovery model, full test set
make -C sim lint         # strict RTL lint only
make -C sim check-spec   # metadata and checker tests (fast)
make -C sim <target>     # one focused bench, e.g. test-core-tlb-miss
make -C sim clean-cache  # after builds finish: reclaim precompiled headers
```

Reference comparison targets (`test-reference*`) need a sibling `../dingusppc`
checkout; it is not vendored. Firmware builds: see [toolchain/README.md](toolchain/README.md).
FPGA fits: see [quartus/README.md](quartus/README.md) and
[docs/INTEGRATED_SYNTHESIS_BASELINE.md](docs/INTEGRATED_SYNTHESIS_BASELINE.md).

## Documentation

- `docs/plans/current/`: active plans. [`PLAN.md`](docs/plans/current/PLAN.md) is the entry point;
  [`MVP_EXECUTION_PLAN.md`](docs/plans/current/MVP_EXECUTION_PLAN.md) holds MVP waves and the accepted-round ledger;
  [`TASK_PLAN.md`](docs/plans/current/TASK_PLAN.md) defines full-603e scope (P00–P30); [`ORIGINAL_DESIGN_BRIEF.md`](docs/plans/current/ORIGINAL_DESIGN_BRIEF.md)
  describes the target machine. Floating-point work starts from
  [docs/FPU_REUSE_ASSESSMENT.md](docs/FPU_REUSE_ASSESSMENT.md) (donor evaluation, F0–F5 plan).
- `docs/plans/stale/`: history only. Do not take instructions or status from it.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): datapath overview and the history of how it grew.
- `docs/references/`: distilled source contracts (ISA matrix, timing, 60x bus, source audit).
- Feature documents in `docs/` come in families: `FEATURE.md` or `*_PROTOCOL.md` /
  `*_CONTRACT.md` define behavior, `FEATURE_VERIFICATION.md` records acceptance
  evidence, `FEATURE_FIRMWARE.md` records compiled-program checks.
- Dated documents (`*_2026-09-20.md`, status reviews) are snapshots; they say so at the top.

## Completion tracking

Exactly two documents own percentages:

- [`docs/SYSTEM_COMPLETION.md`](docs/SYSTEM_COMPLETION.md): MVP score and per-system rows.
- [`docs/FULL_CPU_COMPLETION_AUDIT.md`](docs/FULL_CPU_COMPLETION_AUDIT.md): full-603e score.

After each accepted implementation round:

1. Update the affected scorecard rows and recompute `sum(weight × completion) / 100`.
2. Add a round entry to the scorecard and to [`MVP_EXECUTION_PLAN.md`](docs/plans/current/MVP_EXECUTION_PLAN.md) stating the old and new
   weighted values, and which checks were fresh versus inherited.
3. Update the full audit only for architectural milestones; verification-only rounds need not move it.
4. Refresh [`PLAN.md`](docs/plans/current/PLAN.md) when priorities or gates change.

Keep weights fixed unless scope changes explicitly. Other documents link to these two
instead of restating current numbers.

## Recording evidence

A verification record states what anyone can rerun and check:

- the exact command or make target;
- the commit it ran on (and "plus uncommitted changes" if the tree was dirty);
- the date, pass/fail, and the counts that matter (checks, retirements, cycles);
- what the test establishes and what it does not.

Never cite log files, JSON summaries, source-hash manifests or scratch directories
(`/tmp`, `build/`, home directories). They disappear and nobody else can open them.
If output must be kept, make the test print its own summary, or commit a small,
deliberate artifact next to the test. Reproduction commands use repo-relative paths.

## Working rules

- A feature is done only when implementation and its acceptance test land together.
  Unsupported behavior rejects explicitly; a diagnostic halt is never an implemented exception.
- Strict lint with no blanket waivers; any local waiver is narrow and states a reason.
- Report lint, simulation, synthesis, fit and timing results separately. A passing fit
  is not timing closure; a green lint is not conformance.
- Never trade architectural correctness for timing silently. Add a stage, or put the trade
  behind a named, documented parameter.
- New RTL changes need a fresh fit before any timing claim.
- Cite external code as GitHub permalinks at fixed commits; never reference local paths.
- Follow `concise-writing` for comments and commit messages.
