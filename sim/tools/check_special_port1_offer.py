#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Guard the actual special-port1 cofactor and emit its optional Icarus proof.

Frozen independent old control equations; actual candidate source extraction.
No Git history or private snapshot dependency. No HDL compiler is invoked here.
"""
from pathlib import Path
import argparse, hashlib, re
ROOT=Path(__file__).resolve().parents[2]
PINS={'rtl/ppc_special.sv': {'before': '1d8c5e51a6ccfc4285b6855c56c7c1b56196766882431afb8b5a9a93b455aef5', 'after': 'dc1750ae0e67cdd50da76c3903a33ba2e77020f02059ebe7267e93d74c3b6ca0'}, 'rtl/ppc_core.sv': {'before': '8a717edfb0feea9cb3985613ea7e6ec79f8c7d0576e84b55bec3894ed979b8e4', 'after': '7d07b701c6c9ef7b372c6df3f021b03f520cbce4dfacafa22670ed2606efea47'}}
PACKAGE_SHA='d2f9ebdc165a880507bead0c791f3fdabffc38a2dcef7e98f0338882e61dc7b6'
OFFER_BLOCK="  // Form the offer only in states eligible for port 1.\n  always_comb begin\n    result_port1_offer_o = 1'b0;\n    if (state_q == S_EXEC)\n      result_port1_offer_o = (!timer_read && !tlbsync_held) &&\n        !result_o.fault && !uop_q.write_cr_fields && !uop_q.write_cr_bit && !uop_q.write_xer;\n    else if (state_q == S_TIMER_RESULT)\n      result_port1_offer_o = !result_o.fault && !uop_q.write_cr_fields &&\n        !uop_q.write_cr_bit && !uop_q.write_xer;\n  end\n"
PORT_DECL='  // Complete second-port offer.\n  output logic result_port1_offer_o,\n'
OLD_QUAL="""  assign result_port1_o = ((state_q == S_EXEC) || (state_q == S_TIMER_RESULT)) &&
    !result_o.fault && !uop_q.write_cr_fields && !uop_q.write_cr_bit && !uop_q.write_xer;"""
def sha(text):
    return hashlib.sha256(text.encode()).hexdigest()

def validate(special, core, candidate_pin=True):
    # Exact permitted new arm; otherwise stripping it would hide a mutation.
    assert special.count(OFFER_BLOCK)==1, 'modified state/offer clause'
    old=special.replace(PORT_DECL,'').replace(OFFER_BLOCK,'')
    assert sha(old)==PINS['rtl/ppc_special.sv']['before'], 'independent original writer/result delta'
    assert OLD_QUAL in old
    result_block=old[old.index("    result_o = '0;"):old.index('  // tw/twi TO bits')]
    assert result_block.count('result_valid_o =')==5
    assert result_block.index("result_o = '0;") < result_block.index("result_valid_o = 1'b0;") < result_block.index('if (state_q == S_EXEC)')
    assert 'result_port1_offer_o' not in result_block
    for clause in ("if (state_q == S_EXEC) begin\n      result_valid_o = !timer_read && !tlbsync_held;",
                   "end else if (state_q == S_MMU_RESULT) begin\n      result_valid_o = !cancel_i;",
                   "end else if (state_q == S_TIMER_RESULT) begin\n      result_valid_o = 1'b1;",
                   "end else if (state_q == S_MEM_RESULT) begin\n      result_valid_o = 1'b1;"):
        assert clause in old, 'old validity priority changed'
    original_core=core.replace('    .result_port1_offer_o(special_port1_offer),\n','')
    original_core=original_core.replace('  logic special_port1, special_port1_sel, special_port1_offer;', '  logic special_port1, special_port1_sel;')
    original_core=original_core.replace('  logic special_late;', '  logic special_port1_ok, special_late;')
    original_core=original_core.replace('    .result_select_o(special_result_select),\n    /* verilator lint_off PINCONNECTEMPTY */\n    .result_port1_o(),\n    /* verilator lint_on PINCONNECTEMPTY */', '    .result_select_o(special_result_select), .result_port1_o(special_port1_ok),')
    original_core=original_core.replace('  assign special_port1 = special_port1_sel && special_port1_offer;', '  assign special_port1 = special_port1_sel && special_result_valid && special_port1_ok;')
    assert sha(original_core)==PINS['rtl/ppc_core.sv']['before'], 'core selection/other delta'
    if candidate_pin:
        assert sha(special)==PINS['rtl/ppc_special.sv']['after']
        assert sha(core)==PINS['rtl/ppc_core.sv']['after']
    return old

def negatives(special,core):
    cases=[('independent valid writer',special.replace("result_valid_o = 1'b0;", "result_valid_o = 1'b1;",1),core),
           ('modified state clause',special.replace(OFFER_BLOCK,OFFER_BLOCK.replace('if (state_q == S_EXEC)','if (state_q == S_MMU_RESULT)',1)),core),
           ('changed core selection',special,core.replace('assign special_port1 = special_port1_sel && special_port1_offer;', 'assign special_port1 = !special_port1_sel && special_port1_offer;',1))]
    for name,sp,co in cases:
        assert (sp,co)!=(special,core), name
        try:
            validate(sp,co,candidate_pin=False)
        except AssertionError:
            continue
        raise AssertionError('source mutation escaped: '+name)

def fixture(old, special):
    old_qual=OLD_QUAL
    block=re.search(r'  // Form the offer only.*?\n  end\n', special, re.S).group(0)
    states=re.search(r'  typedef enum logic \[4:0\] \{.*?\n  \} state_t;',old,re.S).group(0)
    sv='''// SPDX-License-Identifier: GPL-2.0-or-later
    // Copyright (c) 2026 Kevin Dedon
    `default_nettype none
    module special_port1_projection(input logic[4:0] state_q,
     input logic timer_read,tlbsync_held,cancel_i,fault,wcr,wbit,wxer,sel,
     output logic old_offer,new_offer);
    '''+states+'''
     typedef struct packed { logic write_cr_fields,write_cr_bit,write_xer; } ctrl_t;
     typedef struct packed { logic fault; } packet_t;
     ctrl_t uop_q; packet_t result_o;
     assign uop_q={wcr,wbit,wxer}; assign result_o.fault=fault;
     logic result_valid_o,result_port1_o,result_port1_offer_o;
     // Frozen independent original procedural validity, not the new helper.
     always_comb begin
       result_valid_o=1'b0;
       if(state_q==S_EXEC) result_valid_o=!timer_read&&!tlbsync_held;
       else if(state_q==S_MMU_RESULT) result_valid_o=!cancel_i;
       else if(state_q==S_TIMER_RESULT) result_valid_o=1'b1;
       else if(state_q==S_MEM_RESULT) result_valid_o=1'b1;
     end
    '''+old_qual+'\n'+block+'''
     assign old_offer=sel&&result_valid_o&&result_port1_o;
     assign new_offer=sel&&result_port1_offer_o;
    endmodule
    module tb_special_port1_projection;
     logic[4:0] state; logic[6:0] c; logic sel,old_offer,new_offer;
     special_port1_projection dut(state,c[0],c[1],c[2],c[3],c[4],c[5],c[6],sel,old_offer,new_offer);
     integer checks=0,mmu=0,execs=0,timers=0,unknowns=0,xstate_fault0=0,invalids=0;
     function automatic logic q(input integer v);
       case(v) 0:q=0;1:q=1;2:q=1'bx;default:q=1'bz;endcase
     endfunction
     task automatic sample;
       #1;
       if(old_offer!==new_offer) $fatal(1,"port1 mismatch state=%b controls=%b sel=%b old=%b new=%b",state,c,sel,old_offer,new_offer);
       checks++;
       if(state===5'd18)mmu++;
       if(state===5'd1 && old_offer===1'b1)execs++;
       if(state===5'd14 && old_offer===1'b1)timers++;
       if($isunknown(state))unknowns++;
       if($isunknown(state)&&c[3]===1'b0)begin
         xstate_fault0++;
         if(old_offer!==1'b0||new_offer!==1'b0)$fatal(1,"unknown state default lost");
       end
       if(state===5'd30||state===5'd31)invalids++;
     endtask
     initial begin
       for(integer st=0;st<1024;st++)begin
         for(integer b=0;b<5;b++)state[b]=q((st>>(2*b))&3);
         for(integer v=0;v<128;v++)begin
           c=7'(v);
           for(integer s=0;s<4;s++)begin sel=q(s);sample();end
         end
       end
       for(integer st=0;st<7;st++)begin
         case(st)0:state=5'd0;1:state=5'd1;2:state=5'd6;3:state=5'd14;4:state=5'd18;5:state='x;default:state='z;endcase
         for(integer v=0;v<16384;v++)begin
           for(integer b=0;b<7;b++)c[b]=q((v>>(2*b))&3);
           for(integer s=0;s<4;s++)begin sel=q(s);sample();end
         end
       end
       if(checks!=983040||mmu==0||execs==0||timers==0||unknowns==0||xstate_fault0==0||invalids==0)$fatal(1,"coverage failed %0d %0d %0d %0d %0d",checks,mmu,execs,timers,unknowns);
       $display("PASS special port1 fourstate comparisons=%0d mmu=%0d exec_true=%0d timer_true=%0d unknownstate=%0d xstate_fault0=%0d invalid=%0d",checks,mmu,execs,timers,unknowns,xstate_fault0,invalids);
       $finish;
     end
    endmodule
    `default_nettype wire
    '''
    return sv

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    assert hashlib.sha256((ROOT/'rtl/ppc_pkg.sv').read_bytes()).hexdigest()==PACKAGE_SHA, 'package/type drift'
    special=(ROOT/'rtl/ppc_special.sv').read_text()
    core=(ROOT/'rtl/ppc_core.sv').read_text()
    actual_core=core
    if sha(core) != PINS['rtl/ppc_core.sv']['after']:
        from d1_special_port1_views import load_views, negative_guards
        views=load_views(ROOT)
        count=negative_guards(views)
        core=views['port1_core']
        assert special == views['actual_special']
        print('COMPOSITION SOURCE PASS actual=' + sha(actual_core) + ' P1-view=' + sha(core) +
              ' D1-view=' + sha(views['d1_core']) + ' source-negative-guards=' + str(count))
    old=validate(special,core)
    negatives(special,core)
    args.output.mkdir(parents=True,exist_ok=True)
    (args.output/'tb_special_port1_projection.sv').write_text(fixture(old,special))
    print('PASS special-port1 source guards and 3 negative source mutations; prepared 983040 four-state comparisons (HDL not run)')
if __name__=='__main__':
    main()
