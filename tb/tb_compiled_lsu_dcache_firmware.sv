// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
// The compiled load/store-extension firmware with the data cache in the
// translated cached top, on from reset, on one randomized 60x memory with
// instruction fetch. The mailbox is seen at the LSU port, since cached
// stores need not reach the bus; after the mailbox the bench flushes nothing
// and checks coverage.
/* verilator lint_off BLKSEQ */
module tb_compiled_lsu_dcache_firmware;
  localparam bit LSU_EXTENSIONS = 1'b1;
  import ppc_pkg::*;
  logic clk=0,rst_n=0;
  always #5 clk=~clk;
  logic start_valid=0,start_ready,running,cir,cdr,cpr;
  logic tv,tr,halted,unused_checkstop,ifetch_error,protocol_error,bus_busy,pimem_error;
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
  int align_entries=0,cache_hits=0,cache_misses=0,held_fills=0;
  int split_writes=0,partials=0;
  logic lsu_write;
  logic [31:0] lsu_addr,lsu_wdata;
  logic [3:0] lsu_wstrb;
  dmem_attr_t lsu_attr;
  localparam int FW_MEM_BYTES=65536;
  function automatic string check_detail();
    return $sformatf(" bus=%08x",bus_a);
  endfunction
  `define FW_DUMP_ARRAY target.mem
  logic dc_busy,snoop_ts_n,snoop_gbl_n,cpu_artry_n,cpu_artry_oe;
  logic [31:0] snoop_a;
  logic [4:0] snoop_tt;
  int dc_hits=0,dc_misses=0;
  `include "compiled_firmware.svh"

  /* verilator lint_off PINCONNECTEMPTY */
  ppc_core_bat_cached_bus60x #(.RESET_PC(32'hfff00100),.ENABLE_TEST_REDIRECT(1'b0),
    .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),.ENABLE_LIVE_CONTEXT(1'b1),
    .ENABLE_EXTERNAL_INTERRUPTS(1'b1),.ENABLE_TIMERS(1'b1),
    .ENABLE_RUNTIME_BAT(1'b1),.ENABLE_SEGMENT_REGISTERS(1'b1),
    .ENABLE_SDR1(1'b1),.ENABLE_TGPR(1'b1),.ENABLE_TLB_MISS_EXCEPTIONS(1'b1),
    .ENABLE_PAGE_TRANSLATION(1'b1),.ENABLE_PAGE_MISS_RESULTS(1'b1),
    .ENABLE_PAGE_DATA_EXCEPTIONS(1'b1),.ENABLE_PAGE_INSTRUCTION_EXCEPTIONS(1'b1),
    .ENABLE_TLB_INVALIDATE(1'b1),.ENABLE_TLB_LOAD(1'b1),
    .ENABLE_CACHE_INSTRUCTIONS(1'b1),
    .ENABLE_BYTE_REVERSE(LSU_EXTENSIONS),.ENABLE_MULTIPLE_STRING(LSU_EXTENSIONS),
    .ENABLE_RESERVATION(LSU_EXTENSIONS),.ENABLE_MISALIGNED_ACCESS(LSU_EXTENSIONS),
    .ENABLE_MACHINE_CHECK(1'b1),.ENABLE_PIN_INTERRUPTS(1'b1),
    .ENABLE_DCACHE(1'b1),.RESET_DCACHE_ENABLE(1'b1)) dut(
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
    .halted_o(halted),.checkstop_o(unused_checkstop),.redirect_valid_i(1'b0),.redirect_all_i(1'b0),
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
    .cache_enabled_o(cache_enabled),.dcache_busy_o(dc_busy),
    .maintenance_busy_o(maintenance_busy),
    .br_n_o(br_n),.bg_n_i(bg_n),.abb_n_i(1'b1),
    .abb_n_o(abb_n),.abb_oe_o(abb_oe),.ts_n_o(ts_n),.ts_oe_o(ts_oe),
    .a_o(bus_a),.tt_o(tt),.tbst_n_o(tbst_n),.tsiz_o(tsiz),
    .tc_o(tc),.ci_n_o(ci_n),.wt_n_o(wt_n),.gbl_n_o(gbl_n),
    .cse_o(cse),.addr_oe_o(addr_oe),.aack_n_i(aack_n),
    .snoop_ts_n_i(snoop_ts_n),.snoop_a_i(snoop_a),.snoop_tt_i(snoop_tt),.snoop_gbl_n_i(snoop_gbl_n),
    .artry_n_o(cpu_artry_n),.artry_oe_o(cpu_artry_oe),
    .artry_n_i(artry_n),.dbg_n_i(dbg_n),.dbb_n_i(1'b1),
    .dbb_n_o(dbb_n),.dbb_oe_o(dbb_oe),
    .d_i(data_in),.d_o(data_out),.d_oe_o(data_oe),
    .ta_n_i(ta_n),.drtry_n_i(drtry_n),.tea_n_i(tea_n)
  );
  /* verilator lint_on PINCONNECTEMPTY */
  bus60x_coherent_bfm #(.BASE_ADDR(BASE),.MEM_BYTES(FW_MEM_BYTES)) target(
    .clk_i(clk),.br_n_i(br_n),.ts_n_i(ts_n),.ts_oe_i(ts_oe),.a_i(bus_a),
    .tt_i(tt),.tbst_n_i(tbst_n),.tsiz_i(tsiz),.tc_i(tc),.ci_n_i(ci_n),.wt_n_i(wt_n),
    .gbl_n_i(gbl_n),.dbb_n_i(dbb_n),.dbb_oe_i(dbb_oe),.d_i(data_out),.d_oe_i(data_oe),
    .artry_n_i(cpu_artry_n),.artry_oe_i(cpu_artry_oe),
    .retry_i(bfm_retry),.hold_i(bfm_hold),.drtry_i(bfm_drtry),.wait_i(bfm_wait),
    .bg_n_o(bg_n),.aack_n_o(aack_n),.artry_n_o(artry_n),.dbg_n_o(dbg_n),
    .d_o(data_in),.ta_n_o(ta_n),.drtry_n_o(drtry_n),.tea_n_o(tea_n),
    .bus_ts_n_o(snoop_ts_n),.bus_a_o(snoop_a),.bus_tt_o(snoop_tt),.bus_gbl_n_o(snoop_gbl_n)
  );
  assign tr=rst_n&&retire_enable;
  // Interrupt, cache-status and maintenance outputs are idle in this profile.
  logic unused_outputs;
  assign unused_outputs=^{running,irq_pc,dec_pc,cache_busy,cache_enabled,
                          maintenance_ready,maintenance_done_valid,maintenance_busy,dc_busy,
                          lsu_attr.rid};

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
        check(abb_oe&&!abb_n&&bus_busy&&cse==0&&bus_a>=BASE,
          "address ownership and range");
      end
      if(cache_hit)cache_hits++;
      if(cache_miss)cache_misses++;
      check(!irq_taken&&!dec_taken,"no interrupt source is active");
      if(dut.dcache_slot.g_cache.dc_hit)dc_hits++;
      if(dut.dcache_slot.g_cache.dc_miss)dc_misses++;
      // Mirror each store at the LSU port so the mailbox rule sees it.
      if(dut.dcache_slot.lsu_req_valid_i&&dut.dcache_slot.lsu_req_ready_o)begin
        lsu_write=dut.dcache_slot.lsu_req_write_i;lsu_addr=dut.dcache_slot.lsu_req_addr_i;
        lsu_wdata=dut.dcache_slot.lsu_req_wdata_i;lsu_wstrb=dut.dcache_slot.lsu_req_wstrb_i;
        lsu_attr=dut.dcache_slot.lsu_req_attr_i;
        if(lsu_write&&lsu_attr.kind!=DMEM_CACHE&&(lsu_wstrb==4'b1110||lsu_wstrb==4'b0111))
          split_writes++;
      end
      if(dut.dcache_slot.lsu_rsp_valid_o&&dut.dcache_slot.lsu_rsp_ready_i&&lsu_write&&
         lsu_attr.kind!=DMEM_CACHE&&!dut.dcache_slot.lsu_rsp_error_o&&
         (lsu_attr.kind!=DMEM_ATOMIC||dut.dcache_slot.lsu_rsp_rdata_o[0]))begin
        int first;
        first=-1;
        for(int k=0;k<4;k++)if(lsu_wstrb[3-k])begin
          mem[int'(lsu_addr-BASE)+k]=lsu_wdata[31-8*k -:8];
          if(first<0)first=k;
        end
        mailbox_store(lsu_addr+32'(first),lsu_wstrb==4'hf);
      end
      if(tv&&tr)begin
        retires++;
        check(^retired!==1'bx&&!retired.illegal,"known legal retirement");
        if(retired.pc==BASE+32'h600)align_entries++;
        if(retired.seq_partial)partials++;
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
    bfm_hold=hold_until>cycles;
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
    check(align_entries==2&&partials>0&&split_writes>0&&dc_hits>0&&dc_misses>0&&
          target.n_read_burst>0&&!cir&&!cdr&&!cpr,
          $sformatf("coverage align=%0d partial=%0d three_byte=%0d hits=%0d retries=%0d drtries=%0d ctx=%0d%0d%0d",
                    align_entries,partials,split_writes,cache_hits,target.retries,
                    target.drtries,cir,cdr,cpr));
    $display("PASS compiled load/store extensions with data cache: checks=%0d retires=%0d partial=%0d cycles=%0d align=%0d three_byte_stores=%0d dcache_hits=%0d dcache_misses=%0d fills=%0d castouts=%0d single_reads=%0d single_writes=%0d icache_hits=%0d icache_misses=%0d held=%0d",
      checks,retires,partials,cycles,align_entries,split_writes,dc_hits,dc_misses,
      target.n_read_burst,target.n_write_burst,target.n_read_single,target.n_write_single,
      cache_hits,cache_misses,held_fills);
    $finish;
  end
endmodule
