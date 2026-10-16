#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Optional bounded four-state raw-owner projection proof (Icarus).

Strictly pinned actual-source expressions versus a fixed independent legacy
reader. Factored combinational coverage, not temporal ownership/recovery or
whole-core ISA/timing acceptance. Default-on core, default-off standalone rename.
"""
from pathlib import Path
import argparse, hashlib, re, subprocess
EXPECTED_HASHES = {'ppc_core.sv': '7cbed49780ec8aed425670c6f5fa8974674169ea4479bb5fae468bf11796bd77', 'ppc_rename.sv': 'c22f2a20e365a713943ce178d19431aac4fe4b4ff142f81a3c505eff602c65f9', 'ppc_completion.sv': 'eb0e1aa902394340b1e5c1501629a27c0dc167474c48d1380a32505b23d2c2a5', 'ppc_pkg.sv': '64897d2f8bff3dbc6e0247f6b89d773eb80627bedfe6397173870a81964d58ee'}
ORIGINAL_FUNCTION = "  function automatic operand_t read_operand(input logic [4:0] reg_index,\n                                             input logic [31:0] arch_value,\n                                             input logic [31:0] wake_value,\n                                             input logic [31:0] wake1_value);\n    operand_t operand;\n    operand = '0;\n    operand.ready = 1'b1;\n    operand.value = arch_value;\n    if (map_valid[reg_index]) begin\n      operand.tag = map_tag[reg_index];\n      operand.producer = owners[operand.tag];\n      operand.ready = ready[operand.tag];\n      // Pending payload is not consumed.\n      operand.value = ready[operand.tag] ? values[operand.tag] : 32'b0;\n      // The value forwards on the producer alone, keeping recovery's kill\n      // and the wake's tag lookup out of the dispatch operand cone. It is\n      // consumed only with ready, which needs a valid wake of this tag on\n      // the same bus or a second-port wake, which takes precedence; a killed\n      // wake also kills the reader.\n      if (!ready[operand.tag] && wake_owns[operand.tag])\n        operand.value = wake_value;\n      // A late wake is not forwarded; the reader takes it from the bus.\n      if (wake_match && !wake_i.late && wake_i.tag == operand.tag)\n        operand.ready = 1'b1;\n      if (!ready[operand.tag] && wake1_offer_i && wake1_i.tag == operand.tag &&\n          wake1_owns[operand.tag])\n        operand.value = wake1_value;\n      if (wake1_match && !wake1_i.late && wake1_i.tag == operand.tag)\n        operand.ready = 1'b1;\n    end\n    return operand;\n  endfunction"
ORIGINAL_COMPUTE = "  assign wake_match = wake_valid_i && int'(wake_i.tag) < GPR_RENAME_DEPTH &&\n                      valid[wake_i.tag] && owners[wake_i.tag] == wake_i.producer;\n  assign wake1_match = wake1_valid_i && int'(wake1_i.tag) < GPR_RENAME_DEPTH &&\n                       valid[wake1_i.tag] && owners[wake1_i.tag] == wake1_i.producer;\n  \n    for (int i = 0; i < GPR_RENAME_DEPTH; i++) begin\n      wake_owns[i] = owners[i] == wake_i.producer;\n      wake1_owns[i] = owners[i] == wake1_i.producer;\n    end"
ORIGINAL_CALLERS = {'read_a_o': 'read_a_i, arch_a_i, wake_i.value, wake1_i.value', 'read_b_o': 'read_b_i, arch_b_i, wake_i.value, wake1_i.value', 'read_c_o': 'read_c_i, arch_c_i, wake_i.value, wake1_i.value', 'read_a1_o': 'read_a1_i, arch_a1_i, wake_i.value, wake1_i.value', 'read_b1_o': 'read_b1_i, arch_b1_i, wake_i.value, wake1_i.value', 'read_c1_o': 'read_c1_i, arch_c1_i, wake_i.value, wake1_i.value', 'early_a': 'read_a_i, arch_a_i, wake_early_value_i, wake1_early_value_i', 'early_b': 'read_b_i, arch_b_i, wake_early_value_i, wake1_early_value_i'}
ORIGINAL_TYPES = {'completion_tag_t': 'typedef struct packed {\n    logic [CQ_INDEX_WIDTH-1:0] index;\n    logic [CQ_GENERATION_WIDTH-1:0] generation;\n  } completion_tag_t;', 'operand_t': 'typedef struct packed {\n    logic ready;\n    logic [31:0] value;\n    rename_tag_t tag;\n    completion_tag_t producer;\n  } operand_t;', 'wake_packet_t': 'typedef struct packed {\n    completion_tag_t producer;\n    rename_tag_t tag;\n    logic [31:0] value;\n    // A completion-serialized result, written before its producer retires\n    // but forwarded only after (UM 6.3.3.2): readers use it a cycle later.\n    logic late;\n  } wake_packet_t;', 'page_miss_t': 'typedef struct packed {\n    logic [31:0] ea;\n    logic [31:0] sr;\n    logic pr;\n    logic ir;\n    logic dr;\n    logic write;\n    logic way;\n  } page_miss_t;', 'result_packet_t': 'typedef struct packed {\n    completion_tag_t producer;\n    logic [31:0] value;\n    logic [31:0] update_value;\n    logic fault;\n    data_fault_t data_fault;\n    page_miss_t page_miss;\n    logic ca;\n    logic ov;\n    logic so;\n    logic [3:0] cr0;\n  } result_packet_t;'}

def one(pattern, source):
    found = re.findall(pattern, source, re.S)
    if len(found) != 1:
        raise ValueError(f'expected one source fragment: {pattern!r}, got {len(found)}')
    return found[0]

def prefix(text, name):
    for symbol in ('read_operand', 'wake_owns', 'wake1_owns', 'wake_match', 'wake1_match'):
        text = re.sub(r'\b'+symbol+r'\b', name+'_'+symbol, text)
    return text

def prepare(rtl):
    sources = {n:(rtl/n).read_text() for n in EXPECTED_HASHES}
    for name, expected in EXPECTED_HASHES.items():
        actual=hashlib.sha256(sources[name].encode()).hexdigest()
        if actual != expected:
            raise ValueError(f'{name}: source drift: {actual} != {expected}')
    r,c,q,p=(sources[n] for n in ('ppc_rename.sv','ppc_core.sv','ppc_completion.sv','ppc_pkg.sv'))
    for name, expected in ORIGINAL_TYPES.items():
        actual=one(r'(typedef struct packed \{[^}]*\} '+name+r';)',p)
        if actual != expected: raise ValueError(f'{name}: layout drift')
    for literal in ('localparam int GPR_RENAME_DEPTH = 5;', 'localparam int CQ_DEPTH = 5;',
                    'localparam int TAG_WIDTH = $clog2(GPR_RENAME_DEPTH);',
                    'localparam int CQ_INDEX_WIDTH = $clog2(CQ_DEPTH);',
                    'localparam int CQ_GENERATION_WIDTH = 8;',
                    'typedef logic [TAG_WIDTH-1:0] rename_tag_t;'):
        if p.count(literal)!=1: raise ValueError('width/constants drift: '+literal)
    if one(r'(  function automatic operand_t read_operand.*?  endfunction)',r)!=ORIGINAL_FUNCTION:
        raise ValueError('reader policy changed')
    calls=dict(re.findall(r'assign (read_[abc](?:1)?_o|early_[ab]) = read_operand\((.*?)\);',r))
    if calls!=ORIGINAL_CALLERS: raise ValueError('reader callers changed')
    for literal in ("parameter bit ENABLE_WAKE1_OWNER_PROJECTION = 1'b1,",
                    '.ENABLE_WAKE1_OWNER_PROJECTION(ENABLE_WAKE1_OWNER_PROJECTION)) rename (',
                    '.result1_i(result1)', '.wake1_o(cq_wake1)'):
        if c.count(literal)!=1: raise ValueError('core linkage changed: '+literal)
    if "parameter bit ENABLE_WAKE1_OWNER_PROJECTION = 1'b0" not in r:
        raise ValueError('rename must retain standalone default off')
    hint=one(r'\.wake1_producers_i\((\{[^}]*\})\)',c)
    select=one(r'\.wake1_select_i\((\{[^}]*\})\)',c)
    if hint!='{sru_result.producer, special_result.producer, iu_result.producer}' or select!='{sru_result_offer, special_port1_sel}':
        raise ValueError('raw source order changed')
    actual_match='\n'.join(re.findall(r'  assign wake(?:1)?_match =.*?;',r,re.S))
    wake0=one(r'(always_comb\s+for \(int i = 0; i < GPR_RENAME_DEPTH; i\+\+\)\s+wake_owns\[i\] = owners\[i\] == wake_i.producer;)',r).replace('always_comb','')
    enabled=one(r'g_wake1_owner_projection(.*?)// synthesis translate_off',r)
    enabled=one(r'(always_comb\s+for .*?\n        end)\s*$',enabled).replace('always_comb','')
    disabled=one(r'g_wake1_owner_legacy(.*?)endgenerate',r)
    disabled=one(r'(always_comb\s+for .*?wake1_owns\[i\] = owners\[i\] == wake1_i.producer;)',disabled).replace('always_comb','')
    route=one(r'(assign result1 = .*?;)',c).replace('assign ','')
    qualify=one(r'(assign special_port1_sel = .*?;)',c).replace('assign ','')
    cq_copy=one(r'(wake1_o.producer = result1_i.producer;)',q)
    late=one(r'(wake1 = cq_wake1;\s*wake1.late = .*?;)',c)
    early=one(r'(assign wake1_early_value = .*?;)',c).replace('assign ','')
    types='\n'.join(ORIGINAL_TYPES.values())
    decl='''localparam int GPR_RENAME_DEPTH=5, CQ_DEPTH=5, TAG_WIDTH=3,
CQ_INDEX_WIDTH=3, CQ_GENERATION_WIDTH=8;
typedef logic[2:0] rename_tag_t;
typedef logic[3:0] data_fault_t;
'''+types
    body='module tb_rename_raw_owner;\n'+decl+'\n'+FIXTURE
    funcs='\n'.join(prefix(ORIGINAL_FUNCTION,n) for n in ('old','new','disabled'))
    # Icarus supports these scalar functions; calls execute after explicit compute.
    compute=prefix(ORIGINAL_COMPUTE.replace('assign ',''),'old')+'\n'+prefix(actual_match.replace('assign ','')+'\n'+wake0+'\n'+enabled,'new')
    compute+='''
 saved_producers=wake1_producers_i; saved_select=wake1_select_i;
 wake1_producers_i='z; wake1_select_i='x;
 disabled_hint_changed=(wake1_producers_i!==saved_producers)||(wake1_select_i!==saved_select);
'''+prefix(actual_match.replace('assign ','')+'\n'+wake0+'\n'+disabled,'disabled')+'''
 wake1_producers_i=saved_producers; wake1_select_i=saved_select;
 if(disabled_hint_changed) disabled_garbage++;
'''
    source='''
 if(linked_selector) begin
'''+qualify+'''
 end else begin sru_result_offer=request_select[1]; special_port1_sel=request_select[0]; end
'''+route+'''
 result1_i=result1; cq_wake1=wake1_i;
'''+cq_copy.replace('wake1_o','cq_wake1')+'\n'+late+'''
 wake1_i.producer=wake1.producer;
 wake1_producers_i='''+hint+''';
 wake1_select_i='''+select+''';
 reference_result=sru_result_offer ? sru_result : special_port1_sel ? special_result : iu_result;
 if(result1 !== reference_result) $fatal(1,"full result packet priority");
 reference_producer=sru_result_offer ? sru_result.producer :
                    special_port1_sel ? special_result.producer : iu_result.producer;
 if(result1.producer !== reference_producer || wake1_i.producer !== reference_producer)
   $fatal(1,"actual core/CQ/late producer linkage");
 reference_late=special_port1_sel && special_late;
 if(wake1.late !== reference_late) $fatal(1,"late overlay");
'''+early+'''
 reference_early=sru_result_offer ? sru_result.value : special_result_select ? special_early_value : iu_result.value;
 if(wake1_early_value !== reference_early) $fatal(1,"early value priority");
'''
    assignments=[]
    for i,args in enumerate(calls.values()):
        for n in ('old','new','disabled'):
            assignments.append(f'{n}_out[{i}]={n}_read_operand({args});')
    return body.replace('@@FUNCTIONS@@',funcs).replace('@@COMPUTE@@',compute).replace('@@SOURCE@@',source).replace('@@CALLS@@','\n'.join(assignments))+'\nendmodule\n'

FIXTURE=r'''
logic[4:0] read_a_i,read_b_i,read_c_i,read_a1_i,read_b1_i,read_c1_i;
logic[31:0] arch_a_i,arch_b_i,arch_c_i,arch_a1_i,arch_b1_i,arch_c1_i;
logic[31:0] wake_early_value_i,wake1_early_value_i;
logic[4:0] valid,ready; logic[31:0] values[5];
completion_tag_t owners[5]; logic[31:0] map_valid; rename_tag_t map_tag[32];
wake_packet_t wake_i,wake1_i,cq_wake1,wake1;
logic wake_valid_i,wake1_valid_i,wake1_offer_i;
logic[4:0] old_wake_owns,old_wake1_owns,new_wake_owns,new_wake1_owns,disabled_wake_owns,disabled_wake1_owns;
logic old_wake_match,old_wake1_match,new_wake_match,new_wake1_match,disabled_wake_match,disabled_wake1_match;
logic[4:0] iu_owns,special_owns,sru_owns;
logic[2:0][10:0] wake1_producers_i,saved_producers;
logic[1:0] wake1_select_i,saved_select,request_select;
logic ENABLE_LSU_PIPE,special_result_select,lsu_port0,sru_result_offer,special_port1_sel,special_late;
logic linked_selector,disabled_hint_changed,reference_late;
logic[31:0] special_early_value,wake1_early_value,reference_early;
completion_tag_t reference_producer;
result_packet_t iu_result,special_result,sru_result,result1,result1_i,reference_result;
operand_t old_out[8],new_out[8],disabled_out[8];
integer checks=0,reader_comparisons=0,owner_comparisons=0;
integer lemma_vectors=0,alias_vectors=0,linked_vectors=0;
integer eq_zero=0,eq_one=0,eq_unknown=0,index_reject=0,generation_reject=0;
integer select_iu=0,select_special=0,select_sru=0,fallback_sru=0,fallback_special=0,sru_ignored_unknown=0,alias_fallback_one=0;
integer ready0=0,ready1=0,slots_seen[5],unknown_tags=0,unused_tags=0,invalid_masked=0,collisions=0,tag_exclusions=0,early_distinct=0,disabled_garbage=0;
@@FUNCTIONS@@
function automatic logic s4(input integer n);
 case(n%4) 0:s4=0;1:s4=1;2:s4=1'bx;3:s4=1'bz;endcase
endfunction
function automatic logic[2:0] tag4(input integer n);
 for(integer b=0;b<3;b++) tag4[b]=s4(n>>(2*b));
endfunction
function automatic logic[10:0] producer_pattern(input integer p);
 logic[10:0] v;
 v=11'h255;
 if(p>=1&&p<=11)v[p-1]=!v[p-1];
 if(p>=12&&p<=33)v[(p-12)/2]=((p-12)%2)?1'bz:1'bx;
 if(p==34)v='x;if(p==35)v='z;
 producer_pattern=v;
endfunction
function automatic logic[31:0] payload(input integer p);
 case(p%4)0:payload=32'ha5c35a3c;1:payload=32'h5a3ca5c3;
 2:payload={8{4'b10xz}};3:payload={8{4'bzx01}};endcase
endfunction
task automatic baseline(input logic[2:0] tag);
 read_a_i=0;read_b_i=1;read_c_i=2;read_a1_i=3;read_b1_i=4;read_c1_i=5;
 arch_a_i='h10;arch_b_i='h20;arch_c_i='h30;arch_a1_i='h40;arch_b1_i='h50;arch_c1_i='h60;
 wake_early_value_i='hf0a;wake1_early_value_i='hb0f;
 map_valid='1;valid='1;ready='0;
 for(integer s=0;s<32;s++)map_tag[s]=tag;
 for(integer s=0;s<5;s++)begin owners[s]=11'h255;values[s]=payload(s);end
 wake_i='0;wake1_i='0;wake_i.producer=11'h255;wake1_i.producer=11'h255;
 wake_i.tag=tag;wake1_i.tag=tag;wake_i.value=payload(0);wake1_i.value=payload(1);
 wake_valid_i=1;wake1_valid_i=1;wake1_offer_i=1;
 linked_selector=0;request_select={s4(checks/4),s4(checks)};
 ENABLE_LSU_PIPE=1;special_result_select=0;lsu_port0=1;special_late=0;special_early_value='hfed;
endtask
task automatic compute;
@@COMPUTE@@
endtask
task automatic source_link;
@@SOURCE@@
endtask
task automatic source_compare;
 logic eq; completion_tag_t own;
 source_link();compute();
 for(integer s=0;s<5;s++)begin
  eq=owners[s]==reference_producer;own=owners[s];
  if(new_wake1_owns[s]!==eq||disabled_wake1_owns[s]!==eq||old_wake1_owns[s]!==eq)
    $fatal(1,"owner equality slot=%0d",s);
  owner_comparisons++;
  if(eq===0)eq_zero++;else if(eq===1)eq_one++;else eq_unknown++;
  if(!$isunknown({own.index,reference_producer.index})&&own.index!=reference_producer.index&&eq===0)index_reject++;
  if(!$isunknown({own,reference_producer})&&own.index==reference_producer.index&&own.generation!=reference_producer.generation&&eq===0)generation_reject++;
 end
 if(wake1_select_i[1]===1)begin select_sru++;
  if($isunknown(wake1_select_i[0]))sru_ignored_unknown++;end
 else if(wake1_select_i[1]===0)begin
  if(wake1_select_i[0]===0)select_iu++;
  else if(wake1_select_i[0]===1)select_special++;
  else fallback_special++;
 end else fallback_sru++;
endtask
task automatic compare_readers;
 operand_t item,first;
 // Alias raw hints to the independently chosen selected producer. This
 // composes the separate selector lemma with the complete reader matrix.
 iu_result='0;special_result='x;sru_result='z;
 iu_result.producer=wake1_i.producer;special_result.producer=wake1_i.producer;sru_result.producer=wake1_i.producer;
 source_link();compute();
@@CALLS@@
 first=old_out[0];
 for(integer port=0;port<8;port++)begin
  if(old_out[port]!==new_out[port]||old_out[port]!==disabled_out[port])
   $fatal(1,"reader packet check=%0d port=%0d",checks,port);
  reader_comparisons+=2;item=old_out[port];
  if(item.ready===0)ready0++;if(item.ready===1)ready1++;
 end
 if(map_valid[0]===0)begin
  if(first.ready!==1||first.value!==arch_a_i||first.tag!=='0||first.producer!=='0)$fatal(1,"invalid mapped raw fields visible");
  invalid_masked++;
 end else if(map_valid[0]===1)begin
  if($isunknown(map_tag[0]))unknown_tags++;
  else if(int'(map_tag[0])>=5)unused_tags++;
  else begin
   slots_seen[map_tag[0]]++;
   if((!ready[map_tag[0]]&&wake1_offer_i&&wake1_i.tag==map_tag[0]&&old_wake1_owns[map_tag[0]])===1 &&
      (old_wake_match&&!wake_i.late&&wake_i.tag==map_tag[0])===1 &&
      (old_wake1_match&&!wake1_i.late&&wake1_i.tag==map_tag[0])===1)begin
    if(first.value!==wake1_i.value)$fatal(1,"port1 payload priority");collisions++;
   end
   if(ready[map_tag[0]]===0&&wake_valid_i===1&&wake_i.late===0&&valid[map_tag[0]]===1&&old_wake_owns[map_tag[0]]===1&&
      (wake_i.tag==map_tag[0])===0&&wake1_valid_i===0)begin
    if(first.ready!==0)$fatal(1,"wrong tag ready");tag_exclusions++;
   end
  end
 end
 if(old_out[6]!==old_out[0])early_distinct++;
 // Procedural IF membership is the actual contract, not a 0-vs-X assertion.
 if((old_wake_match===1)!==(new_wake_match===1)||(old_wake1_match===1)!==(new_wake1_match===1))$fatal(1,"wake membership");
 checks++;
endtask
initial begin
 for(integer s=0;s<5;s++)slots_seen[s]=0;
 // General raw source/selector lemma, including each bit of full owner tags.
 for(integer sel=0;sel<16;sel++)for(integer own=0;own<36;own++)for(integer prod=0;prod<36;prod++)for(integer role=0;role<3;role++)begin
  baseline(0);request_select={s4(sel/4),s4(sel)};
  iu_result='x;special_result='z;sru_result='x;
  iu_result.producer=producer_pattern(34);special_result.producer=producer_pattern(35);sru_result.producer=producer_pattern(11);
  case(role)0:iu_result.producer=producer_pattern(prod);1:special_result.producer=producer_pattern(prod);2:sru_result.producer=producer_pattern(prod);endcase
  for(integer s=0;s<5;s++)owners[s]=producer_pattern((own+s)%36);
  source_compare();lemma_vectors++;
 end
 for(integer sel=0;sel<16;sel++)for(integer p=0;p<36;p++)begin
  baseline(0);request_select={s4(sel/4),s4(sel)};
  iu_result='0;special_result='x;sru_result='z;
  iu_result.producer=producer_pattern(p);special_result.producer=producer_pattern(p);sru_result.producer=producer_pattern(p);
  for(integer s=0;s<5;s++)owners[s]=producer_pattern(p);
  source_compare();alias_vectors++;
  if(($isunknown(wake1_select_i[1])||(wake1_select_i[1]===0&&$isunknown(wake1_select_i[0])))&&new_wake1_owns[0]===1)alias_fallback_one++;
 end
 // Actual core qualification is linked, never an independent select premise.
 for(integer c=0;c<128;c++)for(integer p=0;p<36;p++)begin
  baseline(0);linked_selector=1;ENABLE_LSU_PIPE=c%2;special_result_select=s4(c/2);lsu_port0=s4(c/8);sru_result_offer=s4(c/32);special_late=s4(p);
  iu_result='0;special_result='x;sru_result='z;
  iu_result.producer=producer_pattern(p);special_result.producer=producer_pattern((p+11)%36);sru_result.producer=producer_pattern((p+23)%36);
  for(integer s=0;s<5;s++)owners[s]=producer_pattern((p+s)%36);
  source_compare();linked_vectors++;
 end
 // Unknown and out-of-range operand and wake tags, both active ports.
 for(integer t=0;t<64;t++)for(integer wt=0;wt<64;wt++)for(integer active=0;active<2;active++)begin
  baseline(tag4(t));wake_valid_i=!active;wake1_valid_i=active;wake1_offer_i=active;
  if(active)wake1_i.tag=tag4(wt);else wake_i.tag=tag4(wt);
  compare_readers();
 end
 // Independent full four-state validity/readiness/late/offer product.
 for(integer slot=0;slot<5;slot++)for(integer q=0;q<16384;q++)begin
  baseline(slot);valid[slot]=s4(q);ready[slot]=s4(q/4);wake_valid_i=s4(q/16);wake1_valid_i=s4(q/64);
  wake_i.late=s4(q/256);wake1_i.late=s4(q/1024);wake1_offer_i=s4(q/4096);
  wake_i.value=payload(q/32);wake1_i.value=payload(q/128);compare_readers();
 end
 for(integer slot=0;slot<5;slot++)for(integer own=0;own<36;own++)for(integer w=0;w<36;w++)for(integer active=0;active<2;active++)begin
  baseline(slot);owners[slot]=producer_pattern(own);wake_valid_i=!active;wake1_valid_i=active;wake1_offer_i=active;
  if(active)wake1_i.producer=producer_pattern(w);else wake_i.producer=producer_pattern(w);
  compare_readers();
 end
 for(integer slot=0;slot<5;slot++)for(integer mv=0;mv<4;mv++)for(integer qr=0;qr<4;qr++)for(integer offer=0;offer<4;offer++)for(integer data=0;data<4;data++)begin
  baseline(slot);map_valid={32{s4(mv)}};ready[slot]=s4(qr);wake1_offer_i=s4(offer);
  wake_i.value=payload(data);wake1_i.value=payload(data+1);wake_early_value_i=payload(data+2);wake1_early_value_i=payload(data+3);
  if(mv==0)begin valid='x;ready='z;for(integer s=0;s<5;s++)owners[s]='x;for(integer s=0;s<32;s++)map_tag[s]='z;end
  compare_readers();
 end
 if(lemma_vectors!=62208||alias_vectors!=576||linked_vectors!=4608||owner_comparisons!=336960||checks!=104352||reader_comparisons!=1669632)$fatal(1,"wrong matrix size");
 if(!(eq_zero&&eq_one&&eq_unknown&&index_reject&&generation_reject&&select_iu&&select_special&&select_sru&&fallback_sru&&fallback_special&&sru_ignored_unknown&&alias_fallback_one))$fatal(1,"vacuous source coverage");
 if(!(ready0&&ready1&&unknown_tags&&unused_tags&&invalid_masked&&collisions&&tag_exclusions&&early_distinct&&disabled_garbage))$fatal(1,"vacuous reader coverage");
 for(integer s=0;s<5;s++)if(!slots_seen[s])$fatal(1,"uncovered slot");
 $display("PASS raw-owner: owner=%0d reader=%0d vectors=%0d disabled_poison=%0d",owner_comparisons,reader_comparisons,checks,disabled_garbage);
 $display("source: eq0=%0d eq1=%0d eqX=%0d index=%0d generation=%0d fallback=%0d/%0d ignored_secondary=%0d alias_positive=%0d",eq_zero,eq_one,eq_unknown,index_reject,generation_reject,fallback_sru,fallback_special,sru_ignored_unknown,alias_fallback_one);
 $display("reader: ready0=%0d ready1=%0d collision=%0d exclusion=%0d invalid=%0d unknown_tag=%0d unused_tag=%0d early=%0d",ready0,ready1,collisions,tag_exclusions,invalid_masked,unknown_tags,unused_tags,early_distinct);
 $finish;
end
'''

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-dir',type=Path,required=True)
    parser.add_argument('--rtl-dir',type=Path,default=Path(__file__).resolve().parents[2]/'rtl')
    parser.add_argument('--prepare-only',action='store_true')
    args=parser.parse_args()
    fixture=prepare(args.rtl_dir)
    args.build_dir.mkdir(parents=True,exist_ok=True)
    source=args.build_dir/'prepared.sv'; source.write_text(fixture)
    if args.prepare_only:
        print('Prepared source-guarded fixture; no compiler or simulator executed.')
        return
    executable=args.build_dir/'equivalence.vvp'
    try:
        subprocess.run(['iverilog','-g2012','-s','tb_rename_raw_owner','-o',str(executable),str(source)],check=True,timeout=30)
        subprocess.run(['vvp',str(executable)],check=True,timeout=60)
    finally:
        executable.unlink(missing_ok=True)
if __name__=='__main__': main()
