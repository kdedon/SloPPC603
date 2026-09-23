// Pin-driven translated-wrapper transport errors and reset recovery.
/* verilator lint_off BLKSEQ */
/* verilator lint_off PINCONNECTEMPTY */
module tb_core_bat_bus60x_errors;
  import ppc_pkg::*;
  logic clk=0,rst_n=0;
  always #5 clk=~clk;
  logic start_valid=0,start_ready,running,cir,cdr,cpr;
  logic tv,tr=1,halted,ifetch_error,protocol_error,bus_busy,pimem_error;
  logic translated_busy,redirect_accepted;
  retire_packet_t retired;
  logic br_n,bg_n,abb_n,abb_oe,ts_n,ts_oe,tbst_n,ci_n,wt_n,gbl_n,addr_oe;
  logic [31:0] bus_a;
  logic [4:0] tt;
  logic [2:0] tsiz;
  logic [1:0] tc,cse;
  logic aack_n,artry_n,dbg_n,dbb_n,dbb_oe,data_oe,ta_n,drtry_n,tea_n;
  logic [63:0] data_in,data_out;
  int cycles=0,checks=0,phase=0,retirements=0,address_offers=0;
  bit data_error_seen=0,recovered_retire=0,saw_data_tea=0;

  task automatic check(input bit ok,input string what);
    checks++;
    if(!ok)$fatal(1,"%s phase=%0d cycle=%0d pc=%08x bus=%08x",
                  what,phase,cycles,retired.pc,bus_a);
  endtask
  function automatic logic [31:0] spr(input int rt,input int number);
    return 32'h7c0003a6|(32'(rt)<<21)|
      ((32'(number)&31)<<16)|((32'(number)>>5)<<11);
  endfunction
  task automatic put_word(input int address,input logic [31:0] value);
    for(int k=0;k<4;k++)target.mem[address+k]=value[31-8*k -:8];
  endtask

  ppc_core_bat_bus60x #(.RESET_PC(32'b0),
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
    .halted_o(halted),.redirect_valid_i(1'b0),.redirect_all_i(1'b0),
    .redirect_keep_pivot_i(1'b0),.redirect_pivot_i('0),
    .redirect_target_i('0),.redirect_accepted_o(redirect_accepted),
    .translation_fault_o(),.fault_instruction_o(),.fault_write_o(),
    .fault_ea_o(),.fault_miss_o(),.fault_protection_o(),
    .fault_guarded_o(),.fault_config_o(),.fault_invalid_input_o(),
    .fault_invalid_entry_o(),.pimem_error_o(pimem_error),
    .busy_o(translated_busy),.ifetch_error_o(ifetch_error),
    .bus_protocol_error_o(protocol_error),.bus_busy_o(bus_busy),
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
  bus60x_target_bfm #(.BASE_ADDR(32'b0),.MEM_BYTES(8192)) target(
    .clk_i(clk),.br_n_i(br_n),.abb_n_i(abb_n),.abb_oe_i(abb_oe),
    .ts_n_i(ts_n),.ts_oe_i(ts_oe),.a_i(bus_a),
    .dbb_n_i(dbb_n),.dbb_oe_i(dbb_oe),.bg_n_o(bg_n),
    .aack_n_o(aack_n),.artry_n_o(artry_n),.dbg_n_o(dbg_n),
    .d_o(data_in),.ta_n_o(ta_n),.drtry_n_o(drtry_n),.tea_n_o(tea_n)
  );

  always @(posedge clk) begin
    cycles++;
    if(cycles>3000)$fatal(1,"translated 60x error watchdog phase=%0d",phase);
    if(rst_n&&dbb_oe)check(!data_oe || ^data_out !== 1'bx,
                           "driven data pins known");
    if(rst_n&&addr_oe&&ts_oe&&!ts_n)begin
      address_offers++;
      check(abb_oe&&!abb_n&&bus_busy&&!ci_n&&wt_n&&gbl_n&&cse==0&&
            tbst_n&&tsiz==4&&bus_a[1:0]==0,
            "scalar physical address attributes/shape");
      if(tc==2)check(tt==5'b01010&&bus_a<64,"instruction physical offer");
      else check(tc==0&&cdr&&!cir&&tt==5'b01010&&bus_a==32'h1000,
                 "data physical offer");
    end
    if(rst_n&&tv&&tr)begin
      check(^retired !== 1'bx,"retirement packet fully known");
      retirements++;
      if(phase==1||phase==3)
        check(0,"instruction TEA or pre-reset offer fabricated retirement");
      if(phase==2&&retired.pc==44)begin
        check(retired.insn==32'h80c30000&&retired.illegal&&
              retired.data_fault==DATA_OK&&!retired.gpr_write&&
              !retired.update_write&&retired.page_miss=='0,
              "data TEA must retire only a transport diagnostic");
        data_error_seen=1;
      end
      if(phase==4&&retired.pc==0)begin
        check(retired.insn==32'h38600002&&!retired.illegal&&
              retired.gpr_write&&retired.gpr==3&&
              retired.value==32'h2,"post-reset valid fetch result");
        recovered_retire=1;
      end
    end
  end

  task automatic reset_wrapper;
    @(negedge clk);rst_n=0;start_valid=0;
    repeat(3)@(posedge clk);
    #1;
    check(!ifetch_error&&!halted&&!protocol_error&&!bus_busy&&
          !translated_busy&&!pimem_error&&!running&&
          br_n&&!abb_oe&&!ts_oe&&!dbb_oe&&!data_oe&&!addr_oe,
          "reset releases transport, translation and pins");
    @(negedge clk);rst_n=1;
  endtask
  task automatic start_wrapper;
    @(negedge clk);start_valid=1;
    do @(posedge clk);while(!start_ready);
    @(negedge clk);start_valid=0;
    check(running&&!cir&&!cdr&&!cpr,"real-mode startup accepted");
  endtask

  initial begin
    put_word(0,32'h38600002);  // r3=BAT lower valid/PP bits
    put_word(4,spr(3,539));  // DBAT1L physical 0
    put_word(8,32'h3c801000); // lis r4,0x1000
    put_word(12,32'h60840002);// ori r4,r4,2: EA 0x10000000
    put_word(16,spr(4,538)); // DBAT1U translated alias
    put_word(20,32'h7ca000a6);// mfmsr r5
    put_word(24,32'h60a50010);// ori r5,r5,DR
    put_word(28,32'h7ca00124);// mtmsr r5
    put_word(32,32'h4c00012c);// isync
    put_word(36,32'h3c601000);// lis r3,0x1000
    put_word(40,32'h60631000);// ori r3,r3,0x1000
    put_word(44,32'h80c30000);// lwz r6,0(r3): EA 10001000 -> PA 1000
    put_word(48,32'h38e00007);// addi r7,r0,7
    put_word(52,32'h48000000);// terminal self branch
    target.mem['h1000]=8'h11;target.mem['h1001]=8'h22;
    target.mem['h1002]=8'h33;target.mem['h1003]=8'h44;

    phase=1;reset_wrapper();start_wrapper();
    target.grant_address(1,1,1'b0,1'b0);
    check(tc==2&&bus_a==0,"first physical fetch selected");
    target.grant_data(1);
    target.terminate_with_tea(1);
    repeat(3)@(posedge clk);#1;
    check(ifetch_error&&halted&&bus_busy&&translated_busy&&
          !pimem_error&&!protocol_error&&retirements==0,
          "instruction TEA sticky terminal, router owner pending");
    repeat(5)begin
      @(posedge clk);#1;
      check(br_n&&!abb_oe&&!dbb_oe&&retirements==0,
            "instruction TEA offers no new bus request or word");
    end

    phase=2;reset_wrapper();start_wrapper();
    for(int i=0;i<30;i++)begin
      target.grant_address(1,1,1'b0,1'b0);
      target.grant_data(1);
      if(tc==0)begin
        check(bus_a==32'h1000,"translated data TEA targets alias PA, not EA");
        target.terminate_with_tea(1);
        saw_data_tea=1;
        break;
      end else target.acknowledge_normal_read(1);
    end
    check(saw_data_tea,"data request reached physical bus");
    for(int i=0;i<80&&!data_error_seen;i++)@(posedge clk);
    #1;
    check(data_error_seen&&halted&&!ifetch_error&&!pimem_error&&
          !protocol_error&&!bus_busy,
          "data TEA retires transport diagnostic without typed DSI");
    check(dut.translated_core.core.regfile.gpr[6]==0,
          "data TEA cannot write destination GPR");
    check({target.mem['h1000],target.mem['h1001],
           target.mem['h1002],target.mem['h1003]}==32'h11223344,
          "data TEA cannot mutate physical memory");

    // An accepted wrapper request may be waiting for address grant at reset.
    phase=3;reset_wrapper();start_wrapper();
    target.wait_for_address_request(64);
    check(!br_n&&!abb_oe&&bus_busy,"pending address request before reset");
    reset_wrapper();
    repeat(3)@(posedge clk);#1;
    check(!tv&&!ifetch_error&&!bus_busy&&!translated_busy,
          "reset discards old address offer and response");

    // The same image starts cleanly after reset and retires the exact word.
    phase=4;start_wrapper();
    target.grant_address(1,1,1'b0,1'b0);
    check(bus_a==0&&tc==2,"restart fetches reset PC");
    target.grant_data(1);
    target.acknowledge_normal_read(1);
    for(int i=0;i<80&&!recovered_retire;i++)@(posedge clk);
    #1;
    check(recovered_retire&&!ifetch_error&&!protocol_error&&
          !redirect_accepted&&address_offers>=4,"reset recovery executes valid instruction");
    $display("PASS translated 60x errors: checks=%0d retires=%0d offers=%0d",
             checks,retirements,address_offers);
    $finish;
  end
endmodule
