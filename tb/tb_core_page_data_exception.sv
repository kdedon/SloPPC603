// Actual CPU, BAT, committed SR and prefilled DTLB integration. The expected
// physical effects and GPR results are computed independently of the router.
/* verilator lint_off BLKSEQ */
/* verilator lint_off UNUSEDSIGNAL */
module tb_core_page_data_exception;
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
    .ENABLE_PAGE_TRANSLATION(1'b1),
    .ENABLE_PAGE_DATA_EXCEPTIONS(1'b1)) dut (
    .external_irq_i(1'b0),.timer_tick_i(1'b0),.timebase_enable_i(1'b1),.*);

  integer checks=0,cycles=0,phase=0,denied=0,physical_data=0;
  integer held_retire=0,handler_reads=0;
  logic ipending,done,cut_seen;
  logic [31:0] held_ipa;
  integer idelay;
  assign pimem_req_ready_i=rst_ni&&!ipending;
  assign pimem_rsp_valid_i=rst_ni&&ipending&&idelay==0;
  assign pimem_rsp_error_i=1'b0;
  assign pdmem_req_ready_i=1'b1;
  assign pdmem_rsp_valid_i=1'b0;
  assign pdmem_rsp_rdata_i=32'b0;
  assign pdmem_rsp_error_i=1'b0;
  assign retire_ready_i=!(phase<2&&retire_valid_o&&
    retire_o.pc==32'd32&&held_retire<6);
  assign redirect_all_i=1'b1;
  assign redirect_keep_pivot_i=1'b0;
  assign redirect_pivot_i='0;
  assign redirect_target_i=32'h100;

  function automatic logic [31:0] spr(input bit write_form,
    input int regno,input int number);
    return (write_form?32'h7c00_03a6:32'h7c00_02a6) |
      (32'(regno)<<21)|((32'(number)&31)<<16)|
      (((32'(number)>>5)&31)<<11);
  endfunction
  function automatic logic [31:0] program_word(input logic [31:0] pa);
    case(pa)
      0:return 32'h3c60_1000; // addis r3,0,0x1000
      4:return 32'h6063_1234; // EA=0x10001234
      8:return 32'h38c0_0055; // original update destination
      12:return 32'h3c80_4000; // SR.Ks=1
      16:return 32'h6084_1234; // VSID=0x001234
      20:return 32'h7c81_01a4; // mtsr 1,r4
      24:return 32'h38a0_0010; // MSR.DR
      28:return 32'h7ca0_0124; // mtmsr r5
      32:return phase==1?32'h94c3_0000:32'h84c3_0000; // stwu/lwzu
      36:return 32'h3be0_0007; // terminal after handler skips fault
      32'h100:return 32'h3be0_0009; // external-cut target
      32'h300:return spr(0,7,19); // DAR
      32'h304:return spr(0,8,18); // DSISR
      32'h308:return spr(0,9,26); // SRR0
      32'h30c:return spr(0,10,27); // SRR1
      32'h310:return 32'h3929_0004; // skip denied instruction
      32'h314:return spr(1,9,26); // mtspr SRR0,r9
      32'h318:return 32'h4c00_0064; // rfi
      default:return 32'h4800_0000;
    endcase
  endfunction
  assign pimem_rsp_insn_i=program_word(held_ipa);

  task automatic check(input logic okay,input string why);
    checks++;
    if(!okay)$fatal(1,"core page DSI %s phase=%0d cycle=%0d pc=%08x",
      why,phase,cycles,retire_o.pc);
  endtask
  always @(posedge clk_i)begin
    if(!rst_ni)begin
      cycles<=0;ipending<=0;idelay<=0;held_ipa<=0;
      denied<=0;physical_data<=0;held_retire<=0;
      handler_reads<=0;done<=0;cut_seen<=0;
    end else begin
      cycles<=cycles+1;
      check(cycles<1500,"watchdog");
      check(!halted_o&&!pimem_error_o,"unexpected fatal transport");
      if(pimem_req_valid_o&&pimem_req_ready_i)begin
        held_ipa<=pimem_req_addr_o;ipending<=1;idelay<=2;
        check((pimem_req_addr_o<=32'h140)||
              (pimem_req_addr_o>=32'h300&&pimem_req_addr_o<=32'h340),
              $sformatf("instruction fetch escaped real-mode program or DSI handler PA=%08x",pimem_req_addr_o));
      end else if(ipending&&idelay!=0)idelay<=idelay-1;
      else if(pimem_rsp_valid_i&&pimem_rsp_ready_o)ipending<=0;
      if(pdmem_req_valid_o)begin
        physical_data<=physical_data+1;
        check(0,"page-PP denied data request reached physical memory");
      end
      if(retire_valid_o&&retire_o.pc==32'd32&&!retire_ready_i)begin
        held_retire<=held_retire+1;
        check(dut.core.special.dar_q==0&&
              dut.core.special.dsisr_q==0,
              "DAR/DSISR changed before held DSI retirement");
      end
      if(retire_valid_o&&retire_ready_i)begin
        if(retire_o.pc==32'd32)begin
          denied<=denied+1;
          check(phase!=2&&!retire_o.illegal&&
                retire_o.data_fault==DATA_DSI_PROTECTION&&
                !retire_o.gpr_write&&!retire_o.update_write,
                "page PP fault lost typed DSI or wrote update registers");
        end
        if(retire_o.pc==32'h300)begin
          handler_reads<=handler_reads+1;
          check(retire_o.gpr_write&&retire_o.gpr==7&&
                retire_o.value==32'h1000_1234,"handler DAR");
        end
        if(retire_o.pc==32'h304)begin
          handler_reads<=handler_reads+1;
          check(retire_o.gpr_write&&retire_o.gpr==8&&
                retire_o.value==(phase==1?32'h0a00_0000:32'h0800_0000),
                "handler DSISR protection/store");
        end
        if(retire_o.pc==32'h308)begin
          handler_reads<=handler_reads+1;
          check(retire_o.gpr_write&&retire_o.gpr==9&&retire_o.value==32,
                "handler SRR0 faulting PC");
        end
        if(retire_o.pc==32'h30c)begin
          handler_reads<=handler_reads+1;
          check(retire_o.gpr_write&&retire_o.gpr==10&&
                retire_o.value==32'h10,"handler SRR1 old DR state");
        end
        if(retire_o.pc==36)begin
          check(retire_o.gpr_write&&retire_o.gpr==31&&retire_o.value==7,
                "post-RFI skip terminal");
          done<=1;
        end
        if(retire_o.pc==32'h100)begin
          check(phase==2&&retire_o.gpr_write&&
                retire_o.gpr==31&&retire_o.value==9,
                "external cut terminal");
          done<=1;
        end
      end
      if(redirect_accepted_o&&phase==2)cut_seen<=1;
    end
  end
  task automatic reset_case(input int next_phase);
    @(negedge clk_i);rst_ni=0;phase=next_phase;
    bat_write_valid_i=0;bat_write_rsp_ready_i=0;
    tlb_mgmt_req_valid_i=0;tlb_mgmt_rsp_ready_i=0;
    start_valid_i=0;start_ir_i=0;start_dr_i=0;start_pr_i=0;
    redirect_valid_i=0;
    repeat(4)@(negedge clk_i);rst_ni=1;
  endtask
  task automatic preload(input logic [1:0] pp);
    @(negedge clk_i);
    tlb_mgmt_req_kind_i=2'd1;tlb_mgmt_req_bank_i=1;
    tlb_mgmt_req_ea_i=32'h1000_1234;tlb_mgmt_req_vsid_i=24'h001234;
    tlb_mgmt_req_pr_i=0;tlb_mgmt_req_way_i=0;
    tlb_mgmt_req_rpn_i=20'h80000;tlb_mgmt_req_c_i=1;
    tlb_mgmt_req_wimg_i=4'h2;tlb_mgmt_req_pp_i=pp;
    tlb_mgmt_req_valid_i=1;
    #1;check(tlb_mgmt_req_ready_o,"TLB prefill not ready");
    @(posedge clk_i);@(negedge clk_i);tlb_mgmt_req_valid_i=0;
    check(tlb_mgmt_rsp_valid_o&&tlb_mgmt_rsp_kind_o==2'd1&&
          !tlb_mgmt_rsp_privileged_o&&!tlb_mgmt_rsp_refill_rejected_o&&
          !tlb_mgmt_rsp_unsupported_o&&!tlb_mgmt_rsp_invalid_input_o,
          "TLB prefill rejected");
    tlb_mgmt_rsp_ready_i=1;
    @(posedge clk_i);@(negedge clk_i);tlb_mgmt_rsp_ready_i=0;
  endtask
  task automatic start_core;
    @(negedge clk_i);start_valid_i=1;
    #1;check(start_ready_o,"start not ready");
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
    reset_case(0);preload(2'b00);start_core();
    wait(done);@(negedge clk_i);
    check(denied==1&&physical_data==0&&held_retire>=6&&
          handler_reads==4&&page_protection_o&&
          dut.core.regfile.gpr[3]==32'h1000_1234&&
          dut.core.regfile.gpr[6]==32'h55,
          "load update denial mutated destination/base or missed handler");
    reset_case(1);preload(2'b11);start_core();
    wait(done);@(negedge clk_i);
    check(denied==1&&physical_data==0&&held_retire>=6&&
          handler_reads==4&&page_protection_o&&
          dut.core.regfile.gpr[3]==32'h1000_1234&&
          dut.core.regfile.gpr[6]==32'h55,
          "store update denial changed memory/base or missed handler");
    reset_case(2);preload(2'b00);start_core();
    wait(dut.router.dmem_rsp_valid_o);
    @(negedge clk_i);redirect_valid_i=1;
    #1;check(redirect_accepted_o,"typed page response cut rejected");
    @(posedge clk_i);@(negedge clk_i);redirect_valid_i=0;
    wait(done);@(negedge clk_i);
    check(cut_seen&&denied==0&&handler_reads==0&&physical_data==0&&
          dut.core.special.dar_q==0&&dut.core.special.dsisr_q==0&&
          dut.core.regfile.gpr[3]==32'h1000_1234&&
          dut.core.regfile.gpr[6]==32'h55,
          "cancelled page denial installed DSI or mutated registers");
    $display("PASS actual-core page DSI checks=%0d",checks);$finish;
  end
endmodule
/* verilator lint_on UNUSEDSIGNAL */
/* verilator lint_on BLKSEQ */
