#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Converts the Amiga Quake PowerPC sources from vasm syntax to GNU as:
positional macro parameters (\\1) become named ones, '$' as the location
counter becomes '.', .rodata becomes a section, and the local labels
(.name, scoped between global labels) get a unique suffix per scope. The
output is otherwise line for line the input.

Usage: asmconv.py in.s out.s"""
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


def main(argv):
    if len(argv) != 2:
        sys.exit(__doc__)
    lines = open(argv[0], encoding='latin-1').read().splitlines()
    lines = convert_macros(lines)
    lines = [re.sub(r'^(\s*)\.rodata\b', r'\1.section .rodata', line) for line in lines]
    lines = scope_labels(lines)
    if argv[0].endswith('.i'):
        # Register names as numbers, which vasm also takes in expressions.
        lines = [f'.set\t{r}{n},{n}' for r in 'rf' for n in range(32)] + lines
    open(argv[1], 'w', encoding='latin-1').write('\n'.join(lines) + '\n')


if __name__ == '__main__':
    main(sys.argv[1:])
