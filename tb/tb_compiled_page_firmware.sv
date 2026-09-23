// Compiled I/D page-hit firmware with CPU-owned segment switching and live events.
// Physical byte RAM uses independent delayed/backpressured instruction/data ports.
/* verilator lint_off BLKSEQ */
module tb_compiled_page_firmware;
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
  logic start_valid=0,start_ready,running,cir,cdr,cpr,fault,physical_error;
  logic unused_busy,unused_fi,unused_fw,unused_fm,unused_fp,unused_fg,unused_fc,unused_finv;
  logic [31:0] unused_fea;
  logic [3:0] unused_fentries;
  /* verilator lint_off UNUSEDSIGNAL */
  retire_packet_t retired;
  /* verilator lint_on UNUSEDSIGNAL */
  logic [7:0] mem[0:196607];
  logic ipending=0,dpending=0,mailbox_written=0,mailbox_retired=0;
  logic [31:0] fetch_pc;
  logic [1:0] last_context=0;
  int idelay=0,ddelay=0,cycles=0,retires=0,checks=0,reads=0,writes=0;
  int transitions=0,interrupts=0,decrements=0,phase=0;
  logic external_irq,interrupt_taken,decrementer_taken;
  int bat_writes=0,segment_reads=0,segment_writes=0;

  logic [31:0] decrementer_pc;
  logic [31:0] interrupt_pc;
  assign external_irq=running&&phase>=1&&interrupts==0;
  logic tlb_mgmt_req_valid_i=0;
  logic tlb_mgmt_req_ready_o;
  logic [1:0] tlb_mgmt_req_kind_i=0;
  logic tlb_mgmt_req_bank_i=0;
  logic [31:0] tlb_mgmt_req_ea_i=0;
  logic [23:0] tlb_mgmt_req_vsid_i=0;
  logic tlb_mgmt_req_pr_i=0;
  logic tlb_mgmt_req_way_i=0;
  logic [19:0] tlb_mgmt_req_rpn_i=0;
  logic tlb_mgmt_req_c_i=0;
  logic [3:0] tlb_mgmt_req_wimg_i=0;
  logic [1:0] tlb_mgmt_req_pp_i=0;
  logic tlb_mgmt_rsp_valid_o;
  logic tlb_mgmt_rsp_ready_i=0;
  logic [1:0] tlb_mgmt_rsp_kind_o;
  logic tlb_mgmt_rsp_bank_o;
  logic [31:0] tlb_mgmt_rsp_ea_o;
  logic tlb_mgmt_rsp_privileged_o;
  logic tlb_mgmt_rsp_refill_rejected_o;
  logic tlb_mgmt_rsp_unsupported_o;
  logic tlb_mgmt_rsp_invalid_input_o;
  logic tlb_mgmt_idle_o;
  logic page_fault_o;
  logic page_miss_o;
  logic page_protection_o;
  logic page_no_execute_o;
  logic page_guarded_o;
  logic page_direct_store_o;
  logic page_needs_changed_o;
  logic page_config_o;
  int page_retires=0,page_fetches=0,alias_stores=0,preloads=0;
  string image_path;
  logic [49:0] unused_page_ports;
  ppc_core_bat #(.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),.ENABLE_LIVE_CONTEXT(1'b1),
                 .ENABLE_EXTERNAL_INTERRUPTS(1'b1),.ENABLE_TIMERS(1'b1),.ENABLE_RUNTIME_BAT(1'b1),.ENABLE_SEGMENT_REGISTERS(1'b1),.ENABLE_PAGE_TRANSLATION(1'b1)) dut(
    .clk_i(clk),.rst_ni(rst_n),
    .tlb_mgmt_req_valid_i,
    .tlb_mgmt_req_ready_o,
    .tlb_mgmt_req_kind_i,
    .tlb_mgmt_req_bank_i,
    .tlb_mgmt_req_ea_i,
    .tlb_mgmt_req_vsid_i,
    .tlb_mgmt_req_pr_i,
    .tlb_mgmt_req_way_i,
    .tlb_mgmt_req_rpn_i,
    .tlb_mgmt_req_c_i,
    .tlb_mgmt_req_wimg_i,
    .tlb_mgmt_req_pp_i,
    .tlb_mgmt_rsp_valid_o,
    .tlb_mgmt_rsp_ready_i,
    .tlb_mgmt_rsp_kind_o,
    .tlb_mgmt_rsp_bank_o,
    .tlb_mgmt_rsp_ea_o,
    .tlb_mgmt_rsp_privileged_o,
    .tlb_mgmt_rsp_refill_rejected_o,
    .tlb_mgmt_rsp_unsupported_o,
    .tlb_mgmt_rsp_invalid_input_o,
    .tlb_mgmt_idle_o,
    .page_fault_o,
    .page_miss_o,
    .page_protection_o,
    .page_no_execute_o,
    .page_guarded_o,
    .page_direct_store_o,
    .page_needs_changed_o,
    .page_config_o,

    .external_irq_i(external_irq),.interrupt_taken_o(interrupt_taken),.interrupt_pc_o(interrupt_pc),
    .timer_tick_i(1'b0),.timebase_enable_i(1'b0),
    .decrementer_taken_o(decrementer_taken),.decrementer_pc_o(decrementer_pc),
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
    .translation_fault_o(fault),.fault_instruction_o(unused_fi),.fault_write_o(unused_fw),
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
    logic [9:0] selector;
    if(!rst_n)begin
      ipending<=0;dpending<=0;idelay<=0;ddelay<=0;fetch_pc<=BASE;rd<=0;
    end else begin
      cycles++;check(cycles<150000,"firmware timeout");
      check(!halted&&!cut_accepted&&!fault&&!physical_error&&!page_fault_o&&!page_miss_o&&
            !page_protection_o&&!page_no_execute_o&&!page_guarded_o&&!page_direct_store_o&&
            !page_needs_changed_o&&!page_config_o,"unexpected halt/translation/physical fault");
      check(!bat_valid&&!bat_rsp&&!bat_rejected&&!bat_unsupported&&!bat_config&&!bat_overlap&&bat_invalid==0,
            "harness must not program BATs");
      if(running)begin
        check(!bat_ready&&!cpr&&cir==cdr,"unexpected startup/live context");
        if({cir,cdr}!=last_context)begin
          check({cir,cdr}==((transitions%2==0)?2'b11:2'b00),"context transition order");
          transitions++;check(transitions<=6,"extra context transition");last_context={cir,cdr};
        end
      end
      if(idelay>0)idelay<=idelay-1;
      if(ddelay>0)ddelay<=ddelay-1;
      if(sv&&sr)ipending<=0;
      if(rv&&rr)dpending<=0;
      if(iv&&ir)begin
        check(ia>=BASE&&ia<=BASE+32'hfffc&&ia[1:0]==0,"instruction physical RAM range");
        check(iwimg==(cir?4'b0000:4'b0001),"instruction attributes");
        ipending<=1;fetch_pc<=ia;idelay<=1+cycles%4;
        if(ia>=BASE+32'h6000&&ia<BASE+32'h7000)begin
          check(cir,"instruction page probe in real mode");page_fetches++;idelay<=13;
        end
      end
      if(dv&&dr)begin
        check(da>=BASE&&da<=BASE+32'h2fffc&&da[1:0]==0,"data physical RAM range");
        check(dwimg==(cdr?4'b0000:4'b0011),"data attributes");
        dpending<=1;ddelay<=1+cycles%5;rd<=word_at(da);
        if(dw)begin
          writes++;
          if(da==BASE+32'h8000||da==BASE+32'h9000)begin
            check(cdr&&st==15&&alias_stores<2,"page store context/count");
            check(alias_stores==0 ? (da==BASE+32'h8000&&wd==32'h13579bdf) :
                  (da==BASE+32'h9000&&wd==32'h2468ace0),"VSID-specific physical store");
            alias_stores++;ddelay<=18;
          end
          for(int lane=0;lane<4;lane++)if(st[3-lane])mem[int'(da-BASE)+lane]=wd[31-lane*8 -:8];
          if(da==BASE+32'ha004)begin
            check(st==15&&wd==1&&phase==0,"fixture phase order");phase=1;
          end
          if(da==tohost_addr&&word_at(da)!=0)begin
            check(st==15&&word_at(da)==1,$sformatf("firmware failure mailbox=%08x",word_at(da)));
            check(!mailbox_written,"duplicate mailbox");mailbox_written=1;
          end
        end else reads++;
      end
      if(interrupt_taken)begin
        check(external_irq&&interrupts==0&&decrements==0&&bat_writes==4&&segment_writes==5,"IRQ ordering or lost pending level");
        check(interrupt_pc[1:0]==0&&interrupt_pc>=BASE&&interrupt_pc<BASE+32'h10000,"IRQ resume PC");
        check(!(tv&&tr),"IRQ fabricated retirement");interrupts++;
      end
      if(decrementer_taken)begin
        check(interrupts==1&&decrements==0&&!interrupt_taken&&bat_writes==4&&segment_writes==5,"DEC ordering");
        check(decrementer_pc[1:0]==0&&decrementer_pc>=BASE&&decrementer_pc<BASE+32'h10000,"DEC resume PC");
        check(!(tv&&tr),"DEC fabricated retirement");decrements++;
      end
      if(tv&&tr)begin
        check(!retired.illegal&&!retired.alignment_exception&&retired.fetch_fault==FETCH_OK&&retired.data_fault==DATA_OK,"retirement diagnostic");
        selector={retired.insn[15:11],retired.insn[20:16]};
        if(retired.insn[31:26]==31&&selector>=528&&selector<=543)begin
          if(retired.insn[10:1]==467)bat_writes++;

        end
        if(retired.insn[31:26]==31)begin
          if(retired.insn[10:1]==595||retired.insn[10:1]==659)segment_reads++;
          if(retired.insn[10:1]==210||retired.insn[10:1]==242)segment_writes++;
        end
        if(mailbox_written&&!mailbox_retired)begin
          check(retired.insn[31:26]==36&&!retired.gpr_write&&!retired.update_write,"mailbox retirement");mailbox_retired=1;
        end
        if(retired.pc==32'h20000000||retired.pc==32'h20000004)begin
          check(cir&&page_retires<4,"unexpected instruction-page retirement");
          check(retired.pc[2] ? retired.insn==32'h4e800020 : retired.insn==32'h38630011,
                "wrong instruction-page contents");
          page_retires++;
        end
        retires++;
      end
      if(mailbox_retired&&!ipending&&!dpending&&!iv&&!dv&&!sv&&!rv)begin
        check(transitions==6&&last_context==0&&phase==1,"missing context phases");
        check(interrupts==1&&decrements==1,"missing events");
        check(bat_writes==4&&segment_writes==6&&segment_reads==0,"missing CPU register accesses");
        check(preloads==3&&alias_stores==2&&page_retires==4&&page_fetches>=4,"missing page effects");
        check(word_at(BASE+32'h8000)==32'h13579bdf&&word_at(BASE+32'h9000)==32'h2468ace0,"page physical data corrupted");
        $display("PASS compiled page firmware: Ipage_retires=%0d Ipage_fetches=%0d SRwrites=%0d SRreads=%0d BATwrites=%0d EXT=%0d DEC=%0d retires=%0d reads=%0d writes=%0d cycles=%0d",page_retires,page_fetches,segment_writes,segment_reads,bat_writes,interrupts,decrements,retires,reads,writes,cycles);$finish;
      end
    end
  end
  assert property(@(posedge clk) disable iff(!rst_n) sv&&!sr |=> sv&&$stable(iw));
  assert property(@(posedge clk) disable iff(!rst_n) rv&&!rr |=> rv&&$stable(rd));
  assert property(@(posedge clk) disable iff(!rst_n) tv&&!tr |=> tv&&$stable(retired));
  task automatic preload(input logic bank,input logic [31:0] ea,input logic [23:0] vsid,
                         input logic way,input logic [19:0] rpn);
    @(negedge clk);tlb_mgmt_req_valid_i=1;tlb_mgmt_req_kind_i=1;
    tlb_mgmt_req_bank_i=bank;tlb_mgmt_req_ea_i=ea;tlb_mgmt_req_vsid_i=vsid;
    tlb_mgmt_req_way_i=way;tlb_mgmt_req_rpn_i=rpn;tlb_mgmt_req_c_i=1;tlb_mgmt_req_pp_i=2;
    do @(posedge clk);while(!tlb_mgmt_req_ready_o);
    @(negedge clk);tlb_mgmt_req_valid_i=0;
    wait(tlb_mgmt_rsp_valid_o);repeat(3)@(negedge clk);
    check(!running&&tlb_mgmt_rsp_kind_o==1&&tlb_mgmt_rsp_bank_o==bank&&
      tlb_mgmt_rsp_ea_o==ea&&!tlb_mgmt_rsp_privileged_o&&!tlb_mgmt_rsp_refill_rejected_o&&
      !tlb_mgmt_rsp_unsupported_o&&!tlb_mgmt_rsp_invalid_input_o,"TLB preload failed");
    tlb_mgmt_rsp_ready_i=1;@(posedge clk);@(negedge clk);tlb_mgmt_rsp_ready_i=0;
    wait(tlb_mgmt_idle_o);preloads++;
  endtask
  initial begin
    if(!$value$plusargs("IMAGE=%s",image_path)||!$value$plusargs("TOHOST=%h",tohost_addr))$fatal(1,"IMAGE/TOHOST required");
    check(tohost_addr==BASE+32'h4000,"mailbox range");
    foreach(mem[i])mem[i]=0;
    $readmemh(image_path,mem,0,65535);repeat(4)@(negedge clk);rst_n=1;
    // Fixture-owned normalized TLB preload; CPU owns every BAT and SR write.
    preload(1,32'h10008000,24'h001234,0,20'hfff08);
    preload(1,32'h10008000,24'h002345,1,20'hfff09);
    preload(0,32'h20000000,24'h005678,0,20'hfff06);
    @(negedge clk);start_valid=1;
    do @(posedge clk);while(!start_ready);
    @(negedge clk);start_valid=0;
  end
endmodule
