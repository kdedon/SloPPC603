// Stateless selected-bank 32-bit BAT translation.  Caller supplies IBATs for
// instruction accesses or DBATs for data accesses; no segment/TLB fallback here.
// Local configuration rejection is not an architectural exception mechanism.
module ppc_bat_translate (
  input  logic              valid_i,
  input  logic              instruction_i,
  input  logic              write_i,
  input  logic [31:0]       ea_i,
  input  logic              msr_ir_i,
  input  logic              msr_dr_i,
  input  logic              msr_pr_i,
  input  logic [3:0][31:0]  batu_i,
  input  logic [3:0][31:0]  batl_i,
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
  output logic [1:0]        pp_o
);
  logic [3:0][31:0] address_mask;
  logic [3:0] active;
  logic [3:0] bad;
  logic overlaps;
  logic translation_enabled;

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
    // [12:2], [1], [0]. BATL WIMG / PP become [6:3] / [1:0].
    active = '0;
    bad = '0;
    address_mask = '0;
    overlaps = 1'b0;
    translation_enabled = instruction_i ? msr_ir_i : msr_dr_i;
    for (integer i = 0; i < 4; i++) begin
      active[i] = |batu_i[i][1:0];
      address_mask[i] = ~{4'b0000, batu_i[i][12:2], 17'h1ffff};
      bad[i] = active[i] &&
        (!legal_length(batu_i[i][12:2]) ||
         |batu_i[i][16:13] || |batl_i[i][16:7] || batl_i[i][2] ||
         |(batu_i[i][31:17] & ~address_mask[i][31:17]) ||
         |(batl_i[i][31:17] & ~address_mask[i][31:17]) ||
         (instruction_i && batl_i[i][6]));
    end
    for (integer i = 0; i < 4; i++) begin
      for (integer j = i + 1; j < 4; j++) begin
        // Reject intersecting effective ranges if either privilege could hit
        // both. Check independent of current PR and translation enable.
        if (active[i] && active[j] && !bad[i] && !bad[j] &&
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
          wimg_o = instruction_i ? 4'b0001 : 4'b0011;
        end else begin
          for (integer i = 0; i < 4; i++) begin
            if (batu_i[i][msr_pr_i ? 0 : 1] &&
                (ea_i & address_mask[i]) == (batu_i[i] & 32'hfffe0000)) begin
              match_o[i] = 1'b1;
              hit_index_o = 2'(i);
            end
          end
          bat_hit_o = |match_o;
          bat_miss_o = !bat_hit_o;
          if (bat_hit_o) begin
            pp_o = batl_i[hit_index_o][1:0];
            wimg_o = batl_i[hit_index_o][6:3];
            protection_fault_o = pp_o == 2'b00 || (write_i && pp_o != 2'b10);
            // Specific 603e Table 5-3 overrides generic PEM IBAT G reservation.
            guarded_fault_o = instruction_i && wimg_o[0];
            allow_o = !protection_fault_o && !guarded_fault_o;
            if (allow_o)
              pa_o = (batl_i[hit_index_o] & 32'hfffe0000) |
                     (ea_i & ~address_mask[hit_index_o]);
          end
        end
      end
    end
  end
endmodule
