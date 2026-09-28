// Resettable 60x target, one tenure at a time, with phase-varied delays and
// bench-steered retries. Delays follow the delay target: BG follows BR except
// when phase%3==0, AACK 1-3 cycles after TS, DBG skips phase%4==1, the first
// TA waits 2-5 owned DBB cycles and later beats BEAT_GAP + phase%3.
// Policy inputs, sampled where noted:
//   retry_i  at AACK: assert ARTRY in the following cycle; the tenure ends
//            without a data tenure and the master reoffers it,
//   drtry_i  at a read TA: from the next cycle assert DRTRY, cancelling that
//            beat, for 1-3 cycles (phase%4==0 extends it); the replacement
//            TA comes in the last DRTRY cycle,
//   hold_i   withholds each new TA while high,
//   tea_i    at a would-be TA: assert TEA instead and end the tenure.
// Every accepted read beat is followed by one confirmation cycle without a
// new TA, so DRTRY never meets the next beat. The bench owns memory: it reads the state
// below by hierarchical reference, drives read data and captures writes.
module bus60x_retry_target_bfm #(
  parameter int BEAT_GAP = 1
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  int          phase_i,
  input  logic        retry_i,
  input  logic        drtry_i,
  input  logic        hold_i,
  input  logic        tea_i,
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
  output logic        artry_n_o,
  output logic        dbg_n_o,
  output logic        ta_n_o,
  output logic        drtry_n_o,
  output logic        tea_n_o
);
  // Each bench reads the subset of this state it needs.
  /* verilator lint_off UNUSEDSIGNAL */
  logic address_pending = 1'b0, transfer_pending = 1'b0, data_ok = 1'b0;
  logic retry_window = 1'b0, retry_q = 1'b0;
  logic confirm_q = 1'b0, replace_q = 1'b0;
  logic transfer_write = 1'b0, transfer_instruction = 1'b0, transfer_burst = 1'b0;
  logic [31:0] transfer_addr = 32'b0;
  int address_delay = 0, data_delay = 0, transfer_size = 0, beat = 0;
  int replace_wait = 0;
  int tenures = 0, retries = 0, drtries = 0, teas = 0, held = 0;
  /* verilator lint_on UNUSEDSIGNAL */
  logic owned, offer;

  assign owned = dbb_oe_i && !dbb_n_i;
  // A TA or TEA may start only outside a confirmation or replacement cycle.
  assign offer = transfer_pending && data_ok && owned && data_delay == 0 &&
                 !confirm_q && !replace_q && !hold_i;
  assign bg_n_o = !(rst_ni && !br_n_i && phase_i % 3 != 0);
  assign aack_n_o = !(address_pending && address_delay == 0);
  assign artry_n_o = !(retry_window && retry_q);
  assign dbg_n_o = !(transfer_pending && data_ok && phase_i % 4 != 1);
  assign ta_n_o = !((offer && !tea_i) || (replace_q && replace_wait == 0));
  assign tea_n_o = !(offer && tea_i);
  assign drtry_n_o = !replace_q;

  task automatic next_beat;
    if (transfer_burst && beat < 3) begin
      beat <= beat + 1;
      data_delay <= BEAT_GAP + phase_i % 3;
    end else begin
      transfer_pending <= 1'b0;
      data_ok <= 1'b0;
    end
  endtask

  always @(posedge clk_i) begin
    if (!rst_ni) begin
      address_pending <= 1'b0;
      transfer_pending <= 1'b0;
      data_ok <= 1'b0;
      retry_window <= 1'b0;
      retry_q <= 1'b0;
      confirm_q <= 1'b0;
      replace_q <= 1'b0;
      replace_wait <= 0;
      address_delay <= 0;
      data_delay <= 0;
      beat <= 0;
    end else begin
      if (address_delay > 0) address_delay <= address_delay - 1;
      if (data_delay > 0 && owned) data_delay <= data_delay - 1;
      if (transfer_pending && data_ok && owned && data_delay == 0 && hold_i &&
          !confirm_q && !replace_q)
        held <= held + 1;
      if (!aack_n_o) begin
        address_pending <= 1'b0;
        retry_window <= 1'b1;
        retry_q <= retry_i;
      end
      if (retry_window) begin
        retry_window <= 1'b0;
        retry_q <= 1'b0;
        if (retry_q) begin
          transfer_pending <= 1'b0;
          retries <= retries + 1;
        end else begin
          data_ok <= 1'b1;
        end
      end
      if (ts_oe_i && !ts_n_i) begin
        address_pending <= 1'b1;
        transfer_pending <= 1'b1;
        data_ok <= 1'b0;
        address_delay <= 1 + phase_i % 3;
        data_delay <= 2 + phase_i % 4;
        transfer_addr <= a_i;
        transfer_write <= tt_i == 5'b00010;
        transfer_instruction <= tc_i == 2'd2;
        transfer_burst <= !tbst_n_i;
        transfer_size <= int'(tsiz_i);
        beat <= 0;
        tenures <= tenures + 1;
      end
      if (offer && tea_i) begin
        transfer_pending <= 1'b0;
        data_ok <= 1'b0;
        teas <= teas + 1;
      end else if (offer) begin
        if (transfer_write) begin
          transfer_pending <= 1'b0;
          data_ok <= 1'b0;
        end else if (drtry_i) begin
          replace_q <= 1'b1;
          replace_wait <= phase_i % 4 == 0 ? 1 + phase_i % 2 : 0;
        end else begin
          confirm_q <= 1'b1;
        end
      end
      // The replacement gets its own confirmation cycle.
      if (replace_q && replace_wait > 0) begin
        replace_wait <= replace_wait - 1;
      end else if (replace_q) begin
        replace_q <= 1'b0;
        confirm_q <= 1'b1;
        drtries <= drtries + 1;
      end
      if (confirm_q) begin
        confirm_q <= 1'b0;
        next_beat();
      end
    end
  end
endmodule
