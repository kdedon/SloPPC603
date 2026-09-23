// Compiled timer firmware through real BAT translation and committed MSR context.
// Physical byte RAM uses independent delayed/backpressured instruction/data ports.
/* verilator lint_off BLKSEQ */
module tb_compiled_timer_firmware;
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
  logic [7:0] mem[0:65535];
  logic ipending=0,dpending=0,mailbox_written=0,mailbox_retired=0;
  logic [31:0] fetch_pc;
  logic [1:0] last_context=0;
  int idelay=0,ddelay=0,cycles=0,retires=0,checks=0,reads=0,writes=0;
  int transitions=0,alias_stores=0,interrupts=0,decrements=0,phase=0;
  logic external_irq,interrupt_taken,decrementer_taken,alias_retired=0;
  logic tb_enabled=0,timer_tick=0;
  logic [31:0] decrementer_pc;
  logic [31:0] interrupt_pc;
  assign external_irq=running&&phase>=2&&interrupts==0;
  // Tick is stable before the sampling edge; fixture phases may pause it.
  always @(negedge clk)
    timer_tick=running&&cycles%4==0&&((phase<2)||alias_stores==1);
  string image_path;
  logic [49:0] unused_page_ports;
  ppc_core_bat #(.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),.ENABLE_LIVE_CONTEXT(1'b1),
                 .ENABLE_EXTERNAL_INTERRUPTS(1'b1),.ENABLE_TIMERS(1'b1)) dut(
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
    .external_irq_i(external_irq),.interrupt_taken_o(interrupt_taken),.interrupt_pc_o(interrupt_pc),
    .timer_tick_i(timer_tick),.timebase_enable_i(tb_enabled),
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
  task automatic write_bat(input logic[9:0] spr,input logic[31:0] value);
    @(negedge clk);bat_spr=spr;bat_data=value;bat_valid=1;
    do @(posedge clk); while(!bat_ready);
    @(negedge clk);bat_valid=0;
    while(!bat_rsp)@(negedge clk);
    check(!(bat_rejected||bat_unsupported||bat_config||bat_overlap||(|bat_invalid)),"BAT setup rejected");
    @(negedge clk);
  endtask
  assign ir=rst_n&&!ipending&&cycles%4!=1;
  assign sv=rst_n&&ipending&&idelay==0;
  assign iw=word_at(fetch_pc);
  assign dr=rst_n&&!dpending&&cycles%5!=2;
  assign rv=rst_n&&dpending&&ddelay==0;
  assign tr=rst_n&&cycles%7>=2;
  always @(posedge clk)begin
    if(!rst_n)begin
      ipending<=0;dpending<=0;idelay<=0;ddelay<=0;fetch_pc<=BASE;rd<=0;
    end else begin
      cycles++;check(cycles<100000,"firmware timeout");
      check(!halted&&!cut_accepted&&!fault&&!physical_error,"unexpected halt/translation/physical fault");
      if(running)begin
        check(!cpr&&cir==cdr,"unexpected live context");
        if({cir,cdr}!=last_context)begin
          check({cir,cdr}==((transitions%2==0)?2'b11:2'b00),"context transition order");
          transitions++;check(transitions<=8,"extra context transition");last_context={cir,cdr};
        end
      end
      if(idelay>0)idelay<=idelay-1;
      if(ddelay>0)ddelay<=ddelay-1;
      if(sv&&sr)ipending<=0;
      if(rv&&rr)dpending<=0;
      if(iv&&ir)begin
        check(ia>=BASE&&ia<=BASE+32'hfffc&&ia[1:0]==0,"instruction physical RAM range");
        check(iwimg==(cir?4'b0000:4'b0001),"unexpected instruction WIMG");
        ipending<=1;fetch_pc<=ia;idelay<=1+cycles%4;
      end
      if(dv&&dr)begin
        check(da>=BASE&&da<=BASE+32'hfffc&&da[1:0]==0,"data physical RAM range");
        check(dwimg==(cdr?4'b0000:4'b0011),"unexpected data WIMG");dpending<=1;ddelay<=1+cycles%5;rd<=word_at(da);
        if(dw)begin
          writes++;
          for(int lane=0;lane<4;lane++)if(st[3-lane])mem[int'(da-BASE)+lane]=wd[31-lane*8 -:8];
          if(da==BASE+32'h3000&&wd==32'h13579bdf)begin
            check(cdr&&st==4'hf,"alias store outside translated context");
            check(interrupts==1&&decrements==1&&phase==3&&alias_stores==0,"alias store event ordering/duplicate");
            alias_stores++;ddelay<=24;
          end
          if(da==BASE+32'h3004)begin
            check(st==4'hf&&wd==32'(phase+1)&&phase<3,"fixture phase order");
            phase=int'(wd);
          end
          if(da==tohost_addr&&word_at(da)!=0)begin
            check(st==4'hf&&word_at(da)==1,"firmware failure mailbox");
            check(!mailbox_written,"duplicate mailbox");mailbox_written=1;
          end
        end else reads++;
      end
      if(interrupt_taken)begin
        check(external_irq&&interrupts==0&&decrements==0,"unexpected interrupt trace");
        check(interrupt_pc[1:0]==0&&interrupt_pc>=BASE&&interrupt_pc<BASE+32'h10000,
              "invalid interrupt resume PC");
        check(!(tv&&tr),"interrupt fabricated an instruction retirement");
        interrupts++;
      end
      if(decrementer_taken)begin
        check(interrupts==1&&decrements<2&&!interrupt_taken,"DEC event ordering");
        check(!(tv&&tr),"DEC fabricated retirement");
        check(decrementer_pc[1:0]==0&&decrementer_pc>=BASE&&decrementer_pc<BASE+32'h10000,"DEC resume PC range");
        if(decrements==1)check(alias_retired&&!dpending,"DEC overtook store completion");
        decrements++;
      end
      if(tv&&tr)begin
        // Start counting only after the first TBU in the retry loop has sampled.
        if(phase==1&&!tb_enabled&&retired.insn[31:26]==6'd31&&
           retired.insn[10:1]==10'd371&&{retired.insn[15:11],retired.insn[20:16]}==10'd269)begin
          check(retired.value==32'h1234,"rollover initial upper sample");
          tb_enabled<=1;
        end
        check(!retired.illegal&&!retired.alignment_exception&&retired.fetch_fault==FETCH_OK,"retirement diagnostic");
        if(alias_stores==1&&!alias_retired)begin
          check(retired.insn[31:26]==6'd36,"alias owner must retire STW");alias_retired=1;
        end
        if(mailbox_written&&!mailbox_retired)begin
          check(retired.insn[31:26]==6'd36&&!retired.gpr_write&&!retired.update_write,"mailbox STW retirement");
          mailbox_retired=1;
        end
        retires++;
      end
      if(mailbox_retired&&!ipending&&!dpending&&!iv&&!dv&&!sv&&!rv)begin
        check(transitions==8&&last_context==0,"missing context transitions");
        check(alias_stores==1&&alias_retired&&reads>0&&writes>0,"missing mapped memory activity");
        check(interrupts==1&&decrements==2,"expected EXT followed by two DECs");
        $display("PASS compiled timer firmware: interrupts=%0d decrements=%0d transitions=%0d alias_stores=%0d retires=%0d reads=%0d writes=%0d cycles=%0d",interrupts,decrements,transitions,alias_stores,retires,reads,writes,cycles);$finish;
      end
    end
  end
  assert property(@(posedge clk) disable iff(!rst_n) sv&&!sr |=> sv&&$stable(iw));
  assert property(@(posedge clk) disable iff(!rst_n) rv&&!rr |=> rv&&$stable(rd));
  assert property(@(posedge clk) disable iff(!rst_n) tv&&!tr |=> tv&&$stable(retired));
  initial begin
    if(!$value$plusargs("IMAGE=%s",image_path)||!$value$plusargs("TOHOST=%h",tohost_addr))$fatal(1,"IMAGE/TOHOST required");
    check(tohost_addr>=BASE&&tohost_addr<=BASE+32'hfffc&&tohost_addr[1:0]==0,"mailbox range");
    foreach(mem[i])mem[i]=0;
    $readmemh(image_path,mem);repeat(4)@(negedge clk);rst_n=1;
    write_bat(10'd529,32'hfff00002);write_bat(10'd528,32'hfff00002);
    write_bat(10'd537,32'hfff00002);write_bat(10'd536,32'hfff00002);
    write_bat(10'd539,32'hfff00002);write_bat(10'd538,32'h10000002);
    @(negedge clk);start_valid=1;
    do @(posedge clk);while(!start_ready);
    @(negedge clk);start_valid=0;
  end
endmodule
