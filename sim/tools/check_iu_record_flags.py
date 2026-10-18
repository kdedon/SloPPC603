#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Optional standalone IU record-flag source proof; no historical views or Git."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess
sha=lambda s:hashlib.sha256(s.encode()).hexdigest()
DATA_SHA256='04e35477023499f88de9c2f166014605bfe43312ce88e320340d699f149a4364'
_data=Path(__file__).with_name('iu_record_flags.json').read_text()
assert sha(_data)==DATA_SHA256,'IU flag reference/metadata drift'
PINS=json.loads(_data)
EDITS=[(''.join(e['before_lines']),''.join(e['after_lines']))for e in PINS['edits']]
DRIVER=''.join(PINS['driver_lines'])

def assign(s,name):
 found=re.findall(r'  assign '+re.escape(name)+r'\s*=.*?;',s,re.S);assert len(found)==1,name;return found[0]+'\n'
def record_case(s):
 start=s.index('      always_comb begin\n        case (held.ctrl.op)')
 return s[start:s.index('        endcase\n      end',start)+len('        endcase\n      end')]
def inverse(source,pin=True):
 actual=source
 if pin:assert sha(actual)==PINS['after'],'unknown actual IU source'
 for before,after in reversed(EDITS):
  assert source.count(after)==1,'IU inverse fragment changed'
  source=source.replace(after,before)
 assert sha(source)==PINS['before'],'unrelated actual IU delta'
 return source

def clocked_blocks(source):
 masked=re.sub(r'//[^\n]*|/\*[\s\S]*?\*/',lambda m:' '*len(m[0]),source)
 blocks=[]
 for m in re.finditer(r'\balways_ff\s*@\([^\n]*\)\s*begin\b',masked):
  depth=1;end=None
  for t in re.finditer(r'\b(begin|end)\b',masked[m.end():]):
   depth+=1 if t[0]=='begin'else-1
   if depth==0:end=m.end()+t.end();break
  assert end is not None,'unbalanced clocked block'
  blocks.append(source[m.start():end])
 assert len(blocks)==6,len(blocks)
 return blocks

def validate(source,pkg):
 assert sha(pkg)==PINS['package'],'actual package/type drift'
 old=inverse(source)
 # Actual full-source inverse includes every clocked/arithmetic/handshake bit;
 # explicitly retain the consumed-output and held-state authorities as well.
 for name in ['held_compare','compare_eq','compare_gt','result_value','result_o.value','issue_ready_o','result_offer_o','result_valid_o']:
  assert assign(source,name)==assign(old,name),name
 assert clocked_blocks(source)==clocked_blocks(old),'held/arithmetic state drift'
 assert record_case(old).count('record_value =')==24
 assert record_case(source).count('record_flags = flags_from_record(')==24
 assert len(re.findall(r'\brecord_value\s*=',source))==1,'full-profile record temporary restored'
 assert source.count("return {value[31], !value[31] && (value != 0), value == 0};")==1
 assert 'predict_result_ready_i'not in source and 'predict_issue_ready_o'not in source,'NoRec interface leakage'
 return old

def negative_guards(source,pkg):
 mutants=[('CR bit ordering','record_flags[2],','record_flags[1],'),
  ('consumed numerical output','alu_value = add_sum[31:0];','alu_value = add_sum[30:0];'),
  ('held acceptance','if (issue_valid_i && issue_ready_o) held <= issue_i;','if (issue_valid_i) held <= issue_i;'),
  ('helper sign','return {value[31],','return {value[30],'),
  ('unknown opcode default',"record_flags = flags_from_record('0);","record_flags = 3'b000;")]
 for label,a,b in mutants:
  assert a in source,label;changed=source.replace(a,b,1)
  try:inverse(changed,pin=False)
  except AssertionError:pass
  else:raise AssertionError('source mutation survived: '+label)
 try:validate(source,pkg+'\n')
 except AssertionError:pass
 else:raise AssertionError('package identity mutation survived')
 return len(mutants)+1

def fixture(old,new,pkg):
 def typedef(name):
  x=re.findall(r'typedef\s+(?:struct\s+packed\s*\{[^}]*\}|enum\s+logic\s*\[[^]]+\]\s*\{[^}]*\}|logic\s*\[[^]]+\])\s*'+name+r'\s*;',pkg);assert len(x)==1;return x[0]+'\n'
 types='package cut_types;\n'
 for n in ['CQ_DEPTH','CQ_INDEX_WIDTH','CQ_GENERATION_WIDTH']:
  x=re.findall(r'localparam int '+n+r'\s*=[^;]+;',pkg);assert len(x)==1;types+=x[0]+'\n'
 for n in ['completion_tag_t','alu_op_t','carry_in_t','iu_ctrl_t','issue_packet_t']:types+=typedef(n)
 types+='endpackage\n'
 def assign(s,n):
  x=re.findall(r'  assign '+re.escape(n)+r'\s*=.*?;',s,re.S);assert len(x)==1,n;return x[0]+'\n'
 def module(name,s,candidate):
  start=s.index('      always_comb begin\n        case (held.ctrl.op)');end=s.index('        endcase\n      end',start)+len('        endcase\n      end');case=s[start:end]
  case=re.sub(r'            alu_value = .*?;\n','',case,flags=re.S)
  assert 'alu_value' not in case
  assert case.count('record_value =')==(0 if candidate else 24)
  if candidate:case+='\nassign record_value=32\'b0;\n'
  helper=re.search(r'  function automatic logic \[2:0\] flags_from_record.*?  endfunction',s,re.S).group(0) if candidate else ''
  add="assign record_value = held_compare ? 32'b0 : add_sum[31:0];\n"
  if candidate:add+='assign record_flags = flags_from_record(record_value);\n'
  return f'''module {name} #(parameter bit ADD_COMPARE_ONLY=0)(
 input cut_types::issue_packet_t held,input logic[32:0] add_sum,
 input logic add_overflow,final_so,input logic[63:0] multiply_acc,
 input logic[31:0] divider_quotient,input logic[5:0] leading_zeros,
 input logic record_a_sign,record_a_nonzero,record_b_sign,record_b_nonzero,
 output logic[31:0] record_value,output logic[3:0] cr0);
 import cut_types::*;
 typedef struct packed {{logic[3:0] cr0;}} result_t;
 result_t result_o;
 logic held_compare,compare_eq,compare_gt;
 logic[2:0] record_flags;
 {helper}
 {assign(s,'held_compare')}{assign(s,'compare_eq')}{assign(s,'compare_gt')}{assign(s,'result_o.cr0')}
 assign cr0=result_o.cr0;
 generate if(ADD_COMPARE_ONLY)begin:g_add
 {add}
 end else begin:g_full
 {case}
 end endgenerate
 endmodule\n'''
 return '// SPDX-License-Identifier: GPL-2.0-or-later\n// Copyright (c) 2026 Kevin Dedon\n`timescale 1ns/1ps\n'+types+module('record_old',old,False)+module('record_new',new,True)+DRIVER

def main():
 ap=argparse.ArgumentParser(description=__doc__)
 ap.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[2]);ap.add_argument('--output',type=Path,required=True)
 ap.add_argument('--prepare-only',action='store_true');ap.add_argument('--iverilog',default='iverilog');ap.add_argument('--vvp',default='vvp')
 args=ap.parse_args();actual=(args.root/'rtl/ppc_iu.sv').read_text();pkg=(args.root/'rtl/ppc_pkg.sv').read_text()
 old=validate(actual,pkg);negatives=negative_guards(actual,pkg);sv=fixture(old,actual,pkg)
 args.output.mkdir(parents=True,exist_ok=True);path=args.output/'tb_record_flags.sv';path.write_text(sv)
 receipt={'actual_IU':sha(actual),'inverse':sha(old),'package':sha(pkg),'fixture':sha(sv),'source_negatives':negatives,'expected_CR_comparisons':524288,'expected_ADD_temporary_comparisons':262144,'status':'PREPARED; installed runtime pending','scope':'Finite combinational selector/type cut; no temporal/numerical/full-core/Fmax claim'}
 (args.output/'source.json').write_text(json.dumps(receipt,indent=2)+'\n')
 if args.prepare_only:print('PREPARED',receipt['fixture'],'source negatives',negatives);return
 exe=args.output/'proof.vvp'
 try:
  with(args.output/'compile.log').open('w')as log:subprocess.run([args.iverilog,'-g2012','-s','tb_record_flags','-o',str(exe),str(path)],stdout=log,stderr=subprocess.STDOUT,timeout=30,check=True)
  with(args.output/'run.log').open('w')as log:subprocess.run([args.vvp,str(exe)],stdout=log,stderr=subprocess.STDOUT,timeout=90,check=True)
  log=(args.output/'run.log').read_text();assert 'PASS record flags comparisons=524288 unknownOp=253952 invalidOp=1792 unknownWrite=131072'in log
  receipt['status']='PASS bounded installed selector proof';(args.output/'source.json').write_text(json.dumps(receipt,indent=2)+'\n');print(log,end='')
 finally:
  exe.unlink(missing_ok=True);assert (args.root/'rtl/ppc_iu.sv').read_text()==actual;assert (args.root/'rtl/ppc_pkg.sv').read_text()==pkg
if __name__=='__main__':main()
