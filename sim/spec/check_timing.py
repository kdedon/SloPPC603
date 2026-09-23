#!/usr/bin/env python3
"""Check timing-transcription structure/provenance, not processor conformance."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re

GROUPS = ('rows', 'rules', 'footnotes', 'schedules', 'unresolved')
REF_GROUPS = {
    'issue_ids': 'unresolved',
    'footnote_ids': 'footnotes',
    'serialization_rule_ids': 'rules',
}
UM_OFFSETS = {1: 40, 2: 78, 3: 126, 4: 158, 5: 196, 6: 246, 7: 276, 8: 308, 9: 354}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate(path):
    data = json.loads(path.read_text(encoding='utf-8'))
    require(data['schema_version'] == 1, 'unsupported schema version')
    ids = {group: {item['id'] for item in data[group]} for group in GROUPS}
    for group, values in ids.items():
        require(len(values) == len(data[group]), f'duplicate {group} ID')
    counts = Counter(row['table'] for row in data['rows'])
    require(dict(counts) == data['coverage']['row_counts'], 'table row-count coverage mismatch')
    require(len(data['rows']) == data['coverage']['total_rows'], 'total row-count mismatch')
    require(len(data['rules']) == data['coverage']['rule_count'], 'rule-count mismatch')
    graphical = [schedule for schedule in data['schedules'] if 'instructions' in schedule]
    for schedule in graphical:
        instructions = schedule['instructions']
        bounds = schedule['cycle_bounds']
        numbers = [instruction['instruction_number'] for instruction in instructions]
        require(len(set(numbers)) == len(numbers), f"duplicate instruction row in {schedule['id']}")
        require(len(instructions) == schedule['instruction_row_count'], 'schedule row-count mismatch')
        cell_count = 0
        for instruction in instructions:
            cells = instruction['cells']
            cycles = [cell['cycle'] for cell in cells]
            require(len(set(cycles)) == len(cycles), 'multiple drawn stages at one instruction/cycle')
            for cell in cells:
                require(cell['stage'] in schedule['stages'], f"unknown drawn stage: {cell}")
                require(type(cell['cycle']) is int, f"noninteger cycle: {cell}")
                if cell['extent'] == 'full':
                    require(bounds['first_labeled_cycle'] <= cell['cycle'] <= bounds['last_labeled_cycle'],
                            f"full cell outside labeled cycles: {cell}")
                else:
                    require(cell['extent'] == 'partial_right_edge' and
                            cell['cycle'] == bounds['partial_tail_cycle'], f"invalid partial cell: {cell}")
            cell_count += len(cells)
        require(cell_count == schedule['cell_count'], 'schedule cell-count mismatch')
    if graphical:
        coverage = data['coverage']
        require(len(graphical) == coverage['graphical_schedule_transcriptions'], 'graphical coverage mismatch')
        require(sum(s['instruction_row_count'] for s in graphical) == coverage['schedule_instruction_rows'],
                'total graphical instruction-count mismatch')
        require(sum(s['cell_count'] for s in graphical) == coverage['schedule_cell_count'],
                'total graphical cell-count mismatch')
    for row in data['rows']:
        timing = row['timing']
        if timing['kind'] == 'pipeline_stage_latency':
            stages = timing['pipeline_stage_occupancy']
            require(len(stages) == 3 and all(type(n) is int and n > 0 for n in stages),
                    f"invalid FP stage occupancy: {row['id']}")
            require(sum(stages) == timing['execute_latency_cycles'],
                    f"FP latency sum mismatch: {row['id']}")
    source_file = data['source_document']['file']
    locators = 0

    def walk(value):
        nonlocal locators
        if isinstance(value, dict):
            for field, group in REF_GROUPS.items():
                if field in value:
                    unknown = set(value[field]) - ids[group]
                    require(not unknown, f'unknown {field}: {sorted(unknown)}')
            if 'pdf_page' in value:
                locators += 1
                require(value['file'] == source_file, 'source outside declared document')
                label = re.fullmatch(r'(\d+)-(\d+)', value['printed_page'])
                require(label is not None, f'unsupported printed-page label: {value}')
                chapter, page = map(int, label.groups())
                require(chapter in UM_OFFSETS and page > 0, f'invalid page label: {value}')
                require(value['pdf_page'] == UM_OFFSETS[chapter] + page,
                        f'PDF/printed-page mapping mismatch: {value}')
            for child in value.values():
                walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)

    walk(data)
    return len(data['rows']), len(data['rules']), locators


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path', nargs='?', type=Path,
                        default=Path(__file__).with_name('timing.json'))
    args = parser.parse_args()
    try:
        rows, rules, locators = validate(args.path)
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f'FAIL: {error}\n')
    print(f'PASS: {rows} rows, {rules} rules, {locators} source locators; structural checks only')


if __name__ == '__main__':
    main()
