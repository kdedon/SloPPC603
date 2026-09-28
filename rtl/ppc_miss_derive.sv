// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Pure 32-bit page-miss compare and PTEG address derivation.
// PowerPC Programming Environments Manual, sections 7.6.1.1.2,
// 7.6.1.3.2, and 7.6.1.4.2.
module ppc_miss_derive (
  input  logic [31:0] ea_i,
  input  logic [31:0] sr_i,
  input  logic [31:0] sdr1_i,
  output logic        valid_o,
  output logic [31:0] miss_page_o,
  output logic [31:0] compare_o,
  output logic [31:0] hash1_o,
  output logic [31:0] hash2_o
);
  logic [15:0] htaborg;
  logic [8:0] htabmask;
  logic [18:0] primary_hash, secondary_hash;
  // Hash derivation ignores byte offset; IMISS/DMISS retain the full EA
  // despite the manual's "effective page address" figure caption.
  logic _unused_context_bits;
  assign _unused_context_bits = ^sr_i[30:24];

  assign htaborg = sdr1_i[31:16];
  assign htabmask = sdr1_i[8:0];
  // PEM 7.6.1.4.2 defines the PTEG address as an AND with HTABMASK and an
  // OR with HTABORG. A non-contiguous mask or unaligned base is a
  // programming error; the same bitwise formula applies to it.
  // The 603e direct-store T segment does not enter a hashed lookup. Segment
  // no-execute N is deliberately not rejected here because data misses use it.
  assign valid_o = !sr_i[31];
  logic _unused_reserved_sdr1;
  assign _unused_reserved_sdr1 = ^sdr1_i[15:9];
  assign primary_hash = sr_i[18:0] ^ {3'b0, ea_i[27:12]};
  assign secondary_hash = ~primary_hash;

  always_comb begin
    miss_page_o = 32'b0;
    compare_o = 32'b0;
    hash1_o = 32'b0;
    hash2_o = 32'b0;
    if (valid_o) begin
      miss_page_o = ea_i;
      compare_o = {1'b1, sr_i[23:0], 1'b0, ea_i[27:22]};
      hash1_o = {htaborg | {7'b0, (primary_hash[18:10] & htabmask)},
                 primary_hash[9:0], 6'b0};
      hash2_o = {htaborg | {7'b0, (secondary_hash[18:10] & htabmask)},
                 secondary_hash[9:0], 6'b0};
    end
  end
endmodule
`default_nettype wire
