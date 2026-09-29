# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
"""Exact integer IEEE binary32/binary64 oracle, version 1.

All finite values are signed integers times powers of two. Rounding happens once
at the destination boundary. No host floating-point or DUT helpers are used.
"""
from dataclasses import dataclass


@dataclass(frozen=True)
class Format:
    fraction: int
    exponent: int
    bias: int

    @property
    def signbit(self):
        return self.fraction + self.exponent

    @property
    def infinity(self):
        return ((1 << self.exponent) - 1) << self.fraction


B32 = Format(23, 8, 127)
B64 = Format(52, 11, 1023)


def decode(bits, fmt=B64):
    sign = bits >> fmt.signbit
    exponent = (bits >> fmt.fraction) & ((1 << fmt.exponent) - 1)
    fraction = bits & ((1 << fmt.fraction) - 1)
    if exponent == (1 << fmt.exponent) - 1:
        kind = 'snan' if fraction and not (fraction >> (fmt.fraction - 1)) else 'qnan' if fraction else 'inf'
        return kind, sign, fraction, 0
    significand = fraction | ((1 << fmt.fraction) if exponent else 0)
    return 'finite', sign, significand, (exponent or 1) - fmt.bias - fmt.fraction


def rounded_integer(n, shift, sign, rn):
    if shift <= 0:
        return n << -shift, False, False
    quotient, remainder = divmod(n, 1 << shift)
    increment = bool(remainder) and ((rn == 0 and (remainder * 2 > (1 << shift) or (remainder * 2 == (1 << shift) and quotient & 1))) or (rn == 2 and not sign) or (rn == 3 and sign))
    return quotient + increment, bool(remainder), increment


def pack(n, exponent, sign, rn, fmt=B64):
    """Return raw bits, NX, UF, OF, rounded-away-from-zero."""
    if not n:
        return sign << fmt.signbit, False, False, False, False
    top = n.bit_length() - 1 + exponent
    quantum = max(top - fmt.fraction, 1 - fmt.bias - fmt.fraction)
    mantissa, nx, increment = rounded_integer(n, quantum - exponent, sign, rn)
    if mantissa.bit_length() > fmt.fraction + 1:
        mantissa >>= 1
        quantum += 1
    result_exp = quantum + fmt.fraction + fmt.bias
    if result_exp >= (1 << fmt.exponent) - 1:
        to_inf = rn == 0 or (rn == 2 and not sign) or (rn == 3 and sign)
        return (sign << fmt.signbit) | (fmt.infinity if to_inf else fmt.infinity - 1), True, False, True, to_inf
    subnormal = mantissa < (1 << fmt.fraction)
    encoded_exp = 0 if subnormal else result_exp
    return (sign << fmt.signbit) | (encoded_exp << fmt.fraction) | (mantissa & ((1 << fmt.fraction) - 1)), nx, nx and subnormal, False, increment


def pack_ratio(numerator, denominator, exponent, sign, rn, fmt=B64):
    """Round an exact positive rational scaled by a power of two."""
    if not numerator:
        return sign << fmt.signbit, False, False, False, False
    top = numerator.bit_length() - denominator.bit_length()
    if (numerator < denominator << top) if top >= 0 else (numerator << -top < denominator):
        top -= 1
    top += exponent
    quantum = max(top - fmt.fraction, 1 - fmt.bias - fmt.fraction)
    shift = exponent - quantum
    scaled_n = numerator << shift if shift >= 0 else numerator
    scaled_d = denominator if shift >= 0 else denominator << -shift
    mantissa, remainder = divmod(scaled_n, scaled_d)
    nx = bool(remainder)
    increment = nx and ((rn == 0 and (2 * remainder > scaled_d or (2 * remainder == scaled_d and mantissa & 1)))
                        or (rn == 2 and not sign) or (rn == 3 and sign))
    mantissa += increment
    if mantissa.bit_length() > fmt.fraction + 1:
        mantissa >>= 1
        quantum += 1
    result_exp = quantum + fmt.fraction + fmt.bias
    if result_exp >= (1 << fmt.exponent) - 1:
        to_inf = rn == 0 or (rn == 2 and not sign) or (rn == 3 and sign)
        return (sign << fmt.signbit) | (fmt.infinity if to_inf else fmt.infinity - 1), True, False, True, to_inf
    subnormal = mantissa < (1 << fmt.fraction)
    encoded_exp = 0 if subnormal else result_exp
    return (sign << fmt.signbit) | (encoded_exp << fmt.fraction) | (mantissa & ((1 << fmt.fraction) - 1)), nx, nx and subnormal, False, increment


def calculate(op, a, b, rn=0, fmt=B64):
    """Operations add/sub/mul/div/cmp/to32/to64/i32tof/ftoi32.

    Result dictionary carries raw result and independent IEEE exception flags.
    NaN choice is first operand, quieted; integer invalid returns 0x80000000.
    """
    ka, sa, ma, ea = decode(a, fmt)
    kb, sb, mb, eb = decode(b, fmt)
    invalid = ka == 'snan' or kb == 'snan'
    out = dict(bits=0, nx=False, uf=False, of=False, dz=False, invalid=False, increment=False)
    if op == 'i32tof':
        value = a & 0xffffffff
        value = value - (1 << 32) if value >> 31 else value
        raw = pack(abs(value), 0, int(value < 0), rn, fmt)
    elif op == 'cmp':
        if 'nan' in ka or 'nan' in kb:
            out.update(bits=3, invalid=invalid)
            return out
        if ka == 'inf' or kb == 'inf':
            va = (-2 if sa else 2) if ka == 'inf' else (-1 if sa else 1) if ma else 0
            vb = (-2 if sb else 2) if kb == 'inf' else (-1 if sb else 1) if mb else 0
        else:
            exponent = min(ea, eb)
            va = (-ma if sa else ma) << (ea - exponent)
            vb = (-mb if sb else mb) << (eb - exponent)
        out['bits'] = 1 if va < vb else 2 if va > vb else 0
        return out
    elif op == 'ftoi32':
        if ka != 'finite':
            out.update(bits=0x80000000, invalid=True)
            return out
        value, nx, inc = rounded_integer(ma, -ea, sa, rn)
        value = -value if sa else value
        if not -(1 << 31) <= value < (1 << 31):
            out.update(bits=0x80000000, invalid=True)
        else:
            out.update(bits=value & 0xffffffff, nx=nx, increment=inc)
        return out
    elif op in ('to32', 'to64'):
        dest = B32 if op == 'to32' else B64
        if 'nan' in ka:
            payload = ma >> (fmt.fraction - dest.fraction) if fmt.fraction >= dest.fraction else ma << (dest.fraction - fmt.fraction)
            out.update(bits=(sa << dest.signbit) | dest.infinity | payload | (1 << (dest.fraction - 1)), invalid=ka == 'snan')
            return out
        if ka == 'inf':
            out['bits'] = (sa << dest.signbit) | dest.infinity
            return out
        raw = pack(ma, ea, sa, rn, dest)
    else:
        if 'nan' in ka or 'nan' in kb:
            selected = a if 'nan' in ka else b
            out.update(bits=selected | (1 << (fmt.fraction - 1)), invalid=invalid)
            return out
        if op == 'sub':
            sb ^= 1
        if op in ('add', 'sub'):
            if ka == 'inf' and kb == 'inf' and sa != sb:
                out.update(bits=fmt.infinity | (1 << (fmt.fraction - 1)), invalid=True)
                return out
            if ka == 'inf' or kb == 'inf':
                out['bits'] = ((sa if ka == 'inf' else sb) << fmt.signbit) | fmt.infinity
                return out
            exponent = min(ea, eb)
            value = ((-ma if sa else ma) << (ea - exponent)) + ((-mb if sb else mb) << (eb - exponent))
            sign = int(value < 0) if value else sa if sa == sb else int(rn == 3)
            raw = pack(abs(value), exponent, sign, rn, fmt)
        elif op in ('mul', 'div'):
            if op == 'div':
                if (ka == 'inf' and kb == 'inf') or (ka == 'finite' and not ma and kb == 'finite' and not mb):
                    out.update(bits=fmt.infinity | (1 << (fmt.fraction - 1)), invalid=True)
                    return out
                if ka == 'finite' and ma and kb == 'finite' and not mb:
                    out.update(bits=((sa ^ sb) << fmt.signbit) | fmt.infinity, dz=True)
                    return out
                if ka == 'inf' or kb == 'inf':
                    out['bits'] = ((sa ^ sb) << fmt.signbit) | (fmt.infinity if ka == 'inf' else 0)
                    return out
                raw = pack_ratio(ma, mb, ea - eb, sa ^ sb, rn, fmt)
                out.update(zip(('bits', 'nx', 'uf', 'of', 'increment'), raw))
                return out
            if (ka == 'inf' and kb == 'finite' and not mb) or (kb == 'inf' and ka == 'finite' and not ma):
                out.update(bits=fmt.infinity | (1 << (fmt.fraction - 1)), invalid=True)
                return out
            if ka == 'inf' or kb == 'inf':
                out['bits'] = ((sa ^ sb) << fmt.signbit) | fmt.infinity
                return out
            raw = pack(ma * mb, ea + eb, sa ^ sb, rn, fmt)
        else:
            raise ValueError(op)
    out.update(zip(('bits', 'nx', 'uf', 'of', 'increment'), raw))
    return out


def calculate_fma(a, b, c, rn=0, fmt=B64, negate_product=False, negate_addend=False):
    """Fuse an exact product and addend, rounding only the final sum."""
    decoded = [decode(bits, fmt) for bits in (a, b, c)]
    out = dict(bits=0, nx=False, uf=False, of=False, dz=False, invalid=False, increment=False)
    out['invalid'] = any(kind == 'snan' for kind, _, _, _ in decoded)
    for bits, (kind, _, _, _) in zip((a, b, c), decoded):
        if kind in ('snan', 'qnan'):
            out['bits'] = bits | (1 << (fmt.fraction - 1))
            return out
    (ka, sa, ma, ea), (kb, sb, mb, eb), (kc, sc, mc, ec) = decoded
    sp = sa ^ sb ^ negate_product
    sc ^= negate_addend
    if (ka == 'inf' and kb == 'finite' and not mb) or (kb == 'inf' and ka == 'finite' and not ma):
        out.update(bits=fmt.infinity | (1 << (fmt.fraction - 1)), invalid=True)
        return out
    if ka == 'inf' or kb == 'inf':
        if kc == 'inf' and sp != sc:
            out.update(bits=fmt.infinity | (1 << (fmt.fraction - 1)), invalid=True)
        else:
            out['bits'] = (sp << fmt.signbit) | fmt.infinity
        return out
    if kc == 'inf':
        out['bits'] = (sc << fmt.signbit) | fmt.infinity
        return out
    exponent = min(ea + eb, ec)
    product = ma * mb << (ea + eb - exponent)
    addend = mc << (ec - exponent)
    value = (-product if sp else product) + (-addend if sc else addend)
    sign = int(value < 0) if value else sp if sp == sc else int(rn == 3)
    raw = pack(abs(value), exponent, sign, rn, fmt)
    out.update(zip(('bits', 'nx', 'uf', 'of', 'increment'), raw))
    return out
