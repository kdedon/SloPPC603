#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Optional actual-source CQ projection proof. Bounded four-state expressions only.

Requires reviewed candidate installed in rtl/ppc_completion.sv. --prepare-only
checks guards and emits the fixture without compiling. No private-tree inputs.
Full-source inverse guards protect downstream acceptance/kill/retirement logic.
Temporal queue reachability and architectural precision require canonical RTL tests.
"""
from pathlib import Path
import argparse, hashlib, re, subprocess, shutil
ROOT=Path(__file__).resolve().parents[2]
PINS={'baseline_completion': 'eb0e1aa902394340b1e5c1501629a27c0dc167474c48d1380a32505b23d2c2a5', 'candidate_completion': '50611d2d59cb55f2801a580a6511384388416e3223be747c8fcee4cd3d0dbcf3', 'package': '64897d2f8bff3dbc6e0247f6b89d773eb80627bedfe6397173870a81964d58ee', 'old_fragments': ['    logic pivot_hit, kill_head, kill_head1;\n\n    // Queue age', '      (pivot_age < count_q) && active_q[redirect_pivot_i.index] &&\n      (redirect_pivot_i.generation == generations_q[redirect_pivot_i.index]);'], 'new_fragments': ['    logic pivot_hit, kill_head, kill_head1;\n    logic [CQ_DEPTH-1:0] pivot_owner_match;\n\n    // Compare each registered owner before selecting the pivot slot.\n    for (int s = 0; s < CQ_DEPTH; s++)\n      pivot_owner_match[s] = active_q[s] &&\n        (redirect_pivot_i.generation == generations_q[s]);\n\n    // Queue age', '      (pivot_age < count_q) && pivot_owner_match[redirect_pivot_i.index];'], 'status': 'Source preparation only; no compiler, simulator, or synthesis run.'}
FROZEN_BLOCK='  always_comb begin\n    logic [COUNT_WIDTH-1:0] retained, pivot_age;\n    logic pivot_hit, kill_head, kill_head1;\n\n    // Queue age is distance from head; numeric slot or generation order has\n    // no age meaning after ring wrap and reuse. Each slot\'s age is computed\n    // directly so that no selection waits on a walk from the head.\n    pivot_age = ring_age(redirect_pivot_i.index, head_q);\n    pivot_hit = PIVOT && !redirect_all_i &&\n      (redirect_pivot_i.index < CQ_INDEX_WIDTH\'(CQ_DEPTH)) &&\n      (pivot_age < count_q) && active_q[redirect_pivot_i.index] &&\n      (redirect_pivot_i.generation == generations_q[redirect_pivot_i.index]);\n    redirect_found = redirect_all_i || pivot_hit;\n    retained = redirect_all_i ? \'0 :\n               pivot_hit ? pivot_age + COUNT_WIDTH\'(redirect_keep_pivot_i) : count_q;\n    redirect_candidate_kill = \'0;\n    for (int s = 0; s < CQ_DEPTH; s++) begin\n      if ((ring_age(CQ_INDEX_WIDTH\'(s), head_q) < count_q) &&\n          (ring_age(CQ_INDEX_WIDTH\'(s), head_q) >= retained))\n        redirect_candidate_kill[s] = 1\'b1;\n    end\n    // The head has age 0 and the next entry age 1. The head is removed by a\n    // recovery that removes all, or by one that drops a pivot at the head.\n    kill_head = (count_q != \'0) && (redirect_all_i ||\n      (PIVOT && !redirect_keep_pivot_i && (redirect_pivot_i.index == head_q) &&\n       active_q[head_q] && (redirect_pivot_i.generation == generations_q[head_q])));\n    // synthesis translate_off\n    if (rst_ni && PIVOT && (kill_head != ((count_q != \'0) && (retained == \'0))))\n      $error("head removal disagrees with the retained count");\n    // synthesis translate_on\n    kill_head1 = (count_q > COUNT_WIDTH\'(1)) && (retained <= COUNT_WIDTH\'(1));\n\n    if (!PIVOT) begin\n      redirect_found = 1\'b1;\n      retained = \'0;\n      redirect_candidate_kill = active_q;\n    end\n    redirect_candidate_survivors = COUNT_WIDTH\'(retained);\n    redirect_candidate_tail =\n      ring_offset(head_q, retained);\n    redirect_accepted_o = redirect_valid_i && redirect_found;\n    // An offered finished head is irrevocable even when ready on this edge.\n    if (ENABLE_PIVOT_RECOVERY && (count_q != \'0) &&\n        (head_q < CQ_INDEX_WIDTH\'(CQ_DEPTH)) && !retire_hold_i &&\n        done_q[head_q] && kill_head)\n      redirect_accepted_o = 1\'b0;\n    // So is an offered CQ[1] that may retire.\n    if (ENABLE_PIVOT_RECOVERY && retire1_settled && retire1_ready_i && !retire_hold_i &&\n        kill_head1)\n      redirect_accepted_o = 1\'b0;\n\n    redirect_kill_o = redirect_accepted_o ? redirect_candidate_kill : \'0;\n    // The pending-arrival path uses the stronger fixed-head predicate below.\n    // Retain the general accepted-kill form as its simulation cross-check.\n    // synthesis translate_off\n    head_killed = redirect_accepted_o && (PIVOT ? kill_head : active_q[head_q]);\n    // synthesis translate_on\n    for (int i = 0; i < CQ_DEPTH; i++)\n      redirect_kill_generation_o[i] = generations_q[i];\n  end\n\n'
FROZEN_AGE="  function automatic logic [COUNT_WIDTH-1:0] ring_age(\n    input logic [CQ_INDEX_WIDTH-1:0] slot,\n    input logic [CQ_INDEX_WIDTH-1:0] head\n  );\n    logic [CQ_INDEX_WIDTH:0] diff;\n    diff = (CQ_INDEX_WIDTH+1)'(slot) - (CQ_INDEX_WIDTH+1)'(head);\n    if (slot < head) diff = diff + (CQ_INDEX_WIDTH+1)'(CQ_DEPTH);\n    return COUNT_WIDTH'(diff);\n  endfunction\n\n"
FROZEN_OFFSET="  function automatic logic [CQ_INDEX_WIDTH-1:0] ring_offset(\n    input logic [CQ_INDEX_WIDTH-1:0] index,\n    input logic [COUNT_WIDTH-1:0] offset\n  );\n    logic [CQ_INDEX_WIDTH:0] sum;\n    sum = (CQ_INDEX_WIDTH+1)'(index) + (CQ_INDEX_WIDTH+1)'(offset);\n    if (sum >= (CQ_INDEX_WIDTH+1)'(CQ_DEPTH))\n      sum = sum - (CQ_INDEX_WIDTH+1)'(CQ_DEPTH);\n    return CQ_INDEX_WIDTH'(sum);\n  endfunction\n\n"
TB='\nmodule tb_cq_fixed_pivot_actual;\n logic [4:0] active,done;\n logic [7:0] generations[5],generation;\n logic [2:0] index,head,count,indices[16];\n logic pivot,enable,all_entries,keep,valid,hold_retire,pair_done,pair_ready,age_guard;\n logic states[4];\n wire old_owner,new_owner,old_guard,new_guard;\n wire [63:0] old_result,new_result;\n wire [7:0] old_generations[5],new_generations[5];\n integer checks,original_checks,index_checks,ring_checks;\n integer owner0,owner1,ownerx,hit1,accepted1,killed1,outside,unknown_index;\n integer all_bins[4],pivot_bins[4],slot_bins[5];\n original old_dut(active,done,generations,head,count,index,generation,pivot,enable,\n   all_entries,keep,valid,hold_retire,pair_done,pair_ready,age_guard,\n   old_owner,old_guard,old_result,old_generations);\n candidate new_dut(active,done,generations,head,count,index,generation,pivot,enable,\n   all_entries,keep,valid,hold_retire,pair_done,pair_ready,age_guard,\n   new_owner,new_guard,new_result,new_generations);\n task automatic compare;\n   #1;\n   assert(old_owner===new_owner && old_guard===new_guard && old_result===new_result)\n     else $fatal(1,"CQ projection mismatch vector=%0d idx=%b head=%b count=%b gen=%b active=%b old=%b/%b/%h new=%b/%b/%h",\n       checks,index,head,count,generation,active,old_owner,old_guard,old_result,new_owner,new_guard,new_result);\n   for(integer s=0;s<5;s=s+1)\n     assert(old_generations[s]===new_generations[s] && old_generations[s]===generations[s])\n       else $fatal(1,"generation payload changed");\n   checks=checks+1;\n   if(old_owner===0) owner0=owner0+1;\n   if(old_owner===1) owner1=owner1+1;\n   if(old_owner===1\'bx) ownerx=ownerx+1;\n   if(old_result[26]===1\'b1) hit1=hit1+1;\n   if(old_dut.redirect_accepted_o===1\'b1) accepted1=accepted1+1;\n   if((|old_dut.redirect_kill_o)===1\'b1) killed1=killed1+1;\n   if(!$isunknown(index) && index>=5) outside=outside+1;\n   if($isunknown(index)) unknown_index=unknown_index+1;\n   for(integer s=0;s<4;s=s+1) begin\n     if(all_entries===states[s]) all_bins[s]=all_bins[s]+1;\n     if(pivot===states[s]) pivot_bins[s]=pivot_bins[s]+1;\n   end\n   for(integer s=0;s<5;s=s+1)\n     if(index===3\'(s) && old_owner===1\'b1) slot_bins[s]=slot_bins[s]+1;\n endtask\n initial begin\n   checks=0;original_checks=0;index_checks=0;ring_checks=0;\n   owner0=0;owner1=0;ownerx=0;hit1=0;accepted1=0;killed1=0;outside=0;unknown_index=0;\n   for(integer s=0;s<4;s=s+1) begin all_bins[s]=0;pivot_bins[s]=0;end\n   for(integer s=0;s<5;s=s+1) slot_bins[s]=0;\n   states[0]=0;states[1]=1;states[2]=1\'bx;states[3]=1\'bz;\n   assert($isunknown(states[2])) else $fatal(1,"four-state backend required");\n   for(integer i=0;i<8;i=i+1) indices[i]=3\'(i);\n   indices[8]=3\'bx00;indices[9]=3\'b0x0;indices[10]=3\'b00x;indices[11]=3\'bx11;\n   indices[12]=3\'bzzz;indices[13]=3\'bxxx;indices[14]=3\'bz01;indices[15]=3\'b10z;\n   pivot=1;all_entries=0;age_guard=1;\n   head=0;count=5;done=0;enable=1;keep=1;valid=1;hold_retire=0;pair_done=0;pair_ready=1;\n   // Original 141312 vectors, now bound to actual source owner/full recovery block.\n   for(integer a=0;a<32;a=a+1) for(integer idx=0;idx<8;idx=idx+1)\n     for(integer gen=0;gen<256;gen=gen+1) for(integer stale=0;stale<2;stale=stale+1) begin\n       active=5\'(a);index=3\'(idx);generation=8\'(gen);\n       for(integer s=0;s<5;s=s+1) generations[s]=8\'(gen+s*37);\n       if(idx<5) generations[idx]=8\'(gen+stale);\n       compare();original_checks=original_checks+1;\n     end\n   for(integer idx=0;idx<16;idx=idx+1) for(integer slot=0;slot<5;slot=slot+1)\n     for(integer bitno=0;bitno<8;bitno=bitno+1) for(integer uk=2;uk<4;uk=uk+1)\n       for(integer guard=0;guard<4;guard=guard+1) begin\n         index=indices[idx];active=5\'b11111;generation=8\'h5a;\n         for(integer s=0;s<5;s=s+1) generations[s]=8\'h5a;\n         generations[slot][bitno]=states[uk];active[slot]=states[guard];\n         pivot=states[guard];all_entries=0;age_guard=1;\n         compare();original_checks=original_checks+1;\n         pivot=1;all_entries=states[guard];age_guard=states[guard];generation[bitno]=states[uk];\n         compare();original_checks=original_checks+1;\n       end\n   // All 64 four-state three-bit index words, mixed active/generation and raw\n   // head/count states. This factored grid is not the exhaustive full CQ state.\n   for(integer ix=0;ix<64;ix=ix+1) for(integer gp=0;gp<4;gp=gp+1)\n     for(integer hd=0;hd<8;hd=hd+1) for(integer cp=0;cp<4;cp=cp+1)\n       for(integer ac=0;ac<4;ac=ac+1) for(integer pv=0;pv<4;pv=pv+1) begin\n         index={states[(ix/16)%4],states[(ix/4)%4],states[ix%4]};\n         head=3\'(hd);case(cp) 0:count=0;1:count=1;2:count=5;default:count=3\'bx1z;endcase\n         active={states[gp],1\'b1,1\'b0,states[(gp+1)%4],1\'b1};\n         generation=8\'h5a;\n         for(integer s=0;s<5;s=s+1) begin\n           generations[s]=8\'h5a;\n           generations[s][s]=states[gp];\n           if(gp==1) generations[s][7]=1\'b1; // known mismatch wins over lower X/Z\n           if(gp==2) generations[s][7]=1\'b1;\n         end\n         pivot=states[pv];all_entries=states[ac];keep=states[gp];valid=states[cp];\n         enable=states[pv];hold_retire=states[ac];pair_done=states[gp];pair_ready=states[cp];\n         done=active;age_guard=states[cp];\n         compare();index_checks=index_checks+1;\n       end\n   // All binary head/count/index encodings; deliberately includes invalid raw\n   // queue snapshots to preserve expressions without asserting reachability.\n   for(integer hd=0;hd<8;hd=hd+1) for(integer ct=0;ct<8;ct=ct+1)\n     for(integer ix=0;ix<8;ix=ix+1) for(integer p=0;p<2;p=p+1)\n       for(integer a=0;a<2;a=a+1) for(integer k=0;k<2;k=k+1)\n         for(integer control=0;control<16;control=control+1) begin\n           head=3\'(hd);count=3\'(ct);index=3\'(ix);pivot=1\'(p);all_entries=1\'(a);keep=1\'(k);\n           generation=8\'hff;\n           for(integer s=0;s<5;s=s+1) generations[s]=control[0]?8\'hff:8\'h00;\n           active=control[1]?5\'b11111:5\'b00101;done=control[2]?5\'b11111:0;\n           enable=control[3];hold_retire=control[0];pair_done=control[2];pair_ready=control[1];\n           valid=control[3];age_guard=1;\n           compare();ring_checks=ring_checks+1;\n         end\n   $display("CQ counts total=%0d inherited=%0d index=%0d ring=%0d owner0/1/X=%0d/%0d/%0d hit=%0d accepted=%0d kill=%0d outside=%0d indexXZ=%0d",\n     checks,original_checks,index_checks,ring_checks,owner0,owner1,ownerx,hit1,accepted1,killed1,outside,unknown_index);\n   assert(original_checks==141312 && index_checks==131072 && ring_checks==65536 && checks==337920)\n     else $fatal(1,"missing finite vectors");\n   assert(owner0>0 && owner1>0 && ownerx>0 && hit1>0 && accepted1>0 && killed1>0 && outside>0 && unknown_index>0)\n     else $fatal(1,"vacuous result category");\n   for(integer s=0;s<4;s=s+1) assert(all_bins[s]>0 && pivot_bins[s]>0) else $fatal(1,"missing control state");\n   for(integer s=0;s<5;s=s+1) assert(slot_bins[s]>0) else $fatal(1,"missing live slot");\n   $display("PASS actual-source fixed pivot: %0d bounded four-state observations",checks);\n   $finish;\n end\nendmodule\n'

def sha(s): return hashlib.sha256(s.encode()).hexdigest()

FRONTEND_PACKAGE_SHA = 'd2f9ebdc165a880507bead0c791f3fdabffc38a2dcef7e98f0338882e61dc7b6'
FRONTEND_PACKAGE_ADDITIONS = ['\n  /* verilator lint_off UNUSEDSIGNAL */\n  // Takes the CR rename, or writes CR from the FPU.\n  function automatic logic cr_writer(uop_t u);\n    return !u.illegal && (u.write_cr_field || u.write_cr_fields || u.write_cr_bit ||\n      ((u.needs_flags || u.write_xer) && !(!u.write_xer && (u.write_ca || u.write_ov_so))));\n  endfunction\n  /* verilator lint_on UNUSEDSIGNAL */\n', '  // Per-word transport: {CR rename demand, branch class, needs primary IU}.\n  typedef struct packed {\n    logic cr_writer;\n    fetch_lookahead_t lookahead;\n  } fetch_hint_t;\n']

def original_package(text):
    """Accept only the original package or the exact reviewed hint additions.

    Normalization removes the shared CR-demand helper and opaque hint typedef
    only; the original package pin and CQ type checks remain authoritative.
    """
    if sha(text) == PINS['package']:
        return text
    assert sha(text) == FRONTEND_PACKAGE_SHA, 'unreviewed frontend package/type drift'
    for addition in FRONTEND_PACKAGE_ADDITIONS:
        assert text.count(addition) == 1, 'frontend package inverse shape'
        text = text.replace(addition, '')
    assert sha(text) == PINS['package'], 'frontend package inverse original hash'
    return text
def section(s,a,b):
    assert s.count(a)==s.count(b)==1, ('extraction markers',a,b)
    return s[s.index(a):s.index(b)]
def clean(s):
    # Omit simulation-only assertions from the combinational expression fixture.
    # They constrain reachable states; the matrix intentionally includes raw states.
    return re.sub(r'    // synthesis translate_off\n.*?    // synthesis translate_on\n','',s,flags=re.S)
def module(name, actual, candidate):
    actual=clean(actual)
    final='    for (int i = 0; i < CQ_DEPTH; i++)\n      redirect_kill_generation_o[i] = generations_q[i];\n'
    assert actual.count(final)==1
    # Outputs include full acceptance/candidate/qualified kill/count/tail results.
    actual=actual.replace(final,final+'''    observed = {pivot_hit, redirect_found, pivot_age, retained,
      redirect_candidate_kill, redirect_candidate_survivors,
      redirect_candidate_tail, redirect_accepted_o, redirect_kill_o,
      kill_head, kill_head1};
''')
    owner='active_q[redirect_pivot_i.index] && (redirect_pivot_i.generation == generations_q[redirect_pivot_i.index])'
    loop=''
    if candidate:
        loop=section(actual,'    for (int s = 0; s < CQ_DEPTH; s++)\n      pivot_owner_match[s]', '    // Queue age')
        owner='pivot_owner_match[redirect_pivot_i.index]'
    # Reuse the actual candidate loop for the separately observed owner expression.
    # Full original/candidate blocks below remain literal source (assertions aside).
    aux=('logic [CQ_DEPTH-1:0] pivot_owner_match;\n'+loop if candidate else '')
    hits=re.findall(r'(?m)^    pivot_hit =[\s\S]*?;\n',actual)
    assert len(hits)==1,'actual pivot assignment extraction'
    h=hits[0].replace('pivot_hit =','guarded_owner =').replace('(pivot_age < count_q)','age_guard')
    # No rewrite of ring-age/full-block behavior; synthetic age_guard only reproduces
    # the inherited 141312 owner/guard corpus alongside actual full-block comparisons.
    return f'''module {name}(
 input logic [4:0] active_q,done_q,
 input logic [7:0] generations_q [5],
 input logic [2:0] head_q,count_q,
 input logic [2:0] pivot_index,
 input logic [7:0] pivot_generation,
 input logic PIVOT,ENABLE_PIVOT_RECOVERY,redirect_all_i,redirect_keep_pivot_i,
 input logic redirect_valid_i,retire_hold_i,retire1_settled,retire1_ready_i,age_guard,
 output logic owner,guarded_owner,
 output logic [63:0] observed,
 output logic [7:0] redirect_kill_generation_o [5]);
 localparam int CQ_DEPTH=5,CQ_INDEX_WIDTH=3,COUNT_WIDTH=3;
 typedef struct packed {{logic [2:0] index; logic [7:0] generation;}} completion_tag_t;
 completion_tag_t redirect_pivot_i;
 assign redirect_pivot_i={{pivot_index,pivot_generation}};
 logic redirect_found,redirect_accepted_o;
 logic [4:0] redirect_candidate_kill,redirect_kill_o;
 logic [2:0] redirect_candidate_survivors,redirect_candidate_tail;
{FROZEN_AGE}{FROZEN_OFFSET}
 always_comb begin
 {aux}
 owner={owner};
 {h}
 end
{actual}
endmodule
'''
def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output',type=Path,required=True)
    ap.add_argument('--prepare-only',action='store_true')
    a=ap.parse_args()
    pkg=original_package((ROOT/'rtl/ppc_pkg.sv').read_text())
    assert sha(pkg)==PINS['package'],'package/type drift'
    for literal in ('localparam int CQ_DEPTH = 5;', 'localparam int CQ_GENERATION_WIDTH = 8;',
                    'localparam int CQ_INDEX_WIDTH = $clog2(CQ_DEPTH);',
                    'logic [CQ_INDEX_WIDTH-1:0] index;',
                    'logic [CQ_GENERATION_WIDTH-1:0] generation;'):
        assert pkg.count(literal)==1, ('type guard',literal)
    current=(ROOT/'rtl/ppc_completion.sv').read_text()
    assert sha(current)==PINS['candidate_completion'],'reviewed candidate not installed or source drift'
    old=current
    for before,after in zip(PINS['old_fragments'],PINS['new_fragments']):
        assert old.count(after)==1,'inverse delta shape'
        old=old.replace(after,before)
    assert sha(old)==PINS['baseline_completion'],'inverse whole-module guard'
    start='  always_comb begin\n    logic [COUNT_WIDTH-1:0] retained, pivot_age;'
    oldblock=section(old,start,'  assign alloc_ready_o =')
    newblock=section(current,start,'  assign alloc_ready_o =')
    assert oldblock==FROZEN_BLOCK,'independent original block drift'
    for s in (old,current):
        assert section(s,'  function automatic logic [COUNT_WIDTH-1:0] ring_age(', '  // Allocation-time fault metadata')==FROZEN_AGE
        assert section(s,'  function automatic logic [CQ_INDEX_WIDTH-1:0] ring_offset(', '  // Distance from head to slot')==FROZEN_OFFSET
    fixture=module('original',FROZEN_BLOCK,False)+module('candidate',newblock,True)+TB
    a.output.mkdir(parents=True,exist_ok=True)
    tb=a.output/'tb_cq_fixed_pivot_actual.sv'
    tb.write_text('// SPDX-License-Identifier: GPL-2.0-or-later\n// Copyright (c) 2026 Kevin Dedon\n`default_nettype none\n'+fixture+'\n`default_nettype wire\n')
    print('SOURCE GUARDS PASS; fixture prepared; no temporal/full-module claim',flush=True)
    if a.prepare_only: return
    for tool in ('iverilog','vvp'):
        assert shutil.which(tool),tool+' is required for this optional target'
    exe=a.output/'proof.vvp'
    subprocess.run(['iverilog','-g2012','-gassertions','-s','tb_cq_fixed_pivot_actual','-o',str(exe),str(tb)],check=True,timeout=30)
    subprocess.run(['vvp',str(exe)],check=True,timeout=90)
if __name__=='__main__': main()
