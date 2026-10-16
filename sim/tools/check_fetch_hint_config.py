#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Fail-closed structural guard for the fetch classifier's static configuration.

This checks the current explicit named-parameter source style, not elaborated
behavior, decoder semantics, four-state mux composition or cache provenance.
A new decoder parameter requires deliberate review of this inventory as well
as producer/consumer forwarding. No complete RTL file hashes are pinned.
"""
from pathlib import Path
import re
import sys

PARAMS = """ENABLE_SUPERVISOR_EXCEPTIONS ENABLE_LIVE_CONTEXT ENABLE_TIMERS
ENABLE_RUNTIME_BAT ENABLE_SEGMENT_REGISTERS ENABLE_TLB_INVALIDATE ENABLE_TLB_LOAD
ENABLE_SDR1 ENABLE_TLB_MISS_EXCEPTIONS ENABLE_CACHE_INSTRUCTIONS ENABLE_DATA_CACHE
ENABLE_BYTE_REVERSE ENABLE_MULTIPLE_STRING ENABLE_RESERVATION ENABLE_DEBUG_EXCEPTIONS
ENABLE_FULL_DECODE ENABLE_FPU CPU_VARIANT""".split()


def require(ok, message):
    if not ok:
        raise ValueError(message)


def clean(text):
    return re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.S)


def norm(text):
    return re.sub(r"\s+", "", text)


def group(text, start):
    require(text[start] == "(", "expected parenthesized source block")
    depth = 0
    for end in range(start, len(text)):
        if text[end] == "(":
            depth += 1
        elif text[end] == ")":
            depth -= 1
            if depth == 0:
                return text[start + 1:end], end + 1
    raise ValueError("unterminated source block")


def header(text, module):
    found = list(re.finditer(r"\bmodule\s+" + module + r"\s*#\s*\(", text))
    require(len(found) == 1, f"{module}: expected exactly one module header")
    return group(text, found[0].end() - 1)[0]


def bindings(body):
    result = {}
    pos = 0
    while pos < len(body):
        m = re.match(r"\s*\.([A-Za-z_]\w*)\s*\(", body[pos:])
        require(m is not None, "unsupported non-named parameter syntax")
        name = m.group(1)
        value, end = group(body, pos + m.end() - 1)
        require(name not in result, f"duplicate parameter {name}")
        result[name] = norm(value)
        pos = end
        comma = re.match(r"\s*,", body[pos:])
        if comma:
            pos += comma.end()
        else:
            require(not body[pos:].strip(), "unexpected trailing parameter text")
            break
    return result


def instances(text, module):
    result = {}
    for m in re.finditer(r"\b" + module + r"\s*#\s*\(", text):
        body, end = group(text, m.end() - 1)
        name = re.match(r"\s*([A-Za-z_]\w*)\s*\(", text[end:])
        if name is None:  # module declaration has ports immediately after #(...)
            continue
        require(name.group(1) not in result, "duplicate instance name")
        result[name.group(1)] = bindings(body)
    return result


def expect(mapping, expected, label, exact=True):
    require((mapping == expected) if exact else
            all(mapping.get(k) == v for k, v in expected.items()),
            f"{label}: parameter bindings differ")


def main():
    root = Path(__file__).resolve().parents[2]
    names = ('ppc_decode', 'ppc_fetch_hints', 'ppc_core',
             'ppc_core_bat', 'ppc_core_bat_cached_bus60x', 'ppc_pkg')
    src = {n: clean((root / 'rtl' / (n + '.sv')).read_text()) for n in names}
    decoder_header = header(src['ppc_decode'], 'ppc_decode')
    declarations = re.findall(r"\bparameter\s+(.+?)\s+(\w+)\s*=\s*([^,]+)(?:,|$)",
                              decoder_header, re.S)
    require([n for _, n, _ in declarations] == PARAMS,
            "decoder parameter inventory changed or declaration syntax unsupported")
    require(norm(header(src['ppc_fetch_hints'], 'ppc_fetch_hints')) == norm(decoder_header),
            "classifier header types/defaults/order differ from actual decoder")
    same = {p: p for p in PARAMS}
    producer = instances(src['ppc_fetch_hints'], 'ppc_decode')
    require(set(producer) == {'decode'}, "classifier decoder instances changed")
    expect(producer['decode'], same, 'classifier decoder')
    consumers = instances(src['ppc_core'], 'ppc_decode')
    require(set(consumers) == {'predecode', 'predecode1', 'check_decode'},
            "core decoder instance inventory changed")
    for name, mapping in consumers.items():
        expect(mapping, same, 'core ' + name)
    cached = src['ppc_core_bat_cached_bus60x']
    assembly = dict(same, ENABLE_DATA_CACHE='ENABLE_DCACHE')
    hints = instances(cached, 'ppc_fetch_hints')
    require(set(hints) == {'classify'}, "cached classifier instance inventory changed")
    expect(hints['classify'], assembly, 'cached classifier')
    bats = instances(cached, 'ppc_core_bat')
    require(set(bats) == {'translated_core'}, "cached core instance inventory changed")
    expect(bats['translated_core'], assembly, 'cached core', exact=False)
    cores = instances(src['ppc_core_bat'], 'ppc_core')
    require(set(cores) == {'core'}, "BAT core instance inventory changed")
    expect(cores['core'], same, 'BAT core', exact=False)
    frozen_cr = """function automatic logic cr_writer(uop_t u);
      return !u.illegal && (u.write_cr_field || u.write_cr_fields || u.write_cr_bit ||
      ((u.needs_flags || u.write_xer) && !(!u.write_xer && (u.write_ca || u.write_ov_so))));
      endfunction"""
    cr = re.findall(r"function\s+automatic\s+logic\s+cr_writer\b.*?endfunction",
                    src['ppc_pkg'], re.S)
    require(len(cr) == 1 and norm(cr[0]) == norm(frozen_cr),
            "shared CR demand helper differs from frozen original predicate")
    require(not re.search(r"function\b[^;]*\bcr_writer\s*\(", src['ppc_core']),
            "core shadows shared cr_writer")
    hints_text = norm(src['ppc_fetch_hints'])
    require("assignword_class=fetch_lookahead(decoded,word,1'b0);" in hints_text and
            "assignhints={cr_writer(decoded),word_class};" in hints_text,
            "producer no longer uses shared raw class/CR helper layout")
    print('PASS fetch-hint configuration: 18 parameter declarations; producer, '
          '3 consumer instances and cached/BAT assembly bindings; shared CR predicate')
    print('Scope: structural source guard only; transport, ownership and functional equivalence are separate.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as error:
        print(f'FAIL fetch-hint configuration: {error}', file=sys.stderr)
        sys.exit(1)
