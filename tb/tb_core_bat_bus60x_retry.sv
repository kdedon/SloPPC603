// CPU-programmed translated scalar bus with address retry and provisional read replacement.
/* verilator lint_off BLKSEQ */
module tb_core_bat_bus60x_retry;
  import ppc_pkg::*;
  logic clk=0,rst_n=0;
  always #5 clk=~clk;
  logic start_valid=0,start_ready,running,cir,cdr,cpr;
  logic tv,tr,halted,ifetch_error,protocol_error,bus_busy,pimem_error,redirect_accepted;
  retire_packet_t retired;
  logic br_n,bg_n,abb_n,abb_oe,ts_n,ts_oe,tbst_n,ci_n,wt_n,gbl_n,addr_oe;
  logic [31:0] bus_a;
  logic [4:0] tt;
  logic [2:0] tsiz;
  logic [1:0] tc,cse;
  logic aack_n,artry_n,dbg_n,dbb_n,dbb_oe,data_oe,ta_n,drtry_n,tea_n;
  logic [63:0] data_in,data_out;
  int cycles=0,checks=0,retires=0,address_offers=0,data_reads=0,data_writes=0;
  int fetch_real=0,fetch_translated=0,retire_stalls=0;
  int byte_writes=0,half_reads=0,word_reads=0,word_writes=0;
  logic done=0;
  logic did_artry=0,did_drtry=0,retry_pending=0;
  logic [31:0] retry_addr=0;
  logic [4:0] retry_tt=0;
  logic [2:0] retry_size=0;
  logic [1:0] retry_tc=0;
  int physical_data_requests=0,word_retire_holds=0;


  function automatic logic [31:0] imm(input int op,input int rt,input int ra,input int value);
    return (32'(op)<<26)|(32'(rt)<<21)|(32'(ra)<<16)|(32'(value)&32'hffff);
  endfunction
  function automatic logic [31:0] spr(input bit write_spr,input int rt,input int number);
    return (write_spr?32'h7c0003a6:32'h7c0002a6)|(32'(rt)<<21)|
      ((32'(number)&31)<<16)|((32'(number)>>5)<<11);
  endfunction
  function automatic logic [31:0] insn_at(input int a);
    case(a)
      0:return imm(14,3,0,2);
      4:return spr(1,3,529);              // IBAT0L
      8:return spr(1,3,528);              // IBAT0U identity
      12:return imm(14,6,0,'h1a);         // PP=2, WIMG=3
      16:return spr(1,6,539);             // DBAT1L nonzero WIMG
      20:return imm(15,4,0,'h1000);
      24:return imm(24,4,4,2);
      28:return spr(1,4,538);             // DBAT1U alias
      32:return (32'd31<<26)|(32'd5<<21)|(32'd83<<1);
      36:return imm(24,5,5,'h30);
      40:return (32'd31<<26)|(32'd5<<21)|(32'd146<<1);
      44:return 32'h4c00012c;
      48:return imm(15,1,0,'h1000);
      52:return imm(24,1,1,'h1000);
      56:return imm(14,2,0,'h5a);
      60:return imm(38,2,1,3);
      64:return imm(40,6,1,2);            // ARTRY once
      68:return imm(32,7,1,0);            // DRTRY poison + replacement
      72:return imm(36,7,1,4);
      76:return 32'h44000002;
      80:return imm(14,8,0,9);
      84:return 32'h48000000;
      'hc00:return imm(14,9,0,7);
      'hc04:return 32'h4c000064;
      default:return 32'h60000000;
    endcase
  endfunction
  function automatic logic [31:0] expected_pc(input int ordinal);
    if(ordinal<=19)return 32'(ordinal*4);
    if(ordinal==20)return 32'hc00;
    if(ordinal==21)return 32'hc04;
    return 32'd80;
  endfunction
  task automatic check(input bit ok,input string why);
    checks++;
    if(!ok)$fatal(1,"%s cycle=%0d retire=%0d pc=%08x bus=%08x",
      why,cycles,retires,retired.pc,bus_a);
  endtask
  task automatic put_word(input int address,input logic [31:0] value);
    for(int k=0;k<4;k++)target.mem[address+k]=value[31-k*8 -:8];
  endtask

  /* verilator lint_off PINCONNECTEMPTY */
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
    .busy_o(),.ifetch_error_o(ifetch_error),
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
  assign tr=rst_n&&cycles%7!=2&&cycles%7!=3&&
    !(tv&&retired.pc==32'd68&&word_retire_holds<8);

  always @(posedge clk)begin
    cycles++;
    if(rst_n)begin
      check(cycles<10000,"direct composition watchdog");
      check(!halted&&!ifetch_error&&!pimem_error&&!protocol_error&&
            !redirect_accepted&&(!running||!cpr),"unexpected fault, redirect, or PR");
      if(tv&&!tr)begin
        retire_stalls++;
        if(retired.pc==68)word_retire_holds++;
      end
      if(dut.translated_core.pdmem_req_valid_o&&
         dut.translated_core.pdmem_req_ready_i)begin
        check(dut.translated_core.pdmem_req_wimg_o==4'b0011,
          "nonzero BAT WIMG metadata lost before fixed CI bus");
        physical_data_requests++;
      end
      if(addr_oe&&ts_oe&&!ts_n)begin
        address_offers++;
        if(retry_pending)begin
          check(bus_a==retry_addr&&tt==retry_tt&&tc==retry_tc&&
                tsiz==retry_size,"ARTRY reoffer changed physical owner/shape");
          retry_pending=0;
        end
        check(abb_oe&&!abb_n&&bus_busy&&tbst_n&&!ci_n&&
              wt_n&&gbl_n&&cse==0,"scalar address tenure/attributes");
        if(tc==2)begin
          check(tt==5'b01010&&tsiz==4&&bus_a<8192&&bus_a[1:0]==0,
            "instruction transfer shape/PA");
          if(cir)fetch_translated++;else fetch_real++;
        end else begin
          check(tc==0&&bus_a>=32'h1000&&bus_a<32'h1008,
            "data transfer escaped translated physical alias");
          if(bus_a==32'h1003)begin
            check(tt==5'b00010&&tsiz==1&&cdr,"byte-store translation/size");
            byte_writes++;
          end
          if(bus_a==32'h1002)begin
            check(tt==5'b01010&&tsiz==2&&cdr,"half-read translation/size");
            half_reads++;
          end
          if(bus_a==32'h1000)begin
            check(tt==5'b01010&&tsiz==4&&cdr,"word-read translation/size");
            word_reads++;
          end
          if(bus_a==32'h1004)begin
            check(tt==5'b00010&&tsiz==4&&cdr,"word-store translation/size");
            word_writes++;
          end
        end
      end
      if(dbb_oe)check(bus_busy,"data tenure without busy owner");
      if(!ta_n&&dbb_oe)begin
        if(tt==5'b00010)begin
          check(data_oe&&bus_a>=32'h1000&&bus_a<32'h1008,
            "write data without physical target ownership");
          if(bus_a==32'h1003)
            check(data_out==64'h0000005a00000000,
              "big-endian byte store lane or inactive lanes");
          if(bus_a==32'h1004)
            check(data_out==64'h000000001122335a,
              "big-endian lower-half word store lanes");
          for(int k=0;k<int'(tsiz);k++)
            target.mem[int'(bus_a)+k]=
              data_out[63-8*(int'(bus_a[2:0])+k) -:8];
          data_writes++;
        end else begin
          check(!data_oe,"read drove physical data pins");
          if(tc==0)data_reads++;
        end
      end
      if(tv&&tr)begin
        check(retires<23&&retired.pc==expected_pc(retires)&&
              retired.insn==insn_at(int'(retired.pc))&&
              !retired.illegal&&!retired.alignment_exception&&
              retired.fetch_fault==FETCH_OK&&retired.data_fault==DATA_OK,
              "precise retirement sequence/word");
        if(retired.pc==64)
          check(retired.gpr_write&&retired.gpr==6&&retired.value==32'h335a,
            "translated halfword/lane result");
        if(retired.pc==68)
          check(retired.gpr_write&&retired.gpr==7&&retired.value==32'h1122335a,
            "translated fullword result");
        if(retired.pc==80)begin
          check(retired.gpr_write&&retired.gpr==8&&retired.value==9&&
                cir&&cdr,"RFI restored translated context");
          done=1;
        end
        if(retired.pc==32'hc00)
          check(!cir&&!cdr&&retired.gpr_write&&retired.gpr==9&&
                retired.value==7,"SC handler real-mode context");
        retires++;
      end
    end
  end
  assert property(@(posedge clk) disable iff(!rst_n)
    tv&&!tr |=> tv&&$stable(retired));

  initial begin
    for(int a=0;a<=84;a+=4)put_word(a,insn_at(a));
    put_word('hc00,insn_at('hc00));
    put_word('hc04,insn_at('hc04));
    target.mem['h1000]=8'h11;target.mem['h1001]=8'h22;
    target.mem['h1002]=8'h33;target.mem['h1003]=8'h44;
    repeat(4)@(negedge clk);rst_n=1;
    @(negedge clk);start_valid=1;
    do @(posedge clk);while(!start_ready);
    @(negedge clk);start_valid=0;
    forever begin : target_loop
      bit retry_this;
      target.wait_for_address_request(64);
      retry_this=!did_artry&&tc==0&&bus_a==32'h1002;
      target.grant_address(1,1,retry_this,1'b0);
      if(retry_this)begin
        did_artry=1;retry_pending=1;
        retry_addr=bus_a;retry_tt=tt;retry_tc=tc;retry_size=tsiz;
      end else begin
        target.grant_data(1);
        if(tt==5'b00010)target.acknowledge_write(1);
        else if(!did_drtry&&tc==0&&bus_a==32'h1000)begin
          did_drtry=1;
          target.drive_provisional(64'hdeadbeef00000000,1'b1,1'b1,
            64'h1122335a00000000);
          target.finish_replacement(1'b1);
        end else target.acknowledge_normal_read(1);
      end
    end
  end
  initial begin
    wait(done);@(negedge clk);
    $display("RETRY COUNTERS retires=%0d real=%0d translated=%0d artry=%b drtry=%b pending=%b phys=%0d holds=%0d byte=%0d half=%0d word=%0d wstore=%0d reads=%0d writes=%0d retirestalls=%0d",
      retires,fetch_real,fetch_translated,did_artry,did_drtry,retry_pending,
      physical_data_requests,word_retire_holds,byte_writes,half_reads,
      word_reads,word_writes,data_reads,data_writes,retire_stalls);
    check(retires==23&&fetch_real>0&&fetch_translated>0&&
          did_artry&&did_drtry&&!retry_pending&&
          physical_data_requests==4&&word_retire_holds>=8&&
          byte_writes==1&&half_reads==2&&word_reads==1&&word_writes==1&&
          data_reads==3&&data_writes==2&&retire_stalls>0,
          "translation, byte lane, or backpressure coverage");
    check({target.mem['h1000],target.mem['h1001],
           target.mem['h1002],target.mem['h1003]}==32'h1122335a&&
          {target.mem['h1004],target.mem['h1005],
           target.mem['h1006],target.mem['h1007]}==32'h1122335a,
          "physical byte memory mismatch");
    $display("PASS translated 60x retry: retires=%0d address=%0d fetch-real=%0d fetch-IR=%0d data-read=%0d data-write=%0d checks=%0d",
      retires,address_offers,fetch_real,fetch_translated,data_reads,data_writes,checks);
    $finish;
  end
endmodule
