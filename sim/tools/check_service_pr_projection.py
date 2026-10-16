#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Guard actual BAT-PR candidate; prepare original-router and minimal enum fixtures.

This tool does not run HDL. The optional Icarus test proves accepted input/capture
congruence over bounded four-state vectors; the actual router pair compares public
outputs and complete BAT state under independent runtime-BAT protocol stimuli.
Source drift requires review and explicit re-pinning, never automatic acceptance.
"""
from pathlib import Path
import argparse, hashlib, json, re
ROOT = Path(__file__).resolve().parents[2]
OLD = '  assign service_pr = !bat_setup_q &&\n    ((csr_offer && bat_csr_req_valid_i) ? context_pr_q : request_pr_q);\n'
NEW = "  // PR follows the registered request source, like the other BAT payload.\n  // CSR arbitration qualifies valid; it need not select translation data.\n  always_comb begin\n    // Preserve the original merge when the request source is unknown.\n    service_pr = !bat_setup_q &&\n      ((csr_offer && bat_csr_req_valid_i) ? context_pr_q : request_pr_q);\n    case (bat_setup_q)\n      1'b1: service_pr = 1'b0;\n      1'b0: begin\n        case (state_q == ROUTE_TRANSLATE_OFFER)\n          1'b1: service_pr = 1'b1 && request_pr_q;\n          1'b0: service_pr = 1'b1 && context_pr_q;\n          default: begin end // service_pr unknown route-state fallback\n        endcase\n      end\n      default: begin end // service_pr unknown setup-state fallback\n    endcase\n  end\n"
PINS = {'rtl/ppc_bat_service.sv': '3dc84d3c3da95ad1f3dc28059e56eab175ba2e6f68636eb40507a150863cf169', 'rtl/ppc_bat_translate.sv': '3d5de4422d7f07b705dca0153f4226767fe7c370d95c249eb643f33a902206d5', 'rtl/ppc_pkg.sv': '64897d2f8bff3dbc6e0247f6b89d773eb80627bedfe6397173870a81964d58ee', 'tb/tb_service_pr_payload.sv': '3baf51a4402ae6b92ed191525982db0e38d933f96fd013ea77e1e258e86fc0ab', 'tb/tb_service_pr_router_pair.sv': '5d24ff6f401d161ec6d13738f2a5ee3d29c7bb959144e5b70240e511d53a03ae'}
CANDIDATE = 'bb7a2462c983e846bf2529515b9349fb7010d93bb41c8bdbe6fb93af0f9a452a'
ORIGINAL = '3babfeeed856bae59a544a48f13ff4ab80c7ead00c1dc55b2302bf515092d18c'
def digest(s): return hashlib.sha256(s.encode()).hexdigest()
# Metadata companions do not participate in the BAT privilege proof. Accept
# only these reviewed literal additions, then require the unchanged full-file
# identity below. The generated independent old router has no hint ports; the
# actual candidate DUT ties hint inputs to zero and leaves hint output unused.
# This projection does not prove metadata transport or enabled fetch behavior.
METADATA_SOURCES = {'rtl/ppc_bat_memory_router.sv': 'd5584fdde7ae11b80eeab08c6dedb4a7eee20849533d8773b3e614d21fe24cd6', 'rtl/ppc_pkg.sv': 'd2f9ebdc165a880507bead0c791f3fdabffc38a2dcef7e98f0338882e61dc7b6', 'tb/tb_service_pr_router_pair.sv': 'fa7bb6ebf128db0abc50907d800a912303ab8d6986fee7531e06d29a5f0b59b0'}
METADATA_EDITS = {'rtl/ppc_bat_memory_router.sv': [('', '  input  logic [3*FETCH_WIDTH-1:0] phys_imem_rsp_hints_i,\n'), ('', '  output logic [3*FETCH_WIDTH-1:0] imem_rsp_hints_o,\n'), ("  always_comb begin\n    imem_rsp_insn = pimem_rsp_insn_i;\n    if (i_state_q == LANE_RESPONSE) begin\n      // With machine check enabled, i_refetch is the only discard case.\n      if (i_refetch) imem_rsp_insn = pimem_rsp_insn_i;\n      else if (ENABLE_MACHINE_CHECK && (pimem_rsp_error_i || i_refetch_q))\n        imem_rsp_insn = '0;\n    end else if (state_q == ROUTE_IFETCH_FAULT_RESPONSE) begin\n      imem_rsp_insn = '0;\n    end\n  end\n", "  always_comb begin\n    imem_rsp_insn = pimem_rsp_insn_i;\n    imem_rsp_hints_o = phys_imem_rsp_hints_i;\n    if (i_state_q == LANE_RESPONSE) begin\n      // With machine check enabled, i_refetch is the only discard case.\n      if (i_refetch) begin\n        imem_rsp_insn = pimem_rsp_insn_i;\n        imem_rsp_hints_o = phys_imem_rsp_hints_i;\n      end else if (ENABLE_MACHINE_CHECK && (pimem_rsp_error_i || i_refetch_q)) begin\n        imem_rsp_insn = '0;\n        imem_rsp_hints_o = '0;\n      end\n    end else if (state_q == ROUTE_IFETCH_FAULT_RESPONSE) begin\n      imem_rsp_insn = '0;\n      imem_rsp_hints_o = '0;\n    end\n  end\n")], 'rtl/ppc_pkg.sv': [('', '\n  /* verilator lint_off UNUSEDSIGNAL */\n  // Takes the CR rename, or writes CR from the FPU.\n  function automatic logic cr_writer(uop_t u);\n    return !u.illegal && (u.write_cr_field || u.write_cr_fields || u.write_cr_bit ||\n      ((u.needs_flags || u.write_xer) && !(!u.write_xer && (u.write_ca || u.write_ov_so))));\n  endfunction\n  /* verilator lint_on UNUSEDSIGNAL */\n'), ('', '  // Per-word transport: {CR rename demand, branch class, needs primary IU}.\n  typedef struct packed {\n    logic cr_writer;\n    fetch_lookahead_t lookahead;\n  } fetch_hint_t;\n')], 'tb/tb_service_pr_router_pair.sv': [('', "    .phys_imem_rsp_hints_i('0),\n    .imem_rsp_hints_o(),\n\n")]}
def pr_source(file):
    text=(ROOT/file).read_text()
    if file not in METADATA_EDITS:
        return text
    expected=CANDIDATE if file=='rtl/ppc_bat_memory_router.sv' else PINS[file]
    if digest(text)==expected:
        return text
    assert digest(text)==METADATA_SOURCES[file], 'unreviewed metadata source drift: '+file
    for original,addition in METADATA_EDITS[file]:
        assert text.count(addition)==1, 'metadata projection shape changed: '+file
        text=text.replace(addition,original)
    assert digest(text)==expected, 'metadata inverse does not recover fixed BAT-PR source: '+file
    return text

def section(s, start, end):
    assert s.count(start)==1 and s.count(end)==1, (start,end)
    return s[s.index(start):s.index(end)]
def enum(s, name):
    values=re.findall(r'  typedef enum logic \[[^\]]+\] \{[^}]+\} '+name+r';',s)
    assert len(values)==1,name
    return values[0]
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    for file,expected in PINS.items():
        assert digest(pr_source(file))==expected, 'source drift: '+file
    router=pr_source('rtl/ppc_bat_memory_router.sv')
    assert digest(router)==CANDIDATE,'live router is not the reviewed normalized candidate'
    assert router.count(NEW)==1 and OLD not in router,'candidate projection shape changed'
    original=router.replace(NEW,OLD)
    assert digest(original)==ORIGINAL,'inverse projection does not recover frozen independent baseline'
    payload=(ROOT/'tb/tb_service_pr_payload.sv').read_text()
    pair=pr_source('tb/tb_service_pr_router_pair.sv')
    service=(ROOT/'rtl/ppc_bat_service.sv').read_text()
    pkg=pr_source('rtl/ppc_pkg.sv')
    # Actual source linkage, not merely a hand-written equivalent expression.
    chunks={
      'slot_admission':section(router,'  assign slot_free =','  assign slot_grant[SLOT_BAT_CSR]'),
      'request_source':section(router,'  always_comb begin\n    bat_req_valid =','  ppc_segment_registers #('),
      'slot_constants':section(router,'  localparam int SLOT_BAT_CSR =','  owner_t owner_q;'),
      'candidate_pr':NEW,
    }
    for name in ('route_state_t','lane_state_t','owner_t'):
        chunks[name]=enum(router,name)
    for name in ('req_ready_o','request_fire','transaction_idle_o'):
        values=re.findall(r'  assign '+name+r' = [\s\S]*?;',service)
        assert len(values)==1,name
        chunks[name]=values[0]
    for name,actual in chunks.items():
        assert payload.count(actual)==1,'payload source extraction drift: '+name
    # Independent legacy equation is frozen, never derived from NEW.
    assert payload.count('  assign old_pr=!bat_setup_q&&((csr_offer&&bat_csr_req_valid_i)?context_pr_q:request_pr_q);')==1
    assert 'if(vectors!=122690||' in payload
    assert 'logic [2:0] bat_req_kind; // width-identical raw enum carrier' in payload
    kind=enum(pkg,'bat_req_kind_t')
    assert 'typedef enum logic [2:0]' in kind
    outputs=re.findall(r'^\s*output\s+[^\n,;]*?\b(\w+_o)\s*[,\n]',router[:router.index('  import ppc_pkg::*;')],re.M)
    assert len(outputs)==94 and len(set(outputs))==94,'public interface drift'
    for name in outputs:
        assert pair.count('if(dut.'+name+'!==trial.'+name+')')==1,'missing public pair output '+name
    assert pair.count('ppc_bat_memory_router_original #(')==1
    assert pair.count('ppc_bat_memory_router #(')==1
    assert original.count('module ppc_bat_memory_router #(')==1
    renamed=original.replace('module ppc_bat_memory_router #(','module ppc_bat_memory_router_original #(')
    assert renamed.replace('module ppc_bat_memory_router_original #(','module ppc_bat_memory_router #(')==original
    args.output.mkdir(parents=True,exist_ok=True)
    (args.output/'ppc_bat_memory_router_original.sv').write_text(renamed)
    (args.output/'ppc_pkg.sv').write_text('// SPDX-License-Identifier: GPL-2.0-or-later\n// Copyright (c) 2026 Kevin Dedon\n// Actual enum only; full production package hash guarded above.\npackage ppc_pkg;\n'+kind+'\nendpackage\n')
    (args.output/'source.json').write_text(json.dumps({'candidate':CANDIDATE,'inverse_original':ORIGINAL,'pins':PINS,'extracted':{n:digest(t) for n,t in chunks.items()},'public_outputs':outputs,'scope':'bounded four-state accepted input tuple plus separate actual-router temporal pair; preparation is not HDL acceptance'},indent=2)+'\n')
    print('Prepared guarded original router and actual BAT enum; no HDL compile/simulation performed')
if __name__=='__main__': main()
