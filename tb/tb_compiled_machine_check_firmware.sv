// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Compiled machine-check, trace and IABR firmware on the translated cached
// 60x top. The pin target ends every tenure in the TEA window with TEA and
// otherwise retries, replaces read beats, holds fills and delays at random.
// MODE=0 runs the firmware to its tohost report; MODE=1 is the ME=0
// negative control, which must enter checkstop without a vector fetch.
/* verilator lint_off BLKSEQ */
module tb_compiled_machine_check_firmware;
  import ppc_pkg::*;
  logic clk=0,rst_n=0;
  always #5 clk=~clk;
  logic start_valid=0,start_ready,running,cir,cdr,cpr;
  logic tv,tr,halted,checkstop,ifetch_error,protocol_error,bus_busy,pimem_error;
  logic translation_fault;
  retire_packet_t retired;
  logic br_n,bg_n,abb_n,abb_oe,ts_n,ts_oe,tbst_n,ci_n,wt_n,gbl_n,addr_oe;
  logic [31:0] bus_a;
  logic [4:0] tt;
  logic [2:0] tsiz;
  logic [1:0] tc,cse;
  logic aack_n,artry_n,dbg_n,dbb_n,dbb_oe,data_oe,ta_n,drtry_n,tea_n;
  logic [63:0] data_in,data_out;
  logic cache_hit,cache_miss;
  logic bfm_retry=0,bfm_hold=0,bfm_drtry=0,retire_enable=1;
  int bfm_wait=0,mode=0;
  int unsigned rng=32'h1a2b3c4d;
  int cycles=0,retires=0,hold_until=0,held_fills=0;
  int mc_entries=0,trace_entries=0,iabr_entries=0,cache_hits=0,cache_misses=0;
  int vector_fetches=0;
  localparam int FW_MEM_BYTES=65536;
  localparam logic [31:0] TEA_BASE=32'hfff0dff0,TEA_END=32'hfff0e100;
  function automatic string check_detail();
    return $sformatf(" bus=%08x mode=%0d",bus_a,mode);
  endfunction
  `include "compiled_firmware.svh"

  /* verilator lint_off PINCONNECTEMPTY */
  ppc_core_bat_cached_bus60x #(.RETIRE_PAIRS(1'b0), .RESET_PC(32'hfff00100),.ENABLE_TEST_REDIRECT(1'b0),
    .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),.ENABLE_LIVE_CONTEXT(1'b1),
    .ENABLE_RUNTIME_BAT(1'b1),.ENABLE_EXTERNAL_INTERRUPTS(1'b1),
    .ENABLE_MACHINE_CHECK(1'b1),.ENABLE_DEBUG_EXCEPTIONS(1'b1)) dut(.bus_ce_i(1'b1),
    .perf_o(),
    .clk_i(clk),.rst_ni(rst_n),
    .external_irq_i(1'b0),.interrupt_taken_o(),.interrupt_pc_o(),
    .timer_tick_i(1'b0),.timebase_enable_i(1'b0),
    .pin_event_i('0), .pin_status_o(),
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
    .halted_o(halted),.checkstop_o(checkstop),
    .redirect_valid_i(1'b0),.redirect_all_i(1'b0),
    .redirect_keep_pivot_i(1'b0),.redirect_pivot_i('0),
    .redirect_target_i('0),.redirect_accepted_o(),
    .translation_fault_o(translation_fault),.fault_instruction_o(),.fault_write_o(),
    .fault_ea_o(),.fault_miss_o(),.fault_protection_o(),
    .fault_guarded_o(),.fault_config_o(),.fault_invalid_input_o(),
    .fault_invalid_entry_o(),.pimem_error_o(pimem_error),
    .busy_o(),.ifetch_error_o(ifetch_error),
    .bus_protocol_error_o(protocol_error),.bus_busy_o(bus_busy),
    .icache_hit_o(cache_hit),.icache_miss_o(cache_miss),
    .icache_busy_o(),
    .maintenance_valid_i(1'b0),.maintenance_ready_o(),
    .maintenance_invalidate_i(1'b0),.maintenance_cache_enable_i(1'b0),
    .maintenance_done_valid_o(),.maintenance_done_ready_i(1'b0),
    .cache_enabled_o(),.dcache_busy_o(),
    .maintenance_busy_o(),
    .br_n_o(br_n),.bg_n_i(bg_n),.abb_n_i(1'b1),
    .abb_n_o(abb_n),.abb_oe_o(abb_oe),.ts_n_o(ts_n),.ts_oe_o(ts_oe),
    .a_o(bus_a),.tt_o(tt),.tbst_n_o(tbst_n),.tsiz_o(tsiz),
    .tc_o(tc),.ci_n_o(ci_n),.wt_n_o(wt_n),.gbl_n_o(gbl_n),
    .cse_o(cse),.addr_oe_o(addr_oe),.aack_n_i(aack_n),
    .snoop_ts_n_i(1'b1),.snoop_a_i(32'b0),.snoop_tt_i(5'b0),.snoop_gbl_n_i(1'b1),.artry_n_o(),.artry_oe_o(),.artry_n_i(artry_n),.dbwo_n_i(1'b1), .dbg_n_i(dbg_n),.dbb_n_i(1'b1),
    .dbb_n_o(dbb_n),.dbb_oe_o(dbb_oe),
    .d_i(data_in),.d_o(data_out),.d_oe_o(data_oe),
    .ta_n_i(ta_n),.drtry_n_i(drtry_n),.tea_n_i(tea_n), .xats_n_i(1'b1), .xats_n_o()
  );
  /* verilator lint_on PINCONNECTEMPTY */
  bus60x_scripted_target_bfm #(.BASE_ADDR(BASE),.MEM_BYTES(FW_MEM_BYTES)) target(
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

  always @(posedge clk)begin
    cycles++;
    if(rst_n)begin
      check(cycles<2000000,"machine-check firmware watchdog");
      check(!ifetch_error&&!pimem_error&&!protocol_error&&!translation_fault,
        "TEA or translation took a diagnostic path");
      check((mode==1)||(!halted&&!checkstop),"unexpected halt or checkstop");
      if(addr_oe&&ts_oe&&!ts_n)begin
        check(abb_oe&&!abb_n&&bus_busy&&wt_n&&gbl_n&&cse==0&&bus_a>=BASE,
          "address ownership and range");
        if(tc!=2)check(tbst_n&&!ci_n,"scalar inhibited data");
        if({bus_a[31:8],8'b0}==BASE+32'h200)vector_fetches++;
      end
      if(cache_hit)cache_hits++;
      if(cache_miss)cache_misses++;
      // Mirror each written word so the mailbox rule sees it.
      if(!ta_n&&dbb_oe&&tt==5'b00010&&bus_a>=BASE&&bus_a<BASE+32'(FW_MEM_BYTES))begin
        int size;
        size=(tsiz==0)?8:int'(tsiz);
        check(bus_a<TEA_BASE||bus_a>=TEA_END,"write completed inside the TEA window");
        for(int k=0;k<size;k++)
          mem[int'(bus_a-BASE)+k]=data_out[63-8*(int'(bus_a[2:0])+k) -:8];
        mailbox_store(bus_a,size==4);
      end
      if(tv&&tr)begin
        retires++;
        check(^retired!==1'bx&&!retired.illegal,"known legal retirement");
        if(retired.pc==BASE+32'h200)mc_entries++;
        if(retired.pc==BASE+32'hd00)trace_entries++;
        if(retired.pc==BASE+32'h1300)iabr_entries++;
        if(retired.data_fault==DATA_MACHINE_CHECK)
          check(!retired.gpr_write&&!retired.update_write,"machine-checked access wrote a register");
        mailbox_retire();
      end
    end
  end
  assert property(@(posedge clk) disable iff(!rst_n)
    tv&&!tr |=> tv&&$stable(retired));

  always @(posedge clk)begin
    #2;
    bfm_wait=(rnd()%4==0)?int'(rnd()%4):0;
    bfm_retry=rnd()%100<10;
    bfm_drtry=rnd()%100<8;
    retire_enable=rnd()%8!=0;
    if(rst_n&&target.in_data&&target.burst&&hold_until<=cycles&&rnd()%100<5)begin
      hold_until=cycles+5+int'(rnd()%40);
      held_fills++;
    end
    bfm_hold=hold_until>cycles;
  end

  initial begin
    if(!$value$plusargs("MODE=%d",mode)||mode<0||mode>1)$fatal(1,"MODE 0..1 required");
    load_image();
    mem['hc000]=0;mem['hc001]=0;mem['hc002]=0;mem['hc003]=8'(mode);
    for(int i=0;i<FW_MEM_BYTES;i++)target.mem[i]=mem[i];
    target.tea_base=TEA_BASE;
    target.tea_bytes=TEA_END-TEA_BASE;
    repeat(4)@(negedge clk);rst_n=1;
    @(negedge clk);start_valid=1;
    do @(posedge clk);while(!start_ready);
    @(negedge clk);start_valid=0;
    check(running,"router running");
    if(mode==1)begin
      wait(checkstop);
      repeat(500)@(posedge clk);
      check(checkstop&&halted&&!mailbox_written&&mc_entries==0&&vector_fetches==0&&
            target.teas==1,"ME=0 TEA checkstops without a vector fetch");
      $display("PASS compiled machine check: mode=1 checkstop checks=%0d retires=%0d cycles=%0d teas=%0d",
        checks,retires,cycles,target.teas);
      $finish;
    end
    wait(mailbox_retired);
    repeat(20)@(posedge clk);
    check(mc_entries==3&&trace_entries==7&&iabr_entries==1&&target.teas>=3&&
          cache_hits>0&&cache_misses>0&&target.retries>0&&target.drtries>0&&
          cir&&cdr&&!cpr,"machine-check firmware coverage");
    $display("PASS compiled machine check: mode=0 checks=%0d retires=%0d cycles=%0d mc=%0d trace=%0d iabr=%0d teas=%0d retries=%0d drtries=%0d held=%0d hits=%0d misses=%0d",
      checks,retires,cycles,mc_entries,trace_entries,iabr_entries,target.teas,
      target.retries,target.drtries,held_fills,cache_hits,cache_misses);
    $finish;
  end
endmodule
