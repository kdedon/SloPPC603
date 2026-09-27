// Cache control instructions on the translated cached 60x top: translated
// probe faults, dcbz alignment, dcbi privilege, stale code without icbi,
// icbi across a retried and held same-set refill with a pending external
// interrupt, icbi tied with external maintenance, and retried guarded data.
/* verilator lint_off BLKSEQ */
module tb_core_bat_cached_bus60x_cacheops;
  import ppc_pkg::*;
  `include "ppc_asm.svh"
  logic clk=0,rst_n=0;
  always #5 clk=~clk;
  logic start_valid=0,start_ready,running,cir,cdr,cpr;
  logic tv,tr,halted,ifetch_error,protocol_error,bus_busy,pimem_error;
  logic irq=0,irq_taken;
  logic [31:0] irq_pc;
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
  logic maintenance_done_ready=0,maintenance_busy;
  logic bfm_retry,bfm_hold,bfm_drtry;
  int bfm_wait;
  int cycles=0,checks=0,retires=0,phase=0;
  int data_offers[0:127];

  localparam logic [31:0] X=32'h6100;          // patched routine, set 8
  localparam logic [31:0] Y_LINE=32'h4100;     // code after icbi, set 8
  localparam logic [31:0] ICBI_PC=32'h40fc;
  localparam logic [31:0] DATA=32'h3014;
  localparam logic [31:0] IO=32'h3100;         // guarded CI through DBAT3

  // Expected synchronous exceptions, in program order.
  typedef struct {int vector; logic [31:0] srr0,dar,dsisr,srr1;} expect_t;
  expect_t expected[$];
  expect_t current;
  int exceptions=0,dsi_count=0,align_count=0,program_count=0,ext_count=0;
  int x_runs=0;
  int x_values[4]='{1,1,2,3};
  logic [31:0] ext_srr0=0;
  int icbi_retire_cycle=-1,icbi_valid_cycles=0,y_hold_overlap=0;
  bit y_retry_done=0,y_hold_active=0,y_seen=0,maint_started=0,store9_retired=0;
  int maint_accept_cycle=-1,maint_done_cycle=-1,icbi_ready_cycle=-1;
  int io_writes[$];
  int cache_misses=0,cache_hits=0,cache_busy_cycles=0;

  /* verilator lint_off PINCONNECTEMPTY */
  ppc_core_bat_cached_bus60x #(.RESET_PC(32'b0),
    .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),.ENABLE_LIVE_CONTEXT(1'b1),
    .ENABLE_RUNTIME_BAT(1'b1),.ENABLE_EXTERNAL_INTERRUPTS(1'b1),
    .ENABLE_CACHE_INSTRUCTIONS(1'b1)) dut(
    .clk_i(clk),.rst_ni(rst_n),
    .external_irq_i(irq),.interrupt_taken_o(irq_taken),.interrupt_pc_o(irq_pc),
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
    .icache_hit_o(cache_hit),.icache_miss_o(cache_miss),
    .icache_busy_o(cache_busy),
    .maintenance_valid_i(maintenance_valid),
    .maintenance_ready_o(maintenance_ready),
    .maintenance_invalidate_i(1'b1),.maintenance_cache_enable_i(1'b1),
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
  bus60x_scripted_target_bfm #(.MEM_BYTES(32768)) target(
    .clk_i(clk),.br_n_i(br_n),.ts_n_i(ts_n),.ts_oe_i(ts_oe),.a_i(bus_a),
    .tt_i(tt),.tbst_n_i(tbst_n),.tsiz_i(tsiz),.tc_i(tc),
    .dbb_n_i(dbb_n),.dbb_oe_i(dbb_oe),.d_i(data_out),.d_oe_i(data_oe),
    .retry_i(bfm_retry),.hold_i(bfm_hold),.drtry_i(bfm_drtry),.wait_i(bfm_wait),
    .bg_n_o(bg_n),.aack_n_o(aack_n),.artry_n_o(artry_n),.dbg_n_o(dbg_n),
    .d_o(data_in),.ta_n_o(ta_n),.drtry_n_o(drtry_n),.tea_n_o(tea_n)
  );
  assign tr=rst_n&&cycles%7!=3;

  // Retry the Y-line fill once and data tenures once each in phase 10;
  // hold the Y-line fill until icbi has waited on it; replace phase-10 reads.
  assign bfm_retry=!target.last_retried &&
    ((phase==8&&target.burst&&{target.addr[31:5],5'b0}==Y_LINE&&!y_retry_done)||
     (phase==10&&!target.instruction));
  assign bfm_hold=y_hold_active&&target.burst&&{target.addr[31:5],5'b0}==Y_LINE;
  assign bfm_drtry=phase==10&&!target.instruction;
  assign bfm_wait=cycles%3;

  task automatic check(input bit ok,input string why);
    checks++;
    if(!ok)$fatal(1,"%s cycle=%0d phase=%0d pc=%08x insn=%08x value=%08x",
      why,cycles,phase,retired.pc,retired.insn,retired.value);
  endtask
  task automatic put_word(input logic [31:0] address,input logic [31:0] value);
    for(int k=0;k<4;k++)target.mem[int'(address)+k]=value[31-8*k -:8];
  endtask
  function automatic logic [31:0] get_word(input logic [31:0] address);
    return {target.mem[int'(address)],target.mem[int'(address)+1],
            target.mem[int'(address)+2],target.mem[int'(address)+3]};
  endfunction
  // UM Table 4-13 for an X-form instruction, in manual bit numbering.
  function automatic logic [31:0] alignment_dsisr(input logic [31:0] insn);
    logic [31:0] value;
    value=0;
    value[31-15]=insn[31-29]; value[31-16]=insn[31-30];
    value[31-17]=insn[31-25];
    for(int k=0;k<4;k++)value[31-(18+k)]=insn[31-(21+k)];
    for(int k=0;k<5;k++)value[31-(22+k)]=insn[31-(6+k)];
    for(int k=0;k<5;k++)value[31-(27+k)]=insn[31-(11+k)];
    return value;
  endfunction

  // Hand assembler cursor.
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
  task automatic set_phase(input int number); emit(asm_li(31,number)); endtask
  task automatic expect_fault(input int vector,input logic [31:0] word,
      input logic [31:0] dar,input logic [31:0] dsisr,input logic [31:0] srr1);
    expect_t e;
    e.vector=vector; e.srr0=pc_cursor; e.dar=dar; e.dsisr=dsisr; e.srr1=srr1;
    expected.push_back(e);
    emit(word);
  endtask
  task automatic handler(input int vector,input int counter);
    org(32'(vector));
    if(vector==32'h300||vector==32'h600)begin
      emit(asm_spr(0,20,19)); emit(asm_spr(0,21,18));
    end
    emit(asm_spr(0,22,26)); emit(asm_spr(0,23,27));
    if(vector!=32'h500)begin
      emit(asm_addi(22,22,4)); emit(asm_spr(1,22,26));
    end
    emit(asm_addi(counter,counter,1));
    emit(ASM_RFI);
  endtask

  task automatic assemble;
    org(0); emit(asm_ba(32'h2000,0));
    handler('h300,30); handler('h500,27); handler('h600,29); handler('h700,28);
    org('hc00); emit(asm_li(26,'h30)); emit(asm_spr(1,26,27)); emit(ASM_RFI);
    org(X); emit(asm_li(8,1)); emit(ASM_BLR);

    org('h2000);
    emit(asm_li(0,0));
    emit(asm_li(3,3)); emit(asm_spr(1,3,528)); emit(asm_spr(1,3,536));
    emit(asm_li(3,2)); emit(asm_spr(1,3,529)); emit(asm_spr(1,3,537));
    load32(3,32'h4000_0003); emit(asm_spr(1,3,538));
    emit(asm_li(3,1)); emit(asm_spr(1,3,539));      // read-only
    load32(3,32'h5000_0003); emit(asm_spr(1,3,540));
    emit(asm_li(3,0)); emit(asm_spr(1,3,541));      // no access
    load32(3,32'h6000_0003); emit(asm_spr(1,3,542));
    emit(asm_li(3,'h2a)); emit(asm_spr(1,3,543));   // I|G, read/write
    emit(asm_li(5,'h30)); emit(asm_mtmsr(5)); emit(ASM_ISYNC);

    // Touches never fault or reach the bus, even with no access.
    set_phase(1);
    load32(9,32'h5000_3000);
    emit(asm_dcbt(0,9)); emit(asm_dcbtst(0,9)); emit(asm_dcbt(9,0));

    // Permitted probes complete without a transfer.
    set_phase(2);
    emit(asm_li(10,int'(DATA)));
    emit(asm_dcbf(0,10)); emit(asm_dcbst(0,10)); emit(asm_dcbi(0,10));

    // No-access block: load-class and store-class DSI.
    set_phase(3);
    load32(11,32'h5000_3014);
    expect_fault('h300,asm_dcbf(0,11),32'h5000_3014,32'h0800_0000,32'h30);
    expect_fault('h300,asm_dcbst(0,11),32'h5000_3014,32'h0800_0000,32'h30);
    expect_fault('h300,asm_dcbi(0,11),32'h5000_3014,32'h0a00_0000,32'h30);

    // Read-only block: loads pass; dcbi and dcbz fault before alignment.
    set_phase(4);
    load32(12,32'h4000_3014);
    emit(asm_dcbf(0,12)); emit(asm_dcbst(0,12));
    expect_fault('h300,asm_dcbi(0,12),32'h4000_3014,32'h0a00_0000,32'h30);
    expect_fault('h300,asm_dcbz(0,12),32'h4000_3014,32'h0a00_0000,32'h30);

    // Translated dcbz on a writable block takes the alignment exception.
    set_phase(5);
    expect_fault('h600,asm_dcbz(10,0),DATA,alignment_dsisr(asm_dcbz(10,0)),32'h30);

    // User mode: dcbi is privileged; icbi, dcbf and dcbz are not.
    set_phase(6);
    emit(asm_li(5,'h4030)); emit(asm_mtmsr(5));
    expect_fault('h700,asm_dcbi(0,10),0,0,32'h0004_4030);
    emit(asm_icbi(0,10)); emit(asm_dcbf(0,10));
    expect_fault('h600,asm_dcbz(0,10),DATA,alignment_dsisr(asm_dcbz(0,10)),32'h4030);
    emit(ASM_SC);

    // A cached routine stays stale after store/dcbst/sync/isync.
    set_phase(7);
    emit(asm_ori(5,0,'h8030)); emit(asm_mtmsr(5));
    emit(asm_ba(X,1));
    load32(11,32'h3900_0002);
    emit(asm_li(12,int'(X)));
    emit(asm_stw(11,0,12)); emit(asm_dcbst(0,12)); emit(ASM_SYNC); emit(ASM_ISYNC);
    emit(asm_ba(X,1));
    emit(asm_ba(32'h4000,0));

    // icbi waits on a retried, held fill of its own set; EXT waits for it.
    org('h4000);
    set_phase(8);
    emit(asm_dcbst(0,12)); emit(ASM_SYNC);
    while(pc_cursor!=ICBI_PC)emit(ASM_NOP);
    emit(asm_icbi(0,12));
    emit(ASM_ISYNC);
    emit(asm_ba(X,1));

    // icbi ties with external maintenance and waits for its completion.
    set_phase(9);
    load32(11,32'h3900_0003);
    emit(asm_stw(11,0,12)); emit(asm_dcbst(0,12)); emit(ASM_SYNC);
    emit(asm_icbi(0,12)); emit(ASM_ISYNC);
    emit(asm_ba(X,1));

    // Guarded CI data: each tenure retried once, each read beat replaced.
    set_phase(10);
    load32(14,32'h6000_0000|IO);
    load32(13,32'h1122_3344);
    emit(asm_stw(13,0,14)); emit(ASM_EIEIO);
    emit(asm_li(15,'h55)); emit(asm_stb(15,5,14)); emit(ASM_SYNC);
    emit(asm_lwz(16,0,14)); emit(asm_lbz(17,5,14)); emit(asm_lwz(18,4,14));

    // Real mode: dcbz still aligns; probes complete.
    set_phase(11);
    emit(asm_mtmsr(0));
    expect_fault('h600,asm_dcbz(0,10),DATA,alignment_dsisr(asm_dcbz(0,10)),32'h0);
    emit(asm_dcbf(0,10)); emit(asm_dcbi(0,10));
    set_phase(99);
    emit(ASM_SELF);
  endtask

  always @(posedge clk)begin
    cycles++;
    if(rst_n)begin
      check(cycles<40000,"cache-operation watchdog");
      check(!halted&&!ifetch_error&&!pimem_error&&!protocol_error,
        "unexpected transport or core diagnostic");
      if(addr_oe&&ts_oe&&!ts_n)
        check(abb_oe&&!abb_n&&bus_busy&&wt_n&&gbl_n&&cse==0,"address tenure ownership");
      if(cache_miss)cache_misses++;
      if(cache_hit)cache_hits++;
      if(cache_busy&&phase==8)cache_busy_cycles++;
      if(maintenance_busy&&!maint_started)
        check(dut.icbi_req_valid,"control plane busy without icbi or command");
      if(addr_oe&&ts_oe&&!ts_n&&tc!=2)begin
        data_offers[phase]++;
        check(tbst_n&&!ci_n,"data tenure is scalar cache-inhibited");
      end
      if(!ta_n&&dbb_oe&&tt==5'b00010&&phase==10)io_writes.push_back(int'(bus_a));
      if(dut.icbi_req_valid)icbi_valid_cycles++;
      if(dut.icbi_req_valid&&dut.icbi_req_ready)icbi_ready_cycle=cycles;
      if(phase==8&&target.burst&&{target.addr[31:5],5'b0}==Y_LINE)begin
        y_seen=1;
        if(target.retries>0)y_retry_done=1;
      end
      if(phase==8&&dut.icbi_req_valid&&target.in_data&&target.burst&&
         {target.addr[31:5],5'b0}==Y_LINE)y_hold_overlap++;
      if(irq_taken)begin
        check(irq&&phase==8&&icbi_retire_cycle>=0&&irq_pc==ext_srr0,
          "EXT taken only after icbi retired, at the next instruction");
        irq<=0;
      end
      if(maintenance_valid&&maintenance_ready)maint_accept_cycle=cycles;
      if(maintenance_done_valid&&maintenance_done_ready)maint_done_cycle=cycles;
      if(tv&&tr)begin
        retires++;
        check(^retired!==1'bx&&!retired.illegal&&retired.fetch_fault==FETCH_OK,
          "known legal retirement");
        if(retired.gpr_write&&retired.gpr==31)phase=int'(retired.value);
        if(phase>=1&&phase<=10&&phase!=6&&retired.pc>=32'h2000)
          check(cir&&cdr&&!cpr,"translated supervisor context");
        if(retired.pc==ICBI_PC)icbi_retire_cycle=cycles;
        if(phase==9&&retired.insn==asm_stw(11,0,12))store9_retired=1;
        if(retired.pc==X)begin
          check(x_runs<4&&retired.gpr==8&&retired.value==32'(x_values[x_runs]),
            "patched routine value");
          x_runs++;
        end
        if(retired.pc==32'h300||retired.pc==32'h600||retired.pc==32'h700)begin
          check(expected.size()>0,"unexpected exception");
          current=expected.pop_front();
          check(current.vector==int'(retired.pc),"exception vector");
          exceptions++;
        end
        if(retired.pc==32'h300||retired.pc==32'h600)
          check(retired.value==current.dar,"DAR");
        if(retired.pc==32'h304||retired.pc==32'h604)
          check(retired.value==current.dsisr,"DSISR");
        if(retired.pc==32'h308||retired.pc==32'h608||retired.pc==32'h700)
          check(retired.value==current.srr0,"SRR0");
        if(retired.pc==32'h30c||retired.pc==32'h60c||retired.pc==32'h704)
          check(retired.value==current.srr1,"SRR1");
        if(retired.pc==32'h500)check(retired.value==ext_srr0,"EXT SRR0");
        if(retired.pc==32'h504)check(retired.value==32'h8030,"EXT SRR1");
        if(retired.gpr_write&&retired.gpr==30)dsi_count=int'(retired.value);
        if(retired.gpr_write&&retired.gpr==29)align_count=int'(retired.value);
        if(retired.gpr_write&&retired.gpr==28)program_count=int'(retired.value);
        if(retired.gpr_write&&retired.gpr==27)ext_count=int'(retired.value);
        if(phase==10&&retired.gpr_write&&retired.gpr==16)
          check(retired.value==32'h1122_3344,"guarded word load");
        if(phase==10&&retired.gpr_write&&retired.gpr==17)
          check(retired.value==32'h55,"guarded byte load");
        if(phase==10&&retired.gpr_write&&retired.gpr==18)
          check(retired.value==32'h0055_0000,"guarded neighbor word load");
      end
    end
  end
  assert property(@(posedge clk) disable iff(!rst_n)
    tv&&!tr |=> tv&&$stable(retired));

  // Phase 8: hold the Y fill until icbi has waited on it for 12 cycles and
  // raise EXT while icbi is pending.
  initial begin : y_line_control
    int waited;
    wait(phase==8);
    wait(y_seen&&y_retry_done);
    y_hold_active=1;
    wait(dut.icbi_req_valid);
    @(negedge clk);
    ext_srr0=Y_LINE;
    irq=1;
    waited=0;
    while(waited<12)begin
      @(posedge clk);
      check(!irq_taken&&!(dut.icbi_req_valid&&dut.icbi_req_ready),
        "icbi or EXT overtook the held fill");
      waited++;
    end
    @(negedge clk);
    y_hold_active=0;
  end

  // Phase 9: raise external maintenance when the patch store retires, while
  // icbi is already queued, and hold its completion until icbi has waited.
  initial begin : maintenance_control
    int waited;
    wait(phase==9&&store9_retired);
    @(negedge clk);
    maintenance_valid=1;
    maint_started=1;
    #1;
    while(!maintenance_ready)begin @(negedge clk);#1;end
    @(posedge clk);
    @(negedge clk);
    maintenance_valid=0;
    while(!maintenance_done_valid)@(negedge clk);
    waited=0;
    for(int i=0;i<400&&waited<20;i++)begin
      @(posedge clk);
      check(!(dut.icbi_req_valid&&dut.icbi_req_ready),"icbi ran before external completion");
      if(dut.icbi_req_valid)waited++;
    end
    check(waited==20,"icbi never waited on held external completion");
    @(negedge clk);
    maintenance_done_ready=1;
    @(posedge clk);
    @(negedge clk);
    maintenance_done_ready=0;
  end

  initial begin
    for(int a=0;a<64;a++)target.mem['h3000+a]=8'ha5;
    assemble();
    repeat(4)@(negedge clk);rst_n=1;
    @(negedge clk);start_valid=1;
    do @(posedge clk);while(!start_ready);
    @(negedge clk);start_valid=0;
    check(running&&cache_enabled&&!cir&&!cdr&&!cpr,"real-mode startup");
    wait(phase==6);
    wait(cpr);
    check(cir&&cdr,"user mode keeps translation");
    wait(phase==99);
    repeat(20)@(posedge clk);
    check(expected.size()==0&&exceptions==9&&dsi_count==5&&align_count==3&&
          program_count==1&&ext_count==1,"exception totals");
    check(x_runs==4,"patched routine ran four times");
    for(int p=1;p<=11;p++)
      if(p!=7&&p!=9&&p!=10)check(data_offers[p]==0,$sformatf("phase %0d data traffic",p));
    check(data_offers[7]==1&&data_offers[9]==1,"one store per patch");
    check(data_offers[10]>=10&&io_writes.size()==2&&io_writes[0]==int'(IO)&&
          io_writes[1]==int'(IO)+5,"guarded tenures retried once, stores once, in order");
    check(get_word(IO)==32'h1122_3344&&get_word(IO+4)==32'h0055_0000,"guarded memory");
    for(int a=0;a<64;a++)check(target.mem['h3000+a]==8'ha5,"probed block unchanged");
    check(y_retry_done&&y_hold_overlap>=12&&icbi_retire_cycle>0,
      "icbi overlapped a retried held fill");
    check(maint_started&&maint_accept_cycle>0&&maint_done_cycle>maint_accept_cycle&&
          icbi_ready_cycle>maint_done_cycle,"icbi followed external completion");
    check(target.drtries==3&&target.retries>=6,"retry coverage");
    check(cache_misses>=5&&cache_hits>0&&cache_busy_cycles>0&&!cir&&!cdr,"cache and final context");
    $display("PASS cache operations: checks=%0d retires=%0d exceptions=%0d icbi_wait=%0d y_overlap=%0d retries=%0d drtries=%0d",
      checks,retires,exceptions,icbi_valid_cycles,y_hold_overlap,target.retries,target.drtries);
    $finish;
  end
endmodule
