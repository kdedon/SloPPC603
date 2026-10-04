# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
import unittest
from pathlib import Path

from check_dispatch_trace import check_rules, compare, parse, stage_events

SCHEDULE = Path(__file__).resolve().parents[1] / 'spec/schedules/stage.txt'


class DispatchTraceTest(unittest.TestCase):
    def setUp(self):
        self.expected = parse(SCHEDULE.read_text())

    def test_schedule_matches_itself(self):
        self.assertEqual(compare(self.expected, self.expected)[:2], (14, 14))

    def test_one_cycle_shift_fails(self):
        for cycle in self.expected:
            mutated = dict(self.expected)
            event = mutated.pop(cycle)
            if cycle + 1 in mutated:
                continue
            mutated[cycle + 1] = event
            with self.assertRaises(ValueError):
                compare(mutated, self.expected)

    def test_dropped_or_moved_pc_fails(self):
        cycle = min(self.expected)
        dispatched, retired = self.expected[cycle]
        for event in (([], retired or [0]), (dispatched + [4], retired)):
            with self.assertRaises(ValueError):
                compare({**self.expected, cycle: event}, self.expected)

    def test_malformed_counts_rejected(self):
        with self.assertRaises(ValueError):
            parse('5 D2 R0 00000000 |')
        with self.assertRaises(ValueError):
            parse('5 D0 R0 |')

    def test_stage_rows_count_only_accepted_retirements(self):
        rows = [dict(edge=3, dispatch=dict(pc=8), retire_ready=0, retire=dict(pc=0)),
                dict(edge=4, retire_ready=1, retire=dict(pc=0))]
        self.assertEqual(stage_events(rows), {3: ([8], []), 4: ([], [0])})



# Instruction words at 0x100: add, lwz, stw, addi, isync, mtmsr, mullw, lis, or.
WORDS = {0x100: 0x7c632214, 0x104: 0x80830000, 0x108: 0x90830000, 0x10c: 0x38630001,
         0x110: 0x4c00012c, 0x114: 0x7c600124, 0x118: 0x7ca321d6, 0x11c: 0x3ca0fff0,
         0x120: 0x7c832b78}


class DispatchRulesTest(unittest.TestCase):
    def check(self, text, width=2, sru=True):
        return check_rules(text.splitlines(), width, WORDS, sru)

    def test_legal_pairs_pass(self):
        st = self.check('1 D2 R0 00000100 00000104 |\n3 D0 R2 | 00000100 00000104\n'
                        '4 D2 R0 0000011c 0000010c |\n6 D0 R2 | 0000011c 0000010c')
        self.assertEqual((st['pairs_dispatched'], st['pairs_retired'], st['sru_pairs']), (2, 2, 1))

    def test_each_rule_fails(self):
        cases = {
            'width': ('1 D2 R0 00000100 00000104 |', 1),
            'same unit': ('1 D2 R0 00000120 00000118 |', 2),
            'retire before dispatch': ('1 D1 R0 00000100 |\n1 D0 R1 | 00000100', 2),
            'out of order': ('1 D2 R0 00000100 00000104 |\n2 D0 R1 | 00000104', 2),
            'store in CQ1': ('1 D2 R0 00000100 00000108 |\n2 D0 R2 | 00000100 00000108', 2),
            'serialized pair': ('1 D2 R0 00000100 00000114 |', 2),
            'dispatch after dser': ('1 D1 R0 00000114 |\n2 D1 R0 00000100 |', 2),
            'dser with full CQ': ('1 D1 R0 00000100 |\n2 D1 R0 00000114 |\n3 D0 R1 | 00000100', 2),
            'isync refetch': ('1 D1 R0 00000110 |\n3 D1 R1 00000100 | 00000110', 2),
        }
        for label, (text, width) in cases.items():
            with self.subTest(label), self.assertRaises(ValueError):
                self.check(text.replace('\\n', '\n'), width)

    def test_two_ius_pair_only_with_sru(self):
        text = '1 D2 R0 00000100 0000010c |'
        self.check(text)
        with self.assertRaises(ValueError):
            self.check(text, sru=False)


if __name__ == '__main__':
    unittest.main()
