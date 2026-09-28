// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
// ppc603e on a scripted 60x target, connected pin to pin. Included in a bench
// body after `clk` is declared. The bench drives the input pin variables and
// the target policy (bfm_retry, bfm_hold, bfm_drtry, bfm_wait); RAM is
// memory.mem from BASE for MEM_BYTES.
/* verilator lint_off ASCRANGE */
logic int_n = 1'b1, smi_n = 1'b1, mcp_n = 1'b1, ckstp_in_n = 1'b1;
logic hreset_n = 1'b0, sreset_n = 1'b1, qack_n = 1'b0, tben = 1'b1;
logic tlbisync_n = 1'b1, dbdis_n = 1'b1;
logic [0:3] pll_cfg = 4'b0000;
logic bfm_retry = 1'b0, bfm_hold = 1'b0, bfm_drtry = 1'b0;
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

ppc603e dut (
  .sysclk(clk), .pll_cfg_i(pll_cfg), .clk_out_o(clk_out), .clk_out_oe_o(clk_out_oe),
  .br_n_o(br_n), .bg_n_i(bg_n || bus_block), .abb_n_i(1'b1), .abb_n_o(abb_n), .abb_oe_o(abb_oe),
  .ts_n_i(1'b1), .ts_n_o(ts_n), .ts_oe_o(ts_oe),
  .a_i('0), .a_o(a), .ap_i('1), .ap_o(ap), .ape_n_o(ape_n),
  .tt_i('0), .tt_o(tt), .tsiz_o(tsiz), .tbst_n_i(1'b1), .tbst_n_o(tbst_n),
  .tc_o(tc), .ci_n_o(ci_n), .wt_n_o(wt_n), .gbl_n_i(1'b1), .gbl_n_o(gbl_n),
  .cse_o(cse), .addr_oe_o(addr_oe),
  .aack_n_i(aack_n), .artry_n_i(artry_n), .artry_n_o(artry_out_n), .artry_oe_o(artry_oe),
  .dbg_n_i(dbg_n), .dbwo_n_i(1'b1), .dbb_n_i(1'b1), .dbb_n_o(dbb_n), .dbb_oe_o(dbb_oe),
  .dh_i(target_data[63:32]), .dl_i(target_data[31:0]), .dh_o(dh_out), .dl_o(dl_out),
  .dp_i('1), .dp_o(dp), .data_oe_o(data_oe), .dpe_n_o(dpe_n), .dbdis_n_i(dbdis_n),
  .ta_n_i(ta_n), .drtry_n_i(drtry_n), .tea_n_i(tea_n),
  .int_n_i(int_n), .smi_n_i(smi_n), .mcp_n_i(mcp_n), .ckstp_in_n_i(ckstp_in_n),
  .ckstp_out_n_o(ckstp_out_n), .hreset_n_i(hreset_n), .sreset_n_i(sreset_n),
  .rsrv_n_o(rsrv_n), .qreq_n_o(qreq_n), .qack_n_i(qack_n), .tben_i(tben),
  .tlbisync_n_i(tlbisync_n),
  .tck_i(1'b0), .tms_i(1'b1), .tdi_i(1'b1), .trst_n_i(1'b0), .tdo_o(tdo), .tdo_oe_o(tdo_oe),
  .test_i(3'b111)
);

bus60x_scripted_target_bfm #(.BASE_ADDR(BASE), .MEM_BYTES(MEM_BYTES)) memory (
  .clk_i(clk), .br_n_i(br_n), .ts_n_i(ts_n), .ts_oe_i(ts_oe), .a_i(a),
  .tt_i(tt), .tbst_n_i(tbst_n), .tsiz_i(tsiz), .tc_i(tc),
  .dbb_n_i(dbb_n), .dbb_oe_i(dbb_oe), .d_i({dh_out, dl_out}), .d_oe_i(data_oe),
  .retry_i(bfm_retry), .hold_i(bfm_hold), .drtry_i(bfm_drtry), .wait_i(bfm_wait),
  .bg_n_o(bg_n), .aack_n_o(aack_n), .artry_n_o(artry_n), .dbg_n_o(dbg_n),
  .d_o(target_data), .ta_n_o(ta_n), .drtry_n_o(drtry_n), .tea_n_o(tea_n)
);

// Attribute pins no check reads.
logic unused_harness;
assign unused_harness = ^{abb_n, ci_n, wt_n, gbl_n, artry_out_n, clk_out, tdo, cse,
                          memory.in_data};

// Pin-level write monitor: the address tenure's attributes, then each TA of
// our data tenure. One tenure is outstanding at a time.
logic [31:0] wr_addr_q = '0;
logic wr_pending_q = 1'b0;
logic wr_fire;
logic [31:0] wr_addr;
always @(posedge clk) begin
  if (ts_oe && !ts_n) begin
    wr_addr_q <= a;
    wr_pending_q <= (tt == 5'b00010) || (tt == 5'b10010);
  end
end
assign wr_fire = wr_pending_q && !ta_n && dbb_oe && data_oe;
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
