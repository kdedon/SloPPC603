// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Architectural FPR storage in MLAB: one RAM bank per write port, each copied
// once per read port. A live-value table names the bank holding each
// register's latest value; the second write port wins on a shared index.
// Contents are not reset: a register not written since reset reads zero.
// Reads are combinational and return the value before this cycle's writes.
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
    logic [31:0] written_q;
    logic [31:0] bank_q;
    logic [READS-1:0][1:0][WIDTH-1:0] bank_data;

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            written_q <= '0;
        end else begin
            if (we_i[0]) begin
                written_q[waddr_i[0]] <= 1'b1;
                bank_q[waddr_i[0]] <= 1'b0;
            end
            if (we_i[1]) begin
                written_q[waddr_i[1]] <= 1'b1;
                bank_q[waddr_i[1]] <= 1'b1;
            end
        end
    end

    genvar port;
    genvar bank;
    generate
    for (port = 0; port < READS; port = port + 1) begin : g_read
        for (bank = 0; bank < 2; bank = bank + 1) begin : g_bank
            ppc_ram_lut #(.DEPTH(32), .WIDTH(WIDTH)) ram (
                .clk_i,
                .we_i(rst_ni && we_i[bank]),
                .waddr_i(waddr_i[bank]),
                .wdata_i(wdata_i[bank]),
                .raddr_i(raddr_i[port]),
                .rdata_o(bank_data[port][bank])
            );
        end
        assign rdata_o[port] = !written_q[raddr_i[port]] ? '0 :
            bank_data[port][bank_q[raddr_i[port]]];
    end
    endgenerate
endmodule
`default_nettype wire
