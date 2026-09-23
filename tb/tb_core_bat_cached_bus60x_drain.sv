// Accepted physical refill drain, maintenance, redirect, and line TEA.
/* verilator lint_off BLKSEQ */
module tb_core_bat_cached_bus60x_drain;
  import ppc_pkg::*;
  logic clk=0,rst_n=0;
  always #5 clk=~clk;
  logic start_valid=0,start_ready,running,cir,cdr,cpr;
  logic tv,tr,retire_enable=1,halted,ifetch_error,protocol_error,bus_busy;
  logic pimem_error,redirect_accepted,redirect_valid=0,redirect_all=0;
  logic [31:0] redirect_target=0;
  retire_packet_t retired;
  logic br_n,bg_n,abb_n,abb_oe,ts_n,ts_oe,tbst_n,ci_n,wt_n,gbl_n,addr_oe;
  logic [31:0] bus_a;
  logic [4:0] tt;
  logic [2:0] tsiz;
  logic [1:0] tc,cse;
  logic aack_n,artry_n,dbg_n,dbb_n,dbb_oe,data_oe,ta_n,drtry_n,tea_n;
  logic [63:0] data_in;
  logic cache_busy,cache_enabled,maintenance_ready;
  logic maintenance_valid=0,maintenance_invalidate=0,maintenance_enable=1;
  logic maintenance_done_valid,maintenance_done_ready=0,maintenance_busy;
  int cycles=0,checks=0,phase=0,retirements=0,alias_lines=0;
  int target_old_retires=0,target_new_retires=0;
  bit held_refill=0,release_old_line=0,old_line_released=0;
  bit inject_line_tea=0,partial_beat_sent=0,tea_sent=0;
  logic [63:0] held_dw[0:3];
  localparam logic [31:0] I_OLD=32'h39000001; // addi r8,r0,1
  localparam logic [31:0] I_NEW=32'h39000009; // addi r8,r0,9
  localparam logic [31:0] TARGET=32'h10000100;

  function automatic logic [31:0] spr(input int rt,input int number);
    return 32'h7c0003a6|(32'(rt)<<21)|
      ((32'(number)&31)<<16)|((32'(number)>>5)<<11);
  endfunction
  task automatic check(input bit ok,input string why);
    checks++;
    if(!ok)$fatal(1,"%s phase=%0d cycle=%0d pc=%08x bus=%08x",
      why,phase,cycles,retired.pc,bus_a);
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
    .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1),.ENABLE_RUNTIME_BAT(1'b1)) dut(
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
    .halted_o(halted),.redirect_valid_i(redirect_valid),.redirect_all_i(redirect_all),
    .redirect_keep_pivot_i(1'b0),.redirect_pivot_i('0),
    .redirect_target_i(redirect_target),.redirect_accepted_o(redirect_accepted),
    .translation_fault_o(),.fault_instruction_o(),.fault_write_o(),
    .fault_ea_o(),.fault_miss_o(),.fault_protection_o(),
    .fault_guarded_o(),.fault_config_o(),.fault_invalid_input_o(),
    .fault_invalid_entry_o(),.pimem_error_o(pimem_error),
    .busy_o(),.ifetch_error_o(ifetch_error),
    .bus_protocol_error_o(protocol_error),.bus_busy_o(bus_busy),
    .icache_hit_o(),.icache_miss_o(),
    .icache_busy_o(cache_busy),
    .maintenance_valid_i(maintenance_valid),.maintenance_ready_o(maintenance_ready),
    .maintenance_invalidate_i(maintenance_invalidate),.maintenance_cache_enable_i(maintenance_enable),
    .maintenance_done_valid_o(maintenance_done_valid),
    .maintenance_done_ready_i(maintenance_done_ready),.cache_enabled_o(cache_enabled),
    .maintenance_busy_o(maintenance_busy),
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
    if(cycles>20000)$fatal(1,"translated I-cache drain watchdog phase=%0d",phase);
    if(rst_n)begin
      check(!protocol_error,"bus/cache protocol diagnostic");
      if(addr_oe&&ts_oe&&!ts_n)begin
        check(abb_oe&&!abb_n&&bus_busy&&bus_a<8192&&wt_n&&gbl_n&&cse==0,
          "physical bus ownership/attributes");
        if(!tbst_n)begin
          check(tt==5'b01110&&tsiz==2&&tc==2&&ci_n,
            "cacheable physical line shape");
          if((bus_a&32'hffffffe0)==32'h100)alias_lines++;
        end else check(tt==5'b01010&&tsiz==4&&tc==2&&!ci_n,
                       "real-mode scalar bootstrap shape");
      end
      if(tv&&tr)begin
        check(^retired !== 1'bx,"known retired packet");
        retirements++;
        if(retired.pc==TARGET)begin
          if(retired.insn==I_OLD)target_old_retires++;
          else if(retired.insn==I_NEW)begin
            check(retired.gpr_write&&retired.gpr==8&&retired.value==9,
              "new target instruction effects");
            target_new_retires++;
          end else check(0,"unexpected target word");
          check(phase!=2,"line TEA fabricated target retirement");
        end
      end
    end
  end

  task automatic apply_reset;
    @(negedge clk);
    rst_n=0;start_valid=0;redirect_valid=0;redirect_all=0;
    maintenance_valid=0;maintenance_done_ready=0;retire_enable=1;
    repeat(4)@(posedge clk);
    #1;
    check(!ifetch_error&&!pimem_error&&!bus_busy&&!cache_busy&&
          !running&&br_n&&!abb_oe&&!ts_oe&&!dbb_oe&&!data_oe,
          "reset clears fatal/ownership and releases pins");
    @(negedge clk);rst_n=1;
  endtask
  task automatic start_wrapper;
    @(negedge clk);start_valid=1;
    do @(posedge clk);while(!start_ready);
    @(negedge clk);start_valid=0;
    check(running&&!cir&&!cdr&&!cpr&&cache_enabled,"real-mode startup");
  endtask
  task automatic redirect_to_target;
    redirect_target=TARGET;redirect_all=1;redirect_valid=1;
    for(int i=0;i<200&&!redirect_accepted;i++)@(negedge clk);
    check(redirect_accepted,"all-kill redirect accepted");
    @(posedge clk);@(negedge clk);
    redirect_valid=0;redirect_all=0;
  endtask

  // Independent pin target: retain old line bytes before software modifies
  // memory, and release that accepted refill only after maintenance is pending.
  initial begin : responder
    forever begin
      logic [31:0] base;
      int critical;
      target.grant_address(1,1,1'b0,1'b0);
      target.grant_data(1);
      if(!tbst_n)begin
        base=bus_a&32'hffffffe0;
        critical=int'(bus_a[4:3]);
        if(base==32'h100&&phase==1&&!held_refill)begin
          for(int beat=0;beat<4;beat++)
            held_dw[beat]=line_dw(base,(critical+beat)%4);
          held_refill=1;
          wait(release_old_line);
          for(int beat=0;beat<4;beat++)target.sample_ta(held_dw[beat]);
          old_line_released=1;
        end else if(base==32'h100&&phase==2&&inject_line_tea)begin
          target.sample_ta(line_dw(base,critical));
          partial_beat_sent=1;
          target.sample_termination(1'b0,1'b1,1'b0,64'b0);
          tea_sent=1;
        end else begin
          for(int beat=0;beat<4;beat++)
            target.sample_ta(line_dw(base,(critical+beat)%4));
        end
      end else target.acknowledge_normal_read(1);
    end
  end

  initial begin
    // CPU installs an identity WIMG=0 IBAT and an alias EA10000000 -> PA0.
    put_word(0,32'h38600002); put_word(4,spr(3,529));
    put_word(8,spr(3,528)); put_word(12,spr(3,531));
    put_word(16,32'h3c801000); put_word(20,32'h60840002);
    put_word(24,spr(4,530)); put_word(28,32'h7ca000a6);
    put_word(32,32'h60a50020); put_word(36,32'h7ca00124);
    put_word(40,32'h4c00012c); put_word(44,32'h3ce01000);
    put_word(48,32'h60e70100); put_word(52,spr(7,9));
    put_word(56,32'h4e800420); // bctr to translated target
    put_word('h100,I_OLD);put_word('h104,32'h48000000);

    phase=1;apply_reset();start_wrapper();
    for(int i=0;i<3000&&!held_refill;i++)@(posedge clk);
    check(held_refill&&!ifetch_error&&alias_lines==1,
          "CPU-programmed cacheable alias refill accepted");
    @(negedge clk);
    retire_enable=0;
    maintenance_invalidate=1;maintenance_enable=1;maintenance_valid=1;
    repeat(5)begin
      @(posedge clk);#1;
      check(!maintenance_ready&&!maintenance_done_valid&&cache_busy,
        "maintenance cannot overtake held physical refill");
    end
    @(negedge clk);
    redirect_to_target();
    put_word('h100,I_NEW);
    release_old_line=1;
    for(int i=0;i<300&&!old_line_released;i++)@(posedge clk);
    check(old_line_released,"accepted old line failed to drain");
    for(int i=0;i<300&&!maintenance_ready;i++)@(negedge clk);
    check(maintenance_ready,"maintenance did not wait for physical response");
    @(posedge clk);@(negedge clk);maintenance_valid=0;
    for(int i=0;i<300&&!maintenance_done_valid;i++)@(negedge clk);
    check(maintenance_done_valid&&maintenance_busy,
          "invalidate completion missing");
    repeat(4)begin
      @(posedge clk);#1;
      check(maintenance_done_valid&&!maintenance_ready&&
            alias_lines==1&&target_old_retires==0,
            "held completion exposed stale line/fetch");
    end
    @(negedge clk);maintenance_done_ready=1;
    @(posedge clk);@(negedge clk);maintenance_done_ready=0;
    retire_enable=1;
    for(int i=0;i<400&&target_new_retires==0;i++)@(posedge clk);
    check(target_new_retires>0&&target_old_retires==0&&alias_lines>=2,
          "post-invalidate restart did not refill new physical bytes");

    // A line TEA after a hard reset is terminal and cannot publish an
    // instruction or poison a future reset's cache state.
    phase=2;inject_line_tea=1;apply_reset();start_wrapper();
    for(int i=0;i<3000&&!tea_sent;i++)@(posedge clk);
    for(int i=0;i<30&&!ifetch_error;i++)@(posedge clk);
    check(partial_beat_sent&&tea_sent&&ifetch_error&&pimem_error&&halted&&
          !protocol_error&&target_old_retires==0,
          "line TEA must stop without a fabricated instruction");
    repeat(4)begin
      @(posedge clk);#1;
      check(!tv&&ifetch_error,"fatal line error leaked a retirement");
    end
    phase=3;inject_line_tea=0;apply_reset();start_wrapper();
    begin
      int prior_new_retires;
      prior_new_retires=target_new_retires;
      for(int i=0;i<3000&&target_new_retires==prior_new_retires;i++)@(posedge clk);
      check(target_new_retires>prior_new_retires&&!ifetch_error&&!pimem_error&&
            alias_lines>=4,"reset failed to recover from line TEA");
    end
    $display("PASS translated I-cache drain: checks=%0d retires=%0d alias_lines=%0d",
      checks,retirements,alias_lines);
    $finish;
  end
endmodule
