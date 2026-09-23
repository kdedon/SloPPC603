// CPU-programmed translation before instruction cache and scalar bypass.
/* verilator lint_off BLKSEQ */
module tb_core_bat_cached_bus60x;
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
  int retire_stalls=0,cache_busy_cycles=0;
  int word_reads=0,word_writes=0;
  logic done=0;
  logic cache_hit,cache_miss,cache_busy,cache_enabled,unused_maintenance_ready;
  logic maintenance_done_valid,maintenance_busy;
  int line_bursts=0,cache_hits=0,cache_misses=0;
  int scalar_instruction=0,scalar_data=0;
  int alias_lines=0,bypass_scalar=0,bootstrap_scalar=0;


  function automatic logic [31:0] imm(input int op,input int rt,input int ra,input int value);
    return (32'(op)<<26)|(32'(rt)<<21)|(32'(ra)<<16)|(32'(value)&32'hffff);
  endfunction
  function automatic logic [31:0] spr(input bit write_spr,input int rt,input int number);
    return (write_spr?32'h7c0003a6:32'h7c0002a6)|(32'(rt)<<21)|
      ((32'(number)&31)<<16)|((32'(number)>>5)<<11);
  endfunction
  function automatic logic [31:0] insn_at(input int a);
    int pa;
    pa=a;
    if(a>=32'h20000000)pa=a-32'h20000000;
    else if(a>=32'h10000000)pa=a-32'h10000000;
    case(pa)
      0:return imm(14,3,0,2);
      4:return spr(1,3,529);              // IBAT0 identity L
      8:return spr(1,3,528);              // IBAT0 identity U
      12:return spr(1,3,531);             // IBAT1 alias L
      16:return imm(15,4,0,'h1000);
      20:return imm(24,4,4,2);
      24:return spr(1,4,530);             // IBAT1 EA10000000 -> PA0
      28:return imm(14,5,0,'h12);         // WIMG 2, PP 2
      32:return spr(1,5,533);             // IBAT2 bypass L
      36:return imm(15,4,0,'h2000);
      40:return imm(24,4,4,2);
      44:return spr(1,4,532);             // IBAT2 EA20000000 -> PA0
      48:return spr(1,3,539);             // DBAT1 alias L
      52:return imm(15,4,0,'h3000);
      56:return imm(24,4,4,2);
      60:return spr(1,4,538);             // DBAT1 EA30000000 -> PA0
      64:return (32'd31<<26)|(32'd6<<21)|(32'd83<<1);
      68:return imm(24,6,6,'h30);
      72:return (32'd31<<26)|(32'd6<<21)|(32'd146<<1);
      76:return 32'h4c00012c;
      80:return imm(15,7,0,'h1000);
      84:return imm(24,7,7,'h100);
      88:return spr(1,7,9);               // mtctr alias I target
      92:return 32'h4e800420;             // bctr
      'h100:return imm(14,8,0,1);
      'h104:return imm(14,8,8,1);
      'h108:return imm(15,9,0,'h3000);
      'h10c:return imm(24,9,9,'h1000);
      'h110:return imm(32,10,9,0);        // translated data load
      'h114:return imm(14,10,10,1);
      'h118:return imm(36,10,9,4);        // translated data store
      'h11c:return imm(15,7,0,'h2000);
      'h120:return imm(24,7,7,'h200);
      'h124:return spr(1,7,9);
      'h128:return 32'h4e800420;
      'h200:return imm(14,11,0,5);
      'h204:return imm(14,11,11,1);
      'h208:return 32'h44000002;
      'h20c:return imm(14,13,0,9);
      'h210:return 32'h48000000;
      'hc00:return imm(14,12,0,7);
      'hc04:return 32'h4c000064;
      default:return 32'h60000000;
    endcase
  endfunction
  function automatic logic [31:0] expected_pc(input int ordinal);
    if(ordinal<24)return 32'(ordinal*4);
    if(ordinal<35)return 32'h10000100+32'((ordinal-24)*4);
    if(ordinal<38)return 32'h20000200+32'((ordinal-35)*4);
    if(ordinal==38)return 32'hc00;
    if(ordinal==39)return 32'hc04;
    return 32'h2000020c;
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
    if(!ok)$fatal(1,"%s cycle=%0d retire=%0d pc=%08x bus=%08x",
      why,cycles,retires,retired.pc,bus_a);
  endtask
  task automatic put_word(input int address,input logic [31:0] value);
    for(int k=0;k<4;k++)target.mem[address+k]=value[31-k*8 -:8];
  endtask

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
    .halted_o(halted),.redirect_valid_i(1'b0),.redirect_all_i(1'b0),
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
    .maintenance_busy_o(maintenance_busy),
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
  assign tr=rst_n&&cycles%7!=2&&cycles%7!=3;

  always @(posedge clk)begin
    cycles++;
    if(rst_n)begin
      check(cycles<10000,"direct composition watchdog");
      check(!halted&&!ifetch_error&&!pimem_error&&!protocol_error&&
            !redirect_accepted&&(!running||!cpr),"unexpected fault, redirect, or PR");
      if(tv&&!tr)retire_stalls++;
      if(cache_busy)cache_busy_cycles++;
      if(cache_hit)cache_hits++;
      if(cache_miss)cache_misses++;
      check(cache_enabled&&!maintenance_busy&&!maintenance_done_valid,
        "cache maintenance unexpectedly active");
      if(addr_oe&&ts_oe&&!ts_n)begin
        address_offers++;
        check(abb_oe&&!abb_n&&bus_busy&&wt_n&&gbl_n&&cse==0,
              "shared address tenure/attributes");
        if(!tbst_n)begin
          check(tt==5'b01110&&tsiz==2&&tc==2&&ci_n&&
                bus_a<8192&&bus_a[2:0]==0,"translated line burst pins/PA");
          line_bursts++;
          if((bus_a&32'hffffffe0)==32'h100||
             (bus_a&32'hffffffe0)==32'h120)alias_lines++;
          check((bus_a&32'hffffffe0)!=32'h200,
            "WIMG-I page incorrectly filled into line cache");
          check(cir,"line fill occurred before instruction translation");
        end else if(tc==2)begin
          check(tt==5'b01010&&tsiz==4&&!ci_n&&bus_a<8192,
            "scalar instruction bypass shape");
          scalar_instruction++;
          if(bus_a>=32'h200&&bus_a<32'h220)begin
            check(cir,"WIMG-I bypass lost translated instruction context");
            bypass_scalar++;
          end else if(!cir)bootstrap_scalar++;
        end else begin
          check(tc==0&&tt!=5'b01110&&!ci_n&&
                bus_a>=32'h1000&&bus_a<32'h1008&&cdr,
            "translated scalar data physical address/attributes");
          scalar_data++;
          if(bus_a==32'h1000)begin
            check(tt==5'b01010&&tsiz==4,"word load physical shape");
            word_reads++;
          end
          if(bus_a==32'h1004)begin
            check(tt==5'b00010&&tsiz==4,"word store physical shape");
            word_writes++;
          end
        end
      end
      if(dbb_oe)check(bus_busy,"data tenure without busy owner");
      if(!ta_n&&dbb_oe)begin
        if(tt==5'b00010)begin
          check(data_oe&&bus_a==32'h1004,
            "write data without physical target ownership");
          check(data_out==64'h0000000011223345,
            "big-endian scalar data-store lower half");
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
        check(retires<41&&retired.pc==expected_pc(retires)&&
              retired.insn==insn_at(int'(retired.pc))&&
              !retired.illegal&&!retired.alignment_exception&&
              retired.fetch_fault==FETCH_OK&&retired.data_fault==DATA_OK,
              "precise retirement sequence/word");
        if(retired.pc==32'h10000110)
          check(retired.gpr_write&&retired.gpr==10&&retired.value==32'h11223344,
            "translated data load value");
        if(retired.pc==32'h10000114)
          check(retired.gpr_write&&retired.gpr==10&&retired.value==32'h11223345,
            "translated data arithmetic");
        if(retired.pc==32'hc00)
          check(!cir&&!cdr&&retired.gpr_write&&retired.gpr==12&&
                retired.value==7,"SC real-mode handler");
        if(retired.pc==32'h2000020c)begin
          check(retired.gpr_write&&retired.gpr==13&&retired.value==9&&
                cir&&cdr,"RFI returned to WIMG-I bypass code");
          done=1;
        end
        retires++;
      end
    end
  end
  assert property(@(posedge clk) disable iff(!rst_n)
    tv&&!tr |=> tv&&$stable(retired));

  initial begin
    for(int a=0;a<=92;a+=4)put_word(a,insn_at(a));
    for(int a='h100;a<='h128;a+=4)put_word(a,insn_at(a));
    for(int a='h200;a<='h210;a+=4)put_word(a,insn_at(a));
    put_word('hc00,insn_at('hc00));
    put_word('hc04,insn_at('hc04));
    target.mem['h1000]=8'h11;target.mem['h1001]=8'h22;
    target.mem['h1002]=8'h33;target.mem['h1003]=8'h44;
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
  initial begin
    wait(done);@(negedge clk);
    check(retires==41&&line_bursts>=3&&alias_lines>=2&&
          cache_hits>0&&cache_misses>0&&cache_busy_cycles>0&&
          scalar_instruction>0&&
          bootstrap_scalar>0&&bypass_scalar>=4&&
          scalar_data==2&&word_reads==1&&word_writes==1&&
          data_reads==1&&data_writes==1&&retire_stalls>0,
          "translated fill/hit, WIMG bypass, or data coverage");
    check({target.mem['h1000],target.mem['h1001],
           target.mem['h1002],target.mem['h1003]}==32'h11223344&&
          {target.mem['h1004],target.mem['h1005],
           target.mem['h1006],target.mem['h1007]}==32'h11223345,
          "translated data target physical memory");
    $display("PASS translated I-cache: retires=%0d address=%0d line=%0d hit=%0d miss=%0d bypass=%0d data-read=%0d data-write=%0d checks=%0d",
      retires,address_offers,line_bursts,cache_hits,cache_misses,bypass_scalar,data_reads,data_writes,checks);
    $finish;
  end
endmodule
