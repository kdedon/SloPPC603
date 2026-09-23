import random
import unittest

from model import FetchDrainModel, RecoveryModel, Redirect, Tag


class RecoveryTests(unittest.TestCase):
    def allocate(self, model, dst=3):
        tag = model.step(allocate=True, dst=dst).allocated
        self.assertIsNotNone(tag)
        return tag

    def finish(self, model, tag, value, kind="local"):
        self.assertTrue(model.step(issue=tag, producer_kind=kind).issue_accepted)
        self.assertEqual(model.step(result=(tag, value)).finished, tag)

    def test_no_finish_commit_or_allocate_issue_bypass(self):
        m = RecoveryModel()
        candidate = m.candidate()
        e = m.step(allocate=True, dst=3, issue=candidate)
        self.assertEqual(e.allocated, candidate)
        self.assertFalse(e.issue_accepted)
        e = m.step(issue=candidate, result=(candidate, 91), retire_ready=True)
        self.assertTrue(e.issue_accepted)
        self.assertIsNone(e.finished)
        self.assertIsNone(e.committed)
        e = m.step(result=(candidate, 92), retire_ready=True)
        self.assertEqual(e.finished, candidate)
        self.assertIsNone(e.committed)
        self.assertEqual(m.arch[3], 0)
        self.assertEqual(m.step(retire_ready=True).committed, (0, 3, 92))

    def test_redirect_finish_commit_and_waw_survivor_map(self):
        m = RecoveryModel()
        head, pivot, younger = [self.allocate(m, 3) for _ in range(3)]
        self.finish(m, head, 11)
        m.step(issue=pivot)
        m.step(issue=younger)
        e = m.step(redirect=Redirect(0x1000, pivot), result=(pivot, 22),
                   retire_ready=True, allocate=True, dst=9)
        self.assertTrue(e.redirect_accepted)
        self.assertEqual(e.killed, (younger,))
        self.assertEqual(e.finished, pivot)
        self.assertEqual(e.committed, (0, 3, 11))
        self.assertIsNone(e.allocated)
        self.assertEqual(m.arch[3], 11)
        self.assertEqual(m.operand(3), (True, 22, pivot))
        self.assertNotIn(younger, m.tokens)
        self.assertIsNone(m.step(result=(younger, 999)).finished)
        self.assertEqual(m.step(retire_ready=True).committed, (1, 3, 22))
        self.assertEqual(m.operand(3), (True, 22, None))

    def test_wrapped_age_uses_queue_order_and_restores_older_writer(self):
        m = RecoveryModel()
        for value in (1, 2, 3, 4):
            tag = self.allocate(m, 5)
            self.finish(m, tag, value)
            m.step(retire_ready=True)
        oldest, pivot, young = [self.allocate(m, 5) for _ in range(3)]
        self.assertEqual([oldest.slot, pivot.slot, young.slot], [4, 0, 1])
        self.finish(m, oldest, 70)
        e = m.step(redirect=Redirect(0x2000, pivot, keep_pivot=False))
        self.assertEqual(e.killed, (pivot, young))
        self.assertEqual(m.operand(5), (True, 70, oldest))
        self.assertEqual(m.tail, 0)
        self.assertEqual(m.step(retire_ready=True).committed, (4, 5, 70))
        new = self.allocate(m, 5)
        self.assertEqual(new.slot, pivot.slot)
        self.assertNotEqual(new.generation, pivot.generation)

    def test_killed_finish_cannot_wake_or_commit(self):
        m = RecoveryModel()
        pivot = self.allocate(m)
        m.step(issue=pivot, producer_kind="external")
        e = m.step(redirect=Redirect(0x1000, pivot, False), result=(pivot, 88), retire_ready=True)
        self.assertTrue(e.result_consumed)
        self.assertTrue(e.redirect_accepted)
        self.assertIsNone(e.finished)
        self.assertIsNone(e.committed)
        self.assertEqual(m.arch, [0] * 32)
        self.assertFalse(m.tokens)
        self.assertFalse(m.entries)

    def test_invalid_redirect_does_not_block_progress(self):
        m = RecoveryModel()
        first = self.allocate(m)
        self.finish(m, first, 12)
        stale = Tag(first.slot, first.generation + 1)
        e = m.step(redirect=Redirect(0x1000, stale), allocate=True, dst=4, retire_ready=True)
        self.assertFalse(e.redirect_accepted)
        self.assertEqual(e.redirect_rejected, "inactive_pivot")
        self.assertIsNotNone(e.allocated)
        self.assertEqual(e.committed, (0, 3, 12))

    def test_finished_head_offer_cannot_be_retracted(self):
        for ready in (False, True):
            m = RecoveryModel()
            tag = self.allocate(m)
            self.finish(m, tag, 42)
            e = m.step(redirect=Redirect(0x1000), retire_ready=ready)
            self.assertFalse(e.redirect_accepted)
            self.assertEqual(e.redirect_rejected, "irrevocable_retirement_head")
            self.assertEqual(e.committed is not None, ready)
            if not ready:
                self.assertEqual(m.operand(3), (True, 42, tag))
                # Keeping a stalled head still permits removal of younger state.
                younger = self.allocate(m, 4)
                e = m.step(redirect=Redirect(0x2000, tag))
                self.assertTrue(e.redirect_accepted)
                self.assertEqual(e.killed, (younger,))
                self.assertEqual(m.operand(3), (True, 42, tag))

    def test_external_token_blocks_full_generation_wrap_until_drain(self):
        m = RecoveryModel(depth=1, rename_depth=1, generation_bits=2)
        old = self.allocate(m)
        m.step(issue=old, producer_kind="external")
        m.step(redirect=Redirect(0x1000))
        self.assertIn(old, m.tokens)
        for generation in (2, 3, 0):
            tag = self.allocate(m)
            self.assertEqual(tag.generation, generation)
            m.step(redirect=Redirect(0x1000))
        self.assertEqual(m.candidate(), old)
        self.assertIsNone(m.step(allocate=True, dst=3).allocated)
        e = m.step(result=(old, 0xBAD), allocate=True, dst=3)
        self.assertTrue(e.result_consumed)
        self.assertIsNone(e.finished)
        self.assertIsNone(e.allocated)  # Pre-edge collision conservatively blocks.
        self.assertEqual(self.allocate(m), old)
        self.assertEqual(m.operand(3), (False, 0, old))
        # No replay is legal after this token has drained and identity is reused.

    def test_full_queue_no_same_edge_reclaim_and_unfinished_fault_cut(self):
        m = RecoveryModel()
        tags = [self.allocate(m, i) for i in range(5)]
        self.finish(m, tags[0], 9)
        e = m.step(allocate=True, dst=8, retire_ready=True)
        self.assertIsNone(e.allocated)
        self.assertEqual(e.committed, (0, 0, 9))
        self.assertIsNotNone(self.allocate(m, 8))
        e = m.step(redirect=Redirect(0x1000, tags[2], False))
        self.assertTrue(e.redirect_accepted)
        self.assertEqual([entry.tag for entry in m.entries], [tags[1]])
        self.assertEqual(m.arch[0], 9)

    def test_reset_cancels_producers_and_clears_generations(self):
        m = RecoveryModel()
        tag = self.allocate(m)
        m.step(issue=tag, producer_kind="external")
        m.reset()  # Explicit environment-wide cancellation contract.
        self.assertFalse(m.entries or m.mapping or m.tokens)
        self.assertEqual(m.candidate(), Tag(0, 1))
        self.assertIsNone(m.step(result=(tag, 99)).finished)

    def test_deterministic_random_prefix_cuts(self):
        rng = random.Random(603)
        m = RecoveryModel(generation_bits=3)
        committed_serials, killed_serials = [], set()
        expected_arch = [0] * 32
        for _ in range(1500):
            # Values come from immutable allocation serials, independent of storage.
            available = [e for e in m.entries if not e.issued and not e.done]
            live = [e for e in m.entries if e.tag in m.tokens]
            kwargs = dict(retire_ready=rng.randrange(3) != 0)
            if rng.randrange(3) == 0:
                kwargs.update(allocate=True, dst=rng.randrange(8))
            if available and rng.randrange(2):
                kwargs['issue'] = rng.choice(available).tag
            if live and rng.randrange(2):
                e = rng.choice(live)
                kwargs['result'] = (e.tag, (e.serial * 101 + 7) & 0xFFFFFFFF)
            if m.entries and rng.randrange(5) == 0:
                kwargs['redirect'] = Redirect(0x1000, rng.choice(m.entries).tag, bool(rng.randrange(2)))
            before = {e.tag: (e.serial, e.dst) for e in m.entries}
            event = m.step(**kwargs)
            killed_serials.update(before[tag][0] for tag in event.killed)
            if event.committed:
                serial, dst, value = event.committed
                self.assertNotIn(serial, killed_serials)
                self.assertEqual(value, (serial * 101 + 7) & 0xFFFFFFFF)
                self.assertTrue(not committed_serials or serial > committed_serials[-1])
                committed_serials.append(serial)
                expected_arch[dst] = value
            self.assertEqual(m.arch, expected_arch)
        self.assertGreater(len(committed_serials), 30)
        self.assertGreater(len(killed_serials), 30)


class FetchDrainTests(unittest.TestCase):
    def test_held_request_and_repeated_redirects_preserve_old_offer(self):
        f = FetchDrainModel(0x100)
        self.assertEqual(f.offer(), 0x100)
        self.assertEqual(f.step(redirect=0x200).request, 0x100)
        self.assertEqual(f.step(redirect=0x300).request, 0x100)
        self.assertEqual(f.step(request_ready=True).request, 0x100)
        self.assertIsNone(f.offer())
        e = f.step(response=0xDEAD, packet_ready=False)
        self.assertTrue(e.response_consumed)
        self.assertIsNone(e.packet)
        self.assertEqual(f.offer(), 0x300)
        f.step(request_ready=True)
        self.assertEqual(f.step(response=42, packet_ready=True).packet, (0x300, 42))

    def test_redirect_coincident_response_and_request_acceptance(self):
        f = FetchDrainModel(0x100)
        e = f.step(request_ready=True, redirect=0x200)
        self.assertTrue(e.request_accepted)
        self.assertEqual(e.request, 0x100)
        e = f.step(response=22, packet_ready=True, redirect=0x400)
        self.assertTrue(e.response_consumed)
        self.assertIsNone(e.packet)
        self.assertEqual(f.offer(), 0x400)

    def test_normal_backpressure_and_no_same_edge_response(self):
        f = FetchDrainModel(0x100)
        e = f.step(request_ready=True, response=99, packet_ready=True)
        self.assertFalse(e.response_consumed)
        self.assertIsNone(e.packet)
        self.assertFalse(f.step(response=99).response_consumed)
        e = f.step(response=99, packet_ready=True)
        self.assertEqual(e.packet, (0x100, 99))
        self.assertEqual(f.offer(), 0x104)

    def test_reset_during_drain_and_target_alignment(self):
        f = FetchDrainModel(0x100)
        f.step(request_ready=True, redirect=0x200)
        f.reset()  # Environment cancels response; never replay after reset.
        self.assertEqual(f.offer(), 0x100)
        with self.assertRaises(ValueError):
            f.step(redirect=0x102)
        with self.assertRaises(ValueError):
            Redirect(-4)

    def test_random_stalls_deliver_only_latest_target(self):
        rng = random.Random(60)
        for trial in range(100):
            start = 0x100 + trial * 4
            f = FetchDrainModel(start)
            f.offer()
            target = 0x1000 + trial * 4
            for _ in range(rng.randrange(1, 8)):
                self.assertEqual(f.step(redirect=target).request, start)
                target += 4
            final_target = target - 4
            f.step(request_ready=True)
            for _ in range(rng.randrange(8)):
                self.assertIsNone(f.step().packet)
            self.assertIsNone(f.step(response=0xBAD, packet_ready=True).packet)
            self.assertEqual(f.offer(), final_target)
            f.step(request_ready=True)
            self.assertEqual(f.step(response=trial, packet_ready=True).packet, (final_target, trial))


if __name__ == '__main__':
    unittest.main()
