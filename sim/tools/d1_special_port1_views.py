# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Exact two-cut source views, not a general rebase/normalization facility."""
import hashlib
import re
from d1_admission_proof.source import EDITS as D1_EDITS, validate as validate_d1

PINS = {'baseline_core': '8a717edfb0feea9cb3985613ea7e6ec79f8c7d0576e84b55bec3894ed979b8e4',
 'combined_core': 'c6e1730703054c274fe4f08e79350e1457608d1adeebe2d0c9559444e48bd6a6',
 'd1_core': '91c2f994a1abb5b207e7c2d1e91aea494b98a9b78630620851da611be9046a95',
 'old_special': '1d8c5e51a6ccfc4285b6855c56c7c1b56196766882431afb8b5a9a93b455aef5',
 'package': 'd2f9ebdc165a880507bead0c791f3fdabffc38a2dcef7e98f0338882e61dc7b6',
 'port1_core': '7d07b701c6c9ef7b372c6df3f021b03f520cbce4dfacafa22670ed2606efea47',
 'special': 'dc1750ae0e67cdd50da76c3903a33ba2e77020f02059ebe7267e93d74c3b6ca0'}
P1_EDITS = [{'after': '  logic special_late;\n', 'before': '  logic special_port1_ok, special_late;\n'},
 {'after': '    .result_select_o(special_result_select),\n'
           '    /* verilator lint_off PINCONNECTEMPTY */\n'
           '    .result_port1_o(),\n'
           '    /* verilator lint_on PINCONNECTEMPTY */\n'
           '    .result_port1_offer_o(special_port1_offer),\n',
  'before': '    .result_select_o(special_result_select), .result_port1_o(special_port1_ok),\n'},
 {'after': '  logic special_port1, special_port1_sel, special_port1_offer;\n',
  'before': '  logic special_port1, special_port1_sel;\n'},
 {'after': '  assign special_port1 = special_port1_sel && special_port1_offer;\n',
  'before': '  assign special_port1 = special_port1_sel && special_result_valid && '
            'special_port1_ok;\n'}]

def sha(s):
    return hashlib.sha256(s.encode()).hexdigest()

def require_actual_core(core):
    assert sha(core) == PINS['combined_core'], 'unknown actual combined core'

def inverse(text, edits):
    for edit in reversed(edits):
        assert text.count(edit['after']) == 1, 'exact inverse fragment shape'
        text = text.replace(edit['after'], edit['before'], 1)
    return text

def between(text, start, end):
    assert text.count(start) == text.count(end) == 1, (start, end)
    return text[text.index(start):text.index(end)]

def function(text, name):
    matches = re.findall(r'  function automatic [^\n]*\b'+name+r'\b.*?  endfunction', text, re.S)
    assert len(matches) == 1, name
    return matches[0]

def assign(text, name):
    matches = re.findall(r'  assign '+re.escape(name)+r' = .*?;', text, re.S)
    assert len(matches) == 1, name
    return matches[0]

def actual_authority(core, d1, p1, old):
    # Check actual equations before using either proof view. No body is rebuilt
    # from a presumed equivalent hand-written formula in these comparisons.
    for name in ('d1_permissions', 'branch_resolved', 'reads_reg'):
        assert function(core, name) == function(d1, name), name
    for name in ('d1_admission_actual', 'd1_admission_pre', 'd1_admission_fault',
                 'dispatch1', 'rename0_dq1', 'rename1_dq1', 'rename2_dq1',
                 'd1_base_wait', 'unit_update', 'update_load'):
        assert assign(core, name) == assign(d1, name), name
    selector=lambda s: re.findall(r'  always_comb begin\n    d1_admission_ok =.*?\n  end',s,re.S)
    assert len(selector(core)) == 1 and selector(core) == selector(d1)
    contexts = lambda s: re.findall(r'  assign d1_admission_context\.\w+ =\s*.*?;', s, re.S)
    assert len(contexts(core)) == 15 and contexts(core) == contexts(d1)
    for start, end in (
        ('  typedef struct packed {\n    logic move_allowed', '  d1_admission_context_t d1_admission_context;'),

        ('  always_comb begin\n    dispatch_pre = uop;', '\n  // The alignment fault depends'),
        ('  always_comb begin\n    dispatch_base = dispatch_pre;', '\n  // A branch resolved')):
        assert between(core, start, end) == between(d1, start, end), start
    cancel_start='  // Classify held identities without depending on cancel-masked valid signals.'
    cancel_end='  // Without the test redirect or branch speculation every recovery is the'
    cancel=between(core,cancel_start,cancel_end)
    assert cancel == between(d1,cancel_start,cancel_end) == between(p1,cancel_start,cancel_end) == between(old,cancel_start,cancel_end)
    for name in ('rs_cancel','iu_cancel','sru_rs_cancel','sru_cancel','special_kill','fault_killed','sru_hold_kill'):
        # Complete actual seven-writer authority, not an assumed implication.
        assert len(re.findall(r'\b'+name+r'\s*=',core)) == 2, name
        assert len(re.findall(r'\b'+name+r'\s*=',cancel)) == 2, name
    assert assign(core,'special_cancel') == assign(old,'special_cancel')
    # The port1 cofactor proof owns the one changed product; the entire actual
    # arbiter, ready/offer/wake/payload context must be identical to its view.
    assert between(core,'  assign lsu_port0 =',cancel_start) == between(p1,'  assign lsu_port0 =',cancel_start)
    special_instance=lambda s: re.findall(r'  ppc_special #\(.*?\n  \);',s,re.S)
    assert len(special_instance(core)) == 1
    assert special_instance(core) == special_instance(p1)
    assert len(re.findall(r'\balways_ff\b',core)) == len(re.findall(r'\balways_ff\b',old))

def validate_sources(core, special, package):
    require_actual_core(core)
    assert sha(special) == PINS['special'], 'actual special source drift'
    assert sha(package) == PINS['package'], 'actual package/types drift'
    d1=inverse(core,P1_EDITS)
    assert sha(d1) == PINS['d1_core']
    old=validate_d1(d1,package)
    assert sha(old) == PINS['baseline_core']
    p1=inverse(core,D1_EDITS)
    assert sha(p1) == PINS['port1_core']
    assert inverse(p1,P1_EDITS) == old, 'two inverse orders disagree'
    actual_authority(core,d1,p1,old)
    # Existing special proof also checks the exact offer/result/state inverse.
    from check_special_port1_offer import OFFER_BLOCK, PORT_DECL
    assert special.count(OFFER_BLOCK) == special.count(PORT_DECL) == 1
    old_special=special.replace(OFFER_BLOCK,'').replace(PORT_DECL,'')
    assert sha(old_special) == PINS['old_special']
    result_start="    result_o = '0;"
    result_end='  // tw/twi TO bits'
    assert between(special,result_start,result_end) == between(old_special,result_start,result_end)
    return dict(actual_core=core, d1_core=d1, port1_core=p1, baseline_core=old,
                actual_special=special, baseline_special=old_special, package=package)

def load_views(root):
    core=(root/'rtl/ppc_core.sv').read_text()
    require_actual_core(core)  # Reject an unknown route before reading dependencies.
    return validate_sources(core,(root/'rtl/ppc_special.sv').read_text(),
                            (root/'rtl/ppc_pkg.sv').read_text())

def negative_guards(views):
    core=views['actual_core'];sp=views['actual_special'];pkg=views['package']
    mutations=[('unrelated core',core+'\n',sp,pkg),
        ('helper',core.replace('r.move_ok = c.move_allowed &&','r.move_ok = c.move_allowed ||',1),sp,pkg),
        ('cancel authority',core.replace("iu_cancel = 1'b0;","iu_cancel = 1'b1;",1),sp,pkg),
        ('port1 product',core.replace('special_port1_sel && special_port1_offer','!special_port1_sel && special_port1_offer',1),sp,pkg),
        ('special validity',core,sp.replace("result_valid_o = 1'b0;","result_valid_o = 1'b1;",1),pkg),
        ('package types',core,sp,pkg+'\n')]
    for name,co,se,pa in mutations:
        assert (co,se,pa) != (core,sp,pkg), name
        try:
            validate_sources(co,se,pa)
        except AssertionError:
            continue
        raise AssertionError('source mutation escaped: '+name)
    return len(mutations)
