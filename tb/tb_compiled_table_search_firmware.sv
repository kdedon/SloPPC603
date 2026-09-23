// Compiled software primary/secondary PTEG search, R/C update, and retry.
// Physical byte RAM uses independent delayed/backpressured instruction/data ports.
/* verilator lint_off BLKSEQ */
module tb_compiled_table_search_firmware;
  import ppc_pkg::*;
  localparam logic [31:0] BASE=32'hfff00000;
  logic clk=0,rst_n=0;
  always #5 clk=~clk;
  logic iv,ir,sv,sr,dv,dr,dw,rv,rr,tv,tr,halted,cut_accepted;
  logic [31:0] ia,iw,da,wd,rd,tohost_addr;
  logic [3:0] st,iwimg,dwimg;
  logic bat_valid=0,bat_ready,bat_rsp,bat_rejected,bat_unsupported,bat_config,bat_overlap;
  logic [3:0] bat_invalid;
  logic [9:0] bat_spr=0;
  logic [31:0] bat_data=0;
  logic start_valid=0,start_ready,running,cir,cdr,cpr,unused_fault,physical_error;
  /* verilator lint_off UNUSEDSIGNAL */
  logic unused_busy,unused_fi,unused_fw,unused_fm,unused_fp,unused_fg,unused_fc,unused_finv;
  logic [31:0] unused_fea;
  logic [3:0] unused_fentries;
  /* verilator lint_on UNUSEDSIGNAL */
  /* verilator lint_off UNUSEDSIGNAL */
  retire_packet_t retired;
  /* verilator lint_on UNUSEDSIGNAL */
  logic [7:0] mem[0:196607];
  logic ipending=0,dpending=0,mailbox_written=0,mailbox_retired=0;
  logic [31:0] fetch_pc;
  int idelay=0,ddelay=0,cycles=0,retires=0,checks=0,reads=0,writes=0;
  int mtmsr_retires=0,rfi_retires=0,bank_switches=0;
  int misses=0,tlbli=0,tlbld=0,seed_fills=0,probe_fetches=0;
  int translated_loads=0,translated_stores=0;
  int scan_reads[4],low_reads[4],pte_writes[4],handler_fills[4];
  logic [31:0] store_probe_pc;
  logic last_bank=0;
  logic external_irq,interrupt_taken,decrementer_taken;

  logic [31:0] unused_decrementer_pc;
  logic [31:0] unused_interrupt_pc;
  assign external_irq=0;
  string image_path;
  logic [49:0] unused_page_ports;
  ppc_core_bat #(.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1),.ENABLE_TGPR(1'b1),.ENABLE_SDR1(1'b1),.ENABLE_RUNTIME_BAT(1'b1),
                 .ENABLE_SEGMENT_REGISTERS(1'b1),.ENABLE_PAGE_TRANSLATION(1'b1),
                 .ENABLE_TLB_LOAD(1'b1),.ENABLE_PAGE_MISS_RESULTS(1'b1),
                 .ENABLE_TLB_MISS_EXCEPTIONS(1'b1)) dut(
    .tlb_mgmt_req_valid_i('0),
    .tlb_mgmt_req_ready_o(unused_page_ports[0]),
    .tlb_mgmt_req_kind_i('0),
    .tlb_mgmt_req_bank_i('0),
    .tlb_mgmt_req_ea_i('0),
    .tlb_mgmt_req_vsid_i('0),
    .tlb_mgmt_req_pr_i('0),
    .tlb_mgmt_req_way_i('0),
    .tlb_mgmt_req_rpn_i('0),
    .tlb_mgmt_req_c_i('0),
    .tlb_mgmt_req_wimg_i('0),
    .tlb_mgmt_req_pp_i('0),
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
    .clk_i(clk),.rst_ni(rst_n),
    .external_irq_i(external_irq),.interrupt_taken_o(interrupt_taken),.interrupt_pc_o(unused_interrupt_pc),
    .timer_tick_i(1'b0),.timebase_enable_i(1'b0),
    .decrementer_taken_o(decrementer_taken),.decrementer_pc_o(unused_decrementer_pc),
    .bat_write_valid_i(bat_valid),.bat_write_ready_o(bat_ready),
    .bat_write_spr_i(bat_spr),.bat_write_data_i(bat_data),
    .bat_write_rsp_valid_o(bat_rsp),.bat_write_rsp_ready_i(1'b1),
    .bat_write_rsp_rejected_o(bat_rejected),.bat_write_rsp_unsupported_o(bat_unsupported),
    .bat_write_rsp_config_error_o(bat_config),.bat_write_rsp_overlap_o(bat_overlap),
    .bat_write_rsp_invalid_entry_o(bat_invalid),
    .start_valid_i(start_valid),.start_ready_o(start_ready),
    .start_ir_i(1'b0),.start_dr_i(1'b0),.start_pr_i(1'b0),.running_o(running),
    .context_ir_o(cir),.context_dr_o(cdr),.context_pr_o(cpr),
    .pimem_req_valid_o(iv),.pimem_req_ready_i(ir),.pimem_req_addr_o(ia),.pimem_req_wimg_o(iwimg),
    .pimem_rsp_valid_i(sv),.pimem_rsp_ready_o(sr),.pimem_rsp_insn_i(iw),.pimem_rsp_error_i(1'b0),
    .pdmem_req_valid_o(dv),.pdmem_req_ready_i(dr),.pdmem_req_write_o(dw),
    .pdmem_req_addr_o(da),.pdmem_req_wdata_o(wd),.pdmem_req_wstrb_o(st),.pdmem_req_wimg_o(dwimg),
    .pdmem_rsp_valid_i(rv),.pdmem_rsp_ready_o(rr),.pdmem_rsp_rdata_i(rd),.pdmem_rsp_error_i(1'b0),
    .retire_valid_o(tv),.retire_ready_i(tr),.retire_o(retired),.halted_o(halted),
    .redirect_valid_i(1'b0),.redirect_all_i(1'b0),.redirect_keep_pivot_i(1'b0),
    .redirect_pivot_i('0),.redirect_target_i('0),.redirect_accepted_o(cut_accepted),
    .translation_fault_o(unused_fault),.fault_instruction_o(unused_fi),.fault_write_o(unused_fw),
    .fault_ea_o(unused_fea),.fault_miss_o(unused_fm),.fault_protection_o(unused_fp),
    .fault_guarded_o(unused_fg),.fault_config_o(unused_fc),.fault_invalid_input_o(unused_finv),
    .fault_invalid_entry_o(unused_fentries),.pimem_error_o(physical_error),.busy_o(unused_busy));
  localparam logic [31:0] HTAB=32'hfff10000;
  function automatic logic [31:0] word_at(input logic [31:0] address);
    int o; o=int'(address-BASE); return {mem[o],mem[o+1],mem[o+2],mem[o+3]};
  endfunction
  function automatic logic [31:0] group_base(input int group);
    case(group)
      0:return 32'hfff19e00; 1:return 32'hfff161c0;
      2:return 32'hfff18f00; 3:return 32'hfff170c0;
      4:return 32'hfff18f40; 5:return 32'hfff17080;
      6:return 32'hfff18f80; default:return 32'hfff17040;
    endcase
  endfunction
  function automatic int target_group(input int event_index);
    case(event_index)
      0:return 0; 1:return 3; 2:return 4; default:return 7;
    endcase
  endfunction
  function automatic int target_slot(input int event_index);
    case(event_index)
      0:return 7; 1:return 6; 2:return 3; default:return 7;
    endcase
  endfunction
  function automatic logic [31:0] target_high(input int event_index);
    case(event_index)
      0:return 32'h802b3c00;
      1,3:return 32'h80091a40;
      default:return 32'h80091a00;
    endcase
  endfunction
  function automatic logic [31:0] initial_low(input int event_index);
    case(event_index)
      0:return 32'hfff06002; 1:return 32'hfff08002;
      2:return 32'hfff09002; default:return 32'hfff0a002;
    endcase
  endfunction
  function automatic logic [31:0] final_low(input int event_index);
    case(event_index)
      0:return 32'hfff06102; 1:return 32'hfff08102;
      2:return 32'hfff09182; default:return 32'hfff0a182;
    endcase
  endfunction
  function automatic logic [31:0] miss_ea(input int event_index);
    case(event_index)
      0:return 32'h20000000; 1:return 32'h10008004;
      2:return 32'h10009008; default:return 32'h1000a00c;
    endcase
  endfunction
  function automatic logic [31:0] low_addr(input int event_index);
    return group_base(target_group(event_index)) +
           32'(target_slot(event_index)*8+4);
  endfunction
  function automatic int scan_total(input int event_index);
    case(event_index)
      0:return 8; 1:return 15; 2:return 4; default:return 16;
    endcase
  endfunction
  function automatic logic [31:0] scan_addr(input int event_index,
    input int ordinal);
    case(event_index)
      0:return group_base(0)+32'(ordinal*8);
      1:return ordinal<8?group_base(2)+32'(ordinal*8):
                 group_base(3)+32'((ordinal-8)*8);
      2:return group_base(4)+32'(ordinal*8);
      default:return ordinal<8?group_base(6)+32'(ordinal*8):
                 group_base(7)+32'((ordinal-8)*8);
    endcase
  endfunction
  function automatic logic [31:0] wrong_field(input int kind);
    case(kind)
      0:return 32'h80000000; 1:return 32'h00000040;
      2:return 32'h00000080; default:return 32'h00000001;
    endcase
  endfunction
  function automatic logic [31:0] before_word(input int group,input int word);
    int slot,kind,event_index;
    logic [31:0] high;
    slot=word/2;kind=-1;event_index=-1;high=0;
    for(int ev=0;ev<4;ev++)
      if(group==target_group(ev))begin event_index=ev;high=target_high(ev);end
    if(event_index>=0)begin
      if(slot==target_slot(event_index))
        return (word%2==0)?high:initial_low(event_index);
      if(slot<3)kind=slot;
      else if(slot==3&&event_index!=2)kind=3;
      else if(slot==4&&event_index==2)kind=3;
      if(kind>=0)
        return (word%2==0)?(high^wrong_field(kind)):
          (32'hdec00002+(32'(group)<<16)+(32'(slot)<<12));
    end
    if((group==2||group==6)&&slot==5)
      return (word%2==0)?32'h80091a40:
             (group==2?32'hdec20502:32'hdec60502);
    return 0;
  endfunction
  task automatic check(input logic ok,input string message);
    checks++;if(!ok)$fatal(1,"%s cycle=%0d pc=%08x addr=%08x misses=%0d",message,
      cycles,retired.pc,da,misses);
  endtask
  task automatic check_table(input int updates_completed);
    logic [31:0] expected;
    for(int group=0;group<8;group++)
      for(int word=0;word<16;word++)begin
        expected=before_word(group,word);
        for(int ev=0;ev<4;ev++)
          if(ev<=updates_completed&&group==target_group(ev)&&
             word==target_slot(ev)*2+1)expected=final_low(ev);
        check(word_at(group_base(group)+32'(word*4))==expected,
          $sformatf("table mismatch group=%0d word=%0d got=%08x expected=%08x",
            group,word,word_at(group_base(group)+32'(word*4)),expected));
      end
  endtask
  assign ir=rst_n&&!ipending&&cycles%4!=1;
  assign sv=rst_n&&ipending&&idelay==0;
  assign iw=word_at(fetch_pc);
  assign dr=rst_n&&!dpending&&cycles%5!=2;
  assign rv=rst_n&&dpending&&ddelay==0;
  assign tr=rst_n&&cycles%7>=2;
  always @(posedge clk)begin : monitor
    int event_index;
    if(!rst_n)begin
      ipending<=0;dpending<=0;idelay<=0;ddelay<=0;fetch_pc<=BASE;rd<=0;
      for(int ev=0;ev<4;ev++)begin
        scan_reads[ev]=0;low_reads[ev]=0;pte_writes[ev]=0;handler_fills[ev]=0;
      end
    end else begin
      cycles++;
      check(cycles<300000,"table-search firmware timeout");
      if(dut.core.msr[17]!=last_bank)begin
        check(dut.core.frontend_fence&&!dut.core.gpr_commit&&
              !dut.core.update_commit,"TGPR bank switch escaped serialization");
        last_bank=dut.core.msr[17];bank_switches++;
      end
      check(!halted&&!cut_accepted&&!physical_error&&
            !interrupt_taken&&!decrementer_taken,"unexpected fault/event");
      check(!unused_page_ports[1],"fixture TLB management active");
      check(!bat_valid&&!bat_rsp&&!bat_rejected&&!bat_unsupported&&
            !bat_config&&!bat_overlap&&bat_invalid==0,"fixture BAT management active");
      if(running)check(!bat_ready&&!cpr,"unexpected privilege context");
      if(idelay>0)idelay<=idelay-1;
      if(ddelay>0)ddelay<=ddelay-1;
      if(sv&&sr)ipending<=0;
      if(rv&&rr)dpending<=0;
      if(iv&&ir)begin
        check(ia>=BASE&&ia<=BASE+32'h2fffc&&ia[1:0]==0,
          "instruction RAM range");
        check(iwimg==(cir?4'b0000:4'b0001),"instruction attributes");
        if(cir&&ia>=32'hfff06000&&ia<32'hfff06010)probe_fetches++;
        ipending<=1;fetch_pc<=ia;idelay<=1+cycles%4;
      end
      if(dv&&dr)begin
        check(da>=BASE&&da<=BASE+32'h2fffc&&da[1:0]==0,
          "data RAM range");
        check(dwimg==(cdr?4'b0000:4'b0011),"data attributes");
        dpending<=1;ddelay<=1+cycles%5;rd<=word_at(da);
        if(dut.core.msr[17]&&da>=HTAB&&da<HTAB+32'h10000)begin
          check(misses>=1&&misses<=4,"PTEG access without a selected miss");
          event_index=misses-1;
          if(dw)begin
            check(da==low_addr(event_index)&&
                  st==(event_index<2?4'b0010:4'b0011)&&
                  pte_writes[event_index]==0&&
                  low_reads[event_index]==1&&
                  scan_reads[event_index]==scan_total(event_index),
                  "PTE R/C write missed selected lowword or search order");
            pte_writes[event_index]++;
          end else if(da==low_addr(event_index))begin
            check(low_reads[event_index]==0&&
                  scan_reads[event_index]==scan_total(event_index),
                  "PTE1 read before exact PTE0 match");
            low_reads[event_index]++;
          end else begin
            check(scan_reads[event_index]<scan_total(event_index)&&
                  da==scan_addr(event_index,scan_reads[event_index]),
                  "PTE0 scan skipped/duplicated primary or secondary slot");
            scan_reads[event_index]++;
          end
        end
        if(dw)begin
          writes++;
          for(int lane=0;lane<4;lane++)
            if(st[3-lane])mem[int'(da-BASE)+lane]=wd[31-lane*8 -:8];
          if(dut.core.msr[17]&&da>=HTAB&&da<HTAB+32'h10000)begin
            event_index=misses-1;
            check(word_at(da)==final_low(event_index),
              "PTE R/C update wrote incorrect byte/halfword");
            check_table(event_index);
          end
          if(da==tohost_addr&&word_at(da)!=0)begin
            check(st==15&&word_at(da)==1,
              $sformatf("firmware failure mailbox=%08x",word_at(da)));
            check(!mailbox_written,"duplicate mailbox");mailbox_written=1;
          end
          if(cdr&&da==32'hfff09008)translated_stores++;
          if(cdr&&da==32'hfff0a00c)translated_stores++;
        end else begin
          reads++;
          if(cdr&&da==32'hfff08004)translated_loads++;
        end
      end
      if(dut.tlb_fill_req_valid&&dut.tlb_fill_req_ready)begin
        if(misses==0)begin
          check(dut.tlb_fill_req_bank&&dut.tlb_fill_req_way&&
                dut.tlb_fill_req_ea==32'h1000a00c&&
                dut.tlb_fill_req_rpn==20'hfff0a&&
                !dut.tlb_fill_req_c,"resident C=0 way-one seed fill");
          seed_fills++;
        end else begin
          event_index=misses-1;
          check(pte_writes[event_index]==1&&low_reads[event_index]==1&&
                scan_reads[event_index]==scan_total(event_index),
                "TLB fill preceded exact PTE read and R/C write");
          check(dut.tlb_fill_req_bank==(event_index!=0)&&
                dut.tlb_fill_req_way==(event_index==3)&&
                dut.tlb_fill_req_ea==miss_ea(event_index)&&
                dut.tlb_fill_req_vsid==(event_index==0?24'h5678:24'h1234)&&
                dut.tlb_fill_req_rpn==20'(final_low(event_index)>>12)&&
                dut.tlb_fill_req_c==(event_index>=2)&&
                dut.tlb_fill_req_pp==2'b10&&
                dut.tlb_fill_req_wimg==0,
                "TLB fill payload not derived from updated selected PTE");
          handler_fills[event_index]++;
        end
      end
      if(tv&&tr)begin
        check(!retired.illegal&&!retired.alignment_exception&&
          (retired.fetch_fault==FETCH_OK||retired.fetch_fault==FETCH_PAGE_MISS)&&
          (retired.data_fault==DATA_OK||retired.data_fault==DATA_PAGE_MISS||
           retired.data_fault==DATA_PAGE_CHANGED),"retirement diagnostic");
        if(retired.fetch_fault==FETCH_PAGE_MISS||retired.data_fault!=DATA_OK)begin
          check(misses<4&&!retired.gpr_write&&!retired.update_write&&
                !retired.write_xer,"miss retired write permissions/count");
          check(retired.page_miss.ir&&retired.page_miss.dr&&
                !retired.page_miss.pr&&
                retired.page_miss.ea==miss_ea(misses)&&
                retired.page_miss.sr==(misses==0?32'h5678:32'h1234)&&
                retired.page_miss.way==(misses==3)&&
                retired.page_miss.write==(misses>=2),
                "full-EA response capsule or matched way");
          if(misses==0)
            check(retired.fetch_fault==FETCH_PAGE_MISS&&
                  retired.pc==32'h20000000,"instruction miss cause/PC");
          else if(misses==3)
            check(retired.data_fault==DATA_PAGE_CHANGED,
                  "matched-way C=0 cause");
          else check(retired.data_fault==DATA_PAGE_MISS,
                     "data true-miss cause");
          if(misses==0)check_table(-1);
          if(misses==2)store_probe_pc=retired.pc;
          if(misses==3)check(retired.pc==store_probe_pc,
                            "C=0 and absent-page store did not share probe");
          misses++;
        end else check(retired.page_miss=='0,"normal retire retained stale capsule");
        if(retired.insn[31:26]==31&&retired.insn[10:1]==978)tlbld++;
        if(retired.insn[31:26]==31&&retired.insn[10:1]==1010)tlbli++;
        if(retired.insn[31:26]==31&&retired.insn[10:1]==146)mtmsr_retires++;
        if(retired.insn==32'h4c000064&&retired.pc>=BASE+32'h2000)
          rfi_retires++; // Startup RFI that sets IP is not a miss return.
        if(mailbox_written&&!mailbox_retired)begin
          check(retired.insn[31:26]==36&&!retired.gpr_write&&
                !retired.update_write,"mailbox retirement");
          mailbox_retired=1;
        end
        retires++;
      end
      if(mailbox_retired&&!ipending&&!dpending&&!iv&&!dv&&!sv&&!rv)begin
        $display("TABLE COUNTERS misses=%0d rfi=%0d bank=%0d last=%b seed=%0d tlbli=%0d tlbld=%0d loads=%0d stores=%0d ifetch=%0d",
          misses,rfi_retires,bank_switches,last_bank,seed_fills,tlbli,tlbld,
          translated_loads,translated_stores,probe_fetches);
        check(misses==4&&rfi_retires==4&&bank_switches==8&&!last_bank&&
              seed_fills==1&&tlbli==1&&tlbld==4&&
              translated_loads>=1&&translated_stores==2&&probe_fetches>=1,
              "missing search entries, fills, retry, or target physical access");
        for(int ev=0;ev<4;ev++)
          check(scan_reads[ev]==scan_total(ev)&&low_reads[ev]==1&&
                pte_writes[ev]==1&&handler_fills[ev]==1,
                "PTEG scan/update/fill event count");
        check_table(3);
        check(word_at(32'hfff08004)==32'h13579bdf&&
              word_at(32'hfff09008)==32'h2468ace0&&
              word_at(32'hfff0a00c)==32'haabbccdd,
              "retry target memory result");
        $display("PASS compiled table search: misses=%0d fills=%0d PTE0reads=%0d/%0d/%0d/%0d PTEupdates=%0d/%0d/%0d/%0d retires=%0d cycles=%0d checks=%0d",
          misses,seed_fills+tlbli+tlbld-1,
          scan_reads[0],scan_reads[1],scan_reads[2],scan_reads[3],
          pte_writes[0],pte_writes[1],pte_writes[2],pte_writes[3],
          retires,cycles,checks);$finish;
      end
    end
  end
  assert property(@(posedge clk) disable iff(!rst_n) sv&&!sr |=> sv&&$stable(iw));
  assert property(@(posedge clk) disable iff(!rst_n) rv&&!rr |=> rv&&$stable(rd));
  assert property(@(posedge clk) disable iff(!rst_n) tv&&!tr |=> tv&&$stable(retired));
  initial begin
    if(!$value$plusargs("IMAGE=%s",image_path)||
       !$value$plusargs("TOHOST=%h",tohost_addr))
      $fatal(1,"IMAGE/TOHOST required");
    check(tohost_addr==BASE+32'h4000,"mailbox range");
    foreach(mem[i])mem[i]=0;
    $readmemh(image_path,mem,0,65535);
    repeat(4)@(negedge clk);rst_n=1;
    @(negedge clk);start_valid=1;
    do @(posedge clk);while(!start_ready);
    @(negedge clk);start_valid=0;
  end
endmodule
