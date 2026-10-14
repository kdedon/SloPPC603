#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Optional bounded actual-source four-state FD classification check.

Fixed legacy whole-pair/class/SRU equations are independent of current source.
303104 finite class/whole-pair and 4096 FD cases require positive class/outcome
coverage. This is expression coverage, not whole-core ISA or timing acceptance.
Requires optional Icarus, as existing four-state targets do.
"""
from pathlib import Path
import re, argparse, subprocess
REFERENCE_PKG = r'''
typedef enum logic [4:0] {
    ALU_ADD, ALU_OR, ALU_XOR, ALU_AND, ALU_ANDC,
    ALU_ORC, ALU_NAND, ALU_NOR, ALU_EQV,
    ALU_ROTATE, ALU_SLW, ALU_SRW, ALU_SRAW, ALU_RLWIMI,
    ALU_CNTLZW, ALU_EXTSB, ALU_EXTSH, ALU_MULLW,
    ALU_MULHW, ALU_MULHWU, ALU_DIVWU, ALU_DIVW, ALU_MULLI,
    ALU_CMP, ALU_CMPL
  } alu_op_t;
typedef enum logic [2:0] {
    CACHE_OP_NONE, CACHE_OP_DCBF, CACHE_OP_DCBST, CACHE_OP_DCBI,
    CACHE_OP_DCBZ, CACHE_OP_DCBT, CACHE_OP_DCBTST, CACHE_OP_SYNC
  } cache_op_t;
typedef enum logic [1:0] {
    CARRY_ZERO, CARRY_ONE, CARRY_CA
  } carry_in_t;
typedef enum logic [2:0] {
    CR_LOGIC_AND, CR_LOGIC_ANDC, CR_LOGIC_EQV, CR_LOGIC_NAND,
    CR_LOGIC_NOR, CR_LOGIC_OR, CR_LOGIC_ORC, CR_LOGIC_XOR
  } cr_logic_op_t;
typedef enum logic [1:0] {
    ESA_DENIED = 2'd0,
    ESA_ALLOWED = 2'd1,
    ESA_PO_BASE = 2'd2,
    ESA_PO_SER = 2'd3
  } esa_enable_t;
typedef enum logic [2:0] {
    FETCH_OK = 3'd0,
    FETCH_ISI_PROTECTION = 3'd1,
    FETCH_ISI_GUARDED = 3'd2,
    FETCH_PAGE_MISS = 3'd3,
    FETCH_MACHINE_CHECK = 3'd4,
    FETCH_IABR = 3'd5,
    FETCH_TEA_REPEAT = 3'd6
  } fetch_fault_t;
typedef enum logic [1:0] {
    SEQ_NONE, SEQ_MULTIPLE, SEQ_STRING_IMM, SEQ_STRING_INDEXED
  } mem_seq_t;
typedef enum logic [1:0] {
    MEM_BYTE, MEM_HALF, MEM_WORD
  } mem_size_t;
typedef enum logic [5:0] {
    SPECIAL_NONE, SPECIAL_B, SPECIAL_BC, SPECIAL_BCLR, SPECIAL_BCCTR,
    SPECIAL_MFSPR, SPECIAL_MTSPR,
    SPECIAL_LOAD, SPECIAL_STORE, SPECIAL_MFCR, SPECIAL_MTCRF,
    SPECIAL_CR_LOGIC, SPECIAL_MCRF, SPECIAL_MCRXR,
    SPECIAL_SC, SPECIAL_RFI, SPECIAL_PROGRAM_ILLEGAL,
    SPECIAL_PROGRAM_PRIV, SPECIAL_MFMSR,
    SPECIAL_ISYNC, SPECIAL_SYNC, SPECIAL_EIEIO, SPECIAL_ALIGNMENT, SPECIAL_ISI, SPECIAL_MTMSR,
    SPECIAL_MFSR, SPECIAL_MTSR, SPECIAL_TLBIE,
    SPECIAL_TLBLD, SPECIAL_TLBLI, SPECIAL_TLBSYNC, SPECIAL_ICBI,
    
    SPECIAL_TRAP,
    
    
    SPECIAL_FPU, SPECIAL_FP_UNAVAILABLE,
    
    
    
    SPECIAL_EMULATION_TRAP, SPECIAL_FPU_EMULATE,
    SPECIAL_ESA, SPECIAL_DSA, SPECIAL_MFROM,
    
    SPECIAL_FP_ENABLED
  } special_op_t;
typedef enum logic [2:0] {
    UNIT_IU, UNIT_LSU, UNIT_FPU, UNIT_BPU, UNIT_SPECIAL
  } unit_class_e;
typedef struct packed {
    alu_op_t op;
    logic invert_a;
    carry_in_t carry_in;
    logic illegal;
    logic [4:0] src_a;
    logic [4:0] src_b;
    logic [4:0] src_c;
    logic [4:0] dst;
    logic gpr_write;
    logic mem_update;
    logic zero_a;
    logic use_imm;
    logic [31:0] imm;
    logic [31:0] mask;
    logic [4:0] shift;
    special_op_t special_op;
    fetch_fault_t fetch_fault;
    esa_enable_t esa;
    logic [31:0] branch_disp;
    logic branch_aa;
    logic branch_lk;
    logic [4:0] branch_bo;
    logic [4:0] branch_bi;
    logic [9:0] spr;
    logic [3:0] sr_index;
    logic sr_indexed;
    logic [2:0] cr_field;
    logic [2:0] cr_source_field;
    logic write_cr_fields;
    logic [7:0] cr_mask;
    logic write_cr_bit;
    logic [4:0] cr_bit;
    logic [4:0] cr_bit_a;
    logic [4:0] cr_bit_b;
    cr_logic_op_t cr_logic;
    mem_size_t mem_size;
    logic mem_signed;
    logic mem_reverse;
    
    
    logic mem_left;
    logic [1:0] mem_bytes;
    mem_seq_t mem_seq;
    
    logic mem_reserve;
    logic mem_conditional;
    
    logic mem_external;
    
    logic mem_skip;
    
    logic seq_partial;
    
    logic cache_probe;
    
    logic block_zero;
    
    cache_op_t cache_op;
    logic privileged;
    
    logic [16:0] alignment_dsisr;
    logic read_ca;
    logic read_so;
    logic needs_flags;
    logic write_xer;
    logic write_ca;
    logic write_ov_so;
    logic write_cr_field;
  } uop_t;
typedef struct packed {
    unit_class_e unit;
    
    logic sru;
    
    logic serial;
    
    logic [3:0] reads;
    logic [3:0] writes;
    logic [1:0] gpr_dsts;
    
    logic cq1_ok;
    
    logic [2:0] dep_prev;
  } iq_pair_t;
function automatic iq_pair_t pair_predecode(uop_t u, logic [31:0] insn, logic fault);
    iq_pair_t p;
    logic branch, fp_arith, fp_mem, store, plain_mem;
    branch = (u.special_op == SPECIAL_B) || (u.special_op == SPECIAL_BC) ||
             (u.special_op == SPECIAL_BCLR) || (u.special_op == SPECIAL_BCCTR);
    fp_arith = (u.special_op == SPECIAL_FPU) &&
               ((insn[31:26] == 6'd59) || (insn[31:26] == 6'd63));
    fp_mem = (u.special_op == SPECIAL_FPU) && !fp_arith;
    plain_mem = ((u.special_op == SPECIAL_LOAD) || (u.special_op == SPECIAL_STORE)) &&
                (u.mem_seq == SEQ_NONE) && !u.mem_reserve && !u.mem_conditional &&
                !u.mem_external && !u.mem_skip && !u.cache_probe && !u.block_zero;
    store = (u.special_op == SPECIAL_STORE) ||
            (fp_mem && ((insn[31:26] == 6'd31) ? insn[8] : insn[28]));
    p = '0;
    if (u.illegal || fault) p.unit = UNIT_SPECIAL;
    else if (branch) p.unit = UNIT_BPU;
    else if (u.special_op == SPECIAL_NONE) p.unit = UNIT_IU;
    else if (fp_arith) p.unit = UNIT_FPU;
    else if (plain_mem || fp_mem) p.unit = UNIT_LSU;
    else p.unit = UNIT_SPECIAL;
    p.serial = p.unit == UNIT_SPECIAL;
    p.sru = (p.unit == UNIT_IU) &&
      ((insn[31:26] == 6'd14) || (insn[31:26] == 6'd15) ||
       (insn[31:26] == 6'd11) || (insn[31:26] == 6'd10) ||
       ((insn[31:26] == 6'd31) && !insn[0] &&
        ((insn[9:1] == 9'd266) || (insn[10:1] == 10'd0) || (insn[10:1] == 10'd32))));
    p.reads[3] = branch && (u.special_op != SPECIAL_B) && !u.branch_bo[4];
    p.reads[2] = u.read_ca || u.read_so;
    p.reads[1] = u.special_op == SPECIAL_BCLR;
    p.reads[0] = (branch && (u.special_op != SPECIAL_B) && !u.branch_bo[2]) ||
                 (u.special_op == SPECIAL_BCCTR);
    p.writes[3] = u.write_cr_field || u.write_cr_bit || u.write_cr_fields;
    p.writes[2] = u.write_ca || u.write_ov_so || u.write_xer;
    p.writes[1] = branch && u.branch_lk;
    p.writes[0] = branch && (u.special_op != SPECIAL_B) && !u.branch_bo[2];
    p.gpr_dsts = 2'(u.gpr_write) + 2'(u.mem_update);
    p.cq1_ok = !p.serial && !store && (p.unit != UNIT_FPU);
    return p;
  endfunction
'''
REFERENCE_CORE = r'''
function automatic logic needs_iu(unit_class_e unit, logic sru);
    return (unit == UNIT_IU) && !sru;
  endfunction
assign fd_next_iu = fd_valid && ((push_pair.unit != UNIT_BPU) ? needs_iu(push_pair.unit, push_pair.sru) : (fd1_valid && needs_iu(push_pair1.unit, push_pair1.sru)));
push_pair = pair_predecode(push_uop, queued.insn, queued.fault != FETCH_OK);
push_pair1 = pair_predecode(push_uop1, queued1.insn, queued1.fault != FETCH_OK);
'''
FIXTURE = r'''
// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Prepared finite actual-source helper/FD composition proof, not ISA acceptance.
module tb_fd_lookahead;
/* EXTRACTED_TYPES */
/* EXTRACTED_SOURCE_FUNCTIONS */
  typedef struct packed {logic[31:0] insn;fetch_fault_t fault;} packet_t;
  uop_t push_uop,push_uop1;
  packet_t queued,queued1;
  iq_pair_t push_pair,push_pair1;
  fetch_lookahead_t fd_class,fd_class1;
  logic fd_valid,fd1_valid;
  wire old_fd,new_fd;
  assign push_pair=pair_predecode_old(push_uop,queued.insn,queued.fault!=FETCH_OK);
  assign push_pair1=pair_predecode_old(push_uop1,queued1.insn,queued1.fault!=FETCH_OK);
/* EXTRACTED_SOURCE_FD */

  function automatic logic state4(input int index);
    case(index%4) 0:return 1'b0;1:return 1'b1;2:return 1'bx;default:return 1'bz;endcase
  endfunction
  // Fixed independent old enum-class/SRU equations; never calls new helpers.
  function automatic logic[1:0] reference_class(input uop_t u,input logic[31:0] word,input logic fault);
    unit_class_e unit;
    logic branch,sru;
    branch=(u.special_op==SPECIAL_B)||(u.special_op==SPECIAL_BC)||
           (u.special_op==SPECIAL_BCLR)||(u.special_op==SPECIAL_BCCTR);
    unit=UNIT_SPECIAL;
    if(u.illegal||fault)unit=UNIT_SPECIAL;
    else if(branch)unit=UNIT_BPU;
    else if(u.special_op==SPECIAL_NONE)unit=UNIT_IU;
    // Other original classes are all non-BPU/non-IU; their distinction is
    // immaterial to these two predicates, and whole records are tested too.
    sru=(unit==UNIT_IU)&&((word[31:26]==6'd14)||(word[31:26]==6'd15)||
      (word[31:26]==6'd11)||(word[31:26]==6'd10)||
      ((word[31:26]==6'd31)&&!word[0]&&
        ((word[9:1]==9'd266)||(word[10:1]==10'd0)||(word[10:1]==10'd32))));
    return{unit==UNIT_BPU,(unit==UNIT_IU)&&!sru};
  endfunction
  function automatic logic[5:0] special_pattern(input int index);
    logic[5:0] value;
    if(index<64)return 6'(index);
    if(index==64)return 6'bxxxxxx;
    if(index==65)return 6'bzzzzzz;
    if(index<78)begin
      value=6'b0;value[(index-66)/2]=((index-66)%2==0)?1'bx:1'bz;return value;
    end
    return(index==78)?6'b0x0z01:6'bz1x010;
  endfunction
  function automatic logic[31:0] instruction_pattern(input int index);
    logic[31:0] word;
    word=32'b0;
    case(index)
      0:word[31:26]=6'd14;1:word[31:26]=6'd15;
      2:word[31:26]=6'd11;3:word[31:26]=6'd10;
      4,5,6,7,8,9,10,11:begin
        word[31:26]=6'd31;word[0]=1'(index%2);
        case((index-4)/2)0:word[10:1]=10'd266;1:word[10:1]=10'd0;
          2:word[10:1]=10'd32;default:word[10:1]=10'd778;endcase
      end
      12:word[31:26]=6'd16;13:word[31:26]=6'd18;
      14:word[31:26]=6'd59;15:word[31:26]=6'd63;
      16:begin word[31:26]=6'd31;word[10:1]=10'd266;word[0]=1'bx;end
      17:begin word[31:26]=6'd31;word[10:1]=10'd266;word[0]=1'bz;end
      18:begin word[31:26]=6'd31;word[10:1]=10'bxxxxxxxxxx;end
      19:begin word[31:26]=6'd31;word[10:1]=10'bzzzzzzzzzz;end
      20:word[31:26]=6'bxxxxxx;21:word[31:26]=6'bzzzzzz;
      22:begin word[31:26]=6'b0x1110;word[10:1]=10'd0;end
      23:begin word[31:26]=6'b0z1111;word[10:1]=10'd32;end
      24:begin word[31:26]=6'd31;word[10:1]=10'b01x0001010;end
      25:begin word[31:26]=6'd31;word[10:1]=10'bz000000000;end
      26:begin word[31:26]=6'd31;word[10:1]=10'd512;end
      27:begin word[31:26]=6'd31;word[10:1]=10'd544;end
      28:word=32'h00000000;29:word=32'hffffffff;
      30:word={8{4'b01xz}};default:word={8{4'bz10x}};
    endcase
    return word;
  endfunction
  // Independent fixed IU-eligibility/SRU reference for positive coverage.
  function automatic logic reference_iu(uop_t u, logic fault);
    logic branch,eligible;
    branch=(u.special_op==SPECIAL_B)||(u.special_op==SPECIAL_BC)||
      (u.special_op==SPECIAL_BCLR)||(u.special_op==SPECIAL_BCCTR);
    eligible=0;
    if(u.illegal||fault)eligible=0;
    else if(branch)eligible=0;
    else if(u.special_op==SPECIAL_NONE)eligible=1;
    return eligible;
  endfunction
  function automatic logic reference_raw_sru(logic[31:0] word);
    return (word[31:26]==6'd14)||(word[31:26]==6'd15)||
      (word[31:26]==6'd11)||(word[31:26]==6'd10)||
      ((word[31:26]==6'd31)&&!word[0]&&
       ((word[9:1]==9'd266)||(word[10:1]==10'd0)||(word[10:1]==10'd32)));
  endfunction
  // Rows old/new/reference, columns branch/needsIU/SRU/non-IU-nonbranch.
  integer coverage[3][4]; integer fd_positive[2],fd_negative[2];
  task automatic compare_class(input uop_t u,input logic[31:0] word,input logic fault);
    iq_pair_t before_pair,after_pair;
    fetch_lookahead_t actual_class;
    logic[1:0] expected;logic eligible,ref_sru;
    before_pair=pair_predecode_old(u,word,fault);
    after_pair=pair_predecode_new(u,word,fault);
    actual_class=fetch_lookahead(u,word,fault);
    expected=reference_class(u,word,fault);
    eligible=reference_iu(u,fault);ref_sru=eligible&&reference_raw_sru(word);
    if((before_pair.unit==UNIT_BPU)===1'b1)coverage[0][0]++;
    if(((before_pair.unit==UNIT_IU)&&!before_pair.sru)===1'b1)coverage[0][1]++;
    if(((before_pair.unit==UNIT_IU)&&before_pair.sru)===1'b1)coverage[0][2]++;
    if(((before_pair.unit!=UNIT_IU)&&(before_pair.unit!=UNIT_BPU))===1'b1)coverage[0][3]++;
    if(actual_class.branch===1'b1)coverage[1][0]++;
    if(actual_class.needs_iu===1'b1)coverage[1][1]++;
    if(((after_pair.unit==UNIT_IU)&&pair_sru_form(word))===1'b1)coverage[1][2]++;
    if(((after_pair.unit!=UNIT_IU)&&(after_pair.unit!=UNIT_BPU))===1'b1)coverage[1][3]++;
    if(expected[1]===1'b1)coverage[2][0]++;
    if(expected[0]===1'b1)coverage[2][1]++;
    if(ref_sru===1'b1)coverage[2][2]++;
    if((!eligible&&!expected[1])===1'b1)coverage[2][3]++;
    if(before_pair !== after_pair)$fatal(1,"whole pair metadata changed");
    if({before_pair.unit==UNIT_BPU,(before_pair.unit==UNIT_IU)&&!before_pair.sru} !== expected)
      $fatal(1,"actual original helper differs from independent fixture");
    if(actual_class !== expected)$fatal(1,"direct class differs from old reference");
  endtask
  integer class_checks,fd_checks;
  uop_t sample;
  logic[31:0] word;
  initial begin
    class_checks=0;fd_checks=0;
    for(int r=0;r<3;r++)for(int c=0;c<4;c++)coverage[r][c]=0;
    for(int r=0;r<2;r++)begin fd_positive[r]=0;fd_negative[r]=0;end
    // Finite raw special-op space (all64 binary plus X/Z patterns), all16
    // independent illegal/fault states, and targeted SRU encoding corners.
    for(int op=0;op<80;op++)for(int pattern=0;pattern<32;pattern++)begin
      case(pattern%4)0:sample='0;1:sample='1;
        2:sample={$bits(uop_t){1'bx}};default:sample={$bits(uop_t){1'bz}};endcase
      sample.special_op=special_pattern(op);word=instruction_pattern(pattern);
      for(int flags=0;flags<16;flags++)begin
        sample.illegal=state4(flags);
        compare_class(sample,word,state4(flags/4));class_checks++;
      end
    end
    // Exhaust known primary/XO bits and all four Rc states in the IU class.
    // Memory/source flags remain an independent fixed old/new record check.
    sample='0;sample.special_op=SPECIAL_NONE;
    for(int primary=0;primary<64;primary++)for(int xo=0;xo<1024;xo++)for(int rc=0;rc<4;rc++)begin
      word='0;word[31:26]=6'(primary);word[10:1]=10'(xo);word[0]=state4(rc);
      compare_class(sample,word,1'b0);class_checks++;
    end
    // Actual caller equations: both lane payloads, independent transport-fault
    // patterns, paired valid0/1/X/Z, and a literal old/new fd_next ternary.
    for(int row=0;row<32;row++)for(int lane=0;lane<8;lane++)begin
      push_uop='0;push_uop1='0;
      case(lane%4)0:push_uop.special_op=SPECIAL_NONE;1:push_uop.special_op=SPECIAL_B;
        2:push_uop.special_op=SPECIAL_LOAD;default:push_uop.special_op=6'bxxxxxx;endcase
      push_uop1.special_op=(lane<4)?SPECIAL_NONE:SPECIAL_BC;
      push_uop.illegal=state4(row%4);push_uop1.illegal=state4((lane/2)%4);
      queued.insn=instruction_pattern(row);queued1.insn=instruction_pattern(31-row);
      case(row%4)0:queued.fault=FETCH_OK;1:queued.fault=FETCH_IABR;
        2:queued.fault=3'bxxx;default:queued.fault=3'bzzz;endcase
      case((lane/2)%4)0:queued1.fault=FETCH_OK;1:queued1.fault=FETCH_MACHINE_CHECK;
        2:queued1.fault=3'bxxx;default:queued1.fault=3'bzzz;endcase
      for(int valid0=0;valid0<4;valid0++)for(int valid1=0;valid1<4;valid1++)begin
        fd_valid=state4(valid0);fd1_valid=state4(valid1);#1;
        if(old_fd !== new_fd)$fatal(1,"actual FD lookahead ternary changed");
        if(old_fd===1'b1)fd_positive[0]++;
        if(new_fd===1'b1)fd_positive[1]++;
        if(old_fd===1'b0)fd_negative[0]++;
        if(new_fd===1'b0)fd_negative[1]++;
        fd_checks++;
      end
    end
    if(class_checks!=303104 || fd_checks!=4096)$fatal(1,"coverage counts changed");
    for(int r=0;r<3;r++)begin
      for(int c=0;c<4;c++)if(coverage[r][c]==0)$fatal(1,"vacuous class coverage row%0d category%0d",r,c);
      $display("positive class row%0d branch=%0d needsIU=%0d SRU=%0d nonIU=%0d",r,coverage[r][0],coverage[r][1],coverage[r][2],coverage[r][3]);
    end
    for(int r=0;r<2;r++)if(fd_positive[r]==0||fd_negative[r]==0)$fatal(1,"vacuous FD outcome coverage");
    $display("PASS source-extracted direct class: %0d wholepair/class vectors, %0d actual FD valid/fault/lane vectors",class_checks,fd_checks);
    $finish;
  end
endmodule

'''

def clean(s):return re.sub(r'/\*.*?\*/|//[^\n]*','',s,flags=re.S)
def structure(s,name):
 matches=re.findall(r'typedef struct packed\s*\{([^{}]*)\}\s*'+name+r';',clean(s),re.S)
 if len(matches)!=1:raise ValueError('struct '+name)
 return 'typedef struct packed {'+matches[0]+'} '+name+';\n'
def function(s,name):
 matches=re.findall(r'function automatic \w+\s+'+name+r'\s*\(.*?endfunction',clean(s),re.S)
 if len(matches)!=1:raise ValueError('function '+name)
 return matches[0]+'\n'
def assignment(s,name):
 matches=re.findall(r'\bassign\s+'+name+r'\s*=\s*(.*?);',clean(s),re.S)
 if len(matches)!=1:raise ValueError('assignment '+name)
 return matches[0]

def prepare(new,new_core):
    old=REFERENCE_PKG;old_core=REFERENCE_CORE
    # Retain exact packed layouts and enum widths/constants. Flatten storage types
    # only so Icarus may apply arbitrary unknown raw enum patterns.
    uop=structure(old,'uop_t');pair=structure(old,'iq_pair_t');cls=structure(new,'fetch_lookahead_t')
    assert uop==structure(new,'uop_t') and pair==structure(new,'iq_pair_t')
    assert re.sub(r'\s+','',cls)==re.sub(r'\s+','','typedef struct packed {logic branch;logic needs_iu;} fetch_lookahead_t;'), 'lookahead layout drift'
    types=set(re.findall(r'^\s*(\w+_t|unit_class_e)\s+\w+;',uop+pair,re.M))
    # uop enum types include fields with a range after logic only; scalar typed fields above.
    enums=[]
    for name in sorted(types):
     matches=re.findall(r'typedef enum logic \[(\d+):0\]\s*\{([^{}]*)\}\s*'+name+r';',clean(old),re.S)
     if len(matches)!=1:raise ValueError('enum '+name)
     assert matches==re.findall(r'typedef enum logic \[(\d+):0\]\s*\{([^{}]*)\}\s*'+name+r';',clean(new),re.S), 'enum changed '+name
     width=int(matches[0][0])+1
     if name in ['special_op_t','unit_class_e','fetch_fault_t']:assert width=={'special_op_t':6,'unit_class_e':3,'fetch_fault_t':3}[name], 'fixture enum width '+name
     tokens=matches[0][1].split(',');value=0
     lines=[f'typedef logic [{width-1}:0] {name};']
     for token in tokens:
      bits=token.strip().split('=');identifier=bits[0].strip()
      if len(bits)==2:
       literal=bits[1].strip();match=re.fullmatch(r"\d+'([dhb])([0-9a-fA-F_]+)",literal)
       if not match:raise ValueError('unsupported enum literal '+literal)
       value=int(match[2].replace('_',''),{'d':10,'h':16,'b':2}[match[1]])
      lines.append(f"localparam {name} {identifier} = {width}'d{value};");value+=1
     enums.append('\n'.join(lines))
    old_pair=function(old,'pair_predecode').replace('pair_predecode(','pair_predecode_old(',1)
    new_pair=function(new,'pair_predecode').replace('pair_predecode(','pair_predecode_new(',1)
    new_raw=function(new,'pair_sru_form');new_cls=function(new,'fetch_lookahead')
    needs=function(old_core,'needs_iu')
    assert needs==function(new_core,'needs_iu'), 'needs_iu changed'
    def compact(s):return re.sub(r'\s+','',clean(s))
    for core in [old_core,new_core]:
     for name,expr in [('push_pair','pair_predecode(push_uop, queued.insn, queued.fault != FETCH_OK)'),('push_pair1','pair_predecode(push_uop1, queued1.insn, queued1.fault != FETCH_OK)')]:
      matches=re.findall(r'\b'+name+r'\s*=\s*(.*?);',clean(core),re.S)
      assert len(matches)==1 and compact(matches[0])==compact(expr), 'pair caller wiring '+name
    old_fd=assignment(old_core,'fd_next_iu');new_fd=assignment(new_core,'fd_next_iu')
    assert compact(old_fd)==compact('fd_valid && ((push_pair.unit != UNIT_BPU) ? needs_iu(push_pair.unit, push_pair.sru) : (fd1_valid && needs_iu(push_pair1.unit, push_pair1.sru)))'), 'original FD equation drift'
    assert compact(new_fd)==compact('fd_valid && (!fd_class.branch ? fd_class.needs_iu : (fd1_valid && fd_class1.needs_iu))'), 'candidate FD equation drift'
    fd_class=assignment(new_core,'fd_class');fd_class1=assignment(new_core,'fd_class1')
    assert compact(fd_class)==compact('fetch_lookahead(push_uop, queued.insn, queued.fault != FETCH_OK)')
    assert compact(fd_class1)==compact('fetch_lookahead(push_uop1, queued1.insn, queued1.fault != FETCH_OK)')
    
    fixture=FIXTURE
    fragments=dict(TYPES='\n'.join(enums)+'\n'+uop+pair+cls,
      SOURCE_FUNCTIONS=old_pair+new_raw+new_pair+new_cls+needs,
      SOURCE_FD='assign fd_class = '+fd_class+';\nassign fd_class1 = '+fd_class1+';\nassign old_fd = '+old_fd+';\nassign new_fd = '+new_fd+';')
    for name,value in fragments.items():
     marker='/* EXTRACTED_'+name+' */'
     if fixture.count(marker)!=1:raise ValueError('marker '+name)
     fixture=fixture.replace(marker,value)
    if 'EXTRACTED_' in fixture:raise ValueError('unfilled marker')
    return fixture

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-dir',type=Path,required=True)
    parser.add_argument('--prepare-only',action='store_true')
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[2]
    fixture=prepare((root/'rtl/ppc_pkg.sv').read_text(),(root/'rtl/ppc_core.sv').read_text())
    args.build_dir.mkdir(parents=True,exist_ok=True)
    source=args.build_dir/'fd_lookahead_fixture.sv';binary=args.build_dir/'fd_lookahead.vvp'
    source.write_text(fixture)
    if args.prepare_only:
        print('Prepared bounded actual-source FD classification fixture; no execution');return
    try:
        subprocess.run(['iverilog','-g2012','-s','tb_fd_lookahead','-o',str(binary),str(source)],check=True,timeout=30)
        subprocess.run(['vvp',str(binary)],check=True,timeout=30)
    finally:binary.unlink(missing_ok=True)

if __name__=='__main__':main()
