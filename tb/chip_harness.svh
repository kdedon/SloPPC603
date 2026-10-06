// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// ppc603e on a 60x memory with a second bus master, connected pin to pin.
// Included in a bench body after `clk` is declared. The bench drives the
// input pin variables and the target policy (bfm_retry, bfm_hold, bfm_drtry,
// bfm_wait); RAM is memory.mem from BASE for MEM_BYTES. The address bus
// (TS, A, TT, GBL) and ARTRY are shared with the second master. The bench
// declares parameter PLL, the strap (negative: the PID7v default); the
// memory and the pin checks run on the chip's SYSCLK enable.
/* verilator lint_off ASCRANGE */
logic int_n = 1'b1, smi_n = 1'b1, mcp_n = 1'b1, ckstp_in_n = 1'b1;
logic hreset_n = 1'b0, sreset_n = 1'b1, qack_n = 1'b0, tben = 1'b1;
logic tlbisync_n = 1'b1, dbdis_n = 1'b1;
localparam logic [3:0] CHIP_PLL_CFG =
  (PLL < 0) ? ppc_pkg::pll_cfg_default(ppc_pkg::CPU_PID7V_603E) : 4'(PLL);
logic [0:3] pll_cfg = CHIP_PLL_CFG;
logic bus_ce;
logic bfm_retry = 1'b0, bfm_hold = 1'b0, bfm_drtry = 1'b0;
// Hides the shared TS from the chip's snooper (negative controls).
logic snoop_hide = 1'b0;
// Withholds BG from the chip, so no new tenure starts.
logic bus_block = 1'b0;
int bfm_wait = 0;

logic br_n, bg_n, abb_n, abb_oe, ts_n, ts_oe, ape_n, tbst_n, ci_n, wt_n;
logic gbl_n, addr_oe, aack_n, artry_n, artry_out_n, artry_oe, dbg_n, dbb_n;
logic dbb_oe, data_oe, dpe_n, ta_n, drtry_n, tea_n, ckstp_out_n, rsrv_n;
logic qreq_n, clk_out, clk_out_oe, tdo, tdo_oe;
logic [0:31] a, dh_out, dl_out;
logic [0:3] ap;
logic [0:4] tt;
logic [0:2] tsiz;
logic [0:1] tc, cse;
logic [0:7] dp;
logic [63:0] target_data;
logic bus_ts_n, bus_gbl_n;
logic [31:0] bus_a;
logic [3:0] bus_ap;
logic [4:0] bus_tt;

// +define+CHIP_ENABLE_FPU=1 attaches the FPU; +define+CHIP_VARIANT=n builds
// another part, CHIP_DS_PID its direct-store tag.
`ifndef CHIP_ENABLE_FPU
`define CHIP_ENABLE_FPU 0
`endif
`ifndef CHIP_VARIANT
`define CHIP_VARIANT 0
`endif
`ifndef CHIP_DS_PID
`define CHIP_DS_PID 0
`endif
// A direct-store controller beside the memory: its active-low grant and
// termination outputs join the memory's, and it may drive A, TT, XATS and DH.
logic buc_aack_n = 1'b1, buc_artry_n = 1'b1, buc_dbg_n = 1'b1;
logic buc_drtry_n = 1'b1;
logic buc_ta_n = 1'b1, buc_tea_n = 1'b1, buc_xats_n = 1'b1, buc_drive = 1'b0;
logic [31:0] buc_a = '0, buc_dh = '0;
logic [4:0] buc_tt = '0;
logic xats_n, xats_oe;
// Odd parity of the inbound data, wrong where the memory flips it.
logic [63:0] in_d;
logic [0:7] in_dp;
assign in_d = {buc_ta_n ? target_data[63:32] : buc_dh, target_data[31:0]};
always_comb
  for (int i = 0; i < 8; i++)
    in_dp[i] = ~^in_d[63-8*i -: 8] ^ memory.dp_flip[7-i];
ppc603e #(.CPU_VARIANT(ppc_pkg::cpu_variant_e'(`CHIP_VARIANT)), .PLL_CFG(CHIP_PLL_CFG),
  .ENABLE_FPU(1'(`CHIP_ENABLE_FPU)), .DS_PID(4'(`CHIP_DS_PID))) dut (
  /* verilator lint_off PINCONNECTEMPTY */
  .perf_o(), .bus_ce_o(bus_ce),
  /* verilator lint_on PINCONNECTEMPTY */
  .sysclk(clk), .pll_cfg_i(pll_cfg), .clk_out_o(clk_out), .clk_out_oe_o(clk_out_oe),
  .br_n_o(br_n), .bg_n_i(bg_n || bus_block), .abb_n_i(1'b1), .abb_n_o(abb_n), .abb_oe_o(abb_oe),
  .ts_n_i(bus_ts_n || snoop_hide), .ts_n_o(ts_n), .ts_oe_o(ts_oe),
  .a_i(buc_drive ? buc_a : bus_a), .a_o(a), .ap_i(bus_ap), .ap_o(ap), .ape_n_o(ape_n),
  .tt_i(buc_drive ? buc_tt : bus_tt), .tt_o(tt), .tsiz_o(tsiz), .tbst_n_i(1'b1), .tbst_n_o(tbst_n),
  .tc_o(tc), .ci_n_o(ci_n), .wt_n_o(wt_n), .gbl_n_i(bus_gbl_n), .gbl_n_o(gbl_n),
  .cse_o(cse), .addr_oe_o(addr_oe),
  .xats_n_i(xats_oe ? xats_n : buc_xats_n), .xats_n_o(xats_n), .xats_oe_o(xats_oe),
  .aack_n_i(aack_n && buc_aack_n), .artry_n_i(artry_n && buc_artry_n), .artry_n_o(artry_out_n), .artry_oe_o(artry_oe),
  .dbg_n_i(dbg_n && buc_dbg_n), .dbwo_n_i(memory.dbwo_n), .dbb_n_i(1'b1), .dbb_n_o(dbb_n), .dbb_oe_o(dbb_oe),
  .dh_i(in_d[63:32]), .dl_i(in_d[31:0]), .dh_o(dh_out), .dl_o(dl_out),
  .dp_i(in_dp), .dp_o(dp), .data_oe_o(data_oe), .dpe_n_o(dpe_n), .dbdis_n_i(dbdis_n),
  .ta_n_i(ta_n && buc_ta_n), .drtry_n_i(drtry_n && buc_drtry_n), .tea_n_i(tea_n && buc_tea_n),
  .int_n_i(int_n), .smi_n_i(smi_n), .mcp_n_i(mcp_n), .ckstp_in_n_i(ckstp_in_n),
  .ckstp_out_n_o(ckstp_out_n), .hreset_n_i(hreset_n), .sreset_n_i(sreset_n),
  .rsrv_n_o(rsrv_n), .qreq_n_o(qreq_n), .qack_n_i(qack_n), .tben_i(tben),
  .tlbisync_n_i(tlbisync_n),
  .tck_i(1'b0), .tms_i(1'b1), .tdi_i(1'b1), .trst_n_i(1'b0), .tdo_o(tdo), .tdo_oe_o(tdo_oe),
  .test_i(3'b111)
);

bus60x_coherent_bfm #(.BASE_ADDR(BASE), .MEM_BYTES(MEM_BYTES)) memory (.bus_ce_i(bus_ce),
  .clk_i(clk), .br_n_i(br_n), .ts_n_i(ts_n), .ts_oe_i(ts_oe), .a_i(a),
  .tt_i(tt), .tbst_n_i(tbst_n), .tsiz_i(tsiz), .tc_i(tc), .ci_n_i(ci_n), .wt_n_i(wt_n),
  .gbl_n_i(gbl_n), .dbb_n_i(dbb_n), .dbb_oe_i(dbb_oe), .d_i({dh_out, dl_out}),
  .d_oe_i(data_oe), .artry_n_i(artry_out_n), .artry_oe_i(artry_oe),
  .retry_i(bfm_retry), .hold_i(bfm_hold), .drtry_i(bfm_drtry), .wait_i(bfm_wait),
  .bg_n_o(bg_n), .aack_n_o(aack_n), .artry_n_o(artry_n), .dbg_n_o(dbg_n),
  .d_o(target_data), .ta_n_o(ta_n), .drtry_n_o(drtry_n), .tea_n_o(tea_n),
  .bus_ts_n_o(bus_ts_n), .bus_a_o(bus_a), .bus_tt_o(bus_tt), .bus_gbl_n_o(bus_gbl_n),
  .bus_ap_o(bus_ap)
);

// Attribute pins no check reads.
logic unused_harness;
assign unused_harness = ^{abb_n, clk_out, tdo, cse, memory.in_data};

// Pin-level write monitor: the address tenure's attributes, then each TA of
// our data tenure. One tenure is outstanding at a time.
logic [31:0] wr_addr_q = '0;
logic wr_pending_q = 1'b0;
logic wr_fire;
logic [31:0] wr_addr;
always @(posedge clk) begin
  if (bus_ce && ts_oe && !ts_n) begin
    wr_addr_q <= a;
    wr_pending_q <= (tt == 5'b00010) || (tt == 5'b10010);
  end
end
assign wr_fire = bus_ce && wr_pending_q && !ta_n && dbb_oe && data_oe;
assign wr_addr = wr_addr_q;

// Odd parity on every driven address and data byte.
logic [63:0] dout;
assign dout = {dh_out, dl_out};
always @(posedge clk) begin
  if (addr_oe)
    for (int i = 0; i < 4; i++)
      if (^{a[8*i +: 8], ap[i]} !== 1'b1) $fatal(1, "address parity byte %0d", i);
  if (data_oe)
    for (int i = 0; i < 8; i++)
      if (^{dout[63-8*i -: 8], dp[i]} !== 1'b1) $fatal(1, "data parity byte %0d", i);
end

// Outputs change only in the first cycle after a SYSCLK edge (the
// half-cycle releases fall inside it); hard reset and checkstop release
// them at any cycle.
logic pins_first_q = 1'b1, pins_live_q = 1'b0;
logic [139:0] pins_q = '0;
logic [139:0] pins_now;
assign pins_now = {xats_n, xats_oe, br_n, abb_n, abb_oe, ts_n, ts_oe, a, ap, ape_n, tt, tsiz,
                   tbst_n, tc, ci_n, wt_n, gbl_n, cse, addr_oe, artry_out_n,
                   artry_oe, dbb_n, dbb_oe, data_oe, data_oe ? dout : 64'b0,
                   data_oe ? dp : 8'b0, rsrv_n, qreq_n};
always @(posedge clk) begin
  if (pins_live_q && dut.core_rst_n && !pins_first_q && pins_now !== pins_q)
    $fatal(1, "pins changed between SYSCLK edges: %h -> %h", pins_q, pins_now);
  pins_first_q <= bus_ce;
  pins_live_q <= dut.core_rst_n;
  pins_q <= pins_now;
end

function automatic logic [31:0] mem_word(input logic [31:0] address);
  int o;
  o = int'(address - BASE);
  return {memory.mem[o], memory.mem[o+1], memory.mem[o+2], memory.mem[o+3]};
endfunction
task automatic put_word(input logic [31:0] address, input logic [31:0] value);
  int o;
  o = int'(address - BASE);
  {memory.mem[o], memory.mem[o+1], memory.mem[o+2], memory.mem[o+3]} = value;
endtask
// Every output the processor must release in hard reset or checkstop.
function automatic logic outputs_released();
  return br_n && !abb_oe && !ts_oe && !addr_oe && !dbb_oe && !data_oe &&
         !artry_oe && rsrv_n && !clk_out_oe && !tdo_oe;
endfunction
/* verilator lint_on ASCRANGE */
