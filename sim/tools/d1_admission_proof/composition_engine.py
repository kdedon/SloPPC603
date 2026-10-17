# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Literal source fixture engine; supplied validated o/n/p strings."""
import re
names=['c0_move','pair_units','d1_base_wait','d1_lsu_ready','update_load','dispatch1','rename0_dq1','rename1_dq1','rename2_dq1']
def equation(s,name):
 m=re.search(r'  assign '+re.escape(name)+r' = .*?;',s,re.S);assert m,name
 return m.group(0).replace('  assign ','',1)
old_eq='\n'.join(equation(o,x) for x in names)
context='\n'.join(m.group(0).replace('  assign ','',1) for m in re.finditer(r'  assign d1_admission_context\.\w+ =\s*.*?;',n,re.S))
assert len(re.findall(r'^d1_admission_context\.',context,re.M))==15
helper_calls='\n'.join(equation(n,x) for x in
    ('d1_admission_actual','d1_admission_pre','d1_admission_fault'))
expected_calls={
 'd1_admission_actual': ('dispatch_uop.gpr_write','dispatch_uop.mem_update'),
 'd1_admission_pre': ('sp_dispatch_uop.gpr_write','sp_dispatch_uop.mem_update'),
 'd1_admission_fault': ("1'b0","1'b0")}
for name,(g,m) in expected_calls.items():
    actual_call=re.sub(r'\s+','',equation(n,name))
    assert actual_call==name+'=d1_permissions('+g+','+m+',d1_admission_context);',name
new_dispatch=equation(n,'dispatch1').replace('dispatch1 =','new_dispatch1 =',1)
new_rename='\n'.join(equation(n,x).replace(x+' =','new_'+x+' =',1).replace('dispatch1 &&','new_dispatch1 &&') for x in names[-3:])
for x in names[-3:]:assert equation(n,x)==equation(o,x)
helper=re.search(r'  function automatic d1_admission_t d1_permissions\(.*?  endfunction',n,re.S).group(0)
reads=re.search(r'  function automatic logic reads_reg\(.*?  endfunction',o,re.S).group(0)
assert reads in n
start=n.index('  typedef struct packed {\n    logic move_allowed')
stop=n.index('  d1_admission_context_t d1_admission_context;',start)
types=n[start:stop]
closure=p[p.index('  localparam int IQ_DEPTH'):p.index('  } uop_t;')+len('  } uop_t;')]
assert 'logic [2:0] dep_prev;' in p
# Identifier census after removing comments/field names: every scalar input is
# driven by the same timed fixture, not a manually substituted decision result.
text=re.sub(r'//[^\n]*','',old_eq+'\n'+context+'\n'+new_dispatch+'\n'+new_rename)
ids=set(re.findall(r'(?<![.\w])([A-Za-z_]\w*)',text))
structs={'dispatch_uop','dq1_uop','uop','src_a1','src_b1','dq1_pair','d1_admission_context'}
outputs=set(names)|{'d1_admission_ok','new_dispatch1'}|{'new_'+x for x in names[-3:]}
exclude=structs|outputs|{'reads_reg','SPECIAL_LOAD','SPECIAL_STORE'}
inputs=sorted(ids-exclude)
assert not any(x in inputs for x in ['logic','assign'])
selector_start=n.index('  always_comb begin\n    d1_admission_ok =')
selector_end=n.index('\n  end',selector_start)+len('\n  end')
select=n[selector_start:selector_end].replace('  always_comb begin','begin',1)
code='''// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
module tb_d1_composition;
'''+closure+'\n'+types+'\n'+helper+'\n'+reads+'''
 uop_t uop,dq1_uop,dispatch_uop,sp_dispatch_uop;
 operand_t src_a1,src_b1;
 // Only this exact width-identical field is referenced by extracted equations.
 struct packed {logic[2:0]dep_prev;} dq1_pair;
 d1_admission_context_t d1_admission_context;
 d1_admission_t d1_admission_actual,d1_admission_pre,d1_admission_fault;
 logic dispatch_align;
 logic '''+','.join(sorted(outputs))+';\n logic '+','.join(inputs)+''';
 integer i,j,k,samples,admit_yes,admit_no,fault_yes,gm_x,contexts_changed;
 function automatic logic s4(input integer x);
  case(x&3)0:s4=0;1:s4=1;2:s4=1'bx;default:s4=1'bz;endcase
 endfunction
 task automatic evaluate;begin
'''+old_eq+'\n'+context+'\n'+helper_calls+'\n'+select+'\n'+new_dispatch+'\n'+new_rename+'''
 if({c0_move,pair_units,d1_base_wait,d1_lsu_ready}!==
    {d1_admission_actual.move_ok,d1_admission_actual.pair_ok,d1_admission_actual.base_wait,d1_admission_actual.lsu_ready})
   $fatal(1,"actual upstream composition mismatch sample%0d",samples);
 if({dispatch1,rename0_dq1,rename1_dq1,rename2_dq1}!==
    {new_dispatch1,new_rename0_dq1,new_rename1_dq1,new_rename2_dq1})
   $fatal(1,"actual dispatch/rename composition mismatch sample%0d",samples);
 samples++;if(dispatch1===1)admit_yes++;if(dispatch1===0)admit_no++;
 if(dispatch_align===1)fault_yes++;
 if(sp_dispatch_uop.gpr_write===1'bx||sp_dispatch_uop.gpr_write===1'bz)gm_x++;
 if(d1_admission_pre.admit!==d1_admission_fault.admit)contexts_changed++;
 end endtask
 initial begin
 samples=0;admit_yes=0;admit_no=0;fault_yes=0;gm_x=0;contexts_changed=0;
 for(j=0;j<3;j++)for(i=0;i<65536;i++)begin
'''
code+='\n'.join(' '+x+'=s4((i>>'+str((a%8)*2)+')+'+str(a//8)+');' for a,x in enumerate(inputs))
code+='''
 uop='0;dq1_uop='0;sp_dispatch_uop='0;src_a1='0;src_b1='0;dq1_pair='0;
 sp_dispatch_uop.gpr_write=s4(i);sp_dispatch_uop.mem_update=s4(i>>2);
 sp_dispatch_uop.dst=3;dq1_uop.src_a=3;dq1_uop.zero_a=s4(i>>4);
 dq1_uop.use_imm=s4(i>>6);dq1_uop.special_op=SPECIAL_LOAD;
 dq1_uop.mem_update=s4(i>>8);dq1_pair.dep_prev={s4(i>>10),s4(i>>12),s4(i>>14)};
 src_a1.ready=s4(i>>4);src_b1.ready=s4(i>>6);
 dispatch_align=s4(i>>8);dispatch_uop=sp_dispatch_uop;
 if(dispatch_align)begin dispatch_uop.gpr_write=0;dispatch_uop.mem_update=0;end
 if(j!=0)begin
  // Nonvacuous dispatch contexts: D0 serialized move/IU paired with IU/LSU.
  dispatch=1;seq_last=1;cq1_ready=1;d1_remove=0;c0_carry=0;c1_carry=0;
  sru_wait1=0;update_wait1=0;flags_tok1=0;d1_needs_flags=0;
  d1_iu_ready=1;d1_mem=0;d1_fp=0;c0_branch=0;c0_lane=0;c0_fp=0;c0_fp_mem=0;
  c0_iu=(j==2);d1_iu=(j==1);d1_lsu=(j==2);d1_branch=0;d1_gpr=1;
  special_uop=1;sru_move=1;unit_update=s4(i>>10);
  alloc_ready=s4(i>>12);alloc1_ready=s4(i>>14);alloc2_ready=s4(i>>6);
  lsu_ready=1;lane_mem_idle=1;fp_unsafe_pending=0;msr_le=0;
  LSU_BASE_SNOOP=1;LSU_BASE_WAIT=0;ENABLE_SUPERVISOR_EXCEPTIONS=1;
 end
 evaluate();
 end
 $display("COMPOSITION BINS yes=%0d no=%0d fault=%0d gmXZ=%0d differing=%0d",admit_yes,admit_no,fault_yes,gm_x,contexts_changed);
 if(samples!=196608||admit_yes==0||admit_no==0||fault_yes==0||gm_x==0||contexts_changed==0)$fatal(1,"composition coverage missing");
 $display("PASS actual D1 composition samples=%0d",samples);$finish;
 end
endmodule
'''
