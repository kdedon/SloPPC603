# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
import unittest
from pathlib import Path

from check_dispatch_trace import compare, parse, stage_events

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


if __name__ == '__main__':
    unittest.main()
