// Actual CPU, BAT, committed SR and prefilled DTLB integration. The expected
// physical effects and GPR results are computed independently of the router.
/* verilator lint_off BLKSEQ */
/* verilator lint_off UNUSEDSIGNAL */
module tb_core_page_translation;
  import ppc_pkg::*;
  logic clk_i=0, rst_ni=0;
  always #5 clk_i=~clk_i;
  logic bat_write_valid_i,bat_write_ready_o,bat_write_rsp_valid_o,bat_write_rsp_ready_i;
  logic [9:0] bat_write_spr_i;
  logic [31:0] bat_write_data_i;
  logic bat_write_rsp_rejected_o,bat_write_rsp_unsupported_o;
  logic bat_write_rsp_config_error_o,bat_write_rsp_overlap_o;
  logic [3:0] bat_write_rsp_invalid_entry_o;
  logic tlb_mgmt_req_valid_i,tlb_mgmt_req_ready_o,tlb_mgmt_req_bank_i;
  logic [1:0] tlb_mgmt_req_kind_i,tlb_mgmt_req_pp_i;
  logic [31:0] tlb_mgmt_req_ea_i;
  logic [23:0] tlb_mgmt_req_vsid_i;
  logic tlb_mgmt_req_pr_i,tlb_mgmt_req_way_i,tlb_mgmt_req_c_i;
  logic [19:0] tlb_mgmt_req_rpn_i;
  logic [3:0] tlb_mgmt_req_wimg_i;
  logic tlb_mgmt_rsp_valid_o,tlb_mgmt_rsp_ready_i,tlb_mgmt_rsp_bank_o;
  logic [1:0] tlb_mgmt_rsp_kind_o;
  logic [31:0] tlb_mgmt_rsp_ea_o;
  logic tlb_mgmt_rsp_privileged_o,tlb_mgmt_rsp_refill_rejected_o;
  logic tlb_mgmt_rsp_unsupported_o,tlb_mgmt_rsp_invalid_input_o,tlb_mgmt_idle_o;
  logic page_fault_o,page_miss_o,page_protection_o,page_no_execute_o;
  logic page_guarded_o,page_direct_store_o,page_needs_changed_o,page_config_o;
  logic start_valid_i,start_ready_o,start_ir_i,start_dr_i,start_pr_i;
  logic running_o,context_ir_o,context_dr_o,context_pr_o;
  logic pimem_req_valid_o,pimem_req_ready_i,pimem_rsp_valid_i,pimem_rsp_ready_o;
  logic [31:0] pimem_req_addr_o,pimem_rsp_insn_i;
  logic [3:0] pimem_req_wimg_o;
  logic pimem_rsp_error_i;
  logic pdmem_req_valid_o,pdmem_req_ready_i,pdmem_req_write_o;
  logic [31:0] pdmem_req_addr_o,pdmem_req_wdata_o,pdmem_rsp_rdata_i;
  logic [3:0] pdmem_req_wstrb_o,pdmem_req_wimg_o;
  logic pdmem_rsp_valid_i,pdmem_rsp_ready_o,pdmem_rsp_error_i;
  logic retire_valid_o,retire_ready_i,halted_o;
  retire_packet_t retire_o;
  logic redirect_valid_i,redirect_all_i,redirect_keep_pivot_i,redirect_accepted_o;
  completion_tag_t redirect_pivot_i;
  logic [31:0] redirect_target_i;
  logic translation_fault_o,fault_instruction_o,fault_write_o;
  logic [31:0] fault_ea_o;
  logic fault_miss_o,fault_protection_o,fault_guarded_o,fault_config_o;
  logic fault_invalid_input_o,pimem_error_o,busy_o;
  logic [3:0] fault_invalid_entry_o;
  logic interrupt_taken_o,decrementer_taken_o;
  logic [31:0] interrupt_pc_o,decrementer_pc_o;

  ppc_core_bat #(.RESET_PC(32'b0),.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1),.ENABLE_SEGMENT_REGISTERS(1'b1),
    .ENABLE_PAGE_TRANSLATION(1'b1)) dut (
    .external_irq_i(1'b0),.timer_tick_i(1'b0),.timebase_enable_i(1'b1),.*);

  integer checks=0,cycles=0,phase=0,loads=0,physical_reads=0;
  integer physical_writes=0,segment_commits=0,old_fetch_drains=0;
  logic ipending,dpending,done,load_killed;
  logic [31:0] held_ipa,held_dpa;
  integer idelay,ddelay;
  assign pimem_req_ready_i=rst_ni && !ipending;
  assign pimem_rsp_valid_i=rst_ni && ipending && idelay==0;
  assign pimem_rsp_error_i=0;
  assign pdmem_req_ready_i=rst_ni && !dpending;
  assign pdmem_rsp_valid_i=rst_ni && dpending && ddelay==0;
  assign pdmem_rsp_error_i=0;
  assign retire_ready_i=1'b1;
  assign redirect_all_i=1'b1;
  assign redirect_keep_pivot_i=1'b0;
  assign redirect_pivot_i='0;
  assign redirect_target_i=32'd64;

  function automatic logic [31:0] srinsn(input int xo,input int rt,input int sr);
    return (32'd31<<26)|(32'(rt)<<21)|(32'(sr)<<16)|(32'(xo)<<1);
  endfunction
  function automatic logic [31:0] addi(input int rt,input int ra,input int imm);
    return 32'h3800_0000|(32'(rt)<<21)|(32'(ra)<<16)|(32'(imm)&32'hffff);
  endfunction
  function automatic logic [31:0] program_word(input logic [31:0] pa);
    logic [31:0] ea;
    ea=(pa>=32'h4000_0000)?pa-32'h4000_0000:pa;
    case(ea)
      0:return 32'h3c60_1000;                // addis r3,0,0x1000
      4:return addi(4,0,'h1234);            // VSID A
      8:return srinsn(210,4,1);            // mtsr 1,r4
      12:return addi(5,0,'h30);             // MSR.IR|DR
      16:return 32'h7ca0_0124;              // mtmsr r5
      20:return 32'h4c00_012c;              // isync
      24:return 32'h80c3_0000;              // lwz r6,0(r3)
      28:return addi(4,0,'h2345);            // VSID B
      32:return srinsn(210,4,1);            // mtsr 1,r4
      36:return 32'h4c00_012c;
      40:return 32'h80e3_0000;              // lwz r7,0(r3)
      44:return addi(4,0,'h1234);
      48:return srinsn(210,4,1);
      52:return 32'h4c00_012c;
      56:return 32'h8103_0000;              // lwz r8,0(r3)
      60:return addi(31,0,7);
      64:return addi(31,0,9);               // recovery target
      default:return 32'h6000_0000;         // ori r0,r0,0
    endcase
  endfunction
  assign pimem_rsp_insn_i=program_word(held_ipa);
  assign pdmem_rsp_rdata_i=(held_dpa==32'h8000_0000)?32'h1111_1111:
                               (held_dpa==32'h9000_0000)?32'h2222_2222:32'hdead_beef;

  task automatic check(input logic condition,input string message_text);
    checks++;
    if(!condition)$fatal(1,"core page check %0d: %s phase=%0d cycle=%0d pc=%08x",
      checks,message_text,phase,cycles,retire_o.pc);
  endtask
  always @(posedge clk_i) begin
    if(!rst_ni)begin
      cycles<=0;ipending<=0;dpending<=0;idelay<=0;ddelay<=0;
      held_ipa<=0;held_dpa<=0;loads<=0;physical_reads<=0;
      physical_writes<=0;segment_commits<=0;old_fetch_drains<=0;
      done<=0;load_killed<=0;
    end else begin
      cycles<=cycles+1;
      check(cycles<3000,"watchdog");
      check(!page_fault_o && !translation_fault_o && !pimem_error_o,
        "unexpected page/BAT diagnostic");
      if(pimem_req_valid_o && pimem_req_ready_i)begin
        check((pimem_req_addr_o<32'h100 && pimem_req_wimg_o==4'b0001) ||
          (pimem_req_addr_o>=32'h4000_0000 &&
           pimem_req_addr_o<32'h4000_0100 && pimem_req_wimg_o==4'b0000),
          "instruction PA or WIMG escaped real/BAT code region");
        held_ipa<=pimem_req_addr_o;ipending<=1;idelay<=4;
      end else if(ipending && idelay!=0) idelay<=idelay-1;
      else if(pimem_rsp_valid_i && pimem_rsp_ready_o)begin
        ipending<=0;
        if(dut.core.frontend_fence)old_fetch_drains<=old_fetch_drains+1;
      end
      if(pdmem_req_valid_o && pdmem_req_ready_i)begin
        check(!pdmem_req_write_o,"page test issued physical store");
        check((pdmem_req_addr_o==32'h8000_0000 && pdmem_req_wimg_o==4'b0100) ||
          (pdmem_req_addr_o==32'h9000_0000 && pdmem_req_wimg_o==4'b0010),
          "DTLB PA/WIMG mismatch");
        held_dpa<=pdmem_req_addr_o;dpending<=1;
        ddelay<=phase==1?24:5;
        physical_reads<=physical_reads+1;
      end else if(dpending && ddelay!=0) ddelay<=ddelay-1;
      else if(pdmem_rsp_valid_i && pdmem_rsp_ready_o)dpending<=0;
      if(dut.segment_csr_commit)begin
        segment_commits<=segment_commits+1;
        check(!ipending && !dpending,"SR committed before old physical obligation drained");
      end
      if(retire_valid_o && retire_ready_i)begin
        check(!retire_o.illegal,"unexpected CPU diagnostic retirement");
        case(retire_o.pc)
          24:begin
            loads<=loads+1;
            check(phase==0 && retire_o.gpr_write && retire_o.gpr==6 &&
              retire_o.value==32'h1111_1111,"VSID A load result");
          end
          40:begin
            loads<=loads+1;
            check(phase==0 && retire_o.gpr_write && retire_o.gpr==7 &&
              retire_o.value==32'h2222_2222,"VSID B load result");
          end
          56:begin
            loads<=loads+1;
            check(phase==0 && retire_o.gpr_write && retire_o.gpr==8 &&
              retire_o.value==32'h1111_1111,"restored VSID A load result");
          end
          60:if(phase==0)begin
            check(retire_o.gpr_write && retire_o.gpr==31 && retire_o.value==7,
              "normal terminal result");done<=1;
          end
          64:if(phase==1)begin
            check(retire_o.gpr_write && retire_o.gpr==31 && retire_o.value==9,
              "recovery terminal result");done<=1;
          end
          default: ;
        endcase
      end
      if(redirect_accepted_o && phase==1)load_killed<=1;
    end
  end

  task automatic reset_case(input integer next_phase);
    @(negedge clk_i);rst_ni=0;phase=next_phase;
    bat_write_valid_i=0;bat_write_rsp_ready_i=0;
    tlb_mgmt_req_valid_i=0;tlb_mgmt_rsp_ready_i=0;
    start_valid_i=0;start_ir_i=0;start_dr_i=0;start_pr_i=0;
    redirect_valid_i=0;
    repeat(4)@(negedge clk_i);rst_ni=1;
  endtask
  task automatic setup_bat;
    @(negedge clk_i);bat_write_spr_i=10'd529;
    bat_write_data_i=32'h4000_0002;bat_write_valid_i=1;
    #1;check(bat_write_ready_o,"IBATL setup not ready");
    @(posedge clk_i);@(negedge clk_i);bat_write_valid_i=0;
    check(bat_write_rsp_valid_o && !bat_write_rsp_rejected_o,
      "IBATL setup rejected");
    bat_write_rsp_ready_i=1;
    @(posedge clk_i);@(negedge clk_i);bat_write_rsp_ready_i=0;
    bat_write_spr_i=10'd528;bat_write_data_i=32'h0000_0003;
    bat_write_valid_i=1;
    #1;check(bat_write_ready_o,"IBATU setup not ready");
    @(posedge clk_i);@(negedge clk_i);bat_write_valid_i=0;
    check(bat_write_rsp_valid_o && !bat_write_rsp_rejected_o,
      "IBATU setup rejected");
    bat_write_rsp_ready_i=1;
    @(posedge clk_i);@(negedge clk_i);bat_write_rsp_ready_i=0;
  endtask
  task automatic preload(input logic [23:0] vsid,input logic way,
    input logic [19:0] rpn,input logic [3:0] wimg);
    @(negedge clk_i);
    tlb_mgmt_req_kind_i=2'd1;tlb_mgmt_req_bank_i=1;
    tlb_mgmt_req_ea_i=32'h1000_0000;tlb_mgmt_req_vsid_i=vsid;
    tlb_mgmt_req_pr_i=0;tlb_mgmt_req_way_i=way;
    tlb_mgmt_req_rpn_i=rpn;tlb_mgmt_req_c_i=1;
    tlb_mgmt_req_wimg_i=wimg;tlb_mgmt_req_pp_i=2'b10;
    tlb_mgmt_req_valid_i=1;
    #1;check(tlb_mgmt_req_ready_o,"TLB preload not ready");
    @(posedge clk_i);@(negedge clk_i);tlb_mgmt_req_valid_i=0;
    check(tlb_mgmt_rsp_valid_o && tlb_mgmt_rsp_kind_o==2'd1 &&
      tlb_mgmt_rsp_bank_o && tlb_mgmt_rsp_ea_o==32'h1000_0000 &&
      !tlb_mgmt_rsp_privileged_o && !tlb_mgmt_rsp_refill_rejected_o &&
      !tlb_mgmt_rsp_unsupported_o && !tlb_mgmt_rsp_invalid_input_o,
      "TLB preload response rejected or wrong echo");
    tlb_mgmt_rsp_ready_i=1;
    @(posedge clk_i);@(negedge clk_i);tlb_mgmt_rsp_ready_i=0;
  endtask
  task automatic start_core;
    @(negedge clk_i);start_valid_i=1;
    #1;check(start_ready_o,"start not ready after preload");
    @(posedge clk_i);@(negedge clk_i);start_valid_i=0;
    check(running_o,"wrapper did not start");
  endtask
  initial begin
    bat_write_valid_i=0;bat_write_spr_i=0;bat_write_data_i=0;
    bat_write_rsp_ready_i=0;tlb_mgmt_req_valid_i=0;
    tlb_mgmt_req_kind_i=0;tlb_mgmt_req_bank_i=0;
    tlb_mgmt_req_ea_i=0;tlb_mgmt_req_vsid_i=0;tlb_mgmt_req_pr_i=0;
    tlb_mgmt_req_way_i=0;tlb_mgmt_req_rpn_i=0;tlb_mgmt_req_c_i=0;
    tlb_mgmt_req_wimg_i=0;tlb_mgmt_req_pp_i=0;
    tlb_mgmt_rsp_ready_i=0;start_valid_i=0;start_ir_i=0;
    start_dr_i=0;start_pr_i=0;redirect_valid_i=0;
    reset_case(0);setup_bat();
    preload(24'h001234,0,20'h80000,4'b0100);
    preload(24'h002345,1,20'h90000,4'b0010);
    start_core();wait(done);@(negedge clk_i);
    check(loads==3 && physical_reads==3 && physical_writes==0 &&
      segment_commits==3 && old_fetch_drains>0 &&
      dut.core.regfile.gpr[6]==32'h1111_1111 &&
      dut.core.regfile.gpr[7]==32'h2222_2222 &&
      dut.core.regfile.gpr[8]==32'h1111_1111,
      "A-B-A retained TLB mapping or physical effects");
    reset_case(1);setup_bat();
    preload(24'h001234,0,20'h80000,4'b0100);
    preload(24'h002345,1,20'h90000,4'b0010);
    start_core();
    wait(dpending && held_dpa==32'h8000_0000);
    @(negedge clk_i);redirect_valid_i=1;
    #1;check(redirect_accepted_o,"pending page load cut rejected");
    @(posedge clk_i);@(negedge clk_i);redirect_valid_i=0;
    wait(done);@(negedge clk_i);
    check(load_killed && loads==0 && physical_reads==1 && physical_writes==0 &&
      dut.core.regfile.gpr[6]==0 && segment_commits==1,
      "canceled page load changed GPR or failed to drain");
    $display("PASS actual-core page integration: %0d checks",checks);$finish;
  end
endmodule
