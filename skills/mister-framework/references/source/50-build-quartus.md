# Build: Quartus Project Layout

> Bundle version: 2026-05-18
> Pinned commits: `Template_MiSTer` @ `f35083f3b40d`, `MkDocs_MiSTer` @ `9033bd292fdc`
> Load with: [10-emu-top-level.md](10-emu-top-level.md), [12-clocks-resets-plls.md](12-clocks-resets-plls.md), [51-simulation.md](51-simulation.md), [52-mra-and-arcade.md](52-mra-and-arcade.md)
> Status mix: [C] [V] [O] [I]

**Brief reconciliation note.** The brief states "top-level entity `emu`". That is wrong against primary source: `Template.qsf:11` sets `TOP_LEVEL_ENTITY sys_top`. `emu` is the user core MODULE that `sys_top.v` instantiates; the Quartus top-level entity for the project is `sys_top`. This doc follows primary source and matches the existing neighbor doc `12-clocks-resets-plls.md`.

**Scope note.** `.rbf_cd` (cold-loadable variant) is mentioned in framework lore but is not produced by any settings in the inputs available to this doc — the `.qsf` only enables `GENERATE_RBF_FILE`. The `.rbf_cd` row in §3 is labelled `[I]` and cites no archive line.

## 1. Purpose & one-line summary

Building a MiSTer core means opening the core's `.qpf` in Quartus 17.0.x (or 13.0sp1 for the `_Q13` revision) and pressing Start Compilation; this produces an `.rbf` bitstream that the HPS loads at boot. The project layout is fixed by the `Template_MiSTer` framework: one Quartus top entity `sys_top`, one user-core module `emu`, source aggregation via `files.qip`, framework aggregation via `sys/sys.qip`, and a build-stamp generated each compile by `sys/build_id.tcl`.

## 2. The contract (must-obey)

### Project identity

- Project file (`.qpf`) declares Quartus version and revision name, e.g. `QUARTUS_VERSION = "17.0"` and `PROJECT_REVISION = "Template"`; the revision name selects the matching `.qsf`. [C] ([[`Template_MiSTer/Template.qpf:1-2`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qpf#L1-L2)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qpf#L1-L2))
- The Q13 sibling project carries `QUARTUS_VERSION = "13.1"` and `PROJECT_REVISION = "Template_Q13"`; both projects live in the same directory and share `files.qip` + `sys/`. [C] ([[`Template_MiSTer/Template_Q13.qpf:1-2`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template_Q13.qpf#L1-L2)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template_Q13.qpf#L1-L2))
- Cores MUST be developed on Quartus 17.0.x (17.0.2 recommended); newer Quartus versions are not supported by the framework. [C] ([[`Template_MiSTer/Readme.md:47-48`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Readme.md#L47-L48)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Readme.md#L47-L48))

### Target device

- The device family is `Cyclone V`; the exact part number is `5CSEBA6U23I7` (672-pin UFBGA, industrial speed grade 7). [C] ([[`Template_MiSTer/sys/sys.tcl:1-5`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.tcl#L1-L5)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.tcl#L1-L5))
- The device family/part is set by sourcing `sys/sys.tcl` from the `.qsf`; changing the device line breaks the SoC HPS interface and the pin assignments that follow. [C] ([[`Template_MiSTer/Template.qsf:76`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qsf#L76)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qsf#L76)) ([[`Template_MiSTer/sys/sys.tcl:1-5`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.tcl#L1-L5)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.tcl#L1-L5))

### Top-level entity

- The Quartus `TOP_LEVEL_ENTITY` is `sys_top`, not `emu`; `sys_top.v` is the framework wrapper that instantiates `emu` and wires HPS/video/audio. [C] ([[`Template_MiSTer/Template.qsf:11`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qsf#L11)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qsf#L11))
- `sys_top.v` is included via `sys/sys.qip`, which is in turn pulled in by the `.qsf`; cores never edit `sys_top.v` or `sys.qip`. [C] ([[`Template_MiSTer/sys/sys.tcl:219`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.tcl#L219)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.tcl#L219)) ([[`Template_MiSTer/sys/sys.qip:2`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.qip#L2)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.qip#L2))
- The user core defines `module emu ( \`include "sys/emu_ports.vh" );` in `Template.sv`; `emu`'s port list is the macro-included framework boundary. [C] ([[`Template_MiSTer/Template.sv:19-22`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L19-L22)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L19-L22))

### Source aggregation

- All user RTL is listed in `files.qip` (one `set_global_assignment` line per source file); the `.qsf` sources this file with `source files.qip` (Q17 path) or `set_global_assignment -name QIP_FILE files.qip` (Q13 path). [C] ([[`Template_MiSTer/Template.qsf:78`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qsf#L78)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qsf#L78)) ([[`Template_MiSTer/Template_Q13.qsf:45`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template_Q13.qsf#L45)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template_Q13.qsf#L45))
- `files.qip` lists the core's `.sv`/`.v` sources, the `.sdc`, and the glue file `Template.sv` (rename to `<core_name>.sv`); editing this file is the canonical way to add a source. [C] ([[`Template_MiSTer/files.qip:1-5`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/files.qip#L1-L5)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/files.qip#L1-L5)) ([[`Template_MiSTer/Readme.md:24`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Readme.md#L24)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Readme.md#L24))
- Adding files via the Quartus IDE writes them into the `.qsf` and is explicitly forbidden by the framework; the `.qsf` header warns "Do not add files to project in Quartus IDE! It will mess this file!" [C] ([[`Template_MiSTer/Template.qsf:5-7`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qsf#L5-L7)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qsf#L5-L7)) ([[`Template_MiSTer/Readme.md:20`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Readme.md#L20)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Readme.md#L20))

### Framework aggregation (`sys.qip`)

- `sys/sys.qip` enumerates the framework's HDL files using `$::quartus(qip_path)` so paths are relative to the qip; cores include `sys.qip` from the `.qsf` and never edit its contents. [C] ([[`Template_MiSTer/sys/sys.qip:1-36`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.qip#L1-L35)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.qip#L1-L35)) ([[`Template_MiSTer/sys/sys.tcl:219`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.tcl#L219)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.tcl#L219))
- The first line of `sys/sys.qip` selects the PLL variant: `set_global_assignment -name QIP_FILE [join [list $::quartus(qip_path) pll_q [regexp -inline {[0-9]+} $quartus(version)] .qip] {}]`; the regex extracts the leading digit run from `$quartus(version)` ("17.0.2" → "17", "13.1" → "13"), composing `pll_q17.qip` or `pll_q13.qip`. [C] ([[`Template_MiSTer/sys/sys.qip:1`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.qip#L1)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.qip#L1))
- `pll_q17.qip` chains to the user-supplied `rtl/pll.qip` (core author's MegaWizard output) plus framework `pll_hdmi.qip`/`pll_audio.qip`/`pll_cfg.qip`. [C] ([[`Template_MiSTer/sys/pll_q17.qip:1-4`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_q17.qip#L1-L4)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_q17.qip#L1-L4))
- `pll_q13.qip` chains to the framework-shipped `sys/pll.13.qip` (not `rtl/pll.qip`) plus `pll_hdmi.13.qip`, `pll_audio.13.qip`, and `pll_cfg.qip`; Q13 builds therefore use a framework PLL artifact, not a per-core one. [C] ([[`Template_MiSTer/sys/pll_q13.qip:1-4`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_q13.qip#L1-L4)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_q13.qip#L1-L4))

### Constraints

- The core's `.sdc` is included from `files.qip` and applies `derive_pll_clocks` + `derive_clock_uncertainty`; the framework's own `sys_top.sdc` is included separately via `sys.qip`. [C] ([[`Template_MiSTer/Template.sdc:1-2`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sdc#L1-L2)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sdc#L1-L2)) ([[`Template_MiSTer/files.qip:4`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/files.qip#L4)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/files.qip#L4)) ([[`Template_MiSTer/sys/sys.qip:3`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.qip#L3)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.qip#L3))
- The `.qsf` disables multi-corner timing analysis (`TIMEQUEST_MULTICORNER_ANALYSIS OFF`); cores are timed against a single corner only. [C] ([[`Template_MiSTer/Template.qsf:27`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qsf#L27)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qsf#L27))

### Build stamp

- `sys/build_id.tcl` runs as a `PRE_FLOW_SCRIPT_FILE` (`quartus_sh:sys/build_id.tcl`) registered in `sys/sys.qip`; it executes before each compile flow. [C] ([[`Template_MiSTer/sys/sys.tcl:216`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.tcl#L216)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.tcl#L216))
- The pre-flow script writes a Verilog file `build_id.v` containing `` `define BUILD_DATE "YYMMDD" `` at the project root; the file is rewritten only when the date string changes, preserving incremental compile state when re-running on the same day. [C] ([[`Template_MiSTer/sys/build_id.tcl:5-26`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/build_id.tcl#L5-L26)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/build_id.tcl#L5-L26))
- The same script also generates `jtag.cdf` (referenced by the `.qsf` for USB Blaster programming) parameterised by revision name and device. [C] ([[`Template_MiSTer/sys/build_id.tcl:29-49`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/build_id.tcl#L29-L49)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/build_id.tcl#L29-L49)) ([[`Template_MiSTer/sys/sys.tcl:218`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.tcl#L218)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.tcl#L218))

### Output artifact

- `GENERATE_RBF_FILE ON` in the `.qsf` directs the Assembler to emit `output_files/<revision>.rbf` after `quartus_asm` completes; this is the file copied to `_Console`/`_Computer`/etc. as the deliverable. [C] ([[`Template_MiSTer/Template.qsf:18-19`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qsf#L18-L19)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qsf#L18-L19))
- The output directory is `output_files` (relative to the project root) and contains the `.rbf`, the `.sof`, fitter reports, and assembler reports. [C] ([[`Template_MiSTer/Template.qsf:19`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qsf#L19)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qsf#L19))

## 3. Ports / signals reference

"Ports/signals" for the build topic = the project artifacts that the framework expects, with their generators and consumers. The verbatim minimal `files.qip`:

```text
// https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/files.qip#L1-L5
set_global_assignment -name VERILOG_FILE rtl/lfsr.v
set_global_assignment -name SYSTEMVERILOG_FILE rtl/cos.sv
set_global_assignment -name SYSTEMVERILOG_FILE rtl/mycore.v
set_global_assignment -name SDC_FILE Template.sdc
set_global_assignment -name SYSTEMVERILOG_FILE Template.sv
```

Artifact table:

| Artifact | Purpose | Generated by | Consumed by |
| --- | --- | --- | --- |
| `<core>.qpf` | Project file. Names Quartus version + revision. [C] | Hand-authored (cloned from `Template.qpf`). | Quartus IDE / `quartus_sh`. |
| `<core>.qsf` | Settings file. Top entity, optimisation flags, sources `sys.tcl`/`sys_analog.tcl`/`files.qip`, includes `sys/sys.qip`, registers `PRE_FLOW_SCRIPT_FILE`. [C] | Hand-authored (cloned from `Template.qsf`). May also be (illegally) modified by IDE — see §7. | Quartus toolchain at every phase. |
| `<core>.sdc` | Core-specific SDC constraints (PLL derivation, false paths). [C] | Hand-authored. | Quartus Fitter + TimeQuest. |
| `<core>.srf` | Suppressed-warnings list. Quartus message filter file. [V] | Hand-authored. Quartus IDE may extend it via the Suppress feature. | Quartus message engine. |
| `<core>.sv` | Glue logic: instantiates user core, wires `emu_ports.vh` ports, includes PLL. [C] | Hand-authored (cloned from `Template.sv`). | Quartus Synthesis (entry point for user RTL). |
| `files.qip` | Source manifest. One `set_global_assignment -name {VERILOG_FILE,SYSTEMVERILOG_FILE,VHDL_FILE,SDC_FILE} <path>` line per source. [C] | Hand-authored / edited per source change. | Quartus, via `source files.qip` (or `QIP_FILE files.qip` on Q13) in `.qsf`. |
| `sys/sys.qip` | Framework manifest: HDL files, PLL variant selector, `PRE_FLOW_SCRIPT_FILE`, `jtag.cdf`. [C] | Framework (shipped). Cores never edit. | Quartus, via `QIP_FILE sys/sys.qip` in `.qsf`. |
| `sys/sys.tcl` | Device/part assignment + DE10-Nano pin assignments for all framework pins. [C] | Framework (shipped). | Quartus, via `source sys/sys.tcl` in `.qsf`. |
| `sys/sys_analog.tcl` | SDIO + VGA + analogue audio + LED/button pin assignments (single-SDRAM I/O board). [C] | Framework (shipped). | Quartus, via `source sys/sys_analog.tcl` in `.qsf`. |
| `sys/sys_dual_sdram.tcl` | Alternative pin map: overlays SDIO/VGA pins with a second SDRAM module; sets `MISTER_DUAL_SDRAM=1`. [C] | Framework (shipped). | Quartus, sourced INSTEAD OF `sys_analog.tcl` when building for dual-SDRAM I/O board. |
| `sys/build_id.tcl` | Pre-flow script. Writes `build_id.v` + `jtag.cdf`. [C] | Framework (shipped). | `quartus_sh` (invoked by Quartus before Synthesis). |
| `build_id.v` | Generated header. Defines macro `BUILD_DATE "YYMMDD"`. [C] | `sys/build_id.tcl` at every compile. | Any RTL that `` `include "build_id.v" `` to embed build date. |
| `jtag.cdf` | Chain Description File for USB Blaster programming. [C] | `sys/build_id.tcl`. | Quartus Programmer (`quartus_pgm`). |
| `sys/pll_q17.qip` / `sys/pll_q13.qip` | PLL variant manifest, chosen at parse time from `$quartus(version)`. [C] | Framework (shipped). | Quartus, via `sys/sys.qip` line 1. |
| `output_files/<revision>.rbf` | Raw Binary File. The bitstream the HPS loads to reconfigure FPGA fabric. [C] | Quartus Assembler when `GENERATE_RBF_FILE ON`. | HPS-side `Main_MiSTer` boot path. |
| `output_files/<revision>.sof` | SRAM Object File. JTAG-loadable bitstream for development. [C] | Quartus Assembler. | `quartus_pgm` via `jtag.cdf`. |
| `output_files/<revision>.rbf_cd` | Cold-loadable RBF variant (in-place reconfig). Production path not in these inputs; see neighbor docs for the actual generation step. [I] | (Not generated by `Template.qsf` directly.) | HPS cold-reload path (out of this doc's scope). |
| `db/`, `incremental_db/`, `output_files/` | Compile databases + reports. Removed by `clean.bat`. [V] | Quartus toolchain. | Incremental compile (when `SMART_RECOMPILE ON`). |

## 4. Sequencing & timing

The compile flow is launched via the Quartus IDE "Start Compilation" button or `quartus_sh --flow compile <project>`. Phases run sequentially:

```
                            files.qip + sys.qip
                                    |
                                    v
[PRE_FLOW]   build_id.tcl --> build_id.v  +  jtag.cdf
                                    |
                                    v
[Analysis & Elaboration]   quartus_map walks Template.qsf, sources sys.tcl,
                           sys_analog.tcl (or sys_dual_sdram.tcl), files.qip.
                           Resolves $quartus(version) -> selects pll_q17.qip or
                           pll_q13.qip. Elaborates from TOP_LEVEL_ENTITY=sys_top.
                                    |
                                    v
[Synthesis]                quartus_map -> .db/ netlist
                                    |
                                    v
[Fitter (Place & Route)]   quartus_fit -> placement, routing, pin assignments
                           checked against sys.tcl / sys_analog.tcl / sys_dual_sdram.tcl
                                    |
                                    v
[TimeQuest]                quartus_sta -> single-corner static timing,
                           with Template.sdc + sys/sys_top.sdc constraints
                                    |
                                    v
[Assembler]                quartus_asm -> output_files/<revision>.sof
                           + output_files/<revision>.rbf (because
                           GENERATE_RBF_FILE ON)
                                    |
                                    v
                           Done. .rbf is the deliverable.
```

Cycle-by-cycle narration:

- **Pre-flow**: `quartus_sh` runs `sys/build_id.tcl` (registered as `PRE_FLOW_SCRIPT_FILE` in `sys/sys.tcl:216`). The script reads existing `build_id.v`, compares the build-date string, rewrites the file only on change, then regenerates `jtag.cdf` with current revision + device. Same-day re-compiles do not bump `build_id.v`, preserving downstream incremental state. [C] ([[`Template_MiSTer/sys/build_id.tcl:5-26`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/build_id.tcl#L5-L26)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/build_id.tcl#L5-L26))
- **Analysis & Elaboration**: Quartus parses the `.qsf` top-down. `set_global_assignment -name TOP_LEVEL_ENTITY sys_top` (line 11) fixes the entity. `source sys/sys.tcl` (line 76) sets device/part. `source sys/sys_analog.tcl` (line 77) adds pin assignments. `source files.qip` (line 78) adds user RTL. `set_global_assignment -name QIP_FILE sys/sys.qip` (line 219) adds the framework manifest, which fires its own Tcl on parse — including the version-string selector at `sys/sys.qip:1` that picks `pll_q17.qip` vs `pll_q13.qip`.
- **Synthesis**: Optimisation flags from `Template.qsf:38-50` apply (HIGH PERFORMANCE EFFORT, register retiming, gated-clock conversion, pre-mapping resynthesis, etc.). Warnings deemed safe are filtered by `<core>.srf`.
- **Fitter**: Pin locations and IO standards from `sys.tcl` and `sys_analog.tcl`/`sys_dual_sdram.tcl` are applied. `FITTER_EFFORT "STANDARD FIT"` and `OPTIMIZATION_MODE "HIGH PERFORMANCE EFFORT"` govern effort. [C] ([[`Template_MiSTer/Template.qsf:30-31`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qsf#L30-L31)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qsf#L30-L31))
- **TimeQuest**: SDC constraints from both `<core>.sdc` (via `files.qip`) and `sys/sys_top.sdc` (via `sys/sys.qip:3`) are merged. `derive_pll_clocks` and `derive_clock_uncertainty` apply automatic constraints to PLL outputs. [C] ([[`Template_MiSTer/Template.sdc:1-2`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sdc#L1-L2)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sdc#L1-L2))
- **Assembler**: Emits `.sof` and (because `GENERATE_RBF_FILE ON` per `Template.qsf:18`) `.rbf`. Both land in `output_files/`.

Incremental compile state is preserved between runs via `db/` and `incremental_db/` directories (`SMART_RECOMPILE ON` per `Template.qsf:22`); `clean.bat` removes them when a full rebuild is required. [V] ([[`Template_MiSTer/Template.qsf:22`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qsf#L22)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qsf#L22)) ([[`Template_MiSTer/clean.bat:6-8`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/clean.bat#L6-L8)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/clean.bat#L6-L8))

## 5. Minimal working pattern

The smallest functioning `.qsf` glue is the three lines that wire `files.qip` + `sys.qip` and the top entity. Verbatim from `Template.qsf`:

```text
// https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qsf#L11
set_global_assignment -name TOP_LEVEL_ENTITY sys_top
```

```text
// https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qsf#L76-L79
source sys/sys.tcl
source sys/sys_analog.tcl
source files.qip
set_instance_assignment -name PARTITION_HIERARCHY root_partition -to | -section_id Top
```

```text
// https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.tcl#L218-L219
set_global_assignment -name CDF_FILE jtag.cdf
set_global_assignment -name QIP_FILE sys/sys.qip
```

And the minimal `files.qip` template:

```text
// https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/files.qip#L1-L5
set_global_assignment -name VERILOG_FILE rtl/lfsr.v
set_global_assignment -name SYSTEMVERILOG_FILE rtl/cos.sv
set_global_assignment -name SYSTEMVERILOG_FILE rtl/mycore.v
set_global_assignment -name SDC_FILE Template.sdc
set_global_assignment -name SYSTEMVERILOG_FILE Template.sv
```

Per-source line types: `VERILOG_FILE` (`.v`), `SYSTEMVERILOG_FILE` (`.sv`), `VHDL_FILE` (`.vhd`), `SDC_FILE` (`.sdc`), `QIP_FILE` (`.qip`), `SOURCE_FILE` (e.g. `.vh` includes). Paths are relative to the project root.

The PLL is NOT listed in `files.qip` — it lives in `rtl/pll.qip` (for Q17) and is reached via the version-selector in `sys/sys.qip:1`. Adding `rtl/pll.qip` to `files.qip` causes double-instantiation of the PLL library. (See [12-clocks-resets-plls.md](12-clocks-resets-plls.md).)

## 6. Common variations across cores

### Quartus 17 vs Quartus 13 toolchain

- Q17 path (preferred): `.qpf` declares `QUARTUS_VERSION = "17.0"`; `.qsf` sources sys-side via `source sys/sys.tcl`, `source sys/sys_analog.tcl`, `source files.qip` (Tcl `source` command). [O] ([[`Template_MiSTer/Template.qsf:76-78`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qsf#L76-L78)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qsf#L76-L78))
- Q13 path (legacy): `.qpf` declares `QUARTUS_VERSION = "13.1"`; `.qsf` uses `source sys/sys.tcl` / `source sys/sys_analog.tcl` BUT includes `files.qip` as `set_global_assignment -name QIP_FILE files.qip` rather than `source` — a syntactic asymmetry preserved for tool compatibility. [O] ([[`Template_MiSTer/Template_Q13.qsf:43-45`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template_Q13.qsf#L43-L45)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template_Q13.qsf#L43-L45))
- Q13 also drops a number of Q17-only optimisation flags (no `PHYSICAL_SYNTHESIS_REGISTER_RETIMING`, no `ECO_OPTIMIZE_TIMING`, no `ALLOW_POWER_UP_DONT_CARE`) and adds `PLACEMENT_EFFORT_MULTIPLIER 2.0`, `OPTIMIZE_HOLD_TIMING "ALL PATHS"`, `OPTIMIZE_MULTI_CORNER_TIMING ON`. [O] ([[`Template_MiSTer/Template_Q13.qsf:31-40`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template_Q13.qsf#L31-L40)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template_Q13.qsf#L31-L40))
- PLL family selection is automatic: the regex at `sys/sys.qip:1` reads `$quartus(version)` ("17.0.2" or "13.1") and selects `pll_q17.qip` or `pll_q13.qip` accordingly; this means a single `sys/` directory supports both toolchains without per-revision `.qsf` edits. [C] ([[`Template_MiSTer/sys/sys.qip:1`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.qip#L1)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.qip#L1))
- The Q17 PLL chain points at `rtl/pll.qip` (user MegaWizard output, regenerated per core); the Q13 PLL chain points at `sys/pll.13.qip` (framework artefact, common across cores). A Q13 build therefore cannot use a per-core PLL frequency without additionally hand-editing the framework PLL files — a known limitation of the legacy path. [I] ([[`Template_MiSTer/sys/pll_q17.qip:1`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_q17.qip#L1)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_q17.qip#L1)) ([[`Template_MiSTer/sys/pll_q13.qip:1`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_q13.qip#L1)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_q13.qip#L1)) ([[`Template_MiSTer/sys/pll.13.qip:1-17`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll.13.qip#L1-L17)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll.13.qip#L1-L17))

### Single SDRAM vs Dual SDRAM I/O boards

- The default pin set is `sys/sys_analog.tcl` — SDIO + VGA + analogue audio + LED/buttons live on FPGA pins. [O] ([[`Template_MiSTer/Template.qsf:77`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qsf#L77)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qsf#L77)) ([[`Template_MiSTer/sys/sys_analog.tcl:1-72`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_analog.tcl#L1-L71)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_analog.tcl#L1-L71))
- Cores requiring a second SDRAM swap `sys_analog.tcl` for `sys_dual_sdram.tcl`, which reassigns the SDIO/VGA pins to `SDRAM2_*` and sets `VERILOG_MACRO "MISTER_DUAL_SDRAM=1"` so framework Verilog conditionally exposes the second SDRAM bus. [C] ([[`Template_MiSTer/sys/sys_dual_sdram.tcl:1-51`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_dual_sdram.tcl#L1-L51)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_dual_sdram.tcl#L1-L51))
- The two pin maps are mutually exclusive: `sys_dual_sdram.tcl` reuses PIN locations that `sys_analog.tcl` assigns to SDIO/VGA (e.g. `PIN_AH22` is `VGA_HS` in analog mode, `SDRAM2_CLK` in dual-SDRAM mode), so a core must source exactly one. [O] ([[`Template_MiSTer/sys/sys_analog.tcl:40`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_analog.tcl#L40)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_analog.tcl#L40)) ([[`Template_MiSTer/sys/sys_dual_sdram.tcl:22`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_dual_sdram.tcl#L22)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_dual_sdram.tcl#L22))
- Setting `MISTER_DUAL_SDRAM=1` is the SDRAM2 enable signal at synthesis time; for analog/SDIO mode the macro is undefined and the SDRAM2 ports are elided. [V] ([[`Template_MiSTer/sys/sys_dual_sdram.tcl:51`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_dual_sdram.tcl#L51)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_dual_sdram.tcl#L51))

### Build macros (per-core opt-ins)

- Build flags are passed as Verilog macros via `set_global_assignment -name VERILOG_MACRO "<MACRO>=1"`; documented options include `MISTER_FB`, `MISTER_FB_PALETTE`, `MISTER_DEBUG_NOHDMI`, `MISTER_DOWNSCALE_NN`, `MISTER_DISABLE_ADAPTIVE`, `MISTER_SMALL_VBUF`, `MISTER_DISABLE_YC`, `MISTER_DISABLE_ALSA`. [V] ([[`Template_MiSTer/Template.qsf:53-74`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qsf#L53-L74)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qsf#L53-L74)) ([[`Template_MiSTer/Readme.md:36-44`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Readme.md#L36-L44)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Readme.md#L36-L44))
- All of these are commented out in `Template.qsf`; a core enables a feature by un-commenting the relevant line. [V] ([[`Template_MiSTer/Template.qsf:53-74`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qsf#L53-L74)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qsf#L53-L74))

### Cross-core comparison

- Per-core comparison (NES vs SNES vs ao486 etc.) is `[deferred — reference cores not fetched]` in this bundle revision.

## 7. Anti-patterns

### A.1 Adding files via Quartus IDE instead of `files.qip`

- **Symptom:** New sources appear under random sections of `<core>.qsf`; subsequent framework updates that rewrite the `.qsf` lose them. Diff churn in `<core>.qsf` makes review impractical.
- **Cause:** Quartus's "Add files…" dialog writes `set_global_assignment -name {VERILOG_FILE,SYSTEMVERILOG_FILE,...}` lines into the active `.qsf` directly. The framework expects user sources to live in `files.qip` and `<core>.qsf` to remain a near-verbatim copy of `Template.qsf`.
- **Fix:** Edit `files.qip` in a text editor. Add one `set_global_assignment -name VERILOG_FILE rtl/<new>.v` (or `SYSTEMVERILOG_FILE`/`VHDL_FILE`) line per source. If `.qsf` was already polluted, revert to the upstream `Template.qsf` and migrate the source lines into `files.qip`.
- **Citation:** [[`Template_MiSTer/Template.qsf:5-7`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qsf#L5-L7)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qsf#L5-L7) ("Do not add files to project in Quartus IDE! It will mess this file!"); [[`Template_MiSTer/Readme.md:20`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Readme.md#L20)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Readme.md#L20), :24 @ f35083f3b40d.

### A.2 Forgetting to bump `files.qip` after adding RTL

- **Symptom:** New module compiles in isolation in a separate simulation flow but Quartus reports `Error: Verilog HDL syntax error … undefined symbol` or `Can't elaborate top-level user hierarchy`. Synthesis silently skips the new module.
- **Cause:** Source not listed in `files.qip` (or any other `.qip` sourced by `.qsf`) is never seen by `quartus_map`. The IDE shows the file as "present" because it was opened in the editor, but presence in the editor does not equal presence in the project manifest.
- **Fix:** Add the file to `files.qip` (or to a `<sub>.qip` already referenced by `files.qip`). After editing `files.qip`, close and reopen the project, or run `Processing → Update Memory Initialization File` to refresh the file list.
- **Citation:** [[`Template_MiSTer/files.qip:1-5`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/files.qip#L1-L5)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/files.qip#L1-L5) (the canonical aggregation file).

### A.3 Targeting the wrong Cyclone V part

- **Symptom:** Fitter fails with "Cannot place pin … because the I/O standard is not supported on this device" or "Device has no matching package/pin" errors against `SDRAM_*`, `HDMI_TX_*`, or `HPS_*` instances. Pin assignments from `sys/sys.tcl` are rejected.
- **Cause:** A user manually changed the device in Quartus → Assignments → Device, overriding `sys/sys.tcl:2`. The DE10-Nano part is `5CSEBA6U23I7` (672-pin UFBGA, speed grade 7); any other Cyclone V variant will not match the pin map in `sys.tcl` + `sys_analog.tcl` + `sys_dual_sdram.tcl` and the HPS HPS_LOCATION assignments in `Template.qsf:212-214`.
- **Fix:** Do not change the device. If a build mysteriously fails on pin assignments, restore `sys/sys.tcl` from upstream and remove any conflicting `set_global_assignment -name DEVICE …` from the `.qsf`.
- **Citation:** [[`Template_MiSTer/sys/sys.tcl:1-5`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.tcl#L1-L5)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.tcl#L1-L5); [[`Template_MiSTer/sys/sys.tcl:212-214`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.tcl#L212-L214)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.tcl#L212-L214).

### A.4 Mixing Q13 and Q17 PLL `.qip` files

- **Symptom:** "Entity `altera_pll` is multiply defined" or "Cannot resolve PLL output `outclk_0`" elaboration errors. PLL inferred but downstream clocks dead at runtime.
- **Cause:** Hand-editing `sys.qip` or `pll_q17.qip`/`pll_q13.qip` to load the wrong variant for the active Quartus version. The version selector at `sys.qip:1` is supposed to pick exactly one of `pll_q17.qip` or `pll_q13.qip`; bypassing it by manually listing both pulls in two incompatible PLL IP cores at once. The Q13 PLL points at `sys/pll.13.qip` (framework-shipped); the Q17 PLL points at `rtl/pll.qip` (user MegaWizard).
- **Fix:** Do not edit `sys/sys.qip` or the `pll_q*.qip` files. Let `$quartus(version)` resolve the selector. If a core needs a custom PLL frequency, regenerate `rtl/pll.v`+`rtl/pll.qip` from MegaWizard and recompile on Q17.
- **Citation:** [[`Template_MiSTer/sys/sys.qip:1`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.qip#L1)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.qip#L1); [[`Template_MiSTer/sys/pll_q17.qip:1`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_q17.qip#L1)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_q17.qip#L1); [[`Template_MiSTer/sys/pll_q13.qip:1`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_q13.qip#L1)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_q13.qip#L1).

### A.5 Not bumping `build_id` and shipping a stale `.rbf`

- **Symptom:** Released `.rbf` reports an outdated build date in the OSD About / version readout. Users believe they have an older build than they do, or the same date stamp appears in two distinct releases.
- **Cause:** `sys/build_id.tcl` rewrites `build_id.v` only when the date string differs; same-day re-compiles preserve the existing macro. If the released `.rbf` is produced from an unclean tree (e.g. forgot to re-run the compile after a fix), the embedded date is yesterday's.
- **Fix:** Always do a fresh compile before tagging a release. Optionally `del build_id.v` (or `rm build_id.v`) before the final compile so the next pre-flow regenerates it from today's clock. The `clean.bat` script already removes `build_id.v` for full rebuilds.
- **Citation:** [[`Template_MiSTer/sys/build_id.tcl:5-26`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/build_id.tcl#L5-L26)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/build_id.tcl#L5-L26); [[`Template_MiSTer/clean.bat:18`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/clean.bat#L18)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/clean.bat#L18).

## 8. Verification

- **Successful compile:** Quartus shows "Full Compilation was successful" and `output_files/<revision>.rbf` exists. The Compilation Report's Flow Summary should show 0 errors. Warnings are expected; refer to `<core>.srf` for the framework-known-safe set.
- **Build stamp embedded:** After compile, `build_id.v` exists at the project root and contains `` `define BUILD_DATE "YYMMDD" `` for today's date. Cores that surface the build date in the OSD (via `` `include "build_id.v" ``) should reflect this value.
- **TimeQuest:** TimeQuest Timing Analyzer reports must be clean for the clocks the core uses; cores set `TIMEQUEST_MULTICORNER_ANALYSIS OFF` per `Template.qsf:27`, so only the slow corner is analysed by default. Setup/hold failures on `SDRAM_*` paths usually indicate a missing `.sdc` constraint or wrong SDRAM clock phase; see `30-sdram.md`.
- **Warning hygiene:** The framework's accepted-warning baseline is captured in `Template.srf` (PLL `RST` not connected; inferred RAM read-during-write on PS/2 FIFOs; unused-but-assigned sys_top signals). Suppressed warnings should not propagate into a per-core `.srf` without review — if a NEW warning category appears, fix the RTL rather than suppressing.
- **Programmer chain:** `jtag.cdf` is regenerated each compile; opening it in Quartus Programmer should auto-populate the chain with `SOCVHPS` + the Cyclone V part. If the chain is empty, `build_id.tcl` did not run — confirm `PRE_FLOW_SCRIPT_FILE` is present in `sys/sys.qip:216` and that the project file (`.qpf`) opened cleanly.
- **Clean rebuild:** `clean.bat` (Windows) removes `db/`, `incremental_db/`, `output_files/`, `build_id.v`, `jtag.cdf`, and miscellany; a full re-compile after `clean.bat` is the canonical reproducibility check.
- **Quartus version sanity:** open Help → About in Quartus and confirm 17.0.2 (or 13.0sp1 for Q13 builds). Newer Quartus versions are not supported by the framework and may corrupt `.qsf` settings.

## 9. Provenance footer

- [[`Template_MiSTer/Template.qpf`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qpf)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qpf) — §2 (project identity)
- [[`Template_MiSTer/Template.qsf`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qsf)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.qsf) — §2 (top entity, source aggregation, build macros, output), §3 (artifact table), §4 (sequencing), §5 (minimal pattern), §7 (anti-patterns A.1, A.3, A.5), §8
- [[`Template_MiSTer/Template.sdc`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sdc)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sdc) — §2 (constraints), §3 (artifact table)
- [[`Template_MiSTer/Template_Q13.qpf`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template_Q13.qpf)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template_Q13.qpf) — §2, §6 (Q13 path)
- [[`Template_MiSTer/Template_Q13.qsf`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template_Q13.qsf)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template_Q13.qsf) — §2 (Q13 syntax), §6 (Q13 path)
- [[`Template_MiSTer/Template.sv`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv) — §2 (module emu signature)
- [[`Template_MiSTer/Template.srf`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.srf)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.srf) — §3 (artifact table), §8 (warning hygiene)
- [[`Template_MiSTer/files.qip`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/files.qip)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/files.qip) — §2 (source aggregation), §3 (artifact table), §5 (minimal pattern), §7 (A.2)
- [[`Template_MiSTer/clean.bat`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/clean.bat)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/clean.bat) — §4 (incremental compile), §7 (A.5), §8
- [[`Template_MiSTer/Readme.md`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Readme.md)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Readme.md) — §2 (Quartus version, file roles), §6 (build macros), §7 (A.1)
- [[`Template_MiSTer/sys/sys.qip`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.qip)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.qip) — §2 (sys.qip aggregation, PLL variant selector, build_id pre-flow), §3 (artifact table), §4 (analysis phase, pre-flow), §6 (variant selector), §7 (A.4)
- [[`Template_MiSTer/sys/sys.tcl`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.tcl)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.tcl) — §2 (target device), §3 (artifact table), §7 (A.3)
- [[`Template_MiSTer/sys/sys_analog.tcl`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_analog.tcl)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_analog.tcl) — §3 (artifact table), §6 (single-SDRAM pin map)
- [[`Template_MiSTer/sys/sys_dual_sdram.tcl`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_dual_sdram.tcl)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_dual_sdram.tcl) — §3 (artifact table), §6 (dual-SDRAM pin map, MISTER_DUAL_SDRAM macro)
- [[`Template_MiSTer/sys/build_id.tcl`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/build_id.tcl)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/build_id.tcl) — §2 (build stamp), §3 (artifact table), §4 (pre-flow), §7 (A.5), §8
- [[`Template_MiSTer/sys/pll.13.qip`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll.13.qip)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll.13.qip) — §2 (Q13 PLL chain), §6 (Q13 PLL artefact)
- [[`Template_MiSTer/sys/pll_q13.qip`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_q13.qip)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_q13.qip) — §2 (Q13 variant), §3 (artifact table), §6 (Q13 chain), §7 (A.4)
- [[`Template_MiSTer/sys/pll_q17.qip`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_q17.qip)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_q17.qip) — §2 (Q17 variant), §3 (artifact table), §6 (Q17 chain), §7 (A.4)
- [[`MkDocs_MiSTer/docs/developer/mistercompile.md`](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mistercompile.md)](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/mistercompile.md) — §1 (Quartus 17.0.2 recommendation, "press the play button")
