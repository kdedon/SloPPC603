// CPU-driven BAT remap, explicit cache maintenance, and warmed-line denial.
/* verilator lint_off BLKSEQ */
module tb_core_bat_cached_bus60x_coherence;
  import ppc_pkg::*;
  logic clk=0,rst_n=0;
  always #5 clk=~clk;
  logic start_valid=0,start_ready,running,cir,cdr,cpr;
  logic tv,tr,halted,ifetch_error,protocol_error,bus_busy,pimem_error;
  logic redirect_valid=0,redirect_accepted;
  logic [31:0] redirect_target=0;
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
  int cycles=0,checks=0,retires=0,offers=0,old_lines=0,new_lines=0;
  int alias_runs=0,physical_store=0,denied_baseline=-1;
  int stale_hits=0,retire_stalls=0,cache_misses=0,cache_busy_cycles=0;
  logic fresh_seen=0,denied_seen=0,redirect_phase=0;

  function automatic logic [31:0] imm(input int op,input int rt,input int ra,input int value);
    return (32'(op)<<26)|(32'(rt)<<21)|(32'(ra)<<16)|(32'(value)&32'hffff);
  endfunction
  function automatic logic [31:0] spr(input bit wr,input int rt,input int number);
    return (wr?32'h7c0003a6:32'h7c0002a6)|(32'(rt)<<21)|
      ((32'(number)&31)<<16)|((32'(number)>>5)<<11);
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
    if(!ok)$fatal(1,"%s cycle=%0d retire=%0d pc=%08x bus=%08x alias=%0d",
      why,cycles,retires,retired.pc,bus_a,alias_runs);
  endtask
  task automatic put_word(input int address,input logic [31:0] value);
    for(int k=0;k<4;k++)target.mem[address+k]=value[31-k*8 -:8];
  endtask
  function automatic logic [31:0] program_word(input int a);
    case(a)
      0:return imm(14,3,0,2);
      4:return spr(1,3,529); 8:return spr(1,3,528);
      12:return spr(1,3,531);
      16:return imm(15,4,0,'h1000);20:return imm(24,4,4,2);
      24:return spr(1,4,530);
      28:return imm(15,4,0,2);32:return imm(24,4,4,2);
      36:return spr(1,4,539);
      40:return imm(15,4,0,'h3000);44:return imm(24,4,4,2);
      48:return spr(1,4,538);
      52:return (32'd31<<26)|(32'd6<<21)|(32'd83<<1);
      56:return imm(24,6,6,'h30);
      60:return (32'd31<<26)|(32'd6<<21)|(32'd146<<1);
      64:return 32'h4c00012c;
      68:return imm(14,15,0,'h180);
      72:return imm(15,7,0,'h1000);76:return imm(24,7,7,'h100);
      80:return spr(1,7,9);84:return 32'h4e800420;
      'h180:return imm(15,4,0,2);
      'h184:return imm(24,4,4,2);
      'h188:return spr(1,4,531); // remap same EA to PA 0x20000
      'h18c:return imm(14,15,0,'h1c0);
      'h190:return imm(15,7,0,'h1000);
      'h194:return imm(24,7,7,'h100);
      'h198:return spr(1,7,9);
      'h19c:return 32'h4e800420;
      'h1c0:return imm(15,9,0,'h3000);
      'h1c4:return imm(15,10,0,'h39c0);
      'h1c8:return imm(24,10,10,'h21);
      'h1cc:return imm(36,10,9,'h100); // physical 0x20100 gets new code
      'h1d0:return 32'h7c0004ac; // sync
      'h1d4:return 32'h4c00012c; // isync, no cache invalidation
      'h1d8:return imm(14,15,0,'h1f0);
      'h1dc:return imm(15,7,0,'h1000);
      'h1e0:return imm(24,7,7,'h100);
      'h1e4:return spr(1,7,9);
      'h1e8:return 32'h4e800420;
      'h1f0:return 32'h48000000; // maintenance rendezvous
      'h240:return imm(14,15,0,'h280);
      'h244:return imm(15,7,0,'h1000);
      'h248:return imm(24,7,7,'h100);
      'h24c:return spr(1,7,9);
      'h250:return 32'h4e800420;
      'h280:return imm(15,4,0,2);
      'h284:return spr(1,4,531); // PP 00 denies warmed I-cache line
      'h288:return imm(14,15,0,'h2c0);
      'h28c:return imm(15,7,0,'h1000);
      'h290:return imm(24,7,7,'h100);
      'h294:return spr(1,7,9);
      'h298:return 32'h4e800420;
      'h2c0:return 32'h48000000; // forbidden arrival
      'h100:return imm(14,14,0,11);
      'h104:return spr(1,15,9);
      'h108:return 32'h4e800420;
      'h20100:return imm(14,14,0,22);
      'h20104:return spr(1,15,9);
      'h20108:return 32'h4e800420;
      default:return 32'h60000000;
    endcase
  endfunction

  /* verilator lint_off PINCONNECTEMPTY */
  ppc_core_bat_cached_bus60x #(.RESET_PC(32'b0),
    .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),.ENABLE_LIVE_CONTEXT(1'b1),
    .ENABLE_RUNTIME_BAT(1'b1)) dut(
    .clk_i(clk),.rst_ni(rst_n),
    .external_irq_i(1'b0),.interrupt_taken_o(),.interrupt_pc_o(),
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
    .halted_o(halted),.redirect_valid_i(redirect_valid),
    .redirect_all_i(redirect_valid),.redirect_keep_pivot_i(1'b0),
    .redirect_pivot_i('0),.redirect_target_i(redirect_target),
    .redirect_accepted_o(redirect_accepted),
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
  bus60x_target_bfm #(.BASE_ADDR(32'b0),.MEM_BYTES(196608)) target(
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
      check(cycles<20000,"coherence watchdog");
      check(!halted&&!ifetch_error&&!pimem_error&&!protocol_error&&
            (!running||!cpr),"unexpected transport or privilege state");
      if(tv&&!tr)retire_stalls++;
      if(cache_miss)cache_misses++;
      if(cache_busy)cache_busy_cycles++;
      if(addr_oe&&ts_oe&&!ts_n)begin
        offers++;
        check(abb_oe&&!abb_n&&bus_busy&&wt_n&&gbl_n&&cse==0,
          "scalar/line address attributes");
        if(!tbst_n)begin
          check(tt==5'b01110&&tsiz==2&&tc==2&&ci_n,
            "line-burst shape");
          if((bus_a&32'hffffffe0)==32'h100)old_lines++;
          if((bus_a&32'hffffffe0)==32'h20100)new_lines++;
        end else if(tc==2)check(!ci_n,"scalar instruction bypass shape");
        if(denied_baseline>=0)
          check((bus_a&32'hffffffe0)!=32'h20100,
            "denied warmed physical line accessed");
      end
      if(denied_baseline>=0)begin
        check(!(dut.imem_req_valid&&dut.imem_req_addr==32'h20100),
          "denied physical fetch was offered to cache routing");
        check(!(dut.managed_fetch_valid&&dut.imem_req_addr==32'h20100),
          "denied physical fetch probed the cache");
      end
      if(!ta_n&&dbb_oe&&tt==5'b00010)begin
        check(data_oe&&bus_a==32'h20100&&tsiz==4&&
              data_out[63:32]==32'h39c00021,
          "CPU store did not update mapped physical instruction");
        for(int k=0;k<4;k++)target.mem[int'(bus_a)+k]=
          data_out[63-8*(int'(bus_a[2:0])+k) -:8];
        physical_store++;
      end
      if(cache_hit&&alias_runs>=2&&alias_runs<3)stale_hits++;
      if(tv&&tr)begin
        retires++;
        if(retired.pc==32'h10000100&&retired.fetch_fault==FETCH_OK)begin
          check(cir&&cdr&&!cpr,"alias retired outside translated supervisor mode");
          if(alias_runs==0)check(retired.insn==32'h39c0000b&&
            retired.gpr_write&&retired.gpr==14&&retired.value==11,
            "old PA instruction retired");
          if(alias_runs==1||alias_runs==2)check(retired.insn==32'h39c00016&&
            retired.gpr_write&&retired.gpr==14&&retired.value==22,
            "remapped/stale physical instruction retired");
          if(alias_runs==3)begin
            check(retired.insn==32'h39c00021&&retired.gpr_write&&
              retired.gpr==14&&retired.value==33,
              "post-maintenance fresh instruction retired");
            fresh_seen=1;
          end
          alias_runs++;
        end
        if(retired.pc==32'h284)begin
          check(fresh_seen&&new_lines>=2,"denial only after warm fresh line");
          denied_baseline=new_lines;
        end
        if(retired.pc==32'h10000100&&retired.fetch_fault==FETCH_ISI_PROTECTION)begin
          check(!retired.illegal&&retired.pc==32'h10000100&&
                alias_runs==4&&denied_baseline>=0&&
                new_lines==denied_baseline,
            "denied warmed line produced precise ISI without cache fill");
          denied_seen=1;
        end else if(retired.fetch_fault!=FETCH_OK)
          check(0,"unexpected instruction fault");
        if(retired.pc==32'h2c0)check(0,"denied code reached forbidden target");
      end
    end
  end
  assert property(@(posedge clk) disable iff(!rst_n)
    tv&&!tr |=> tv&&$stable(retired));

  initial begin
    for(int a=0;a<=84;a+=4)put_word(a,program_word(a));
    for(int a='h180;a<='h1f0;a+=4)put_word(a,program_word(a));
    for(int a='h240;a<='h250;a+=4)put_word(a,program_word(a));
    for(int a='h280;a<='h2c0;a+=4)put_word(a,program_word(a));
    for(int a='h100;a<='h108;a+=4)put_word(a,program_word(a));
    for(int a='h20100;a<='h20108;a+=4)put_word(a,program_word(a));
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
      end else if(tt==5'b00010)target.acknowledge_write(1);
      else target.acknowledge_normal_read(1);
    end
  end
  initial begin : maintenance_control
    int timeout;
    wait(alias_runs==3);
    timeout=0;
    while(!maintenance_ready&&timeout<2000)begin @(negedge clk);timeout++;end
    check(maintenance_ready,"maintenance command never ready");
    @(negedge clk);maintenance_valid=1;
    @(posedge clk);
    @(negedge clk);maintenance_valid=0;
    timeout=0;
    while(!maintenance_done_valid&&timeout<2000)begin @(negedge clk);timeout++;end
    check(maintenance_done_valid&&maintenance_busy,
      "maintenance completion did not hold");
    redirect_target=32'h240;redirect_valid=1;redirect_phase=1;
    timeout=0;
    while(!redirect_accepted&&timeout<500)begin @(negedge clk);timeout++;end
    check(redirect_accepted,"frontend redirect not accepted");
    @(posedge clk);
    @(negedge clk);redirect_valid=0;
    maintenance_done_ready=1;
    @(posedge clk);
    @(negedge clk);maintenance_done_ready=0;
    check(!maintenance_busy&&!maintenance_done_valid,
      "maintenance completion did not release");
  end
  initial begin
    wait(denied_seen);@(negedge clk);
    check(redirect_phase&&alias_runs==4&&old_lines>=1&&new_lines>=2&&
          physical_store==1&&stale_hits>0&&retire_stalls>0&&
          cache_misses>=2&&cache_busy_cycles>0&&
          {target.mem['h20100],target.mem['h20101],
           target.mem['h20102],target.mem['h20103]}==32'h39c00021&&
          cache_enabled,"remap/stale/update/denial coverage");
    $display("PASS translated I-cache coherence: retire=%0d offers=%0d old-line=%0d new-line=%0d alias=%0d stale-hits=%0d checks=%0d",
      retires,offers,old_lines,new_lines,alias_runs,stale_hits,checks);
    $finish;
  end
endmodule
