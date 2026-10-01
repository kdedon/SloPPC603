// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
// Six read and two write ports of the GPR file against a model: every
// register through every port from each write port, both ports in one cycle,
// write-write ordering across cycles, and reads in the cycle of a write.
module tb_regfile_gpr_ports #(
  parameter bit ENABLE_TGPR = 1'b1
);
  logic clk_i = 1'b0;
  always #5 clk_i <= ~clk_i;
  logic rst_ni, tgpr_i, ready_o;
  logic [4:0] read_a_i, read_b_i, read_c_i, read_a1_i, read_b1_i, read_c1_i;
  logic [31:0] read_a_o, read_b_o, read_c_o, read_a1_o, read_b1_o, read_c1_o;
  logic write_i, write1_i;
  logic [4:0] write_reg_i, write1_reg_i;
  logic [31:0] write_value_i, write1_value_i;

  ppc_regfile_gpr #(.ENABLE_TGPR(ENABLE_TGPR)) dut (.*);

  logic [31:0] model_gpr [32];
  logic [31:0] model_tgpr [4];
  logic [5:0][4:0] rd;
  logic [31:0] got [6];
  int checks, raw_hits [2], both_cycles, single_cycles [2], ww_pairs;

  assign got[0] = read_a_o;
  assign got[1] = read_b_o;
  assign got[2] = read_c_o;
  assign got[3] = read_a1_o;
  assign got[4] = read_b1_o;
  assign got[5] = read_c1_o;

  function automatic logic shadowed(input logic [4:0] r);
    return ENABLE_TGPR && tgpr_i && r < 5'd4;
  endfunction

  function automatic logic [31:0] expected(input logic [4:0] r);
    return shadowed(r) ? model_tgpr[r[1:0]] : model_gpr[r];
  endfunction

  // Reads settle before the edge, so a register written this cycle must
  // still read its old value.
  task automatic check_reads;
    read_a_i = rd[0];
    read_b_i = rd[1];
    read_c_i = rd[2];
    read_a1_i = rd[3];
    read_b1_i = rd[4];
    read_c1_i = rd[5];
    #1;
    for (int p = 0; p < 6; p++) begin
      if (got[p] !== expected(rd[p]))
        $fatal(1, "read port %0d r%0d tgpr=%0b got %08x expected %08x",
               p, rd[p], tgpr_i, got[p], expected(rd[p]));
      checks++;
      if (write_i && rd[p] == write_reg_i) raw_hits[0]++;
      if (write1_i && rd[p] == write1_reg_i) raw_hits[1]++;
    end
  endtask

  task automatic model_write(input logic [4:0] r, input logic [31:0] v);
    if (shadowed(r)) model_tgpr[r[1:0]] = v;
    else model_gpr[r] = v;
  endtask

  // Drive at the falling edge, check, then commit both writes on the edge.
  task automatic step(input logic w0, input logic [4:0] r0, input logic [31:0] v0,
                      input logic w1, input logic [4:0] r1, input logic [31:0] v1);
    @(negedge clk_i);
    write_i = w0;
    write_reg_i = r0;
    write_value_i = v0;
    write1_i = w1;
    write1_reg_i = r1;
    write1_value_i = v1;
    check_reads();
    if (w0 && w1) both_cycles++;
    else if (w0) single_cycles[0]++;
    else if (w1) single_cycles[1]++;
    @(posedge clk_i);
    if (w0) model_write(r0, v0);
    if (w1) model_write(r1, v1);
    #1;
    write_i = 1'b0;
    write1_i = 1'b0;
  endtask

  task automatic idle_check;
    step(1'b0, '0, '0, 1'b0, '0, '0);
  endtask

  task automatic set_reads(input logic [4:0] r);
    for (int p = 0; p < 6; p++) rd[p] = r;
  endtask

  // Every register through every read port.
  task automatic sweep_reads;
    for (int r = 0; r < 32; r++) begin
      set_reads(5'(r));
      idle_check();
    end
  endtask

  initial begin
    checks = 0;
    raw_hits = '{0, 0};
    single_cycles = '{0, 0};
    both_cycles = 0;
    ww_pairs = 0;
    rst_ni = 1'b0;
    tgpr_i = 1'b0;
    set_reads('0);
    write_i = 1'b0;
    write1_i = 1'b0;
    write_reg_i = '0;
    write1_reg_i = '0;
    write_value_i = '0;
    write1_value_i = '0;
    for (int i = 0; i < 32; i++) model_gpr[i] = '0;
    for (int i = 0; i < 4; i++) model_tgpr[i] = '0;
    repeat (2) @(posedge clk_i);
    @(negedge clk_i);
    rst_ni = 1'b1;
    while (!ready_o) @(posedge clk_i);
    sweep_reads();

    // Each write port alone, every register; reads include the one written.
    for (int port = 0; port < 2; port++) begin
      for (int r = 0; r < 32; r++) begin
        set_reads(5'(r));
        if (port == 0) step(1'b1, 5'(r), {8'(port + 1), 19'b0, 5'(r)}, 1'b0, '0, '0);
        else step(1'b0, '0, '0, 1'b1, 5'(r), {8'(port + 1), 19'b0, 5'(r)});
      end
      sweep_reads();
    end

    // Both ports in one cycle, distinct registers, both orders of index.
    for (int r = 0; r < 32; r++) begin
      rd[0] = 5'(r);
      rd[1] = 5'(r ^ 1);
      rd[2] = 5'(r);
      rd[3] = 5'(r ^ 1);
      rd[4] = 5'(r);
      rd[5] = 5'(r ^ 1);
      step(1'b1, 5'(r), 32'h3300_0000 | r, 1'b1, 5'(r ^ 1), 32'h3311_0000 | r);
    end
    sweep_reads();

    // Write-write to one register on consecutive edges, each port order.
    for (int r = 0; r < 32; r++) begin
      set_reads(5'(r));
      step(1'b0, '0, '0, 1'b1, 5'(r), 32'h4410_0000 | r);
      step(1'b1, 5'(r), 32'h4400_0000 | r, 1'b0, '0, '0);
      idle_check();
      step(1'b1, 5'(r), 32'h4500_0000 | r, 1'b0, '0, '0);
      step(1'b0, '0, '0, 1'b1, 5'(r), 32'h4510_0000 | r);
      idle_check();
      ww_pairs += 2;
    end

    // Random traffic with reads aimed at the written registers, in both
    // modes when the shadow bank exists.
    for (int n = 0; n < 40000; n++) begin
      logic w0, w1;
      logic [4:0] r0, r1;
      if (n % 5000 == 0) begin
        @(negedge clk_i);
        tgpr_i = ENABLE_TGPR && ((n / 5000) % 2 == 1);
      end
      w0 = 1'($urandom_range(0, 1));
      w1 = 1'($urandom_range(0, 1));
      r0 = 5'($urandom_range(0, 31));
      r1 = 5'($urandom_range(0, 31));
      if (n % 3 == 0) r1 = r0 ^ 5'(1 << $urandom_range(0, 4));
      if (w0 && w1 && r0 == r1) r1 = r0 ^ 5'd1;
      for (int p = 0; p < 6; p++) begin
        case ($urandom_range(0, 3))
          0: rd[p] = r0;
          1: rd[p] = r1;
          default: rd[p] = 5'($urandom_range(0, 31));
        endcase
      end
      step(w0, r0, $urandom, w1, r1, $urandom);
    end
    tgpr_i = 1'b0;
    sweep_reads();
    if (ENABLE_TGPR) begin
      @(negedge clk_i);
      tgpr_i = 1'b1;
      sweep_reads();
    end

    if (raw_hits[0] == 0 || raw_hits[1] == 0 || both_cycles == 0 ||
        single_cycles[0] == 0 || single_cycles[1] == 0)
      $fatal(1, "coverage hole");
    $display("PASS GPR ports tgpr=%0d: %0d read checks, %0d single-port-0, %0d single-port-1, %0d dual-write cycles, %0d write-write pairs, same-cycle read-after-write %0d (port 0) %0d (port 1)",
             ENABLE_TGPR, checks, single_cycles[0], single_cycles[1], both_cycles,
             ww_pairs, raw_hits[0], raw_hits[1]);
    $finish;
  end
endmodule
