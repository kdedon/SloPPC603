#!/usr/bin/env python3
"""Check reviewed P05 IU edge relations, not full 603e cycle conformance."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FORMS = {'addi', 'addis', 'ori', 'oris', 'xori', 'xoris', 'add'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def decode(word):
    """Independent subset decode for dependency/value checks; no RTL trace hints."""
    op, rt, ra, rb = word >> 26, (word >> 21) & 31, (word >> 16) & 31, (word >> 11) & 31
    imm = word & 65535
    if op in (14, 15):
        imm = (imm - 65536 if imm & 32768 else imm) if op == 14 else imm << 16
        return ('addi' if op == 14 else 'addis'), rt, [None if ra == 0 else ra, None], imm & 0xffffffff
    if op in (24, 25, 26, 27):
        return {24: 'ori', 25: 'oris', 26: 'xori', 27: 'xoris'}[op], ra, [rt, None], imm << (16 if op & 1 else 0)
    require(op == 31 and ((word >> 1) & 1023) == 266 and not word & 1, 'unsupported instruction form')
    return 'add', rt, [ra, rb], None


def validate_contract(contract):
    require(contract['schema_version'] == 1, 'contract schema')
    require(set(x['form'] for x in contract['forms']) == FORMS and len(contract['forms']) == 7, 'seven form coverage')
    # Reviewed constants are intentionally independent of the input manifest.
    require(contract['implementation_edges'] == {
        'dispatch_to_issue_min': 1, 'issue_to_finish_exact': 1,
        'finish_to_retire_min': 1, 'release_equals_retire': True,
        'full_same_edge_reclaim': False}, 'reviewed edge constants changed')
    timing = json.loads((ROOT / 'sim/spec/timing.json').read_text())
    rows = {x['id']: x for x in timing['rows']}
    for form in contract['forms']:
        row = rows[form['timing_row_id']]
        require(row['mnemonic_key'] == form['form'], 'timing row form mismatch')
        require(row['timing']['execute_latency_cycles'] == form['manual_execute_cycles'] == 1, 'manual IU latency')
        require(row['source'] == form['source'], 'timing source mismatch')
    for source in contract['manual_relations']:
        for loc in source['sources']:
            require(loc['file'] == contract['source_file'] and loc['printed_page'] == f"6-{loc['pdf_page'] - 246}", 'source page mapping')
    return True


def check_trace(edges, require_coverage=True):
    """All fields are pre-NBA samples; events on an edge are simultaneous.

    Finish is processed first only to permit same-edge RAW forwarding. Retirement
    separately requires a strictly older finish, preventing accidental bypass.
    """
    live, history, latest, order = {}, {}, {}, []
    registers = [0] * 32
    last_edge, stalled = None, None
    forms, stats = set(), dict(dispatch=0, issue=0, finish=0, retire=0,
        retire_stall_edges=0, pending_raw=0, same_edge_raw_issue=0, earliest_issue=0,
        earliest_retire=0, full_edges=0)
    for row in edges:
        edge = row['edge']
        require(type(edge) is int and (last_edge is None or edge == last_edge + 1), 'edge sequence')
        last_edge = edge
        require(row['cq_count'] == len(order) == row['rename_count'], f'edge {edge}: resource occupancy/release')
        stats['full_edges'] += len(order) == 5
        packet = row.get('retire')
        if stalled is not None:
            require(packet == stalled, f'edge {edge}: stalled retirement changed')
        if packet:
            require(order and packet['id'] == order[0], f'edge {edge}: retirement not oldest')
            r = live[packet['id']]
            require('finish' in r and edge >= r['finish'] + 1, f'edge {edge}: retirement before registered finish')
            require(packet == r['packet'], f'edge {edge}: retirement payload')
        elif order and 'finish' in live[order[0]]:
            require(False, f'edge {edge}: finished head withheld retirement valid')
        stalled = packet if packet and not row['retire_ready'] else None
        stats['retire_stall_edges'] += stalled is not None

        finish = row.get('finish')
        if finish:
            ident = finish['id']
            require(ident in live and 'issue' in live[ident] and 'finish' not in live[ident], 'invalid/duplicate finish')
            r = live[ident]
            require(edge == r['issue'] + 1, f'edge {edge}: issue-to-finish distance')
            require(finish['value'] == r['value'], f'edge {edge}: result value')
            r['finish'] = edge
            stats['finish'] += 1
        issue = row.get('issue')
        if issue:
            ident = issue['id']
            require(ident in live and 'issue' not in live[ident], 'invalid/duplicate issue')
            r = live[ident]
            require(edge >= r['dispatch'] + 1, f'edge {edge}: dispatch-to-issue distance')
            for producer in r['deps']:
                require('finish' in history[producer] and history[producer]['finish'] <= edge, f'edge {edge}: RAW issued before finish')
            stats['same_edge_raw_issue'] += any(history[p]['finish'] == edge for p in r['deps'])
            require([issue['a'], issue['b']] == r['operands'], f'edge {edge}: issue operands')
            r['issue'] = edge
            stats['earliest_issue'] += edge == r['dispatch'] + 1
            stats['issue'] += 1
        dispatch = row.get('dispatch')
        if dispatch:
            ident = dispatch['id']
            require(len(order) < 5, f'edge {edge}: full same-edge reclaim')
            require(ident not in history, 'identity reused within bounded trace')
            form, dst, sources, imm = decode(dispatch['insn'])
            deps = [latest[s] for s in sources if s is not None and s in latest]
            operands = [registers[s] if s is not None else 0 for s in sources]
            if imm is not None:
                operands[1] = imm
            value = ((operands[0] ^ operands[1]) if form.startswith('xor') else
                     (operands[0] | operands[1]) if form.startswith('or') else
                     (operands[0] + operands[1])) & 0xffffffff
            r = dict(dispatch=edge, deps=deps, operands=operands, value=value,
                packet=dict(id=ident, pc=dispatch['pc'], insn=dispatch['insn'], gpr=dst, value=value))
            stats['pending_raw'] += any('finish' not in history[p] for p in deps)
            registers[dst], latest[dst] = value, ident
            live[ident] = history[ident] = r
            order.append(ident)
            forms.add(form)
            stats['dispatch'] += 1
        if packet and row['retire_ready']:
            r = live.pop(order.pop(0))
            stats['earliest_retire'] += edge == r['finish'] + 1
            stats['retire'] += 1
    require(not live and stats['dispatch'] > 0, 'trace ended without draining work')
    if require_coverage:
        require(forms == FORMS, 'seven forms not observed')
        for name in ('retire_stall_edges', 'pending_raw', 'same_edge_raw_issue', 'earliest_issue', 'earliest_retire', 'full_edges'):
            require(stats[name] > 0, f'missing coverage: {name}')
    return stats


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('trace', type=Path, nargs='?')
    args = parser.parse_args()
    try:
        validate_contract(json.loads((ROOT / 'sim/spec/stage_timing.json').read_text()))
        if args.trace:
            print('PASS stage timing:', json.dumps(check_trace([json.loads(s) for s in args.trace.read_text().splitlines()]), sort_keys=True))
        else:
            print('PASS stage timing contract: seven form/source anchors and reviewed edge constants')
    except (ValueError, KeyError, TypeError) as error:
        parser.exit(1, f'FAIL stage timing: {error}\n')


if __name__ == '__main__':
    main()
