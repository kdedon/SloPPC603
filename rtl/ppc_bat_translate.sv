// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Stateless selected-bank 32-bit BAT translation. Caller supplies IBATs for
// instruction accesses or DBATs for data accesses. VALIDATE_BANK=0 drops the
// whole-bank configuration checks, whose outputs then read zero. Overlapping
// valid entries are a programming error with unpredictable results (UM 5.3
// implementation note, PEM 7.4.2); the lowest-numbered match wins. BL acts
// bitwise, so a BL value outside PEM Table 7-10 masks the bits it sets.
// HAS_602 adds the IBAT NE and SE bits and the HID0 real-mode WIMG.
module ppc_bat_translate #(
  parameter bit VALIDATE_BANK = 1'b1,
  parameter bit HAS_602 = 1'b0
) (
  input  logic              valid_i,
  input  logic              instruction_i,
  input  logic              write_i,
  input  logic [31:0]       ea_i,
  input  logic              msr_ir_i,
  input  logic              msr_dr_i,
  input  logic              msr_pr_i,
  input  logic [3:0][31:0]  batu_i,
  input  logic [3:0][31:0]  batl_i,
  // 602 HID0[WIMG]: real-mode attributes for both sides.
  input  logic [3:0]        default_wimg_i,
  output logic              allow_o,
  output logic              bypass_o,
  output logic              bat_hit_o,
  output logic              bat_miss_o,
  output logic              protection_fault_o,
  output logic              guarded_fault_o,
  output logic              config_error_o,
  output logic              invalid_input_o,
  output logic [3:0]        invalid_entry_o,
  output logic              overlap_o,
  output logic [3:0]        match_o,
  output logic [1:0]        hit_index_o,
  output logic [31:0]       pa_o,
  output logic [3:0]        wimg_o,
  output logic [1:0]        pp_o,
  // 602 IBAT SE of an allowed instruction hit.
  output logic              se_o
);
  logic [3:0][31:0] address_mask;
  logic [3:0] active;
  logic [3:0] bad;
  logic overlaps;
  logic translation_enabled;
  logic [31:0] hit_lower, hit_mask;
  logic [3:0] winner;

  // PEM Table 7-10: twelve masks, 128 KiB through 256 MiB.
  function automatic logic legal_length(input logic [10:0] bl);
    case (bl)
      11'h000, 11'h001, 11'h003, 11'h007, 11'h00f, 11'h01f,
      11'h03f, 11'h07f, 11'h0ff, 11'h1ff, 11'h3ff, 11'h7ff:
        return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  always_comb begin
    // PowerPC bits 0:14 / 19:29 / 30 / 31 become HDL [31:17],
    // [12:2], [1], [0]. BATL WIMG / PP become [6:3] / [1:0]; 602 IBATL
    // NE / SE (bits 21 / 22) become [10] / [9].
    active = '0;
    bad = '0;
    address_mask = '0;
    overlaps = 1'b0;
    translation_enabled = instruction_i ? msr_ir_i : msr_dr_i;
    for (integer i = 0; i < 4; i++) begin
      active[i] = |batu_i[i][1:0];
      address_mask[i] = ~{4'b0000, batu_i[i][12:2], 17'h1ffff};
      bad[i] = VALIDATE_BANK && active[i] &&
        (!legal_length(batu_i[i][12:2]) ||
         |batu_i[i][16:13] || |batl_i[i][16:11] || |batl_i[i][8:7] ||
         (!(HAS_602 && instruction_i) && |batl_i[i][10:9]) || batl_i[i][2] ||
         |(batu_i[i][31:17] & ~address_mask[i][31:17]) ||
         |(batl_i[i][31:17] & ~address_mask[i][31:17]) ||
         (instruction_i && batl_i[i][6]));
    end
    for (integer i = 0; i < 4; i++) begin
      for (integer j = i + 1; j < 4; j++) begin
        // Reject intersecting effective ranges if either privilege could hit
        // both. Check independent of current PR and translation enable.
        if (VALIDATE_BANK && active[i] && active[j] && !bad[i] && !bad[j] &&
            |(batu_i[i][1:0] & batu_i[j][1:0]) &&
            (((batu_i[i] ^ batu_i[j]) & address_mask[i] &
              address_mask[j]) == 32'b0))
          overlaps = 1'b1;
      end
    end

    allow_o = 1'b0;
    bypass_o = 1'b0;
    bat_hit_o = 1'b0;
    bat_miss_o = 1'b0;
    protection_fault_o = 1'b0;
    guarded_fault_o = 1'b0;
    config_error_o = 1'b0;
    invalid_input_o = 1'b0;
    invalid_entry_o = '0;
    overlap_o = 1'b0;
    match_o = '0;
    hit_index_o = '0;
    pa_o = '0;
    wimg_o = '0;
    pp_o = '0;
    se_o = 1'b0;
    hit_lower = '0;
    hit_mask = '0;
    winner = '0;
    if (valid_i) begin
      invalid_entry_o = bad;
      overlap_o = overlaps;
      invalid_input_o = instruction_i && write_i;
      config_error_o = (|bad) || overlaps || invalid_input_o;
      if (!config_error_o) begin
        if (!translation_enabled) begin
          allow_o = 1'b1;
          bypass_o = 1'b1;
          pa_o = ea_i;
          // 603e UM §5.2: real-mode instruction/data attributes differ.
          // 602UM Table 2-7: HID0[WIMG] sets both.
          if (HAS_602) wimg_o = default_wimg_i;
          else wimg_o = instruction_i ? 4'b0001 : 4'b0011;
        end else begin
          for (integer i = 0; i < 4; i++)
            match_o[i] = batu_i[i][msr_pr_i ? 0 : 1] &&
              (ea_i & address_mask[i]) == (batu_i[i] & 32'hfffe0000);
          winner = match_o & ~{match_o[2:0] | {match_o[1:0], 1'b0} |
                                    {match_o[0], 2'b0}, 1'b0};
          for (integer i = 0; i < 4; i++) begin
            hit_lower |= {32{winner[i]}} & batl_i[i];
            hit_mask |= {32{winner[i]}} & address_mask[i];
          end
          hit_index_o = {winner[3] | winner[2],
                         winner[3] | winner[1]};
          bat_hit_o = |match_o;
          bat_miss_o = !bat_hit_o;
          if (bat_hit_o) begin
            pp_o = hit_lower[1:0];
            wimg_o = hit_lower[6:3];
            protection_fault_o = pp_o == 2'b00 || (write_i && pp_o != 2'b10);
            // Specific 603e Table 5-3 overrides generic PEM IBAT G reservation.
            // 602 IBAT NE takes the same ISI cause (602UM Figure 5-27).
            guarded_fault_o = instruction_i &&
              (wimg_o[0] || (HAS_602 && hit_lower[10]));
            allow_o = !protection_fault_o && !guarded_fault_o;
            se_o = HAS_602 && instruction_i && allow_o && hit_lower[9];
            if (allow_o)
              pa_o = (hit_lower & 32'hfffe0000) | (ea_i & ~hit_mask);
          end
        end
      end
    end
  end
endmodule
`default_nettype wire
