# Skills

Claude Code skills shared by everyone working on this core. `.claude/skills` links here, so Claude Code
loads them automatically in this repository. Each skill is a folder with a `SKILL.md`; the `description`
in its frontmatter decides when it triggers. Skills can also be read directly as design checklists.

## Baseline (general HDL and writing)

| Skill | Use for |
|---|---|
| `hdl-coding-guidelines` | SystemVerilog rules, clocks/resets, FSMs, handshakes, CDC, BRAM/DSP inference, SDC, Quartus reports on Cyclone V. Source docs in `references/source/`. |
| `mister-framework` | MiSTer `emu` top level, `hps_io`, SDRAM/DDRAM, video/audio, build, simulation. Source docs in `references/source/`. |
| `hdl-design-organization` | Packages, structs/enums, config records, RAM wrappers, SPR definitions with masks, build hygiene. |
| `concise-writing` | Comments, commit messages and replies. |

## CPU microarchitecture

| Skill | Use for |
|---|---|
| `cpu-reference-cores` | Index of five mined FPGA CPUs (N64 VR4300, PSX R3000A, Saturn SH-2, SPARC V8, ARM7TDMI) with full reports. |
| `cpu-pipeline-control` | Stall, flush, hazards, forwarding, operand capture. |
| `cpu-decode-control` | Decode records, predecode, microcode, exception pseudo-ops. |
| `cpu-register-files` | MLAB/M10K/flop regfiles, ports, RDW, rename-by-index. |
| `cpu-cache-design` | I/D cache hit path, fill, replacement, stores, invalidate, snoop. |
| `cpu-mmu-tlb` | µTLB/TLB/BAT hierarchy, protection folding, invalidation. |
| `cpu-precise-exceptions` | Commit, committed shadows, redirect, interrupts, serialization. |
| `cpu-execution-units` | ALU, rotate/mask, multiplier, divider, flags, latency. |
| `cpu-fpu-design` | FPU integration, datapath sharing, PowerPC FPSCR/NaN semantics. |
| `cpu-memory-interface` | BIU, request queues, ordering, arbitration, latency hiding. |
| `cpu-fmax-critical-paths` | CPU critical loops, fixes, CPU-specific SDC rules. |
| `cpu-verification-debug` | Retirement traces, state injection, debug injection, error flags. |

Each skill stands alone. Evidence links go to upstream sources on GitHub, pinned to the reviewed
commit, or to the live document; nothing depends on a local checkout or on another skill.

## Adding or changing a skill

Keep one topic per skill, rules stated as *rule → why → evidence*, and a checklist at the end.
Cite code as a GitHub permalink at a fixed commit. Put long source material under the skill's
`references/`. Update this table.
