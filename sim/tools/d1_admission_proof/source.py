# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Exact source inverses; rejects all unreviewed core/package revisions."""
import hashlib

def sha(text):
    return hashlib.sha256(text.encode()).hexdigest()

OLD = '8a717edfb0feea9cb3985613ea7e6ec79f8c7d0576e84b55bec3894ed979b8e4'
NEW = '91c2f994a1abb5b207e7c2d1e91aea494b98a9b78630620851da611be9046a95'
PKG = 'd2f9ebdc165a880507bead0c791f3fdabffc38a2dcef7e98f0338882e61dc7b6'
EDITS = [{'before': '  logic c0_sru, c0_iu, c0_branch, c0_lane, c0_move, c0_fp, c0_fp_mem, d1_valid, d1_iu, d1_mem, d1_fp;', 'after': '  logic c0_sru, c0_iu, c0_branch, c0_lane, c0_fp, c0_fp_mem, d1_valid, d1_iu, d1_mem, d1_fp;'}, {'before': '  logic d1_lsu, d1_lsu_ready, d1_base_wait, d1_wait_a, d1_wait_b;', 'after': '  logic d1_lsu, d1_base_wait, d1_wait_a, d1_wait_b;'}, {'before': '  logic pair_units, d1_iu_ready, d1_fp_ready;', 'after': "  logic d1_iu_ready, d1_fp_ready;\n  // DQ0 alignment changes only GPR/update permissions relevant to DQ1.\n  // Compute the dependent admission terms before the late alignment choice.\n  typedef struct packed {\n    logic move_allowed, reads_dst, pair_other, base_allowed, no_previous_base;\n    logic lsu_allowed, sources_ready, misaligned;\n    logic iu, lsu, gpr, update;\n    logic alloc0, alloc1, alloc2;\n  } d1_admission_context_t;\n  typedef struct packed {\n    logic move_ok, pair_ok, base_wait, lsu_ready, rename_ready, admit;\n  } d1_admission_t;\n  d1_admission_context_t d1_admission_context;\n  // One shared helper returns named intermediate predicates for source proofs.\n  // Hardware consumes actual.base_wait and pre/fault.admit; other fields prune.\n  /* verilator lint_off UNUSEDSIGNAL */\n  d1_admission_t d1_admission_actual, d1_admission_pre, d1_admission_fault;\n  /* verilator lint_on UNUSEDSIGNAL */\n  logic d1_admission_ok;\n  function automatic d1_admission_t d1_permissions(\n      input logic gpr_write, input logic mem_update,\n      input d1_admission_context_t c);\n    d1_admission_t r;\n    r.move_ok = c.move_allowed && !(gpr_write && c.reads_dst);\n    r.pair_ok = c.pair_other || (r.move_ok && c.iu);\n    r.base_wait = c.base_allowed &&\n      (c.no_previous_base || (gpr_write && !mem_update));\n    r.lsu_ready = c.lsu_allowed && (r.base_wait || !c.misaligned) &&\n      (r.base_wait || c.sources_ready);\n    r.rename_ready = (c.update && gpr_write) ? c.alloc2 :\n                     (gpr_write || c.update) ? c.alloc1 : c.alloc0;\n    r.admit = r.pair_ok && (!c.lsu || r.lsu_ready) && (!c.gpr || r.rename_ready);\n    return r;\n  endfunction\n  assign d1_admission_actual = d1_permissions(dispatch_uop.gpr_write,\n                                              dispatch_uop.mem_update, d1_admission_context);\n  assign d1_admission_pre = d1_permissions(sp_dispatch_uop.gpr_write,\n                                           sp_dispatch_uop.mem_update, d1_admission_context);\n  assign d1_admission_fault = d1_permissions(1'b0, 1'b0, d1_admission_context);\n  always_comb begin\n    d1_admission_ok = d1_admission_pre.admit;\n    // Match dispatch_base's procedural selector, including X/Z false.\n    if (dispatch_align) d1_admission_ok = d1_admission_fault.admit;\n  end\n"}, {'before': '  assign c0_move = special_uop && sru_move &&\n    !(dispatch_uop.gpr_write && reads_reg(dq1_uop, dispatch_uop.dst));', 'after': '  assign d1_admission_context.move_allowed = special_uop && sru_move;\n  assign d1_admission_context.reads_dst = reads_reg(dq1_uop, dispatch_uop.dst);'}, {'before': '  assign pair_units = ((c0_iu || c0_lane || c0_fp || c0_fp_mem) && d1_branch) ||\n    ((c0_iu || c0_branch) && d1_lsu) ||\n    (c0_iu && (d1_sru || (c0_sru && d1_iu) || d1_mem || d1_fp)) ||\n    (c0_branch && (d1_iu || d1_mem || d1_fp)) || (c0_lane && (d1_iu || d1_fp)) ||\n    (c0_move && d1_iu) ||\n    ((c0_fp || c0_fp_mem) && d1_iu);', 'after': '  assign d1_admission_context.pair_other = ((c0_iu || c0_lane || c0_fp || c0_fp_mem) && d1_branch) ||\n    ((c0_iu || c0_branch) && d1_lsu) ||\n    (c0_iu && (d1_sru || (c0_sru && d1_iu) || d1_mem || d1_fp)) ||\n    (c0_branch && (d1_iu || d1_mem || d1_fp)) || (c0_lane && (d1_iu || d1_fp)) ||\n    ((c0_fp || c0_fp_mem) && d1_iu);'}, {'before': '  assign d1_base_wait = (LSU_BASE_SNOOP || LSU_BASE_WAIT) && ENABLE_SUPERVISOR_EXCEPTIONS &&\n    ((dq1_uop.special_op == SPECIAL_LOAD) || (dq1_uop.special_op == SPECIAL_STORE)) &&\n    !dq1_uop.mem_update && (d1_wait_a != d1_wait_b) &&\n    (!(dq1_pair.dep_prev[0] || dq1_pair.dep_prev[1]) ||\n     (dispatch_uop.gpr_write && !dispatch_uop.mem_update));', 'after': '  assign d1_admission_context.base_allowed = (LSU_BASE_SNOOP || LSU_BASE_WAIT) && ENABLE_SUPERVISOR_EXCEPTIONS &&\n    ((dq1_uop.special_op == SPECIAL_LOAD) || (dq1_uop.special_op == SPECIAL_STORE)) &&\n    !dq1_uop.mem_update && (d1_wait_a != d1_wait_b);\n  assign d1_admission_context.no_previous_base = !(dq1_pair.dep_prev[0] || dq1_pair.dep_prev[1]);\n  assign d1_base_wait = d1_admission_actual.base_wait;'}, {'before': '  assign d1_lsu_ready = lsu_ready && lane_mem_idle && !fp_unsafe_pending &&\n    (d1_base_wait || !d1_misaligned) && !msr_le &&\n    (d1_base_wait || ((dq1_uop.zero_a || (src_a1.ready && !dq1_pair.dep_prev[0])) &&\n                      (dq1_uop.use_imm || (src_b1.ready && !dq1_pair.dep_prev[1]))));', 'after': '  assign d1_admission_context.lsu_allowed = lsu_ready && lane_mem_idle && !fp_unsafe_pending && !msr_le;\n  assign d1_admission_context.sources_ready =\n    (dq1_uop.zero_a || (src_a1.ready && !dq1_pair.dep_prev[0])) &&\n    (dq1_uop.use_imm || (src_b1.ready && !dq1_pair.dep_prev[1]));\n  assign d1_admission_context.misaligned = d1_misaligned;\n  assign d1_admission_context.iu = d1_iu;\n  assign d1_admission_context.lsu = d1_lsu;\n  assign d1_admission_context.gpr = d1_gpr;\n  assign d1_admission_context.update = unit_update;\n  assign d1_admission_context.alloc0 = alloc_ready;\n  assign d1_admission_context.alloc1 = alloc1_ready;\n  assign d1_admission_context.alloc2 = alloc2_ready;'}, {'before': '  assign dispatch1 = dispatch && seq_last && pair_units && (cq1_ready || d1_remove) &&\n    !(c0_carry && (!(d1_iu || d1_lsu) || c1_carry)) &&\n    !(c1_carry && ((bs_busy && !bs_hit) || fp_cr_pending ||\n      (bu_branch && bu_spec) || c0_fp || c0_fp_mem)) &&\n    // DQ1 needs only the renames left after DQ0 (UM 6.6.1.2). It does not\n    // read the base an update form in DQ0 writes.\n    (!unit_update || (d1_iu && !reads_reg(dq1_uop, uop.src_a))) &&\n    !sru_wait1 && !update_wait1 &&\n    (!d1_lsu || d1_lsu_ready) &&\n    (!flags_tok1 || (!flags_waiter && (!cr_wait1 || (cr_wait_ok1 && !cr_wait0)))) &&\n    (!d1_needs_flags || xer_ready1) &&\n    (!d1_gpr || (update_load ? alloc2_ready :\n                 (dispatch_uop.gpr_write || unit_update) ? alloc1_ready : alloc_ready)) &&\n    (!d1_iu || d1_iu_ready) && (!d1_mem || d1_mem_ready) && (!d1_fp || d1_fp_ready);', 'after': '  assign dispatch1 = dispatch && seq_last && d1_admission_ok && (cq1_ready || d1_remove) &&\n    !(c0_carry && (!(d1_iu || d1_lsu) || c1_carry)) &&\n    !(c1_carry && ((bs_busy && !bs_hit) || fp_cr_pending ||\n      (bu_branch && bu_spec) || c0_fp || c0_fp_mem)) &&\n    // DQ1 needs only the renames left after DQ0 (UM 6.6.1.2). It does not\n    // read the base an update form in DQ0 writes.\n    (!unit_update || (d1_iu && !reads_reg(dq1_uop, uop.src_a))) &&\n    !sru_wait1 && !update_wait1 &&\n    (!flags_tok1 || (!flags_waiter && (!cr_wait1 || (cr_wait_ok1 && !cr_wait0)))) &&\n    (!d1_needs_flags || xer_ready1) &&\n    (!d1_iu || d1_iu_ready) && (!d1_mem || d1_mem_ready) && (!d1_fp || d1_fp_ready);'}]

def validate(core, package):
    assert sha(core) == NEW, 'unreviewed actual core'
    assert sha(package) == PKG, 'unreviewed package/type closure'
    old = core
    assert len(EDITS) == 8
    for edit in reversed(EDITS):
        assert old.count(edit['after']) == 1, 'inverse fragment shape'
        old = old.replace(edit['after'], edit['before'], 1)
    assert sha(old) == OLD, 'whole-core inverse failed'
    return old

def load(root):
    core = (root / 'rtl/ppc_core.sv').read_text()
    package = (root / 'rtl/ppc_pkg.sv').read_text()
    if sha(core) == NEW:
        return validate(core, package), core, package
    from d1_special_port1_views import load_views, negative_guards
    views = load_views(root)
    count = negative_guards(views)
    print('COMPOSITION SOURCE PASS actual=' + sha(core) + ' D1-view=' + sha(views['d1_core']) +
          ' P1-view=' + sha(views['port1_core']) + ' source-negative-guards=' + str(count), flush=True)
    return views['baseline_core'], views['d1_core'], views['package']

def negative_guards(core, package):
    # SOURCE rejection checks, not behavioral counterexamples. The fixtures
    # separately execute three deliberately incorrect semantic alternatives.
    mutations = [
        ('helper', 'r.move_ok = c.move_allowed &&', 'r.move_ok = c.move_allowed ||'),
        ('actual call', 'd1_permissions(dispatch_uop.gpr_write,', 'd1_permissions(!dispatch_uop.gpr_write,'),
        ('pre call', 'd1_permissions(sp_dispatch_uop.gpr_write,', 'd1_permissions(!sp_dispatch_uop.gpr_write,'),
        ('fault call', "d1_permissions(1'b0, 1'b0,", "d1_permissions(1'b1, 1'b0,"),
        ('context', 'd1_admission_context.move_allowed = special_uop &&', 'd1_admission_context.move_allowed = special_uop ||'),
        ('priority', "dispatch_align = 1'b0;", "dispatch_align = 1'b1;"),
        ('branch', "r.gpr_write = 1'b0;", "r.gpr_write = 1'b1;"),
        ('dispatch', 'seq_last && d1_admission_ok &&', 'seq_last && !d1_admission_ok &&'),
    ]
    checks = []
    for name, before, after in mutations:
        assert core.count(before) == 1, ('mutation shape', name)
        checks.append((name, core.replace(before, after, 1), package))
    assert package.count('logic [2:0] dep_prev;') == 1
    checks.append(('package type', core, package.replace('logic [2:0] dep_prev;', 'logic [3:0] dep_prev;', 1)))
    for name, altered_core, altered_package in checks:
        try:
            validate(altered_core, altered_package)
        except AssertionError:
            continue
        raise AssertionError('accepted source mutation: ' + name)
    assert len(checks) == 9
    return len(checks)
