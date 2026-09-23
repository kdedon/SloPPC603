"""Positive fixtures and deliberate failures independent of the RTL probe."""
import copy
import json
import unittest
from check_stage_timing import ROOT, check_trace, validate_contract


def packet(ident, pc, insn, gpr, value):
    return dict(id=ident, pc=pc, insn=insn, gpr=gpr, value=value)


def fixture(stall=False):
    a = (14 << 26) | (1 << 21) | 7
    b = (14 << 26) | (2 << 21) | (1 << 16) | 1
    pa, pb = packet(1, 0, a, 1, 7), packet(257, 4, b, 2, 8)
    rows = [dict(dispatch=dict(id=1, pc=0, insn=a)),
            dict(issue=dict(id=1, a=0, b=7), dispatch=dict(id=257, pc=4, insn=b)),
            dict(finish=dict(id=1, value=7), issue=dict(id=257, a=7, b=1)),
            dict(retire=pa, finish=dict(id=257, value=8))]
    if stall:
        rows += [dict(retire=pa), dict(retire=pa), dict(retire=pb)]
        counts, readiness = [0, 1, 2, 2, 2, 2, 1], [1, 1, 1, 0, 0, 1, 1]
    else:
        rows += [dict(retire=pb)]
        counts, readiness = [0, 1, 2, 2, 1], [1] * 5
    for edge, row in enumerate(rows):
        row.update(edge=edge, cq_count=counts[edge], rename_count=counts[edge], retire_ready=readiness[edge])
    return rows


class StageTimingTests(unittest.TestCase):
    def reject(self, trace, pattern):
        with self.assertRaisesRegex(ValueError, pattern):
            check_trace(trace, require_coverage=False)

    def test_same_edge_raw_and_retire_stall_pass(self):
        result = check_trace(fixture(True), require_coverage=False)
        self.assertEqual(result['same_edge_raw_issue'], 1)
        self.assertEqual(result['retire_stall_edges'], 2)
        self.assertEqual(result['retire'], 2)

    def test_contract_passes(self):
        validate_contract(json.loads((ROOT / 'sim/spec/stage_timing.json').read_text()))

    def test_changed_edge_contract_rejected(self):
        contract = json.loads((ROOT / 'sim/spec/stage_timing.json').read_text())
        contract['implementation_edges']['dispatch_to_issue_min'] = 0
        with self.assertRaisesRegex(ValueError, 'edge constants'):
            validate_contract(contract)

    def test_wrong_source_page_rejected(self):
        contract = json.loads((ROOT / 'sim/spec/stage_timing.json').read_text())
        contract['manual_relations'][0]['sources'][0]['printed_page'] = '6-99'
        with self.assertRaisesRegex(ValueError, 'source page mapping'):
            validate_contract(contract)

    def test_issue_on_dispatch_edge_rejected(self):
        trace = fixture()
        trace[0]['issue'] = trace[1].pop('issue')
        self.reject(trace, 'issue')

    def test_finish_on_issue_edge_rejected(self):
        trace = fixture()
        trace[1]['finish'] = trace[2].pop('finish')
        self.reject(trace, 'finish')

    def test_late_finish_rejected(self):
        trace = fixture()
        # Remove child and extend single producer's execution without a stall.
        del trace[1]['dispatch']
        del trace[2]['issue']
        trace[3] = dict(edge=3, cq_count=1, rename_count=1, retire_ready=1,
                        finish=trace[2].pop('finish'))
        trace[2].update(cq_count=1, rename_count=1)
        self.reject(trace, 'issue-to-finish distance')

    def test_finish_to_retire_bypass_rejected(self):
        trace = fixture()
        trace[2]['retire'] = trace[3].pop('retire')
        self.reject(trace, 'retirement before registered finish')

    def test_raw_issue_without_finish_rejected(self):
        trace = fixture()
        del trace[2]['finish']
        self.reject(trace, 'RAW issued before finish')

    def test_wrong_issue_operand_rejected(self):
        trace = fixture()
        trace[2]['issue']['a'] = 6
        self.reject(trace, 'issue operands')

    def test_wrong_finish_value_rejected(self):
        trace = fixture()
        trace[2]['finish']['value'] = 9
        self.reject(trace, 'result value')

    def test_younger_retirement_rejected(self):
        trace = fixture()
        trace[3]['retire'] = copy.deepcopy(trace[4]['retire'])
        self.reject(trace, 'retirement not oldest')

    def test_stalled_payload_change_rejected(self):
        trace = fixture(True)
        trace[4]['retire'] = dict(trace[4]['retire'], value=99)
        self.reject(trace, 'stalled retirement changed')

    def test_early_rename_release_rejected(self):
        trace = fixture(True)
        trace[4]['rename_count'] = 1
        self.reject(trace, 'resource occupancy/release')

    def test_missing_edge_rejected(self):
        trace = fixture()
        del trace[2]
        self.reject(trace, 'edge sequence')

    def test_incomplete_trace_rejected(self):
        self.reject(fixture()[:-1], 'without draining')

    def test_probe_coverage_required(self):
        with self.assertRaisesRegex(ValueError, 'seven forms'):
            check_trace(fixture())

    def test_full_same_edge_reclaim_rejected(self):
        trace = []
        packets = []
        for i in range(6):
            word = (14 << 26) | ((i + 1) << 21) | i
            packets.append(packet(i + 1, i * 4, word, i + 1, i))
        for edge in range(8):
            row = dict(edge=edge, cq_count=min(edge, 5), rename_count=min(edge, 5), retire_ready=int(edge == 7))
            if edge < 5 or edge == 7:
                p = packets[edge if edge < 5 else 5]
                row['dispatch'] = {k: p[k] for k in ('id', 'pc', 'insn')}
            if 1 <= edge <= 5:
                row['issue'] = dict(id=edge, a=0, b=edge - 1)
            if 2 <= edge <= 6:
                row['finish'] = dict(id=edge - 1, value=edge - 2)
            if edge >= 3:
                row['retire'] = packets[0]
            trace.append(row)
        self.reject(trace, 'full same-edge reclaim')


if __name__ == '__main__':
    unittest.main()
