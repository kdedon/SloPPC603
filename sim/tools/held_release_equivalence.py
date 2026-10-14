#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Optional bounded Icarus expression check, not whole-core conformance.

Compare actual registered-FD release wiring/helpers against a fixed original
FD-view/release/readiness oracle. Known FD-valid controls must agree; X/Z-valid
controls report diagnostic divergences. The 131072-case finite matrix plus
72 directed release/inhibition cases are not exhaustive packet/qualifier
coverage. Each branch family must check four positive, independent targets. No Git history or saved source snapshot is required.
"""
import argparse
import re
import subprocess
from pathlib import Path

FUNCTIONS = ['iabr_check', 'folds', 'waits', 'cr_branch', 'selected_cr_bit', 'folded_target']
COMMON = ['fd_bypass', 'fd_valid', 'fd_packet', 'queued', 'cr0_now', 'fold_predict', 'wait0', 'crb0', 'wait0_cr', 'cr_hold0', 'fd_push', 'fd_split_q', 'rel_fold', 'fetch_ready', 'fold0_target']
EXTRA = ['held_word', 'held_push', 'held_cr_now', 'held_predict', 'rel_target']
# Fixed original formula/helper fixture; never derived from the current core.
REFERENCE_SOURCE = r'''
  function automatic fetch_packet_t iabr_check(fetch_packet_t p, logic [31:0] bp);
    fetch_packet_t q;
    q = p;
    if (ENABLE_DEBUG_EXCEPTIONS && bp[1] && (p.fault == FETCH_OK) &&
        (p.pc[31:2] == bp[31:2]))
      q.fault = FETCH_IABR;
    return q;
  endfunction
  function automatic logic folds(fetch_packet_t p, logic trace, logic lr_ok, logic ctr_ok,
                                 logic cr_final, logic cr_bit, logic ctr_one);
    logic predict, bo_ok, xl_ok;
    predict = (p.insn[25] && p.insn[23]) || (p.insn[15] ^ p.insn[21]);
    if (!p.insn[25] && cr_final)
      predict = (cr_bit == p.insn[24]) &&
                (p.insn[23] || (ctr_one == p.insn[22]));
    // On the CTR alone, known when queued: resolved.
    if (p.insn[25] && !p.insn[23])
      predict = ctr_one == p.insn[22];
    bo_ok = (p.insn[25:21] <= 5'd20) && (p.insn[24:22] != 3'b011) &&
            (p.insn[24:22] != 3'b111);
    xl_ok = (p.insn[15:11] == 5'd0) && bo_ok &&
            ((p.insn[10:1] == 10'd16) || ((p.insn[10:1] == 10'd528) && p.insn[23]));
    return !trace && (p.fault == FETCH_OK) &&
      ((p.insn[31:26] == 6'd18) || ((p.insn[31:26] == 6'd16) && predict) ||
       ((p.insn[31:26] == 6'd19) && xl_ok && predict && (p.insn[10] ? ctr_ok : lr_ok)));
  endfunction
  function automatic logic waits(fetch_packet_t p, logic lr_ok, logic lk_ok, logic ctr_ok,
                                 logic ctr_dec_ok);
    logic bc, bclr, bcctr;
    bc = p.insn[31:26] == 6'd16;
    bclr = (p.insn[31:26] == 6'd19) && (p.insn[10:1] == 10'd16);
    bcctr = (p.insn[31:26] == 6'd19) && (p.insn[10:1] == 10'd528);
    return (p.fault == FETCH_OK) &&
      ((bclr && !lr_ok) || (bcctr && !ctr_ok) ||
       ((bc || bclr || bcctr) && ((!p.insn[23] && !ctr_dec_ok) || (p.insn[0] && !lk_ok))));
  endfunction
  function automatic logic cr_branch(fetch_packet_t p, logic ctr_known, logic ctr_one);
    return (p.fault == FETCH_OK) && !p.insn[25] &&
      !(!p.insn[23] && ctr_known && (ctr_one ^ p.insn[22])) &&
      ((p.insn[31:26] == 6'd16) ||
       ((p.insn[31:26] == 6'd19) && ((p.insn[10:1] == 10'd16) || (p.insn[10:1] == 10'd528))));
  endfunction
  function automatic logic selected_cr_bit(input logic [4:0] bi,
                                            input logic capture,
                                            input logic field_valid,
                                            input logic [2:0] field,
                                            input logic [31:0] committed,
                                            input logic [31:0] previous,
                                            input logic [3:0] incoming);
    return capture ?
      ((field_valid && (field == bi[4:2])) ? incoming[2'd3 - bi[1:0]] :
                                           committed[5'd31 - bi]) :
      previous[5'd31 - bi];
  endfunction
  function automatic logic [31:0] folded_target(input logic [31:0] pc,
                                                 input logic [31:0] insn,
                                                 input logic [31:2] lr_target,
                                                 input logic [31:2] ctr_target);
    return (insn[31:26] == 6'd19) ?
      {(insn[10] ? ctr_target : lr_target), 2'b00} :
      (insn[1] ? 32'b0 : pc) +
      ((insn[31:26] == 6'd18) ?
        {{6{insn[25]}}, insn[25:2], 2'b00} :
        {{16{insn[15]}}, insn[15:2], 2'b00});
  endfunction
  assign fd_bypass = !FETCH_DECODE_REG && !fd_valid_q;
  assign fd_valid = fd_bypass ? fetch_valid : fd_valid_q;
  assign fd_packet = fd_bypass ? fetched : fd_packet_q;
  assign queued = iabr_check(fd_packet, iabr);
  assign cr0_now = selected_cr_bit(queued.insn[20:16], bu_cr_capture,
    owner_crf_valid_q, owner_crf_q, cr, bu_cr, owner_cr0);
  assign fold_predict = folds(queued, trace_mode, lr_ok, ctr_free, cr_final, cr0_now, ctr_one) &&
    !wait0;
  assign wait0 = waits(queued, lr_ok, lk_free, ctr_free, ctr_fe_ok);
  assign crb0 = cr_branch(queued, ctr_fe_ok, ctr_one);
  assign wait0_cr = crb0 && cr_unres;
  assign cr_hold0 = fd_valid && wait0_cr;
  assign fd_push = fd_valid && !fold_q && !fstop_q && !cr_hold0;
  assign fd_split_q = fd_push && fd_push_ok_q && fd1_valid_q && hold1_cr;
  assign rel_fold = held_q && fd_valid_q && fd_push && fd_push_ok_q && fold_predict &&
                    !frontend_clear && !early_q;
  assign fetch_ready = !frontend_clear && !fold_q && !fstop_q && !rel_fold &&
    (fd_bypass || (!cr_hold0 && !fd_split_q && (!fd_valid_q || fd_push_ok_q)));
  assign fold0_target = folded_target(queued.pc, queued.insn, lr_fold[31:2], ctr_arch);
'''
HEADER = r'''`timescale 1ns/1ps
module tb;
 typedef logic[2:0] fetch_fault_t;
 typedef logic[1:0] esa_enable_t;
 localparam logic[2:0] FETCH_OK=0,FETCH_IABR=5;
 typedef struct packed {logic[31:0]pc,insn;fetch_fault_t fault;esa_enable_t esa;}fetch_packet_t;
 logic ENABLE_DEBUG_EXCEPTIONS=1, FETCH_DECODE_REG;
 logic fetch_valid,fd_valid_q,fold_q,fstop_q,held_q,frontend_clear,early_q;
 logic fd_push_ok_q,fd1_valid_q,hold1_cr,cr_unres,trace_mode,lr_ok,ctr_free,cr_final,ctr_one,lk_free,ctr_fe_ok;
 logic bu_cr_capture,owner_crf_valid_q;logic[2:0]owner_crf_q;logic[31:0]cr,bu_cr,iabr,lr_fold;logic[3:0]owner_cr0;logic[31:2]ctr_arch;
 fetch_packet_t fetched,fd_packet_q;
 logic[3:0]v=4'bzx10; integer count=0, unknown_divergences=0;
 integer direct_count=0, target_checks[4]; logic[31:0] expected_target;
 function automatic logic f(input integer i);return v[i%4];endfunction
'''
TEST = r'''
 initial begin
 cr=32'h963ca56f;bu_cr=32'h8f00f01c;owner_cr0=4'h6;owner_crf_q=2;lr_fold=32'h1004;ctr_arch=30'h0800;
 for(integer cfg=0;cfg<2;cfg++) for(integer pat=0;pat<16;pat++) for(integer c=0;c<256;c++) for(integer bg=0;bg<4;bg++) for(integer q=0;q<4;q++)begin
 FETCH_DECODE_REG=cfg;fd_valid_q=f(q);held_q=f(c);fetch_valid=f(c/4);cr_unres=f(c/16);fd_push_ok_q=f(c/64);
 fold_q=f(bg);fstop_q=0;frontend_clear=0;early_q=0;fd1_valid_q=f(bg+1);hold1_cr=f(bg+2);
 trace_mode=0;lr_ok=f(bg);ctr_free=f(bg+1);cr_final=f(bg+2);ctr_one=f(bg+3);lk_free=1;ctr_fe_ok=1;bu_cr_capture=f(bg);owner_crf_valid_q=f(bg+1);
 fd_packet_q='0;fetched='0;fd_packet_q.pc=32'h1040;fetched.pc=32'h2074;iabr=32'h1042;
 case(pat%8)
 0:fd_packet_q.insn=32'h48000020;
 1:fd_packet_q.insn=32'h4182fff0;
 2:fd_packet_q.insn=32'h4e800020;
 3:fd_packet_q.insn=32'h4e800420;
 4:fd_packet_q.insn=32'h60000000;
 5:fd_packet_q.insn=32'h41820008;
 6:fd_packet_q.insn=32'hxxxxxxxx;
 7:fd_packet_q.insn=32'hzzzzzzzz;
 endcase
 fetched.insn=pat[0]?32'h60000000:32'h48000040;
 fd_packet_q.fault=pat<8?3'b000:3'bxxx;fetched.fault=pat[1]?3'b001:3'b000;
 #1;
 if(q<2)begin
  if(old_rel_fold!==new_rel_fold || old_fetch_ready!==new_fetch_ready)$fatal(1,"known-valid mismatch cfg%0d pat%0d c%0d bg%0d q%0d",cfg,pat,c,bg,q);
  if(new_rel_fold===1'b1 && old_fold0_target!==new_rel_target)$fatal(1,"qualified target mismatch");
 end else if(old_rel_fold!==new_rel_fold || old_fetch_ready!==new_fetch_ready)unknown_divergences++;
 count++;
 end
 // Dedicated known-state release cases; independent controls and IABR modes.
 // The finite equality matrix above deliberately retains its original counts.
 for(integer fam=0;fam<4;fam++) target_checks[fam]=0;
 for(integer cfg=0;cfg<2;cfg++) for(integer fam=0;fam<4;fam++) begin
  for(integer mode=0;mode<3;mode++)begin
   FETCH_DECODE_REG=cfg;fd_valid_q=1;held_q=1;fetch_valid=1;
   fold_q=0;fstop_q=0;frontend_clear=0;early_q=0;fd_push_ok_q=1;
   fd1_valid_q=0;hold1_cr=0;cr_unres=0;trace_mode=0;lr_ok=1;
   ctr_free=1;cr_final=1;ctr_one=0;lk_free=1;ctr_fe_ok=1;
   bu_cr_capture=0;owner_crf_valid_q=0;owner_crf_q=0;owner_cr0=0;
   cr=32'hffffffff;bu_cr=32'hffffffff;lr_fold=32'h00001200;ctr_arch=30'h000008c0;
   fd_packet_q='0;fetched='0;fd_packet_q.pc=32'h1040;fetched.pc=32'h3000;fetched.insn=32'h60000000;
   case(fam)
    0:begin fd_packet_q.insn=32'h48000020;expected_target=32'h1060;end
    1:begin fd_packet_q.insn=32'h41820030;expected_target=32'h1070;end
    2:begin fd_packet_q.insn=32'h4e800020;expected_target=32'h1200;end
    3:begin fd_packet_q.insn=32'h4e800420;expected_target=32'h2300;end
   endcase
   // Disabled compare, enabled nonmatch, enabled match (which inhibits fold).
   iabr=mode==0?32'h1040:mode==1?32'h1046:32'h1042;
   #1;
   if(old_rel_fold !== (mode<2) || new_rel_fold !== (mode<2))
    $fatal(1,"direct release qualification cfg%0d family%0d IABRmode%0d",cfg,fam,mode);
   if(old_fetch_ready!==new_fetch_ready)$fatal(1,"direct readiness mismatch");
   if(mode<2)begin
    if(old_fold0_target!==expected_target || new_rel_target!==expected_target)
     $fatal(1,"independent target mismatch cfg%0d family%0d",cfg,fam);
    target_checks[fam]++;
   end
   direct_count++;
  end
  // Independently inhibit a previously positive packet; do not mask each other.
  iabr=32'h1046;
  for(integer inhibit=0;inhibit<6;inhibit++)begin
   frontend_clear=0;early_q=0;fstop_q=0;fold_q=0;fd_push_ok_q=1;held_q=1;
   case(inhibit)
    0:frontend_clear=1;
    1:early_q=1;
    2:fstop_q=1;
    3:fd_push_ok_q=0;
    4:held_q=0;
    5:fold_q=1;
   endcase
   #1;
   if(old_rel_fold!==1'b0 || new_rel_fold!==1'b0)$fatal(1,"release inhibitor failed %0d",inhibit);
   if(old_fetch_ready!==new_fetch_ready)$fatal(1,"inhibited readiness mismatch");
   direct_count++;
  end
 end
 for(integer fam=0;fam<4;fam++)
  if(target_checks[fam]!=4)$fatal(1,"missing positive target coverage family%0d count%0d",fam,target_checks[fam]);
 if(direct_count!=72 || count!=131072)$fatal(1,"coverage count mismatch");
 $display("PASS bounded held release: matrix %0d (65536 known/65536 unknown), X/Z diagnostics %0d; directed %0d, target B=%0d BC=%0d BCLR=%0d BCCTR=%0d",count,unknown_divergences,direct_count,target_checks[0],target_checks[1],target_checks[2],target_checks[3]);$finish;
 end
 endmodule
'''

def compact(s):
    s = re.sub(r"//[^\n]*|/\*.*?\*/", "", s, flags=re.S)
    return re.sub(r"\s+", "", s)


def checked_types(pkg):
    # Header width substitutions are deliberate Icarus enum adapters. Reject
    # any actual packet layout or enum encoding changes before adapting them.
    expected = {
        "fetch_fault_t": "typedef enum logic [2:0] { FETCH_OK=3'd0, FETCH_ISI_PROTECTION=3'd1, FETCH_ISI_GUARDED=3'd2, FETCH_PAGE_MISS=3'd3, FETCH_MACHINE_CHECK=3'd4, FETCH_IABR=3'd5, FETCH_TEA_REPEAT=3'd6 } fetch_fault_t;",
        "esa_enable_t": "typedef enum logic [1:0] { ESA_DENIED=2'd0, ESA_ALLOWED=2'd1, ESA_PO_BASE=2'd2, ESA_PO_SER=2'd3 } esa_enable_t;",
        "fetch_packet_t": "typedef struct packed { logic [31:0] pc; logic [31:0] insn; fetch_fault_t fault; esa_enable_t esa; } fetch_packet_t;",
    }
    for name, oracle in expected.items():
        pattern = r"typedef (?:enum logic \[[^\]]*\] \{[^}]*\}|struct packed \{[^}]*\})\s*" + name + r"\s*;"
        candidates = re.findall(pattern, pkg, re.S)
        if len(candidates) != 1 or compact(candidates[0]) != compact(oracle):
            raise ValueError("package layout/encoding changed: " + name)


def actual_function(source, name):
    matches = re.findall(r"  function automatic [^;\n]*\b" + name + r"\s*\(.*?endfunction", source, re.S)
    if len(matches) != 1:
        raise ValueError("expected one helper: " + name)
    return matches[0]


def actual_assignment(source, name):
    matches = re.findall(r"  assign " + name + r"\s*=.*?;", source, re.S)
    if len(matches) != 1:
        raise ValueError("expected one continuous assignment: " + name)
    return matches[0]


def project(text, prefix, names):
    return re.sub(r"\b\w+\b", lambda m: prefix + "_" + m[0] if m[0] in names else m[0], text)


def prepare(core, pkg):
    checked_types(pkg)
    if "<<<<<<<" in core:
        raise ValueError("unresolved core merge")
    declarations = []
    bodies = []
    for prefix, names in [("old", COMMON), ("new", COMMON + EXTRA)]:
        for name in names:
            kind = "fetch_packet_t" if name in ["fd_packet", "queued", "held_word"] else "logic[31:0]" if name in ["fold0_target", "rel_target"] else "logic"
            declarations.append(f" {kind} {prefix}_{name};")
        helpers = [actual_function(REFERENCE_SOURCE if prefix == "old" else core, n) for n in FUNCTIONS]
        equations = [actual_assignment(REFERENCE_SOURCE if prefix == "old" else core, n) for n in names]
        bodies.extend(project(s, prefix, set(names + FUNCTIONS)) for s in helpers + equations)
    return HEADER + "\n".join(declarations + bodies) + TEST


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, required=True)
    parser.add_argument("--prepare-only", action="store_true", help="extract fixture without compiler/simulator")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    fixture = prepare((root / "rtl/ppc_core.sv").read_text(), (root / "rtl/ppc_pkg.sv").read_text())
    args.build_dir.mkdir(parents=True, exist_ok=True)
    source = args.build_dir / "held_release_fixture.sv"
    binary = args.build_dir / "held_release.vvp"
    source.write_text(fixture)
    if args.prepare_only:
        print("Prepared bounded actual-source held-release fixture; no compile/run")
        return
    try:
        subprocess.run(["iverilog", "-g2012", "-s", "tb", "-o", str(binary), str(source)], check=True, timeout=30)
        subprocess.run(["vvp", str(binary)], check=True, timeout=30)
    finally:
        binary.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
