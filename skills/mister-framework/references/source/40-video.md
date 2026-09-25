# 40 — Video: emu boundary contract

> Bundle version: 2026-05-18
> Pinned commits: [`Template_MiSTer`](https://github.com/MiSTer-devel/Template_MiSTer/tree/f35083f3b40d24853abea4cd3f77caccbd71d5de), [`MkDocs_MiSTer`](https://github.com/MiSTer-devel/MkDocs_MiSTer/tree/9033bd292fdcc98f30dfe47eed7d61371181454a)
> Load with: [40a-video-pipeline.md](40a-video-pipeline.md), [12-clocks-resets-plls.md](12-clocks-resets-plls.md), [41-audio.md](41-audio.md), [10-emu-top-level.md](10-emu-top-level.md), [11-conf-str.md](11-conf-str.md)
> Status mix: `[C]`, `[V]`, `[I]`
>
> NOTE: This topic exceeded the 50 KB soft cap, so it is split. **This file** covers the `emu` video boundary (`VGA_*`, `VIDEO_ARX/ARY`, `HDMI_*`, `CLK_VIDEO`/`CE_PIXEL`, top-level tie-offs). The framework-internal pipeline modules (`video_mixer`, `video_freak`, `video_cleaner`, `video_freezer`, `scandoubler`, `scanlines`, `shadowmask`, `gamma_corr`, `hq2x`, `vga_out`, `yc_out`, `ascal`, `arcade_video`, `screen_rotate`) live in [40a-video-pipeline.md](40a-video-pipeline.md).

## 1. Purpose & one-line summary

A MiSTer core's video starts at the `emu` boundary as positive-pulse RGB+sync gated by `CE_PIXEL` on `CLK_VIDEO`. The framework's `sys/` pipeline (covered in 40a) routes that one source to two independent sinks: an HDMI scaler chain (driven by `ascal.vhd` using DDR3 as a framebuffer) and an analog VGA chain (with `scanlines`, optional `yc_out` for composite/S-Video, and a 6-bit DAC on the IO board). The core's job at the boundary is to deliver a clean source — the framework handles scaling, gamma, scandoubling, deinterlacing, freezing, OSD overlay, and shadow-mask CRT emulation.

## 2. The contract (must-obey)

Emu-boundary clock and pacing
- `CE_PIXEL` MUST be a 1-cycle clock-enable pulse on `CLK_VIDEO`; multi-resolution support depends on it. [C] ([[`Template_MiSTer/sys/emu_ports.vh:14-16`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L14-L16)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L14-L16))
- `CLK_VIDEO` is the base video clock and is usually `clk_sys`. [C] ([[`Template_MiSTer/sys/emu_ports.vh:11-12`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L11-L12)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L11-L12))
- `CLK_VIDEO` MUST be > 40 MHz for the framework's scandoubler / hq2x / ascal stack to work; if the core's pixel clock is lower, `CE_PIXEL` paces a faster `CLK_VIDEO`. [C] ([[`MkDocs_MiSTer/docs/developer/emu.md:53`](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/emu.md#L53)](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/emu.md#L53))

Sync polarity and DE
- `VGA_HS`, `VGA_VS` driven by the emu MUST be positive-polarity pulses (active-high during sync); `sys_top` inverts for the analog DAC and `s_fix` auto-detects polarity downstream. [C] ([[`Template_MiSTer/sys/video_mixer.sv:42-45`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/video_mixer.sv#L42-L45)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/video_mixer.sv#L42-L45))
- `VGA_DE` MUST equal `~(HBlank | VBlank)` and be 1 only during active pixels. [C] ([[`Template_MiSTer/sys/emu_ports.vh:28`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L28)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L28))
- `VGA_R/G/B/HS/VS/DE` SHOULD be updated only on cycles where `CE_PIXEL` is high; sampling stages downstream gate identically. [C] ([[`Template_MiSTer/sys/video_mixer.sv:206-216`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/video_mixer.sv#L206-L216)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/video_mixer.sv#L206-L216))
- `VGA_F1` is the field flag for interlaced content. [C] ([[`Template_MiSTer/sys/emu_ports.vh:29`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L29)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L29))
- `VGA_SL[1:0]` selects analog scanlines weight (0=off, 1=25%, 2=50%, 3=75%), consumed by the framework's `scanlines` module. [C] ([[`Template_MiSTer/sys/scanlines.v:36-55`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/scanlines.v#L36-L55)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/scanlines.v#L36-L55))

Color depth
- `VGA_R/G/B` are 8-bit unsigned at the emu boundary; sys_top truncates to 6-bit for the IO board analog DAC and forwards 8-bit to HDMI. [C] ([[`Template_MiSTer/sys/emu_ports.vh:23-25`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L23-L25)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L23-L25))

Aspect ratio
- `VIDEO_ARX[11:0]`/`VIDEO_ARY[11:0]` carry the numerator/denominator of source aspect ratio when bit `[12]` is 0; the scaler computes target dimensions. [C] ([[`Template_MiSTer/sys/emu_ports.vh:18-21`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L18-L21)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L18-L21))
- If `VIDEO_ARX[12]` or `VIDEO_ARY[12]` is set, the low 12 bits hold an absolute scaled pixel size in HDMI output space. [C] ([[`Template_MiSTer/sys/emu_ports.vh:18-21`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L18-L21)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L18-L21))
- `HDMI_WIDTH`/`HDMI_HEIGHT` are 12-bit framework inputs to the core giving the current HDMI mode resolution; cores using `video_freak` forward them to derive integer-scale targets. [C] ([[`Template_MiSTer/sys/emu_ports.vh:34-35`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L34-L35)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L34-L35))
- A core that does not use `video_freak` typically drives ARX/ARY directly from a status bit (e.g. 4:3 vs full-screen in `Template.sv`). [V] ([[`Template_MiSTer/Template.sv:52-55`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L52-L55)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L52-L55))

HDMI controls and analog routing
- `HDMI_FREEZE=1` causes the HDMI output to display the last frame (ascal stops writing the framebuffer) while the analog output goes to black RGB with synthesized HS/VS so a CRT does not drop sync. [C] ([[`Template_MiSTer/sys/video_mixer.sv:48-50`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/video_mixer.sv#L48-L50)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/video_mixer.sv#L48-L50))
- `HDMI_BLACKOUT=1` requests ascal to emit black until resolution lock, used during status switches. [C] ([[`Template_MiSTer/sys/sys_top.v:789`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L789)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L789))
- `HDMI_BOB_DEINT=1` selects bob deinterlace mode in ascal for interlaced input. [C] ([[`Template_MiSTer/sys/sys_top.v:747`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L747)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L747))
- `VGA_SCALER=1` forces the analog VGA output to the ascal-scaled HDMI image (1080p over VGA via clock select). [C] ([[`Template_MiSTer/sys/sys_top.v:1346`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1346)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1346), [`1689`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1689))
- `VGA_DISABLE=1` tri-states the analog RGB and drives sync inactive. [C] ([[`Template_MiSTer/sys/sys_top.v:1521-1525`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1521-L1525)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1521-L1525))

Default tie-offs
- A bare-minimum core MUST drive `VGA_SL=0`, `VGA_F1=0`, `VGA_SCALER=0`, `VGA_DISABLE=0`, `HDMI_FREEZE=0`, `HDMI_BLACKOUT=0`, `HDMI_BOB_DEINT=0`. [V] ([[`Template_MiSTer/Template.sv:33-39`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L33-L39)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L33-L39))

## 3. Ports / signals reference

### The `emu` video boundary

```verilog
// https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L11-L38
output        CLK_VIDEO,
output        CE_PIXEL,
output [12:0] VIDEO_ARX,
output [12:0] VIDEO_ARY,
output  [7:0] VGA_R,
output  [7:0] VGA_G,
output  [7:0] VGA_B,
output        VGA_HS,
output        VGA_VS,
output        VGA_DE,    // = ~(VBlank | HBlank)
output        VGA_F1,
output [1:0]  VGA_SL,
output        VGA_SCALER, // Force VGA scaler
output        VGA_DISABLE, // analog out is off
input  [11:0] HDMI_WIDTH,
input  [11:0] HDMI_HEIGHT,
output        HDMI_FREEZE,
output        HDMI_BLACKOUT,
output        HDMI_BOB_DEINT,
```

When `MISTER_FB` is defined the boundary also exposes `FB_EN`, `FB_FORMAT[4:0]`, `FB_WIDTH/HEIGHT[11:0]`, `FB_BASE[31:0]`, `FB_STRIDE[13:0]`, `FB_VBL`, `FB_LL`, `FB_FORCE_BLANK` for DDR3-framebuffer-source HDMI. [C] ([[`Template_MiSTer/sys/emu_ports.vh:40-67`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L40-L67)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L40-L67))

| Signal | Dir | Width | Clock | Active | Meaning | Driven by | Drives |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `CLK_VIDEO` | out | 1 | self | n/a | Base video clock (usually `clk_sys`); must be > 40 MHz | core PLL | all sys video stages |
| `CE_PIXEL` | out | 1 | `CLK_VIDEO` | high | 1-cycle pixel-valid pulse | core | `video_mixer`, `scanlines`, OSD, ascal `i_ce` |
| `VIDEO_ARX` | out | 13 | `CLK_VIDEO` | n/a | [11:0] = ratio numerator or scaled width; [12] = mode flag (0=ratio, 1=scaled size) | core / `video_freak` | sys_top scaler config |
| `VIDEO_ARY` | out | 13 | `CLK_VIDEO` | n/a | [11:0] = ratio denominator or scaled height; [12] = mode flag | core / `video_freak` | sys_top scaler config |
| `VGA_R/G/B` | out | 8 each | `CLK_VIDEO` (gate by `CE_PIXEL`) | n/a | RGB888 active pixel | core | `scanlines`, ascal `i_r/g/b` |
| `VGA_HS` | out | 1 | `CLK_VIDEO` | positive | H-sync pulse | core | `s_fix`, ascal `i_hs` |
| `VGA_VS` | out | 1 | `CLK_VIDEO` | positive | V-sync pulse | core | `s_fix`, ascal `i_vs` |
| `VGA_DE` | out | 1 | `CLK_VIDEO` | high | Active pixel = `~(HBlank \| VBlank)` | core | ascal `i_de`, video_freak `VGA_DE_IN` |
| `VGA_F1` | out | 1 | `CLK_VIDEO` | high during one field | Interlace field flag | core | ascal `i_fl`, sys_top |
| `VGA_SL` | out | 2 | `CLK_VIDEO` | n/a | Analog scanlines weight 0..3 | core (`status`) | `scanlines.scanlines` |
| `VGA_SCALER` | out | 1 | static | high | Force analog VGA from ascal output | core (`status`) | sys_top clock select |
| `VGA_DISABLE` | out | 1 | static | high | Tri-state analog VGA | core | sys_top output mux |
| `HDMI_WIDTH` | in | 12 | sys clock | n/a | Current HDMI active width | sys_top | `video_freak` |
| `HDMI_HEIGHT` | in | 12 | sys clock | n/a | Current HDMI active height | sys_top | `video_freak` |
| `HDMI_FREEZE` | out | 1 | `CLK_VIDEO` | high | Freeze HDMI (last frame) / blank analog | core | `video_mixer`/`video_freezer`, ascal `freeze` |
| `HDMI_BLACKOUT` | out | 1 | `CLK_VIDEO` | high | Force HDMI black through resolution change | core | ascal `swblack` |
| `HDMI_BOB_DEINT` | out | 1 | `CLK_VIDEO` | high | Select bob deinterlace mode | core | ascal `bob_deint` |
| `FB_EN` (MISTER_FB) | out | 1 | `CLK_VIDEO` | high | Enable framebuffer-source HDMI | core | ascal `o_fb_ena` |
| `FB_FORMAT` (MISTER_FB) | out | 5 | `CLK_VIDEO` | n/a | `[2:0]` bpp (011=8 100=16 101=24 110=32), `[3]` 16-bit subformat, `[4]` BGR | core | ascal `o_fb_format` |
| `FB_WIDTH/HEIGHT` (MISTER_FB) | out | 12 | `CLK_VIDEO` | n/a | Framebuffer image size | core | ascal `o_fb_hsize/vsize` |
| `FB_BASE` (MISTER_FB) | out | 32 | `CLK_VIDEO` | n/a | DDR3 base address of the framebuffer | core | ascal `o_fb_base` |
| `FB_STRIDE` (MISTER_FB) | out | 14 | `CLK_VIDEO` | n/a | Bytes per line (0 → rounded to 256) | core | ascal `o_fb_stride` |
| `FB_VBL` (MISTER_FB) | in | 1 | mixed | high | ascal's `o_vbl`; signals end of HDMI frame | sys_top | core sync |
| `FB_LL` (MISTER_FB) | in | 1 | mixed | high | Low-latency mode flag selected by user | sys_top | core sync |
| `FB_FORCE_BLANK` (MISTER_FB) | out | 1 | `CLK_VIDEO` | high | Force ascal output black | core | sys_top blank gate |

## 4. Sequencing & timing

### 4.1 CE_PIXEL gating

```
CLK_VIDEO  |‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
CE_PIXEL   ___/‾\_______/‾\_______/‾\_______/‾\___
                ^ 1-cycle pulse, exactly one per output pixel
VGA_R/G/B  ===X N+0 X=========X N+1 X=========X N+2
VGA_HS     ___________________________/‾‾‾‾‾‾‾‾\___
VGA_VS     __________________________________________
VGA_DE     ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_________
              core advances signal only at CE_PIXEL=1
```

Cycle narration:
1. Core asserts `CE_PIXEL` for one `CLK_VIDEO` cycle per visible pixel.
2. `VGA_R/G/B` are valid on that cycle and held until the next `CE_PIXEL`.
3. `VGA_DE` falls at the start of HBlank or VBlank; `VGA_HS`/`VGA_VS` are positive pulses inside the blanking window.
4. Downstream framework stages (e.g. `video_mixer.sv:206`, ascal `i_ce`) re-register only on `CE_PIXEL=1`; skipping the gate causes the scaler to capture stale or transitional pixel values.

### 4.2 Freeze handoff (HDMI vs analog)

```
HDMI_FREEZE     ____________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\____
              core asserts; both sinks react

HDMI (ascal)    XXXX live framesXXXX X last frame held X X live X
   ascal.freeze = HDMI_FREEZE → stops Avalon writes; reads continue
                                  (last full frame keeps showing)

Analog (mixer)  XXXX live RGB XXXX X RGB = 0  X X live X
   video_mixer R/G/B = 0 while frz=1
   video_freezer synthesizes HS/VS so CRT keeps locked
```

Behavior:
- HDMI: ascal stops writing the framebuffer but continues reading the last completed frame; viewer sees a frozen image. (archive/.../sys/sys_top.v:746 @ f35083f3b40d)
- Analog: RGB forced to black to avoid stale buffer artifacts, but `video_freezer` keeps emitting valid HS/VS so a CRT does not drop lock. (archive/.../sys/video_mixer.sv:97-99 @ f35083f3b40d)

### 4.3 ascal framebuffer mode handoff (MISTER_FB)

```
clk_vid (core)              clk_hdmi (sys)
   |                              |
core writes RGB pixels           ascal reads o_fb_base address (DDR3)
core sets FB_EN=1, FB_FORMAT,    ascal honors o_fb_ena (== FB_EN)
        FB_BASE, FB_STRIDE,        and uses *_fb_* timing to scan out
        FB_WIDTH, FB_HEIGHT        the framebuffer instead of the i_*
   |                              |
FB_VBL (in) <----- ascal pulses at o_vbl ------ ascal o_vbl
FB_LL  (in) <----- "low latency mode" ---------- ascal lowlat select
FB_FORCE_BLANK (out from core) — sys_top blanks ascal output
```

In framebuffer mode the core does not feed `i_r/g/b/hs/vs/de/ce` to ascal — instead it writes pixels into DDR3 at `FB_BASE` and ascal reads from there per `FB_FORMAT`/`FB_STRIDE`. The `VGA_*` boundary outputs are still expected (for analog VGA) but can be tied off if `VGA_DISABLE=1`. (archive/.../sys/sys_top.v:802-820 @ f35083f3b40d)

## 5. Minimal working pattern

### 5.1 Bare-minimum direct VGA tie-off (Template.sv)

```verilog
// https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L33-L39
assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;
```

```verilog
// https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L52-L55
wire [1:0] ar = status[122:121];
assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;
```

```verilog
// https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L149-L157
assign CLK_VIDEO = clk_sys;
assign CE_PIXEL = ce_pix;
assign VGA_DE = ~(HBlank | VBlank);
assign VGA_HS = HSync;
assign VGA_VS = VSync;
assign VGA_G  = (!col || col == 2) ? video : 8'd0;
assign VGA_R  = (!col || col == 1) ? video : 8'd0;
assign VGA_B  = (!col || col == 3) ? video : 8'd0;
```

Notes:
- `VIDEO_ARX/ARY` use the aspect-ratio form (bit [12] = 0). The two `status` bits select among source aspect (4/3), full-screen (0/0 → letterboxed), and two MRA-supplied custom ratios.
- `VGA_DE` is the exact framework-recommended expression. `VGA_HS/VS` are forwarded with positive polarity straight from the core.
- This Template skips `video_mixer` and `video_freak`; the analog side gets no scandoubler/hq2x/gamma; the HDMI side still works because ascal lives above the boundary in sys_top.

For wrapped instantiations using `arcade_video` or `video_freak`, see [40a-video-pipeline.md §5](40a-video-pipeline.md).

## 6. Common variations across cores

Direct cross-core comparison is `[deferred — reference cores not fetched]`. Framework-implied variations at the emu boundary are:

- Direct `VGA_*` tie-off vs `video_mixer` wrapper: a core that does its own scandoubling, or only outputs HDMI-resolution video, drives `VGA_*` directly; `Template.sv` is the canonical example. Most retro cores instantiate `video_mixer` for the framework's analog features. [V] ([[`Template_MiSTer/Template.sv:131-157`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L131-L157)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L131-L157))
- `VIDEO_ARX/ARY` aspect-ratio form vs scaled-size form: when `video_freak` drives them, bit [12] is set during integer-scale modes; without `video_freak`, cores typically use aspect-ratio form (both [12] = 0). [V] ([[`Template_MiSTer/sys/video_freak.sv:313-320`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/video_freak.sv#L313-L320)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/video_freak.sv#L313-L320), Template.sv:54-55 @ f35083f3b40d)
- `HDMI_WIDTH`/`HDMI_HEIGHT` consumed only when `video_freak` is in use (or for explicit integer scaling logic). A core that uses ascal's default aspect-mode does not need them. [I] ([[`Template_MiSTer/sys/video_freak.sv:124-136`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/video_freak.sv#L124-L136)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/video_freak.sv#L124-L136))
- `MISTER_FB` framebuffer-source HDMI vs direct `i_r/g/b/hs/vs/de/ce` to ascal: GBA, NeoGeo, and the system menu use `MISTER_FB`; most discrete cores feed ascal directly. [V] ([[`Template_MiSTer/sys/emu_ports.vh:40-67`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L40-L67)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L40-L67), sys/sys_top.v:802-820 @ f35083f3b40d)
- `VGA_SCALER` toggle: cores expose this in CONF_STR for users that want the 1080p ascal output over the analog VGA jack. Most cores leave it at the default driven by sys_top's `vga_force_scaler`. [V] ([[`Template_MiSTer/sys/sys_top.v:1689`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1689)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1689))
- `MISTER_DEBUG_NOHDMI` build flag: removes the entire HDMI/ascal/shadowmask stack; analog VGA is the only output. Used for low-resource debug builds. [V] ([[`Template_MiSTer/sys/sys_top.v:711`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L711)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L711), [`1141`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1141), [`1316-1326`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1316-L1326), [`1472`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1472))
- Direct-video (`cfg[10]`): runtime config that bypasses ascal on HDMI — the emu's video clock drives `HDMI_TX_CLK`. Cores see this as the framework forwarding `HDMI_WIDTH=0`/`HDMI_HEIGHT=0`. [V] ([[`Template_MiSTer/sys/sys_top.v:296`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L296)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L296), [`1316-1320`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1316-L1320), [`1778-1779`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L1778-L1779))
- Per-core variations across NES/SNES/PSX/ao486 etc. — `[deferred — reference cores not fetched]`.

## 7. Anti-patterns

### A.1 Updating VGA_R/G/B without CE_PIXEL gating

- **Symptom:** Random pixel scrambling on HDMI; analog VGA looks correct on a CRT but the scaler shows torn columns or shifted pixels.
- **Cause:** Driving `VGA_R/G/B` from a free-running counter or combinational logic so the value changes mid-pixel. ascal samples on `i_ce` (= `CE_PIXEL`); if RGB changes between consecutive `CE_PIXEL` pulses, the scaler captures whichever sample lands on the input register edge.
- **Fix:** Register `VGA_R/G/B` and only update inside `if (CE_PIXEL) begin ... end` (or use `video_mixer`, which retimes for you).
- **Citation:** [[`Template_MiSTer/sys/video_mixer.sv:206-216`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/video_mixer.sv#L206-L216)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/video_mixer.sv#L206-L216) (mixer itself only updates outputs `if(CE_PIXEL)`).

### A.2 VGA_DE not equal to `~(HBlank | VBlank)`

- **Symptom:** ascal detects wrong image size; cropping looks off; `video_freak` aspect collapses to 0; HDMI shows partial image or stretched borders.
- **Cause:** Either DE is asserted during blanking, or DE lags HS/VS by an unexpected delay so the scaler's auto-window detection (driven by `iauto=1`, `ascal.vhd:193`) measures the wrong active rectangle.
- **Fix:** Drive `assign VGA_DE = ~(HBlank | VBlank);` directly, or use `video_cleaner` to retime DE alongside RGB so it matches the visible window exactly. Make HBlank and VBlank positive-polarity and aligned to the same pixel cadence as the RGB stream.
- **Citation:** [[`Template_MiSTer/sys/emu_ports.vh:28`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L28)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L28); [[`Template_MiSTer/Template.sv:152`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L152)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv#L152).

### A.3 VIDEO_ARX/ARY scaled-size mode without setting bit [12]

- **Symptom:** Image is sized to a 12-bit "aspect ratio" of e.g. 800/600 → ascal computes a huge stretched image; OSD says aspect 4:3 (because the framework decodes [11:0] as a numerator/denominator pair).
- **Cause:** A core computed an absolute scaled pixel size (e.g. for integer scaling) and wrote it to `VIDEO_ARX[11:0]` without setting `VIDEO_ARX[12]` (or `VIDEO_ARY[12]`) to flag scaled-size mode.
- **Fix:** When delivering an absolute scaled size, set bit [12]: `VIDEO_ARX = {1'b1, width};` `VIDEO_ARY = {1'b1, height};`. `video_freak` does this automatically when `SCALE != 0`. For aspect ratio, both bit [12] stay 0 and [11:0] is the integer ratio.
- **Citation:** [[`Template_MiSTer/sys/emu_ports.vh:18-21`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L18-L21)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh#L18-L21); [[`Template_MiSTer/sys/video_freak.sv:313-320`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/video_freak.sv#L313-L320)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/video_freak.sv#L313-L320).

### A.4 Treating sys_top as a simple mux from emu to HDMI

- **Symptom:** Changing `VGA_HS`/`VGA_VS` polarity "fixes" analog but jitters HDMI OSD; or expectation that the analog 6-bit truncation also applies to HDMI.
- **Cause:** Treating sys_top as if it routes the core's analog `VGA_*` to both DACs. ascal is a deep reformatter: it crosses into `clk_hdmi`, scales, deinterlaces, polyphase-filters, writes DDR3, reads back, and never re-uses the analog DAC's 6-bit value. Analog and HDMI are independent sinks fed by the same `VGA_*` source.
- **Fix:** Drive `VGA_HS`/`VGA_VS` positive-polarity pulses always (the contract). Do not depend on sys_top's analog-side inversions when reasoning about HDMI. Test both outputs independently.
- **Citation:** [[`Template_MiSTer/sys/sys_top.v:714-820`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L714-L820)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v#L714-L820) (ascal instance), 1521-1525 (analog DAC inversion) @ f35083f3b40d.

### A.5 ce_pix held multiple cycles wide

- **Symptom:** Each source pixel rendered 2-3 times; framebuffer mode shows duplicated columns; ascal sees twice the source width.
- **Cause:** `CE_PIXEL` is a clock-enable PULSE (1 cycle per valid pixel), not a clock divider. Downstream samplers (scandoubler line 72, gamma_corr lines 37-38) are rising-edge-sensitive on `ce_pix`.
- **Fix:** Generate `CE_PIXEL` as a 1-cycle pulse per pixel. If you have a wider pulse, AND it with the inverse of a prior copy: `assign CE_PIXEL = ce_pix & ~ce_pix_d`.
- **Citation:** [[`Template_MiSTer/sys/scandoubler.v:71-72`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/scandoubler.v#L71-L72)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/scandoubler.v#L71-L72); [[`Template_MiSTer/sys/gamma_corr.sv:37-38`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/gamma_corr.sv#L37-L38)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/gamma_corr.sv#L37-L38).

## 8. Verification

- **Boundary check (simulation):** Drive `CLK_VIDEO` and a 1-cycle `CE_PIXEL` pulse train at the core's pixel rate. Assert that `VGA_R/G/B/HS/VS/DE` only change in cycles where `CE_PIXEL=1` or stay constant. Assert `VGA_DE === ~(HBlank|VBlank)`.
- **Aspect-ratio check:** Toggle the OSD `Aspect ratio` option and confirm `VIDEO_ARX`/`VIDEO_ARY` change accordingly. If `video_freak` is in use, verify both [12] bits are 1 when `SCALE != 0` and both [12] bits are 0 in "Original" mode.
- **HDMI smoke test:** Enable `HDMI_FREEZE` via OSD pause; the HDMI image must stop on the last frame while the analog output goes black. Release; both must resume in sync.
- **Direct-video probe:** Set `direct_video=1` in MiSTer config and verify the HDMI image is the core's raw video without scaling — this isolates ascal from any core-side timing bug.
- **MiSTer.ini knobs that surface bugs:** `vsync_adjust`, `hdmi_limited`, `vrr_mode`, `vscale_mode`, `direct_video`, `forced_scandoubler`, `dvi_mode`. Toggle each to confirm the core's `VIDEO_ARX/ARY` and `VGA_DE` remain consistent.

## 9. Provenance footer

- [[`Template_MiSTer/sys/emu_ports.vh`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/emu_ports.vh) — used for §2 (contract), §3 (port block), §4 (FB handoff)
- [[`Template_MiSTer/Template.sv`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/Template.sv) — used for §2 (tie-off rule), §5.1 (verbatim tie-off pattern), §6
- [[`Template_MiSTer/sys/video_mixer.sv`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/video_mixer.sv)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/video_mixer.sv) — used for §2 (positive-polarity rule, CE_PIXEL gating, freeze behavior), §4.2, §7 (A.1, A.4)
- [[`Template_MiSTer/sys/video_freak.sv`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/video_freak.sv)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/video_freak.sv) — used for §6 (ARX/ARY scaled-size form), §7 (A.3)
- [[`Template_MiSTer/sys/scandoubler.v`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/scandoubler.v)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/scandoubler.v) — used for §7 (A.5)
- [[`Template_MiSTer/sys/gamma_corr.sv`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/gamma_corr.sv)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/gamma_corr.sv) — used for §7 (A.5)
- [[`Template_MiSTer/sys/scanlines.v`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/scanlines.v)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/scanlines.v) — used for §2 (VGA_SL semantics)
- [[`Template_MiSTer/sys/sys_top.v`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/sys_top.v) — used for §2 (HDMI/analog routing rules), §4.2 (freeze), §4.3 (FB), §6 (NOHDMI, direct_video, VGA_SCALER), §7 (A.4)
- [[`Template_MiSTer/sys/ascal.vhd`](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/ascal.vhd)](https://github.com/MiSTer-devel/Template_MiSTer/blob/f35083f3b40d24853abea4cd3f77caccbd71d5de/sys/ascal.vhd) — used for §7 (A.2 reference to `iauto`)
- [[`MkDocs_MiSTer/docs/developer/emu.md`](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/emu.md)](https://github.com/MiSTer-devel/MkDocs_MiSTer/blob/9033bd292fdcc98f30dfe47eed7d61371181454a/docs/developer/emu.md) — used for §2 (40 MHz clock requirement)
