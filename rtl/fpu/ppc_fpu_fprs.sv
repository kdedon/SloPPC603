// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Architectural FPR storage: two write ports (the second wins on a shared
// index) and READS combinational read ports.
module ppc_fpu_fprs #(
    parameter int WIDTH = 64,
    parameter int READS = 9
) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic [1:0] we_i,
    input  logic [1:0][4:0] waddr_i,
    input  logic [1:0][WIDTH-1:0] wdata_i,
    input  logic [READS-1:0][4:0] raddr_i,
    output logic [READS-1:0][WIDTH-1:0] rdata_o
);
    logic [WIDTH-1:0] fpr_q [0:31];

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            for (integer i = 0; i < 32; i++) fpr_q[i] <= '0;
        end else begin
            if (we_i[0]) fpr_q[waddr_i[0]] <= wdata_i[0];
            if (we_i[1]) fpr_q[waddr_i[1]] <= wdata_i[1];
        end
    end

    always_comb begin
        for (int port = 0; port < READS; port++)
            rdata_o[port] = fpr_q[raddr_i[port]];
    end
endmodule
`default_nettype wire
