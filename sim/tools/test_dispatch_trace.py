# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
import unittest
from pathlib import Path

from check_dispatch_trace import check_rules, classify, compare, parse, stage_events

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

    def test_writeback_classes(self):
        cases = {
            0x613e0001: [1, 0, 0, 0, 0],  # ori r30,r9,1: bit 31 is immediate
            0x1d290001: [1, 0, 0, 0, 0],  # mulli
            0x352b03ff: [1, 1, 0, 0, 0],  # addic.
            0x7c632215: [1, 1, 0, 0, 0],  # add.
            0x55290001: [1, 1, 0, 0, 0],  # rlwinm.
            0xfc011000: [0, 1, 0, 0, 0],  # fcmpu
            0xfc000048: [0, 0, 1, 0, 0],  # fmr
            0xfc00008c: [0, 0, 0, 0, 0],  # mtfsb0
        }
        for word, writes in cases.items():
            with self.subTest(f'{word:08x}'):
                self.assertEqual(classify(word, True)['writes'], writes)

    def test_writeback_limits(self):
        words = {0x200: 0x613e0001, 0x204: 0x352b03ff, 0x208: 0x7c632215}
        pair = '1 D1 R0 {0:08x} |\n2 D1 R0 {1:08x} |\n3 D0 R2 | {0:08x} {1:08x}'
        check_rules(pair.format(0x200, 0x204).splitlines(), 2, words, True)
        with self.assertRaisesRegex(ValueError, 'TIM-WB-LIMITS'):
            check_rules(pair.format(0x204, 0x208).splitlines(), 2, words, True)

    def test_mispredicted_path_removed(self):
        # 0x300 beq 0x308 predicted not taken; 0x304 and 0x308 dispatch down
        # the wrong path, then the correct 0x308 dispatches again.
        words = {0x300: 0x41820008, 0x304: 0x38e00010, 0x308: 0x69290058, 0x30c: 0x38630001}
        early = ('1 D1 R0 00000300 |\n2 D1 R0 00000304 |\n3 D1 R0 00000308 |\n4 D0 R0 | !2\n'
                 '6 D1 R0 00000308 |\n7 D1 R1 0000030c | 00000300\n8 D0 R1 | 00000308\n'
                 '9 D0 R1 | 0000030c')
        late = early.replace('4 D0 R0 | !2\n6 D1 R0 00000308 |\n7 D1 R1 0000030c | 00000300',
                             '4 D0 R1 | 00000300\n5 D0 R0 | !2\n6 D1 R0 00000308 |\n7 D1 R0 0000030c |')
        for label, text in (('early', early), ('late', late)):
            with self.subTest(label):
                st = check_rules(text.split('\n'), 1, words, False)
                self.assertEqual((st['retirements'], st['flushed'], st['mispredicts']), (3, 2, 1))
        cases = {
            'no recovery': early.replace('4 D0 R0 | !2\n', ''),
            'removed work retires': early.replace('!2', '!1'),
            'too many removed': early.replace('!2', '!4'),
            'not after a conditional branch': early.replace('00000300', '00000000').replace(
                '1 D1 R0 00000000', '1 D1 R0 0000030c'),
        }
        for label, text in cases.items():
            with self.subTest(label), self.assertRaises(ValueError):
                check_rules(text.split('\n'), 1, words, False)

    def test_schedule_ignores_recovery_marker(self):
        self.assertEqual(parse('4 D0 R1 | 00000300 !2\n5 D0 R0 | !1'), {4: ([], [0x300])})


if __name__ == '__main__':
    unittest.main()
