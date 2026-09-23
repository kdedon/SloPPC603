// Task-driven responder for the bounded four-beat line-read test.
module bus60x_line_target_bfm (
  input  logic        clk_i,
  input  logic        br_n_i,
  input  logic        abb_n_i,
  input  logic        abb_oe_i,
  input  logic        ts_n_i,
  input  logic        ts_oe_i,
  input  logic [31:0] a_i,
  input  logic        dbb_n_i,
  input  logic        dbb_oe_i,
  output logic        bg_n_o,
  output logic        aack_n_o,
  output logic        artry_n_o,
  output logic        dbg_n_o,
  output logic [63:0] d_o,
  output logic        ta_n_o,
  output logic        drtry_n_o,
  output logic        tea_n_o
);
  logic [31:0] captured_addr;

  initial begin
    bg_n_o = 1'b1;
    aack_n_o = 1'b1;
    artry_n_o = 1'b1;
    dbg_n_o = 1'b1;
    d_o = 64'b0;
    ta_n_o = 1'b1;
    drtry_n_o = 1'b1;
    tea_n_o = 1'b1;
    captured_addr = 32'b0;
  end

  task automatic wait_cycles(input integer count);
    for (integer cycle = 0; cycle < count; cycle++)
      @(posedge clk_i);
  endtask

  task automatic grant_address(
    input integer bg_wait,
    input integer aack_wait,
    input logic retry
  );
    integer timeout;
    begin
      timeout = 0;
      while (br_n_i && timeout < 64) begin
        @(posedge clk_i);
        timeout++;
      end
      if (br_n_i) $fatal(1, "line BFM timed out waiting for BR");
      wait_cycles(bg_wait);
      @(negedge clk_i);
      bg_n_o = 1'b0;
      timeout = 0;
      while (!(abb_oe_i && !abb_n_i && ts_oe_i && !ts_n_i) &&
             timeout < 64) begin
        @(posedge clk_i);
        timeout++;
      end
      if (!(abb_oe_i && !abb_n_i && ts_oe_i && !ts_n_i))
        $fatal(1, "line BFM timed out waiting for TS/ABB");
      captured_addr = a_i;
      @(negedge clk_i);
      bg_n_o = 1'b1;
      wait_cycles(aack_wait);
      @(negedge clk_i);
      aack_n_o = 1'b0;
      @(posedge clk_i);
      @(negedge clk_i);
      aack_n_o = 1'b1;
      artry_n_o = retry ? 1'b0 : 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      artry_n_o = 1'b1;
    end
  endtask

  task automatic grant_data(input integer dbg_wait);
    integer timeout;
    begin
      wait_cycles(dbg_wait);
      @(negedge clk_i);
      dbg_n_o = 1'b0;
      timeout = 0;
      while (!(dbb_oe_i && !dbb_n_i) && timeout < 64) begin
        @(posedge clk_i);
        timeout++;
      end
      if (!(dbb_oe_i && !dbb_n_i))
        $fatal(1, "line BFM timed out waiting for DBB");
      @(negedge clk_i);
      dbg_n_o = 1'b1;
    end
  endtask

  task automatic sample_ta(input logic [63:0] value);
    begin
      @(negedge clk_i);
      d_o = value;
      ta_n_o = 1'b0;
      @(posedge clk_i);
      @(negedge clk_i);
      ta_n_o = 1'b1;
    end
  endtask

  task automatic sample_confirmation(
    input logic cancel,
    input logic next_ta,
    input logic [63:0] next_value
  );
    begin
      drtry_n_o = cancel ? 1'b0 : 1'b1;
      ta_n_o = next_ta ? 1'b0 : 1'b1;
      if (next_ta)
        d_o = next_value;
      @(posedge clk_i);
      @(negedge clk_i);
      ta_n_o = 1'b1;
    end
  endtask

  task automatic sample_tea;
    begin
      @(negedge clk_i);
      tea_n_o = 1'b0;
      @(posedge clk_i);
      @(negedge clk_i);
      tea_n_o = 1'b1;
    end
  endtask

  task automatic clear_drtry;
    begin
      drtry_n_o = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
    end
  endtask
endmodule
