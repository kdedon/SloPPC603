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

    def test_removed_branch(self):
        # 0x400 add, 0x404 b 0x40c (removed), 0x40c add; 0x408 bl, 0x410 bdnz.
        words = {0x400: 0x38630001, 0x404: 0x48000008, 0x40c: 0x38840001,
                 0x408: 0x48000009, 0x410: 0x4200fff0}
        text = '1 D2 R0 00000400 00000404* |\n2 D1 R1 0000040c | 00000400\n3 D0 R1 | 0000040c'
        st = check_rules(text.split('\n'), 2, words, False)
        self.assertEqual((st['dispatches'], st['removed'], st['retirements']), (3, 1, 2))
        self.assertEqual(parse(text)[1], ([0x400, 0x404], []))
        for label, pc in (('linking', '00000408'), ('counting', '00000410'), ('not a branch', '0000040c')):
            with self.subTest(label), self.assertRaises(ValueError):
                check_rules(text.replace('00000404*', pc + '*').split('\n'), 2, words, False)
        with self.subTest('removed branch retires'), self.assertRaises(ValueError):
            check_rules(text.replace('R1 | 0000040c', 'R1 | 00000404').split('\n'), 2, words, False)

    def test_completion_and_rename_limits(self):
        # Five addi, then lwzu (two GPR destinations) and fadd.
        words = {0x500 + 4 * i: 0x38630001 for i in range(6)}
        words.update({0x600 + 4 * i: 0x84830000 for i in range(3)})
        words.update({0x700 + 4 * i: 0xfc22182a for i in range(5)})
        def run(base, count, retire_first=False):
            text = '\n'.join(f'{i + 1} D1 R0 {base + 4 * i:08x} |' for i in range(count))
            if retire_first:
                text += f'\n{count + 1} D0 R1 | {base:08x}'
            return check_rules(text.split('\n'), 1, words, False)
        self.assertEqual(run(0x500, 5)['cq_max'], 5)
        self.assertEqual(run(0x600, 2)['gpr_max'], 4)
        run(0x700, 4)
        for label, (base, count, rule) in {'sixth buffer': (0x500, 6, 'TIM-CQ-ALLOC'),
                                           'sixth GPR rename': (0x600, 3, 'TIM-RENAME-LIMITS'),
                                           'fifth FPR rename': (0x700, 5, 'TIM-RENAME-LIMITS')}.items():
            with self.subTest(label), self.assertRaisesRegex(ValueError, rule):
                run(base, count)

    def test_fetch_stops(self):
        # 0x800 add; 0x804 bl; 0x808 bcl (always); 0x80c bl; 0x810 bdnz;
        # 0x814 bdnz; 0x818 mtctr; 0x81c bcctr; 0x820 mtlr; 0x824 blr; 0x828 addi.
        words = {0x800: 0x7c632214, 0x804: 0x48000009, 0x808: 0x42800005, 0x80c: 0x48000009,
                 0x810: 0x4200fff0, 0x814: 0x4200fff0, 0x818: 0x7c6903a6, 0x81c: 0x4e800420,
                 0x820: 0x7c6803a6, 0x824: 0x4e800020, 0x828: 0x38630001}
        def run(*lines):
            return check_rules(list(lines), 1, words, False)
        # bl need not wait for an older linking branch.
        run('1 D1 R0 00000804 |', '2 D1 R0 0000080c |', '3 D1 R0 00000828 |')
        # The waiting branch may enter; younger work waits for completion.
        st = run('1 D1 R0 00000810 |', '2 D1 R0 00000814 |', '3 D0 R1 | 00000810', '4 D1 R0 00000828 |')
        self.assertEqual(st['fetch_stops'], 1)
        # A move to CTR executes once everything older has retired.
        run('1 D1 R0 00000800 |', '2 D1 R0 00000818 |', '3 D1 R1 0000081c* | 00000800',
            '4 D1 R0 00000828 |')
        cases = {
            'branch(LK) behind branch(LK)': ('1 D1 R0 00000804 |', '2 D1 R0 00000808 |',
                                             '3 D1 R0 00000828 |'),
            'bc(CTR) behind bc(CTR)': ('1 D1 R0 00000810 |', '2 D1 R0 00000814 |', '3 D1 R0 00000828 |'),
            'bcctr behind bc(CTR)': ('1 D1 R0 00000810 |', '2 D1 R0 0000081c |', '3 D1 R0 00000828 |'),
            'bcctr behind mtctr': ('1 D1 R0 00000800 |', '2 D1 R0 00000818 |', '3 D1 R0 0000081c |',
                                   '4 D1 R0 00000828 |'),
            'bcctr removed behind mtctr': ('1 D1 R0 00000800 |', '2 D1 R0 00000818 |',
                                           '3 D1 R0 0000081c* |'),
            'bclr removed behind mtlr': ('1 D1 R0 00000800 |', '2 D1 R0 00000820 |', '3 D1 R0 00000824* |'),
        }
        for label, lines in cases.items():
            with self.subTest(label), self.assertRaisesRegex(ValueError, 'TIM-BPU-FETCH-STOP'):
                run(*lines)

    def test_one_level_of_prediction(self):
        # 0x900 beq predicted not taken; 0x904 bne on the predicted path; 0x908 addi.
        words = {0x900: 0x41820010, 0x904: 0x40820010, 0x908: 0x38630001, 0x910: 0x38630001}
        stop = ['1 D1 R0 00000900 |', '2 D1 R0 00000904 |', '4 D0 R0 | !1',
                '5 D1 R1 00000910 | 00000900', '6 D0 R1 | 00000910']
        st = check_rules(stop, 1, words, False)
        self.assertEqual(st['wrong_path_branches'], 1)
        past = stop[:2] + ['3 D1 R0 00000908 |', '4 D0 R0 | !2'] + stop[3:]
        with self.assertRaisesRegex(ValueError, 'TIM-BPU-ONE-PREDICTION'):
            check_rules(past, 1, words, False)
        with self.assertRaisesRegex(ValueError, 'TIM-BPU-ONE-PREDICTION'):
            check_rules([stop[0], '2 D1 R0 00000904* |', '4 D0 R0 | !0'] + stop[3:], 1, words, False)

    def test_schedule_ignores_recovery_marker(self):
        self.assertEqual(parse('4 D0 R1 | 00000300 !2\n5 D0 R0 | !1'), {4: ([], [0x300])})


if __name__ == '__main__':
    unittest.main()
