// Free-running 60x target handshake with phase-varied delays, one tenure at
// a time. BG follows BR except when phase%3==0; AACK comes 1-3 cycles after
// TS; DBG waits for AACK and skips phase%4==1; each TA waits for a varied
// number of DBB cycles; a burst's later beats wait BEAT_GAP + phase%3. BG is
// combinational in BR, so the master must keep BG out of its own BR decision.
//
// The bench owns memory and checks: it reads the transfer state below by
// hierarchical reference, drives read data and captures write data on TA.
module bus60x_delay_target_bfm #(
  parameter int BEAT_GAP = 0
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  int          phase_i,
  input  logic        br_n_i,
  input  logic        ts_n_i,
  input  logic        ts_oe_i,
  input  logic [31:0] a_i,
  input  logic [4:0]  tt_i,
  input  logic [2:0]  tsiz_i,
  input  logic        tbst_n_i,
  input  logic [1:0]  tc_i,
  input  logic        dbb_n_i,
  input  logic        dbb_oe_i,
  output logic        bg_n_o,
  output logic        aack_n_o,
  output logic        dbg_n_o,
  output logic        ta_n_o
);
  // Each bench reads the subset of this state it needs.
  /* verilator lint_off UNUSEDSIGNAL */
  logic address_pending = 1'b0, transfer_pending = 1'b0;
  logic transfer_write = 1'b0, transfer_instruction = 1'b0, transfer_burst = 1'b0;
  logic [31:0] transfer_addr = 32'b0;
  int address_delay = 0, data_delay = 0, transfer_size = 0, beat = 0;
  /* verilator lint_on UNUSEDSIGNAL */

  assign bg_n_o = !(rst_ni && !br_n_i && phase_i % 3 != 0);
  assign aack_n_o = !(address_pending && address_delay == 0);
  assign dbg_n_o = !(transfer_pending && !address_pending && phase_i % 4 != 1);
  assign ta_n_o = !(transfer_pending && dbb_oe_i && !dbb_n_i && data_delay == 0);

  always @(posedge clk_i) begin
    if (!rst_ni) begin
      address_pending <= 1'b0;
      transfer_pending <= 1'b0;
      address_delay <= 0;
      data_delay <= 0;
      beat <= 0;
    end else begin
      if (address_delay > 0) address_delay <= address_delay - 1;
      if (data_delay > 0 && dbb_oe_i && !dbb_n_i) data_delay <= data_delay - 1;
      if (!aack_n_o) address_pending <= 1'b0;
      if (ts_oe_i && !ts_n_i) begin
        address_pending <= 1'b1;
        transfer_pending <= 1'b1;
        address_delay <= 1 + phase_i % 3;
        data_delay <= 2 + phase_i % 4;
        transfer_addr <= a_i;
        transfer_write <= tt_i == 5'b00010;
        transfer_instruction <= tc_i == 2'd2;
        transfer_burst <= !tbst_n_i;
        transfer_size <= int'(tsiz_i);
        beat <= 0;
      end
      if (!ta_n_o) begin
        if (transfer_burst && beat < 3) begin
          beat <= beat + 1;
          data_delay <= BEAT_GAP + phase_i % 3;
        end else begin
          transfer_pending <= 1'b0;
        end
      end
    end
  end
endmodule
