// The unchanged table-search/table-fault ELF runs through the translated
// instruction-cache wrapper. RAM behavior uses only public 60x pin tenures.
/* verilator lint_off BLKSEQ */
module tb_compiled_table_cached_bus60x_firmware #(
  parameter int FAULT_PROFILE = 0
);
  import ppc_pkg::*;
  localparam logic [31:0] BASE=32'hfff00000;
  localparam logic [31:0] HTAB=32'hfff10000;
  localparam logic [31:0] MARKER=32'hfff0b000;
  logic clk=0,rst_n=0;
  always #5 clk=~clk;
  logic start_valid=0,start_ready,running,cir,cdr,cpr;
  logic tv,tr,halted,cut_accepted,ifetch_error,bus_error,bus_busy;
  logic pimem_error,router_busy,translation_fault;
  logic icache_hit,icache_miss,icache_busy,cache_enabled,unused_maintenance_ready;
  logic maintenance_done,maintenance_busy;
  logic interrupt_taken,decrementer_taken;
  logic [31:0] unused_interrupt_pc,unused_decrementer_pc;
  retire_packet_t retired;
  logic bat_valid=0,bat_ready,bat_rsp,bat_rejected,bat_unsupported;
  logic bat_config,bat_overlap;
  logic [3:0] bat_invalid;
  logic [9:0] bat_spr=0;
  logic [31:0] bat_data=0;
  logic [49:0] unused_page_ports;
  logic unused_fault_instruction,unused_fault_write,unused_fault_miss;
  logic unused_fault_protection,unused_fault_guarded,unused_fault_config;
  logic unused_fault_invalid_input;
  logic [31:0] unused_fault_ea;
  logic [3:0] unused_fault_invalid_entry;

  logic br_n,bg_n,abb_n,abb_oe,ts_n,ts_oe,addr_oe;
  logic dbb_n,dbb_oe,d_oe,aack_n,dbg_n,ta_n,tbst_n;
  logic ci_n,wt_n,gbl_n;
  logic [31:0] a;
  logic [4:0] tt;
  logic [2:0] tsiz;
  logic [1:0] tc,cse;
  logic [63:0] d_i,d_o;
  logic [7:0] mem[0:196607];
  logic address_pending=0,transfer_pending=0;
  logic transfer_write=0,transfer_instruction=0,transfer_line=0;
  logic [31:0] beat_addr;
  int line_beat=0,line_starts=0,line_beats=0,scalar_ifetches=0;
  int cache_hits=0,cache_misses=0;
  logic [31:0] transfer_addr=0;
  int transfer_size=0,address_delay=0,data_delay=0;
  logic pin_done=0,pin_done_write=0;
  logic [31:0] pin_done_addr=0;
  int pin_done_size=0;
  int cycles=0,checks=0,retires=0,pin_reads=0,pin_writes=0,pin_ifetches=0;
  int bank_switches=0;
  logic last_bank=0,mailbox_written=0,mailbox_retired=0;
  logic [31:0] tohost_addr,fault_count_addr,fault_records_addr;
  string image_path;

  ppc_core_bat_cached_bus60x #(
    .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),.ENABLE_LIVE_CONTEXT(1'b1),
    .ENABLE_TGPR(1'b1),.ENABLE_SDR1(1'b1),.ENABLE_RUNTIME_BAT(1'b1),
    .ENABLE_SEGMENT_REGISTERS(1'b1),.ENABLE_PAGE_TRANSLATION(1'b1),
    .ENABLE_TLB_LOAD(1'b1),.ENABLE_TLB_INVALIDATE(FAULT_PROFILE!=0),
    .ENABLE_PAGE_MISS_RESULTS(1'b1),.ENABLE_TLB_MISS_EXCEPTIONS(1'b1)
  ) dut(
    .clk_i(clk),.rst_ni(rst_n),
    .external_irq_i(1'b0),.interrupt_taken_o(interrupt_taken),
    .interrupt_pc_o(unused_interrupt_pc),
    .timer_tick_i(1'b0),.timebase_enable_i(1'b0),
    .decrementer_taken_o(decrementer_taken),
    .decrementer_pc_o(unused_decrementer_pc),
    .bat_write_valid_i(bat_valid),.bat_write_ready_o(bat_ready),
    .bat_write_spr_i(bat_spr),.bat_write_data_i(bat_data),
    .bat_write_rsp_valid_o(bat_rsp),.bat_write_rsp_ready_i(1'b1),
    .bat_write_rsp_rejected_o(bat_rejected),
    .bat_write_rsp_unsupported_o(bat_unsupported),
    .bat_write_rsp_config_error_o(bat_config),
    .bat_write_rsp_overlap_o(bat_overlap),
    .bat_write_rsp_invalid_entry_o(bat_invalid),
    .tlb_mgmt_req_valid_i('0),.tlb_mgmt_req_ready_o(unused_page_ports[0]),
    .tlb_mgmt_req_kind_i('0),.tlb_mgmt_req_bank_i('0),
    .tlb_mgmt_req_ea_i('0),.tlb_mgmt_req_vsid_i('0),
    .tlb_mgmt_req_pr_i('0),.tlb_mgmt_req_way_i('0),
    .tlb_mgmt_req_rpn_i('0),.tlb_mgmt_req_c_i('0),
    .tlb_mgmt_req_wimg_i('0),.tlb_mgmt_req_pp_i('0),
    .tlb_mgmt_rsp_valid_o(unused_page_ports[1]),
    .tlb_mgmt_rsp_ready_i('0),
    .tlb_mgmt_rsp_kind_o(unused_page_ports[3:2]),
    .tlb_mgmt_rsp_bank_o(unused_page_ports[4]),
    .tlb_mgmt_rsp_ea_o(unused_page_ports[36:5]),
    .tlb_mgmt_rsp_privileged_o(unused_page_ports[37]),
    .tlb_mgmt_rsp_refill_rejected_o(unused_page_ports[38]),
    .tlb_mgmt_rsp_unsupported_o(unused_page_ports[39]),
    .tlb_mgmt_rsp_invalid_input_o(unused_page_ports[40]),
    .tlb_mgmt_idle_o(unused_page_ports[41]),
    .page_fault_o(unused_page_ports[42]),
    .page_miss_o(unused_page_ports[43]),
    .page_protection_o(unused_page_ports[44]),
    .page_no_execute_o(unused_page_ports[45]),
    .page_guarded_o(unused_page_ports[46]),
    .page_direct_store_o(unused_page_ports[47]),
    .page_needs_changed_o(unused_page_ports[48]),
    .page_config_o(unused_page_ports[49]),
    .start_valid_i(start_valid),.start_ready_o(start_ready),
    .start_ir_i(1'b0),.start_dr_i(1'b0),.start_pr_i(1'b0),
    .running_o(running),.context_ir_o(cir),.context_dr_o(cdr),
    .context_pr_o(cpr),
    .retire_valid_o(tv),.retire_ready_i(tr),.retire_o(retired),
    .halted_o(halted),
    .redirect_valid_i(1'b0),.redirect_all_i(1'b0),
    .redirect_keep_pivot_i(1'b0),.redirect_pivot_i('0),
    .redirect_target_i('0),.redirect_accepted_o(cut_accepted),
    .translation_fault_o(translation_fault),
    .fault_instruction_o(unused_fault_instruction),
    .fault_write_o(unused_fault_write),.fault_ea_o(unused_fault_ea),
    .fault_miss_o(unused_fault_miss),
    .fault_protection_o(unused_fault_protection),
    .fault_guarded_o(unused_fault_guarded),
    .fault_config_o(unused_fault_config),
    .fault_invalid_input_o(unused_fault_invalid_input),
    .fault_invalid_entry_o(unused_fault_invalid_entry),
    .pimem_error_o(pimem_error),.busy_o(router_busy),
    .ifetch_error_o(ifetch_error),.bus_protocol_error_o(bus_error),
    .bus_busy_o(bus_busy),
    .icache_hit_o(icache_hit),.icache_miss_o(icache_miss),
    .icache_busy_o(icache_busy),
    .maintenance_valid_i(1'b0),.maintenance_ready_o(unused_maintenance_ready),
    .maintenance_invalidate_i(1'b0),
    .maintenance_cache_enable_i(1'b1),
    .maintenance_done_valid_o(maintenance_done),
    .maintenance_done_ready_i(1'b1),
    .cache_enabled_o(cache_enabled),
    .maintenance_busy_o(maintenance_busy),
    .br_n_o(br_n),.bg_n_i(bg_n),
    .abb_n_i(abb_oe?abb_n:1'b1),.abb_n_o(abb_n),.abb_oe_o(abb_oe),
    .ts_n_o(ts_n),.ts_oe_o(ts_oe),.a_o(a),.tt_o(tt),
    .tbst_n_o(tbst_n),.tsiz_o(tsiz),.tc_o(tc),
    .ci_n_o(ci_n),.wt_n_o(wt_n),.gbl_n_o(gbl_n),
    .cse_o(cse),.addr_oe_o(addr_oe),
    .aack_n_i(aack_n),.artry_n_i(1'b1),.dbg_n_i(dbg_n),
    .dbb_n_i(dbb_oe?dbb_n:1'b1),.dbb_n_o(dbb_n),
    .dbb_oe_o(dbb_oe),.d_i(d_i),.d_o(d_o),.d_oe_o(d_oe),
    .ta_n_i(ta_n),.drtry_n_i(1'b1),.tea_n_i(1'b1)
  );

  function automatic logic [31:0] word_at(input logic [31:0] address);
    int o;o=int'(address-BASE);
    return {mem[o],mem[o+1],mem[o+2],mem[o+3]};
  endfunction
  task automatic check(input bit ok,input string why);
    checks++;
    if(!ok)$fatal(1,"%s cycle=%0d profile=%0d marker=%0d pc=%08x bus=%08x",
      why,cycles,FAULT_PROFILE,active_marker,retired.pc,a);
  endtask
  assign tr=rst_n&&cycles%7>=2;
  assign bg_n=!(rst_n&&!br_n&&cycles%3!=0);
  assign aack_n=!(address_pending&&address_delay==0);
  assign dbg_n=!(transfer_pending&&!address_pending&&cycles%4!=1);
  assign ta_n=!(transfer_pending&&dbb_oe&&!dbb_n&&data_delay==0);
  always_comb begin
    beat_addr=transfer_line ?
      (transfer_addr&32'hffffffe0)+
        32'((((int'(transfer_addr[4:3])+line_beat)&3)*8)) :
      (transfer_addr&32'hfffffff8);
    d_i='0;
    if(transfer_pending&&!transfer_write)
      for(int lane=0;lane<8;lane++)
        d_i[63-8*lane -:8]=mem[int'(beat_addr-BASE)+lane];
  end

  // No abstract physical request or response is used by this RAM responder.
  // The byte address/size and 64-bit data lanes are sampled from the pins.
  always @(posedge clk) begin : pin_ram
    if(!rst_n)begin
      address_pending<=0;transfer_pending<=0;
      address_delay<=0;data_delay<=0;pin_done<=0;
      pin_done_addr<=0;pin_done_write<=0;
      pin_done_size<=0;transfer_line<=0;line_beat<=0;
    end else begin
      pin_done<=0;
      if(address_delay>0)address_delay<=address_delay-1;
      if(data_delay>0&&dbb_oe&&!dbb_n)data_delay<=data_delay-1;
      if(!aack_n)address_pending<=0;
      if(ts_oe&&!ts_n)begin
        check(router_busy&&bus_busy,"60x tenure without translation/bus owner");
        check(addr_oe&&abb_oe&&!abb_n&&!transfer_pending,
          "60x address ownership/overlap");
        check(a>=BASE&&a<=BASE+32'h2fffc&&
          int'(a-BASE)+32<=196608,
          "60x RAM address range");
        check(wt_n&&gbl_n&&cse==0&&(tc==0||tc==2),
          "60x common bus attributes");
        if(!tbst_n)begin
          check(tt==5'b01110&&tsiz==2&&ci_n&&tc==2&&a[2:0]==0,
            "60x cacheable instruction-line shape");
          line_starts++;
        end else begin
          check(tt==5'b01010||tt==5'b00010,
            "60x scalar transaction type");
          check(!ci_n&&(tsiz==1||tsiz==2||tsiz==4),
            "60x cache-inhibited scalar size/attribute");
          if(tc==2)begin
            check(tt==5'b01010&&tsiz==4&&a[1:0]==0,
              "60x scalar instruction shape");
            scalar_ifetches++;
          end
        end
        address_pending<=1;transfer_pending<=1;
        address_delay<=1+cycles%3;data_delay<=2+cycles%4;
        transfer_addr<=a;transfer_write<=tt==5'b00010;
        transfer_instruction<=tc==2;transfer_size<=int'(tsiz);
        transfer_line<=!tbst_n;line_beat<=0;
      end
      if(!ta_n)begin
        check(transfer_pending,"TA without selected tenure");
        if(transfer_write)begin
          check(d_oe,"target accepted undriven write data");
          pin_writes++;
          for(int i=0;i<4;i++)
            if(i<transfer_size)
              mem[int'(transfer_addr-BASE)+i]=
                d_o[63-8*(int'(transfer_addr[2:0])+i) -:8];
        end else begin
          check(!d_oe,"processor drove read data");
          pin_reads++;
          if(transfer_instruction)pin_ifetches++;
        end
        pin_done<=1;pin_done_addr<=transfer_addr;
        pin_done_write<=transfer_write;
        pin_done_size<=transfer_size;
        if(transfer_line)begin
          check(!transfer_write&&transfer_instruction,
            "cache line issued write or data transfer");
          line_beats++;
          if(line_beat==3)transfer_pending<=0;
          else begin
            line_beat<=line_beat+1;
            data_delay<=2+cycles%3;
          end
        end else transfer_pending<=0;
      end
    end
  end

  // Search-profile constants are independent of the linked image.
  function automatic logic [31:0] search_group(input int g);
    case(g)
      0:return 32'hfff19e00;1:return 32'hfff161c0;
      2:return 32'hfff18f00;3:return 32'hfff170c0;
      4:return 32'hfff18f40;5:return 32'hfff17080;
      6:return 32'hfff18f80;default:return 32'hfff17040;
    endcase
  endfunction
  function automatic int search_target_group(input int e);
    case(e)0:return 0;1:return 3;2:return 4;default:return 7;endcase
  endfunction
  function automatic int search_target_slot(input int e);
    case(e)0:return 7;1:return 6;2:return 3;default:return 7;endcase
  endfunction
  function automatic logic [31:0] search_low_addr(input int e);
    return search_group(search_target_group(e))+32'(search_target_slot(e)*8+4);
  endfunction
  function automatic logic [31:0] search_final_low(input int e);
    case(e)
      0:return 32'hfff06102;1:return 32'hfff08102;
      2:return 32'hfff09182;default:return 32'hfff0a182;
    endcase
  endfunction
  function automatic logic [31:0] search_ea(input int e);
    case(e)
      0:return 32'h20000000;1:return 32'h10008004;
      2:return 32'h10009008;default:return 32'h1000a00c;
    endcase
  endfunction
  function automatic int search_scan_total(input int e);
    case(e)0:return 8;1:return 15;2:return 4;default:return 16;endcase
  endfunction
  function automatic logic [31:0] search_scan_addr(input int e,input int n);
    case(e)
      0:return search_group(0)+32'(n*8);
      1:return n<8?search_group(2)+32'(n*8):search_group(3)+32'((n-8)*8);
      2:return search_group(4)+32'(n*8);
      default:return n<8?search_group(6)+32'(n*8):search_group(7)+32'((n-8)*8);
    endcase
  endfunction
  function automatic logic [31:0] search_high(input int e);
    case(e)0:return 32'h802b3c00;1,3:return 32'h80091a40;
      default:return 32'h80091a00;endcase
  endfunction
  function automatic logic [31:0] search_initial_low(input int e);
    case(e)0:return 32'hfff06002;1:return 32'hfff08002;
      2:return 32'hfff09002;default:return 32'hfff0a002;endcase
  endfunction
  function automatic logic [31:0] search_wrong_field(input int k);
    case(k)0:return 32'h80000000;1:return 32'h00000040;
      2:return 32'h00000080;default:return 32'h00000001;endcase
  endfunction
  function automatic logic [31:0] search_before_word(input int g,input int w);
    int slot,kind,e;logic [31:0] high;
    slot=w/2;kind=-1;e=-1;high=0;
    for(int x=0;x<4;x++)
      if(g==search_target_group(x))begin e=x;high=search_high(x);end
    if(e>=0)begin
      if(slot==search_target_slot(e))
        return w%2==0?high:search_initial_low(e);
      if(slot<3)kind=slot;
      else if(slot==3&&e!=2)kind=3;
      else if(slot==4&&e==2)kind=3;
      if(kind>=0)return w%2==0?high^search_wrong_field(kind):
        32'hdec00002+(32'(g)<<16)+(32'(slot)<<12);
    end
    if((g==2||g==6)&&slot==5)
      return w%2==0?32'h80091a40:
        (g==2?32'hdec20502:32'hdec60502);
    return 0;
  endfunction

  // Fault-profile fixed matrix and expected ordinary syndromes.
  function automatic logic [31:0] ordinal_marker(input int n);
    return n<5?32'(n+1):32'(n+11);
  endfunction
  function automatic bit fault_is_i(input int m);
    return m==1||m==4||m==5;
  endfunction
  function automatic bit fault_denied(input int m);
    int pp;bit key,wr;
    if(m<16)return 1;
    key=m>=24;pp=(m-16)/2%4;wr=m%2!=0;
    return (key&&pp==0)||(wr&&(pp==3||(key&&pp==1)));
  endfunction
  function automatic logic [31:0] fault_ea(input int m);
    case(m)
      1:return 32'h20001004;2:return 32'h1000c003;
      3:return 32'h1000d008;4:return 32'h20002008;
      5:return 32'h2000300c;default:return 32'h1000b004;
    endcase
  endfunction
  function automatic logic [31:0] fault_sr(input int m);
    if(m==5)return 32'h40005678;
    if(fault_is_i(m))return 32'h00005678;
    return m>=24?32'h40001234:32'h00001234;
  endfunction
  function automatic logic [31:0] fault_primary(input int m);
    case(m)
      1:return 32'hfff19e40;2:return 32'hfff18e00;
      3:return 32'hfff18e40;4:return 32'hfff19e80;
      5:return 32'hfff19ec0;default:return 32'hfff18fc0;
    endcase
  endfunction
  function automatic logic [31:0] fault_secondary(input int m);
    case(m)
      1:return 32'hfff16180;2:return 32'hfff171c0;
      3:return 32'hfff17180;4:return 32'hfff16140;
      5:return 32'hfff16100;default:return 32'hfff17000;
    endcase
  endfunction
  function automatic int fault_scan_total(input int m);
    case(m)1,2,3:return 16;4:return 5;5:return 3;default:return 6;endcase
  endfunction
  function automatic logic [31:0] fault_scan_addr(input int m,input int n);
    return n<8?fault_primary(m)+32'(n*8):fault_secondary(m)+32'((n-8)*8);
  endfunction
  function automatic logic [31:0] fault_low_addr(input int m);
    case(m)4:return 32'hfff19ea4;5:return 32'hfff19ed4;
      default:return 32'hfff18fec;endcase
  endfunction
  function automatic logic [31:0] fault_low_before(input int m);
    case(m)4:return 32'hfff0d00a;5:return 32'hfff0e000;
      default:return 32'hfff0c000|32'((m-16)/2%4);endcase
  endfunction
  function automatic logic [31:0] fault_srr1(input int m);
    case(m)1:return 32'h40000070;4:return 32'h10000070;
      5:return 32'h08000070;default:return 32'h00000070;endcase
  endfunction
  function automatic logic [31:0] fault_dsisr(input int m);
    case(m)2:return 32'h40000000;3:return 32'h42000000;
      default:return 32'h08000000|(m%2!=0?32'h02000000:0);endcase
  endfunction

  int search_misses=0,search_seed=0,search_tlbli=0,search_tlbld=0;
  int search_rfi=0,search_probe=0,search_loads=0,search_stores=0;
  int search_scan[4],search_low[4],search_write[4],search_fill[4];
  logic [31:0] search_store_pc=0;
  logic [31:0] active_marker=0;
  int fault_started=0,fault_misses=0,fault_vectors=0,fault_fills=0;
  int fault_miss_n[32],fault_vector_n[32],fault_scan_n[32];
  int fault_low_n[32],fault_write_n[32],fault_fill_n[32],fault_target_n[32];
  logic [31:0] fault_event_pc[32],fault_event_cr[32];
  logic [31:0] fault_event_gpr[32][32];

  task automatic search_check_table(input int through_event);
    logic [31:0] expected;
    for(int g=0;g<8;g++)
      for(int w=0;w<16;w++)begin
        expected=search_before_word(g,w);
        for(int e=0;e<4;e++)
          if(e<=through_event&&g==search_target_group(e)&&
             w==search_target_slot(e)*2+1)expected=search_final_low(e);
        check(word_at(search_group(g)+32'(w*4))==expected,
          $sformatf("search PTE mismatch group=%0d word=%0d got=%08x expected=%08x",
            g,w,word_at(search_group(g)+32'(w*4)),expected));
      end
  endtask

  always @(posedge clk) begin : oracle
    int e,m,n,record;
    logic [31:0] ra;
    if(!rst_n)begin
      for(int j=0;j<4;j++)begin
        search_scan[j]=0;search_low[j]=0;search_write[j]=0;search_fill[j]=0;
      end
      for(int j=0;j<32;j++)begin
        fault_miss_n[j]=0;fault_vector_n[j]=0;fault_scan_n[j]=0;
        fault_low_n[j]=0;fault_write_n[j]=0;fault_fill_n[j]=0;
        fault_target_n[j]=0;fault_event_pc[j]=0;fault_event_cr[j]=0;
        for(int k=0;k<32;k++)fault_event_gpr[j][k]=0;
      end
    end else begin
      cycles++;
      check(cycles<(FAULT_PROFILE==0?1500000:8000000),
        $sformatf({"timeout retires=%0d misses=%0d/%0d marker=%0d IQ=%0d ",
          "fetch=%b rsp=%b/%b router=%0d managed=%b/%b ",
          "special=%0d bus=%b cache=%b pins=%b/%b"},
          retires,search_misses,fault_misses,active_marker,
          dut.translated_core.core.iq.count,
          dut.translated_core.core.fetch.pending,
          dut.imem_rsp_valid,dut.imem_rsp_ready,
          dut.translated_core.router.state_q,
          dut.cache_fetch_rsp_valid,dut.cache_fetch_rsp_ready,
          dut.translated_core.core.special.state_q,bus_busy,icache_busy,
          address_pending,transfer_pending));
      check(!halted&&!cut_accepted&&!pimem_error&&!ifetch_error&&
        !bus_error&&!interrupt_taken&&!decrementer_taken,
         $sformatf("unexpected transport or translation failure halted=%b cut=%b pimem=%b ifetch=%b bus=%b translation=%b interrupt=%b dec=%b ea=%08x fi=%b fw=%b fm=%b fp=%b fg=%b fc=%b msr=%08x misses=%0d retired=%0d",halted,cut_accepted,pimem_error,ifetch_error,bus_error,translation_fault,interrupt_taken,decrementer_taken,unused_fault_ea,unused_fault_instruction,unused_fault_write,unused_fault_miss,unused_fault_protection,unused_fault_guarded,unused_fault_config,dut.translated_core.core.msr,search_misses,retires));
      if(search_misses>0||fault_misses>0)
        check(translation_fault,"router missed sticky page diagnostic");
      check(!unused_page_ports[1]&&!bat_valid&&!bat_rsp&&
        !bat_rejected&&!bat_unsupported&&!bat_config&&!bat_overlap&&
        bat_invalid==0,"external management unexpectedly active");
      if(running)check(!bat_ready&&!cpr,"unexpected privilege context");
      if(icache_hit)cache_hits++;
      if(icache_miss)cache_misses++;
      check(!maintenance_done&&!maintenance_busy&&cache_enabled,
        "unexpected cache maintenance/disable");
      if(dut.translated_core.core.msr[17]!=last_bank)begin
        check(dut.translated_core.core.frontend_fence&&
          !dut.translated_core.core.gpr_commit&&
          !dut.translated_core.core.update_commit,
          "TGPR switch escaped serialization");
        last_bank=dut.translated_core.core.msr[17];bank_switches++;
      end

      // Address phase is the independent pin-level search/target oracle.
      if(ts_oe&&!ts_n)begin
        if(FAULT_PROFILE==0)begin
          if(tc==2&&cir&&a>=32'hfff06000&&a<32'hfff06010)search_probe++;
          if(tc==0&&dut.translated_core.core.msr[17]&&
             a>=HTAB&&a<HTAB+32'h10000)begin
            check(search_misses>=1&&search_misses<=4,
              "search PTEG access without selected miss");
            e=search_misses-1;
            if(tt==5'b00010)begin
              check(a==search_low_addr(e)+2&&
                tsiz==(e<2?1:2)&&search_write[e]==0&&
                search_low[e]==1&&search_scan[e]==search_scan_total(e),
                "search R/C write not after exact PTE1 and PTE0 scan");
              search_write[e]++;
            end else if(a==search_low_addr(e))begin
              check(search_low[e]==0&&search_scan[e]==search_scan_total(e),
                "search PTE1 read before exact PTE0 match");
              search_low[e]++;
            end else begin
              check(search_scan[e]<search_scan_total(e)&&
                a==search_scan_addr(e,search_scan[e]),
                "search PTE0 primary/secondary order");
              search_scan[e]++;
            end
          end
          if(tc==0&&tt==5'b01010&&cdr&&a==32'hfff08004)search_loads++;
          if(tc==0&&tt==5'b00010&&cdr&&
            (a==32'hfff09008||a==32'hfff0a00c))search_stores++;
        end else begin
          m=int'(active_marker);
          if(tc==2)begin
            if(m==1)check(a<32'hfff06000,
              "absent I page reached physical target");
            if(m==4)check(a<32'hfff0d000||a>=32'hfff0e000,
              "guarded I page reached physical target");
            if(m==5)check(a<32'hfff0e000||a>=32'hfff0f000,
              "protected I page reached physical target");
            if(a==32'hfff00300||a==32'hfff00400)begin
              check(m>0&&m<32&&fault_denied(m)&&
                fault_miss_n[m]==1&&fault_vector_n[m]==0,
                "ordinary vector provenance/count");
              check(a==(fault_is_i(m)?32'hfff00400:32'hfff00300),
                "ordinary vector kind");
              check(dut.translated_core.core.msr==32'h40&&
                dut.translated_core.core.srr0==fault_event_pc[m]&&
                dut.translated_core.core.srr1==fault_srr1(m),
                "ordinary vector MSR/SRR0/SRR1");
              if(!fault_is_i(m))
                check(dut.translated_core.core.special.dar_q==fault_ea(m)&&
                  dut.translated_core.core.special.dsisr_q==fault_dsisr(m),
                  "ordinary DSI DAR/DSISR");
              check(dut.translated_core.core.cr==fault_event_cr[m],
                "normal CR changed before ordinary vector");
              for(int k=0;k<32;k++)
                check(dut.translated_core.core.regfile.gpr[k]==fault_event_gpr[m][k],
                  $sformatf("normal GPR%0d changed before ordinary vector",k));
              check(fault_write_n[m]==0&&fault_fill_n[m]==0&&
                fault_target_n[m]==0,"failed search changed PTE/TLB/target");
              if(m>=4)check(word_at(fault_low_addr(m))==fault_low_before(m),
                "failed search changed R/C");
              fault_vector_n[m]++;fault_vectors++;
            end
          end else if(dut.translated_core.core.msr[17]&&
                    a>=HTAB&&a<HTAB+32'h10000)begin
            check(m>0&&m<32&&fault_miss_n[m]==1,
              "fault PTE access without selected miss");
            if(tt==5'b00010)begin
              check(m>=16&&!fault_denied(m)&&
                a==fault_low_addr(m)+2&&
                tsiz==(m%2!=0?2:1)&&
                fault_scan_n[m]==6&&fault_low_n[m]==1&&
                fault_write_n[m]==0,
                "fault PTE R/C write on denied page or before scan");
              fault_write_n[m]++;
            end else if(m>=4&&a==fault_low_addr(m))begin
              check(fault_scan_n[m]==fault_scan_total(m)&&fault_low_n[m]==0,
                "fault PTE1 read before match");
              fault_low_n[m]++;
            end else begin
              n=fault_scan_n[m];
              check(n<fault_scan_total(m)&&a==fault_scan_addr(m,n),
                "fault PTE0 primary/secondary order");
              fault_scan_n[m]++;
            end
          end
          if(tc==0&&a==32'hfff0c004&&
             dut.translated_core.core.special.ea_q==32'h1000b004)begin
            check(m>=16&&!fault_denied(m),
              "denied matrix case reached physical target");
            fault_target_n[m]++;
          end
        end
      end

      // Completed pin writes alone mutate the RAM. Observe their effects one
      // cycle later; do not mirror hierarchical physical request payloads.
      if(pin_done&&pin_done_write)begin
        if(pin_done_addr==tohost_addr&&word_at(tohost_addr)!=0)begin
          check(pin_done_size==4&&word_at(tohost_addr)==1,
            $sformatf("firmware failure mailbox=%08x",word_at(tohost_addr)));
          check(!mailbox_written,"duplicate mailbox");mailbox_written=1;
        end
        if(FAULT_PROFILE==0)begin
          for(int x=0;x<4;x++)
            if(pin_done_addr==search_low_addr(x)+2&&
               search_misses==x+1)begin
              check(word_at(search_low_addr(x))==search_final_low(x),
                "search R/C bus write data/lanes");
              search_check_table(x);
            end
        end else begin
          if(pin_done_addr==MARKER)begin
            check(pin_done_size==4&&
              word_at(MARKER)==ordinal_marker(fault_started),
              "fault case marker order");
            active_marker=word_at(MARKER);fault_started++;
          end
          m=int'(active_marker);
          if(m>=16&&m<32&&pin_done_addr==fault_low_addr(m)+2&&
             dut.translated_core.core.msr[17])
            check(word_at(fault_low_addr(m))==
              (fault_low_before(m)|(m%2!=0?32'h180:32'h100)),
              "fault R/C bus write lanes/data");
        end
      end

      if(dut.translated_core.tlb_fill_req_valid&&
         dut.translated_core.tlb_fill_req_ready)begin
        if(FAULT_PROFILE==0)begin
          if(search_misses==0)begin
            check(dut.translated_core.tlb_fill_req_bank&&
              dut.translated_core.tlb_fill_req_way&&
              dut.translated_core.tlb_fill_req_ea==32'h1000a00c&&
              dut.translated_core.tlb_fill_req_rpn==20'hfff0a&&
              !dut.translated_core.tlb_fill_req_c,
              "resident C=0 way-one seed fill");
            search_seed++;
          end else begin
            e=search_misses-1;
            check(search_write[e]==1&&search_low[e]==1&&
              search_scan[e]==search_scan_total(e)&&
              word_at(search_low_addr(e))==search_final_low(e),
              "TLB fill preceded completed bus R/C update");
            check(dut.translated_core.tlb_fill_req_bank==(e!=0)&&
              dut.translated_core.tlb_fill_req_way==(e==3)&&
              dut.translated_core.tlb_fill_req_ea==search_ea(e)&&
              dut.translated_core.tlb_fill_req_vsid==
                (e==0?24'h5678:24'h1234)&&
              dut.translated_core.tlb_fill_req_rpn==
                20'(search_final_low(e)>>12)&&
              dut.translated_core.tlb_fill_req_c==(e>=2)&&
              dut.translated_core.tlb_fill_req_pp==2'b10&&
              dut.translated_core.tlb_fill_req_wimg==0,
              "search TLB fill payload");
            search_fill[e]++;
          end
        end else begin
          m=int'(active_marker);
          check(m>=16&&!fault_denied(m)&&fault_miss_n[m]==1&&
            fault_scan_n[m]==6&&fault_low_n[m]==1&&
            fault_write_n[m]==1&&
            word_at(fault_low_addr(m))==
              (fault_low_before(m)|(m%2!=0?32'h180:32'h100)),
            "fault fill before committed bus R/C update");
          check(dut.translated_core.tlb_fill_req_bank&&
            dut.translated_core.tlb_fill_req_ea==32'h1000b004&&
            dut.translated_core.tlb_fill_req_vsid==24'h1234&&
            dut.translated_core.tlb_fill_req_rpn==20'hfff0c&&
            dut.translated_core.tlb_fill_req_c==(m%2!=0)&&
            dut.translated_core.tlb_fill_req_pp==2'((m-16)/2%4)&&
            dut.translated_core.tlb_fill_req_wimg==0,
            "fault allowed-case fill payload");
          fault_fill_n[m]++;fault_fills++;
        end
      end

      if(tv&&tr)begin
        check(!retired.illegal&&!retired.alignment_exception&&
          (retired.fetch_fault==FETCH_OK||retired.fetch_fault==FETCH_PAGE_MISS)&&
          (retired.data_fault==DATA_OK||retired.data_fault==DATA_PAGE_MISS||
           (FAULT_PROFILE==0&&retired.data_fault==DATA_PAGE_CHANGED)),
          "unexpected retire diagnostic");
        if(FAULT_PROFILE==0)begin
          if(retired.fetch_fault==FETCH_PAGE_MISS||
             retired.data_fault!=DATA_OK)begin
            e=search_misses;
            check(e<4&&!retired.gpr_write&&!retired.update_write&&
              !retired.write_xer,"search miss retirement effects/count");
            check(retired.page_miss.ir&&retired.page_miss.dr&&
              !retired.page_miss.pr&&
              retired.page_miss.ea==search_ea(e)&&
              retired.page_miss.sr==(e==0?32'h5678:32'h1234)&&
              retired.page_miss.way==(e==3)&&
              retired.page_miss.write==(e>=2),
              "search full-EA capsule or matched way");
            if(e==0)check(retired.fetch_fault==FETCH_PAGE_MISS&&
              retired.pc==32'h20000000,"search instruction miss");
            else if(e==3)check(retired.data_fault==DATA_PAGE_CHANGED,
              "search changed-bit miss");
            else check(retired.data_fault==DATA_PAGE_MISS,
              "search data miss");
            if(e==0)search_check_table(-1);
            if(e==2)search_store_pc=retired.pc;
            if(e==3)check(retired.pc==search_store_pc,
              "search shared store probe");
            search_misses++;
          end else check(retired.page_miss=='0,
            "normal search retire retained miss capsule");
          if(retired.insn[31:26]==31&&retired.insn[10:1]==978)search_tlbld++;
          if(retired.insn[31:26]==31&&retired.insn[10:1]==1010)search_tlbli++;
          if(retired.insn==32'h4c000064&&retired.pc>=BASE+32'h2000)
            search_rfi++;
        end else begin
          if(retired.fetch_fault==FETCH_PAGE_MISS||
             retired.data_fault==DATA_PAGE_MISS)begin
            m=int'(active_marker);
            check(m>0&&m<32&&fault_miss_n[m]==0&&
              !retired.gpr_write&&!retired.update_write&&
              !retired.write_xer&&!retired.write_cr0,
              "fault typed miss retirement effects/count");
            check(retired.page_miss.ir&&retired.page_miss.dr&&
              !retired.page_miss.pr&&
              retired.page_miss.ea==
                (fault_is_i(m)?fault_ea(m):(fault_ea(m)&32'hfffffffc))&&
              retired.page_miss.sr==fault_sr(m)&&
              !retired.page_miss.way&&
              retired.page_miss.write==(m==3||(m>=16&&m%2!=0)),
              "fault typed full-EA capsule");
            check(fault_is_i(m)?
              (retired.fetch_fault==FETCH_PAGE_MISS&&retired.pc==fault_ea(m)):
              (retired.data_fault==DATA_PAGE_MISS),
              "fault typed miss kind/PC");
            fault_event_pc[m]=retired.pc;
            fault_event_cr[m]=dut.translated_core.core.cr;
            for(int k=0;k<32;k++)
              fault_event_gpr[m][k]=dut.translated_core.core.regfile.gpr[k];
            fault_miss_n[m]++;fault_misses++;
          end else check(retired.page_miss=='0,
            "normal fault retire retained miss capsule");
        end
        if(mailbox_written&&!mailbox_retired)begin
          check(retired.insn[31:26]==36&&!retired.gpr_write&&
            !retired.update_write,"mailbox retirement");
          mailbox_retired=1;
        end
        retires++;
      end

      if(mailbox_retired)begin
        if(FAULT_PROFILE==0)begin
          check(search_misses==4&&search_rfi==4&&
            bank_switches==8&&!last_bank&&search_seed==1&&
            search_tlbli==1&&search_tlbld==4&&
            search_loads>=1&&search_stores==2&&search_probe>=1,
            "search event/fill/retry totals");
          for(int x=0;x<4;x++)
            check(search_scan[x]==search_scan_total(x)&&
              search_low[x]==1&&search_write[x]==1&&search_fill[x]==1,
              "search PTE scan/update/fill total");
          search_check_table(3);
          check(word_at(32'hfff08004)==32'h13579bdf&&
            word_at(32'hfff09008)==32'h2468ace0&&
            word_at(32'hfff0a00c)==32'haabbccdd,
            "search retry target memory");
          check(line_starts>0&&line_beats==4*line_starts&&
            scalar_ifetches>0&&cache_hits>0&&cache_misses>0,
            "search cache/bypass path coverage");
          $display("PASS compiled table search cached 60x: misses=%0d lines=%0d beats=%0d bypass=%0d hits=%0d retires=%0d cycles=%0d checks=%0d",
            search_misses,line_starts,line_beats,scalar_ifetches,
            cache_hits,retires,cycles,checks);
        end else begin
          check(fault_started==21&&fault_misses==21&&
            fault_vectors==10&&fault_fills==11,
            "fault case/miss/vector/fill totals");
          check(word_at(fault_count_addr)==32'd10,
            "ordinary fault record count");
          record=0;
          for(int j=0;j<21;j++)begin
            m=int'(ordinal_marker(j));
            check(fault_miss_n[m]==1&&
              fault_scan_n[m]==fault_scan_total(m)&&
              fault_low_n[m]==(m>=4?1:0),
              "fault per-case PTE search");
            check(fault_write_n[m]==(fault_denied(m)?0:1)&&
              fault_fill_n[m]==(fault_denied(m)?0:1)&&
              fault_vector_n[m]==(fault_denied(m)?1:0)&&
              fault_target_n[m]==(fault_denied(m)?0:1),
              "fault per-case effects");
            if(fault_denied(m))begin
              ra=fault_records_addr+32'(record*24);
              check(word_at(ra)==32'(m)&&
                word_at(ra+4)==fault_event_pc[m]&&
                word_at(ra+8)==fault_srr1(m)&&
                word_at(ra+20)==32'h40,
                "fault ordinary record marker/PC/SRR1/MSR");
              if(!fault_is_i(m))
                check(word_at(ra+12)==fault_ea(m)&&
                  word_at(ra+16)==fault_dsisr(m),
                  "fault ordinary DAR/DSISR");
              record++;
            end
          end
          check(record==10&&!last_bank,
            "fault ordinary records/TGPR return");
          check(word_at(32'hfff19ea4)==32'hfff0d00a&&
            word_at(32'hfff19ed4)==32'hfff0e000,
            "fault guarded/protected PTE changed");
          check(line_starts>0&&line_beats==4*line_starts&&
            scalar_ifetches>0&&cache_hits>0&&cache_misses>0,
            "fault cache/bypass path coverage");
          $display("PASS compiled table fault cached 60x: cases=%0d misses=%0d vectors=%0d fills=%0d lines=%0d beats=%0d bypass=%0d hits=%0d retires=%0d cycles=%0d checks=%0d",
            fault_started,fault_misses,fault_vectors,fault_fills,
            line_starts,line_beats,scalar_ifetches,cache_hits,
            retires,cycles,checks);
        end
        $finish;
      end
    end
  end

  assert property(@(posedge clk) disable iff(!rst_n)
    tv&&!tr |=> tv&&$stable(retired));
  initial begin
    if(!$value$plusargs("IMAGE=%s",image_path)||
       !$value$plusargs("TOHOST=%h",tohost_addr))
      $fatal(1,"IMAGE/TOHOST required");
    if(FAULT_PROFILE!=0&&
       (!$value$plusargs("FAULT_COUNT=%h",fault_count_addr)||
        !$value$plusargs("FAULT_RECORDS=%h",fault_records_addr)))
      $fatal(1,"FAULT_COUNT/FAULT_RECORDS required");
    check(tohost_addr==BASE+32'h4000,"mailbox address");
    foreach(mem[i])mem[i]=0;
    $readmemh(image_path,mem,0,65535);
    repeat(4)@(negedge clk);rst_n=1;
    @(negedge clk);start_valid=1;
    do @(posedge clk);while(!start_ready);
    @(negedge clk);start_valid=0;
  end
endmodule
