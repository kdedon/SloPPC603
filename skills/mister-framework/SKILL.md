---
name: mister-framework
description: Load for any work touching a MiSTer core's emu top level, conf_str/OSD status bits, hps_io (ioctl download/upload, S-slot mounts, sd_* block interface), SDRAM/DDRAM/BRAM memory paths and arbitration, clocks/resets/PLLs, video/audio boundary, Quartus/SDC build, simulation, or porting/bring-up of a core on the Template_MiSTer framework.
---

# MiSTer Framework — Operating Manual

Distilled from `references/source/` (22 docs, pinned [`Template_MiSTer`](https://github.com/MiSTer-devel/Template_MiSTer/tree/f35083f3b40d24853abea4cd3f77caccbd71d5de), [`Main_MiSTer`](https://github.com/MiSTer-devel/Main_MiSTer/tree/136737b4bed4d5ba58216efdcede0094ae8e8041)). Each rule is tagged `[C]` framework contract (violation breaks the core), `[V]` convention, `[I]` inference. Every entry: rule → why → failure mode → `see <file>#section`. Read the cited file before changing a contract-adjacent line; never edit `sys/`.

Path prefix for all `see` links: `references/source/`.

## 0. Mental model (read first)

- Quartus top entity is `sys_top` (framework). It instantiates exactly one `emu` (yours). `sys/` is frozen and byte-identical across cores; all customization lives in `rtl/`, `<core>.sv`, `files.qip`, `<core>.qsf`, `<core>.sdc`. `see 53-core-patterns.md#2` `see 50-build-quartus.md#2`
- `emu` = four mandatory blocks: (1) `` `include "sys/emu_ports.vh" `` port list, (2) tie-offs for every unused output, (3) `localparam CONF_STR` + one `hps_io`, (4) `pll pll(...)` deriving `clk_sys` from `CLK_50M`. Plus `wire reset = RESET | status[0] | buttons[1];`. `see 53-core-patterns.md#3.1`
- Three memory tiers: **SDRAM** (core-private, FPGA-only pins, you write the controller), **DDRAM** (HPS DDR3 over Avalon f2sdram, high latency, shared with Linux), **BRAM** (M10K, 553 blocks, inferred from RTL idioms). `see 30-sdram.md#1` `see 31-ddram.md#1` `see 33-bram.md#1`
- The HPS talks to the core only through `hps_io` over SPI (`HPS_BUS`). File delivery = `ioctl_*` (one-shot stream) or `sd_*` mounts (live block device) or direct-DDRAM `shmem_map`. `see 20-hps-io-overview.md#1` `see 32-rom-save-state-flows.md#2`

## 1. emu top level: ports, lifecycle, tie-offs

- **Module must be `emu`, port list must begin with `` `include "sys/emu_ports.vh" ``.** [C] sys_top wires by name. Fails: elaboration error / missing connections. `see 10-emu-top-level.md#2`
- **`HPS_BUS[45:0]` passes through untouched to `hps_io.HPS_BUS`.** [C] hps_io drives only `[37]=ioctl_wait`, `[36]=clk_sys`, `[32]=io_wide`, `[15:0]=io_dout`. Re-driving any bit collides. Fails: HPS reports core-magic mismatch, OSD never opens. `see 10-emu-top-level.md#3.4` `see 20-hps-io-overview.md#7`
- **Tie-off idle values differ by port class.** [C] Chip pins (`SDRAM_*`, `ADC_BUS`, `SD_SCK/MOSI/CS`) → `'Z`. Internal Avalon bridge (`DDRAM_CLK/BURSTCNT/ADDR/DIN/BE/RD/WE`) → `'0` (tri-state on an internal bus is illegal; wedges f2sdram). Open-drain `USER_OUT` → `'1` (releases line; you cannot read `USER_IN[n]` unless `USER_OUT[n]=1`). Everything else → `0` (`BUTTONS`, `LED_*`, UART, `VGA_SL/F1/SCALER/DISABLE`, `HDMI_*`, `AUDIO_*`). `see 53-core-patterns.md#3.2` `see 10-emu-top-level.md#5`
- **`RESET` is asynchronous, active-high, from `sysmem_lite.reset_out`.** [C] Synchronize into `clk_sys` before using it as a level/edge. Fails: intermittent, board-specific reset glitches. `see 12-clocks-resets-plls.md#2` `see 12-clocks-resets-plls.md#7`
- **`LED_POWER/LED_DISK[1]=0` = let system OR its own status; `=1` = core sole control.** [C] `see 10-emu-top-level.md#2`
- **`OSD_STATUS` (input) is high while the framework menu is open.** [C] Gate gameplay input / pause / autosave on it. Do NOT instantiate `osd.v` in the core. `see 23-osd-menu-and-input.md#2` `see 23-osd-menu-and-input.md#7`
- **Under `MISTER_DUAL_SDRAM`, drive every `SDRAM2_*` output to `'Z` the moment `SDRAM2_EN==0`.** [C] Board may be absent. `see 30-sdram.md#2`
- **Core-type magic.** [C] HPS won't talk until it reads `{24'h5CA623, 8'hA4}` (`0xA8` if dual SDRAM). Not core-editable, but explains "OSD never opens" when `sys/` is mismatched. `see 20-hps-io-overview.md#2`
- Bring-up isolation knobs in `MiSTer.ini`: `direct_video=1` (bypass scaler), `vga_scaler=1`, `forced_scandoubler=1`, `vsync_adjust=2` (exposes VS drift). `see 10-emu-top-level.md#8`

## 2. Clocks, resets, PLLs, clk_sys

- **PLL module AND instance are both named `pll`, in `rtl/` not `sys/`, `.rst(0)`.** [C] `sys_top.sdc` matches `*|pll|pll_inst|*`; renaming leaves all core clocks unconstrained (STA "unconstrained paths", nothing runs). `.rst(0)` keeps `clk_sys` free-running across warm reset; bouncing it costs full relock. `see 12-clocks-resets-plls.md#2` `see 10-emu-top-level.md#7`
- **`clk_sys` is core-owned and exported to the framework only as `HPS_BUS[36]`.** [C] `hps_io` and sys_top counters sample it. Every `hps_io` output is registered on `clk_sys`; sample them on `clk_sys`. `see 12-clocks-resets-plls.md#2` `see 21-hps-io-ioctl-and-download.md#2`
- **`clk_sys` frequency is unconstrained by the framework; pick one that divides cleanly to every CE (CPU, pixel, audio).** [V] It is the universal CE-domain master. `see 12-clocks-resets-plls.md#2`
- **Warm reset (`gp_out[31:30]` handshake) bounces the HDMI PLL but NOT the user PLL or audio PLL.** [C] Video blanks during reset; `clk_sys`/`clk_audio` keep running. `see 12-clocks-resets-plls.md#4`
- **`CLK_AUDIO` = fixed 24.576 MHz input; audio emission path only.** [C] Never clock core logic from it; CDC properly. `see 12-clocks-resets-plls.md#7`
- **`DDRAM_CLK` and `SDRAM_CLK` are core outputs.** [C] Framework supplies no phase-shifted SDRAM clock; that's your PLL. `see 12-clocks-resets-plls.md#2` `see 30-sdram.md#2`
- **`Template.sdc` ships only `derive_pll_clocks` + `derive_clock_uncertainty`.** [C] Any async crossing you add (`clk_sys`↔`clk_audio`↔`clk_vid`↔`SDRAM_CLK`) needs `set_false_path` / `set_clock_groups -asynchronous` in `<core>.sdc`. `TIMEQUEST_MULTICORNER_ANALYSIS OFF` — single corner only. `see 12-clocks-resets-plls.md#8` `see 50-build-quartus.md#2`
- Expose user `pll.locked` to `LED_USER` during bring-up; framework `led_locked` is the HDMI adjuster, not yours. `see 12-clocks-resets-plls.md#8`

## 3. CONF_STR, status bits, OSD

- **`CONF_STR` is a `localparam` string; directives end in `;`; first line is title (`Title;;`).** [C] Read by SPI cmd `0x14`, byte-per-strobe. `see 11-conf-str.md#2`
- **`status[127:0]` is written whole by cmd `0x1E` (8×16-bit); core only reads it.** [C] Each `O[bit]`/`O[hi:lo]` owns bits; **overlaps silently overwrite**; keep the bit-map comment current. `see 11-conf-str.md#2` `see 11-conf-str.md#7`
- **`status[0]` is Soft Reset (`T[0]`/`R[0]`) — you must OR it into your reset.** [C] Fails: OSD Reset does nothing. `see 11-conf-str.md#7`
- **`T[n]` pulses `status[n]` one cycle; `R[n]` same + closes OSD.** [C] Treat as one-shot. `see 11-conf-str.md#2`
- **Bracket form `O[hi:lo]` reaches all 128 bits; legacy digit form `O{0-9A-V}` only 0..31 (uppercase) / 32..63 (lowercase).** [C] `see 11-conf-str.md#2`
- **Visibility prefixes: `H{i}`/`D{i}` hide/disable when `status_menumask[i]==1`; `h{i}`/`d{i}` when `==0`. Index 0..15 only (menumask is 16 bits). Prefix order: `[HDhd]{i}` then `P{page}` then directive** (`d5P1O[...]`, never `P1d5...`). [C] Compiles clean, silently wrong. `see 11-conf-str.md#2` `see 11-conf-str.md#7`
- **Bump `v,<n>` (0..99) on ANY `O/T/R` bit-layout change.** [C] HPS replays saved status into the new layout otherwise; only existing users see it. `see 11-conf-str.md#7`
- **Non-OSD directives (`J`, `jn`, `jp`, `V`, `I`, `DEFMRA`) go at the bottom.** [C] `see 11-conf-str.md#2`
- **`F[S]<i>,<EXT>[,<text>][,<hexaddr>]`** → `ioctl_index[5:0]=i`, `[15:6]`=extension-list index; `S` variant also mounts a `.sav` on S0; `<hexaddr>` in `[0x20000000,0x40000000)` selects direct-DDRAM load (no `ioctl_wr`). **`S<slot>,<EXT>`** → mount slot. `see 11-conf-str.md#3` `see 32-rom-save-state-flows.md#2.1`
- **`status_set` is rising-edge sampled; `status_in` latched at that edge; HPS polls cmd `0x29` (tens of ms).** [C] Holding it high = one update ever. `see 20-hps-io-overview.md#4.b` `see 20-hps-io-overview.md#7`
- **`buttons[0]`=OSD button, `buttons[1]`=user/reset button (`cfg[1:0]`); `forced_scandoubler=cfg[4]`; `direct_video=cfg[10]`.** [C] `see 20-hps-io-overview.md#2`
- **`RTC[64]` / `TIMESTAMP[32]` toggle only when the whole word has landed; latch `[63:0]`/`[31:0]` on the toggle.** [C] Mid-transfer values are partial. `see 20-hps-io-overview.md#7`
- **Input encodings.** [C] `ps2_key[10]` toggles per event (edge-detect; `[9]`=pressed, `[8]`=E0 ext, `[7:0]`=scancode). `ps2_mouse[24]` toggles. `spinner_N[8]` toggles even for zero delta. `joystick_N[3:0]={right,left,down,up}`, `[4..]` per `J` line (SNES order A=4 B=5 X=6 Y=7 L=8 R=9 SEL=10 START=11). Analog `[15:8]=Y`,`[7:0]=X` are **signed** -127..127. `paddle_N` unsigned 0..255. `see 23-osd-menu-and-input.md#2`
- `gamma_bus`: leave unconnected unless you instantiate `video_mixer/arcade_video` with `GAMMA=1` (which drives the `[21]` presence ack). `EXT_BUS`: leave unconnected unless you implement a second command channel (`[32]` = "I drive `[15:0]`"). `see 23-osd-menu-and-input.md#2` `see 40a-video-pipeline.md#2`

## 4. hps_io: ioctl download/upload

Signals are all registered on `clk_sys`. HPS opcodes: `FIO_FILE_INDEX 0x55` → `FIO_FILE_INFO 0x56` → `FIO_FILE_TX 0x53` (byte `0xFF`=download, `0xAA`=upload, `0`=end) → `FIO_FILE_TX_DAT 0x54`×N → `FIO_FILE_TX 0`. `see 21-hps-io-ioctl-and-download.md#4.3`

- **`ioctl_download` / `ioctl_upload` are mutually exclusive levels framing a transfer.** [C] Edge-detect BOTH edges: rising → assert load-reset, falling (+1 cycle) → release. Direct-DDRAM loads produce the level with **zero `ioctl_wr` pulses**; data is only guaranteed present at the falling edge. `see 21-hps-io-ioctl-and-download.md#7` `see 32-rom-save-state-flows.md#7`
- **`ioctl_wr` is exactly one `clk_sys` cycle per word; `ioctl_dout`/`ioctl_addr` valid that cycle.** [C] Never use as level enable. `see 21-hps-io-ioctl-and-download.md#2`
- **`ioctl_addr[26:0]` resets to 0 at TX start, steps by 1 (`WIDE=0`, 8-bit) or 2 (`WIDE=1`, 16-bit), never wraps/segments; first download word lands at 0 (`skip_add`), each later word pre-increments.** [C] On the end command it increments ONE MORE TIME while dropping `ioctl_download` → post-edge value is word COUNT, not last address. Latch on `ioctl_wr` instead. `see 21-hps-io-ioctl-and-download.md#4.1` `see 21-hps-io-ioctl-and-download.md#7`
- **Optional start-address bytes in `FIO_FILE_TX` land in `ioctl_addr` at the rising edge** (HPS passes total byte count on the direct-DDRAM path) — sample once on the rising edge to learn ROM size. [C] `see 32-rom-save-state-flows.md#2.1`
- **`ioctl_wait=1` stalls the HPS strobe (`HPS_BUS[37]` → sys_top gate).** [C] Assert whenever the write target (SDRAM refresh/contention, decompressor) cannot take the next word. Fails: dropped bytes, CRC mismatch vs HPS `file_crc`. Tie `0` only if you accept one word per `clk_sys` unconditionally. `see 21-hps-io-ioctl-and-download.md#2` `see 32-rom-save-state-flows.md#7`
- **`ioctl_index` / `ioctl_file_ext` are stable before `ioctl_download` rises.** [C] `[5:0]` F-slot / boot index, `[15:6]` extension sub-index. `see 21-hps-io-ioctl-and-download.md#2`
- **Reserved indices.** [C]/[V] `0` = `boot.rom` autoload; `{6'd1,6'd0}=0x40` = `boot1.rom`; `254` = MRA DIP word; `255` = cheat blob (re-sent on every toggle and zeroed at every ROM open — a custom slot at 255 gets clobbered). `see 21-hps-io-ioctl-and-download.md#7` `see 32-rom-save-state-flows.md#2.4` `see 52-mra-and-arcade.md#3`
- **Upload is core-initiated.** [C] Pulse `ioctl_upload_req` (≥1 cycle, rising-edge latched) with `ioctl_upload_index`; HPS polls opcode `0x3C` **only while OSD is open**, then runs the upload. During upload there is no `skip_add`: first DAT pre-increments to 1 before sampling `ioctl_din`, so present the word for the *current* `ioctl_addr` continuously; `ioctl_rd` pulses per word. `see 21-hps-io-ioctl-and-download.md#4.2` `see 32-rom-save-state-flows.md#4.4`
- C64/C128 EasyFlash save-back uses polled `UIO_CHK_UPLOAD (0x3C)` on the regular UIO stream with `ioctl_index=99`, not `ioctl_upload_req`. [O] `see 32-rom-save-state-flows.md#6.2`
- **ROM-load ordering on HPS:** index/info → TX(0xFF) → data → (`process_ss` savestate init) → (`.sav` mount on S0 if `opensave`) → TX(0). The S0 mount pulse arrives INSIDE the `ioctl_download` window; consume save-RAM only after the falling edge. `see 32-rom-save-state-flows.md#4.1`

## 5. hps_io: mounts and SD block interface

`hps_io #(.VDNUM(n), .BLKSZ(b), .WIDE(w))`: `VDNUM` 1..10 slots; block = `128<<BLKSZ` bytes (default 512); `WIDE=1` → 16-bit `sd_buff_dout/din`, `AW=12` else 13. `see 22-hps-io-mount-and-sd.md#2`

- **`img_mounted[n]` is a one-cycle pulse; `img_size[63:0]` and `img_readonly` are valid ONLY that cycle → latch per slot.** [C] HPS sends `UIO_SET_SDINFO 0x1d` (size) then `UIO_SET_SDSTAT 0x1c` (slot mask + RO bit 7). Eject = pulse with `img_size==0`. `see 22-hps-io-mount-and-sd.md#4.1` `see 22-hps-io-mount-and-sd.md#7`
- **`sd_rd[n]`/`sd_wr[n]` are LEVELS: assert and hold with `sd_lba[n]` valid until `sd_ack[n]` rises, then deassert.** [C] HPS polls `UIO_GET_SDSTAT 0x16` every loop; leaving the level high re-issues the same LBA forever. Canonical: 3-stage ack shift register, clear request on `~ack[2]&ack[1]`, advance LBA on `ack[2]&~ack[1]` (`sd_card.sv`). `see 22-hps-io-mount-and-sd.md#2` `see 22-hps-io-mount-and-sd.md#7`
- **`sd_ack[n]` rises on `UIO_SECTOR_RD 0x17`/`WR 0x18` for slot n, falls when `io_enable` drops (transfer done).** [C] `see 22-hps-io-mount-and-sd.md#2`
- **`sd_lba` is a sector number (HPS computes `lba*blksz`), never a byte offset.** [C] `see 22-hps-io-mount-and-sd.md#7`
- **Read: `sd_buff_wr` pulses once per byte/word, `sd_buff_addr` auto-increments; `sd_buff_dout/addr` are shared across slots — only the acked slot consumes.** [C] `see 22-hps-io-mount-and-sd.md#4.2`
- **Write: the entire sector must already be readable via `sd_buff_din[n]` when `sd_wr` asserts; core re-drives `sd_buff_din` for whatever `sd_buff_addr` appears.** [C] `see 22-hps-io-mount-and-sd.md#4.3`
- **`(sd_blk_cnt[n]+1) * (1<<(BLKSZ+7)) <= 16384`.** [C] `see 22-hps-io-mount-and-sd.md#2`
- **Gate `sd_wr` on latched `~img_readonly`.** [C] HPS ACKs writes to RO files but never writes them. `see 22-hps-io-mount-and-sd.md#7`
- Multiple slots requesting simultaneously are round-robined (`sd_rrb`); no starvation. `see 22-hps-io-mount-and-sd.md#3`
- Save-RAM default flavor: `F` with `S` flag → `<root>/saves/<Core>/<rom>.sav` mounted on S0 (`O_RDWR|O_SYNC`). `see 32-rom-save-state-flows.md#2.2`
- Save-states: `SS<base>:<size>` in CONF_STR, 4 contiguous DDRAM slots at `base+i*size`, header `[31:0]`=change detector, `[63:32]`=size in 32-bit words. Write order MUST be payload → size (`+4`) → detector (`+0`) last; HPS polls detector each ~1 s and flushes `(size+2)*4` bytes. "Slot has data" = size word ≠ 0, NOT detector (HPS forces detector to `0xFFFFFFFF` at launch). `see 32-rom-save-state-flows.md#2.3` `see 32-rom-save-state-flows.md#7`

## 6. SDRAM — what the framework guarantees, and what it doesn't

**Scope warning (read this).** The reference is explicit: the framework provides NO SDRAM controller, NO command timing, NO arbitration scheme. `30-sdram.md` covers pins, pad-register constraints, chip geometry, refresh and the dual-SDRAM rules; per-core controller flavour (ports, bursts, CAS, slot scheduling, `clk_ram` phase) is marked `[deferred — reference cores not fetched]`. Anything below tagged `[I]` is inferred/common practice, not a citable framework contract. For this project's actual controller behavior read the core's own `rtl/sdram*.v` — that is the contract your clients must obey. `see 30-sdram.md#4` `see 30-sdram.md#6` `see 30-sdram.md#7`

### 6.1 Pins and pad registers [C]

- **Port set (11 signals):** `SDRAM_CLK, CKE, A[12:0], BA[1:0], DQ[15:0] (inout), DQML, DQMH, nCS, nRAS, nCAS, nWE`; `n*` active-low, `DQM*` active-low byte masks (0 = byte enabled). `see 30-sdram.md#2` `see 30-sdram.md#3.4`
- **HPS has no path to SDRAM.** Only the FPGA core touches it. ROMs reach SDRAM via `ioctl_*` → your controller's write port. Shared HPS↔FPGA memory is DDRAM. `see 30-sdram.md#7`
- **`sys.tcl` forces `FAST_OUTPUT_REGISTER ON` on all `SDRAM_*`, `FAST_INPUT_REGISTER ON` + `FAST_OUTPUT_ENABLE_REGISTER ON` on `SDRAM_DQ`, `ALLOW_SYNCH_CTRL_USAGE OFF`.** Consequences: (a) the last stage of every `SDRAM_*` output in your RTL must be a plain flip-flop feeding the pad with no combinational logic after it, else Quartus retimes that logic into the IOE and your internal timing assumptions break; (b) `SDRAM_DQ` output-enable must come from a single dedicated register; (c) the IOE stage adds one `SDRAM_CLK` cycle on both directions — count it in your CAS-return math. Fails: works for some access patterns, corrupts others; ghosting at burst boundaries; marginal timing. `see 30-sdram.md#2` `see 30-sdram.md#4` `see 53-core-patterns.md#7` (X.3)
- **Do not import a non-MiSTer `sdram.v`** (MiST, dev-board reference). Audit every pad output for registered last stage. `see 90-anti-patterns.md` (X.3)
- **Unused → whole bus `'Z`.** `see 30-sdram.md#5`
- **`SDRAM_CLK` is generated by the core PLL; phase-shift vs `clk_sys` is per-core convention, not framework.** [V] Board has no length-matched clock; you own the sampling window. `see 30-sdram.md#2`
- **Dual SDRAM:** `SDRAM2_*` has NO `DQML/DQMH/CKE` (word-aligned writes only, or RMW); gate everything on `SDRAM2_EN`; enabling requires sourcing `sys/sys_dual_sdram.tcl` (sets `MISTER_DUAL_SDRAM=1`, steals analog VGA/audio/SDIO pins; core magic becomes `0xA8`). `see 30-sdram.md#2` `see 30-sdram.md#7`

### 6.2 Chip and timing facts [C]/[I]

- Current board chip `AS4C32M16SB-7TCN`: 32M×16 = 64 MB (128 MB dual). Geometry BA=2, row=13 (8192), col=10 (1024). Older boards 32 MB single / 64 MB dual, pin compatible. `see 30-sdram.md#2` `see 30-sdram.md#6`
- `-7` grade → tCK ≥ 7 ns (~142 MHz CL3 max); typical MiSTer clocks 96–100 MHz. Inferred cycle counts at CL3/-7: tRCD≈3, tRP≈3, tRC≈9, tWR≈2, CL 2 or 3. [I] `see 30-sdram.md#4`
- **Refresh: 8192 AUTO_REFRESH per 64 ms → tREFI ≈ 7.81 µs; all banks precharged first.** Fails: runs for seconds then bit-rot, worse when hot/busy. Build a counter slightly faster than tREFI. `see 30-sdram.md#7` (A.5)
- Init: CKE=0 ≥100 µs, CKE=1 + NOPs ≥100 µs, PRECHARGE ALL, 2× AUTO_REFRESH, LOAD MODE (CL, burst, seq/interleave). `see 30-sdram.md#4`
- Single read (CL2): `ACT(row) → NOP → READ(col) → NOP → NOP → DQ valid` at the chip; add the IOE input-register cycle before your fabric sees it. `see 30-sdram.md#4`
- Verify with `MemTest_MiSTer` before blaming a controller; SignalTap the pads; symptoms: garbled tiles = wrong CL/phase, ROM checksum drift after idle = missing refresh, boot drift = clock phase outside window. `see 30-sdram.md#8`

### 6.3 Multi-client sharing — practice, not framework contract [I]

Nothing in `sys/` arbitrates SDRAM. The reference only states that real controllers have "multi-cycle CAS latency, refresh cycles, and arbitration between multiple ports" and that behavioural sims must model ≥2-cycle return latency plus busy/ready. Everything else here is the shape MiSTer cores conventionally use; confirm against the controller you actually have.

- **One controller, one command issuer.** Clients (CPU, video fetch, ioctl loader, expansion) present `{req/strobe, addr, wdata, we, byte-mask}`; only the controller sequences `nRAS/nCAS/nWE` and refresh. A client never touches pads. `see 51-simulation.md#7` (A.3) `see 30-sdram.md#5`
- **Typical structure: fixed time-slot or priority arbitration on `clk_ram`**, refresh slotted in as a synthetic client when no bank is open or when its counter overflows. Whichever the controller uses, the client-visible contract is: hold request + address + data stable until the controller acknowledges (ack pulse, `busy` low, or the slot advancing); do not change address mid-request.
- **Read-data return:** data arrives a fixed number of `clk_ram` cycles after the controller's READ (CL + IOE + any internal pipeline), usually accompanied by a per-client `data_ready`/ack pulse or written into a client-owned output register that holds until the next read for that client. Clients must latch on that strobe/register — never assume "N cycles after my request" unless the controller documents it, because refresh and other clients can delay issue. Same principle as DDRAM `DOUT_READY`. `see 31-ddram.md#7` (M.7 analogue)
- **`ioctl` writes into SDRAM go through `ioctl_wait`:** assert `ioctl_wait` from the moment you accept an `ioctl_wr` word until the controller has actually taken it (write ack), else the next HPS strobe overwrites your latched word. `see 32-rom-save-state-flows.md#5.1` `see 32-rom-save-state-flows.md#7` (A.1)
- **Byte writes:** primary bus uses `DQML/DQMH`; a 16-bit controller doing 8-bit client writes drives the mask from client byte-enable. Secondary bus cannot (no DQM). `see 30-sdram.md#3.4`
- **Simulation:** never stub SDRAM as zero-latency; model CL + busy/ready or simulate the real `rtl/sdram.v`. `see 51-simulation.md#7` (A.3)

## 7. DDRAM (HPS DDR3 via f2sdram)

- **Core drives `DDRAM_CLK`; all `DDRAM_*` sampled on it.** [C] `see 31-ddram.md#2`
- **`DDRAM_ADDR[28:0]` is a 64-bit WORD address** (byte = `{ADDR,3'b0}`); `DDRAM_BE[7:0]` active-high per byte; `DDRAM_DIN/DOUT` 64-bit. [C] Sub-word write: word addr = `A>>3`, duplicate data into both halves, `BE = 8'h0F`/`8'hF0`. `see 31-ddram.md#2` `see 31-ddram.md#5`
- **`DDRAM_BUSY` = Avalon `waitrequest`. A command is accepted only on a cycle where `RD`/`WE` is high AND `BUSY` is low. Hold `RD/WE/ADDR/BURSTCNT/DIN/BE` stable until that cycle; clear `RD/WE` only inside `if(!DDRAM_BUSY)`.** [C] Fails: dropped/duplicated transactions, wrong-address reads. Reference: `ddr_svc.sv`. `see 31-ddram.md#4` `see 31-ddram.md#7`
- **`DDRAM_DOUT` is valid ONLY when `DDRAM_DOUT_READY=1`; latency is variable (Linux contends). Burst N → N strobes.** [C] `see 31-ddram.md#4` `see 31-ddram.md#7`
- **`DDRAM_BURSTCNT` 1..255; chunk longer transfers.** [C] `see 31-ddram.md#7`
- **`RD`/`WE` mutually exclusive, conventionally one-cycle pulses per burst when `BUSY=0`.** [V] `see 31-ddram.md#2`
- **Never bypass `f2sdram_safe_terminator`; feed it a synchronous reset on the port clock.** [C] A mid-burst teardown wedges the bridge for the *next* core. `see 31-ddram.md#4` `see 31-ddram.md#7`
- **High latency — bulk/prefetchable only** (framebuffers, CD images, save states). Keep CPU/audio-critical state in BRAM/SDRAM. [C] `see 31-ddram.md#7`
- Address map conventions: `0x20000000–0x40000000` = FPGA-visible window used for direct loads and `SS`; ascal framebuffers `RAMBASE 0x20000000` (8 MB/buffer ×3, 2 MB with `MISTER_SMALL_VBUF`); arcade `screen_rotate` at `0x24000000`; N64 RDRAM `0x30000000`. Avoid collisions. `see 31-ddram.md#2` `see 40a-video-pipeline.md#3.12` `see 32-rom-save-state-flows.md#2.3`

## 8. BRAM (M10K) budget practices

- **553 M10K blocks (10 240 bits each) on `5CSEBA6U23I7`; widths 1/2/4/5/8/10/16/20/32/40.** [C]/[I] Audit Fitter → Resource Usage → "M10K blocks" and RAM Summary. `see 33-bram.md#2` `see 33-bram.md#8`
- **Inference requires a synchronous registered read (`always_ff @(posedge clk) q <= mem[a];`) and NO async reset on the output register.** Combinational read or `posedge rst` → silent MLAB/logic fallback (LUT blow-up, timing). `see 33-bram.md#7` (A.1, A.2)
- **Shapes:** single-port (one `always_ff`), SDP (write block + read block, may be two clocks — the line-buffer/gamma/OSD idiom), TDP only via explicit `altsyncram BIDIR_DUAL_PORT` (`sd_card.sv`), `outdata_aclr="NONE"`, `power_up_uninitialized="FALSE"`, RDW `NEW_DATA_NO_NBE_READ`; cross-port collisions undefined — partition addresses. `see 33-bram.md#3.1` `see 33-bram.md#5.4`
- **Two-clock SDP: annotate `(* ramstyle = "no_rw_check" *)` and guarantee by construction that writer and reader never hit the same word in the same cycle.** [V] `see 33-bram.md#5.2`
- **Opt-outs:** `(* ramstyle = "logic" *)` for tiny arrays and shift registers >~6 deep (each would burn a full block); `(* romstyle = "MLAB" *)` for small ROMs. `see 33-bram.md#7` (A.3–A.5)
- **`$readmemh` paths resolve against project root / `SEARCH_PATH`; check the log for "Loaded file".** `see 33-bram.md#7` (A.6)
- `hps_io` `CONF_STR_BRAM=1` moves the string ROM into M10K (long CONF_STR); `=0` distributed logic. `see 11-conf-str.md#6`
- One-cycle read latency is inherent; plan pipelines around it. `see 33-bram.md#4`

## 9. Video boundary and pipeline

- **`CLK_VIDEO > 40 MHz` and `≥ 4× ce_pix` when using scandoubler/HQ2x/`arcade_video`.** [C] Otherwise `pixsz4` collapses → black bars, garbled HQ2x. `see 40-video.md#2` `see 40a-video-pipeline.md#7`
- **`CE_PIXEL` = exactly one `CLK_VIDEO` cycle per output pixel, derived from `CLK_VIDEO`; update `VGA_R/G/B/HS/VS/DE` only when it's high.** [C] Wide pulse → duplicated columns; ungated updates → scaler tearing. `see 40-video.md#4.1` `see 40-video.md#7`
- **`VGA_DE = ~(HBlank|VBlank)`; `VGA_HS/VS` positive-polarity pulses; RGB 8-bit.** [C] ascal auto-windows on DE (`iauto`). `see 40-video.md#2` `see 40-video.md#7`
- **`VIDEO_ARX/ARY[12]=0` → `[11:0]` aspect numerator/denominator; `=1` → absolute scaled size.** [C] `video_freak` sets it when `SCALE!=0`. `see 40-video.md#7`
- HDMI and analog are independent sinks: HDMI chain `s_fix → video_freezer → gamma → scandoubler/Hq2x → ascal (CDC to clk_hdmi, DDR3 FB) → shadowmask → osd → vga_out`; analog `s_fix → scanlines → osd → yc_out|vga_out → 6-bit DAC`. Don't "fix" HDMI by flipping analog polarity. `see 40a-video-pipeline.md#1` `see 40a-video-pipeline.md#2`
- `video_mixer #(LINE_LENGTH ≥ active width, HALF_DEPTH, GAMMA)`; `arcade_video #(WIDTH, DW∈{6,8,9,12,18,24}, GAMMA)` maps `fx` → `{hq2x, VGA_SL}`. `video_freak` after the mixer, fed pre-scandoubler DE. Advertise gamma in CONF_STR only with `GAMMA=1`. `see 40a-video-pipeline.md#3.1` `see 40a-video-pipeline.md#5` `see 40a-video-pipeline.md#7`
- `HDMI_FREEZE`: HDMI holds last frame, analog goes black with synthesized sync. `HDMI_BLACKOUT`, `HDMI_BOB_DEINT`, `VGA_SCALER`, `VGA_DISABLE` (single-SDRAM only), `VGA_SL[1:0]` 0/25/50/75%. `see 40-video.md#2`
- `MISTER_FB` / `MISTER_FB_PALETTE`: core writes pixels to DDR3 at `FB_BASE`, ascal reads per `FB_FORMAT/STRIDE/WIDTH/HEIGHT`; `FB_VBL` in. `see 40-video.md#4.3`
- OSD adds 3 `clk_video` cycles of latency on de/hs/vs (framework-side). `see 23-osd-menu-and-input.md#2`

## 10. Audio

- **`AUDIO_L/R` 16-bit; `AUDIO_S=1` signed / `0` offset-binary; `AUDIO_MIX` 0/25/50/100%.** [C] Wrong `AUDIO_S` → `{~is_signed ^ msb}` flips sign → thump + DC. `see 41-audio.md#2` `see 41-audio.md#7`
- **`AUDIO_L/R` must hold stable ≥2 `clk_audio` cycles** (3-cycle agreement synchronizer); drive from a sample-rate register, never combinationally per `clk_audio`. Fails: total silence. `see 41-audio.md#4.3`
- Chain after emu: sign-map → IIR LPF (HPS-loaded coeffs, default `LPF20000.txt`) → DC blocker (not bypassable) → boost/ALSA sum/mix/att → I²S (HDMI) + S/PDIF + sigma-delta DAC (single-SDRAM analog jack). Don't bypass the filter; ship `*_afilter.cfg`. `see 41-audio.md#4.1` `see 41-audio.md#7`
- Feed real stereo; `AUDIO_MIX` is a no-op if `L==R`. `MISTER_DISABLE_ALSA` only when intentionally dropping Linux audio. `see 41-audio.md#7`
- `mt32pi.sv` is core-side (uses `USER_IN/OUT`); framework does not wire it. `see 41-audio.md#3.9`

## 11. Build: Quartus, qsf/qip/sdc

- **Quartus 17.0.x (17.0.2), device `5CSEBA6U23I7` via `source sys/sys.tcl`; `TOP_LEVEL_ENTITY sys_top`.** [C] Don't change device in the IDE. `see 50-build-quartus.md#2`
- **All user RTL in `files.qip` only. Never "Add Files" in the IDE** — it writes to `.qsf` and Quartus then "spits" the whole config back into it. `see 50-build-quartus.md#7` (A.1, A.2)
- **`.qsf` sources in order: `sys/sys.tcl`, `sys/sys_analog.tcl` (or `sys/sys_dual_sdram.tcl`, mutually exclusive), `files.qip`; includes `sys/sys.qip`.** [C] `see 50-build-quartus.md#5`
- **PLL selection is automatic (`sys.qip:1` regex on `$quartus(version)` → `pll_q17.qip` → `rtl/pll.qip`). Do not list `rtl/pll.qip` in `files.qip`; do not edit `pll_q*.qip`.** [C] Q13 builds use the framework `sys/pll.13.qip`, so no per-core frequency there. `see 50-build-quartus.md#5` `see 50-build-quartus.md#7` (A.4)
- **Constraints:** `<core>.sdc` (via `files.qip`) + `sys/sys_top.sdc` (via `sys.qip`) merge; add your own false paths/clock groups in `<core>.sdc`. `see 50-build-quartus.md#2`
- **`sys/build_id.tcl` pre-flow writes `build_id.v` (`` `BUILD_DATE "YYMMDD" ``, rewritten only on date change) + `jtag.cdf`.** Delete `build_id.v`/run `clean.bat` before a release compile. `see 50-build-quartus.md#7` (A.5)
- **Feature macros** via `VERILOG_MACRO "<X>=1"` in `.qsf`: `MISTER_FB`, `MISTER_FB_PALETTE`, `MISTER_DUAL_SDRAM`, `MISTER_DEBUG_NOHDMI` (dev only, never release), `MISTER_DOWNSCALE_NN`, `MISTER_DISABLE_ADAPTIVE`, `MISTER_SMALL_VBUF`, `MISTER_DISABLE_YC`, `MISTER_DISABLE_ALSA`. `see 53-core-patterns.md#3.4`
- Output `output_files/<rev>.rbf` (`GENERATE_RBF_FILE ON`); release as `releases/<core>_YYYYMMDD.rbf`. `SMART_RECOMPILE ON`; `db/`, `incremental_db/` hold incremental state. `see 50-build-quartus.md#3`
- `<core>.srf` suppresses known-safe warnings; don't suppress new categories — fix RTL. `see 50-build-quartus.md#8`
- Style: tabs; `_n` suffix for active-low; `(* multstyle = "logic" *)` to save DSPs. [V] `see 53-core-patterns.md#2`

## 12. Simulation

- Framework ships no testbench and no simulation contract; JimmyStones' Verilator template is the de-facto external reference. `see 51-simulation.md#2`
- TB instantiates `emu` directly; stub `hps_io` (drive `status`, `ioctl_*`, `ps2_key`), replace PLLs with behavioural clocks, drop `sys_top.v`, `sysmem.sv`, `f2sdram_safe_terminator.sv`, all VHDL (`ascal.vhd`, `pll_hdmi_adj.vhd`). Verilator can't do VHDL; ModelSim/Questa can. `see 51-simulation.md#3`
- Lifecycle: init → reset (hold ≥1 µs sim time; don't gate on stubbed `locked`) → ROM load via `ioctl_*` with `ioctl_download` high throughout → run → capture at `VGA_*`/`AUDIO_*` per `VS`/audio CE → teardown. `see 51-simulation.md#4`
- Never simulate SDRAM as zero-latency; model CL 2–3 + busy/ready or use the real `rtl/sdram.v`. `see 51-simulation.md#7` (A.3)

## 13. MRA / arcade (only if relevant)

- Each `<rom index=N>` = one ioctl stream (`ioctl_download` drops between them); parts concatenate in document order; `<patch>` applied before streaming; `md5` mismatch aborts (fallback second `index=0` block). `repeat=` is total byte count. `map=` needs `<interleave output=N>`. `zip="a.zip|b.zip"` fallback list. `see 52-mra-and-arcade.md#2` `see 52-mra-and-arcade.md#4`
- DIP word arrives on `ioctl_index=254`; NVRAM via `<nvram index size>`; keep DIP bits disjoint from CONF_STR `O[]` bits. `<rom address=0x...>` → `shmem_put` direct DDR load. `see 52-mra-and-arcade.md#7`

## 14. Anti-pattern checklist (from 90-anti-patterns.md)

Tick every line before declaring a change done. IDs match `90-anti-patterns.md`.

**Top-level / clocks**
- [ ] T.1 DDRAM unused → `'0`, never `'Z`
- [ ] T.2 PLL module+instance named `pll`, in `rtl/`
- [ ] T.3 `USER_OUT[n]=1` before reading `USER_IN[n]`
- [ ] T.4 `BUTTONS` assigned
- [ ] T.5 no status-bit overlap between directives
- [ ] T.6 `v,<n>` bumped after layout change
- [ ] T.7 `status[0]` in reset chain
- [ ] T.8 `H/h`, `D/d` polarity correct
- [ ] T.9 prefix order `[HDhd]{i}P{n}<dir>`
- [ ] T.10 menumask index ≤ 15
- [ ] T.11 `RESET` synchronized, treated as async
- [ ] T.12 user `pll.rst = 0`
- [ ] T.13 no core logic on `clk_audio`

**HPS bridge**
- [ ] H.1 `HPS_BUS` passed through, not driven
- [ ] H.2 `status_set` pulsed, not held
- [ ] H.3 `ioctl_wait` asserted when target busy
- [ ] H.4 `RTC[64]`/`TIMESTAMP[32]` toggle-latched
- [ ] H.5 `ioctl_wr` used as 1-cycle strobe
- [ ] H.6 `ioctl_addr` after `ioctl_download` falls = count, not last addr
- [ ] H.7 `ioctl_addr` doesn't wrap; demux on `ioctl_index`
- [ ] H.8 `ioctl_index==0` reserved for boot.rom
- [ ] H.9 both edges of `ioctl_download` handled (also for direct-DDRAM loads)
- [ ] H.10 `sd_rd/sd_wr` cleared on `sd_ack` rising edge
- [ ] H.11 `sd_wr` gated on `~img_readonly`
- [ ] H.12 `sd_lba` is sector, not byte
- [ ] H.13 `img_size/img_readonly` latched on `img_mounted`
- [ ] H.14 `ps2_key[10]` edge-detected
- [ ] H.15 inputs gated on `~OSD_STATUS`
- [ ] H.16 analog sticks treated as signed
- [ ] H.17 no `osd.v` in core

**Memory**
- [ ] M.1 SDRAM controller lives in the core (none in `sys/`)
- [ ] M.2 `SDRAM2_*` gated on `SDRAM2_EN`
- [ ] M.3 no `SDRAM2_DQML/DQMH/CKE`
- [ ] M.4 no HPS→SDRAM path assumed; ROMs via ioctl
- [ ] M.5 auto-refresh ≤ 7.81 µs
- [ ] M.6 `DDRAM_RD/WE` cleared only when `!BUSY`; cmd/data held
- [ ] M.7 `DDRAM_DOUT` consumed only on `DOUT_READY`
- [ ] M.8 `DDRAM_BE`/word address aligned for sub-64-bit writes
- [ ] M.9 `f2sdram_safe_terminator` not bypassed
- [ ] M.10 `DDRAM_BURSTCNT` ≤ 255
- [ ] M.11 DDRAM not used for latency-critical state
- [ ] M.12 savestate detector written last
- [ ] M.13 `ioctl_index==255` reserved for cheats
- [ ] M.14 `ioctl_upload_req` core-driven, pulsed
- [ ] M.15 savestate occupancy = size word ≠ 0
- [ ] M.16 BRAM reads registered
- [ ] M.17 no async reset on BRAM output
- [ ] M.18 long shift registers `ramstyle="logic"`
- [ ] M.19 tiny arrays `ramstyle="logic"`
- [ ] M.20 small ROMs `romstyle="MLAB"`
- [ ] M.21 `$readmemh` file found (log "Loaded file")
- [ ] M.22 M10K ≤ 553

**Video / audio**
- [ ] V.1 RGB updated only under `CE_PIXEL`
- [ ] V.2 `VGA_DE = ~(HBlank|VBlank)`
- [ ] V.3 `VIDEO_ARX/ARY[12]` set for scaled-size mode
- [ ] V.4 HS/VS positive polarity; HDMI and analog tested independently
- [ ] V.5 `CE_PIXEL` one cycle wide
- [ ] V.6 `CLK_VIDEO > 40 MHz`, ≥4× `ce_pix`
- [ ] V.7 `video_freak` fed pre-scandoubler DE
- [ ] V.8 `GAMMA=1` iff gamma advertised
- [ ] V.9 `AUDIO_S` matches sample format
- [ ] V.10 `AUDIO_L/R` stable ≥2 `clk_audio` cycles
- [ ] V.11 real stereo + `AUDIO_MIX` exposed
- [ ] V.12 framework audio filter not bypassed
- [ ] V.13 `MISTER_DISABLE_ALSA` only when intended

**Build / sim / MRA / cross-core**
- [ ] B.1 files added via `files.qip`, not IDE
- [ ] B.2 every new RTL file listed in `files.qip`
- [ ] B.3 device not overridden
- [ ] B.4 `pll_q*.qip` untouched
- [ ] B.5 fresh `build_id.v` before release
- [ ] B.6 no `ascal.vhd` in TB
- [ ] B.7 TB reset not gated on stubbed PLL lock
- [ ] B.8 SDRAM model has latency
- [ ] B.9 TB excludes VHDL / unsupported SV under Verilator
- [ ] B.10–B.14 MRA part order, `repeat` bytes, DIP bits disjoint, zip fallback, `interleave` parent
- [ ] X.1 nothing edited in `sys/`
- [ ] X.2 project started from `Template_MiSTer`
- [ ] X.3 SDRAM controller is MiSTer-style (registered pad outputs)

## 15. Porting / bring-up gates (condensed from 91-porting-checklist.md)

Sequential; do not advance until the gate passes. Full item list: `see 91-porting-checklist.md`.

1. **Boundary:** `emu` + `emu_ports.vh`; `sys/` untouched; `HPS_BUS` passthrough; tie-offs per class (§1); `SDRAM2_*` gated. `see 91-porting-checklist.md#gate-1`
2. **Clocks/resets:** `pll pll(.rst(0))` in `rtl/`; `RESET` synced; `reset = RESET|status[0]|buttons[1]`; `CLK_VIDEO>40 MHz`; `CE_PIXEL` 1-cycle; `CLK_AUDIO` audio-only; `DDRAM_CLK` driven. `see 91-porting-checklist.md#gate-2`
3. **CONF_STR/hps_io:** localparam; title first; `status[0]` reset; no bit overlap; menumask ≤15; prefix order; `v,<n>`; non-OSD lines last; `V,v`+`BUILD_DATE`; one `hps_io`; `status_set` pulsed; toggles latched; `OSD_STATUS` consumed; signed analog. `see 91-porting-checklist.md#gate-3`
4. **Files/mounts:** `ioctl_download` both edges; `ioctl_wr` strobe; `ioctl_wait`; addr not wrapped; indices 0/255 reserved; index/ext sampled at rising edge; `ioctl_upload_req` pulsed; `sd_rd/wr` levels cleared on ack; `img_*` latched; LBA sectors; RO gating; burst ≤16384. `see 91-porting-checklist.md#gate-4`
5. **Memory:** SDRAM controller core-supplied, registered pads, refresh; no `SDRAM2_DQM/CKE`; DDRAM word addr, burst ≤255, BUSY/READY handshake, terminator intact, no latency-critical use; load-reset across download; savestate order & occupancy; `SS` range; BRAM registered read, no async reset, shape matches topology, `no_rw_check` on 2-clock SDP, init files found, ≤553 M10K, opt-outs applied. `see 91-porting-checklist.md#gate-5`
6. **Video:** positive HS/VS; `VGA_DE`; CE-gated RGB; 8-bit; `VGA_F1`; ARX/ARY mode bit; all HDMI/VGA control outputs driven; `LINE_LENGTH`; `arcade_video` clock rules; `GAMMA`; `video_freak` DE source. `see 91-porting-checklist.md#gate-6`
7. **Audio:** 16-bit; `AUDIO_S`; stable ≥2 cycles; `AUDIO_MIX` from OSD; real stereo; filter intact; ALSA macro intentional. `see 91-porting-checklist.md#gate-7`
8. **Build/power-on:** Quartus 17.0.x; device via `sys.tcl`; `sys_top` top; `files.qip`; qsf source order; qip untouched; `GENERATE_RBF_FILE`; `build_id` pre-flow; fresh build_id for release; TB without VHDL, reset ≥1 µs; on hardware: OSD opens, key toggle once per event, joystick bit order, analog rest ≈0, `.rbf` name. `see 91-porting-checklist.md#gate-8`

## 16. When to open the source doc

| Task | Read |
|---|---|
| New/renamed emu port, tie-off question | `10-emu-top-level.md` §3.3 table |
| HPS_BUS bit meaning | `10-emu-top-level.md` §3.4 |
| Any CONF_STR edit | `11-conf-str.md` §3 grammar table, §7 |
| Reset/PLL/SDC timing | `12-clocks-resets-plls.md` §2, §8 |
| SPI command numbers, status writeback | `20-hps-io-overview.md` §2, §4 |
| ROM load waveform, upload quirks | `21-hps-io-ioctl-and-download.md` §4 |
| Disk mount / sector handshake | `22-hps-io-mount-and-sd.md` §4 |
| Input encodings, EXT_BUS, gamma_bus | `23-osd-menu-and-input.md` §2, §3.4 |
| SDRAM pins/pads/refresh/dual | `30-sdram.md` §2, §4, §7 |
| DDRAM handshake, terminator | `31-ddram.md` §4, §7 |
| ROM/save/savestate/cheat ordering | `32-rom-save-state-flows.md` §2, §4 |
| BRAM inference, altsyncram | `33-bram.md` §3, §5, §7 |
| Video boundary / pipeline / ascal generics | `40-video.md`, `40a-video-pipeline.md` |
| Audio chain, filter, ALSA | `41-audio.md` §2, §4 |
| Quartus project files, macros | `50-build-quartus.md`, `53-core-patterns.md` §3 |
| Testbench scaffolding | `51-simulation.md` §3, §5 |
| MRA XML | `52-mra-and-arcade.md` §2, §3 |
| Upstream file:line proof for any claim | `02-source-map.md` |
| Term lookup | `01-glossary.md` |
