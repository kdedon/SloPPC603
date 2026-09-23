// Compiled page PP DSI repair/retry firmware through CPU-seeded TLB translation and committed MSR context.
// Physical byte RAM uses independent delayed/backpressured instruction/data ports.
/* verilator lint_off BLKSEQ */
module tb_compiled_page_dsi_firmware;
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
  logic last_context=0;
  int idelay=0,ddelay=0,cycles=0,retires=0,checks=0,reads=0,writes=0;
  int transitions=0,alias_stores=0,dsi_loads=0,dsi_stores=0,tlbld_retires=0;
  logic external_irq,interrupt_taken,decrementer_taken;
  int bat_writes=0;

  logic [31:0] unused_decrementer_pc;
  logic [31:0] unused_interrupt_pc;
  assign external_irq=0;
  string image_path;
  logic [49:0] unused_page_ports;
  ppc_core_bat #(.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),.ENABLE_LIVE_CONTEXT(1'b1),
                 .ENABLE_EXTERNAL_INTERRUPTS(1'b1),.ENABLE_TIMERS(1'b1),.ENABLE_RUNTIME_BAT(1'b1),
                 .ENABLE_SEGMENT_REGISTERS(1'b1),.ENABLE_PAGE_TRANSLATION(1'b1),
                 .ENABLE_PAGE_DATA_EXCEPTIONS(1'b1),.ENABLE_TLB_LOAD(1'b1)) dut(
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
      cycles++;check(cycles<100000,"page DSI firmware timeout");
      check(!halted&&!cut_accepted&&!physical_error&&!interrupt_taken&&!decrementer_taken,
            "unexpected halt/physical/asynchronous event");
      check(!unused_page_ports[1],"fixture TLB management active");
      if(fault)check(!unused_fi&&!unused_fp&&!unused_fm&&!unused_fg&&!unused_fc&&
                     !unused_finv&&unused_fentries==0&&unused_fea==32'h10008000&&
                     unused_page_ports[42]&&unused_page_ports[44]&&!unused_page_ports[43],
                      $sformatf("wrong page/router fault classification fi=%b fw=%b fm=%b fp=%b fg=%b fc=%b finv=%b fent=%h fea=%08x page=%h",unused_fi,unused_fw,unused_fm,unused_fp,unused_fg,unused_fc,unused_finv,unused_fentries,unused_fea,unused_page_ports));
      check(!bat_valid&&!bat_rsp&&!bat_rejected&&!bat_unsupported&&!bat_config&&
            !bat_overlap&&bat_invalid==0,"harness must not program BATs");
      if(running)begin
        check(!bat_ready&&!cpr&&!cir,"instruction translation unexpectedly enabled");
        if(cdr!=last_context)begin
          transitions++;last_context=cdr;
          check(transitions<=10,"extra DR context transition");
        end
      end
      if(idelay>0)idelay<=idelay-1;
      if(ddelay>0)ddelay<=ddelay-1;
      if(sv&&sr)ipending<=0;
      if(rv&&rr)dpending<=0;
      if(iv&&ir)begin
        check(ia>=BASE&&ia<=BASE+32'hfffc&&ia[1:0]==0,"instruction physical RAM range");
        check(iwimg==4'b0001,"real-mode instruction attributes");
        ipending<=1;fetch_pc<=ia;idelay<=1+cycles%4;
      end
      if(dv&&dr)begin
        check(da>=BASE&&da<=BASE+32'hfffc&&da[1:0]==0,"data physical RAM range");
        check(dwimg==(cdr?4'b0000:4'b0011),"data attributes");
        dpending<=1;ddelay<=1+cycles%5;rd<=word_at(da);
        if(dw)begin
          writes++;
          if(da==BASE+32'h8000)begin
            check(st==15&&alias_stores<2,"denied page store escaped or extra physical store");
            check(alias_stores==0 ? (!cdr&&wd==32'h13579bdf) :
                  (cdr&&wd==32'h2468ace0&&dsi_loads==1&&dsi_stores==1),
                  "protected physical word changed incorrectly");
            alias_stores++;ddelay<=18;
          end
          for(int lane=0;lane<4;lane++)if(st[3-lane])mem[int'(da-BASE)+lane]=wd[31-lane*8 -:8];
          if(da==tohost_addr&&word_at(da)!=0)begin
            check(st==15&&word_at(da)==1,$sformatf("firmware failure mailbox=%08x",word_at(da)));
            check(!mailbox_written,"duplicate mailbox");mailbox_written=1;
          end
        end else reads++;
      end
      if(tv&&tr)begin
        check(!retired.illegal&&!retired.alignment_exception&&retired.fetch_fault==FETCH_OK,
              "retirement diagnostic");
        selector={retired.insn[15:11],retired.insn[20:16]};
        if(retired.insn[31:26]==31&&selector>=528&&selector<=543&&
           retired.insn[10:1]==467)bat_writes++;
        if(retired.insn[31:26]==31&&retired.insn[10:1]==978)begin
          check(!cir&&!cdr&&!retired.illegal&&!retired.gpr_write&&!retired.update_write,
                "TLBLD context or side effect");
          tlbld_retires++;
        end
        if(retired.data_fault!=DATA_OK)begin
          check(retired.data_fault==DATA_DSI_PROTECTION&&!retired.gpr_write&&
                !retired.update_write&&!retired.write_xer,"DSI leaked architectural result");
          check(dut.core.regfile.gpr[retired.insn[20:16]]==32'h10007ffc,
                "faulting update base changed before exception retirement");
          if(retired.insn[31:26]==33)begin
            check(dut.core.regfile.gpr[retired.insn[25:21]]==32'h76543210,
                  "denied update load destination changed");
            check(dsi_loads==0,"repeated denied load after handler repair");
            dsi_loads++;
          end else begin
            check(retired.insn[31:26]==37,"wrong fault instruction");
            check(dut.core.regfile.gpr[retired.insn[25:21]]==32'h2468ace0,
                  "denied update store source changed");
            check(dsi_stores==0,"repeated denied store after handler repair");
            dsi_stores++;
          end
        end
        if(mailbox_written&&!mailbox_retired)begin
          check(retired.insn[31:26]==36&&!retired.gpr_write&&!retired.update_write,
                "mailbox retirement");mailbox_retired=1;
        end
        retires++;
      end
      if(mailbox_retired&&!ipending&&!dpending&&!iv&&!dv&&!sv&&!rv)begin
        check(transitions==8&&!cdr&&fault&&unused_fw&&unused_page_ports[42]&&
              unused_page_ports[44]&&!unused_page_ports[43]&&
              !unused_page_ports[45]&&!unused_page_ports[46]&&
              !unused_page_ports[47]&&!unused_page_ports[48]&&!unused_page_ports[49],
              "missing clean page PP denial or context transitions");
        check(alias_stores==2&&dsi_loads==1&&dsi_stores==1&&bat_writes==12&&
              tlbld_retires==4,"missing CPU-seeded page DSI effects");
        check(word_at(BASE+32'h8000)==32'h2468ace0,"final physical data corrupted");
        $display("PASS compiled page DSI firmware: DSIload=%0d DSIstore=%0d TLBLD=%0d BATwrites=%0d retires=%0d cycles=%0d",
                 dsi_loads,dsi_stores,tlbld_retires,bat_writes,retires,cycles);
        $finish;
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
    foreach(mem[i])mem[i]=0;
    $readmemh(image_path,mem,0,65535);repeat(4)@(negedge clk);rst_n=1;
    @(negedge clk);start_valid=1;
    do @(posedge clk);while(!start_ready);
    @(negedge clk);start_valid=0;
  end
endmodule
