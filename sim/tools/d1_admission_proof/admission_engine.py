# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Literal source fixture engine; supplied validated old/new/pkg strings."""
import re
# Whole-source inverse guards actual state, all outgoing allocations and ownership.
def fun(s,n):
 m=re.search(r'  function automatic [^\n]*\b'+n+r'\b.*?  endfunction',s,re.S);assert m,n
 return m.group(0)
def typed(s,n):
 matches=list(re.finditer(r'  typedef struct packed \{.*?\} '+n+r';',s,re.S));assert matches
 # Start at the final struct opener preceding this exact type's close.
 end=matches[-1].end();start=s.rfind('  typedef struct packed {',0,end)
 return s[start:end]
helper=fun(new,'d1_permissions')
ctx=typed(new,'d1_admission_context_t');outtype=typed(new,'d1_admission_t')
assert ctx.count('logic ')==4 and 'logic alloc0, alloc1, alloc2;' in ctx
branch=fun(old,'branch_resolved');assert branch==fun(new,'branch_resolved')
start=old.index('  always_comb begin\n    dispatch_pre = uop;')
end=old.index('\n  // The alignment fault depends',start)
priority=old[start:end];assert priority in new
base_start=old.index('  always_comb begin\n    dispatch_base = dispatch_pre;')
base_end=old.index('\n  // A branch resolved',base_start)
base=old[base_start:base_end];assert base in new
# Extract the exact finite type closure preceding uop_t, avoiding the unrelated
# later unpacked localparam arrays unsupported by Icarus. No type substitutions.
closure=pkg[pkg.index('  localparam int IQ_DEPTH'):pkg.index('  } uop_t;')+len('  } uop_t;')]
assert 'function ' not in closure
msr='\n'.join(re.findall(r'  localparam int MSR_(?:PR|FP)\s*=.*?;',pkg))
assert msr.count('localparam')==2
# Independent frozen pre-refactor equations on an explicit scalar cut.
reference='''function automatic d1_admission_t original(input logic g, input logic m, input d1_admission_context_t c);
 d1_admission_t r;
 r.move_ok = c.move_allowed && !(g && c.reads_dst);
 r.pair_ok = c.pair_other || (r.move_ok && c.iu);
 r.base_wait = c.base_allowed && (c.no_previous_base || (g && !m));
 r.lsu_ready = c.lsu_allowed && (r.base_wait || !c.misaligned) && (r.base_wait || c.sources_ready);
 r.rename_ready = (c.update && g) ? c.alloc2 : (g || c.update) ? c.alloc1 : c.alloc0;
 r.admit = r.pair_ok && (!c.lsu || r.lsu_ready) && (!c.gpr || r.rename_ready);
 return r;
endfunction
'''
# Freeze all original connection formulas, not only the scalar reference. These
# are reviewed cut boundaries; the finite test does not enumerate all CPU inputs.
boundary={}
for name in ('c0_move','pair_units','d1_base_wait','d1_lsu_ready','dispatch1','update_load'):
 m=re.search(r'  assign '+name+r' = .*?;',old,re.S);assert m,name
 boundary[name]=m.group(0)
# Exact actual late selection, no handwritten candidate selector.
sel_start=new.index('  always_comb begin\n    d1_admission_ok =')
sel_end=new.index('\n  end',sel_start)+len('\n  end')
selector=new[sel_start:sel_end].replace('  always_comb begin','task automatic select_candidate; begin',1)+'\nendtask'
selector=selector.replace('d1_admission_ok','selected').replace('d1_admission_pre','pre').replace('d1_admission_fault','fault')
# Actual priority/base blocks become timed-driver tasks only; equations literal.
priority_task=priority.replace('  always_comb begin','task automatic apply_priority; begin',1)+'\nendtask'
base_task=base.replace('  always_comb begin','task automatic apply_base; begin',1)+'\nendtask'
body='''// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
module tb_d1_admission;
'''+closure+'\n'+msr+'\n'+ctx+'\n'+outtype+'\n'+helper+'\n'+branch+'\n'+reference+'''
 d1_admission_context_t c;
 d1_admission_t pre,fault,actual,expected;
 logic selected,dispatch_align,g,m,br,og,om,common;
 uop_t uop,dispatch_pre,dispatch_base,old_uop,pre_uop;
 fetch_packet_t iq_head;
 logic [31:0] msr;
 logic ENABLE_SUPERVISOR_EXCEPTIONS, ENABLE_TLB_MISS_EXCEPTIONS;
 logic ENABLE_MACHINE_CHECK,ENABLE_DEBUG_EXCEPTIONS,ENABLE_FPU,base_snoop,dispatch_misaligned;
 integer samples,priority_samples,phase,i,j,k,changed,aligned,faulted,xselectors,branchx,priority_suppressed;
 function automatic logic s4(input integer v);
  case(v&3) 0:s4=0;1:s4=1;2:s4=1'bx;default:s4=1'bz;endcase
 endfunction
'''+selector+'\n'+priority_task+'\n'+base_task+'''
 task automatic compare;
 begin
  actual=d1_permissions(og,om,c);
  expected=original(og,om,c);
  if(actual!==expected)$fatal(1,"actual/helper mismatch phase=%0d sample=%0d",phase,samples);
  pre=d1_permissions(g,m,c);fault=d1_permissions(0,0,c);select_candidate();
  if((selected&&common)!==(expected.admit&&common))
    $fatal(1,"selected admission mismatch phase=%0d sample=%0d",phase,samples);
  samples++;
  if(pre.admit!==fault.admit)changed++;
  if(dispatch_align===0)aligned++;
  if(dispatch_align===1)faulted++;
  if(dispatch_align===1'bx||dispatch_align===1'bz)xselectors++;
 end
 endtask
 initial begin
  samples=0;priority_samples=0;changed=0;aligned=0;faulted=0;xselectors=0;branchx=0;priority_suppressed=0;
  // Capacity and procedural-selector cut: 4^8 controls, eight distinct contexts.
  phase=0;
  for(j=0;j<8;j++)for(i=0;i<65536;i++)begin
   c='1;c.move_allowed=j[0];c.reads_dst=j[1];c.base_allowed=j[2];
   c.pair_other=0;c.iu=1;c.lsu=j[1];c.no_previous_base=j[0];
   g=s4(i);m=s4(i>>2);dispatch_align=s4(i>>4);br=s4(i>>6);
   c.update=s4(i>>8);c.alloc0=s4(i>>10);c.alloc1=s4(i>>12);c.alloc2=s4(i>>14);
   if(br)g=0;og=g;om=m;if(dispatch_align)begin og=0;om=0;end
   common=s4(j);compare();
  end
  // Eight independent structural predicates with correlated remaining controls.
  phase=1;
  for(i=0;i<65536;i++)begin
   c='1;c.move_allowed=s4(i);c.reads_dst=s4(i>>2);c.pair_other=s4(i>>4);c.iu=s4(i>>6);
   c.base_allowed=s4(i>>8);c.no_previous_base=s4(i>>10);c.lsu_allowed=s4(i>>12);c.sources_ready=s4(i>>14);
   c.misaligned=s4(i>>2);c.lsu=s4(i>>8);c.gpr=s4(i>>12);c.update=s4(i>>6);
   c.alloc0=s4(i>>4);c.alloc1=s4(i>>10);c.alloc2=s4(i>>14);
   g=s4(i>>2);m=s4(i>>12);dispatch_align=s4(i>>4);common=1;
   og=g;om=m;if(dispatch_align)begin og=0;om=0;end
   compare();
  end
  // Actual priority and complete branch/packet procedures; all feature bits on
  // except FPU varied, plus raw four-state values. No full-package shim.
  phase=2;
  for(k=0;k<4;k++)for(i=0;i<65536;i++)begin
   uop='0;iq_head='0;msr=0;
   ENABLE_SUPERVISOR_EXCEPTIONS=1;ENABLE_TLB_MISS_EXCEPTIONS=1;
   ENABLE_MACHINE_CHECK=1;ENABLE_DEBUG_EXCEPTIONS=1;ENABLE_FPU=s4(i>>14);
   case(k)0:uop.special_op=SPECIAL_LOAD;1:uop.special_op=SPECIAL_STORE;
    2:uop.special_op=SPECIAL_MFSPR;default:uop.special_op=SPECIAL_FPU;endcase
   uop.gpr_write=s4(i);uop.mem_update=s4(i>>2);br=s4(i>>4);
   dispatch_misaligned=s4(i>>6);base_snoop=s4(i>>8);uop.illegal=s4(i>>10);
   uop.privileged=s4(i>>12);msr[MSR_PR]=s4(i>>14);msr[MSR_FP]=1;
   if(i[13])iq_head.fault=FETCH_ISI_PROTECTION;
   apply_priority();apply_base();
   old_uop=branch_resolved(dispatch_base,br);pre_uop=branch_resolved(dispatch_pre,br);
   g=pre_uop.gpr_write;m=pre_uop.mem_update;og=old_uop.gpr_write;om=old_uop.mem_update;
   c='1;c.pair_other=0;c.lsu=0;c.move_allowed=1;c.reads_dst=s4(i>>6);
   c.alloc0=1;c.alloc1=0;c.alloc2=0;c.update=s4(i>>2);common=1;
   compare();priority_samples++;
   if(br===1'bx||br===1'bz)branchx++;
   if(dispatch_misaligned===1&&dispatch_align===0)priority_suppressed++;
  end
  $display("D1 BINS changed=%0d aligned=%0d faulted=%0d selectorXZ=%0d branchXZ=%0d prioritysuppressed=%0d",changed,aligned,faulted,xselectors,branchx,priority_suppressed);
  if(samples!=851968||priority_samples!=262144||changed==0||aligned==0||faulted==0||xselectors==0||branchx==0||priority_suppressed==0)$fatal(1,"coverage missing");
  $display("PASS D1 bounded admission samples=%0d priority=%0d",samples,priority_samples);
  $finish;
 end
endmodule
'''
# Targeted behavioral mutants are isolated test functions; actual DUT source
# and normal comparison corpus stay unchanged. Each must show the specified
# difference rather than merely fail a source hash.
mut_capacity=helper.replace('d1_permissions(', 'mutant_capacity(',1)
assert mut_capacity.count('c.update')==2
mut_capacity=mut_capacity.replace('c.update','mem_update')
mut_branch=branch.replace('branch_resolved(', 'mutant_branch(',1)
assert mut_branch.count("      r.gpr_write = 1'b0;")==1
mut_branch=mut_branch.replace("      r.gpr_write = 1'b0;",'')
assert mut_branch.count('    return r;')==1
mut_branch=mut_branch.replace('    return r;', '    r.gpr_write = u.gpr_write && !branch;\n    return r;')
mut_select=selector.replace('select_candidate','select_raw_mutant').replace('selected','mutant_selected').replace('if (dispatch_align)','if (dispatch_misaligned)')
mut_tasks="""
 logic mutant_selected;
 d1_admission_t mutant_result;
 uop_t mutant_uop;
 integer semantic_witnesses;
 task automatic check_semantic_mutants; begin
  semantic_witnesses=0;
  // Raw update reservation remains1 after a fault clears actual G/M.
  c='0;c.pair_other=1;c.gpr=1;c.update=1;c.alloc0=1;c.alloc1=0;
  actual=d1_permissions(0,0,c);expected=original(0,0,c);
  mutant_result=mutant_capacity(0,0,c);
  if(actual!==expected||expected.admit!==1'b0||mutant_result.admit!==1'b1)
    $fatal(1,"missing postfault-update capacity counterexample");
  semantic_witnesses++;
  // Actual priority defers alignment to base-snoop; raw misalignment is1.
  uop='0;iq_head='0;msr=0;uop.special_op=SPECIAL_LOAD;uop.gpr_write=1;
  ENABLE_SUPERVISOR_EXCEPTIONS=1;ENABLE_TLB_MISS_EXCEPTIONS=1;
  ENABLE_MACHINE_CHECK=1;ENABLE_DEBUG_EXCEPTIONS=1;ENABLE_FPU=1;
  base_snoop=1;dispatch_misaligned=1;br=0;
  apply_priority();apply_base();
  old_uop=branch_resolved(dispatch_base,br);pre_uop=branch_resolved(dispatch_pre,br);
  c='0;c.pair_other=1;c.gpr=1;c.alloc0=1;c.alloc1=0;
  pre=d1_permissions(pre_uop.gpr_write,pre_uop.mem_update,c);
  fault=d1_permissions(0,0,c);select_candidate();select_raw_mutant();
  expected=original(old_uop.gpr_write,old_uop.mem_update,c);
  if(dispatch_align!==0||selected!==expected.admit||selected!==0||mutant_selected!==1)
    $fatal(1,"missing raw-alignment selector counterexample");
  semantic_witnesses++;
  // Procedural unknown branch is false; a logical mask turns G=1 intoX.
  uop='0;uop.gpr_write=1;br=1'bx;
  old_uop=branch_resolved(uop,br);mutant_uop=mutant_branch(uop,br);
  c='0;c.pair_other=1;c.gpr=1;c.alloc0=0;c.alloc1=1;
  expected=original(old_uop.gpr_write,old_uop.mem_update,c);
  actual=d1_permissions(old_uop.gpr_write,old_uop.mem_update,c);
  mutant_result=d1_permissions(mutant_uop.gpr_write,mutant_uop.mem_update,c);
  if(actual!==expected||old_uop.gpr_write!==1||mutant_uop.gpr_write!==1'bx||
     expected.admit!==1||mutant_result.admit!==1'bx)
    $fatal(1,"missing procedural branch-X counterexample");
  semantic_witnesses++;
  if(semantic_witnesses!=3)$fatal(1,"semantic witnesses missing");
  $display("PASS targeted semantic counterexamples=%0d",semantic_witnesses);
 end endtask
"""
body=body.replace(' initial begin\n',mut_capacity+'\n'+mut_branch+'\n'+mut_select+'\n'+mut_tasks+'\n initial begin\n',1)
assert body.count('  $finish;')==1
body=body.replace('  $finish;','  check_semantic_mutants();\n  $finish;',1)
