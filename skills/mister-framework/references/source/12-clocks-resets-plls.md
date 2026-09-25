# Clocks, Resets, and PLLs

> Bundle version: 2026-05-18
> Pinned commits: `Template_MiSTer` @ `f35083f3b40d`
> Load with: [10-emu-top-level.md](10-emu-top-level.md), [30-sdram.md](30-sdram.md), [40-video.md](40-video.md), [41-audio.md](41-audio.md)
> Status mix: [C] [V] [O] [I]

**Missing-source note.** The brief lists `sys/pll.v` but no such file exists. The system-side selector chain works as follows: `files.qip` adds `sys/pll_q[regexp -inline {[0-9]+} $quartus(version)].qip`, which expands to `pll_q17.qip` or `pll_q13.qip`; each of those points to `rtl/pll.qip`; that file declares the user-provided `rtl/pll.v` (a MegaWizard-generated Altera PLL). Cores regenerate `rtl/pll.v` per-core to set their own `clk_sys` frequency. The audio and HDMI PLLs (`sys/pll_audio.v`, `sys/pll_hdmi.v`) are fixed framework artefacts and shipped under `sys/` directly.

## 1. Purpose & one-line summary

The framework owns three PLLs (HDMI pixel, audio, system reconfig manager) and a reset distribution network; the core owns exactly one PLL (`pll`) that derives `clk_sys` from `CLK_50M`. The core must export `clk_sys`, `CLK_VIDEO`, `CE_PIXEL`, and consume `RESET` (async) plus the fixed-rate `CLK_AUDIO` input.

## 2. The contract (must-obey)

### Reset semantics

- `RESET` arrives at `emu` as an asynchronous active-high level; `emu_ports.vh` comments it as "Async reset from top-level module. Can be used as initial reset." [C] ([[`Template_MiSTer/sys/emu_ports.vh:4-6`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L4-L6)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L4-L6))
- Cold reset (FPGA reconfig) propagates `RESET=1` to `emu` for the full duration that `sysmem_lite.reset_out` is asserted; user PLLs lose lock during reconfig and re-lock on power-up. [C] ([[`Template_MiSTer/sys/sys_top.v:601-609`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L601-L609)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L601-L609))
- Warm reset (HPS-initiated, "Reset and close OSD") is signalled via `gp_out[31:30]` at the SPI boundary; `sys_top.v` latches it into `reset_req` then routes it through `sysmem_lite` to produce `RESET` to `emu`. [C] ([[`Template_MiSTer/sys/sys_top.v:581-597`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L581-L597)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L581-L597))
- The user `pll` in `Template.sv` is hardwired with `.rst(0)`, so the user PLL is NOT bounced by warm reset; `clk_sys` remains running and locked across `RESET` pulses. [C] ([[`Template_MiSTer/Template.sv:113-118`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L113-L118)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L113-L118))
- The HDMI PLL IS bounced by warm reset via `.rst(reset_req)`; pixel clock disappears during reset, video output blanks. [C] ([[`Template_MiSTer/sys/sys_top.v:1042-1049`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1042-L1049)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1042-L1049))
- The audio PLL is NOT bounced by warm reset: `.rst(0)` is hardwired, so `clk_audio` (24.576 MHz) is free-running across `RESET`. [C] ([[`Template_MiSTer/sys/sys_top.v:1572-1577`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1572-L1577)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1572-L1577))
- Cores combine `RESET` with OSD reset (`status[0]`) and OSD reset button (`buttons[1]`) into an internal `reset`; this is convention, not framework-required. [V] ([[`Template_MiSTer/Template.sv:120`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L120)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L120))
- `sysmem_lite.reset_hps_cold_req` is wired to the physical reset button (`btn_r`); a cold-reset combination on the I/O board re-triggers HPS-side reconfig flow but does not directly clock `emu`'s `RESET` line — DE10-nano has no GPIO reset signal, so the core's `RESET` only fires on warm-reset SPI command or initial bring-up. [C] ([[`Template_MiSTer/sys/sys_top.v:604-612`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L604-L612)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L604-L612))

### `clk_sys` contract

- `clk_sys` is a core-OWNED, core-DRIVEN clock; the core instantiates its own `pll` from `CLK_50M` (which `sys_top.v` ties to `FPGA_CLK2_50`). [C] ([[`Template_MiSTer/Template.sv:113-118`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L113-L118)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L113-L118)) ([[`Template_MiSTer/sys/sys_top.v:1758`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1758)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1758))
- `clk_sys` is NOT a named port of `emu`; it is smuggled into the framework as bit 36 of `HPS_BUS[45:0]`, packed by `sys_top.v` and unpacked by `hps_io`. [C] ([[`Template_MiSTer/sys/sys_top.v:1760-1763`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1760-L1763)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1760-L1763))
- The `HPS_BUS` bundle from sys_top to emu carries: `{f1, HDMI_TX_VS, clk_100m, clk_ihdmi, ce_hpix, hde_emu, hhs_fix, hvs_fix, io_wait, clk_sys, io_fpga, io_uio, io_strobe, io_wide, io_din, io_dout}`; `clk_sys` is bidirectional in effect (driven by core, observed by hps_io and `sys_top.v` post-counters running on it). [C] ([[`Template_MiSTer/sys/sys_top.v:1760-1763`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1760-L1763)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1760-L1763))
- `clk_sys` frequency is not constrained by the framework — Template's default `rtl/pll.v` ships an unspecified frequency the core author replaces via MegaWizard. [C] ([[`Template_MiSTer/rtl/pll.v:8-13`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/rtl/pll.v#L8-L13)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/rtl/pll.v#L8-L13))
- `clk_sys` SHOULD be high enough that all core CE rates (CPU, audio, pixel) divide cleanly from it; it is the universal CE-domain master. [V] ([[`Template_MiSTer/Template.sv:131-150`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L131-L150)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L131-L150))

### `CLK_VIDEO` / `CE_PIXEL` contract

- `CLK_VIDEO` is an OUTPUT from `emu` driving the video mixer / OSD / HDMI scaler chain inside `sys_top.v`. [C] ([[`Template_MiSTer/sys/emu_ports.vh:11-12`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L11-L12)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L11-L12))
- `CE_PIXEL` is an OUTPUT from `emu`, MUST be a one-cycle pulse on `CLK_VIDEO`, and marks each valid pixel; sub-pixel-rate `CLK_VIDEO` with gated `CE_PIXEL` is the normal mode. [C] ([[`Template_MiSTer/sys/emu_ports.vh:14-16`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L14-L16)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L14-L16))
- `CE_PIXEL` MUST be derived from `CLK_VIDEO`; the comment "Must be based on CLK_VIDEO" is a hard rule because downstream mixer/scaler register video on `CLK_VIDEO`. [C] ([[`Template_MiSTer/sys/emu_ports.vh:14-16`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L14-L16)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L14-L16))
- The simplest legal pattern assigns `CLK_VIDEO = clk_sys` and lets `CE_PIXEL` come from the core's pixel generator; Template does exactly this. [V] ([[`Template_MiSTer/Template.sv:149-150`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L149-L150)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L149-L150))
- Multiple resolutions are explicitly supported by varying `CE_PIXEL` cadence on a single `CLK_VIDEO`; the framework tolerates non-uniform CE_PIXEL streams. [C] ([[`Template_MiSTer/sys/emu_ports.vh:14-15`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L14-L15)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L14-L15))
- Inside `sys_top.v`, the user's `CLK_VIDEO` is renamed `clk_vid` and feeds `sync_fix`, the video mixer, OSD, and (when not direct-video) is the source of `hdmi_tx_clk` via `cyclonev_clkselect`. [C] ([[`Template_MiSTer/sys/sys_top.v:1707-1708`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1707-L1708)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1707-L1708), [`1262-1272`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1262-L1272), [`1784-1785`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1784-L1785))

### Fixed-rate clocks from framework to emu

- `CLK_AUDIO` is an INPUT to `emu` at 24.576 MHz, generated by `sys/pll_audio` from `FPGA_CLK3_50`; cores must not assume reconfigurability. [C] ([[`Template_MiSTer/sys/emu_ports.vh:82`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L82)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L82)) ([[`Template_MiSTer/sys/sys_top.v:1572-1577`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1572-L1577)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1572-L1577))
- `pll_audio` instantiates an Altera PLL configured for `gui_reference_clock_frequency=50.0` and `gui_output_clock_frequency0=24.576`. [C] ([[`Template_MiSTer/sys/pll_audio.v:53-68`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_audio.v#L53-L68)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_audio.v#L53-L68))
- `DDRAM_CLK` is an OUTPUT from `emu`; the core supplies the clock for its DDR3 (HPS f2sdram) access port. Typical convention is to drive it from a system-PLL output or `clk_sys`. [C] ([[`Template_MiSTer/sys/emu_ports.vh:98-100`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L98-L100)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L98-L100)) [V] ([[`Template_MiSTer/Template.sv:31`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L31)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L31))
- `SDRAM_CLK` is an OUTPUT from `emu`; the core both supplies and consumes (for sample timing) the SDRAM clock; defer phase/skew rules to `30-sdram.md`. [C] ([[`Template_MiSTer/sys/emu_ports.vh:111-113`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L111-L113)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L111-L113))
- `HDMI_TX_CLK` is driven by `sys_top.v` (not by the core); it is the pixel clock at the HDMI transmitter, sourced from either `clk_vid` (direct-video path) or `hdmi_clk_out` (scaler PLL output). [C] ([[`Template_MiSTer/sys/sys_top.v:1262-1297`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1262-L1297)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1262-L1297))
- `clk_100m` (sysmem clock) and `clk_ihdmi` (HDMI input clock to OSD via HPS_BUS) cross into the `emu` boundary as members of `HPS_BUS` and are consumed by `hps_io` for downstream blocks; cores do not directly use them. [I] ([[`Template_MiSTer/sys/sys_top.v:1761-1763`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1761-L1763)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1761-L1763))

### HDMI PLL adjustment

- `pll_hdmi` has fractional reconfig ports (`reconfig_to_pll[63:0]`, `reconfig_from_pll[63:0]`); `pll_cfg_hdmi` is the Altera reconfig core that the framework manages, and `pll_hdmi_adj.vhd` is the "lowlat" closed-loop adjuster fed by scaler measurements. [C] ([[`Template_MiSTer/sys/pll_hdmi.v:8-23`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_hdmi.v#L8-L23)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_hdmi.v#L8-L23)) ([[`Template_MiSTer/sys/sys_top.v:1042-1084`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1042-L1084)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1042-L1084))
- `pll_hdmi_adj` snoops scaler outputs via `lltune[15:0]` (encoded fields: DE/VS/IL/IF/oVS/clk_in/clk_out), computes a frequency/phase trim using a Schmurtz state machine, and writes M-counter + M-fractional-K registers back via `pll_cfg_hdmi`. [C] ([[`Template_MiSTer/sys/pll_hdmi_adj.vhd:6-44`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_hdmi_adj.vhd#L6-L44)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_hdmi_adj.vhd#L6-L44), [`256-428`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_hdmi_adj.vhd#L256-L428))
- Adjustment is enabled only when `llena=1` (lowlat mode); when disabled, the original M/K are restored from `mfrac_mem`. [C] ([[`Template_MiSTer/sys/pll_hdmi_adj.vhd:305-314`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_hdmi_adj.vhd#L305-L314)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_hdmi_adj.vhd#L305-L314))
- `pll_hdmi_adj` clock domain is `FPGA_CLK1_50` (50 MHz framework clock), with `reset_na = ~reset_req` (active-low async). [C] ([[`Template_MiSTer/sys/sys_top.v:1001-1002`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1001-L1002)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1001-L1002))
- `MISTER_DEBUG_NOHDMI` build flag elides the HDMI PLL and its adjuster entirely; `led_locked` is then forced to 0. [C] ([[`Template_MiSTer/sys/sys_top.v:997-1018`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L997-L1018)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L997-L1018), [`1040-1050`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1040-L1050))

### Framework input clocks

- `FPGA_CLK1_50`, `FPGA_CLK2_50`, `FPGA_CLK3_50` are three independent 50 MHz pin inputs; the framework uses `CLK1` for HDMI PLL & adjuster, `CLK2` for `CLK_50M` to `emu` and reset latching, `CLK3` for audio PLL. [C] ([[`Template_MiSTer/sys/sys_top.v:25-27`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L25-L27)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L25-L27), [`1001`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1001), [`1574`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1574), [`1758`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1758)) ([[`Template_MiSTer/sys/sys_top.v:582`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L582)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L582))

## 3. Ports / signals reference

Verbatim emu-side clock and reset declarations:

```verilog
// https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L1-L16
//Master input clock
input         CLK_50M,

//Async reset from top-level module.
//Can be used as initial reset.
input         RESET,

//Must be passed to hps_io module
inout  [45:0] HPS_BUS,

//Base video clock. Usually equals to CLK_SYS.
output        CLK_VIDEO,

//Multiple resolutions are supported using different CE_PIXEL rates.
//Must be based on CLK_VIDEO
output        CE_PIXEL,
```

```verilog
// https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L82
input         CLK_AUDIO, // 24.576 MHz
```

```verilog
// https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L98-L113
//High latency DDR3 RAM interface
//Use for non-critical time purposes
output        DDRAM_CLK,
input         DDRAM_BUSY,
output  [7:0] DDRAM_BURSTCNT,
output [28:0] DDRAM_ADDR,
input  [63:0] DDRAM_DOUT,
input         DDRAM_DOUT_READY,
output        DDRAM_RD,
output [63:0] DDRAM_DIN,
output  [7:0] DDRAM_BE,
output        DDRAM_WE,

//SDRAM interface with lower latency
output        SDRAM_CLK,
output        SDRAM_CKE,
```

Sys-top side framework PLL & reset declarations:

```verilog
// https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L25-L27
input         FPGA_CLK1_50,
input         FPGA_CLK2_50,
input         FPGA_CLK3_50,
```

```verilog
// https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1572-L1577
pll_audio pll_audio
(
    .refclk(FPGA_CLK3_50),
    .rst(0),
    .outclk_0(clk_audio)
);
```

```verilog
// https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1042-L1049
pll_hdmi pll_hdmi
(
    .refclk(FPGA_CLK1_50),
    .rst(reset_req),
    .reconfig_to_pll(reconfig_to_pll),
    .reconfig_from_pll(reconfig_from_pll),
    .outclk_0(hdmi_clk_out)
);
```

Port table — every clock/reset signal crossing the `emu` boundary:

| Signal | Dir | Width | Clock | Active | Meaning | Driven by | Drives |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `CLK_50M` | in | 1 | self (50 MHz) | rising edge | Framework master reference; sourced from `FPGA_CLK2_50` pin [C] | `sys_top.FPGA_CLK2_50` | core's `pll` refclk; user reset-button samplers |
| `RESET` | in | 1 | async | high | Async warm-reset level from framework [C] | `sysmem_lite.reset_out` ← `reset_req` ← `gp_out[31:30]` SPI command | core's internal reset combiner |
| `HPS_BUS[36]` (=`clk_sys`) | out (bundled) | 1 | self | rising edge | Core's system clock — DRIVEN by core, sampled by `hps_io` and `sys_top` counters [C] | core's `pll.outclk_0` | hps_io; status latch; sys_top SPI status FSM |
| `CLK_VIDEO` | out | 1 | self | rising edge | Pixel-domain clock to mixer/OSD/scaler [C] | core (commonly = `clk_sys`) | `sys_top.clk_vid` → video_mixer, OSD, HDMI clkselect |
| `CE_PIXEL` | out | 1 | `CLK_VIDEO` | high (1-cycle pulse) | Per-valid-pixel strobe on `CLK_VIDEO` [C] | core | video_mixer, OSD, scaler input gate |
| `CLK_AUDIO` | in | 1 | self (24.576 MHz) | rising edge | Fixed audio sample clock from `sys/pll_audio` [C] | `pll_audio.outclk_0` ← `FPGA_CLK3_50` | core's audio resamplers / mixers |
| `DDRAM_CLK` | out | 1 | self | rising edge | Avalon-MM clock for HPS f2sdram bridge access — supplied by core [C] | core (typ. `clk_sys` or PLL output) | `sysmem_lite.ram1_clk` |
| `SDRAM_CLK` | out | 1 | self | rising edge | Clock output to SDRAM chip; core-driven [C] | core (typ. phase-shifted PLL output) | SDRAM device |
| `HPS_BUS[44]` (=`clk_ihdmi`) | in (bundled) | 1 | self | rising edge | Scaler/HDMI input pixel clock observed by OSD/IO inside hps_io [I] | `sys_top.clk_vid` (via bundle) | hps_io OSD timing |
| `HPS_BUS[45]` (=`HDMI_TX_VS`) | in (bundled) | 1 | `clk_ihdmi` | high (vsync) | Output VS used inside hps_io [I] | sys_top.HDMI_TX_VS | hps_io |
| `HPS_BUS[43]` (=`clk_100m`) | in (bundled) | 1 | self (100 MHz) | rising edge | Sysmem clock observable inside hps_io [I] | `sysmem_lite.clock` | hps_io |

Cold-reset chain inside `sys_top.v` (not directly visible to `emu`, but documented for completeness):

```verilog
// https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L581-L612
reg reset_req = 0;
always @(posedge FPGA_CLK2_50) begin
    reg [1:0] resetd, resetd2;
    reg       old_reset;

    //latch the reset
    old_reset <= reset;
    if(~old_reset & reset) reset_req <= 1;

    //special combination to set/clear the reset
    //preventing of accidental reset control
    if(resetd==1) reset_req <= 1;
    if(resetd==2 && resetd2==0) reset_req <= 0;

    resetd  <= gp_out[31:30];
    resetd2 <= resetd;
end
```

Note: `cold_reset` is not exposed as an `emu` port; "cold reset" in this framework means FPGA reconfiguration. The HPS handles cold-vs-warm reset semantics on its side and only ever exposes warm reset via `gp_out[31:30]` to the FPGA. [I]

## 4. Sequencing & timing

### Cold-boot sequence

```
power-on
    |
    v
FPGA reconfigures from SD bitstream
    |
    v  (Cyclone V config done)
FPGA_CLK1/2/3_50 stable -----.
    |                          \
    v                           v
sys/pll_audio locks (24.576)   sys/pll_hdmi locks (default 148.5)
    |                                            |
    v                                            v
core/pll locks (clk_sys)                  pll_cfg_hdmi reconfig idle
    |                                            |
    v                                            v
sysmem_lite reset_out=1 (until HPS hand-off completes)
    |
    v  reset_req cleared via gp_out[31:30] handshake
sysmem_lite reset_out=0
    |
    v
RESET to emu deasserts ; emu starts executing on clk_sys with RESET=0
```

[C] cold-boot order derived from sys_top.v PLL `.rst()` ties and `sysmem_lite` instantiation. ([[`Template_MiSTer/sys/sys_top.v:601-612`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L601-L612)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L601-L612), [`1042-1049`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1042-L1049), [`1572-1577`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1572-L1577))

### Warm-reset sequence (OSD "Reset" / SPI gp_out[31:30])

```
FPGA_CLK2_50    |‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
gp_out[31:30]   0     0     1     1     2     2     0
resetd          0  0  0  0  1  1  1  1  2  2  2  2  0  0
resetd2         0  0  0  0  0  0  1  1  1  1  2  2  2  2
reset_req       0  0  0  0  1  1  1  1  1  1  1  0  0  0
                                                  ^ resetd==2 && resetd2==0
                                                    clears reset_req
sysmem reset_out  ____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\____
RESET to emu      ____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\____
pll_hdmi.rst      ____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\____  (HDMI PLL DROPS LOCK)
core pll.rst      __________________________________   (TIED LOW, NEVER RESETS)
pll_audio.rst     __________________________________   (TIED LOW, NEVER RESETS)
clk_sys           free-running across the reset pulse
clk_audio         free-running across the reset pulse
hdmi_clk_out      gone during reset; re-locks on deassert
```

Warm reset duration is HPS-driven — typically tens of milliseconds — far longer than any pipeline depth. [I] ([[`Template_MiSTer/sys/sys_top.v:581-597`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L581-L597)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L581-L597))

### HDMI PLL adjustment cycle (per-frame)

The `pll_hdmi_adj` Schmurtz FSM runs on `FPGA_CLK1_50` and writes to `pll_cfg_hdmi` after each measurement cycle (one trigger per output frame when `llena=1`).

```
State transitions in pll_hdmi_adj.Schmurtz (clock = FPGA_CLK1_50):

  sIDLE
   |  up='1' && mulco!=mul
   v
  sW1 (write M counter, address 0x04, data = mulco)
   |  pwrite='1' & o_waitrequest='0'
   v
  sW2 (wait for ack)
   |  pwrite='1' & o_waitrequest='0'
   v
  sW3 (write M fractional K, address 0x07, data = mfrac[31:0])
   |
   v
  sW4 (wait for ack)
   |
   v
  sW5 (write start-reconfig trigger, address 0x02, data = 0x0000_0001)
   |
   v
  sW6 (wait for ack)
   |
   v
  sIDLE (HDMI PLL re-locks at new fractional M)

Fast path: sIDLE -> sW3 -> sW4 -> sW5 -> sW6 -> sIDLE when mulco == mul (M unchanged).
```

[C] FSM transitions and register addresses 0x04 (M counter), 0x07 (M fractional K), 0x02 (start trigger). ([[`Template_MiSTer/sys/pll_hdmi_adj.vhd:236-238`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_hdmi_adj.vhd#L236-L238)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_hdmi_adj.vhd#L236-L238), [`377-425`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_hdmi_adj.vhd#L377-L425))

Frequency/phase measurement is gated on `lltune[15:0]` from the scaler; the adjuster computes log-spaced trim magnitudes (`logcpt` 0..24) and applies fractional shifts of `mfrac_ref` per pulse. [C] ([[`Template_MiSTer/sys/pll_hdmi_adj.vhd:198-232`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_hdmi_adj.vhd#L198-L232)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_hdmi_adj.vhd#L198-L232), [`358-371`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_hdmi_adj.vhd#L358-L371))

`locked` (driven to `led_locked`) asserts only when both frequency and phase error are within ~2^-18 of nominal (`off_v>=18 AND ofp_v>=18`), and only while `llena=1`. [C] ([[`Template_MiSTer/sys/pll_hdmi_adj.vhd:296-300`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_hdmi_adj.vhd#L296-L300)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_hdmi_adj.vhd#L296-L300))

## 5. Minimal working pattern

The minimal PLL+reset pattern from `Template.sv`. Verbatim.

```verilog
// https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L110-L120
///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys;
pll pll
(
    .refclk(CLK_50M),
    .rst(0),
    .outclk_0(clk_sys)
);

wire reset = RESET | status[0] | buttons[1];
```

Underlying PLL stub (regenerated per-core via MegaWizard; default ships an unconfigured single-output PLL):

```verilog
// https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/rtl/pll.v#L7-L22
`timescale 1 ps / 1 ps
module pll (
        input  wire  refclk,   //  refclk.clk
        input  wire  rst,      //   reset.reset
        output wire  outclk_0, // outclk0.clk
        output wire  locked    //  locked.export
    );

    pll_0002 pll_inst (
        .refclk   (refclk),   //  refclk.clk
        .rst      (rst),      //   reset.reset
        .outclk_0 (outclk_0), // outclk0.clk
        .locked   (locked)    //  locked.export
    );

endmodule
```

Quartus-version-aware QIP selector (selects between Quartus 17 and Quartus 13 build artefacts):

```tcl
# https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.qip#L1
set_global_assignment -name QIP_FILE           [join [list $::quartus(qip_path) pll_q [regexp -inline {[0-9]+} $quartus(version)] .qip] {}]
```

```tcl
# https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_q17.qip#L1
set_global_assignment -name QIP_FILE           rtl/pll.qip
```

`CLK_VIDEO`/`CE_PIXEL` assignment (Template uses the cheapest legal pattern: `CLK_VIDEO = clk_sys`):

```verilog
// https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L149-L150
assign CLK_VIDEO = clk_sys;
assign CE_PIXEL = ce_pix;
```

## 6. Common variations across cores

Direct cross-core verification is `[deferred — reference cores not fetched]`. Framework-implied variation patterns from `sys/` and the build chain:

- Single-PLL cores: derive `clk_sys` (and any per-pixel CE) entirely from one MegaWizard `pll` with one to four outputs (CPU clock, video clock, SDRAM clock, SDRAM phase-shifted clock). Implied by Template's default `pll` module exposing a single `outclk_0`. [I] ([[`Template_MiSTer/rtl/pll.v:8-13`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/rtl/pll.v#L8-L13)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/rtl/pll.v#L8-L13))
- Multi-PLL cores: a second user-PLL is added in `rtl/` when video upconversion or chip-specific clock domains (e.g. CD audio, FDC) require independent jitter / phase. Framework imposes no upper limit on user PLL count — `derive_pll_clocks` in `Template.sdc` discovers all of them. [I] ([[`Template_MiSTer/Template.sdc:1`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sdc#L1)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sdc#L1))
- Quartus 13 vs Quartus 17 build: `sys.qip` selects `pll_q[VER].qip` at compile time via regexp on `$quartus(version)`; both flavours target the same user `rtl/pll.qip`, but the framework HDMI/audio PLLs ship as both `pll_hdmi.qip` (Q17) and `pll_hdmi.13.qip` (Q13). [C] ([[`Template_MiSTer/sys/sys.qip:1`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.qip#L1)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.qip#L1)) ([[`Template_MiSTer/sys/pll_q13.qip:1-4`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_q13.qip#L1-L4)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_q13.qip#L1-L4))
- `MISTER_DEBUG_NOHDMI` cores: skip HDMI PLL and adjuster entirely; useful for analog-only debug builds, halves the PLL footprint. [C] ([[`Template_MiSTer/sys/sys_top.v:997-1018`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L997-L1018)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L997-L1018), [`1040-1050`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1040-L1050))
- `MISTER_DUAL_SDRAM` cores: a second SDRAM chip with its own clock (`SDRAM2_CLK`) is added to `sys_top.v`; typically driven from a second output of the user `pll`. [O] ([[`Template_MiSTer/sys/sys_top.v:60-68`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L60-L68)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L60-L68))
- `MISTER_FB` cores: enable the HDMI framebuffer path; this adds an optional `FB_PAL_CLK` clock-domain crossing if `MISTER_FB_PALETTE` is also defined, otherwise no new clock. [C] ([[`Template_MiSTer/sys/emu_ports.vh:40-66`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L40-L66)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L40-L66))

## 7. Anti-patterns

### A.1 Treating `RESET` as synchronous to `clk_sys`

- **Symptom:** Intermittent or board-specific reset failures: state machines sometimes don't reset cleanly, registers latch metastable values, or reset-deassert glitches re-fire one cycle later.
- **Cause:** `emu_ports.vh:4-6` documents `RESET` as ASYNC. It is generated in the `FPGA_CLK2_50` domain (`sys_top.v:582`) but propagated through `sysmem_lite` with no synchronizer guarantee at the `emu` boundary. Connecting it directly to a `posedge clk_sys` `always` block as an edge-sensitive signal violates the contract; deassertion can violate setup on `clk_sys` flops.
- **Fix:** Synchronize `RESET` into `clk_sys` with a two-flop synchronizer before use as a level (or as an async-clear input to flops that only need the asynchronous assert path). Or: combine it with `status[0] | buttons[1]` into a `reset` wire that drives a dedicated reset distribution synchronizer per clock domain.
- **Citation:** [[`Template_MiSTer/sys/emu_ports.vh:4-6`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L4-L6)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L4-L6); [[`Template_MiSTer/sys/sys_top.v:582-597`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L582-L597)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L582-L597)

### A.2 Forgetting `CE_PIXEL` on a pipelined video stage

- **Symptom:** Scaler shows tearing, duplicated columns, or scrambled output; OSD overlay misaligns; `pll_hdmi_adj` cannot converge (`led_locked` stays low).
- **Cause:** A pipeline register that processes `CLK_VIDEO`-domain data was clocked by `posedge CLK_VIDEO` without gating its enable on `CE_PIXEL`. Downstream `sys_top.v` mixer/OSD/scaler assume one valid sample per `CE_PIXEL` pulse, and they advance their own pointers on that strobe; advancing data without the strobe produces extra "ghost" pixels.
- **Fix:** Either gate every pipeline register's load enable with `CE_PIXEL`, or set `CLK_VIDEO` itself to the actual pixel rate (and tie `CE_PIXEL = 1'b1`). The Template's cheap pattern (`CLK_VIDEO = clk_sys`, `CE_PIXEL = ce_pix`) is the canonical reference.
- **Citation:** [[`Template_MiSTer/sys/emu_ports.vh:14-16`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L14-L16)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L14-L16); [[`Template_MiSTer/Template.sv:149-150`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L149-L150)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L149-L150)

### A.3 Resetting the user `pll` on warm reset

- **Symptom:** Every OSD reset causes a multi-millisecond freeze where the core appears hung; SDRAM/DDRAM resync; visible pixel-clock disturbance even though the framework "intends" only a soft reset.
- **Cause:** Connecting `.rst(reset_req)` or `.rst(RESET)` to the user `pll` violates Template's `.rst(0)` convention. The framework expects `clk_sys` to be free-running so warm reset is sub-second; bouncing the PLL costs the entire lock time (~100 us to 10 ms depending on configuration) plus downstream re-synchronization.
- **Fix:** Hardwire user `pll.rst = 0` per Template. If a deliberate clock-tree restart is required, drive only the downstream synchronous reset, not the PLL reset.
- **Citation:** [[`Template_MiSTer/Template.sv:113-118`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L113-L118)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L113-L118)

### A.4 Using `clk_audio` for core logic

- **Symptom:** Core logic that runs on `clk_audio` (24.576 MHz) misses timing in cores expecting >24 MHz operation; cross-domain to `clk_sys` introduces latency that breaks frame timing; audio glitches when `clk_audio` and `clk_sys` race.
- **Cause:** `CLK_AUDIO` is a FIXED 24.576 MHz framework-supplied clock intended for audio sample emission only. It is in a different clock domain from `clk_sys` and the framework never synchronizes them.
- **Fix:** Confine `clk_audio` to the audio sample emission path (DAC, sigma-delta, I2S writer); generate any required audio-tap CE pulses on `clk_sys` and cross sample-rate streams with proper CDC (handshake or async FIFO).
- **Citation:** [[`Template_MiSTer/sys/emu_ports.vh:82`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L82)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L82); [[`Template_MiSTer/sys/sys_top.v:1572-1577`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1572-L1577)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1572-L1577)

## 8. Verification

- **PLL lock check.** `Template.sv` does not surface the user `pll.locked` signal; expose it by tying `.locked(led_locked_user)` from the user PLL to `LED_USER` during bring-up, then watch the LED. Note the framework's `led_locked` is the HDMI adjuster lock, not the user PLL. ([[`Template_MiSTer/sys/sys_top.v:1006`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1006)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1006))
- **Warm-reset round-trip.** Toggle OSD "Reset and close OSD" (which sets `status[0]` and `buttons[1]`); confirm core internal state machines reinitialize but `clk_sys` and `clk_audio` activity LEDs do not blank. Confirmed by `.rst(0)` on user `pll` and `pll_audio`. ([[`Template_MiSTer/Template.sv:113-118`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L113-L118)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L113-L118)) ([[`Template_MiSTer/sys/sys_top.v:1572-1577`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1572-L1577)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1572-L1577))
- **HDMI lock indication.** During lowlat mode, `led_locked` (HDMI adjuster `locked` output) should assert within a few output frames after `cfg_done`; persistent failure indicates `lltune` measurement is failing (scaler-side issue) or `clk_vid` frequency mismatch. See `pll_hdmi_adj.vhd:296-300`.
- **MiSTer.ini flags.** Set `direct_video=1` to bypass the HDMI scaler and feed `clk_vid` directly to `hdmi_tx_clk`; this is the cleanest test of whether glitches are scaler-induced or core-induced. ([[`Template_MiSTer/sys/sys_top.v:1262-1272`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1262-L1272)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1262-L1272))
- **Simulation hook.** `pll_hdmi_adj.vhd:125-132` contains `pragma synthesis_off` initial-block defaults so the FSM can simulate with `reset_na=0` cleanly; user testbenches should hold `reset_na='0'` for at least one clock before deassert.
- **Timing constraints.** `Template.sdc` ships only `derive_pll_clocks` + `derive_clock_uncertainty`; Quartus auto-derives all PLL output clocks. Cores adding asynchronous paths between `clk_sys`/`clk_audio`/`clk_vid` must add `set_false_path` or `set_clock_groups -asynchronous` to suppress spurious unconstrained-path warnings. ([[`Template_MiSTer/Template.sdc:1-4`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sdc#L1-L4)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sdc#L1-L4))

## 9. Provenance footer

- [[`Template_MiSTer/Template.sv`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv) — used for §2 (`clk_sys` contract, reset combine), §5 (minimal pattern), §7 (A.1, A.3)
- [[`Template_MiSTer/Template.sdc`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sdc)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sdc) — used for §6, §8 (timing-constraint default)
- [[`Template_MiSTer/files.qip`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/files.qip)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/files.qip) — used for missing-source note (selector chain)
- [[`Template_MiSTer/sys/emu_ports.vh`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh) — used for §2, §3 (verbatim port quotes), §7 (A.1, A.2, A.4)
- [[`Template_MiSTer/sys/sys_top.v`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v) — used for §2 (reset chain, framework PLL bindings), §3 (port table, reset chain quote), §4 (cold/warm sequences), §6, §7, §8
- [[`Template_MiSTer/sys/sys.qip`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.qip)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys.qip) — used for missing-source note, §5, §6
- [[`Template_MiSTer/sys/pll_q17.qip`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_q17.qip)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_q17.qip) — used for missing-source note, §5
- [[`Template_MiSTer/sys/pll_q13.qip`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_q13.qip)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_q13.qip) — used for §6
- [[`Template_MiSTer/sys/pll_audio.v`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_audio.v)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_audio.v) — used for §2 (audio clock contract)
- [[`Template_MiSTer/sys/pll_hdmi.v`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_hdmi.v)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_hdmi.v) — used for §2 (HDMI PLL reconfig), §3 (sys-top side quote)
- [[`Template_MiSTer/sys/pll_hdmi_adj.vhd`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_hdmi_adj.vhd)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/pll_hdmi_adj.vhd) — used for §2 (adjuster contract), §4 (Schmurtz FSM diagram), §8
- [[`Template_MiSTer/rtl/pll.v`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/rtl/pll.v)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/rtl/pll.v) — used for §2 (`clk_sys` defaults), §5 (PLL stub quote), §6
- [[`Template_MiSTer/rtl/pll.qip`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/rtl/pll.qip)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/rtl/pll.qip) — used for missing-source note
