// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Simple dual-port block RAM with per-byte write enables and a registered
// read. Contents are not reset. A read of the address being written returns
// undefined data; callers discard it.
module ppc_ram_sdp_be #(
  parameter int DEPTH = 512,
  parameter int BYTES = 8
) (
  input  logic                     clk_i,
  input  logic [BYTES-1:0]         we_i,
  input  logic [$clog2(DEPTH)-1:0] waddr_i,
  input  logic [8*BYTES-1:0]       wdata_i,
  input  logic [$clog2(DEPTH)-1:0] raddr_i,
  output logic [8*BYTES-1:0]       rdata_o
);
`ifdef VERILATOR
  logic [8*BYTES-1:0] mem [DEPTH];

  always_ff @(posedge clk_i) begin
    for (int b = 0; b < BYTES; b++)
      if (we_i[b]) mem[waddr_i][8*b +: 8] <= wdata_i[8*b +: 8];
    rdata_o <= mem[raddr_i];
  end
`else
  // Inferred byte-enable RAM is split into one byte-wide M10K per lane, so
  // synthesis instantiates the RAM directly and packs two lanes per block.
  altsyncram #(
    .operation_mode                     ("DUAL_PORT"),
    .intended_device_family             ("Cyclone V"),
    .lpm_type                           ("altsyncram"),
    .ram_block_type                     ("M10K"),
    .numwords_a                         (DEPTH),
    .widthad_a                          ($clog2(DEPTH)),
    .width_a                            (8*BYTES),
    .width_byteena_a                    (BYTES),
    .byte_size                          (8),
    .numwords_b                         (DEPTH),
    .widthad_b                          ($clog2(DEPTH)),
    .width_b                            (8*BYTES),
    .address_reg_b                      ("CLOCK0"),
    .outdata_reg_b                      ("UNREGISTERED"),
    .outdata_aclr_b                     ("NONE"),
    .clock_enable_input_a               ("BYPASS"),
    .clock_enable_input_b               ("BYPASS"),
    .clock_enable_output_b              ("BYPASS"),
    .read_during_write_mode_mixed_ports ("DONT_CARE"),
    .power_up_uninitialized             ("FALSE"),
    .init_file                          ("UNUSED")
  ) ram (
    .clock0    (clk_i),
    .wren_a    (|we_i),
    .byteena_a (we_i),
    .address_a (waddr_i),
    .data_a    (wdata_i),
    .address_b (raddr_i),
    .q_b       (rdata_o)
  );
`endif
endmodule
`default_nettype wire
