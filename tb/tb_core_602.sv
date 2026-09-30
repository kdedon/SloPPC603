// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
// 602 core on the cached 60x wrapper: the 4 KiB two-way instruction cache
// fills and hits from reset with HID0 clear, HID0 bit 16 neither stores nor
// disables it, ICFI invalidates it, and PVR and multiply results are the
// 602's.
/* verilator lint_off BLKSEQ */
module tb_core_602;
  import ppc_pkg::*;
  logic clk=0,rst_n=0;
  always #5 clk=~clk;
  // Wrapper outputs this instruction-only program does not inspect.
  /* verilator lint_off UNUSEDSIGNAL */
  logic running,bus_busy,data_oe,cache_busy;
  logic [2:0] tsiz;
  logic [63:0] data_out;
  logic maintenance_done_valid,maintenance_busy;
  /* verilator lint_on UNUSEDSIGNAL */
  logic start_valid=0,start_ready,cir,cdr,cpr;
  logic tv,tr,halted,ifetch_error,protocol_error,pimem_error,redirect_accepted;
  retire_packet_t retired;
  logic br_n,bg_n,abb_n,abb_oe,ts_n,ts_oe,tbst_n,ci_n,wt_n,gbl_n,addr_oe;
  logic [31:0] bus_a;
  logic [4:0] tt;
  logic [1:0] tc,cse;
  logic aack_n,artry_n,dbg_n,dbb_n,dbb_oe,ta_n,drtry_n,tea_n;
  logic [63:0] data_in;
  logic cache_hit,cache_miss,cache_enabled,unused_maintenance_ready;
  int cycles=0,checks=0,retires=0,line_bursts=0,scalar_fetches=0;
  int line0_fills=0,hits_before_hid0=0,hits_after_hid0=0,cache_misses=0;
  logic hid0_written=0,done=0;
  logic [31:0] hid0_reset_value;

  function automatic logic [31:0] imm(input int op,input int rt,input int ra,input int value);
    return (32'(op)<<26)|(32'(rt)<<21)|(32'(ra)<<16)|(32'(value)&32'hffff);
  endfunction
  function automatic logic [31:0] spr(input bit write_spr,input int rt,input int number);
    return (write_spr?32'h7c0003a6:32'h7c0002a6)|(32'(rt)<<21)|
      ((32'(number)&31)<<16)|((32'(number)>>5)<<11);
  endfunction
  function automatic logic [31:0] xo(input int rt,input int ra,input int rb,input int op);
    return (32'd31<<26)|(32'(rt)<<21)|(32'(ra)<<16)|(32'(rb)<<11)|(32'(op)<<1);
  endfunction
  function automatic logic [31:0] bne(input int from,input int to);
    return (32'd16<<26)|(32'd4<<21)|(32'd2<<16)|(32'(to-from)&32'hfffc);
  endfunction
  function automatic logic [31:0] br(input int from,input int to);
    return (32'd18<<26)|(32'(to-from)&32'h03fffffc);
  endfunction
  // Real mode; HID0[WIMG] = 0 makes every fetch cacheable. The loop runs
  // twice: before and after an ICFI flash invalidate.
  function automatic logic [31:0] insn_at(input int a);
    case(a)
      'h00:return imm(14,14,0,0);          // pass = 0
      'h04:return imm(14,3,0,0);
      'h08:return imm(14,3,3,1);
      'h0c:return imm(11,0,3,3);           // cmpwi r3,3
      'h10:return bne('h10,'h08);
      'h14:return imm(11,0,14,0);          // cmpwi r14,0
      'h18:return bne('h18,'h80);
      'h1c:return spr(0,4,1008);           // mfspr r4,HID0
      'h20:return imm(24,4,5,'h8000);      // ori r5,r4,0x8000 (bit 16)
      'h24:return spr(1,5,1008);
      'h28:return 32'h4c00012c;            // isync
      'h2c:return spr(0,6,1008);
      'h30:return spr(0,7,287);            // PVR
      'h34:return imm(14,8,0,-3);
      'h38:return imm(7,9,8,100);          // mulli r9,r8,100
      'h3c:return imm(15,10,0,'h0123);
      'h40:return imm(24,10,10,'h4567);
      'h44:return xo(11,10,10,235);        // mullw
      'h48:return xo(12,10,8,11);          // mulhwu
      'h4c:return imm(24,4,13,'h0800);     // ori r13,r4,ICFI
      'h50:return spr(1,13,1008);
      'h54:return spr(1,4,1008);
      'h58:return 32'h4c00012c;
      'h5c:return imm(14,14,0,1);
      'h60:return br('h60,'h04);
      'h80:return br('h80,'h80);
      default:return 32'h60000000;
    endcase
  endfunction
  function automatic logic [63:0] line_dw(input logic [31:0] base,input int slot);
    logic [63:0] value;
    value=0;
    for(int lane=0;lane<8;lane++)
      value[63-8*lane -:8]=target.mem[int'(base)+slot*8+lane];
    return value;
  endfunction
  task automatic check(input bit ok,input string why);
    checks++;
    if(!ok)$fatal(1,"%s cycle=%0d retire=%0d pc=%08x value=%08x bus=%08x",
      why,cycles,retires,retired.pc,retired.value,bus_a);
  endtask
  task automatic put_word(input int address,input logic [31:0] value);
    for(int k=0;k<4;k++)target.mem[address+k]=value[31-k*8 -:8];
  endtask

  /* verilator lint_off PINCONNECTEMPTY */
  logic unused_checkstop;
  ppc_core_bat_cached_bus60x #(.RESET_PC(32'b0),.CPU_VARIANT(CPU_602),
    .RESET_CACHE_ENABLE(1'b0),.ENABLE_FULL_DECODE(1'b1),
    .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1),.ENABLE_RUNTIME_BAT(1'b1)) dut(.bus_ce_i(1'b1),
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
    .checkstop_o(unused_checkstop), .halted_o(halted),.redirect_valid_i(1'b0),.redirect_all_i(1'b0),
    .redirect_keep_pivot_i(1'b0),.redirect_pivot_i('0),
    .redirect_target_i('0),.redirect_accepted_o(redirect_accepted),
    .translation_fault_o(),.fault_instruction_o(),.fault_write_o(),
    .fault_ea_o(),.fault_miss_o(),.fault_protection_o(),
    .fault_guarded_o(),.fault_config_o(),.fault_invalid_input_o(),
    .fault_invalid_entry_o(),.pimem_error_o(pimem_error),
    .busy_o(),.ifetch_error_o(ifetch_error),
    .bus_protocol_error_o(protocol_error),.bus_busy_o(bus_busy),
    .icache_hit_o(cache_hit),.icache_miss_o(cache_miss),
    .icache_busy_o(cache_busy),
    .maintenance_valid_i(1'b0),.maintenance_ready_o(unused_maintenance_ready),
    .maintenance_invalidate_i(1'b0),.maintenance_cache_enable_i(1'b1),
    .maintenance_done_valid_o(maintenance_done_valid),
    .maintenance_done_ready_i(1'b0),.cache_enabled_o(cache_enabled),
    .dcache_busy_o(),
    .maintenance_busy_o(maintenance_busy),
    .br_n_o(br_n),.bg_n_i(bg_n),.abb_n_i(1'b1),
    .abb_n_o(abb_n),.abb_oe_o(abb_oe),.ts_n_o(ts_n),.ts_oe_o(ts_oe),
    .a_o(bus_a),.tt_o(tt),.tbst_n_o(tbst_n),.tsiz_o(tsiz),
    .tc_o(tc),.ci_n_o(ci_n),.wt_n_o(wt_n),.gbl_n_o(gbl_n),
    .cse_o(cse),.addr_oe_o(addr_oe),.aack_n_i(aack_n),
    .snoop_ts_n_i(1'b1),.snoop_a_i(32'b0),.snoop_tt_i(5'b0),.snoop_gbl_n_i(1'b1),.artry_n_o(),.artry_oe_o(),.artry_n_i(artry_n),.dbg_n_i(dbg_n),.dbb_n_i(1'b1),
    .dbb_n_o(dbb_n),.dbb_oe_o(dbb_oe),
    .d_i(data_in),.d_o(data_out),.d_oe_o(data_oe),
    .ta_n_i(ta_n),.drtry_n_i(drtry_n),.tea_n_i(tea_n)
  );
  /* verilator lint_on PINCONNECTEMPTY */
  bus60x_target_bfm #(.BASE_ADDR(32'b0),.MEM_BYTES(8192)) target(.bus_ce_i(1'b1),
    .clk_i(clk),.br_n_i(br_n),.abb_n_i(abb_n),.abb_oe_i(abb_oe),
    .ts_n_i(ts_n),.ts_oe_i(ts_oe),.a_i(bus_a),
    .dbb_n_i(dbb_n),.dbb_oe_i(dbb_oe),.bg_n_o(bg_n),
    .aack_n_o(aack_n),.artry_n_o(artry_n),.dbg_n_o(dbg_n),
    .d_o(data_in),.ta_n_o(ta_n),.drtry_n_o(drtry_n),.tea_n_o(tea_n)
  );
  assign tr=rst_n&&cycles%5!=2;

  always @(posedge clk)begin
    cycles++;
    if(rst_n)begin
      check(cycles<20000,"602 core watchdog");
      check(!halted&&!ifetch_error&&!pimem_error&&!protocol_error&&
            !redirect_accepted&&!cir&&!cdr&&!cpr,
            "unexpected fault, redirect, translation or PR");
      check(cache_enabled,"602 instruction cache disabled");
      if(cache_hit)begin
        if(hid0_written)hits_after_hid0++;
        else hits_before_hid0++;
      end
      if(cache_miss)cache_misses++;
      if(addr_oe&&ts_oe&&!ts_n)begin
        check(tc==2&&wt_n&&gbl_n&&cse<2,
              "602 program makes instruction fetches only");
        if(!tbst_n)begin
          check(tt==5'b01110&&ci_n&&bus_a<8192,"instruction line fill shape");
          line_bursts++;
          if((bus_a&32'hffffffe0)==0)line0_fills++;
        end else scalar_fetches++;
      end
      if(tv&&tr)begin
        check(retired.insn==insn_at(int'(retired.pc))&&!retired.illegal&&
              retired.fetch_fault==FETCH_OK&&retired.data_fault==DATA_OK,
              "retired word or fault");
        case(retired.pc)
          'h1c:hid0_reset_value=retired.value;
          'h24:hid0_written=1;
          'h2c:check(retired.value==hid0_reset_value&&!retired.value[15],
                     "HID0 bit 16 stored on the 602");
          'h30:check(retired.value==32'h0005_0101,"602 PVR");
          'h38:check(retired.value==32'hffff_fed4,"mulli");
          'h44:check(retired.value==32'hdafa_af71,"mullw");
          'h48:check(retired.value==32'h0123_4566,"mulhwu");
          'h80:done=1;
          default:;
        endcase
        retires++;
      end
    end
  end
  assert property(@(posedge clk) disable iff(!rst_n)
    tv&&!tr |=> tv&&$stable(retired));

  initial begin
    check(dut.IC_SETS==64&&dut.IC_WAYS==2&&dut.DC_SETS==64&&dut.DC_WAYS==2,
          "602 cache geometry");
    for(int a=0;a<='h80;a+=4)put_word(a,insn_at(a));
    repeat(4)@(negedge clk);rst_n=1;
    @(negedge clk);start_valid=1;
    do @(posedge clk);while(!start_ready);
    @(negedge clk);start_valid=0;
    forever begin : bus_target
      logic [31:0] line_base;
      int critical;
      target.grant_address(1,1,1'b0,1'b0);
      target.grant_data(1);
      if(!tbst_n)begin
        line_base=bus_a&32'hffffffe0;
        critical=int'(bus_a[4:3]);
        for(int beat=0;beat<4;beat++)
          target.sample_ta(line_dw(line_base,(critical+beat)%4));
      end else target.acknowledge_normal_read(1);
    end
  end
  initial begin
    wait(done);@(negedge clk);
    check(scalar_fetches==0&&hits_before_hid0>0&&hits_after_hid0>0&&
          line0_fills==2&&cache_misses>0,
          "602 fill from reset, hits, or ICFI refill");
    $display("PASS 602 core: retires=%0d line=%0d line0=%0d hits=%0d/%0d miss=%0d HID0=%08x checks=%0d",
      retires,line_bursts,line0_fills,hits_before_hid0,hits_after_hid0,
      cache_misses,hid0_reset_value,checks);
    $finish;
  end
endmodule
