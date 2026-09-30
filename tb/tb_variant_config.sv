// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Unit checks of one CPU_VARIANT, including variants the core still rejects:
// cpu_cfg() SPR-presence flags and PLL_CFG codes against the manuals, and
// decode of HID1, EAR and eciwx/ecowx as each flag requires; the 602 HID0
// mask, forms and SPRs, and the mfrom ROM against its formula.
module tb_variant_config #(
  parameter int VARIANT = 0
);
  import ppc_pkg::*;
  localparam cpu_variant_e CPU_VARIANT = cpu_variant_e'(VARIANT);
  localparam cpu_cfg_t CFG = cpu_cfg(CPU_VARIANT);

  logic [31:0] insn;
  // Only special_op is checked.
  /* verilator lint_off UNUSEDSIGNAL */
  uop_t uop;
  /* verilator lint_on UNUSEDSIGNAL */
  int checks = 0;

  ppc_decode #(
    .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1), .ENABLE_FULL_DECODE(1'b1),
    .CPU_VARIANT(CPU_VARIANT)
  ) dut (.insn_i(insn), .uop_o(uop));

  task automatic check(input bit ok, input string label);
    if (!ok) $fatal(1, "variant %0d: %s", VARIANT, label);
    checks++;
  endtask

  function automatic logic [31:0] asm_spr(input bit write, input int rt, input int spr);
    return (32'd31 << 26) | (32'(rt) << 21) | (32'(spr & 31) << 16) |
           (32'(spr >> 5) << 11) | ((write ? 32'd467 : 32'd339) << 1);
  endfunction

  task automatic expect_legal(input logic [31:0] word, input bit legal, input string label);
    insn = word;
    #1;
    // Full decode turns an illegal form into a program-exception uop.
    check((uop.special_op == SPECIAL_PROGRAM_ILLEGAL) == !legal,
          $sformatf("%s special_op=%s", label, uop.special_op.name()));
  endtask

  // Expected presence per variant: UM 1.3.1.1, Tables 2-2/2-3, App. C (603);
  // 602UM Table 2-6 (602).
  bit exp_hid1, exp_ear, exp_key, exp_abe, exp_602;
  localparam int spr_602 [7] = '{984, 986, 987, 990, 991, 1021, 1022};
  logic [3:0] legal_codes [$];
  initial begin
    exp_hid1 = CPU_VARIANT != CPU_603;
    exp_ear = CPU_VARIANT != CPU_602;
    exp_key = CPU_VARIANT != CPU_603;
    exp_abe = (CPU_VARIANT == CPU_PID7V_603E) || (CPU_VARIANT == CPU_EC603E);
    exp_602 = CPU_VARIANT == CPU_602;
    case (CPU_VARIANT)
      CPU_PID6_603E: legal_codes = '{4'b0000, 4'b0001, 4'b0010, 4'b0011, 4'b0100,
                                     4'b0101, 4'b0110, 4'b1000, 4'b1010, 4'b1100,
                                     4'b1110};
      CPU_603: legal_codes = '{4'b0000, 4'b0001, 4'b0010, 4'b0011, 4'b0100,
                               4'b0101, 4'b1000, 4'b1001, 4'b1100};
      CPU_602: legal_codes = '{4'b0100, 4'b0101, 4'b1000, 4'b1001};
      default: legal_codes = '{4'b0011, 4'b0100, 4'b0101, 4'b0110, 4'b1000,
                               4'b1010, 4'b1110};
    endcase

    check(CFG.has_hid1 == exp_hid1, "cfg has_hid1");
    check(CFG.has_ear == exp_ear, "cfg has_ear");
    check(CFG.has_srr1_key == exp_key, "cfg has_srr1_key");
    check(CFG.has_abe_ifem == exp_abe, "cfg has_abe_ifem");
    check((CFG.hid1_rmask != 0) == exp_hid1, "cfg hid1_rmask");
    // IFEM (bit 24) and ABE (bit 28) are stored only where they exist. The
    // 602 layout differs (602UM Table 2-7): bit 24 is PO, no ICE (bit 16).
    if (CPU_VARIANT == CPU_602)
      check(CFG.hid0_wmask == 32'h8af9_7caf, "cfg 602 HID0 mask");
    else
      check(CFG.hid0_wmask[7] == exp_abe && CFG.hid0_wmask[3] == exp_abe,
            "cfg HID0 IFEM/ABE mask");
    check(CFG.hid0_rmask == CFG.hid0_wmask, "cfg HID0 read mask");

    for (int code = 0; code < 16; code++) begin
      bit listed;
      listed = 1'b0;
      foreach (legal_codes[i]) if (legal_codes[i] == 4'(code)) listed = 1'b1;
      check(pll_cfg_legal(CPU_VARIANT, 4'(code)) == listed,
            $sformatf("PLL_CFG %04b legality", 4'(code)));
    end
    check(pll_cfg_legal(CPU_VARIANT, pll_cfg_default(CPU_VARIANT)) ==
          (CPU_VARIANT != CPU_602), "default PLL_CFG legal");
    check(pll_cfg_bus_1to1(pll_cfg_default(CPU_VARIANT)), "default PLL_CFG 1:1");
    // Processor:bus ratio, doubled, per code. 603e: UM Table 7-10 (PID7v
    // without 1:1 and 1.5:1); 603: UM Table C-4; 602: 602HW Table 11.
    begin
      int ratio2 [16];
      unique case (CPU_VARIANT)
        CPU_603:       ratio2 = '{2, 2, 2, 2, 4, 4, 0, 0, 6, 6, 0, 0, 8, 0, 0, 0};
        CPU_602:       ratio2 = '{0, 0, 0, 0, 4, 4, 0, 0, 6, 6, 0, 0, 0, 0, 0, 0};
        CPU_PID6_603E: ratio2 = '{2, 2, 2, 2, 4, 4, 5, 0, 6, 0, 8, 0, 3, 0, 7, 0};
        default:       ratio2 = '{0, 0, 0, 2, 4, 4, 5, 0, 6, 0, 8, 0, 0, 0, 7, 0};
      endcase
      for (int code = 0; code < 16; code++)
        check(pll_cfg_ratio2(CPU_VARIANT, 4'(code)) == ratio2[code],
              $sformatf("PLL_CFG %04b ratio", 4'(code)));
    end

    expect_legal(asm_spr(1'b0, 3, 1009), exp_hid1, "mfspr HID1");
    expect_legal(asm_spr(1'b1, 3, 1009), exp_hid1, "mtspr HID1");
    expect_legal(asm_spr(1'b0, 3, 282), exp_ear, "mfspr EAR");
    expect_legal(asm_spr(1'b1, 3, 282), exp_ear, "mtspr EAR");
    expect_legal(32'h7c63_226c, exp_ear, "eciwx");
    expect_legal(32'h7c63_236c, exp_ear, "ecowx");
    expect_legal(asm_spr(1'b0, 3, 1008), 1'b1, "mfspr HID0");
    expect_legal(asm_spr(1'b0, 3, 287), 1'b1, "mfspr PVR");
    // 602-only forms and SPRs (602UM 2.1.2, 2.3.7); strings trap there.
    expect_legal(32'h7c00_04a8, exp_602, "esa");
    expect_legal(32'h7c00_04e8, exp_602, "dsa");
    expect_legal(32'h7c64_0212, exp_602, "mfrom r3,r4");
    expect_legal(32'h7c64_2a12, 1'b0, "mfrom with rB");
    foreach (spr_602[i]) begin
      expect_legal(asm_spr(1'b0, 3, spr_602[i]), exp_602, $sformatf("mfspr %0d", spr_602[i]));
      expect_legal(asm_spr(1'b1, 3, spr_602[i]), exp_602, $sformatf("mtspr %0d", spr_602[i]));
    end
    insn = 32'h7c64_04aa;  // lswi r3,r4,0
    #1;
    check((uop.special_op == SPECIAL_EMULATION_TRAP) == exp_602, "lswi emulation trap");
    insn = 32'hfc22_182a;  // fadd f1,f2,f3
    #1;
    check((uop.special_op == SPECIAL_FPU_EMULATE) == exp_602, "fadd emulated");
    insn = 32'hec22_182a;  // fadds f1,f2,f3
    #1;
    check(uop.special_op == SPECIAL_FPU, "fadds FP class");
    for (int i = 0; i < 1024; i++) begin
      int expected;
      expected = (i < 602) ?
        int'($floor(256.0 * $log10(1.0 + 10.0 ** (-real'(i) / 256.0)) + 0.5)) : 0;
      check(int'(mfrom_rom(10'(i))) == expected, $sformatf("mfrom ROM %0d", i));
    end
    $display("PASS tb_variant_config variant=%0d: %0d checks", VARIANT, checks);
    $finish;
  end
endmodule
