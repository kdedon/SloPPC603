// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Optional observer only. No DUT controls or metadata are driven here.
`define IB_CORE soc.cpu.cpu.translated_core.core
`define IB_BAT soc.cpu.cpu.translated_core
logic ib_enabled=0, ib_active=0, ib_done=0, ib_configured=0;
logic [31:0] ib_start_pc,ib_start_word,ib_stop_pc,ib_stop_word;
longint unsigned ib_clock=0,ib_begin_cycle=0,ib_end_cycle=0,ib_packets=0,ib_macros=0,ib_partial=0,ib_removed=0,ib_branch_retired=0;
longint unsigned ib_spec=0,ib_resolve=0,ib_miss=0,ib_fast=0,ib_slow_origin=0,ib_slow=0,ib_anchored=0,ib_fp=0;
integer ib_fd=0;
string ib_tuple_path;
initial begin
  ib_enabled=$test$plusargs("INTEGER_BRANCH_PROFILE");
  if(ib_enabled) begin
    if(!$value$plusargs("INTEGER_RETIRE_TUPLES=%s",ib_tuple_path)||
       !$value$plusargs("LOOP_START_PC=%h",ib_start_pc)||
       !$value$plusargs("LOOP_START_WORD=%h",ib_start_word)||
       !$value$plusargs("LOOP_STOP_PC=%h",ib_stop_pc)||
       !$value$plusargs("LOOP_STOP_WORD=%h",ib_stop_word))
      $fatal(1,"integer branch observer requires tuple path and all four guarded loop landmarks");
    ib_fd=$fopen(ib_tuple_path,"w");
    if(ib_fd==0)$fatal(1,"cannot open integer retirement tuples");
    $fdisplay(ib_fd,"# integer-branch tuple-v1: active architectural packet effects, ordered retire0 then retire1");
  end
end

task automatic ib_check_config;
  if(ENABLE_DCACHE || DISPATCH_WIDTH!=2 || !ENABLE_LSU_PIPE || FPU_IMPL!=0 ||
     `IB_CORE.ENABLE_FPU!=ENABLE_FPU || `IB_CORE.DMEM_BITS!=32 ||
     `IB_CORE.ENABLE_FETCH_HINTS!=ENABLE_FETCH_HINTS ||
     `IB_CORE.DISPATCH_WIDTH!=2 || `IB_CORE.FETCH_WIDTH!=2 || !`IB_CORE.ENABLE_LSU_PIPE ||
     `IB_CORE.BRANCH_REMOVAL || !`IB_CORE.ENABLE_BRANCH_SPEC ||
     !`IB_CORE.ENABLE_BRANCH_EARLY_RECOVERY || `IB_CORE.BS_ANCHOR ||
     `IB_CORE.BS_EARLY==ENABLE_FPU || `IB_CORE.FETCH_DECODE_REG ||
     !`IB_CORE.MISPREDICT_FETCH_NOW || soc.cpu.cpu.ENABLE_DCACHE)
    $fatal(1,"integer branch comparison profile mismatch");
  ib_configured=1;
endtask

// The packet's page_miss capsule, rename/update ownership and tags, and
// cq1_ok are allocation/recovery metadata, outside this architectural tuple.
// Scope this waiver to the formal; all active effect fields stay checked below.
/* verilator lint_off UNUSEDSIGNAL */
task automatic ib_packet(input ppc_pkg::retire_packet_t p);
/* verilator lint_on UNUSEDSIGNAL */
  logic [31:0] cr_mask,xer_mask;
  if(!ib_active&&!ib_done&&p.pc==ib_start_pc)begin
    if(p.insn!=ib_start_word)$fatal(1,"loop start word changed");
    ib_active=1;ib_begin_cycle=ib_clock;
  end
  if(ib_active&&p.pc==ib_stop_pc)begin
    if(p.insn!=ib_stop_word)$fatal(1,"loop stop word changed");
    ib_active=0;ib_done=1;ib_end_cycle=ib_clock;
  end else if(ib_active)begin
    if(p.illegal||p.alignment_exception||p.data_fault!=ppc_pkg::DATA_OK||
       p.fetch_fault!=ppc_pkg::FETCH_OK||p.fpr_write||p.removed_branches!=0)
      $fatal(1,"noninteger/fault/removed event in matched loop");
    if($countones({p.write_cr_field,p.write_cr_fields,p.write_cr_bit})>1)
      $fatal(1,"multiple CR write permissions in normalized retire packet");
    cr_mask=0;xer_mask=0;
    if(p.write_cr_fields)for(int f=0;f<8;f++)if(p.cr_mask[7-f])cr_mask|=32'hf0000000>>(4*f);
    if(p.write_cr_field)cr_mask|=32'hf0000000>>(4*p.cr_field);
    if(p.write_cr_bit)cr_mask|=32'h80000000>>p.cr_bit;
    if(p.write_xer)xer_mask=32'he000007f;
    if(p.write_ca)xer_mask|=32'h20000000;
    if(p.write_ov_so)xer_mask|=32'hc0000000;
    // Inactive payload/index bits and allocation identities have no
    // architectural meaning. Preserve every active effect and permission.
    $fdisplay(ib_fd,"%08x %08x %x %x %x %02x %08x %x %02x %08x %x %x %x %x %x %x %x %x %08x %08x %08x %08x %x %x %x %08x %08x",
      p.pc,p.insn,p.seq_partial,p.needs_flags,p.gpr_write,
      p.gpr_write?p.gpr:5'b0,p.gpr_write?p.value:32'b0,
      p.update_write,p.update_write?p.update_gpr:5'b0,p.update_write?p.update_value:32'b0,
      p.write_xer,p.write_ca,p.write_ov_so,p.write_cr_field,
      p.write_cr_fields,p.write_cr_bit,
      p.write_cr_field?p.cr_field:3'b0,p.write_cr_fields?p.cr_mask:8'b0,
      p.write_cr_bit?{27'b0,p.cr_bit}:32'b0,cr_mask,p.cr_delta&cr_mask,xer_mask,
      p.branch,p.branch_lk,p.branch_ctr,p.branch?p.value:32'b0,p.xer_delta&xer_mask);
    ib_packets++;ib_macros+=64'(!p.seq_partial);ib_partial+=64'(p.seq_partial);
    ib_removed+=64'(p.removed_branches);ib_branch_retired+=64'(p.branch);
  end
endtask


// Optional what-if counters only: no routing, eligibility or oracle is driven.
logic ib_q_enabled;
longint unsigned ib_q_starts[2]='{default:0}, ib_q_guard_true[2]='{default:0};
longint unsigned ib_q_potential[2]='{default:0}, ib_q_denied[2]='{default:0};
longint unsigned ib_q_lsu[2]='{default:0}, ib_q_fp[2]='{default:0}, ib_q_special[2]='{default:0};
longint unsigned ib_q_adopt[2]='{default:0}, ib_q_native_release[2]='{default:0}, ib_q_kill[2]='{default:0};
longint unsigned ib_q_replay[2]='{default:0}, ib_q_sticky[2]='{default:0}, ib_q_recovery[2]='{default:0};
longint unsigned ib_q_unknown[2]='{default:0}, ib_q_older_dq0_fp=0;
initial begin
  ib_q_enabled=$test$plusargs("INTEGER_QUIET_OBSERVE");
  if(ib_q_enabled&&!$test$plusargs("INTEGER_BRANCH_PROFILE"))
    $fatal(1,"quiet-start observation requires the guarded integer branch profile");
end

task automatic ib_quiet_sample;
  logic q_start0,q_start1,q_quiet,q_lane_ready,q_capable;
  q_start0=`IB_CORE.dispatch && `IB_CORE.bu_branch && `IB_CORE.bu_spec;
  q_start1=`IB_CORE.dispatch1 && `IB_CORE.d1_bc && !`IB_CORE.d1_bc_now;
  // Hypothetical option=1; these three existing parameters are unchanged.
  q_capable=`IB_CORE.ENABLE_BRANCH_SPEC && `IB_CORE.ENABLE_BRANCH_EARLY_RECOVERY && `IB_CORE.ENABLE_FPU;
  q_quiet=1'b0;
  if (!`IB_CORE.fp_pending && !`IB_CORE.special_busy && `IB_CORE.lsu_empty && !`IB_CORE.lsu_adopt_valid &&
        !`IB_CORE.special_fp_load_release && !`IB_CORE.fp_kill_q && !`IB_CORE.fp_replay_q &&
        !`IB_CORE.fp_replay_req_q && !`IB_CORE.fp_sticky_waited_q && !`IB_CORE.recovery_accepted)
    q_quiet=1'b1;
  for(int lane=0;lane<2;lane++)begin
    if((lane==0&&q_start0)||(lane==1&&q_start1))begin
      ib_q_starts[lane]++;
      q_lane_ready=1'b0;
      if(q_quiet)begin
        if(lane==0)q_lane_ready=1'b1;
        else if(!`IB_CORE.c0_fp && !`IB_CORE.c0_fp_mem)q_lane_ready=1'b1;
      end
      if(q_lane_ready)ib_q_guard_true[lane]++;
      else ib_q_denied[lane]++;
      if(q_capable&&q_lane_ready)ib_q_potential[lane]++;
      // Blocker counters intentionally overlap; their sum is not stall cycles.
      if(!`IB_CORE.lsu_empty)ib_q_lsu[lane]++;
      if(`IB_CORE.fp_pending)ib_q_fp[lane]++;
      if(`IB_CORE.special_busy)ib_q_special[lane]++;
      if(`IB_CORE.lsu_adopt_valid)ib_q_adopt[lane]++;
      if(`IB_CORE.special_fp_load_release)ib_q_native_release[lane]++;
      if(`IB_CORE.fp_kill_q)ib_q_kill[lane]++;
      if(`IB_CORE.fp_replay_q||`IB_CORE.fp_replay_req_q)ib_q_replay[lane]++;
      if(`IB_CORE.fp_sticky_waited_q)ib_q_sticky[lane]++;
      if(`IB_CORE.recovery_accepted)ib_q_recovery[lane]++;
      if((^{`IB_CORE.fp_pending,`IB_CORE.special_busy,`IB_CORE.lsu_empty,
            `IB_CORE.lsu_adopt_valid,`IB_CORE.special_fp_load_release,
            `IB_CORE.fp_kill_q,`IB_CORE.fp_replay_q,`IB_CORE.fp_replay_req_q,
            `IB_CORE.fp_sticky_waited_q,`IB_CORE.recovery_accepted})===1'bx)
        ib_q_unknown[lane]++;
      if(lane==1)begin
        if(`IB_CORE.c0_fp||`IB_CORE.c0_fp_mem)ib_q_older_dq0_fp++;
        if((^{`IB_CORE.c0_fp,`IB_CORE.c0_fp_mem})===1'bx)ib_q_unknown[lane]++;
      end
    end
  end
endtask

task automatic ib_quiet_report;
  if(ib_q_enabled)for(int lane=0;lane<2;lane++)begin
    $display("INTEGER_QUIET observation_only=1 fpu=%0d lane=%0d starts=%0d guard_true=%0d potential_option1=%0d guard_denied=%0d lsu_nonempty=%0d fp_pending=%0d special_busy=%0d adopt=%0d native_release=%0d delayed_kill=%0d replay=%0d sticky_wait=%0d recovery=%0d unknown_tests=%0d older_dq0_fp=%0d",
      ENABLE_FPU,lane,ib_q_starts[lane],ib_q_guard_true[lane],ib_q_potential[lane],ib_q_denied[lane],
      ib_q_lsu[lane],ib_q_fp[lane],ib_q_special[lane],ib_q_adopt[lane],ib_q_native_release[lane],
      ib_q_kill[lane],ib_q_replay[lane],ib_q_sticky[lane],ib_q_recovery[lane],ib_q_unknown[lane],
      lane==1?ib_q_older_dq0_fp:64'd0);
  end
endtask

always @(posedge clk)begin
  if(ib_enabled&&running)begin
    ib_clock++;
    if(!ib_configured)ib_check_config();
    if((`IB_CORE.dispatch&&(`IB_CORE.fp_uop||`IB_CORE.fp_mem_issue))||
       (`IB_CORE.dispatch1&&`IB_CORE.d1_fp)||`IB_CORE.fp_launch_valid||
       `IB_CORE.fp_result_valid||`IB_CORE.fp_replay||`IB_CORE.fp_fpscr!=0)ib_fp++;
    if(ib_active)begin
      if(ib_q_enabled)ib_quiet_sample();
      if((`IB_CORE.dispatch&&`IB_CORE.bu_branch&&`IB_CORE.bu_spec)||
         (`IB_CORE.dispatch1&&`IB_CORE.d1_bc&&!`IB_CORE.d1_bc_now)||`IB_CORE.carry_start)ib_spec++;
      if(`IB_CORE.bs_resolve)begin
        ib_resolve++;
        if(`IB_CORE.bs_taken!=`IB_CORE.bs_pred_q)ib_miss++;
      end
      if(`IB_CORE.bs_early_miss)ib_miss++;
      if(`IB_CORE.bs_recover&&`IB_CORE.recovery_accepted)ib_fast++;
      if(!`IB_CORE.BS_EARLY&&`IB_CORE.commit&&`IB_CORE.bs_head)ib_slow_origin++;
      if(`IB_CORE.bs_redirect_q&&`IB_CORE.recovery_accepted)ib_slow++;
      if(`IB_CORE.bs_valid_q&&`IB_CORE.bs_anch_q)ib_anchored++;
    end
    if(`IB_CORE.retire_valid_o&&`IB_CORE.retire_ready_i)ib_packet(`IB_CORE.retire_o);
    if(`IB_CORE.retire_valid_o&&`IB_CORE.retire_ready_i&&
       `IB_CORE.retire1_valid_o&&`IB_CORE.retire1_ready_i)ib_packet(`IB_CORE.retire1_o);
  end
end

task automatic integer_branch_report;
  if(ib_enabled)begin
    if(!ib_configured||!ib_done||ib_active||ib_end_cycle<=ib_begin_cycle||
       ib_packets==0||ib_macros==0||ib_branch_retired==0||ib_spec==0||ib_resolve==0||ib_miss==0||
       ib_removed!=0||ib_anchored!=0||ib_fp!=0)
      $fatal(1,"missing matched integer loop or meaningful branch coverage");
    if((!ENABLE_FPU&&(ib_fast==0||ib_slow!=0||ib_slow_origin!=0))||
       (ENABLE_FPU&&(ib_fast!=0||ib_slow==0||ib_slow_origin==0)))
      $fatal(1,"missing actual fast/slow accepted branch recovery");
    $fclose(ib_fd);ib_fd=0;
    ib_quiet_report();
    $display("INTEGER_PAIR fpu=%0d hints=%0d dcache=0 dmem=32 width=2 fetch=2 lsu=1 removal=0 fdreg=0 now=1 full=1 sq=%0d snoop=%0d basewait=%0d cpumodel=%0d ce=%0d mhz=%0d early=%0d anchor=0 icsets=%0d icways=%0d iq=%0d cq=%0d rename=%0d cycles=%0d packets=%0d macros=%0d partial=%0d branches=%0d removed=%0d spec=%0d resolve=%0d miss=%0d fast=%0d slow_origin=%0d slow=%0d fp=%0d",
      ENABLE_FPU,`IB_CORE.ENABLE_FETCH_HINTS,`IB_CORE.STORE_QUEUE,`IB_CORE.LSU_BASE_SNOOP,`IB_CORE.LSU_BASE_WAIT,`IB_CORE.CPU_VARIANT,soc.CE_DIV,soc.SYS_MHZ,`IB_CORE.BS_EARLY,soc.cpu.cpu.IC_SETS,soc.cpu.cpu.IC_WAYS,
      ppc_pkg::IQ_DEPTH,ppc_pkg::CQ_DEPTH,ppc_pkg::GPR_RENAME_DEPTH,
      ib_end_cycle-ib_begin_cycle,ib_packets,ib_macros,ib_partial,ib_branch_retired,
      ib_removed,ib_spec,ib_resolve,ib_miss,ib_fast,ib_slow_origin,ib_slow,ib_fp);
  end
endtask
`undef IB_CORE
`undef IB_BAT
