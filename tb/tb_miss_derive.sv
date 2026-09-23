// Fixed PTEG address anchors from 32-bit PEM hash/SDR1 equations.
/* verilator lint_off BLKSEQ */
module tb_miss_derive;
  logic [31:0] ea_i,sr_i,sdr1_i;
  logic valid_o;
  logic [31:0] miss_page_o,compare_o,hash1_o,hash2_o;
  int checks=0;
  ppc_miss_derive dut (.*);
  task automatic check(input logic good,input string why);
    checks++;
    if(!good)$fatal(1,"miss derive %s EA=%08x SR=%08x SDR1=%08x check=%0d",
      why,ea_i,sr_i,sdr1_i,checks);
  endtask
  task automatic expect_vector(input logic [31:0] ea,sr,sdr1,
      input logic [31:0] page,cmp,primary,secondary);
    ea_i=ea;sr_i=sr;sdr1_i=sdr1;#1;
    check(valid_o,"valid literal vector rejected");
    check(miss_page_o==page&&compare_o==cmp&&
          hash1_o==primary&&hash2_o==secondary,
          $sformatf("literal mismatch page=%08x/%08x cmp=%08x/%08x hash=%08x/%08x %08x/%08x",
            miss_page_o,page,compare_o,cmp,hash1_o,primary,hash2_o,secondary));
    check(hash1_o[5:0]==0&&hash2_o[5:0]==0,
          "PTEG address not 64-byte aligned");
  endtask
  task automatic expect_invalid(input logic [31:0] ea,sr,sdr1);
    ea_i=ea;sr_i=sr;sdr1_i=sdr1;#1;
    check(!valid_o&&{miss_page_o,compare_o,hash1_o,hash2_o}==128'b0,
          "malformed descriptor leaked partial derived state");
  endtask
  initial begin
    // PEM Figures 7-28/30/32: 19-bit VSID/page XOR, complement for
    // secondary, ten low hash bits and mask-selected high bits in PTEG PA.
    expect_vector(32'h1000_1234,32'h0012_3456,32'h1000_0000,
                  32'h1000_1234,32'h891a_2b00,32'h1000_15c0,32'h1000_ea00);
    expect_vector(32'habcd_ef12,32'h00fe_dcba,32'h2000_0007,
                  32'habcd_ef12,32'hff6e_5d2f,32'h2000_1900,32'h2007_e6c0);
    expect_vector(32'hffee_dccc,32'h0000_0001,32'h4000_01ff,
                  32'hffee_dccc,32'h8000_00bf,32'h403f_bb00,32'h41c0_44c0);
    expect_vector(32'h0000_0000,32'h00ff_ffff,32'h1234_0003,
                  32'h0000_0000,32'hffff_ff80,32'h1237_ffc0,32'h1234_0000);
    expect_vector(32'hdead_beef,32'h0065_4321,32'hfff0_000f,
                  32'hdead_beef,32'hb2a1_90ba,32'hfffa_7e80,32'hfff5_8140);
    // IMISS/DMISS retain the byte offset although compare and hash do not.
    ea_i=32'h1000_1abc;sr_i=32'h0012_3456;sdr1_i=32'h1000_0000;#1;
    check(valid_o && miss_page_o==32'h1000_1abc &&
          compare_o==32'h891a_2b00 && hash1_o==32'h1000_15c0,
          "nonzero byte offset was discarded or changed page derivation");
    // SR.N is not an input-validity rule; SR.T is.
    ea_i=32'h1000_1234;sr_i=32'h1012_3456;sdr1_i=32'h1000_0000;#1;
    check(valid_o&&compare_o==32'h891a_2b00&&
          hash1_o==32'h1000_15c0,"SR.N incorrectly changed derivation");
    expect_invalid(32'h1000_1234,32'h8012_3456,32'h1000_0000);
    expect_invalid(32'h1000_1234,32'h0012_3456,32'h1000_0200);
    expect_invalid(32'h1000_1234,32'h0012_3456,32'h1001_0001);
    expect_invalid(32'h1000_1234,32'h0012_3456,32'h1000_0005);
    for(int mask=0;mask<512;mask++)begin
      bit contiguous;
      contiguous=((mask&(mask+1))==0);
      ea_i=32'h55aa_ba98;sr_i=32'h00c0_ffee;
      sdr1_i={16'h0000,7'b0,9'(mask)};#1;
      check(valid_o==contiguous,
            "HTABMASK contiguous-low-ones validity");
      if(!contiguous)
        check({miss_page_o,compare_o,hash1_o,hash2_o}==128'b0,
              "invalid mask leaked derivation outputs");
    end
    $display("PASS miss derivation checks=%0d",checks);
    $finish;
  end
endmodule
/* verilator lint_on BLKSEQ */
