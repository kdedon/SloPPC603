#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
# Finite four-state source composition; no sequential or physical claim.
from pathlib import Path
import argparse
import re, subprocess
root=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser()
parser.add_argument('--build-dir',type=Path,required=True)
args=parser.parse_args()
out=args.build_dir.resolve()
out.mkdir(parents=True,exist_ok=True)
def block(path, name):
 s=(root/path).read_text()
 body=s.split('// BEGIN '+name,1)[1].split('// END '+name,1)[0].split('\n',1)[1]
 # Icarus cannot mix continuous/procedural drivers on separate struct fields.
 # Flatten only output lvalues into width-identical field aliases.
 for field in ['use_lookup','source','page']:
  body=body.replace('data_page_projection_o.'+field,'projection_'+field)
 body=body.replace("assign data_page_projection_o = '0;","assign {projection_use_lookup,projection_source,projection_page} = '0;")
 return 'logic projection_use_lookup;logic[2:0] projection_source;wire[4:0][19:0] projection_page;\nassign data_page_projection_o={projection_use_lookup,projection_source,projection_page};\n'+body
lsu=block('rtl/ppc_lsu_pipe.sv','LSU DATA PAGE PROJECTION')
core=block('rtl/ppc_core.sv','CORE DATA PAGE PROJECTION')
pkg=(root/'rtl/ppc_pkg.sv').read_text()
end=pkg.index('} dtlb_projection_t;')+len('} dtlb_projection_t;')
typecode=pkg[pkg.rfind('typedef struct packed {',0,end):end]
s=(root/'rtl/ppc_lsu_pipe.sv').read_text()
for expected in ['assign base_sum0 = wake_early_value_i + p1_head.offset;', 'assign base_sum1 = wake1_early_value_i + p1_head.offset;', 'assign base_sum3 = wake3_early_value_i + p1_head.offset;', 'assign head_ea = (BASE_SNOOP && p1_head.base_wait && head_base0) ? base_sum0 :\n                       (BASE_SNOOP && p1_head.base_wait && head_base1) ? base_sum1 :\n                       (BASE_SNOOP && p1_head.base_wait && head_base3) ? base_sum3 :\n                       p1_head.ea;', 'assign p1_addr = {head_ea[31:3], head_ea[2] ^ p1_head.munge[2], 2\'b00};', 'assign req_addr_o = sq_offer ? sq_head.addr : p1_addr;']:
 if expected not in s: raise SystemExit('legacy LSU guard failed: '+expected)
if 'dmem_req_addr_o = lsu_req_sel ? lsu_req_addr : sp_req_addr;' not in (root/'rtl/ppc_core.sv').read_text(): raise SystemExit('legacy core guard failed')
preamble='`timescale 1ns/1ps\n'+typecode+'\ntypedef struct packed {logic[31:0] ea; logic base_wait;} p1_t;\ntypedef struct packed {logic[31:0] addr;} sq_t;\n'
code=preamble+'''module hint_lsu #(parameter bit BASE_SNOOP=1, ENABLE_DATA_PAGE_PROJECTION=1, P1_EA=0)(input p1_t p1_head, input sq_t sq_head,input logic[31:0] head_ea,base_sum0,base_sum1,base_sum3,input logic sq_offer,head_base0,head_base1,head_base3,output dtlb_projection_t data_page_projection_o);
'''+lsu+'''endmodule
module hint_core #(parameter bit ENABLE_DATA_PAGE_PROJECTION=1)(input logic lsu_req_sel,input dtlb_projection_t lsu_page_projection,input logic[31:0] sp_req_addr,output dtlb_projection_t data_page_projection_o);
'''+core+'''endmodule
module proof #(parameter bit BASE_SNOOP=1,ENABLE=1)(output logic done);
 p1_t p1_head; sq_t sq_head;
 logic sq_offer,head_base0,head_base1,head_base3,lsu_req_sel;
 logic[31:0] head_ea,base_sum0,base_sum1,base_sum3,sp_req_addr,old_head,old_lsu,old_core;
 assign head_ea='0;
 logic[19:0] selected; logic expected_use; logic[2:0] expected_source;
 dtlb_projection_t lsu_page_projection,projected;
 integer samples,active,fallback,known_controls;
 hint_lsu #(.BASE_SNOOP(BASE_SNOOP),.ENABLE_DATA_PAGE_PROJECTION(ENABLE)) lsu(.*,.data_page_projection_o(lsu_page_projection));
 hint_core #(.ENABLE_DATA_PAGE_PROJECTION(ENABLE)) core(.*,.data_page_projection_o(projected));
 function automatic logic digit(input integer v);
  case(v) 0:digit=0;1:digit=1;2:digit=1'bx;default:digit=1'bz;endcase
 endfunction
 initial begin
  done=0;samples=0;active=0;fallback=0;known_controls=0;
  for(integer c=0;c<4096;c=c+1) begin
   sq_offer=digit(c%4);head_base0=digit((c/4)%4);head_base1=digit((c/16)%4);
   p1_head.base_wait=digit((c/64)%4);lsu_req_sel=digit((c/256)%4);head_base3=digit((c/1024)%4);
   for(integer d=0;d<32;d=d+1) begin
    p1_head.ea=32'h12345ffc;base_sum0=32'h23456000;base_sum1=32'h34567004;base_sum3=32'h6789a00c;sq_head.addr=32'h45678ffc;sp_req_addr=32'h56789008;
    case(d%8)
     1:base_sum0=32'h12345ffc;
     2:base_sum1=32'h23456000;
     3:sp_req_addr=32'h45678ffc;
     4:p1_head.ea[20]=1'bx;
     5:base_sum0[19]=1'bz;
     6:base_sum1[18]=1'bx;
     7:sq_head.addr[17]=1'bz;
     default:begin end
    endcase
    if(d>=8 && d<16) begin p1_head.ea=32'hfffffffc;base_sum0=32'b0; end
    if(d>=16 && d<24) sp_req_addr[31]=1'bx;
    if(d>=24) begin base_sum0[31]=1'bz;base_sum1[31]=1'bx;end
    old_head=(BASE_SNOOP && p1_head.base_wait && head_base0)?base_sum0:(BASE_SNOOP && p1_head.base_wait && head_base1)?base_sum1:(BASE_SNOOP && p1_head.base_wait && head_base3)?base_sum3:p1_head.ea;
    old_lsu=sq_offer?sq_head.addr:{old_head[31:3],old_head[2] ^ 1'b1,2'b00};
    old_core=lsu_req_sel?old_lsu:sp_req_addr;
    expected_use=0;expected_source=0;
    if(ENABLE) begin
     if(lsu_req_sel===1'b0) expected_use=1;
     else if(lsu_req_sel===1'b1) begin
      if(sq_offer===1'b1) begin expected_use=1;expected_source=3;end
      else if(sq_offer===1'b0) begin
       if((BASE_SNOOP && p1_head.base_wait && head_base0)===1'b1) begin expected_use=1;expected_source=1;end
       else if((BASE_SNOOP && p1_head.base_wait && head_base0)===1'b0) begin
        if((BASE_SNOOP && p1_head.base_wait && head_base1)===1'b1) begin expected_use=1;expected_source=2;end
        else if((BASE_SNOOP && p1_head.base_wait && head_base1)===1'b0) begin
         if((BASE_SNOOP && p1_head.base_wait && head_base3)===1'b1) begin expected_use=1;expected_source=4;end
         else if((BASE_SNOOP && p1_head.base_wait && head_base3)===1'b0) expected_use=1;
        end
       end
      end
     end
    end
    #1;
    if(projected.use_lookup !== expected_use || projected.source !== expected_source) $fatal(1,"selector mismatch BASE=%0d ENABLE=%0d c=%0d d=%0d",BASE_SNOOP,ENABLE,c,d);
    selected=old_core[31:12];
    if(projected.use_lookup) begin
     case(projected.source) 0:selected=projected.page[0];1:selected=projected.page[1];2:selected=projected.page[2];3:selected=projected.page[3];4:selected=projected.page[4];default:$fatal(1,"unknown active source");endcase
     active=active+1;
    end else fallback=fallback+1;
    if(selected !== old_core[31:12]) $fatal(1,"page mismatch BASE=%0d ENABLE=%0d c=%0d d=%0d",BASE_SNOOP,ENABLE,c,d);
    if(!ENABLE && projected !== '0) $fatal(1,"disabled hints nonzero");
    if(c%4<2 && (c/4)%4<2 && (c/16)%4<2 && (c/64)%4<2 && (c/256)%4<2 && (c/1024)%4<2) begin
     known_controls=known_controls+1;
     if(ENABLE && !projected.use_lookup) $fatal(1,"known control kept legacy bank");
    end
    samples=samples+1;
   end
  end
  if(samples!=131072 || known_controls!=2048 || (ENABLE && (active==0 || fallback==0))) $fatal(1,"coverage missing");
  $display("PASS D-uTLB source composition BASE=%0d ENABLE=%0d samples=%0d active=%0d fallback=%0d knownControls=%0d",BASE_SNOOP,ENABLE,samples,active,fallback,known_controls);done=1;
 end
endmodule
module tb; wire[3:0] done;
 proof #(.BASE_SNOOP(0),.ENABLE(0)) a(done[0]);proof #(.BASE_SNOOP(1),.ENABLE(0)) b(done[1]);
 proof #(.BASE_SNOOP(0),.ENABLE(1)) c(done[2]);proof #(.BASE_SNOOP(1),.ENABLE(1)) d(done[3]);
 initial begin wait(&done);$finish;end
endmodule
'''
path=out/'composition.sv';path.write_text(code)
subprocess.run(['iverilog','-g2012','-s','tb','-o',str(out/'composition.vvp'),str(path)],check=True,stdout=subprocess.DEVNULL)
subprocess.run(['timeout','15s','vvp',str(out/'composition.vvp')],check=True)
(out/'composition.vvp').unlink()
