module tb_regfile_tgpr #(
  parameter bit ENABLE_TGPR = 1'b1
);
  logic clk_i = 1'b0;
  always #5 clk_i <= ~clk_i;
  logic rst_ni, tgpr_i;
  logic [4:0] read_a_i, read_b_i, read_c_i;
  logic [31:0] read_a_o, read_b_o, read_c_o;
  logic write_i, update_write_i;
  logic [4:0] write_reg_i, update_reg_i;
  logic [31:0] write_value_i, update_value_i;
  int checks;

  ppc_regfile_gpr #(.ENABLE_TGPR(ENABLE_TGPR)) dut (.*);

  task automatic check_ports(
    input logic [4:0] a, input logic [31:0] av,
    input logic [4:0] b, input logic [31:0] bv,
    input logic [4:0] c, input logic [31:0] cv
  );
    @(negedge clk_i);
    read_a_i = a;
    read_b_i = b;
    read_c_i = c;
    #1;
    if (read_a_o !== av) $fatal(1, "read A r%0d got %08x expected %08x", a, read_a_o, av);
    if (read_b_o !== bv) $fatal(1, "read B r%0d got %08x expected %08x", b, read_b_o, bv);
    if (read_c_o !== cv) $fatal(1, "read C r%0d got %08x expected %08x", c, read_c_o, cv);
    checks += 3;
  endtask

  task automatic set_mode(input logic mode);
    @(negedge clk_i);
    tgpr_i = mode;
  endtask

  task automatic commit_one(input logic [4:0] dst,
                            input logic [31:0] value);
    @(negedge clk_i);
    write_i = 1'b1;
    write_reg_i = dst;
    write_value_i = value;
    @(posedge clk_i);
    #1;
    write_i = 1'b0;
  endtask

  task automatic commit_two(
    input logic [4:0] dst, input logic [31:0] value,
    input logic [4:0] update_dst, input logic [31:0] update_value
  );
    @(negedge clk_i);
    write_i = 1'b1;
    write_reg_i = dst;
    write_value_i = value;
    update_write_i = 1'b1;
    update_reg_i = update_dst;
    update_value_i = update_value;
    @(posedge clk_i);
    #1;
    write_i = 1'b0;
    update_write_i = 1'b0;
  endtask

  initial begin
    checks = 0;
    rst_ni = 1'b0;
    tgpr_i = 1'b0;
    read_a_i = '0;
    read_b_i = '0;
    read_c_i = '0;
    write_i = 1'b0;
    write_reg_i = '0;
    write_value_i = '0;
    update_write_i = 1'b0;
    update_reg_i = '0;
    update_value_i = '0;
    repeat (2) @(posedge clk_i);
    @(negedge clk_i);
    rst_ni = 1'b1;

    check_ports(5'd0, 32'd0, 5'd3, 32'd0, 5'd31, 32'd0);
    commit_one(5'd0, 32'h1000_0000);
    commit_one(5'd1, 32'h1000_0001);
    commit_one(5'd2, 32'h1000_0002);
    commit_one(5'd3, 32'h1000_0003);
    commit_one(5'd4, 32'h1000_0004);
    commit_one(5'd31, 32'h1000_001f);
    check_ports(5'd0, 32'h1000_0000, 5'd2, 32'h1000_0002,
                5'd31, 32'h1000_001f);

    set_mode(1'b1);
    check_ports(5'd0, ENABLE_TGPR ? 32'd0 : 32'h1000_0000,
                5'd3, ENABLE_TGPR ? 32'd0 : 32'h1000_0003,
                5'd4, 32'h1000_0004);
    commit_one(5'd0, 32'h2000_0000);
    commit_one(5'd3, 32'h2000_0003);
    check_ports(5'd0, 32'h2000_0000,
                5'd3, 32'h2000_0003, 5'd31, 32'h1000_001f);

    // Distinct destinations may use both retirement ports on the same edge.
    commit_two(5'd1, 32'h2000_0001, 5'd2, 32'h2000_0002);
    check_ports(5'd0, 32'h2000_0000,
                5'd1, 32'h2000_0001, 5'd2, 32'h2000_0002);
    commit_two(5'd2, 32'h3000_0002, 5'd4, 32'h3000_0004);
    check_ports(5'd2, 32'h3000_0002,
                5'd4, 32'h3000_0004, 5'd31, 32'h1000_001f);

    set_mode(1'b0);
    check_ports(5'd0, ENABLE_TGPR ? 32'h1000_0000 : 32'h2000_0000,
                5'd1, ENABLE_TGPR ? 32'h1000_0001 : 32'h2000_0001,
                5'd2, ENABLE_TGPR ? 32'h1000_0002 : 32'h3000_0002);
    check_ports(5'd3, ENABLE_TGPR ? 32'h1000_0003 : 32'h2000_0003,
                5'd4, 32'h3000_0004, 5'd31, 32'h1000_001f);
    set_mode(1'b1);
    check_ports(5'd0, 32'h2000_0000,
                5'd2, 32'h3000_0002, 5'd3, 32'h2000_0003);

    // Local reset clears both banks regardless of the active selection.
    @(negedge clk_i);
    rst_ni = 1'b0;
    @(posedge clk_i);
    #1;
    @(negedge clk_i);
    rst_ni = 1'b1;
    check_ports(5'd0, 32'd0, 5'd2, 32'd0, 5'd31, 32'd0);
    set_mode(1'b0);
    check_ports(5'd0, 32'd0, 5'd3, 32'd0, 5'd4, 32'd0);

    if ($test$plusargs("ALIAS_COLLISION")) begin
      // The retained architectural assertion must terminate this run.
      @(negedge clk_i);
      write_i = 1'b1;
      write_reg_i = 5'd1;
      update_write_i = 1'b1;
      update_reg_i = 5'd1;
      @(posedge clk_i);
      #1;
      $display("ERROR: aliased retirement writes were accepted");
      $finish;
    end

    $display("PASS TGPR register file enabled=%0d: %0d checks", ENABLE_TGPR, checks);
    $finish;
  end
endmodule
