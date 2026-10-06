#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Converts the Amiga Quake PowerPC sources from vasm syntax to GNU as:
positional macro parameters (\\1) become named ones, '$' as the location
counter becomes '.', .rodata becomes a section, and the local labels
(.name, scoped between global labels) get a unique suffix per scope. The
output is otherwise line for line the input.

--le adapts the sources to little-endian mode, where a double's low word is
at its address and its high word at +4: within each function or macro, a
load or store narrower than a doubleword into a doubleword that lfd/stfd
also address moves to the mirrored offset in it (stfd at X, lwz at X+4
becomes lwz at X), a two-word .long constant (a double written as two
words in hex) swaps its words, and a word load or store of a pair of
halfwords (HALF_PAIRS) rotates the word by 16 so each halfword keeps its
address.

Usage: asmconv.py [--le] in.s out.s"""
import re
import sys

POS = re.compile(r'\\([1-9])')
LOCAL_DEF = re.compile(r'^(\s*)(\.[A-Za-z_]\w*):')
SCOPE = re.compile(r'^\s*(funcdef|glab)\s|^[A-Za-z_]\w*:')


def convert_macros(lines):
    out, i = [], 0
    while i < len(lines):
        m = re.match(r'^(\s*)\.macro\s+(\w+)\s*(#.*)?$', lines[i])
        if not m:
            out.append(lines[i])
            i += 1
            continue
        end = i + 1
        while not re.match(r'^\s*\.endm\b', lines[end]):
            end += 1
        body = lines[i + 1:end]
        count = max([int(n) for line in body for n in POS.findall(line.split('#')[0])] or [0])
        params = ','.join(f'a{n}' for n in range(1, count + 1))
        out.append(f'{m.group(1)}.macro {m.group(2)} {params}'.rstrip() +
                   (f'\t{m.group(3)}' if m.group(3) else ''))
        for line in body:
            code, sep, comment = line.partition('#')
            code = POS.sub(r'\\a\1\\()', code).replace('$-', '.-')
            out.append(code + sep + comment)
        out.append(lines[end])
        i = end + 1
    return out


def scope_labels(lines):
    scopes, current = [], []
    for line in lines:
        if SCOPE.match(line) and current:
            scopes.append(current)
            current = []
        current.append(line)
    scopes.append(current)
    out = []
    for n, scope in enumerate(scopes):
        names = {m.group(2) for m in map(LOCAL_DEF.match, scope) if m}
        if not names:
            out += scope
            continue
        pat = re.compile(r'(?<![\w.])(' + '|'.join(re.escape(x) for x in sorted(names, key=len, reverse=True))
                         + r')(?!\w)')
        for line in scope:
            code, sep, comment = line.partition('#')
            m = LOCAL_DEF.match(code)
            if m:
                code = f'{m.group(1)}.L{m.group(2)[1:]}_{n}:' + code[m.end():]
                head, rest = code.split(':', 1)
                code = head + ':' + pat.sub(lambda x: f'.L{x.group(1)[1:]}_{n}', rest)
            else:
                lead = re.match(r'^(\s*\S+)(.*)$', code)
                if lead:
                    code = lead.group(1) + pat.sub(lambda x: f'.L{x.group(1)[1:]}_{n}', lead.group(2))
            out.append(code + sep + comment)
    return out


MEM = re.compile(r'^(\s*)(lfdu?|stfdu?|lwzu?|stwu?|lhzu?|lhau?|sthu?|lbzu?|stbu?|lfsu?|stfsu?)'
                 r'(\s+[\w\\()]+,\s*)((?:[^,()]|\\\(\))*)\((r\d+)\)(.*)$')
SIZE = {'lfd': 8, 'stfd': 8, 'lwz': 4, 'stw': 4, 'lfs': 4, 'stfs': 4, 'lhz': 2, 'lha': 2, 'sth': 2,
        'lbz': 1, 'stb': 1}
NUM = re.compile(r'(0x[0-9a-fA-F]+|\d+)(\*(0x[0-9a-fA-F]+|\d+))*')
HEX = re.compile(r'0x[0-9a-fA-F]+')
# Struct members of two shorts that the sources move as one word.
HALF_PAIRS = {'MSURFACE_TEXTUREMINS', 'MSURFACE_EXTENTS', 'EDGE_SURFS'}


def split_offset(text):
    """'local+dbl2int_tmp1+4' -> (('+local', '+dbl2int_tmp1'), 4)."""
    syms, num = [], 0
    for sign, term in re.findall(r'([+-]?)\s*([^+-]+)', text.replace(' ', '')):
        if NUM.fullmatch(term):
            v = 1
            for f in term.split('*'):
                v *= int(f, 0)
            num += -v if sign == '-' else v
        else:
            syms.append((sign or '+') + term)
    return tuple(syms), num


def join_offset(syms, num):
    text = ''.join(syms).lstrip('+')
    return text + (f'{num:+d}' if num else '') if text else str(num)


def little_endian(lines, path):
    scopes, current = [], []
    for line in lines:
        if re.match(r'^\s*(funcdef\s|\.macro\s)', line) and current:
            scopes.append(current)
            current = []
        current.append(line)
    scopes.append(current)
    out = []
    for scope in scopes:
        slots = set()
        for line in scope:
            m = MEM.match(line.partition('#')[0])
            if m and SIZE[m.group(2).rstrip('u')] == 8:
                syms, num = split_offset(m.group(4))
                slots.add((m.group(5), tuple(sorted(syms)), num))
        for line in scope:
            code, sep, comment = line.partition('#')
            m = MEM.match(code)
            size = m and SIZE[m.group(2).rstrip('u')]
            if m and size < 8:
                syms, num = split_offset(m.group(4))
                key = (m.group(5), tuple(sorted(syms)))
                base = [s[2] for s in slots if s[:2] == key and 0 <= num - s[2] < 8]
                if base:
                    new = 2 * base[0] + 8 - size - num
                    code = m.group(1) + m.group(2) + m.group(3) + join_offset(syms, new) + \
                        f'({m.group(5)})' + m.group(6)
                    print(f'{path}: {line.strip()} -> {code.strip()}', file=sys.stderr)
            if m and m.group(2) in ('lwz', 'stw') and m.group(4).strip() in HALF_PAIRS:
                reg = m.group(3).strip().rstrip(',').strip()
                rot = f'rotlwi {reg},{reg},16'
                code = code.rstrip() + f'; {rot}' if m.group(2) == 'lwz' else \
                    f'{m.group(1)}{rot}; ' + code.strip() + f'; {rot}'
                print(f'{path}: {line.strip()} -> {code.strip()}', file=sys.stderr)
            d = re.match(r'^(\s*\.long\s+)([^,\s]+)\s*,\s*([^,\s]+)(\s*)$', code)
            if d and HEX.fullmatch(d.group(2)) and HEX.fullmatch(d.group(3)):
                code = f'{d.group(1)}{d.group(3)},{d.group(2)}{d.group(4)}'
                print(f'{path}: {line.strip()} -> {code.strip()}', file=sys.stderr)
            out.append(code + sep + comment)
    return out


def main(argv):
    le = argv[:1] == ['--le']
    argv = argv[le:]
    if len(argv) != 2:
        sys.exit(__doc__)
    lines = open(argv[0], encoding='latin-1').read().splitlines()
    lines = convert_macros(lines)
    if le:
        lines = little_endian(lines, argv[0])
    lines = [re.sub(r'^(\s*)\.rodata\b', r'\1.section .rodata', line) for line in lines]
    lines = scope_labels(lines)
    if argv[0].endswith('.i'):
        # Register names as numbers, which vasm also takes in expressions.
        lines = [f'.set\t{r}{n},{n}' for r in 'rf' for n in range(32)] + lines
    open(argv[1], 'w', encoding='latin-1').write('\n'.join(lines) + '\n')


if __name__ == '__main__':
    main(sys.argv[1:])
