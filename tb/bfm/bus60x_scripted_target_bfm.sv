// Free-running 60x target serving one tenure at a time. The bench steers each
// tenure from the captured attributes through four policy inputs:
//   retry_i  sampled for the ARTRY window after AACK; a retried tenure ends
//            without a data tenure and the master reoffers it,
//   hold_i   withholds each TA while high,
//   drtry_i  cancels a read beat with DRTRY and replaces it on the same edge,
//   wait_i   extra cycles before BG, AACK, DBG and each TA.
// Writes land in mem on TA; reads return mem at each beat, so a replacement
// beat carries the current memory value.
module bus60x_scripted_target_bfm #(
  parameter int MEM_BYTES = 65536
) (
  input  logic        clk_i,
  input  logic        br_n_i,
  input  logic        ts_n_i,
  input  logic        ts_oe_i,
  input  logic [31:0] a_i,
  input  logic [4:0]  tt_i,
  input  logic        tbst_n_i,
  input  logic [2:0]  tsiz_i,
  input  logic [1:0]  tc_i,
  input  logic        dbb_n_i,
  input  logic        dbb_oe_i,
  input  logic [63:0] d_i,
  input  logic        d_oe_i,
  input  logic        retry_i,
  input  logic        hold_i,
  input  logic        drtry_i,
  input  int          wait_i,
  output logic        bg_n_o,
  output logic        aack_n_o,
  output logic        artry_n_o,
  output logic        dbg_n_o,
  output logic [63:0] d_o,
  output logic        ta_n_o,
  output logic        drtry_n_o,
  output logic        tea_n_o
);
  localparam logic [4:0] TT_WRITE = 5'b00010;
  logic [7:0] mem [0:MEM_BYTES-1];
  // Attributes of the tenure between TS capture and its end.
  logic [31:0] addr;
  /* verilator lint_off UNUSEDSIGNAL */
  logic [4:0] tt;
  int beat;
  /* verilator lint_on UNUSEDSIGNAL */
  logic burst, write, in_data;
  /* verilator lint_off UNUSEDSIGNAL */
  logic instruction;
  // Whether the previous address tenure was retried: a policy of
  // retry_i = want && !last_retried retries each transaction once.
  logic last_retried;
  /* verilator lint_on UNUSEDSIGNAL */
  logic [2:0] tsiz;
  // Each bench reads the subset it needs.
  /* verilator lint_off UNUSEDSIGNAL */
  int tenures = 0, retries = 0, drtries = 0, writes = 0, reads = 0, bursts = 0;
  /* verilator lint_on UNUSEDSIGNAL */

  initial begin
    bg_n_o = 1'b1;
    aack_n_o = 1'b1;
    artry_n_o = 1'b1;
    dbg_n_o = 1'b1;
    d_o = 64'b0;
    ta_n_o = 1'b1;
    drtry_n_o = 1'b1;
    tea_n_o = 1'b1;
    in_data = 1'b0;
    last_retried = 1'b0;
    addr = 32'b0;
    tt = 5'b0;
    burst = 1'b0;
    write = 1'b0;
    instruction = 1'b0;
    tsiz = 3'b0;
    beat = 0;
    for (int index = 0; index < MEM_BYTES; index++) mem[index] = 8'b0;
  end

  task automatic delay;
    int count;
    count = wait_i;
    repeat (count) @(posedge clk_i);
  endtask

  function automatic logic [63:0] doubleword(input logic [31:0] base);
    logic [63:0] value;
    value = 64'b0;
    for (int lane = 0; lane < 8; lane++)
      if (int'(base) + lane < MEM_BYTES)
        value[63-8*lane -: 8] = mem[int'(base) + lane];
    return value;
  endfunction

  function automatic logic [31:0] beat_address(input int index);
    if (!burst) return {addr[31:3], 3'b000};
    return {addr[31:5], 5'b0} + 32'(((int'(addr[4:3]) + index) % 4) * 8);
  endfunction

  task automatic address_tenure(output logic retried);
    while (br_n_i) @(posedge clk_i);
    delay();
    @(negedge clk_i);
    bg_n_o = 1'b0;
    do @(posedge clk_i); while (!(ts_oe_i && !ts_n_i));
    addr = a_i;
    tt = tt_i;
    burst = !tbst_n_i;
    write = tt_i == TT_WRITE;
    instruction = tc_i == 2'd2;
    tsiz = tsiz_i;
    tenures++;
    @(negedge clk_i);
    bg_n_o = 1'b1;
    delay();
    @(negedge clk_i);
    aack_n_o = 1'b0;
    @(posedge clk_i);
    @(negedge clk_i);
    aack_n_o = 1'b1;
    retried = retry_i;
    artry_n_o = !retried;
    @(posedge clk_i);
    @(negedge clk_i);
    artry_n_o = 1'b1;
    last_retried = retried;
    if (retried) retries++;
  endtask

  task automatic read_beat(input int index);
    delay();
    while (hold_i) @(posedge clk_i);
    @(negedge clk_i);
    d_o = doubleword(beat_address(index));
    ta_n_o = 1'b0;
    beat = index;
    @(posedge clk_i);
    @(negedge clk_i);
    if (drtry_i) begin
      // Cancel the candidate and identify its replacement on one edge.
      drtries++;
      drtry_n_o = 1'b0;
      d_o = doubleword(beat_address(index));
      @(posedge clk_i);
      @(negedge clk_i);
      drtry_n_o = 1'b1;
    end
    ta_n_o = 1'b1;
  endtask

  task automatic data_tenure;
    delay();
    @(negedge clk_i);
    dbg_n_o = 1'b0;
    do @(posedge clk_i); while (!(dbb_oe_i && !dbb_n_i));
    in_data = 1'b1;
    @(negedge clk_i);
    dbg_n_o = 1'b1;
    if (write) begin
      int size;
      delay();
      while (hold_i) @(posedge clk_i);
      @(negedge clk_i);
      ta_n_o = 1'b0;
      @(posedge clk_i);
      if (!d_oe_i) $fatal(1, "%m: write TA without driven data");
      size = (tsiz == 3'b000) ? 8 : int'(tsiz);
      for (int k = 0; k < size; k++)
        if (int'(addr) + k < MEM_BYTES)
          mem[int'(addr) + k] = d_i[63-8*(int'(addr[2:0]) + k) -: 8];
      writes++;
      @(negedge clk_i);
      ta_n_o = 1'b1;
    end else begin
      for (int index = 0; index < (burst ? 4 : 1); index++) read_beat(index);
      // Normal-mode DRTRY confirmation of the final beat.
      @(posedge clk_i);
      if (burst) bursts++;
      else reads++;
    end
    in_data = 1'b0;
    d_o = 64'b0;
  endtask

  initial begin : serve
    logic retried;
    forever begin
      address_tenure(retried);
      if (!retried) data_tenure();
    end
  end
endmodule
