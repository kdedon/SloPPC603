// Task-driven, non-synthesizable target used by tb_bus60x.sv.  It is kept
// deliberately simple so the master test controls every grant and termination
// edge.  The byte array uses architectural addresses BASE_ADDR..BASE_ADDR+255.
module bus60x_target_bfm #(
  parameter logic [31:0] BASE_ADDR = 32'h0000_1000,
  parameter int MEM_BYTES = 256
) (
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
  logic [7:0] mem [0:MEM_BYTES-1];
  logic [31:0] captured_addr;
  integer index;

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
    for (index = 0; index < MEM_BYTES; index = index + 1)
      mem[index] = 8'b0;
  end

  task automatic wait_cycles(input integer count);
    integer cycle;
    begin
      for (cycle = 0; cycle < count; cycle = cycle + 1)
        @(posedge clk_i);
    end
  endtask

  task automatic wait_for_address_request(input integer limit);
    integer cycle;
    begin
      cycle = 0;
      while (br_n_i && cycle < limit) begin
        @(posedge clk_i);
        cycle = cycle + 1;
      end
      if (br_n_i)
        $fatal(1, "BFM timed out waiting for BR");
    end
  endtask

  task automatic grant_address(
    input integer bg_wait,
    input integer aack_wait,
    input logic   retry,
    input logic   early_artry_only
  );
    integer cycle;
    begin
      wait_for_address_request(64);
      wait_cycles(bg_wait);
      @(negedge clk_i);
      bg_n_o = 1'b0;
      cycle = 0;
      while (!(abb_oe_i && !abb_n_i && ts_oe_i && !ts_n_i) && cycle < 64) begin
        @(posedge clk_i);
        cycle = cycle + 1;
      end
      if (!(abb_oe_i && !abb_n_i && ts_oe_i && !ts_n_i))
        $fatal(1, "BFM timed out waiting for TS/ABB");
      captured_addr = a_i;
      @(negedge clk_i);
      bg_n_o = 1'b1;
      if (early_artry_only)
        artry_n_o = 1'b0;
      wait_cycles(aack_wait);
      @(negedge clk_i);
      if (early_artry_only)
        artry_n_o = 1'b1;
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
    integer cycle;
    begin
      wait_cycles(dbg_wait);
      @(negedge clk_i);
      dbg_n_o = 1'b0;
      cycle = 0;
      while (!(dbb_oe_i && !dbb_n_i) && cycle < 64) begin
        @(posedge clk_i);
        cycle = cycle + 1;
      end
      if (!(dbb_oe_i && !dbb_n_i))
        $fatal(1, "BFM timed out waiting for DBB");
      @(negedge clk_i);
      dbg_n_o = 1'b1;
    end
  endtask

  task automatic drive_memory_data;
    integer bus_lane;
    integer memory_index;
    begin
      d_o = 64'b0;
      for (bus_lane = 0; bus_lane < 8; bus_lane = bus_lane + 1) begin
        memory_index = (captured_addr - {29'b0, captured_addr[2:0]}) -
                       BASE_ADDR + bus_lane;
        if ((memory_index >= 0) && (memory_index < MEM_BYTES))
          d_o[63-(8*bus_lane) -: 8] = mem[memory_index];
      end
    end
  endtask

  task automatic acknowledge_normal_read(input integer ta_wait);
    begin
      wait_cycles(ta_wait);
      drive_memory_data();
      @(negedge clk_i);
      ta_n_o = 1'b0;
      @(posedge clk_i);
      @(negedge clk_i);
      ta_n_o = 1'b1;
      @(posedge clk_i); // normal-mode DRTRY confirmation
      d_o = 64'b0;
    end
  endtask

  task automatic acknowledge_write(input integer ta_wait);
    begin
      wait_cycles(ta_wait);
      @(negedge clk_i);
      ta_n_o = 1'b0;
      @(posedge clk_i);
      @(negedge clk_i);
      ta_n_o = 1'b1;
    end
  endtask

  task automatic terminate_with_tea(input integer wait_count);
    begin
      wait_cycles(wait_count);
      @(negedge clk_i);
      tea_n_o = 1'b0;
      @(posedge clk_i);
      @(negedge clk_i);
      tea_n_o = 1'b1;
    end
  endtask

  task automatic drive_provisional(
    input logic [63:0] value,
    input logic        cancel,
    input logic        simultaneous_next,
    input logic [63:0] next_value
  );
    begin
      d_o = value;
      @(negedge clk_i);
      ta_n_o = 1'b0;
      @(posedge clk_i);
      @(negedge clk_i);
      ta_n_o = simultaneous_next ? 1'b0 : 1'b1;
      drtry_n_o = cancel ? 1'b0 : 1'b1;
      if (simultaneous_next)
        d_o = next_value;
      @(posedge clk_i);
      @(negedge clk_i);
      ta_n_o = 1'b1;
      if (!simultaneous_next && cancel)
        d_o = next_value;
    end
  endtask

  // Low-level normal-mode helpers used for consecutive replacement tests.
  // Each task drives at a falling edge and lets the master sample at the next
  // rising edge.
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
    input logic        cancel,
    input logic        replacement_valid,
    input logic [63:0] replacement_value
  );
    begin
      drtry_n_o = cancel ? 1'b0 : 1'b1;
      ta_n_o = replacement_valid ? 1'b0 : 1'b1;
      if (replacement_valid)
        d_o = replacement_value;
      @(posedge clk_i);
      @(negedge clk_i);
      ta_n_o = 1'b1;
    end
  endtask

  task automatic set_drtry(input logic asserted);
    begin
      @(negedge clk_i);
      drtry_n_o = asserted ? 1'b0 : 1'b1;
    end
  endtask

  task automatic set_artry(input logic asserted);
    begin
      @(negedge clk_i);
      artry_n_o = asserted ? 1'b0 : 1'b1;
    end
  endtask

  task automatic sample_termination(
    input logic        ta_asserted,
    input logic        tea_asserted,
    input logic        drtry_asserted,
    input logic [63:0] value
  );
    begin
      @(negedge clk_i);
      d_o = value;
      ta_n_o = ta_asserted ? 1'b0 : 1'b1;
      tea_n_o = tea_asserted ? 1'b0 : 1'b1;
      drtry_n_o = drtry_asserted ? 1'b0 : 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      ta_n_o = 1'b1;
      tea_n_o = 1'b1;
      drtry_n_o = 1'b1;
    end
  endtask

  task automatic sample_confirmation_tea;
    begin
      tea_n_o = 1'b0;
      @(posedge clk_i);
      @(negedge clk_i);
      tea_n_o = 1'b1;
    end
  endtask

  task automatic finish_replacement(input logic confirm);
    begin
      if (!confirm) begin
        @(negedge clk_i);
        ta_n_o = 1'b0;
        @(posedge clk_i);
        @(negedge clk_i);
        ta_n_o = 1'b1;
      end
      drtry_n_o = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      d_o = 64'b0;
    end
  endtask
endmodule
