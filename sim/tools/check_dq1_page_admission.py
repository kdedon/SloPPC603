#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Guard live DQ1 candidate and prepare a frozen independent reference.

Generation only: optional Icarus execution is a separate Make target.
Source drift must be reviewed/re-pinned, never accepted automatically.
"""
from pathlib import Path
import argparse,hashlib,re,json
ROOT=Path(__file__).resolve().parents[2]
def sha(s):return hashlib.sha256(s.encode()).hexdigest()
CANDIDATE='16bd8e8a2e8dc00729ee96fae721a07c2710d6c2f7319dd735592666d81d2af3'
ORIGINAL='0be6dda92c4395c5b6f5890a4c14dba72fad21ce1c90a5580712c74f718ad42c'
PACKAGE='64897d2f8bff3dbc6e0247f6b89d773eb80627bedfe6397173870a81964d58ee'
TB='34fc9995ebe0e980c9c96c7b8a10485dad51cf40cb33ae5ac0a762d53cb6c255'
HELPER="  // Select the scalar admission predicate after evaluating each B source.\n  // Unknown selectors retain the original bitwise-merged operand semantics.\n  function automatic logic page_end_b_choice(input logic [11:0] a,\n                                              input logic [11:0] reg_b,\n                                              input logic [11:0] imm_b,\n                                              input logic use_imm,\n                                              input logic word);\n    case (use_imm)\n      1'b0: return page_end(a, reg_b, word);\n      1'b1: return page_end(a, imm_b, word);\n      default: return page_end(a, use_imm ? imm_b : reg_b, word);\n    endcase\n  endfunction\n"
OLD_CALL='     page_end(d1_a[11:0], d1_b[11:0], dq1_uop.mem_size == MEM_WORD));'
NEW_CALL='     page_end_b_choice(d1_a[11:0], ENABLE_LSU_PIPE ? src_b1.value[11:0] : arch_b1[11:0],\n                       dq1_uop.imm[11:0], dq1_uop.use_imm, dq1_uop.mem_size == MEM_WORD));'
FROZEN_REFERENCE="  function automatic logic sum12_is(input logic [11:0] a, input logic [11:0] b,\n                                    input logic [11:0] k);\n    return (a ^ b ^ k) == {(a[10:0] & b[10:0]) | ((a[10:0] | b[10:0]) & ~k[10:0]), 1'b0};\n  endfunction\n  // An EA in the last bytes of a page: the last byte, or for a word any of\n  // the last three.\n  function automatic logic page_end(input logic [11:0] a, input logic [11:0] b,\n                                    input logic word);\n    return sum12_is(a, b, 12'hfff) ||\n           (word && (sum12_is(a, b, 12'hffe) || sum12_is(a, b, 12'hffd)));\n  endfunction\n\n  assign d1_a = dq1_uop.zero_a ? 32'b0 : ENABLE_LSU_PIPE ? src_a1.value : arch_a1;\n  assign d1_b = dq1_uop.use_imm ? dq1_uop.imm : ENABLE_LSU_PIPE ? src_b1.value : arch_b1;\n  assign d1_ea = d1_a[1:0] + d1_b[1:0];\n  assign d1_ea_full = d1_a + d1_b;\n  assign d1_misaligned = !ENABLE_MISALIGNED_ACCESS ?\n    (((dq1_uop.mem_size == MEM_WORD) && (d1_ea[1:0] != 2'b00)) ||\n     ((dq1_uop.mem_size == MEM_HALF) && d1_ea[0])) :\n    ((dq1_uop.mem_size != MEM_BYTE) && msr[MSR_DR] &&\n     page_end(d1_a[11:0], d1_b[11:0], dq1_uop.mem_size == MEM_WORD));\n  assign d1_mem_ready = !special_busy && !sru_hold_q && lsu_empty && !fp_unsafe_pending && !d1_misaligned &&\n    !msr_le &&\n    (dq1_uop.zero_a || (!gpr_mapped[dq1_uop.src_a] && !dq1_pair.dep_prev[0])) &&\n    (dq1_uop.use_imm || (!gpr_mapped[dq1_uop.src_b] && !dq1_pair.dep_prev[1])) &&\n    ((dq1_uop.special_op != SPECIAL_STORE) ||\n     (!gpr_mapped[dq1_uop.src_c] && !dq1_pair.dep_prev[2]));\n  assign d1_wait_a = !dq1_uop.zero_a && (dq1_pair.dep_prev[0] || !src_a1.ready);\n  assign d1_wait_b = !dq1_uop.use_imm && (dq1_pair.dep_prev[1] || !src_b1.ready);\n  assign d1_base_wait = (LSU_BASE_SNOOP || LSU_BASE_WAIT) && ENABLE_SUPERVISOR_EXCEPTIONS &&\n    ((dq1_uop.special_op == SPECIAL_LOAD) || (dq1_uop.special_op == SPECIAL_STORE)) &&\n    !dq1_uop.mem_update && (d1_wait_a != d1_wait_b) &&\n    (!(dq1_pair.dep_prev[0] || dq1_pair.dep_prev[1]) ||\n     (dispatch_uop.gpr_write && !dispatch_uop.mem_update));\n  assign d1_lsu_ready = lsu_ready && lane_mem_idle && !fp_unsafe_pending &&\n    (d1_base_wait || !d1_misaligned) && !msr_le &&\n    (d1_base_wait || ((dq1_uop.zero_a || (src_a1.ready && !dq1_pair.dep_prev[0])) &&\n                      (dq1_uop.use_imm || (src_b1.ready && !dq1_pair.dep_prev[1]))));"
def assigns(s,names):
 return '\n'.join(re.search(r'  assign '+re.escape(n)+r' = .*?;',s,re.S).group() for n in names)
names=['d1_a','d1_b','d1_ea','d1_ea_full','d1_misaligned','d1_mem_ready','d1_wait_a','d1_wait_b','d1_base_wait','d1_lsu_ready']
def logic(s):
 funcs=s[s.index('  function automatic logic sum12_is'):s.index('  assign special_a =')]
 return funcs+'\n'+assigns(s,names)
fields={'dq1_uop.zero_a':'za','dq1_uop.use_imm':'im','dq1_uop.imm':'imm','dq1_uop.mem_size':'size','dq1_uop.special_op':'sop','dq1_uop.mem_update':'upd','dq1_uop.src_a':'ra','dq1_uop.src_b':'rb','dq1_uop.src_c':'rc','dq1_pair.dep_prev':'dep','src_a1.value':'av','src_b1.value':'bv','src_a1.ready':'ar','src_b1.ready':'br','dispatch_uop.gpr_write':'gw','dispatch_uop.mem_update':'gu','msr[MSR_DR]':'dr'}
ports='''input logic [31:0] av,bv,arch_a1,arch_b1,imm,gpr_mapped,
 input logic [4:0] ra,rb,rc,input logic[2:0]dep,
 input logic[1:0]size,input logic[5:0]sop,
 input logic za,im,dr,ar,br,upd,gw,gu,special_busy,sru_hold_q,lsu_empty,
 fp_unsafe_pending,msr_le,lsu_ready,lane_mem_idle,
 output logic[103:0] result'''
def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--output',type=Path,required=True)
 args=parser.parse_args()
 actual=(ROOT/'rtl/ppc_core.sv').read_text()
 assert sha(actual)==CANDIDATE,'live core is not the reviewed candidate'
 assert actual.count(HELPER)==1 and actual.count(NEW_CALL)==1
 baseline=actual.replace(HELPER,'').replace(NEW_CALL,OLD_CALL)
 assert sha(baseline)==ORIGINAL,'inverse delta changed other core behavior'
 assert logic(baseline)==FROZEN_REFERENCE,'frozen original reference mismatch'
 pkg=(ROOT/'rtl/ppc_pkg.sv').read_text()
 assert sha(pkg)==PACKAGE,'package changed: inspect field/enum widths'
 tb=(ROOT/'tb/tb_dq1_page_admission_proof.sv').read_text()
 assert sha(tb)==TB,'proof corpus/mandatory bins changed'
 # Only enum types used by the reduced actual expression fixture.
 enums='\n'.join(re.search(r'  typedef enum logic \['+w+r'\] \{[^}]*\} '+t+';',pkg,re.S).group() for w,t in [('1:0','mem_size_t'),('5:0','special_op_t')])
 mods=[]
 for tag,raw in [('old',FROZEN_REFERENCE),('new',logic(actual))]:
  body=raw
  for a,b in fields.items():body=body.replace(a,b)
  mods.append(f"""module dq1_{tag} #(parameter ENABLE_LSU_PIPE=1, ENABLE_MISALIGNED_ACCESS=1, LSU_BASE_SNOOP=1)( {ports} );
 localparam LSU_BASE_WAIT=0,ENABLE_SUPERVISOR_EXCEPTIONS=1;
 {enums}
 logic[31:0]d1_a,d1_b,d1_ea_full; logic[1:0]d1_ea;
 logic d1_misaligned,d1_mem_ready,d1_lsu_ready,d1_wait_a,d1_wait_b,d1_base_wait;
 {body}
 assign result={{d1_a,d1_b,d1_ea_full,d1_ea,d1_misaligned,d1_mem_ready,d1_lsu_ready,d1_base_wait,d1_wait_a,d1_wait_b}};
endmodule
""")
 args.output.mkdir(parents=True,exist_ok=True)
 generated='// SPDX-License-Identifier: GPL-2.0-or-later\n// Copyright (c) 2026 Kevin Dedon\n`default_nettype none\n'+'\n'.join(mods)+'`default_nettype wire\n'
 (args.output/'dq1_page_predicates.sv').write_text(generated)
 (args.output/'source.json').write_text(json.dumps({'candidate':CANDIDATE,'inverse_original':ORIGINAL,'package':PACKAGE,'testbench':TB,'frozen_reference':sha(FROZEN_REFERENCE),'actual_expression':sha(logic(actual)),'scope':'65536 finite four-state samples x8 profiles, BASE_WAIT0/supervisor1; generation is not HDL acceptance'},indent=2)+'\n')
 print('Prepared guarded actual DQ1 predicate and frozen original; no HDL execution')
if __name__=='__main__':main()
