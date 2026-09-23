// Accepted translated I-cache refill, external IRQ fence, and RFI resume.
/* verilator lint_off BLKSEQ */
module tb_core_bat_cached_bus60x_irq;
  import ppc_pkg::*;
  logic clk=0,rst_n=0;
  always #5 clk=~clk;
  logic start_valid=0,start_ready,running,cir,cdr,cpr;
  logic tv,tr,retire_enable=1,halted,ifetch_error,protocol_error,bus_busy;
  logic pimem_error,irq=0,taken;
  logic [31:0] irq_pc;
  retire_packet_t retired;
  logic br_n,bg_n,abb_n,abb_oe,ts_n,ts_oe,tbst_n,ci_n,wt_n,gbl_n,addr_oe;
  logic [31:0] bus_a;
  logic [4:0] tt;
  logic [2:0] tsiz;
  logic [1:0] tc,cse;
  logic aack_n,artry_n,dbg_n,dbb_n,dbb_oe,data_oe,ta_n,drtry_n,tea_n;
  logic [63:0] data_in;
  logic cache_busy,cache_enabled,cache_hit;
  int cycles=0,checks=0,retires=0,alias_lines=0,irq_count=0;
  int old_beats=0,handler_retires=0,rfi_retires=0,target_retires=0,alias_hits=0;
  bit held_refill=0,release_refill=0,refill_drained=0;
  logic [63:0] held_dw[0:3];
  localparam logic [31:0] TARGET=32'h10000100;
  localparam logic [31:0] TARGET_INSN=32'h39000009; // addi r8,r0,9
  localparam logic [31:0] RFI=32'h4c000064;

  function automatic logic [31:0] spr(input bit wr,input int rt,input int number);
    return (wr?32'h7c0003a6:32'h7c0002a6)|(32'(rt)<<21)|
      ((32'(number)&31)<<16)|((32'(number)>>5)<<11);
  endfunction
  task automatic check(input bit ok,input string why);
    checks++;
    if(!ok)$fatal(1,"%s cycle=%0d pc=%08x bus=%08x irq=%0d",
      why,cycles,retired.pc,bus_a,irq_count);
  endtask
  task automatic put_word(input int address,input logic [31:0] value);
    for(int k=0;k<4;k++)target.mem[address+k]=value[31-8*k -:8];
  endtask
  function automatic logic [63:0] line_dw(input logic [31:0] base,input int slot);
    logic [63:0] result;
    result=0;
    for(int lane=0;lane<8;lane++)
      result[63-8*lane -:8]=target.mem[int'(base)+slot*8+lane];
    return result;
  endfunction

  /* verilator lint_off PINCONNECTEMPTY */
  ppc_core_bat_cached_bus60x #(.RESET_PC(32'b0),
    .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),.ENABLE_LIVE_CONTEXT(1'b1),
    .ENABLE_RUNTIME_BAT(1'b1),.ENABLE_EXTERNAL_INTERRUPTS(1'b1)) dut(
    .clk_i(clk),.rst_ni(rst_n),
    .external_irq_i(irq),.interrupt_taken_o(taken),.interrupt_pc_o(irq_pc),
    .timer_tick_i(1'b0),.timebase_enable_i(1'b0),
    .decrementer_taken_o(),.decrementer_pc_o(),
    .bat_write_valid_i(1'b0),.bat_write_ready_o(),
    .bat_write_spr_i('0),.bat_write_data_i('0),
    .bat_write_rsp_valid_o(),.bat_write_rsp_ready_i(1'b0),
    .bat_write_rsp_rejected_o(),.bat_write_rsp_unsupported_o(),
    .bat_write_rsp_config_error_o(),.bat_write_rsp_overlap_o(),
    .bat_write_rsp_invalid_entry_o(),
    .tlb_mgmt_req_valid_i(1'b0),.tlb_mgmt_req_ready_o(),
    .tlb_mgmt_req_kind_i('0),.tlb_mgmt_req_bank_i('0),
    .tlb_mgmt_req_ea_i('0),.tlb_mgmt_req_vsid_i('0),
    .tlb_mgmt_req_pr_i('0),.tlb_mgmt_req_way_i('0),
    .tlb_mgmt_req_rpn_i('0),.tlb_mgmt_req_c_i('0),
    .tlb_mgmt_req_wimg_i('0),.tlb_mgmt_req_pp_i('0),
    .tlb_mgmt_rsp_valid_o(),.tlb_mgmt_rsp_ready_i(1'b0),
    .tlb_mgmt_rsp_kind_o(),.tlb_mgmt_rsp_bank_o(),.tlb_mgmt_rsp_ea_o(),
    .tlb_mgmt_rsp_privileged_o(),.tlb_mgmt_rsp_refill_rejected_o(),
    .tlb_mgmt_rsp_unsupported_o(),.tlb_mgmt_rsp_invalid_input_o(),
    .tlb_mgmt_idle_o(),.page_fault_o(),.page_miss_o(),
    .page_protection_o(),.page_no_execute_o(),.page_guarded_o(),
    .page_direct_store_o(),.page_needs_changed_o(),.page_config_o(),
    .start_valid_i(start_valid),.start_ready_o(start_ready),
    .start_ir_i(1'b0),.start_dr_i(1'b0),.start_pr_i(1'b0),
    .running_o(running),.context_ir_o(cir),.context_dr_o(cdr),
    .context_pr_o(cpr),
    .retire_valid_o(tv),.retire_ready_i(tr),.retire_o(retired),
    .halted_o(halted),.redirect_valid_i(1'b0),.redirect_all_i(1'b0),
    .redirect_keep_pivot_i(1'b0),.redirect_pivot_i('0),
    .redirect_target_i('0),.redirect_accepted_o(),
    .translation_fault_o(),.fault_instruction_o(),.fault_write_o(),
    .fault_ea_o(),.fault_miss_o(),.fault_protection_o(),
    .fault_guarded_o(),.fault_config_o(),.fault_invalid_input_o(),
    .fault_invalid_entry_o(),.pimem_error_o(pimem_error),
    .busy_o(),.ifetch_error_o(ifetch_error),
    .bus_protocol_error_o(protocol_error),.bus_busy_o(bus_busy),
    .icache_hit_o(cache_hit),.icache_miss_o(),.icache_busy_o(cache_busy),
    .maintenance_valid_i(1'b0),.maintenance_ready_o(),
    .maintenance_invalidate_i(1'b0),.maintenance_cache_enable_i(1'b1),
    .maintenance_done_valid_o(),.maintenance_done_ready_i(1'b0),
    .cache_enabled_o(cache_enabled),.maintenance_busy_o(),
    .br_n_o(br_n),.bg_n_i(bg_n),.abb_n_i(1'b1),
    .abb_n_o(abb_n),.abb_oe_o(abb_oe),.ts_n_o(ts_n),.ts_oe_o(ts_oe),
    .a_o(bus_a),.tt_o(tt),.tbst_n_o(tbst_n),.tsiz_o(tsiz),
    .tc_o(tc),.ci_n_o(ci_n),.wt_n_o(wt_n),.gbl_n_o(gbl_n),
    .cse_o(cse),.addr_oe_o(addr_oe),.aack_n_i(aack_n),
    .artry_n_i(artry_n),.dbg_n_i(dbg_n),.dbb_n_i(1'b1),
    .dbb_n_o(dbb_n),.dbb_oe_o(dbb_oe),
    .d_i(data_in),.d_o(),.d_oe_o(data_oe),
    .ta_n_i(ta_n),.drtry_n_i(drtry_n),.tea_n_i(tea_n)
  );
  /* verilator lint_on PINCONNECTEMPTY */
  bus60x_target_bfm #(.BASE_ADDR(32'b0),.MEM_BYTES(8192)) target(
    .clk_i(clk),.br_n_i(br_n),.abb_n_i(abb_n),.abb_oe_i(abb_oe),
    .ts_n_i(ts_n),.ts_oe_i(ts_oe),.a_i(bus_a),
    .dbb_n_i(dbb_n),.dbb_oe_i(dbb_oe),.bg_n_o(bg_n),
    .aack_n_o(aack_n),.artry_n_o(artry_n),.dbg_n_o(dbg_n),
    .d_o(data_in),.ta_n_o(ta_n),.drtry_n_o(drtry_n),.tea_n_o(tea_n)
  );
  assign tr=rst_n&&retire_enable;

  always @(posedge clk)begin
    cycles++;
    if(cycles>6000)$fatal(1,"cached BAT IRQ watchdog");
    if(rst_n)begin
      check(!protocol_error&&!pimem_error&&!ifetch_error&&!halted,
        "unexpected transport or core diagnostic");
      if(addr_oe&&ts_oe&&!ts_n)begin
        check(abb_oe&&!abb_n&&bus_busy&&bus_a<8192&&wt_n&&gbl_n&&cse==0&&!data_oe,
          "bus ownership and attributes");
        if(!tbst_n)begin
          check(tt==5'b01110&&tsiz==2&&tc==2&&ci_n,
            "cacheable translated line shape");
          if((bus_a&32'hffffffe0)==32'h100)alias_lines++;
        end else check(tt==5'b01010&&tsiz==4&&tc==2&&!ci_n,
                       "real-mode scalar fetch shape");
      end
      if(cache_hit&&rfi_retires>0)begin
        check((dut.imem_req_addr&32'hffffffe0)==32'h100,
          "post-RFI cache hit belongs to translated alias line");
        alias_hits++;
      end
      if(taken)begin
        check(irq&&irq_count==0&&refill_drained&&old_beats==4&&
              irq_pc==TARGET&&!tv,"precise IRQ after old refill drain");
        irq_count++;
        irq<=0;
      end else check(irq_pc==0,"IRQ PC outside acceptance pulse");
      if(tv&&tr)begin
        check(^retired !== 1'bx&&!retired.illegal&&
              retired.fetch_fault==FETCH_OK,"known legal retirement");
        retires++;
        if(retired.pc==32'h500)begin
          check(irq_count==1&&!cir&&!cdr&&!cpr&&retired.insn==spr(0,20,26)&&
                retired.gpr_write&&retired.gpr==20&&retired.value==TARGET,
                "handler observes exact SRR0");
          handler_retires++;
        end
        if(retired.pc==32'h504)begin
          check(irq_count==1&&!cir&&!cdr&&!cpr&&retired.insn==spr(0,21,27)&&
                retired.gpr_write&&retired.gpr==21&&retired.value==32'h8020,
                "handler observes old EE/IR in SRR1");
          handler_retires++;
        end
        if(retired.pc==32'h508)begin
          check(irq_count==1&&!cir&&!cdr&&!cpr&&retired.insn==RFI,"handler RFI identity");
          rfi_retires++;
        end
        if(retired.pc==TARGET)begin
          check(irq_count==1&&rfi_retires==1&&retired.insn==TARGET_INSN&&
                retired.gpr_write&&retired.gpr==8&&retired.value==9,
                "translated target retired only after RFI");
          target_retires++;
        end
      end
    end
  end

  // Snapshot the accepted line before asserting IRQ; preserve the old response
  // until the frontend fence has had time to become visible at the bus boundary.
  initial begin : responder
    forever begin
      logic [31:0] base;
      int critical;
      target.grant_address(1,1,1'b0,1'b0);
      target.grant_data(1);
      if(!tbst_n)begin
        base=bus_a&32'hffffffe0;
        critical=int'(bus_a[4:3]);
        if(base==32'h100&&!held_refill)begin
          for(int beat=0;beat<4;beat++)
            held_dw[beat]=line_dw(base,(critical+beat)%4);
          held_refill=1;
          wait(release_refill);
          for(int beat=0;beat<4;beat++)begin
            target.sample_ta(held_dw[beat]);
            old_beats++;
          end
          refill_drained=1;
        end else begin
          for(int beat=0;beat<4;beat++)
            target.sample_ta(line_dw(base,(critical+beat)%4));
        end
      end else target.acknowledge_normal_read(1);
    end
  end

  initial begin
    retire_packet_t stalled;
    // Real-mode bootstrap installs identity and alias WIMG=0 IBATs, enables
    // EE|IR through MTMSR, then branches to EA 0x10000100 via CTR.
    put_word(0,32'h38600002); put_word(4,spr(1,3,529));
    put_word(8,spr(1,3,528)); put_word(12,spr(1,3,531));
    put_word(16,32'h3c801000); put_word(20,32'h60840002);
    put_word(24,spr(1,4,530)); put_word(28,32'h60058020);
    put_word(32,32'h7ca00124); put_word(36,32'h4c00012c);
    put_word(40,32'h3ce01000); put_word(44,32'h60e70100);
    put_word(48,spr(1,7,9)); put_word(52,32'h4e800420);
    put_word('h100,TARGET_INSN); put_word('h104,32'h48000000);
    put_word('h500,spr(0,20,26));put_word('h504,spr(0,21,27));
    put_word('h508,RFI);
    repeat(4)@(posedge clk);
    @(negedge clk);rst_n=1;start_valid=1;
    do @(posedge clk);while(!start_ready);
    @(negedge clk);start_valid=0;
    check(running&&!cir&&!cdr&&!cpr&&cache_enabled,"real-mode startup");
    for(int i=0;i<3000&&!held_refill;i++)@(negedge clk);
    check(held_refill&&alias_lines==1&&cache_busy,"accepted translated line");
    retire_enable=0;
    irq=1;
    repeat(8)begin
      @(posedge clk);#1;
      check(!taken&&irq_count==0&&old_beats==0&&target_retires==0,
        "IRQ waited for accepted old response");
    end
    @(negedge clk);release_refill=1;
    for(int i=0;i<300&&!refill_drained;i++)@(negedge clk);
    check(refill_drained&&old_beats==4,"old line response drained");
    for(int i=0;i<300&&irq_count==0;i++)@(negedge clk);
    check(irq_count==1&&target_retires==0,"single precise interrupt");
    for(int i=0;i<200&&!tv;i++)@(negedge clk);
    check(tv&&retired.pc==32'h500&&retired.insn==spr(0,20,26),
      "handler retirement offered under backpressure");
    stalled=retired;
    repeat(4)begin
      @(posedge clk);#1;
      check(tv&&!tr&&retired===stalled&&target_retires==0&&
            rfi_retires==0,"backpressure holds handler offer stable");
    end
    @(negedge clk);retire_enable=1;
    for(int i=0;i<800&&target_retires==0;i++)@(negedge clk);
    check(target_retires==1&&handler_retires==2&&rfi_retires==1&&
          irq_count==1&&alias_lines==1&&alias_hits>0&&cir&&!cdr&&!cpr,
          "RFI resumed translated cached target exactly once");
    $display("PASS translated I-cache IRQ: checks=%0d retires=%0d alias_lines=%0d old_beats=%0d irq=%0d handler=%0d rfi=%0d target=%0d alias_hits=%0d",
      checks,retires,alias_lines,old_beats,irq_count,handler_retires,rfi_retires,target_retires,alias_hits);
    $finish;
  end
endmodule
