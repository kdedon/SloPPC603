// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// 602 MMU protection at module level, on any CPU_VARIANT: IBAT NE and SE,
// HID0[WIMG] in real mode, ITLB NE and SE, protection-only TLB entries with
// per-page NE and WE bits, SR0 key 0, and the SEBR/SER esa resolution
// (602UM Tables 2-4, 5-2, 5-3, 5-16; Figures 5-17, 5-22 to 5-28). Other
// variants must ignore the 602 bits and the protection-only request.
module tb_mmu_602 #(
  parameter int VARIANT = 4
);
  import ppc_pkg::*;
  localparam cpu_variant_e CPU_VARIANT = cpu_variant_e'(VARIANT);
  localparam bit V602 = cpu_has_602_ext(CPU_VARIANT);
  localparam int TLB_SETS = cpu_tlb_sets(CPU_VARIANT);

  int checks = 0;
  task automatic check(input string label_text, input logic [31:0] actual,
                       input logic [31:0] expected);
    checks++;
    if (actual !== expected)
      $fatal(1, "%s: got %08h expected %08h (variant %0d)", label_text,
             actual, expected, VARIANT);
  endtask

  // ---- BAT translation (combinational) ----
  logic bt_valid, bt_instruction, bt_write, bt_ir, bt_dr, bt_pr;
  logic [31:0] bt_ea;
  logic [3:0][31:0] bt_batu, bt_batl;
  logic [3:0] bt_default_wimg;
  logic bt_allow, bt_bypass, bt_hit, bt_miss, bt_protection, bt_guarded;
  logic bt_config, bt_invalid_input, bt_overlap, bt_se;
  logic [3:0] bt_invalid_entry, bt_match, bt_wimg;
  logic [1:0] bt_hit_index, bt_pp;
  logic [31:0] bt_pa;
  ppc_bat_translate #(.VALIDATE_BANK(1'b1), .HAS_602(V602)) bat (
    .valid_i(bt_valid), .instruction_i(bt_instruction), .write_i(bt_write),
    .ea_i(bt_ea), .msr_ir_i(bt_ir), .msr_dr_i(bt_dr), .msr_pr_i(bt_pr),
    .batu_i(bt_batu), .batl_i(bt_batl), .default_wimg_i(bt_default_wimg),
    .allow_o(bt_allow), .bypass_o(bt_bypass), .bat_hit_o(bt_hit),
    .bat_miss_o(bt_miss), .protection_fault_o(bt_protection),
    .guarded_fault_o(bt_guarded), .config_error_o(bt_config),
    .invalid_input_o(bt_invalid_input), .invalid_entry_o(bt_invalid_entry),
    .overlap_o(bt_overlap), .match_o(bt_match), .hit_index_o(bt_hit_index),
    .pa_o(bt_pa), .wimg_o(bt_wimg), .pp_o(bt_pp), .se_o(bt_se)
  );
  localparam logic [31:0] NE_BIT = 32'h0000_0400;  // BATL bit 21
  localparam logic [31:0] SE_BIT = 32'h0000_0200;  // BATL bit 22

  task automatic bat_case(input string name, input bit instruction,
                          input logic [31:0] lower, input bit want_config,
                          input bit want_allow, input bit want_guarded,
                          input bit want_se);
    bt_instruction = instruction;
    bt_batl[0] = lower;
    #1;
    check({name, " config"}, 32'(bt_config), 32'(want_config));
    if (!want_config) begin
      check({name, " allow"}, 32'(bt_allow), 32'(want_allow));
      check({name, " guarded"}, 32'(bt_guarded), 32'(want_guarded));
      check({name, " se"}, 32'(bt_se), 32'(want_se));
      if (want_allow) check({name, " pa"}, bt_pa, 32'h1000_0123);
    end
  endtask

  task automatic run_bat;
    bt_valid = 1'b1; bt_write = 1'b0; bt_ir = 1'b1; bt_dr = 1'b1;
    bt_pr = 1'b0; bt_ea = 32'h2000_0123; bt_default_wimg = 4'b0110;
    bt_batu = '0; bt_batl = '0;
    // 128 KiB block at EA 0x2000_0000, supervisor valid, PA 0x1000_0000.
    bt_batu[0] = 32'h2000_0002;
    // IBAT NE and SE are 602 bits; elsewhere they are reserved.
    bat_case("IBAT plain", 1'b1, 32'h1000_0002, 1'b0, 1'b1, 1'b0, 1'b0);
    bat_case("IBAT SE", 1'b1, 32'h1000_0002 | SE_BIT, !V602, 1'b1, 1'b0, V602);
    bat_case("IBAT NE", 1'b1, 32'h1000_0002 | NE_BIT, !V602, 1'b0, 1'b1, 1'b0);
    bat_case("IBAT NE SE", 1'b1, 32'h1000_0002 | NE_BIT | SE_BIT, !V602,
             1'b0, 1'b1, 1'b0);
    bat_case("DBAT NE SE reserved", 1'b0, 32'h1000_0002 | NE_BIT | SE_BIT,
             1'b1, 1'b0, 1'b0, 1'b0);
    bat_case("DBAT plain", 1'b0, 32'h1000_0002, 1'b0, 1'b1, 1'b0, 1'b0);
    // Real mode: the 602 takes HID0[WIMG] for both sides (602UM Table 2-7).
    bt_ir = 1'b0; bt_dr = 1'b0; bt_batl[0] = 32'h1000_0002;
    bt_instruction = 1'b1; #1;
    check("real I bypass", 32'(bt_bypass), 32'd1);
    check("real I se", 32'(bt_se), 32'd0);
    check("real I wimg", 32'(bt_wimg), V602 ? 32'h6 : 32'h1);
    bt_instruction = 1'b0; #1;
    check("real D wimg", 32'(bt_wimg), V602 ? 32'h6 : 32'h3);
    bt_valid = 1'b0;
  endtask

  // ---- TLB service ----
  logic clk = 1'b0;
  always #5 clk <= !clk;
  logic rst_n = 1'b0;
  logic req_valid = 1'b0, req_ready, rsp_valid, rsp_ready = 1'b0;
  tlb_req_kind_t req_kind;
  logic req_bank, req_pr, req_ks, req_kp, req_write, req_way, req_po;
  logic [31:0] req_ea;
  logic [23:0] req_vsid;
  logic [19:0] req_rpn;
  logic [3:0] req_wimg;
  logic [1:0] req_pp;
  logic [4:0] req_ext;
  logic req_c;
  tlb_req_kind_t rsp_kind;
  logic rsp_bank, rsp_allow, rsp_hit, rsp_miss, rsp_protection, rsp_guarded;
  logic rsp_no_execute, rsp_direct_store, rsp_needs_changed, rsp_privileged;
  logic rsp_refill_rejected, rsp_unsupported, rsp_invalid_input, rsp_way;
  logic rsp_c, rsp_r;
  logic [1:0] rsp_match, rsp_pp;
  logic [31:0] rsp_ea, rsp_pa;
  logic [3:0] rsp_wimg;
  esa_enable_t rsp_esa;
  logic unused_ack, unused_idle;
  ppc_tlb_service #(.TLB_SETS(TLB_SETS), .HAS_602(V602)) tlb (
    .clk_i(clk), .rst_ni(rst_n),
    .prepare_commit_i(1'b0), .prepare_abort_i(1'b0),
    .commit_ack_valid_o(unused_ack), .commit_ack_ready_i(1'b1),
    .transaction_idle_o(unused_idle),
    .req_valid_i(req_valid), .req_ready_o(req_ready), .req_kind_i(req_kind),
    .req_bank_i(req_bank), .req_ea_i(req_ea), .req_vsid_i(req_vsid),
    .req_pr_i(req_pr), .req_ks_i(req_ks), .req_kp_i(req_kp),
    .req_n_i(1'b0), .req_t_i(1'b0), .req_write_i(req_write),
    .req_way_i(req_way), .req_rpn_i(req_rpn), .req_c_i(req_c),
    .req_wimg_i(req_wimg), .req_pp_i(req_pp),
    .req_po_i(req_po), .req_ext_i(req_ext),
    .rsp_valid_o(rsp_valid), .rsp_ready_i(rsp_ready), .rsp_kind_o(rsp_kind),
    .rsp_bank_o(rsp_bank), .rsp_ea_o(rsp_ea), .rsp_allow_o(rsp_allow),
    .rsp_hit_o(rsp_hit), .rsp_miss_o(rsp_miss),
    .rsp_protection_fault_o(rsp_protection),
    .rsp_guarded_fault_o(rsp_guarded), .rsp_no_execute_o(rsp_no_execute),
    .rsp_direct_store_unsupported_o(rsp_direct_store),
    .rsp_needs_changed_o(rsp_needs_changed),
    .rsp_privileged_o(rsp_privileged),
    .rsp_refill_rejected_o(rsp_refill_rejected),
    .rsp_unsupported_o(rsp_unsupported),
    .rsp_invalid_input_o(rsp_invalid_input), .rsp_match_o(rsp_match),
    .rsp_way_o(rsp_way), .rsp_pa_o(rsp_pa), .rsp_wimg_o(rsp_wimg),
    .rsp_pp_o(rsp_pp), .rsp_c_o(rsp_c), .rsp_r_o(rsp_r),
    .rsp_esa_o(rsp_esa)
  );
  logic unused_rsp;
  assign unused_rsp = ^{rsp_kind, rsp_bank, rsp_ea, rsp_guarded,
    rsp_direct_store, rsp_needs_changed, rsp_privileged, rsp_refill_rejected,
    rsp_unsupported, rsp_invalid_input, rsp_way, rsp_c, rsp_r, rsp_match,
    rsp_pp, rsp_wimg, bt_hit, bt_miss, bt_protection, bt_invalid_input,
    bt_overlap, bt_invalid_entry, bt_match, bt_hit_index, bt_pp};

  // One request: offer, accept, then take the registered response.
  task automatic transact(input tlb_req_kind_t kind, input bit bank,
                          input logic [31:0] ea, input bit po, input bit key,
                          input bit write_access, input logic [31:0] rpa);
    @(negedge clk);
    req_kind = kind; req_bank = bank; req_ea = ea; req_po = po;
    req_vsid = 24'h00_0abc; req_pr = kind != TLB_REFILL;
    req_ks = 1'b0; req_kp = key;
    req_write = write_access; req_way = 1'b0;
    req_rpn = rpa[31:12]; req_wimg = rpa[6:3]; req_pp = rpa[1:0];
    req_ext = {rpa[11:8], rpa[2]}; req_c = rpa[7];
    req_valid = 1'b1; rsp_ready = 1'b1;
    for (int i = 0; i < 8 && !req_ready; i++) @(negedge clk);
    if (!req_ready) $fatal(1, "TLB request not accepted");
    @(negedge clk);
    req_valid = 1'b0;
    for (int i = 0; i < 8 && !rsp_valid; i++) @(negedge clk);
    if (!rsp_valid) $fatal(1, "TLB response missing");
  endtask
  task automatic load(input bit bank, input logic [31:0] ea, input bit po,
                      input logic [31:0] rpa);
    transact(TLB_REFILL, bank, ea, po, 1'b0, 1'b0, rpa);
    @(negedge clk); rsp_ready = 1'b0;
  endtask
  // Lookup outcome: 0 allow, 1 miss, 2 no-execute, 3 protection.
  task automatic lookup(input string name, input bit bank,
                        input logic [31:0] ea, input bit po, input bit key,
                        input bit write_access, input int want,
                        input logic [31:0] want_pa, input esa_enable_t want_esa);
    int got;
    transact(TLB_LOOKUP, bank, ea, po, key, write_access, 32'b0);
    got = rsp_allow ? 0 : rsp_miss ? 1 : rsp_no_execute ? 2 :
          rsp_protection ? 3 : 9;
    check({name, " outcome"}, 32'(got), 32'(want));
    if (want == 0) check({name, " pa"}, rsp_pa, want_pa);
    if (want == 2) check({name, " hit"}, 32'(rsp_hit), 32'd1);
    check({name, " esa"}, 32'(rsp_esa), 32'(want_esa));
    @(negedge clk); rsp_ready = 1'b0;
  endtask

  localparam logic [31:0] RPA = 32'h0004_5092;  // RPN 0x45, C, PP 2
  task automatic run_tlb;
    req_kind = TLB_LOOKUP; req_bank = 1'b0; req_ea = '0; req_po = 1'b0;
    req_vsid = '0; req_pr = 1'b0; req_ks = 1'b0; req_kp = 1'b0;
    req_write = 1'b0; req_way = 1'b0; req_rpn = '0; req_wimg = '0;
    req_pp = '0; req_ext = '0; req_c = 1'b0;
    repeat (2) @(negedge clk);
    rst_n = 1'b1;
    // ITLB NE and SE (602UM Figure 5-17): NE denies the fetch, SE marks esa.
    load(1'b0, 32'h0000_3000, 1'b0, RPA | NE_BIT);
    load(1'b0, 32'h0000_4000, 1'b0, RPA | SE_BIT);
    load(1'b0, 32'h0000_5000, 1'b0, RPA);
    load(1'b1, 32'h0000_3000, 1'b0, RPA | NE_BIT);
    lookup("ITLB NE", 1'b0, 32'h0000_3010, 1'b0, 1'b1, 1'b0,
           V602 ? 2 : 0, 32'h0004_5010, ESA_DENIED);
    lookup("ITLB SE", 1'b0, 32'h0000_4010, 1'b0, 1'b1, 1'b0, 0,
           32'h0004_5010, V602 ? ESA_ALLOWED : ESA_DENIED);
    lookup("ITLB plain", 1'b0, 32'h0000_5010, 1'b0, 1'b1, 1'b0, 0,
           32'h0004_5010, ESA_DENIED);
    lookup("DTLB ignores NE", 1'b1, 32'h0000_3010, 1'b0, 1'b1, 1'b0, 0,
           32'h0004_5010, ESA_DENIED);
    if (V602) begin
      // Protection-only, SR0 key 0: every access allowed, PA = EA, esa
      // decided by SEBR alone (Figure 5-28).
      lookup("PO key0 fetch", 1'b0, 32'h0123_4560, 1'b1, 1'b0, 1'b0, 0,
             32'h0123_4560, ESA_PO_BASE);
      lookup("PO key0 store", 1'b1, 32'h0123_4560, 1'b1, 1'b0, 1'b1, 0,
             32'h0123_4560, ESA_DENIED);
      // Key 1: TLB miss until the region's word is loaded (5.6.1.1).
      lookup("PO key1 miss", 1'b0, 32'h0123_4560, 1'b1, 1'b1, 1'b0, 1,
             32'b0, ESA_DENIED);
      // Region 0x0122_0000-0x0123_ffff: page 0x14 is NE0+20 -> bit 20.
      load(1'b0, 32'h0123_4560, 1'b1, 32'h0000_0800);
      load(1'b1, 32'h0123_4560, 1'b1, 32'h0000_0800);
      lookup("PO NE page", 1'b0, 32'h0123_4560, 1'b1, 1'b1, 1'b0, 2,
             32'b0, ESA_DENIED);
      lookup("PO NE clear page", 1'b0, 32'h0123_5560, 1'b1, 1'b1, 1'b0, 0,
             32'h0123_5560, ESA_PO_SER);
      lookup("PO WE store", 1'b1, 32'h0123_4560, 1'b1, 1'b1, 1'b1, 0,
             32'h0123_4560, ESA_DENIED);
      lookup("PO WE clear store", 1'b1, 32'h0123_5560, 1'b1, 1'b1, 1'b1, 3,
             32'b0, ESA_DENIED);
      lookup("PO WE clear load", 1'b1, 32'h0123_5560, 1'b1, 1'b1, 1'b0, 0,
             32'h0123_5560, ESA_DENIED);
      // A protection-only entry never serves a translated lookup, and EA11-14
      // selects the set: the neighbouring region misses.
      lookup("PO entry in page mode", 1'b0, 32'h0009_1010, 1'b0, 1'b1, 1'b0,
             1, 32'b0, ESA_DENIED);
      lookup("PO other region", 1'b0, 32'h0125_4560, 1'b1, 1'b1, 1'b0, 1,
             32'b0, ESA_DENIED);
      // Same set and tag in page mode (EA16-19 = 3): the page entry does not
      // answer a protection-only lookup.
      lookup("page entry in PO", 1'b0, 32'h0006_0010, 1'b1, 1'b1, 1'b0, 1,
             32'b0, ESA_DENIED);
    end else begin
      // Without the 602 the request's PO flag is ignored.
      lookup("PO flag ignored", 1'b0, 32'h0000_5010, 1'b1, 1'b1, 1'b0, 0,
             32'h0004_5010, ESA_DENIED);
    end
  endtask

  // ---- esa resolution at execution ----
  task automatic run_esa;
    logic [31:0] sebr, ser;
    sebr = 32'h0122_0000;  // region 0x0122_0000-0x0123_ffff
    ser = 32'h0000_0800;   // SE20: page 0x0123_4000
    check("esa denied", 32'(esa_permitted(ESA_DENIED, 32'h0123_4000, sebr, ser)), 32'd0);
    check("esa allowed", 32'(esa_permitted(ESA_ALLOWED, 32'h0, sebr, ser)), 32'd1);
    check("esa base in", 32'(esa_permitted(ESA_PO_BASE, 32'h0123_5000, sebr, ser)), 32'd1);
    check("esa base out", 32'(esa_permitted(ESA_PO_BASE, 32'h0124_5000, sebr, ser)), 32'd0);
    check("esa SER set", 32'(esa_permitted(ESA_PO_SER, 32'h0123_4ffc, sebr, ser)), 32'd1);
    check("esa SER clear", 32'(esa_permitted(ESA_PO_SER, 32'h0123_5000, sebr, ser)), 32'd0);
    check("esa SER out", 32'(esa_permitted(ESA_PO_SER, 32'h0125_4000, sebr, ser)), 32'd0);
  endtask

  initial begin
    run_bat();
    run_tlb();
    run_esa();
    $display("PASS tb_mmu_602 variant=%0d: %0d checks", VARIANT, checks);
    $finish;
  end
  initial begin
    #200000;
    $fatal(1, "tb_mmu_602 timeout");
  end
endmodule
`default_nettype wire
