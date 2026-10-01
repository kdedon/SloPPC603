// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
// The compiled MMU stress image on the translated cached 60x top with the
// MVP profile. MODE seeds the external IRQ schedule, decrementer ticks, 60x
// target delays and retirement backpressure. Modes 1-8 also reset the CPU at
// a chosen point (during a PTE read or R/C write in a miss handler, a TLB
// load or invalidate, a translated line fill, a held IRQ, a DEC entry or at
// random cycles) and require the image to pass again from reset. RETRY adds
// seeded ARTRY, DRTRY and held data tenures; modes 9-11 reset in an ARTRY
// window, a DRTRY replacement or a held fill and imply RETRY. Modes 12 and 13
// reset inside the branch storm and during a translated cache-inhibited
// fetch. Modes 14 and 15 (15 with RETRY) end seeded tenures with TEA while
// MSR[RI]=1; each must enter the machine-check handler and retry at SRR0.
// RAM changes only through pin tenures.
/* verilator lint_off BLKSEQ */
module tb_compiled_mmu_stress_firmware;
  import ppc_pkg::*;
  logic clk=0,rst_n=0;
  always #5 clk=~clk;
  logic start_valid=0,start_ready,running,cir,cdr,cpr;
  logic tv,tr,halted,cut_accepted,ifetch_error,bus_error,bus_busy;
  logic pimem_error,router_busy,translation_fault;
  logic icache_hit,icache_miss,icache_busy,cache_enabled,unused_maintenance_ready;
  logic maintenance_done,maintenance_busy;
  logic interrupt_taken,decrementer_taken;
  logic [31:0] interrupt_pc,decrementer_pc;
  retire_packet_t retired;
  logic bat_ready,bat_rsp,bat_rejected,bat_unsupported,bat_config,bat_overlap;
  logic [3:0] bat_invalid;
  logic [49:0] unused_page_ports;
  logic unused_fault_instruction,unused_fault_write,unused_fault_miss;
  logic unused_fault_protection,unused_fault_guarded,unused_fault_config;
  logic unused_fault_invalid_input;
  logic [31:0] unused_fault_ea;
  logic [3:0] unused_fault_invalid_entry;

  logic br_n,bg_n,abb_n,abb_oe,ts_n,ts_oe,addr_oe;
  logic dbb_n,dbb_oe,d_oe,aack_n,dbg_n,ta_n,tbst_n,artry_n,drtry_n,tea_n;
  logic ci_n,wt_n,gbl_n;
  logic [31:0] a;
  logic [4:0] tt;
  logic [2:0] tsiz;
  logic [1:0] tc,cse;
  logic [63:0] d_i,d_o;
  logic [31:0] beat_addr;
  logic pin_done=0,pin_done_write=0;
  logic [31:0] pin_done_addr=0;
  int pin_done_size=0;
  int cycles=0;
  localparam int FW_MEM_BYTES=262144;
  `include "compiled_firmware.svh"

  localparam logic [31:0] RFI=32'h4c000064;
  int mode=0,retry=0;
  // TEA per mille of would-be TAs, offered only while the architecture
  // promises recovery (MSR[RI]=1, so not inside any handler).
  int tea_permille=0;
  logic retry_want=0,drtry_want=0,hold_want=0,tea_want=0;
  int hold_until=0;
  logic [31:0] lfsr=0,seed=32'h1;
  int bus_phase=0;
  logic irq=0,tick=0;
  logic [31:0] ext_count_addr,dec_count_addr,irq_ack_addr,miss_total_addr,mc_count_addr;

  // Per-run counters clear on every reset; totals do not.
  int retires=0,ext_taken=0,dec_taken=0,resumes=0,tgpr_entries=0,fills=0;
  int invalidates=0;
  int total_retires=0,total_ext=0,total_dec=0,total_resumes=0,total_cycles=0;
  int irq_in_miss=0,irq_in_bus=0,dec_in_miss=0,line_starts=0,page_lines=0;
  int cache_hits=0,cache_misses=0,chained=0,bypass_fetches=0,storm_retires=0;
  int bat_bypass=0,storm_trigger=0;
  int mc_taken=0,mc_fetch=0,mc_data=0;
  int resets_wanted=0,resets_done=0,next_irq=400;
  logic resume_pending=0,last_tgpr=0,last_irq_tgpr=0;
  logic [31:0] event_pc=0;
  logic [31:0] last_pc=0;
  string summary;

  logic checkstop;
  ppc_core_bat_cached_bus60x #(
    .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),.ENABLE_LIVE_CONTEXT(1'b1),
    .ENABLE_EXTERNAL_INTERRUPTS(1'b1),.ENABLE_TIMERS(1'b1),
    .ENABLE_RUNTIME_BAT(1'b1),.ENABLE_SEGMENT_REGISTERS(1'b1),
    .ENABLE_SDR1(1'b1),.ENABLE_TGPR(1'b1),
    .ENABLE_TLB_MISS_EXCEPTIONS(1'b1),.ENABLE_PAGE_TRANSLATION(1'b1),
    .ENABLE_PAGE_MISS_RESULTS(1'b1),.ENABLE_PAGE_DATA_EXCEPTIONS(1'b1),
    .ENABLE_PAGE_INSTRUCTION_EXCEPTIONS(1'b1),
    .ENABLE_TLB_INVALIDATE(1'b1),.ENABLE_TLB_LOAD(1'b1),
    .ENABLE_TEST_REDIRECT(1'b0),.ENABLE_MACHINE_CHECK(1'b1)
  ) dut(.bus_ce_i(1'b1),
    /* verilator lint_off PINCONNECTEMPTY */
    .perf_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .clk_i(clk),.rst_ni(rst_n),
    .external_irq_i(irq),.interrupt_taken_o(interrupt_taken),
    .interrupt_pc_o(interrupt_pc),
    .timer_tick_i(tick),.timebase_enable_i(1'b1),
    /* verilator lint_off PINCONNECTEMPTY */
    .snoop_ts_n_i(1'b1),.snoop_a_i(32'b0),.snoop_tt_i(5'b0),.snoop_gbl_n_i(1'b1),.artry_n_o(),.artry_oe_o(),
    .pin_event_i('0), .pin_status_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .decrementer_taken_o(decrementer_taken),
    .decrementer_pc_o(decrementer_pc),
    .bat_write_valid_i(1'b0),.bat_write_ready_o(bat_ready),
    .bat_write_spr_i('0),.bat_write_data_i('0),
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
    .checkstop_o(checkstop), .halted_o(halted),
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
    // No data cache in this profile.
    /* verilator lint_off PINCONNECTEMPTY */
    .dcache_busy_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .maintenance_busy_o(maintenance_busy),
    .br_n_o(br_n),.bg_n_i(bg_n),
    .abb_n_i(abb_oe?abb_n:1'b1),.abb_n_o(abb_n),.abb_oe_o(abb_oe),
    .ts_n_o(ts_n),.ts_oe_o(ts_oe),.a_o(a),.tt_o(tt),
    .tbst_n_o(tbst_n),.tsiz_o(tsiz),.tc_o(tc),
    .ci_n_o(ci_n),.wt_n_o(wt_n),.gbl_n_o(gbl_n),
    .cse_o(cse),.addr_oe_o(addr_oe),
    .aack_n_i(aack_n),.artry_n_i(artry_n),.dbg_n_i(dbg_n),
    .dbb_n_i(dbb_oe?dbb_n:1'b1),.dbb_n_o(dbb_n),
    .dbb_oe_o(dbb_oe),.d_i(d_i),.d_o(d_o),.d_oe_o(d_oe),
    .ta_n_i(ta_n),.drtry_n_i(drtry_n),.tea_n_i(tea_n), .xats_n_i(1'b1),
    /* verilator lint_off PINCONNECTEMPTY */ .xats_n_o() /* verilator lint_on PINCONNECTEMPTY */
  );

  // Observed only through the oracle's own fields.
  /* verilator lint_off UNUSEDSIGNAL */
  wire unused_outputs=^{cir,cdr,icache_busy,bat_ready,retired};
  /* verilator lint_on UNUSEDSIGNAL */
  wire tgpr=dut.translated_core.core.msr[17];
  wire recoverable=dut.translated_core.core.msr[MSR_RI];
  wire tlb_fill_offer=dut.translated_core.tlb_fill_req_valid;
  wire tlb_inv_offer=dut.translated_core.tlb_inv_req_valid;

  function automatic string check_detail();
    return $sformatf(" mode=%0d resets=%0d/%0d ext=%0d dec=%0d msr=%08x bus=%08x diag=%b last=%08x",
      mode,resets_done,resets_wanted,ext_taken,dec_taken,
      dut.translated_core.core.msr,a,
      {checkstop,halted,cut_accepted,pimem_error,ifetch_error,bus_error,translation_fault},last_pc);
  endfunction

  assign tr=rst_n&&(lfsr[2:0]!=3'd0);
  bus60x_retry_target_bfm #(.BEAT_GAP(1)) target(
    .clk_i(clk),.rst_ni(rst_n),.phase_i(bus_phase),
    .retry_i(retry_want),.drtry_i(drtry_want),.hold_i(hold_want),.tea_i(tea_want&&recoverable),
    .br_n_i(br_n),.ts_n_i(ts_n),.ts_oe_i(ts_oe),.a_i(a),.tt_i(tt),
    .tsiz_i(tsiz),.tbst_n_i(tbst_n),.tc_i(tc),.dbb_n_i(dbb_n),.dbb_oe_i(dbb_oe),
    .bg_n_o(bg_n),.aack_n_o(aack_n),.artry_n_o(artry_n),.dbg_n_o(dbg_n),
    .ta_n_o(ta_n),.drtry_n_o(drtry_n),.tea_n_o(tea_n));
  always_comb begin
    beat_addr=target.transfer_burst ?
      (target.transfer_addr&32'hffffffe0)+
        32'((((int'(target.transfer_addr[4:3])+target.beat)&3)*8)) :
      (target.transfer_addr&32'hfffffff8);
    d_i='0;
    if(target.transfer_pending&&!target.transfer_write)
      for(int lane=0;lane<8;lane++)
        d_i[63-8*lane -:8]=mem[int'(beat_addr-BASE)+lane];
    // A beat that DRTRY will cancel carries corrupt data.
    if(target.offer&&!target.transfer_write&&drtry_want)d_i=~d_i;
  end

  function automatic logic [31:0] xorshift(input logic [31:0] x);
    x^=x<<13;x^=x>>17;x^=x<<5;
    return x;
  endfunction
  // Seeded stimulus: bus phase, retirement stalls, DEC ticks and, with RETRY,
  // ARTRY 10%, DRTRY 8% of read beats and data tenures held 5-44 cycles.
  always @(posedge clk) begin
    lfsr<=lfsr==0?seed:xorshift(lfsr);
    bus_phase<=int'(lfsr[15:0]);
    tick<=rst_n&&(lfsr[5:4]!=2'd0);
    retry_want<=retry!=0&&lfsr[22:16]<7'd13;
    drtry_want<=retry!=0&&lfsr[29:23]<7'd10;
    tea_want<=tea_permille!=0&&int'(lfsr[31:22])<tea_permille;
    if(retry!=0&&target.data_ok&&hold_until<=cycles&&lfsr[31:26]<6'd3)
      hold_until<=cycles+5+int'(lfsr[13:8])%40;
    hold_want<=hold_until>cycles;
  end

  always @(posedge clk) begin : pin_ram
    if(!rst_n)begin
      pin_done<=0;pin_done_addr<=0;pin_done_write<=0;pin_done_size<=0;
    end else begin
      pin_done<=0;
      if(ts_oe&&!ts_n)begin
        check(router_busy&&bus_busy,"60x tenure without translation/bus owner");
        check(addr_oe&&abb_oe&&!abb_n&&!target.transfer_pending,
          "60x address ownership/overlap");
        check(a>=BASE&&int'(a-BASE)+32<=FW_MEM_BYTES,"60x RAM address range");
        check(wt_n&&gbl_n&&cse==0&&(tc==0||tc==2),"60x common bus attributes");
        if(!tbst_n)begin
          check(tt==5'b01110&&tsiz==2&&ci_n&&tc==2&&a[2:0]==0,
            "60x cacheable instruction-line shape");
          line_starts++;
          if(a>=32'hfff28000&&a<32'hfff30000)page_lines++;
        end else begin
          if(tc==2)bypass_fetches++;
          if(tc==2&&cir&&a[31:12]==20'hfff2e)bat_bypass++;
          check(tt==5'b01010||tt==5'b00010,"60x scalar transaction type");
          check(!ci_n&&(tsiz==1||tsiz==2||tsiz==4),
            "60x cache-inhibited scalar size/attribute");
        end
      end
      if(!ta_n)begin
        check(target.transfer_pending,"TA without selected tenure");
        if(target.transfer_write)begin
          check(d_oe,"target accepted undriven write data");
          for(int i=0;i<4;i++)
            if(i<target.transfer_size)
              mem[int'(target.transfer_addr-BASE)+i]=
                d_o[63-8*(int'(target.transfer_addr[2:0])+i) -:8];
        end else check(!d_oe,"processor drove read data");
        pin_done<=1;pin_done_addr<=target.transfer_addr;
        pin_done_write<=target.transfer_write;
        pin_done_size<=target.transfer_size;
      end
    end
  end

  // Architectural oracle: no diagnostic ever; every EXT/DEC entry resumes
  // at its saved PC; the IRQ level drops only on the handler's ack store.
  always @(posedge clk) begin : oracle
    if(!rst_n)begin
      retires=0;ext_taken=0;dec_taken=0;resumes=0;tgpr_entries=0;fills=0;
      chained=0;invalidates=0;bypass_fetches=0;bat_bypass=0;storm_retires=0;page_lines=0;
      resume_pending=0;last_tgpr=0;last_irq_tgpr=0;event_pc=0;
      mc_taken=0;mc_fetch=0;mc_data=0;
      irq<=0;cycles=0;next_irq=400+int'(lfsr[9:0]);
      mailbox_written=0;mailbox_retired=0;
    end else begin
      cycles++;total_cycles++;
      check(cycles<4000000,$sformatf("timeout retires=%0d",retires));
      check(!checkstop&&!halted&&!cut_accepted&&!pimem_error&&!ifetch_error&&
        !bus_error&&!translation_fault,
        "unexpected checkstop, halt, transport or translation diagnostic");
      check(!unused_page_ports[1]&&!bat_rsp&&!bat_rejected&&
        !bat_unsupported&&!bat_config&&!bat_overlap&&bat_invalid==0,
        "external management unexpectedly active");
      check(!maintenance_done&&!maintenance_busy&&cache_enabled,
        "unexpected cache maintenance/disable");
      if(running)check(!cpr,"unexpected problem state");

      if(tgpr&&!last_tgpr)tgpr_entries++;
      last_tgpr=tgpr;
      if(irq&&tgpr&&!last_irq_tgpr)irq_in_miss++;
      last_irq_tgpr=irq&&tgpr;
      if(irq&&target.transfer_pending&&!target.transfer_instruction)irq_in_bus++;
      if(dut.translated_core.core.special.decrementer_pending_o&&tgpr)dec_in_miss++;
      if(tlb_fill_offer)fills++;
      if(tlb_inv_offer)invalidates++;
      if(icache_hit)cache_hits++;
      if(icache_miss)cache_misses++;
      if(tv&&tr&&retired.pc>=32'h20060f00&&retired.pc<32'h20061100)storm_retires++;

      if(interrupt_taken||decrementer_taken)begin
        check(!(interrupt_taken&&decrementer_taken),"EXT and DEC in one cycle");
        check(!interrupt_taken||irq,"EXT taken without asserted IRQ");
        if(resume_pending)begin
          check((interrupt_taken?interrupt_pc:decrementer_pc)==event_pc,
            "chained event saved a different resume PC");
          resume_pending=0;chained++;
        end
        event_pc=interrupt_taken?interrupt_pc:decrementer_pc;
        if(interrupt_taken)begin ext_taken++;total_ext++;end
        else begin dec_taken++;total_dec++;end
      end
      if(tv&&tr)begin
        retires++;total_retires++;
        if(resume_pending)begin
          check(retired.pc==event_pc,
            $sformatf("RFI resumed at %08x, event saved %08x",retired.pc,event_pc));
          resume_pending=0;resumes++;total_resumes++;
        end
        // A machine check retires its instruction; the handler's RFI must
        // resume at that PC.
        if(retired.fetch_fault==FETCH_MACHINE_CHECK||
           retired.data_fault==DATA_MACHINE_CHECK)begin
          check(tea_permille!=0,"machine check without TEA");
          check(!retired.gpr_write&&!retired.update_write,
            "machine-checked access wrote a register");
          mc_taken++;
          if(retired.fetch_fault==FETCH_MACHINE_CHECK)mc_fetch++;else mc_data++;
          event_pc=retired.pc;
        end
        if(retired.insn==RFI&&
           ((retired.pc>=BASE+32'h200&&retired.pc<BASE+32'h300)||
            (retired.pc>=BASE+32'h500&&retired.pc<BASE+32'h600)||
            (retired.pc>=BASE+32'h900&&retired.pc<BASE+32'ha00)))
          resume_pending=1;
        mailbox_retire();
        last_pc=retired.pc;
      end

      // One IRQ at a time; it drops on the handler's physical ack write.
      if(!ta_n&&target.transfer_write&&target.transfer_addr==irq_ack_addr)begin
        check(irq,"IRQ ack without asserted IRQ");
        irq<=0;
        next_irq=cycles+150+int'(lfsr[10:0]);
      end else if(!irq&&running&&cycles>=next_irq&&!mailbox_written)
        irq<=1;
      // Mode 2 raises the IRQ inside the third miss handler.
      if(mode==2&&!irq&&tgpr&&tgpr_entries==3&&resets_done==0)irq<=1;

      if(pin_done&&pin_done_write)mailbox_store(pin_done_addr,pin_done_size==4);
    end
  end

  task automatic boot;
    @(negedge clk);rst_n=0;
    repeat(4)@(negedge clk);
    rst_n=1;
    @(negedge clk);start_valid=1;
    do @(posedge clk);while(!start_ready);
    @(negedge clk);start_valid=0;
  endtask

  // Wait for the mode's reset point; it must come before the mailbox.
  task automatic wait_trigger;
    case(mode)
      1:wait(tgpr_entries>=5&&tgpr&&target.transfer_pending&&
             !target.transfer_write&&!target.transfer_instruction);
      2:wait(irq&&tgpr&&tgpr_entries==3);
      3:wait(target.transfer_pending&&target.transfer_burst&&
             target.beat==2&&target.transfer_addr>=32'hfff28000&&
             target.transfer_addr<32'hfff2b000);
      4:wait(fills>=7&&tlb_fill_offer);
      5:wait(dec_taken>=3);
      6:wait(tgpr_entries>=4&&tgpr&&target.transfer_pending&&
             target.transfer_write);
      8:wait(invalidates>=40&&tlb_inv_offer);
      9:wait(tgpr&&target.retry_window&&target.retry_q&&
             !target.transfer_write&&!target.transfer_instruction);
      10:wait(target.replace_q&&target.transfer_burst&&target.beat>=1);
      11:wait(hold_want&&target.transfer_burst&&target.data_ok&&target.beat>=1);
      12:wait(storm_retires>=storm_trigger);
      13:wait(target.transfer_pending&&target.transfer_instruction&&
              !target.transfer_burst&&target.data_ok&&cir&&
              target.transfer_addr[31:12]==20'hfff2e);
      default:repeat(3000+int'(lfsr[15:0]))@(posedge clk);
    endcase
    repeat(mode==5?3:0)@(posedge clk);
    check(!mailbox_written,"image finished before its reset point");
  endtask

  initial begin
    load_image;
    if(!$value$plusargs("EXT_COUNT=%h",ext_count_addr)||
       !$value$plusargs("DEC_COUNT=%h",dec_count_addr)||
       !$value$plusargs("IRQ_ACK=%h",irq_ack_addr)||
       !$value$plusargs("MISS_TOTAL=%h",miss_total_addr)||
       !$value$plusargs("MC_COUNT=%h",mc_count_addr))
      $fatal(1,"EXT_COUNT/DEC_COUNT/IRQ_ACK/MISS_TOTAL/MC_COUNT required");
    if(!$value$plusargs("MODE=%d",mode))mode=0;
    if(!$value$plusargs("RETRY=%d",retry))retry=0;
    if(!$value$plusargs("TEA_PERMILLE=%d",tea_permille))tea_permille=0;
    if((mode>=9&&mode<=11)||mode==15)retry=1;
    if(mode>=14&&tea_permille==0)tea_permille=15;
    seed=32'h2545f491^(32'(mode)*32'h9e3779b9)^(retry!=0?32'h5bd1e995:32'h0);
    storm_trigger=100+int'(seed[8:0]);
    resets_wanted=(mode==0||mode>=14)?0:(mode==7?3:1);
    boot;
    while(resets_done<resets_wanted)begin
      wait_trigger;
      resets_done++;
      boot;
    end
    wait(mailbox_retired);
    while(bus_busy||target.transfer_pending||target.address_pending)
      @(posedge clk);
    @(negedge clk);
    check(word_at(ext_count_addr)==32'(ext_taken)&&
          word_at(dec_count_addr)==32'(dec_taken),
          $sformatf("handler counts ext=%0d dec=%0d, bench saw ext=%0d dec=%0d",
            word_at(ext_count_addr),word_at(dec_count_addr),ext_taken,dec_taken));
    // The last RFI before the mailbox may still await its resume.
    check(ext_taken>=8&&dec_taken>=8&&
          resumes+chained>=ext_taken+dec_taken-1&&resumes>chained,
          "too few events or resumes in the final run");
    check(page_lines>0&&cache_hits>0&&cache_misses>0&&tgpr_entries>=60&&
          bat_bypass>0&&storm_retires>0,
          "translated line fills, bypass fetches, storm or miss handlers missing");
    if(retry!=0)check(target.retries>0&&target.drtries>0&&target.held>0,
          "RETRY run without ARTRY, DRTRY or held tenures");
    check(word_at(mc_count_addr)==32'(mc_taken),
          $sformatf("handler machine checks %0d, bench saw %0d",word_at(mc_count_addr),mc_taken));
    if(tea_permille!=0)check(mc_fetch>0&&mc_data>0&&mc_taken<=target.teas,
          "TEA run without fetch and data machine checks, or more checks than TEAs");
    if(mode==0)check(irq_in_miss>0&&irq_in_bus>0&&dec_in_miss>0,
          "no IRQ/DEC overlap with a miss handler or bus tenure");
    summary=$sformatf("PASS compiled MMU stress mode=%0d retry=%0d resets=%0d misses=%0d ext=%0d dec=%0d",
      mode,retry,resets_done,word_at(miss_total_addr),ext_taken,dec_taken);
    summary={summary,$sformatf(" resumes=%0d chained=%0d retires=%0d cycles=%0d",
      resumes,chained,retires,cycles)};
    summary={summary,$sformatf(" irq_in_miss=%0d irq_in_bus=%0d dec_in_miss=%0d fills=%0d",
      irq_in_miss,irq_in_bus,dec_in_miss,fills)};
    summary={summary,$sformatf(" lines=%0d page_lines=%0d bypass=%0d bat_bypass=%0d storm=%0d",
      line_starts,page_lines,bypass_fetches,bat_bypass,storm_retires)};
    summary={summary,$sformatf(" tea=%0d mc=%0d mc_fetch=%0d mc_data=%0d",
      target.teas,mc_taken,mc_fetch,mc_data)};
    summary={summary,$sformatf(" artry=%0d drtry=%0d held_cycles=%0d total_retires=%0d total_cycles=%0d checks=%0d",
      target.retries,target.drtries,target.held,total_retires,total_cycles,checks)};
    $display("%s",summary);
    $finish;
  end
endmodule
/* verilator lint_on BLKSEQ */
