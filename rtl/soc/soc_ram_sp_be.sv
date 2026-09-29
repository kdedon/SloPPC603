// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Single-port block RAM, 64-bit words with per-byte write enables and a
// registered read; the read data of a write is undefined. INIT_FILE preloads
// it: in simulation a $readmemh file (one 16-digit word per line, byte 0 in
// the top bits), in synthesis a .mif with the same 64-bit words.
module soc_ram_sp_be #(
  parameter int DEPTH = 32768,
  parameter INIT_FILE = ""
) (
  input  logic                     clk_i,
  input  logic                     req_i,
  input  logic [7:0]               we_i,
  input  logic [$clog2(DEPTH)-1:0] addr_i,
  input  logic [63:0]              wdata_i,
  output logic [63:0]              rdata_o
);
`ifdef VERILATOR
  logic [7:0][7:0] mem [DEPTH];

  generate
    if (INIT_FILE != "") begin : g_init
      initial $readmemh(INIT_FILE, mem);
    end
  endgenerate

  always_ff @(posedge clk_i) begin
    for (int b = 0; b < 8; b++)
      if (req_i && we_i[b]) mem[addr_i][b] <= wdata_i[8*b +: 8];
    if (req_i) rdata_o <= mem[addr_i];
  end
`else
  // Inferred byte-enable RAM is split into byte-wide RAMs that drop the init
  // data, so synthesis instantiates the RAM directly.
  altsyncram #(
    .operation_mode                ("SINGLE_PORT"),
    .intended_device_family        ("Cyclone V"),
    .lpm_type                      ("altsyncram"),
    .ram_block_type                ("M10K"),
    .numwords_a                    (DEPTH),
    .widthad_a                     ($clog2(DEPTH)),
    .width_a                       (64),
    .width_byteena_a               (8),
    .byte_size                     (8),
    .outdata_reg_a                 ("UNREGISTERED"),
    .outdata_aclr_a                ("NONE"),
    .clock_enable_input_a          ("NORMAL"),
    .clock_enable_output_a         ("BYPASS"),
    .read_during_write_mode_port_a ("DONT_CARE"),
    .power_up_uninitialized        ("FALSE"),
    .init_file                     (INIT_FILE == "" ? "UNUSED" : INIT_FILE)
  ) ram (
    .clock0    (clk_i),
    .clocken0  (req_i),
    .address_a (addr_i),
    .wren_a    (|we_i),
    .byteena_a (we_i),
    .data_a    (wdata_i),
    .q_a       (rdata_o)
  );
`endif
endmodule
`default_nettype wire
