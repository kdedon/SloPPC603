# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Cross-check the PowerPC model against Berkeley TestFloat/SoftFloat.

testfloat_gen, built by fetch-softfloat.sh with a PowerPC specialization
(positive default QNaN, PEM §3.3.1.7; first-NaN propagation; tininess before
rounding, PEM §3.3.6.2.2; fctiw saturation, PEM `fctiwx` and §D.4.2),
supplies operands, IEEE results and flags. Each case is mapped to PowerPC semantics, checked against ppc_reference.arithmetic with
all FPSCR enables clear, and written as an arithmetic-bench vector carrying
the model's expected result, so the RTL is checked on the same operands.

Explicit PowerPC mappings (cases counted per rule, never silently skipped):
  nan-rule   A NaN result is the first NaN of frA, frB, frC quieted, else the
             default QNaN (PEM §3.3.1.7, Figures 3-16-17).
  nan-order  The same rule where SoftFloat differs: it orders fused operands
             as product factors first, so its frC precedes frB.
  imz-qnan   Infinity times zero plus a QNaN returns that QNaN with VXIMZ;
             IEEE returns the default NaN (PEM §3.3.6.1.1).
  negate     fnmadd/fnmsub negate a non-NaN result after rounding
             (PEM §4.2.2.2, `fnmaddx`); fmsub/fnmsub negate frB, the IEEE addend.
  compare    fcmpu/fcmpo set one FPCC bit; eq and lt are checked against the
             matching bit, quiet compares raise VXSNAN only for an SNaN,
             ordered compares also VXVC for a QNaN (PEM §4.2.2.4, `fcmpox`).
Any other difference in result bits or the five IEEE flags is a mismatch.
"""
import argparse
from collections import Counter
from pathlib import Path
import subprocess
import sys

from ppc_reference import arithmetic, SNAN, IMZ
from production_vectors import OPS
from production_vectors_602 import widen_raw

FIELDS = ('result', 'write_result', 'invalid', 'ox', 'ux', 'zx', 'xx',
          'fr', 'fi', 'frfi_valid', 'fprf', 'fprf_valid', 'fpcc',
          'compare_valid', 'tiny_before_round')
ROUND = (('rnear_even', 0), ('rminMag', 1), ('rmax', 2), ('rmin', 3))
SIGN = 1 << 63
QUIET = 1 << 51


def is_nan(bits):
    return (bits >> 52) & 0x7ff == 0x7ff and bits & ((1 << 52) - 1)


def is_inf(bits):
    return bits & ~SIGN == 0x7ff0000000000000


def is_zero(bits):
    return bits & ~SIGN == 0


def ppc_nan(ops):
    return next((v | QUIET for v in ops if is_nan(v)), 0x7ff8000000000000)


def sf_flags(flags):
    """TestFloat flag byte: inexact, underflow, overflow, infinite, invalid."""
    return dict(xx=bool(flags & 1), ux=bool(flags & 2), ox=bool(flags & 4),
                zx=bool(flags & 8), invalid=bool(flags & 16))


def jobs(personality):
    """(testfloat function, rounding options, precision) per corpus."""
    if personality == '602':
        precisions = ('f32',)
    else:
        precisions = ('f64', 'f32')
    for p in precisions:
        for fn in ('add', 'sub', 'mul', 'div', 'mulAdd'):
            for rm in ROUND:
                yield f'{p}_{fn}', rm, p
    if personality == '603e':
        for rm in ROUND:
            yield 'f64_to_f32', rm, 'f64'
        for rm in ROUND:
            yield 'f64_to_i32', rm, 'f64'
    else:
        yield 'f32_to_i32', ROUND[1], 'f32'
    for p in precisions:
        for fn in ('eq', 'lt_quiet', 'lt'):
            yield f'{p}_{fn}', ROUND[0], p


def cases(fn, sf, p):
    """Map one TestFloat case to PowerPC (op, a, b, c, expected, rule)."""
    w = widen_raw if p == 'f32' else (lambda x: x)
    if fn.endswith(('_eq', '_lt_quiet', '_lt')):
        a, b, truth, flags = sf
        op = 'cmpo' if fn.endswith('_lt') else 'cmpu'
        yield op, w(a), w(b), 0, (fn.split('_', 1)[1], truth, flags), 'compare'
        return
    if fn.endswith('_to_i32'):
        x, z, flags = sf
        yield 'fctiw', 0, w(x), 0, (z, flags), 'direct'
        return
    if fn == 'f64_to_f32':
        x, z, flags = sf
        yield 'frsp', 0, x, 0, (widen_raw(z), flags), 'direct'
        return
    if fn.endswith('_mulAdd'):
        x, y, s, z, flags = sf
        a, c, b = w(x), w(y), w(s)
        z = w(z)
        for op, neg_b, neg_z in (('madd', 0, 0), ('msub', 1, 0),
                                 ('nmadd', 0, 1), ('nmsub', 1, 1)):
            bb = b ^ (SIGN if neg_b else 0)
            if is_nan(z):
                imz = is_nan(bb) and ((is_inf(a) and is_zero(c)) or
                                      (is_inf(c) and is_zero(a)))
                if imz:
                    rule = 'imz-qnan'
                elif z != ppc_nan((a, b, c)):
                    rule = 'nan-order'
                else:
                    rule = 'nan-rule'
                yield op, a, bb, c, (ppc_nan((a, bb, c)), flags), rule
            else:
                yield op, a, bb, c, (z ^ (SIGN if neg_z else 0), flags), \
                    'negate' if neg_b or neg_z else 'direct'
        return
    x, y, z, flags = sf
    op = fn.split('_')[1]
    a, other = w(x), w(y)
    z = w(z)
    b, c = (0, other) if op == 'mul' else (other, 0)
    if is_nan(z):
        yield op, a, b, c, (ppc_nan((a, other)), flags), 'nan-rule'
    else:
        yield op, a, b, c, (z, flags), 'direct'


def check(op, rn, exp, want, rule):
    """Return a list of field names where the model differs from TestFloat."""
    diffs = []
    if rule == 'compare':
        kind, truth, flags = want
        bit = 0b0010 if kind == 'eq' else 0b1000
        if bool(exp['fpcc'] & bit) != bool(truth):
            diffs.append('fpcc')
        invalid = exp['invalid'] if op == 'cmpo' else exp['invalid'] & SNAN
        if bool(invalid) != sf_flags(flags)['invalid']:
            diffs.append('invalid')
        return diffs
    value, flags = want
    got = exp['result'] & (0xffffffff if op == 'fctiw' else (1 << 64) - 1)
    if got != value:
        diffs.append('result')
    ieee = sf_flags(flags)
    model = dict(xx=exp['xx'], ux=exp['ux'], ox=exp['ox'], zx=exp['zx'],
                 invalid=bool(exp['invalid']))
    if rule == 'imz-qnan' and not exp['invalid'] & IMZ:
        diffs.append('vximz')
    diffs.extend(k for k in ieee if ieee[k] != bool(model[k]))
    return diffs


def stream(gen, fn, rm, stride):
    args = [gen, '-tininessbefore', f'-{rm}', fn]
    if fn.endswith('_to_i32'):
        args.insert(1, '-exact')
    with subprocess.Popen(args, stdout=subprocess.PIPE, text=True) as proc:
        for index, line in enumerate(proc.stdout):
            if index % stride == 0:
                yield tuple(int(t, 16) for t in line.split())


def generate(gen, personality, path, stride, fused_stride, limit_show):
    counts = Counter()
    rules = Counter()
    mismatches = []
    rows = 0
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('w') as out:
        for fn, (rm, rn), p in jobs(personality):
            step = fused_stride if fn.endswith('_mulAdd') else stride
            if fn.endswith(('_to_f32', '_to_i32')) or '_eq' in fn or '_lt' in fn:
                step = 1
            single = p == 'f32'
            for sf in stream(gen, fn, rm, step):
                for op, a, b, c, want, rule in cases(fn, sf, p):
                    ops = [(op, rn)]
                    if op == 'fctiw':
                        ops = ([] if personality == '602' else [('fctiw', rn)])
                        if rn == 1:
                            ops.append(('fctiwz', 0))
                    for op_name, op_rn in ops:
                        arith_single = single and op_name not in (
                            'fctiw', 'fctiwz', 'cmpu', 'cmpo')
                        exp = arithmetic(op_name, a, b, c, op_rn, arith_single)
                        diffs = check('fctiw' if op_name == 'fctiwz' else op_name,
                                      op_rn, exp, want, rule)
                        key = f'{op_name}.{p}'
                        counts[key] += 1
                        rules[rule] += 1
                        if diffs:
                            mismatches.append((key, rm, a, b, c, want, diffs))
                        mask = 0 if not exp['write_result'] else (
                            0xffffffff if op_name in ('fctiw', 'fctiwz')
                            else (1 << 64) - 1)
                        fields = (OPS[op_name], a, b, c, op_rn, int(arith_single),
                                  0, 0, 0, 0, 0)
                        values = fields + tuple(exp[k] for k in FIELDS) + (mask,)
                        out.write(' '.join(format(int(v), 'x') for v in values) + '\n')
                        rows += 1
    for key in sorted(counts):
        bad = sum(1 for m in mismatches if m[0] == key)
        print(f'TESTFLOAT_OP {key} vectors={counts[key]} mismatches={bad}')
    print('TESTFLOAT_RULES ' + ' '.join(f'{k}={v}' for k, v in sorted(rules.items())))
    for key, rm, a, b, c, want, diffs in mismatches[:limit_show]:
        print(f'TESTFLOAT_MISMATCH {key} {rm} a={a:016x} b={b:016x} c={c:016x} '
              f'want={want} fields={",".join(diffs)}')
    print(f'TESTFLOAT_CORPUS personality={personality} stride={stride} '
          f'fused_stride={fused_stride} vectors={rows} model_mismatches={len(mismatches)}')
    return not mismatches


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--gen', type=Path, required=True)
    parser.add_argument('--vectors', type=Path, required=True)
    parser.add_argument('--personality', choices=('603e', '602'), default='603e')
    parser.add_argument('--stride', type=int, default=1)
    parser.add_argument('--fused-stride', type=int, default=613)
    parser.add_argument('--show', type=int, default=40)
    args = parser.parse_args()
    sys.exit(0 if generate(args.gen, args.personality, args.vectors,
                           args.stride, args.fused_stride, args.show) else 1)
