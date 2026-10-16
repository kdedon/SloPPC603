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
NEW = "  // PR follows the registered request source, like the other BAT payload.\n  // CSR arbitration qualifies valid; it need not select translation data.\n  always_comb begin\n    // Preserve the original merge when the request source is unknown.\n    service_pr = !bat_setup_q &&\n      ((csr_offer && bat_csr_req_valid_i) ? context_pr_q : request_pr_q);\n    case (bat_setup_q)\n      1'b1: service_pr = 1'b0;\n      1'b0: begin\n        case (state_q == ROUTE_TRANSLATE_OFFER)\n          1'b1: service_pr = 1'b1 && request_pr_q;\n          1'b0: service_pr = 1'b1 && context_pr_q;\n          default: begin end\n        endcase\n      end\n      default: begin end\n    endcase\n  end\n"
PINS = {'rtl/ppc_bat_service.sv': '3dc84d3c3da95ad1f3dc28059e56eab175ba2e6f68636eb40507a150863cf169', 'rtl/ppc_bat_translate.sv': '3d5de4422d7f07b705dca0153f4226767fe7c370d95c249eb643f33a902206d5', 'rtl/ppc_pkg.sv': '64897d2f8bff3dbc6e0247f6b89d773eb80627bedfe6397173870a81964d58ee', 'tb/tb_service_pr_payload.sv': '3233a409d745b3493314fc98a21a4a0e03e0f5185aa9f369e2ff286891b87608', 'tb/tb_service_pr_router_pair.sv': '5d24ff6f401d161ec6d13738f2a5ee3d29c7bb959144e5b70240e511d53a03ae'}
CANDIDATE = 'd4cc15f25e90d41642156fd7a3ddbe0924c96fa6363d7bf1a91777e68f042c7b'
ORIGINAL = '3babfeeed856bae59a544a48f13ff4ab80c7ead00c1dc55b2302bf515092d18c'
def digest(s): return hashlib.sha256(s.encode()).hexdigest()
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
        assert hashlib.sha256((ROOT/file).read_bytes()).hexdigest()==expected, 'source drift: '+file
    router=(ROOT/'rtl/ppc_bat_memory_router.sv').read_text()
    assert digest(router)==CANDIDATE,'live router is not the reviewed normalized candidate'
    assert router.count(NEW)==1 and OLD not in router,'candidate projection shape changed'
    original=router.replace(NEW,OLD)
    assert digest(original)==ORIGINAL,'inverse projection does not recover frozen independent baseline'
    payload=(ROOT/'tb/tb_service_pr_payload.sv').read_text()
    pair=(ROOT/'tb/tb_service_pr_router_pair.sv').read_text()
    service=(ROOT/'rtl/ppc_bat_service.sv').read_text()
    pkg=(ROOT/'rtl/ppc_pkg.sv').read_text()
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
