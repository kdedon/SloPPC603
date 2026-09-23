// Compiled software PTEG failure conversion and permission matrix.
// Physical byte RAM uses independent delayed/backpressured instruction/data ports.
/* verilator lint_off BLKSEQ */
module tb_compiled_table_fault_firmware;
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
  int bank_switches=0;
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
                 .ENABLE_TLB_LOAD(1'b1),.ENABLE_TLB_INVALIDATE(1'b1),.ENABLE_PAGE_MISS_RESULTS(1'b1),
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
  localparam logic [31:0] HTAB=32'hfff10000, MARKER=32'hfff0b000;
  logic [31:0] fault_count_addr,fault_records_addr,active_marker=0;
  logic [31:0] event_pc[32],event_cr[32],event_gpr[32][32];
  int started=0,misses=0,vectors=0,fills=0;
  int miss_n[32],vector_n[32],scan_n[32],low_n[32],write_n[32],fill_n[32],target_n[32];

  function automatic logic [31:0] word_at(input logic [31:0] a);
    int o; o=int'(a-BASE); return {mem[o],mem[o+1],mem[o+2],mem[o+3]};
  endfunction
  function automatic logic [31:0] ordinal_marker(input int n);
    return n<5?32'(n+1):32'(n+11);
  endfunction
  function automatic bit is_i(input int m);return m==1||m==4||m==5;endfunction
  function automatic bit is_denied(input int m);
    int pp;bit key,wr;
    if(m<16)return 1;
    key=(m>=24);pp=(m-16)/2%4;wr=(m%2!=0);
    return (key&&pp==0)||(wr&&(pp==3||(key&&pp==1)));
  endfunction
  function automatic logic [31:0] ea(input int m);
    case(m)
      1:return 32'h20001004;2:return 32'h1000c003;
      3:return 32'h1000d008;4:return 32'h20002008;
      5:return 32'h2000300c;default:return 32'h1000b004;
    endcase
  endfunction
  function automatic logic [31:0] sr_expected(input int m);
    if(m==5)return 32'h40005678;
    if(is_i(m))return 32'h00005678;
    return m>=24?32'h40001234:32'h00001234;
  endfunction
  function automatic logic [31:0] primary(input int m);
    case(m)
      1:return 32'hfff19e40;2:return 32'hfff18e00;
      3:return 32'hfff18e40;4:return 32'hfff19e80;
      5:return 32'hfff19ec0;default:return 32'hfff18fc0;
    endcase
  endfunction
  function automatic logic [31:0] secondary(input int m);
    case(m)
      1:return 32'hfff16180;2:return 32'hfff171c0;
      3:return 32'hfff17180;4:return 32'hfff16140;
      5:return 32'hfff16100;default:return 32'hfff17000;
    endcase
  endfunction
  function automatic int scan_total(input int m);
    case(m)1,2,3:return 16;4:return 5;5:return 3;default:return 6;endcase
  endfunction
  function automatic logic [31:0] scan_addr(input int m,input int n);
    return n<8?primary(m)+32'(n*8):secondary(m)+32'((n-8)*8);
  endfunction
  function automatic logic [31:0] low_addr(input int m);
    case(m)4:return 32'hfff19ea4;5:return 32'hfff19ed4;
      default:return 32'hfff18fec;endcase
  endfunction
  function automatic logic [31:0] low_before(input int m);
    case(m)4:return 32'hfff0d00a;5:return 32'hfff0e000;
      default:return 32'hfff0c000|32'((m-16)/2%4);endcase
  endfunction
  function automatic logic [31:0] srr1_expected(input int m);
    case(m)1:return 32'h40000070;4:return 32'h10000070;
      5:return 32'h08000070;default:return 32'h00000070;endcase
  endfunction
  function automatic logic [31:0] dsisr_expected(input int m);
    case(m)2:return 32'h40000000;3:return 32'h42000000;
      default:return 32'h08000000|(m%2!=0?32'h02000000:0);endcase
  endfunction
  task automatic check(input bit ok,input string why);
    checks++;if(!ok)$fatal(1,"%s cycle=%0d marker=%0d pc=%08x da=%08x misses=%0d",
      why,cycles,active_marker,retired.pc,da,misses);
  endtask
  assign ir=rst_n&&!ipending&&cycles%4!=1;
  assign sv=rst_n&&ipending&&idelay==0;
  assign iw=word_at(fetch_pc);
  assign dr=rst_n&&!dpending&&cycles%5!=2;
  assign rv=rst_n&&dpending&&ddelay==0;
  assign tr=rst_n&&cycles%7>=2;

  always @(posedge clk) begin : monitor
    int m,n,record;
    logic [31:0] ra;
    if(!rst_n)begin
      ipending<=0;dpending<=0;idelay<=0;ddelay<=0;fetch_pc<=BASE;rd<=0;
      for(int j=0;j<32;j++)begin
        miss_n[j]=0;vector_n[j]=0;scan_n[j]=0;low_n[j]=0;
        write_n[j]=0;fill_n[j]=0;target_n[j]=0;
        event_pc[j]=0;event_cr[j]=0;
        for(int k=0;k<32;k++)event_gpr[j][k]=0;
      end
    end else begin
      cycles++;
      check(cycles<1500000,"fault firmware timeout");
      if(dut.core.msr[17]!=last_bank)begin
        check(dut.core.frontend_fence&&!dut.core.gpr_commit&&!dut.core.update_commit,
          "TGPR switch escaped fence");
        last_bank=dut.core.msr[17];bank_switches++;
      end
      check(!halted&&!cut_accepted&&!physical_error&&
            !interrupt_taken&&!decrementer_taken,"unexpected hardware fault");
      check(!unused_page_ports[1]&&!bat_valid&&!bat_rsp&&!bat_rejected&&
            !bat_unsupported&&!bat_config&&!bat_overlap&&bat_invalid==0,
            "external management unexpectedly active");
      if(running)check(!bat_ready&&!cpr,"unexpected privileged context");
      if(idelay>0)idelay<=idelay-1;
      if(ddelay>0)ddelay<=ddelay-1;
      if(sv&&sr)ipending<=0;
      if(rv&&rr)dpending<=0;
      if(iv&&ir)begin
        check(ia>=BASE&&ia<=BASE+32'h2fffc&&ia[1:0]==0,
          "denied instruction page issued physical fetch");
        check(iwimg==(cir?4'b0000:4'b0001),"instruction WIMG");
        if(active_marker==1)
          check(ia<32'hfff06000,
            "absent instruction page reached a translated physical target");
        if(active_marker==4)
          check(ia<32'hfff0d000||ia>=32'hfff0e000,
            "guarded instruction page reached physical fetch");
        if(active_marker==5)
          check(ia<32'hfff0e000||ia>=32'hfff0f000,
            "protected instruction page reached physical fetch");
        if(ia==32'hfff00300||ia==32'hfff00400)begin
          m=int'(active_marker);
          check(m>0&&m<32&&is_denied(m)&&miss_n[m]==1&&vector_n[m]==0,
            "ordinary vector provenance/count");
          check(ia==(is_i(m)?32'hfff00400:32'hfff00300),
            "ordinary exception vector");
          check(dut.core.msr==32'h40&&dut.core.srr0==event_pc[m]&&
                dut.core.srr1==srr1_expected(m),
            "ordinary vector MSR/SRR0/SRR1");
          if(!is_i(m))
            check(dut.core.special.dar_q==ea(m)&&
                  dut.core.special.dsisr_q==dsisr_expected(m),
              "DSI DAR/DSISR full byte EA and cause");
          check(dut.core.cr==event_cr[m],"normal CR changed before ordinary vector");
          for(int k=0;k<32;k++)
            check(dut.core.regfile.gpr[k]==event_gpr[m][k],
              $sformatf("normal GPR%0d changed before ordinary vector",k));
          check(write_n[m]==0&&fill_n[m]==0&&target_n[m]==0,
            "failed search touched PTE, TLB, or physical target");
          if(m>=4)check(word_at(low_addr(m))==low_before(m),
            "failed search changed matched PTE R/C bits");
          vector_n[m]++;vectors++;
        end
        ipending<=1;fetch_pc<=ia;idelay<=1+cycles%4;
      end
      if(dv&&dr)begin
        check(da>=BASE&&da<=BASE+32'h2fffc&&da[1:0]==0,
          "physical data RAM range");
        check(dwimg==(cdr?4'b0000:4'b0011),"data WIMG");
        dpending<=1;ddelay<=1+cycles%5;rd<=word_at(da);
        m=int'(active_marker);
        if(m==2||m==3)
          check(dut.core.special.ea_q!=ea(m),
            "absent data page reached a physical target");
        if(dut.core.msr[17]&&da>=HTAB&&da<HTAB+32'h10000)begin
          check(m>0&&m<32&&miss_n[m]==1,"PTE access without chosen miss");
          if(dw)begin
            check(m>=16&&!is_denied(m)&&da==low_addr(m)&&
                  st==(m%2!=0?4'b0011:4'b0010)&&
                  scan_n[m]==6&&low_n[m]==1&&write_n[m]==0,
              "PTE R/C write before exact match or on failure");
            write_n[m]++;
          end else if(m>=4&&da==low_addr(m))begin
            check(scan_n[m]==scan_total(m)&&low_n[m]==0,
              "PTE1 read before selected PTE0");
            low_n[m]++;
          end else begin
            n=scan_n[m];
            check(n<scan_total(m)&&da==scan_addr(m,n),
              "PTE0 scan omitted or reordered group slot");
            scan_n[m]++;
          end
        end
        if(da==32'hfff0c004&&dut.core.special.ea_q==32'h1000b004)begin
          check(m>=16&&!is_denied(m),
            "denied matrix access reached physical target");
          target_n[m]++;
        end
        if(dw)begin
          writes++;
          for(int lane=0;lane<4;lane++)
            if(st[3-lane])mem[int'(da-BASE)+lane]=wd[31-lane*8 -:8];
          if(da==MARKER)begin
            check(st==4'hf&&word_at(da)==ordinal_marker(started),
              "case marker order/strobe");
            active_marker=word_at(da);started++;
          end
          if(dut.core.msr[17]&&da>=HTAB&&da<HTAB+32'h10000)
            check(word_at(da)==(low_before(m)|(m%2!=0?32'h180:32'h100)),
              "PTE R/C update changed wrong lanes");
          if(da==tohost_addr&&word_at(da)!=0)begin
            check(st==4'hf&&word_at(da)==1,
              $sformatf("firmware failure mailbox=%08x",word_at(da)));
            check(!mailbox_written,"duplicate mailbox");mailbox_written=1;
          end
        end else reads++;
      end
      if(dut.tlb_fill_req_valid&&dut.tlb_fill_req_ready)begin
        m=int'(active_marker);
        check(m>=16&&!is_denied(m)&&miss_n[m]==1&&
              scan_n[m]==6&&low_n[m]==1&&write_n[m]==1&&fill_n[m]==0,
              "TLB fill preceded exact PTE read and R/C write");
        check(dut.tlb_fill_req_bank&&
              dut.tlb_fill_req_ea==32'h1000b004&&
              dut.tlb_fill_req_vsid==24'h1234&&
              dut.tlb_fill_req_rpn==20'hfff0c&&
              dut.tlb_fill_req_c==(m%2!=0)&&
              dut.tlb_fill_req_pp==2'((m-16)/2%4)&&
              dut.tlb_fill_req_wimg==0,
              "TLB fill differs from selected updated PTE");
        fill_n[m]++;fills++;
      end
      if(tv&&tr)begin
        check(!retired.illegal&&!retired.alignment_exception&&
              (retired.fetch_fault==FETCH_OK||retired.fetch_fault==FETCH_PAGE_MISS)&&
              (retired.data_fault==DATA_OK||retired.data_fault==DATA_PAGE_MISS),
          "retirement diagnostic");
        if(retired.fetch_fault==FETCH_PAGE_MISS||
           retired.data_fault==DATA_PAGE_MISS)begin
          m=int'(active_marker);
          check(m>0&&m<32&&miss_n[m]==0&&
                !retired.gpr_write&&!retired.update_write&&
                !retired.write_xer&&!retired.write_cr0,
             $sformatf("typed miss retirement count/effects kindI=%0d kindD=%0d ea=%08x msr=%08x lr=%08x",
              retired.fetch_fault,retired.data_fault,retired.page_miss.ea,dut.core.msr,dut.core.lr));
          check(retired.page_miss.ir&&retired.page_miss.dr&&
                !retired.page_miss.pr&&
                retired.page_miss.ea==(is_i(m)?ea(m):(ea(m)&32'hfffffffc))&&
                retired.page_miss.sr==sr_expected(m)&&
                !retired.page_miss.way&&
                retired.page_miss.write==(m==3||(m>=16&&m%2!=0)),
            "typed miss capsule EA/SR/way/write");
          check(is_i(m)?
                (retired.fetch_fault==FETCH_PAGE_MISS&&retired.pc==ea(m)):
                (retired.data_fault==DATA_PAGE_MISS),
            "typed miss kind/PC");
          event_pc[m]=retired.pc;event_cr[m]=dut.core.cr;
          for(int k=0;k<32;k++)event_gpr[m][k]=dut.core.regfile.gpr[k];
          miss_n[m]++;misses++;
        end else check(retired.page_miss=='0,"normal retirement retained capsule");
        if(mailbox_written&&!mailbox_retired)begin
          check(retired.insn[31:26]==36&&!retired.gpr_write&&!retired.update_write,
            "mailbox retirement");
          mailbox_retired=1;
        end
        retires++;
      end
      if(mailbox_retired&&!ipending&&!dpending&&!iv&&!dv&&!sv&&!rv)begin
        check(started==21&&misses==21&&vectors==10&&fills==11,
          "case/miss/vector/fill totals");
        check(word_at(fault_count_addr)==32'd10,"ordinary fault record count");
        record=0;
        for(int j=0;j<21;j++)begin
          m=int'(ordinal_marker(j));
          check(miss_n[m]==1&&scan_n[m]==scan_total(m)&&
                low_n[m]==(m>=4?1:0),
            "per-case miss/primary-secondary scan/PTE1 count");
          check(write_n[m]==(is_denied(m)?0:1)&&
                fill_n[m]==(is_denied(m)?0:1)&&
                vector_n[m]==(is_denied(m)?1:0)&&
                target_n[m]==(is_denied(m)?0:1),
            "per-case fail/allow effects");
          if(is_denied(m))begin
            ra=fault_records_addr+32'(record*24);
            check(word_at(ra)==32'(m)&&word_at(ra+4)==event_pc[m]&&
                  word_at(ra+8)==srr1_expected(m)&&
                  word_at(ra+20)==32'h40,
              "ordinary record marker/PC/SRR1/MSR");
            if(!is_i(m))
              check(word_at(ra+12)==ea(m)&&
                    word_at(ra+16)==dsisr_expected(m),
                "ordinary DSI record DAR/DSISR");
            record++;
          end
        end
        check(record==10&&!last_bank,"ordinary record total or TGPR bank");
        check(word_at(32'hfff19ea4)==32'hfff0d00a&&
              word_at(32'hfff19ed4)==32'hfff0e000,
          "guarded/protected instruction PTE changed");
        $display("PASS compiled table fault: cases=%0d misses=%0d vectors=%0d fills=%0d retires=%0d cycles=%0d checks=%0d",
          started,misses,vectors,fills,retires,cycles,checks);
        $finish;
      end
    end
  end
  assert property(@(posedge clk) disable iff(!rst_n) sv&&!sr |=> sv&&$stable(iw));
  assert property(@(posedge clk) disable iff(!rst_n) rv&&!rr |=> rv&&$stable(rd));
  assert property(@(posedge clk) disable iff(!rst_n) tv&&!tr |=> tv&&$stable(retired));
  initial begin
    if(!$value$plusargs("IMAGE=%s",image_path)||
       !$value$plusargs("TOHOST=%h",tohost_addr)||
       !$value$plusargs("FAULT_COUNT=%h",fault_count_addr)||
       !$value$plusargs("FAULT_RECORDS=%h",fault_records_addr))
      $fatal(1,"IMAGE/TOHOST/FAULT_COUNT/FAULT_RECORDS required");
    check(tohost_addr==BASE+32'h4000&&
          fault_count_addr>=BASE&&fault_count_addr<BASE+32'h10000&&
          fault_records_addr>=BASE&&fault_records_addr<BASE+32'h10000,
      "linked mailbox/fault record range");
    foreach(mem[i])mem[i]=0;
    $readmemh(image_path,mem,0,65535);
    repeat(4)@(negedge clk);rst_n=1;
    @(negedge clk);start_valid=1;
    do @(posedge clk);while(!start_ready);
    @(negedge clk);start_valid=0;
  end
endmodule
