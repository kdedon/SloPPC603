// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Compiled cache-operation firmware on the translated cached 60x top. The
// pin target retries (ARTRY), replaces read beats (DRTRY), holds line fills
// and delays at random; EXT and external cache invalidation also arrive at
// random. The firmware checks its own results and reports through tohost.
/* verilator lint_off BLKSEQ */
module tb_compiled_cacheops_firmware;
  import ppc_pkg::*;
  logic clk=0,rst_n=0;
  always #5 clk=~clk;
  logic start_valid=0,start_ready,running,cir,cdr,cpr;
  logic tv,tr,halted,ifetch_error,protocol_error,bus_busy,pimem_error;
  logic irq=0,irq_taken,dec_taken,tick=0,translation_fault;
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
  logic maintenance_done_ready=0,maintenance_busy;
  logic bfm_retry=0,bfm_hold=0,bfm_drtry=0,retire_enable=1;
  int bfm_wait=0;
  int unsigned rng=32'h2468ace1;
  int cycles=0,retires=0,hold_until=0;
  int icbi_count=0,ext_count=0,dec_count=0,maintenance_commands=0;
  int align_entries=0,dsi_entries=0,cache_hits=0,cache_misses=0,held_fills=0;
  int busy_cycles=0,maintenance_busy_cycles=0;
  localparam int FW_MEM_BYTES=65536;
  function automatic string check_detail();
    return $sformatf(" bus=%08x icbi=%0d",bus_a,icbi_count);
  endfunction
  `include "compiled_firmware.svh"

  /* verilator lint_off PINCONNECTEMPTY */
  logic unused_checkstop;
  ppc_core_bat_cached_bus60x #(.RETIRE_PAIRS(1'b0), .RESET_PC(32'hfff00100),.ENABLE_TEST_REDIRECT(1'b0),
    .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),.ENABLE_LIVE_CONTEXT(1'b1),
    .ENABLE_RUNTIME_BAT(1'b1),.ENABLE_EXTERNAL_INTERRUPTS(1'b1),
    .ENABLE_TIMERS(1'b1),.ENABLE_CACHE_INSTRUCTIONS(1'b1)) dut(.dbw32_i(1'b0), .bus_ce_i(1'b1),
    .perf_o(),
    .clk_i(clk),.rst_ni(rst_n),
    .external_irq_i(irq),.interrupt_taken_o(irq_taken),.interrupt_pc_o(irq_pc),
    .timer_tick_i(tick),.timebase_enable_i(1'b1),
    .pin_event_i('0), .pin_status_o(),
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
    .translation_fault_o(translation_fault),.fault_instruction_o(),.fault_write_o(),
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
    .cache_enabled_o(cache_enabled),.dcache_busy_o(),
    .maintenance_busy_o(maintenance_busy),
    .br_n_o(br_n),.bg_n_i(bg_n),.abb_n_i(1'b1),
    .abb_n_o(abb_n),.abb_oe_o(abb_oe),.ts_n_o(ts_n),.ts_oe_o(ts_oe),
    .a_o(bus_a),.tt_o(tt),.tbst_n_o(tbst_n),.tsiz_o(tsiz),
    .tc_o(tc),.ci_n_o(ci_n),.wt_n_o(wt_n),.gbl_n_o(gbl_n),
    .cse_o(cse),.addr_oe_o(addr_oe),.aack_n_i(aack_n),
    .snoop_ts_n_i(1'b1),.snoop_a_i(32'b0),.snoop_tt_i(5'b0),.snoop_tbst_n_i(1'b1), .snoop_probe_i(1'b0),.snoop_gbl_n_i(1'b1),.artry_n_o(),.artry_oe_o(),.artry_n_i(artry_n),.dbwo_n_i(1'b1), .dbg_n_i(dbg_n),.dbb_n_i(1'b1),
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
      check(cycles<3000000,"cache-operation firmware watchdog");
      check(!halted&&!ifetch_error&&!pimem_error&&!protocol_error&&!translation_fault,
        "unexpected transport, translation or core diagnostic");
      if(addr_oe&&ts_oe&&!ts_n)begin
        check(abb_oe&&!abb_n&&bus_busy&&wt_n&&gbl_n&&cse==0&&bus_a>=BASE,
          "address ownership and range");
        if(tc!=2)check(tbst_n&&!ci_n,"scalar inhibited data");
      end
      if(cache_hit)cache_hits++;
      if(cache_miss)cache_misses++;
      if(cache_busy)busy_cycles++;
      if(maintenance_busy)maintenance_busy_cycles++;
      if(maintenance_done_valid)check(cache_enabled,"invalidation keeps the cache enabled");
      if(dut.icbi_req_valid&&dut.icbi_req_ready)icbi_count++;
      if(irq_taken)begin
        ext_count++;
        check(irq&&irq_pc>=BASE,"accepted EXT");
        irq<=0;
      end
      if(dec_taken)begin
        dec_count++;
        check(dec_pc>=BASE,"accepted DEC");
      end
      // Mirror each written word so the mailbox rule sees it.
      if(!ta_n&&dbb_oe&&tt==5'b00010&&bus_a>=BASE&&bus_a<BASE+32'(FW_MEM_BYTES))begin
        int size;
        size=(tsiz==0)?8:int'(tsiz);
        for(int k=0;k<size;k++)
          mem[int'(bus_a-BASE)+k]=data_out[63-8*(int'(bus_a[2:0])+k) -:8];
        mailbox_store(bus_a,size==4);
      end
      if(tv&&tr)begin
        retires++;
        check(^retired!==1'bx&&!retired.illegal,"known legal retirement");
        if(retired.pc==BASE+32'h600)align_entries++;
        if(retired.pc==BASE+32'h300)dsi_entries++;
        mailbox_retire();
      end
    end
  end
  assert property(@(posedge clk) disable iff(!rst_n)
    tv&&!tr |=> tv&&$stable(retired));

  always @(posedge clk)begin
    #2;
    tick<=1'b1;
    bfm_wait=(rnd()%4==0)?int'(rnd()%4):0;
    bfm_retry=rnd()%100<10;
    bfm_drtry=rnd()%100<8;
    retire_enable=rnd()%8!=0;
    if(rst_n&&target.in_data&&target.burst&&hold_until<=cycles&&rnd()%100<5)begin
      hold_until=cycles+5+int'(rnd()%40);
      held_fills++;
    end
    if(rst_n&&dut.icbi_req_valid&&target.in_data&&target.burst&&
       hold_until<=cycles&&rnd()%2==0)
      hold_until=cycles+8+int'(rnd()%16);
    bfm_hold=hold_until>cycles;
    if(rst_n&&running&&!irq&&!mailbox_written&&rnd()%3000==0)irq=1;
  end

  initial begin : maintenance_control
    wait(rst_n&&running);
    forever begin
      repeat(4000+int'(rnd()%8000))@(posedge clk);
      if(mailbox_written)break;
      @(negedge clk);
      maintenance_valid=1;
      #1;
      while(!maintenance_ready)begin @(negedge clk);#1;end
      @(posedge clk);
      @(negedge clk);
      maintenance_valid=0;
      maintenance_commands++;
      while(!maintenance_done_valid)@(negedge clk);
      repeat(int'(rnd()%20))@(negedge clk);
      maintenance_done_ready=1;
      @(posedge clk);
      @(negedge clk);
      maintenance_done_ready=0;
    end
  end

  initial begin
    load_image();
    for(int i=0;i<FW_MEM_BYTES;i++)target.mem[i]=mem[i];
    repeat(4)@(negedge clk);rst_n=1;
    @(negedge clk);start_valid=1;
    do @(posedge clk);while(!start_ready);
    @(negedge clk);start_valid=0;
    wait(mailbox_retired);
    repeat(20)@(posedge clk);
    check(icbi_count>=64&&align_entries==1&&dsi_entries==5&&dec_count>0&&
          cache_hits>0&&cache_misses>0&&target.retries>0&&target.drtries>0&&
          held_fills>0&&busy_cycles>0&&cir&&cdr&&!cpr,"cache-operation firmware coverage");
    $display("PASS compiled cache operations: checks=%0d retires=%0d cycles=%0d icbi=%0d ext=%0d dec=%0d maint=%0d retries=%0d drtries=%0d held=%0d hits=%0d misses=%0d",
      checks,retires,cycles,icbi_count,ext_count,dec_count,maintenance_commands,
      target.retries,target.drtries,held_fills,cache_hits,cache_misses);
    $finish;
  end
endmodule
