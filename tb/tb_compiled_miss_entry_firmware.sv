// Compiled instruction/data miss and matched-way changed-bit refill/retry.
// Physical byte RAM uses independent delayed/backpressured instruction/data ports.
/* verilator lint_off BLKSEQ */
module tb_compiled_miss_entry_firmware;
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
  int imisses=0,loadmisses=0,storemisses=0,changed=0,tlbli=0,tlbld=0;
  logic last_bank=0;
  int mode=0;
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
  function automatic logic [31:0] word_at(input logic [31:0] address);
    int o; o=int'(address-BASE); return {mem[o],mem[o+1],mem[o+2],mem[o+3]};
  endfunction
  task automatic check(input logic ok,input string message);
    checks++;if(!ok)$fatal(1,"%s cycle=%0d pc=%08x insn=%08x",message,cycles,retired.pc,retired.insn);
  endtask
  assign ir=rst_n&&!ipending&&cycles%4!=1;
  assign sv=rst_n&&ipending&&idelay==0;
  assign iw=word_at(fetch_pc);
  assign dr=rst_n&&!dpending&&cycles%5!=2;
  assign rv=rst_n&&dpending&&ddelay==0;
  assign tr=rst_n&&cycles%7>=2;
  always @(posedge clk)begin : monitor
    if(!rst_n)begin
      ipending<=0;dpending<=0;idelay<=0;ddelay<=0;fetch_pc<=BASE;rd<=0;
    end else begin
      cycles++;check(cycles<20000,"miss-entry firmware timeout");
      if(dut.core.msr[17]!=last_bank)begin
        check(dut.core.frontend_fence&&!dut.core.gpr_commit&&
              !dut.core.update_commit,"bank switch escaped serialization");
        last_bank=dut.core.msr[17];bank_switches++;
      end
      check(!halted&&!cut_accepted&&!physical_error&&
            !interrupt_taken&&!decrementer_taken,"unexpected fault/event");
      check(!unused_page_ports[1],"fixture TLB management active");
      check(!bat_valid&&!bat_rsp&&!bat_rejected&&!bat_unsupported&&!bat_config&&
            !bat_overlap&&bat_invalid==0,"fixture BAT management active");
      if(running)check(!bat_ready&&!cpr,"unexpected privilege context");
      if(idelay>0)idelay<=idelay-1;
      if(ddelay>0)ddelay<=ddelay-1;
      if(sv&&sr)ipending<=0;
      if(rv&&rr)dpending<=0;
      if(iv&&ir)begin
        check(ia>=BASE&&ia<=BASE+32'hfffc&&ia[1:0]==0,"instruction RAM range");
        check(iwimg==(cir?4'b0000:4'b0001),"instruction attributes");
        ipending<=1;fetch_pc<=ia;idelay<=1+cycles%4;
      end
      if(dv&&dr)begin
        check(da>=BASE&&da<=BASE+32'hfffc&&da[1:0]==0,"data RAM range");
        check(dwimg==(cdr?4'b0000:4'b0011),"data attributes");
        dpending<=1;ddelay<=1+cycles%5;rd<=word_at(da);
        if(dw)begin
          writes++;
          for(int lane=0;lane<4;lane++)if(st[3-lane])mem[int'(da-BASE)+lane]=wd[31-lane*8 -:8];
          if(da==tohost_addr&&word_at(da)!=0)begin
            check(st==15&&word_at(da)==1,$sformatf("firmware failure mailbox=%08x",word_at(da)));
            check(!mailbox_written,"duplicate mailbox");mailbox_written=1;
          end
        end else reads++;
      end
      if(tv&&tr)begin
        check(!retired.illegal&&!retired.alignment_exception&&
          (retired.fetch_fault==FETCH_OK||retired.fetch_fault==FETCH_PAGE_MISS)&&
          (retired.data_fault==DATA_OK||retired.data_fault==DATA_PAGE_MISS||retired.data_fault==DATA_PAGE_CHANGED),"retirement diagnostic");
        if(retired.fetch_fault==FETCH_PAGE_MISS||retired.data_fault!=DATA_OK)begin
          check(!retired.gpr_write&&!retired.update_write&&!retired.write_xer,
                "miss retired write permissions");
          check(retired.page_miss.ir&&retired.page_miss.dr&&!retired.page_miss.pr,
                "miss lost context");
          if(retired.fetch_fault==FETCH_PAGE_MISS)begin
            check(imisses==0&&retired.pc==32'h20000000&&
                  retired.page_miss.ea==32'h20000000&&retired.page_miss.sr==32'h5678&&
                  !retired.page_miss.write&&!retired.page_miss.way,"instruction miss capsule");imisses++;
          end else begin
            check(retired.page_miss.sr==32'h1234,"data miss SR");
            if(!retired.page_miss.write)begin
              check(loadmisses==0&&retired.data_fault==DATA_PAGE_MISS&&
                    retired.page_miss.ea==32'h10008000&&!retired.page_miss.way,"load miss capsule");loadmisses++;
            end else if(retired.data_fault==DATA_PAGE_CHANGED)begin
              check(changed==0&&retired.page_miss.ea==32'h1000a000&&retired.page_miss.way==1'(mode),"changed capsule");changed++;
            end else begin
              check(storemisses==0&&retired.page_miss.ea==32'h10009000&&!retired.page_miss.way,"store miss capsule");storemisses++;
            end
          end
        end else check(retired.page_miss=='0,"normal retire retained stale capsule");
        if(retired.insn[31:26]==31&&retired.insn[10:1]==978)tlbld++;
        if(retired.insn[31:26]==31&&retired.insn[10:1]==1010)tlbli++;
        if(retired.insn[31:26]==31&&retired.insn[10:1]==146)mtmsr_retires++;
        if(retired.insn==32'h4c000064)rfi_retires++;
        if(mailbox_written&&!mailbox_retired)begin
          check(retired.insn[31:26]==36&&!retired.gpr_write&&!retired.update_write,
                "mailbox retirement");mailbox_retired=1;
        end
        retires++;
      end
      if(mailbox_retired&&!ipending&&!dpending&&!iv&&!dv&&!sv&&!rv)begin
        check(mtmsr_retires==1&&rfi_retires==5&&bank_switches==8&&!last_bank&&
              imisses==1&&loadmisses==1&&storemisses==1&&changed==1&&tlbld==4&&tlbli==1,
              "missing precise miss entries, fills or bank transitions");
        check(word_at(32'hfff08000)==32'h13579bdf&&
              word_at(32'hfff09000)==32'h2468ace0&&word_at(32'hfff0a000)==32'haabbccdd,
              "retry physical memory result");
        $display("PASS compiled miss-entry firmware: way=%0d I=%0d load=%0d store=%0d changed=%0d fills=%0d retires=%0d cycles=%0d",
                 mode,imisses,loadmisses,storemisses,changed,tlbld+tlbli,retires,cycles);$finish;
      end
    end
  end
  assert property(@(posedge clk) disable iff(!rst_n) sv&&!sr |=> sv&&$stable(iw));
  assert property(@(posedge clk) disable iff(!rst_n) rv&&!rr |=> rv&&$stable(rd));
  assert property(@(posedge clk) disable iff(!rst_n) tv&&!tr |=> tv&&$stable(retired));
  initial begin
    if(!$value$plusargs("IMAGE=%s",image_path)||!$value$plusargs("TOHOST=%h",tohost_addr))
      $fatal(1,"IMAGE/TOHOST required");
    check(tohost_addr==BASE+32'h4000,"mailbox range");
    if(!$value$plusargs("MODE=%d",mode))mode=0;
    check(mode>=0&&mode<=1,"changed-way mode");
    foreach(mem[i])mem[i]=0;
    $readmemh(image_path,mem,0,65535);mem['hb003]=8'(mode);repeat(4)@(negedge clk);rst_n=1;
    @(negedge clk);start_valid=1;
    do @(posedge clk);while(!start_ready);
    @(negedge clk);start_valid=0;
  end
endmodule
