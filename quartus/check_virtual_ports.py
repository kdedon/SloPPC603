#!/usr/bin/env python3
"""Require explicit virtual assignments for every port, including the final one."""
import argparse
from pathlib import Path
import re


def check(top: Path, qsf: Path) -> None:
    header = top.read_text().split('\n);', 1)[0]
    ports = re.findall(
        r'^\s*(?:input|output)\s+(logic|ppc_pkg::\w+)\s*'
        r'(\[[^\]]+\])?\s*(\w+)\s*,?\s*$', header, re.MULTILINE)
    declarations = re.findall(r'^\s*(?:input|output)\b', header, re.MULTILINE)
    if not ports or len(ports) != len(declarations):
        raise ValueError('unsupported or missing port declaration in measurement top')
    # Quartus keeps packed-struct field names on physical ports (retire_o.pc[0]),
    # rather than flattening the whole struct to retire_o[0]. Vector and struct
    # wildcard forms are therefore different. These are the two struct types
    # exposed by the current measurement top; reject new types for review.
    struct_types = {'ppc_pkg::completion_tag_t', 'ppc_pkg::retire_packet_t'}
    if any(kind != 'logic' and kind not in struct_types for kind, _, _ in ports):
        raise ValueError('unreviewed package port type in measurement top')
    expected = {name + ('.*' if kind in struct_types else '[*]' if width else '')
                for kind, width, name in ports}
    actual_list = re.findall(
        r'^set_instance_assignment -name VIRTUAL_PIN ON -to (\S+)\s*$',
        qsf.read_text(), re.MULTILINE)
    actual = set(actual_list)
    if expected != actual or len(actual_list) != len(expected):
        raise ValueError(f'virtual ports differ: missing={sorted(expected-actual)}, '
                         f'extra={sorted(actual-expected)}, duplicates='
                         f'{len(actual_list)-len(actual)}')
    print(f'PASS: all {len(ports)} top-level port declarations are explicitly virtual')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('top', type=Path)
    parser.add_argument('qsf', type=Path)
    args = parser.parse_args()
    check(args.top, args.qsf)
