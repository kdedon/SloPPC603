# SPDX-License-Identifier: MIT
"""Standalone PowerPC FP result model layered over exact integer arithmetic."""
from reference import B32, B64, calculate, decode, pack_ratio

DEFAULT_NAN = 0x7ff8000000000000
SNAN, ISI, IDI, ZDZ, IMZ, VC, SOFT, SQRT, CVI = (1 << bit for bit in range(9))


def classify(bits, fmt=B64):
    kind, sign, significand, _ = decode(bits, fmt)
    if kind in ('snan', 'qnan'):
        return 0b10001
    if kind == 'inf':
        return 0b01001 if sign else 0b00101
    if not significand:
        return 0b10010 if sign else 0b00010
    exponent = (bits >> fmt.fraction) & ((1 << fmt.exponent) - 1)
    if not exponent:
        return 0b11000 if sign else 0b10100
    return 0b01000 if sign else 0b00100


def _top(n, d, exponent):
    bit = n.bit_length() - d.bit_length()
    if (n < d << bit) if bit >= 0 else (n << -bit < d):
        bit -= 1
    return bit + exponent


def _unbounded_round(n, d, exponent, sign, rn, precision):
    quantum = _top(n, d, exponent) - precision + 1
    shift = exponent - quantum
    scaled_n = n << shift if shift >= 0 else n
    scaled_d = d if shift >= 0 else d << -shift
    mantissa, remainder = divmod(scaled_n, scaled_d)
    inexact = bool(remainder)
    increment = inexact and ((rn == 0 and (2 * remainder > scaled_d or
                 (2 * remainder == scaled_d and mantissa & 1))) or
                 (rn == 2 and not sign) or (rn == 3 and sign))
    mantissa += increment
    if mantissa.bit_length() > precision:
        mantissa >>= 1
        quantum += 1
    return mantissa, quantum, inexact, bool(increment)


def _finite(op, a, b, c, rn):
    ka, sa, ma, ea = decode(a)
    kb, sb, mb, eb = decode(b)
    kc, sc, mc, ec = decode(c)
    if op in ('add', 'sub'):
        if op == 'sub':
            sb ^= 1
        exponent = min(ea, eb)
        value = ((-ma if sa else ma) << (ea - exponent)) + ((-mb if sb else mb) << (eb - exponent))
        return abs(value), 1, exponent, int(value < 0) if value else sa if sa == sb else int(rn == 3)
    if op == 'mul':
        return ma * mc, 1, ea + ec, sa ^ sc
    if op == 'div':
        return ma, mb, ea - eb, sa ^ sb
    subtract_b = op in ('msub', 'nmsub')
    sb ^= subtract_b
    sp = sa ^ sc
    exponent = min(ea + ec, eb)
    product = ma * mc << (ea + ec - exponent)
    addend = mb << (eb - exponent)
    value = (-product if sp else product) + (-addend if sb else addend)
    return abs(value), 1, exponent, int(value < 0) if value else sp if sp == sb else int(rn == 3)


def arithmetic(op, a, b=0, c=0, rn=0, single=False, ni=False,
               ve=False, oe=False, ue=False, ze=False):
    """Return raw FPR result and exception metadata for one FP operation.

    Single operations take binary32-exact FPR operands and round directly to
    binary32 before exact widening. Estimates are checked by bounds elsewhere.
    """
    out = dict(result=0, write_result=True, invalid=0, ox=False, ux=False,
               zx=False, xx=False, fr=False, fi=False, frfi_valid=True,
               fprf=0, fprf_valid=False, fpcc=0, compare_valid=False,
               tiny_before_round=False)
    relevant = (a, b) if op not in ('frsp', 'fctiw', 'fctiwz', 'mul') else (b,)
    if op == 'mul':
        relevant = (a, c)
    if op in ('madd', 'msub', 'nmadd', 'nmsub'):
        relevant = (a, b, c)
    if op in ('cmpu', 'cmpo'):
        ka, sa, ma, ea = decode(a)
        kb, sb, mb, eb = decode(b)
        if ka in ('snan', 'qnan') or kb in ('snan', 'qnan'):
            out['fpcc'] = 0b0001
            has_snan = 'snan' in (ka, kb)
            out['invalid'] = SNAN if has_snan else 0
            if op == 'cmpo' and (not has_snan or not ve):
                out['invalid'] |= VC
        else:
            cmp = calculate('cmp', a, b)
            out['fpcc'] = (0b0010, 0b1000, 0b0100)[cmp['bits']]
        out['compare_valid'] = True
        out['write_result'] = False
        out['frfi_valid'] = False
        return out
    for operand in relevant:
        if decode(operand)[0] == 'snan':
            out['invalid'] |= SNAN
    ka, sa, ma, _ = decode(a)
    kb, sb, mb, _ = decode(b)
    kc, sc, mc, _ = decode(c)
    if op in ('mul', 'madd', 'msub', 'nmadd', 'nmsub'):
        if (ka == 'inf' and kc == 'finite' and not mc) or (kc == 'inf' and ka == 'finite' and not ma):
            out['invalid'] |= IMZ
    if op in ('add', 'sub') and ka == kb == 'inf' and (sa != sb if op == 'add' else sa == sb):
        out['invalid'] |= ISI
    if op in ('madd', 'msub', 'nmadd', 'nmsub') and (ka == 'inf' or kc == 'inf') and kb == 'inf' and not (out['invalid'] & IMZ):
        product_sign = sa ^ sc
        addend_sign = sb ^ (op in ('msub', 'nmsub'))
        if product_sign != addend_sign:
            out['invalid'] |= ISI
    if op == 'div' and ka == kb == 'inf':
        out['invalid'] |= IDI
    if op == 'div' and ka == kb == 'finite' and not ma and not mb:
        out['invalid'] |= ZDZ
    nan = next((v for v in relevant if decode(v)[0] in ('snan', 'qnan')), None)
    if op in ('fctiw', 'fctiwz'):
        source = b
        kind, sign, _, _ = decode(source)
        rounded = calculate('ftoi32', source, 0, 1 if op == 'fctiwz' else rn)
        if rounded['invalid']:
            out['invalid'] |= CVI
            word = 0x80000000 if kind in ('snan', 'qnan') or sign else 0x7fffffff
        else:
            word = rounded['bits']
            out['xx'] = rounded['nx']
            out['fi'] = rounded['nx']
            out['fr'] = rounded['increment']
        out['result'] = word
        out['frfi_valid'] = True
        out['write_result'] = not (ve and out['invalid'])
        return out
    if nan is not None:
        out['result'] = nan | (1 << 51)
        if op == 'frsp':
            out['result'] &= ~((1 << 29) - 1)
        out['write_result'] = not (ve and out['invalid'])
        out['fprf'] = classify(out['result'])
        out['fprf_valid'] = out['write_result']
        return out
    if op == 'frsp' and kb == 'inf':
        out['result'] = b
        out['fprf'] = classify(b)
        out['fprf_valid'] = True
        return out
    if op == 'frsp':
        n, d, exponent, sign = _finite('mul', b, 0, 0x3ff0000000000000, rn)
    elif op in ('add', 'sub', 'mul', 'div', 'madd', 'msub', 'nmadd', 'nmsub'):
        ka, sa, ma, _ = decode(a)
        kb, sb, mb, _ = decode(b)
        kc, sc, _, _ = decode(c)
        if op == 'div':
            if ka == kb == 'inf':
                out['invalid'] |= IDI
            elif ka == kb == 'finite' and not ma and not mb:
                out['invalid'] |= ZDZ
            elif ka == 'finite' and ma and kb == 'finite' and not mb:
                out['zx'] = True
                out['result'] = ((sa ^ sb) << 63) | B64.infinity
                out['write_result'] = not ze
                out['fprf'] = classify(out['result'])
                out['fprf_valid'] = out['write_result']
                out['frfi_valid'] = True
                return out
        elif op == 'mul' or op in ('madd', 'msub', 'nmadd', 'nmsub'):
            multiply_kind, multiply_mantissa = (kc, decode(c)[2])
            if (ka == 'inf' and multiply_kind == 'finite' and not multiply_mantissa) or (multiply_kind == 'inf' and ka == 'finite' and not ma):
                out['invalid'] |= IMZ
        elif op in ('add', 'sub') and ka == kb == 'inf' and (sa != sb if op == 'add' else sa == sb):
            out['invalid'] |= ISI
        if out['invalid']:
            out['result'] = DEFAULT_NAN
            out['write_result'] = not ve
            out['fprf'] = classify(out['result'])
            out['fprf_valid'] = out['write_result']
            out['frfi_valid'] = True
            return out
        if any(decode(v)[0] == 'inf' for v in relevant):
            # Finite tests use the exact-rational path below; specials stay raw.
            from reference import calculate_fma
            if op in ('madd', 'msub', 'nmadd', 'nmsub'):
                result = calculate_fma(a, c, b, rn, negate_addend=op in ('msub', 'nmsub'))
            else:
                result = calculate(op, a, c if op == 'mul' else b, rn)
            out['result'] = result['bits']
            if op in ('nmadd', 'nmsub') and decode(out['result'])[0] not in ('snan', 'qnan'):
                out['result'] ^= 1 << 63
            out['fprf'] = classify(out['result'])
            out['fprf_valid'] = True
            return out
        n, d, exponent, sign = _finite(op, a, b, c, rn)
    else:
        raise ValueError(op)
    fmt = B32 if single or op == 'frsp' else B64
    if n:
        out['ux'] = _top(n, d, exponent) < 1 - fmt.bias and ue
    bits, nx, uf_after, overflow, increment = pack_ratio(n, d, exponent, sign, rn, fmt)
    tiny = bool(n) and _top(n, d, exponent) < 1 - fmt.bias
    out['tiny_before_round'] = tiny
    out['ux'] = tiny and (ue or nx)
    out['ox'] = overflow
    out['xx'] = nx or (overflow and not oe)
    out['fi'] = bool(nx) or (overflow and not oe)
    out['fr'] = bool(increment)
    out['frfi_valid'] = True
    if (overflow and oe) or (tiny and ue):
        mantissa, quantum, inexact, increment = _unbounded_round(n, d, exponent, sign, rn, fmt.fraction + 1)
        adjustment = (192 if fmt == B32 else 1536) * (-1 if overflow else 1)
        adjusted = pack_ratio(mantissa, 1, quantum + adjustment, sign, 0, B64)[0]
        if op in ('nmadd', 'nmsub'):
            adjusted ^= 1 << 63
        out['xx'] = inexact
        out['fi'] = inexact
        out['fr'] = increment
        out['result'] = adjusted
        out['fprf'] = classify(adjusted)
        out['fprf_valid'] = True
        return out
    flush_subnormal = ni and (bits & fmt.infinity) == 0 and bool(bits & ((1 << fmt.fraction) - 1))
    if flush_subnormal:
        bits &= 1 << fmt.signbit
    if op in ('nmadd', 'nmsub'):
        bits ^= 1 << fmt.signbit
    out['fprf'] = classify(bits, fmt)
    if fmt == B32:
        bits = calculate('to64', bits, 0, fmt=B32)['bits']
    out['result'] = bits
    out['fprf_valid'] = True
    return out
