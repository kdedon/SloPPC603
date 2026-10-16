#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Guard live abort repair; generate a bounded, bitwise four-state control gate.

No HDL tool is invoked. One-bit payload projection composes over 2/4 ways:
all payload operators are bitwise and the shared abort selector is one bit.
The actual public cache regression separately tests RAM/state behavior.
"""
from pathlib import Path
import argparse,hashlib,json,re
ROOT=Path(__file__).resolve().parents[2]
def sha(s):return hashlib.sha256(s.encode()).hexdigest()
ORIGINAL='db33e1e3926f257525a2032927b8b0b286626e5de1fa37e05c3d59d237bd847f'
CANDIDATE='5479704991cc547b01337fbe25446c7c5b216e718b01c1cbbc216892ade174c3'
TESTBENCH='f5a647e64dc79c7fe569b5d29d7d1a9dd5867fcc9fd8e646debb21f01ab392c8'
OLD_DECL='  logic [WAY_COUNT-1:0] way_valid_rdata, way_valid_wdata, victim_onehot;'
NEW_DECL='  logic [WAY_COUNT-1:0] way_valid_rdata, way_valid_wdata, victim_onehot;\n  logic abort_install, way_valid_we;'
OLD_DATA='  assign way_valid_wdata = miss_valid_q | victim_onehot;'
NEW_CONTROL="  // Half0 already overwrote the chosen way on the preceding good reply.\n  // A kill before half1/tag publication must make that victim unobservable.\n  // Only known abort controls add a write; X/Z kill retains the old enable.\n  always_comb begin\n    abort_install = 1'b0;\n    case ({rst_ni, invalidate_i, kill_i, state_q == IC_INSTALL})\n      4'b1011: abort_install = 1'b1;\n      default: begin end\n    endcase\n  end\n  assign way_valid_we = (install_ok && state_q == IC_INSTALL) || abort_install;\n  assign way_valid_wdata = abort_install ? (miss_valid_q & ~victim_onehot) :\n                                         (miss_valid_q | victim_onehot);"
OLD_PORT='.clk_i, .we_i(install_ok && state_q == IC_INSTALL), .waddr_i(miss_set_q),'
NEW_PORT='.clk_i, .we_i(way_valid_we), .waddr_i(miss_set_q),'
def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--output',type=Path,required=True)
 args=parser.parse_args()
 actual=(ROOT/'rtl/ppc_icache.sv').read_text()
 assert sha(actual)==CANDIDATE,'live cache is not reviewed abort candidate'
 original=actual
 for new,old in [(NEW_DECL,OLD_DECL),(NEW_CONTROL,OLD_DATA),(NEW_PORT,OLD_PORT)]:
  assert original.count(new)==1,new
  original=original.replace(new,old)
 assert sha(original)==ORIGINAL,'inverse delta changed other cache behavior'
 assert sha((ROOT/'tb/tb_icache_abort_install.sv').read_text())==TESTBENCH,'public oracle drift'
 # Exact actual expressions, not substituted hand-written candidate logic.
 install=re.search(r'  assign install_ok = .*?;',actual,re.S).group()
 assert install=="  assign install_ok = rst_ni && !kill_i && !invalidate_i;"
 control=NEW_CONTROL.replace('state_q == IC_INSTALL','state_install')
 fixture=HEADER+install+'\n'+control+BODY
 args.output.mkdir(parents=True,exist_ok=True)
 (args.output/'tb_icache_abort_control.sv').write_text(fixture)
 (args.output/'source.json').write_text(json.dumps({'candidate':CANDIDATE,'inverse_original':ORIGINAL,'public_testbench':TESTBENCH,'scope':'4096 four-state cases; per-bit payload projection; not RAM/temporal/ISA proof'},indent=2)+'\n')
 print('Prepared actual-source abort control fixture; no HDL execution')
HEADER="""// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
module tb_icache_abort_control;
 logic rst_ni,invalidate_i,kill_i,state_install;
 logic [0:0] miss_valid_q,victim_onehot,way_valid_wdata;
 logic install_ok,abort_install,way_valid_we;
 logic old_we,old_data;
 // Independent frozen original expressions, including original RAM enable.
 assign old_we=(rst_ni && !kill_i && !invalidate_i) && state_install;
 assign old_data=miss_valid_q | victim_onehot;
"""
BODY="""
 function automatic logic f(input integer v);
 case(v%4)0:return 1'b0;1:return 1'b1;2:return 1'bx;default:return 1'bz;endcase
 endfunction
 integer vectors,abort_cases,kill_zero,kill_xz;
 initial begin
 vectors=0;abort_cases=0;kill_zero=0;kill_xz=0;
 for(integer c=0;c<256;c++)begin
 rst_ni=f(c);invalidate_i=f(c/4);kill_i=f(c/16);state_install=f(c/64);
 for(integer m=0;m<16;m++)begin
 miss_valid_q=f(m);victim_onehot=f(m/4);#1;
 if({rst_ni,invalidate_i,kill_i,state_install}===4'b1011)begin
   if(abort_install!==1'b1||way_valid_we!==1'b1||
      way_valid_wdata!==(miss_valid_q & ~victim_onehot))$fatal(1,"known abort mismatch c=%0d m=%0d",c,m);
   abort_cases++;
 end else begin
   if(abort_install!==1'b0||way_valid_we!==old_we||way_valid_wdata!==old_data)
     $fatal(1,"legacy control/payload changed c=%0d m=%0d",c,m);
   if((way_valid_we===1'b1)!=(old_we===1'b1))$fatal(1,"procedural write decision changed");
 end
 if(kill_i===1'b0)kill_zero++;
 if(kill_i===1'bx||kill_i===1'bz)kill_xz++;
 vectors++;
 end end
 if(vectors!=4096||abort_cases!=16||kill_zero!=1024||kill_xz!=2048)$fatal(1,"control coverage");
 $display("PASS abort control4096 cases known_abort16 kill0=1024 killXZ=2048 (bitwise payload scope)");
 $finish;
 end
endmodule
`default_nettype wire
"""
if __name__=='__main__':main()
