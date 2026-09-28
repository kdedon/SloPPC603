// Seeded stress of the translated cached 60x top. Each iteration patches two
// routines (store/dcbst/sync/icbi/isync), remaps an IBAT alias between them,
// runs in supervisor, user or real mode, and logs to guarded CI data. The
// target randomly delays, retries (ARTRY), replaces read beats (DRTRY) and
// holds line fills; EXT, DEC and external cache maintenance arrive at random.
// Run with +seed=N; the first divergence reports the seed.
/* verilator lint_off BLKSEQ */
module tb_core_bat_cached_bus60x_stress;
  import ppc_pkg::*;
  `include "ppc_asm.svh"
  localparam int ITERATIONS=24;
  localparam logic [31:0] ROUTINE=32'h6000;       // region A; B is +0x20000
  localparam logic [31:0] ALIAS=32'h1000_6000;    // IBAT1 selects A or B
  localparam logic [31:0] BLOCK_LINE[2]='{32'h3000,32'h4000};   // set 0
  localparam logic [31:0] LOG=32'h3100;           // guarded CI log
  localparam logic [31:0] DEC_RELOAD=32'd220;
  logic clk=0,rst_n=0;
  always #5 clk=~clk;
  logic start_valid=0,start_ready,running,cir,cdr,cpr;
  logic tv,tr,halted,ifetch_error,protocol_error,bus_busy,pimem_error;
  logic irq=0,irq_taken,dec_taken,tick=0;
  logic [31:0] irq_pc,dec_pc;
  retire_packet_t retired;
  logic br_n,bg_n,abb_n,abb_oe,ts_n,ts_oe,tbst_n,ci_n,wt_n,gbl_n,addr_oe;
  logic [31:0] bus_a;
  logic [4:0] tt;
  logic [2:0] tsiz;
  logic [1:0] tc,cse;
  logic aack_n,artry_n,dbg_n,dbb_n,dbb_oe,data_oe,ta_n,drtry_n,tea_n;
  logic [63:0] data_in,data_out;
  logic cache_hit,cache_miss,cache_busy,cache_enabled;
  logic maintenance_valid=0,maintenance_ready,maintenance_done_valid;
  logic maintenance_done_ready=0,maintenance_busy,maintenance_enable=1;
  logic bfm_retry=0,bfm_hold=0,bfm_drtry=0,retire_enable=1;
  int bfm_wait=0;
  int unsigned seed=1,rng=1;
  int cycles=0,checks=0,retires=0,iteration=0;
  bit finished=0;
  int identity_calls=0,alias_calls=0,ext_count=0,dec_count=0,sc_count=0;
  int maintenance_commands=0,cache_toggles=0,icbi_count=0,held_fills=0;
  int icbi_fill_overlap=0,hold_until=0,log_writes=0,log_loads=0;
  int user_iterations=0,real_iterations=0,cache_hits=0;
  logic [31:0] resume_pc=0;
  bit resume_pending=0,line_hold=0;
  logic [31:0] line_hold_addr=32'hffff_ffff;
  int line_hold_start=0,line_hold_icbi=0,line_hold_need=0,line_icbi_overlap=0;
  logic [31:0] event_pc=0;
  int cache_misses=0,busy_cycles=0,maintenance_busy_cycles=0;

  /* verilator lint_off PINCONNECTEMPTY */
  logic unused_checkstop;
  ppc_core_bat_cached_bus60x #(.RESET_PC(32'b0),
    .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),.ENABLE_LIVE_CONTEXT(1'b1),
    .ENABLE_RUNTIME_BAT(1'b1),.ENABLE_EXTERNAL_INTERRUPTS(1'b1),
    .ENABLE_TIMERS(1'b1),.ENABLE_CACHE_INSTRUCTIONS(1'b1)) dut(
    .clk_i(clk),.rst_ni(rst_n),
    .external_irq_i(irq),.interrupt_taken_o(irq_taken),.interrupt_pc_o(irq_pc),
    .timer_tick_i(tick),.timebase_enable_i(1'b1),
    .decrementer_taken_o(dec_taken),.decrementer_pc_o(dec_pc),
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
    .checkstop_o(unused_checkstop), .halted_o(halted),.redirect_valid_i(1'b0),.redirect_all_i(1'b0),
    .redirect_keep_pivot_i(1'b0),.redirect_pivot_i('0),
    .redirect_target_i('0),.redirect_accepted_o(),
    .translation_fault_o(),.fault_instruction_o(),.fault_write_o(),
    .fault_ea_o(),.fault_miss_o(),.fault_protection_o(),
    .fault_guarded_o(),.fault_config_o(),.fault_invalid_input_o(),
    .fault_invalid_entry_o(),.pimem_error_o(pimem_error),
    .busy_o(),.ifetch_error_o(ifetch_error),
    .bus_protocol_error_o(protocol_error),.bus_busy_o(bus_busy),
    .icache_hit_o(cache_hit),.icache_miss_o(cache_miss),
    .icache_busy_o(cache_busy),
    .maintenance_valid_i(maintenance_valid),
    .maintenance_ready_o(maintenance_ready),
    .maintenance_invalidate_i(1'b1),.maintenance_cache_enable_i(maintenance_enable),
    .maintenance_done_valid_o(maintenance_done_valid),
    .maintenance_done_ready_i(maintenance_done_ready),
    .cache_enabled_o(cache_enabled),.maintenance_busy_o(maintenance_busy),
    .br_n_o(br_n),.bg_n_i(bg_n),.abb_n_i(1'b1),
    .abb_n_o(abb_n),.abb_oe_o(abb_oe),.ts_n_o(ts_n),.ts_oe_o(ts_oe),
    .a_o(bus_a),.tt_o(tt),.tbst_n_o(tbst_n),.tsiz_o(tsiz),
    .tc_o(tc),.ci_n_o(ci_n),.wt_n_o(wt_n),.gbl_n_o(gbl_n),
    .cse_o(cse),.addr_oe_o(addr_oe),.aack_n_i(aack_n),
    .artry_n_i(artry_n),.dbg_n_i(dbg_n),.dbb_n_i(1'b1),
    .dbb_n_o(dbb_n),.dbb_oe_o(dbb_oe),
    .d_i(data_in),.d_o(data_out),.d_oe_o(data_oe),
    .ta_n_i(ta_n),.drtry_n_i(drtry_n),.tea_n_i(tea_n)
  );
  /* verilator lint_on PINCONNECTEMPTY */
  bus60x_scripted_target_bfm #(.MEM_BYTES(262144)) target(
    .clk_i(clk),.br_n_i(br_n),.ts_n_i(ts_n),.ts_oe_i(ts_oe),.a_i(bus_a),
    .tt_i(tt),.tbst_n_i(tbst_n),.tsiz_i(tsiz),.tc_i(tc),
    .dbb_n_i(dbb_n),.dbb_oe_i(dbb_oe),.d_i(data_out),.d_oe_i(data_oe),
    .retry_i(bfm_retry),.hold_i(bfm_hold),.drtry_i(bfm_drtry),.wait_i(bfm_wait),
    .bg_n_o(bg_n),.aack_n_o(aack_n),.artry_n_o(artry_n),.dbg_n_o(dbg_n),
    .d_o(data_in),.ta_n_o(ta_n),.drtry_n_o(drtry_n),.tea_n_o(tea_n)
  );
  assign tr=rst_n&&retire_enable;

  function automatic int unsigned rnd();
    rng^=rng<<13; rng^=rng>>17; rng^=rng<<5;
    return rng;
  endfunction
  task automatic check(input bit ok,input string why);
    checks++;
    if(!ok)$fatal(1,"%s seed=%0d cycle=%0d iteration=%0d pc=%08x insn=%08x value=%08x",
      why,seed,cycles,iteration,retired.pc,retired.insn,retired.value);
  endtask
  task automatic put_word(input logic [31:0] address,input logic [31:0] value);
    for(int k=0;k<4;k++)target.mem[int'(address)+k]=value[31-8*k -:8];
  endtask
  function automatic logic [31:0] get_word(input logic [31:0] address);
    return {target.mem[int'(address)],target.mem[int'(address)+1],
            target.mem[int'(address)+2],target.mem[int'(address)+3]};
  endfunction

  logic [31:0] pc_cursor;
  task automatic org(input logic [31:0] address); pc_cursor=address; endtask
  task automatic emit(input logic [31:0] word);
    put_word(pc_cursor,word);
    pc_cursor+=4;
  endtask
  task automatic load32(input int rt,input logic [31:0] value);
    emit(asm_lis(rt,int'(value[31:16])));
    emit(asm_ori(rt,rt,int'(value[15:0])));
  endtask
  task automatic patch_bc(input logic [31:0] at,input int bo,input int bi,
                          input logic [31:0] target_pc);
    put_word(at,asm_bc(bo,bi,int'(target_pc-at)));
  endtask

  // One patch block ending in icbi. The code that follows starts with isync
  // on a line in set 0, the routines' set; blocks alternate so that line was
  // invalidated by the previous iteration's icbi and refills while this
  // iteration's icbi runs. With single set, only A's block is invalidated:
  // icbi clears all four ways of the set, so B must still be fresh.
  task automatic patch_block(input logic [31:0] isync_line,input logic [31:0] loop,
                             input bit single);
    org(isync_line-32'd44);
    emit(asm_lis(11,'h3900)); emit(asm_or(11,11,20)); emit(asm_stw(11,0,12));
    emit(asm_lis(11,'h3920)); emit(asm_or(11,11,20)); emit(asm_stw(11,0,13));
    emit(asm_dcbst(0,12)); emit(asm_dcbst(0,13)); emit(ASM_SYNC);
    if(single)begin emit(ASM_NOP); emit(asm_icbi(0,12)); end
    else begin emit(asm_icbi(0,13)); emit(asm_icbi(0,12)); end
    if(pc_cursor!=isync_line)$fatal(1,"patch block layout");
    emit(ASM_ISYNC);
    emit(asm_spr(1,12,9)); emit(ASM_BCTRL);
    emit(asm_cmpwi(19,0)); emit(asm_bc(ASM_BO_TRUE,ASM_BI_EQ,12));
    emit(asm_spr(1,14,9)); emit(ASM_BCTRL);
    emit(asm_stw(20,0,16)); emit(ASM_EIEIO); emit(asm_lwz(17,0,16));
    emit(asm_dcbf(0,16));
    emit(ASM_SC);
    emit(asm_cmpwi(20,ITERATIONS));
    emit(asm_bc(ASM_BO_TRUE,ASM_BI_LT,int'(loop-pc_cursor)));
    emit(asm_li(31,99));
    emit(ASM_SELF);
  endtask

  task automatic assemble;
    logic [31:0] loop,user_skip,real_skip,odd_block;
    org(0); emit(asm_ba(32'h2000,0));
    org('h500);
    emit(asm_spr(0,23,26)); emit(asm_spr(0,22,27));
    emit(asm_addi(27,27,1)); emit(ASM_RFI);
    org('h900);
    emit(asm_spr(0,23,26)); emit(asm_spr(0,22,27));
    emit(asm_li(25,int'(DEC_RELOAD))); emit(asm_spr(1,25,22));
    emit(asm_addi(26,26,1)); emit(ASM_RFI);
    org('hc00);
    emit(asm_spr(0,23,26)); emit(asm_ori(24,0,'h8030)); emit(asm_spr(1,24,27));
    emit(ASM_RFI);
    org(ROUTINE); emit(asm_li(8,0)); emit(ASM_BLR);
    org(ROUTINE+32'h20000); emit(asm_li(9,0)); emit(ASM_BLR);

    org('h2000);
    emit(asm_li(0,0));
    emit(asm_li(3,3)); emit(asm_spr(1,3,528)); emit(asm_spr(1,3,536));
    emit(asm_li(3,2)); emit(asm_spr(1,3,529)); emit(asm_spr(1,3,537));
    load32(3,32'h1000_0003); emit(asm_spr(1,3,530));
    emit(asm_li(3,2)); emit(asm_spr(1,3,531));
    load32(3,32'h0002_0003); emit(asm_spr(1,3,538));    // region B data
    load32(3,32'h0002_0002); emit(asm_spr(1,3,539));
    load32(3,32'h6000_0003); emit(asm_spr(1,3,542));
    emit(asm_li(3,'h2a)); emit(asm_spr(1,3,543));      // guarded CI
    emit(asm_li(25,int'(DEC_RELOAD))); emit(asm_spr(1,25,22));
    emit(asm_li(20,0)); emit(asm_li(21,0));
    emit(asm_li(12,int'(ROUTINE)));
    emit(asm_d(15,13,12,2));                            // addis r13,r12,2
    emit(asm_d(15,14,12,'h1000));                       // addis r14,r12,0x1000
    emit(asm_ba(32'h2400,0));
    org('h2400);
    loop=pc_cursor;
    emit(asm_ori(5,0,'h8030)); emit(asm_mtmsr(5));
    emit(asm_addi(20,20,1));
    emit(asm_rlwinm(15,20,17,14,14)); emit(asm_ori(15,15,2));
    emit(asm_spr(1,15,531));                            // IBAT1L: odd -> B
    // Mode cycles user, real, supervisor; r18 is the log base, r19 alias use.
    emit(asm_addi(21,21,1)); emit(asm_cmpwi(21,3));
    emit(asm_bc(ASM_BO_FALSE,ASM_BI_EQ,8)); emit(asm_li(21,0));
    emit(asm_ori(5,0,'h8030)); emit(asm_lis(18,'h6000)); emit(asm_li(19,1));
    emit(asm_cmpwi(21,1)); user_skip=pc_cursor; emit(0);
    emit(asm_ori(5,0,'hc030));
    patch_bc(user_skip,ASM_BO_FALSE,ASM_BI_EQ,pc_cursor);
    emit(asm_cmpwi(21,2)); real_skip=pc_cursor; emit(0);
    emit(asm_ori(5,0,'h8000)); emit(asm_li(18,0)); emit(asm_li(19,0));
    patch_bc(real_skip,ASM_BO_FALSE,ASM_BI_EQ,pc_cursor);
    emit(asm_ori(18,18,int'(LOG)));
    emit(asm_rlwinm(10,20,2,0,29)); emit(asm_add(16,18,10));
    emit(asm_d(28,20,10,1));                            // andi. r10,r20,1
    emit(asm_mtmsr(5));
    odd_block=pc_cursor;
    emit(asm_bc(ASM_BO_FALSE,ASM_BI_EQ,int'((BLOCK_LINE[1]-32'd44)-odd_block)));
    emit(asm_ba(BLOCK_LINE[0]-32'd44,0));
    patch_block(BLOCK_LINE[0],loop,1'b0);
    patch_block(BLOCK_LINE[1],loop,1'b1);
  endtask

  function automatic bit handler_pc(input logic [31:0] pc);
    return pc<32'h1000;
  endfunction

  always @(posedge clk)begin
    cycles++;
    if(rst_n)begin
      check(cycles<400000,"stress watchdog");
      check(!halted&&!ifetch_error&&!pimem_error&&!protocol_error,
        "unexpected transport or core diagnostic");
      if(addr_oe&&ts_oe&&!ts_n)
        check(abb_oe&&!abb_n&&bus_busy&&wt_n&&gbl_n&&cse==0,"address ownership");
      if(cache_hit)cache_hits++;
      if(cache_miss)cache_misses++;
      if(cache_busy)busy_cycles++;
      if(maintenance_busy)maintenance_busy_cycles++;
      if(addr_oe&&ts_oe&&!ts_n&&tc!=2)check(tbst_n&&!ci_n,"scalar inhibited data");
      if(irq_taken)event_pc=irq_pc;
      if(dec_taken)event_pc=dec_pc;
      if(dut.icbi_req_valid&&dut.icbi_req_ready)icbi_count++;
      if(dut.icbi_req_valid&&target.in_data&&target.burst)icbi_fill_overlap++;
      if(irq_taken)begin
        check(irq&&!dec_taken,"single accepted event");
        irq<=0;
      end
      if(!ta_n&&dbb_oe&&tt==5'b00010&&bus_a>=LOG&&bus_a<LOG+32'h100)begin
        int index;
        index=int'(bus_a-LOG)/4;
        log_writes++;
        check(bus_a[1:0]==0&&tsiz==4&&index==log_writes&&
              data_out[63-32*int'(bus_a[2]) -:32]==32'(index),
          "log store once per iteration, in order");
      end
      if(tv&&tr)begin
        logic [31:0] pc;
        pc=retired.pc;
        retires++;
        check(^retired!==1'bx&&!retired.illegal&&retired.fetch_fault==FETCH_OK,
          "known legal retirement");
        check(pc<32'h300||pc>=32'h500&&pc<32'h600||pc>=32'h900&&pc<32'ha00||
              pc>=32'hc00&&pc<32'hd00||pc>=32'h2000,
          "unexpected exception vector");
        if(resume_pending&&!handler_pc(pc))begin
          check(pc==resume_pc,"precise resume after event");
          resume_pending=0;
        end
        if(pc==32'h500||pc==32'h900||pc==32'hc00)begin
          check(!resume_pending||retired.value==resume_pc,"nested event keeps resume PC");
          resume_pc=retired.value;
          if(pc!=32'hc00)check(retired.value==event_pc,"handler SRR0 is the accepted event PC");
          if(pc==32'h500)ext_count++;
          if(pc==32'h900)dec_count++;
          if(pc==32'hc00)sc_count++;
        end
        if((pc==32'h504||pc==32'h904))
          check(retired.value[15]&&!retired.value[6],"event SRR1 has EE, IP clear");
        if(retired.insn==ASM_RFI)begin
          resume_pending=1;
        end
        if(retired.gpr_write&&retired.gpr==20&&!handler_pc(pc))begin
          iteration=int'(retired.value);
          if(iteration%3==1)user_iterations++;
          if(iteration%3==2)real_iterations++;
        end
        if(pc==ROUTINE)begin
          check(retired.gpr==8&&retired.value==32'(iteration),"identity routine is fresh");
          check(iteration%3==1?(cpr&&cir&&cdr):iteration%3==2?(!cpr&&!cir&&!cdr):
                (!cpr&&cir&&cdr),"routine runs in the iteration's mode");
          identity_calls++;
        end
        if(pc==ALIAS)begin
          check(iteration%3!=2&&retired.gpr==((iteration%2==1)?9:8)&&
                retired.value==32'(iteration),
            "alias routine follows the remap and is fresh");
          alias_calls++;
        end
        if(retired.gpr_write&&retired.gpr==17&&!handler_pc(pc))begin
          check(retired.value==32'(iteration),"log load returns the store");
          log_loads++;
        end
        if(retired.gpr_write&&retired.gpr==31&&retired.value==99)finished=1;
      end
    end
  end
  assert property(@(posedge clk) disable iff(!rst_n)
    tv&&!tr |=> tv&&$stable(retired));

  // Policies change 2 ns after the edge the target samples, so each draw is
  // ordered against its use.
  always @(posedge clk)begin
    #2;
    tick<=cycles%4==0;
    bfm_wait=(rnd()%4==0)?int'(rnd()%4):0;
    bfm_retry=rnd()%100<12;
    bfm_drtry=rnd()%100<10;
    retire_enable=rnd()%8!=0;
    if(rst_n&&target.in_data&&target.burst&&hold_until<=cycles&&rnd()%100<6)begin
      hold_until=cycles+5+int'(rnd()%50);
      held_fills++;
    end
    if(rst_n&&dut.icbi_req_valid&&target.in_data&&target.burst&&
       hold_until<=cycles&&rnd()%2==0)
      hold_until=cycles+10+int'(rnd()%20);
    // Often hold a fill of a post-icbi line until icbi has waited on it, so
    // icbi overlaps a same-set fill that missed while the routine was valid.
    if(rst_n&&!line_hold&&target.in_data&&target.burst&&
       ({target.addr[31:5],5'b0}==BLOCK_LINE[0]||
        {target.addr[31:5],5'b0}==BLOCK_LINE[1])&&
       target.addr!=line_hold_addr&&rnd()%3!=0)begin
      line_hold=1;
      line_hold_addr=target.addr;
      line_hold_start=cycles;
      line_hold_icbi=0;
      line_hold_need=2+int'(rnd()%16);
    end
    if(line_hold)begin
      if(dut.icbi_req_valid)line_hold_icbi++;
      if(line_hold_icbi>=line_hold_need||cycles-line_hold_start>300)begin
        if(line_hold_icbi>=line_hold_need)line_icbi_overlap++;
        line_hold=0;
      end
    end
    if(!target.in_data)line_hold_addr=32'hffff_ffff;
    bfm_hold=hold_until>cycles||line_hold;
    if(rst_n&&running&&!irq&&!finished&&rnd()%700==0)irq=1;
  end

  initial begin : maintenance_control
    int gap;
    wait(rst_n&&running);
    forever begin
      gap=1500+int'(rnd()%5000);
      repeat(gap)@(posedge clk);
      if(finished)break;
      // Keep commands clear of icbi overlapping a held same-set fill, where
      // a flash invalidate would mask a lost icbi.
      @(negedge clk);
      while(line_hold||dut.icbi_req_valid)@(negedge clk);
      if(!cache_enabled)maintenance_enable=1;
      else maintenance_enable=rnd()%5!=0;
      if(maintenance_enable!=cache_enabled)cache_toggles++;
      maintenance_valid=1;
      #1;
      while(!maintenance_ready)begin @(negedge clk);#1;end
      @(posedge clk);
      @(negedge clk);
      maintenance_valid=0;
      maintenance_commands++;
      while(!maintenance_done_valid)@(negedge clk);
      repeat(int'(rnd()%30))@(negedge clk);
      maintenance_done_ready=1;
      @(posedge clk);
      @(negedge clk);
      maintenance_done_ready=0;
    end
  end

  initial begin
    if(!$value$plusargs("seed=%d",seed))seed=1;
    rng=seed*32'h9e3779b9+32'h7f4a7c15;
    if(rng==0)rng=1;
    assemble();
    repeat(4)@(negedge clk);rst_n=1;
    @(negedge clk);start_valid=1;
    do @(posedge clk);while(!start_ready);
    @(negedge clk);start_valid=0;
    wait(finished);
    repeat(40)@(posedge clk);
    check(iteration==ITERATIONS&&identity_calls==ITERATIONS&&
          alias_calls==ITERATIONS-real_iterations&&sc_count==ITERATIONS,
      "every iteration ran its routines and returned by sc");
    check(icbi_count==ITERATIONS+ITERATIONS/2&&log_writes==ITERATIONS&&log_loads==ITERATIONS,
      "icbi and log totals");
    for(int i=1;i<=ITERATIONS;i++)
      check(get_word(LOG+32'(4*i))==32'(i),"log memory");
    check(user_iterations>0&&real_iterations>0&&ext_count>0&&dec_count>0&&
          maintenance_commands>0&&target.retries>0&&target.drtries>0&&held_fills>0&&
          line_icbi_overlap>0,
      "stress coverage");
    check(cache_misses>0&&busy_cycles>0&&maintenance_busy_cycles>0,"cache activity");
    $display("PASS translated cache stress seed=%0d: checks=%0d retires=%0d cycles=%0d icbi=%0d ext=%0d dec=%0d maint=%0d toggles=%0d retries=%0d drtries=%0d held=%0d icbi_fill_overlap=%0d line_icbi=%0d hits=%0d",
      seed,checks,retires,cycles,icbi_count,ext_count,dec_count,maintenance_commands,
      cache_toggles,target.retries,target.drtries,held_fills,icbi_fill_overlap,
      line_icbi_overlap,cache_hits);
    $finish;
  end
endmodule
