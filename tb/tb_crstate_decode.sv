// Exhaust every architecturally reserved field for MCRF and MCRXR.
module tb_crstate_decode;
  import ppc_pkg::*;
  logic [31:0] insn;
  uop_t unused_uop;
  int checks = 0;
  ppc_decode dut (.insn_i(insn), .uop_o(unused_uop));

  initial begin
    assert (IQ_DEPTH == 6) else $fatal(1, "fixture resource assumption");
    for (int dest = 0; dest < 8; dest++)
      for (int source = 0; source < 8; source++)
        for (int reserved_9_10 = 0; reserved_9_10 < 4; reserved_9_10++)
          for (int reserved_14_15 = 0; reserved_14_15 < 4; reserved_14_15++)
            for (int reserved_16_20 = 0; reserved_16_20 < 32; reserved_16_20++)
              for (int rc = 0; rc < 2; rc++) begin
                insn = 32'h4c00_0000 | (32'(dest) << 23) |
                       (32'(reserved_9_10) << 21) | (32'(source) << 18) |
                       (32'(reserved_14_15) << 16) |
                       (32'(reserved_16_20) << 11) | 32'(rc);
                #1;
                if ((reserved_9_10 == 0) && (reserved_14_15 == 0) &&
                    (reserved_16_20 == 0) && (rc == 0)) begin
                  assert (!unused_uop.illegal && unused_uop.special_op == SPECIAL_MCRF &&
                          unused_uop.needs_flags && unused_uop.write_cr0 &&
                          unused_uop.cr_field == 3'(dest) &&
                          unused_uop.cr_source_field == 3'(source) &&
                          !unused_uop.gpr_write && !unused_uop.write_ca &&
                          !unused_uop.write_ov_so && !unused_uop.write_cr_fields &&
                          !unused_uop.write_cr_bit)
                    else $fatal(1, "MCRF route/permission word=%h", insn);
                end else begin
                  assert (unused_uop.illegal && !unused_uop.needs_flags &&
                          !unused_uop.gpr_write && !unused_uop.write_ca &&
                          !unused_uop.write_ov_so && !unused_uop.write_cr0 &&
                          !unused_uop.write_cr_fields && !unused_uop.write_cr_bit)
                    else $fatal(1, "reserved MCRF accepted word=%h", insn);
                end
                checks++;
              end

    for (int dest = 0; dest < 8; dest++)
      for (int reserved_9_10 = 0; reserved_9_10 < 4; reserved_9_10++)
        for (int reserved_11_15 = 0; reserved_11_15 < 32; reserved_11_15++)
          for (int reserved_16_20 = 0; reserved_16_20 < 32; reserved_16_20++)
            for (int rc = 0; rc < 2; rc++) begin
              insn = 32'h7c00_0400 | (32'(dest) << 23) |
                     (32'(reserved_9_10) << 21) |
                     (32'(reserved_11_15) << 16) |
                     (32'(reserved_16_20) << 11) | 32'(rc);
              #1;
              if ((reserved_9_10 == 0) && (reserved_11_15 == 0) &&
                  (reserved_16_20 == 0) && (rc == 0)) begin
                assert (!unused_uop.illegal && unused_uop.special_op == SPECIAL_MCRXR &&
                        unused_uop.needs_flags && unused_uop.read_ca && unused_uop.read_so &&
                        unused_uop.write_ca && unused_uop.write_ov_so && unused_uop.write_cr0 &&
                        unused_uop.cr_field == 3'(dest) && !unused_uop.gpr_write &&
                        !unused_uop.write_cr_fields && !unused_uop.write_cr_bit)
                  else $fatal(1, "MCRXR route/permission word=%h", insn);
              end else begin
                assert (unused_uop.illegal && !unused_uop.needs_flags &&
                        !unused_uop.gpr_write && !unused_uop.write_ca &&
                        !unused_uop.write_ov_so && !unused_uop.write_cr0 &&
                        !unused_uop.write_cr_fields && !unused_uop.write_cr_bit)
                  else $fatal(1, "reserved MCRXR accepted word=%h", insn);
              end
              checks++;
            end

    assert (checks == 131072) else $fatal(1, "decode coverage count");
    $display("PASS CR state decode: all fields, reserved bits and Rc (%0d checks)", checks);
    $finish;
  end
endmodule
