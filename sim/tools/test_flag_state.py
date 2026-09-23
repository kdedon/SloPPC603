#!/usr/bin/env python3
from dataclasses import replace
import random
import unittest

import flag_state


class FlagStateTest(unittest.TestCase):
    def setUp(self):
        self.seeded = flag_state.ArchitecturalState(
            cr=0x1234_5678,
            xer=0x89AB_CDEF,
            gprs=tuple(0x1000_0000 + index for index in range(32)),
        )

    def test_allocated_masks_preserve_every_untouched_bit(self):
        cases = (
            (flag_state.WritePermissions(write_ca=True), flag_state.CompletionPayload(0, ca=0), 0x1234_5678, 0x89AB_CDEF & ~0x2000_0000),
            (flag_state.WritePermissions(read_so=True, write_ov_so=True), flag_state.CompletionPayload(0, ov=1, so=0), 0x1234_5678, 0x49AB_CDEF),
            (flag_state.WritePermissions(read_so=True, write_cr0=True), flag_state.CompletionPayload(0, cr0=0xA), 0xA234_5678, 0x89AB_CDEF),
            (flag_state.WritePermissions(), flag_state.CompletionPayload(0, 1, 1, 1, 0xF), 0x1234_5678, 0x89AB_CDEF),
        )
        for permissions, payload, expected_cr, expected_xer in cases:
            after = flag_state.apply_commit(self.seeded, flag_state.CommitPacket(permissions, payload))
            self.assertEqual((after.cr, after.xer), (expected_cr, expected_xer))
            self.assertEqual(after.gprs, self.seeded.gprs)

    def test_add_boundaries_have_explicit_carry_overflow_and_final_so(self):
        anchors = (
            (0xFFFF_FFFF, 1, (0, 1, 0, 0, 0x2)),
            (0x7FFF_FFFF, 1, (0x8000_0000, 0, 1, 1, 0x9)),
            (0x8000_0000, 0x8000_0000, (0, 1, 1, 1, 0x3)),
        )
        for a, b, expected in anchors:
            prepared = flag_state.prepare_add("addc", a, b, oe=1, rc=1)
            payload = prepared.payload
            self.assertEqual((payload.value, payload.ca, payload.ov, payload.so, payload.cr0), expected)
        addme = flag_state.prepare_add("addme", 0x8000_0000, ca_in=0, oe=1, rc=1)
        self.assertEqual(
            (addme.payload.value, addme.payload.ca, addme.payload.ov, addme.payload.so, addme.payload.cr0),
            (0x7FFF_FFFF, 1, 1, 1, 0x5),
        )

    def test_negative_final_so_and_sticky_so_mutations_are_rejected(self):
        request = flag_state.AllocationRequest(
            flag_state.OwnerTag(0, 7),
            flag_state.WritePermissions(read_so=True, write_ov_so=True, write_cr0=True),
        )
        incoming_zero = flag_state.CapturedAllocation(request, ca_in=0, so_in=0)
        overflow = flag_state.CompletionPayload(0x8000_0000, ov=1, so=1, cr0=0x9)
        flag_state.validate_completion(incoming_zero, overflow)
        with self.assertRaisesRegex(flag_state.FlagStateError, "final SO"):
            flag_state.validate_completion(incoming_zero, replace(overflow, cr0=0x8))

        incoming_one = flag_state.CapturedAllocation(request, ca_in=0, so_in=1)
        no_overflow = flag_state.CompletionPayload(1, ov=0, so=1, cr0=0x5)
        flag_state.validate_completion(incoming_one, no_overflow)
        # Using OV instead of final sticky SO writes zero into CR0.SO.
        with self.assertRaisesRegex(flag_state.FlagStateError, "final SO"):
            flag_state.validate_completion(incoming_one, replace(no_overflow, cr0=0x4))
        # Clearing SO on a nonoverflowing OE instruction loses incoming history.
        with self.assertRaisesRegex(flag_state.FlagStateError, "Sticky SO|sticky SO"):
            flag_state.validate_completion(incoming_one, replace(no_overflow, so=0, cr0=0x4))

        # Incoming SO is clear, so an overflowing instruction must still set SO.
        with self.assertRaisesRegex(flag_state.FlagStateError, "incoming SO OR current OV"):
            flag_state.validate_completion(
                incoming_zero,
                flag_state.CompletionPayload(0x8000_0000, ov=1, so=0, cr0=0x8),
            )
        # A one-hot relation is insufficient when it disagrees with the result.
        with self.assertRaisesRegex(flag_state.FlagStateError, "signed result value"):
            flag_state.validate_completion(incoming_zero, replace(overflow, cr0=0x5))

    def test_negative_untouched_ca_and_cr_mutations_are_detected(self):
        prepared = flag_state.prepare_logical("xor", 0xAAAA_AAAA, 0x5555_5555, rc=0)
        packet = flag_state.CommitPacket(prepared.permissions, prepared.payload, gpr_write=True, gpr=9)
        correct = flag_state.apply_commit(self.seeded, packet)
        self.assertEqual(correct.gprs[9], 0xFFFF_FFFF)
        flag_state.check_commit_transition(self.seeded, packet, correct)
        with self.assertRaisesRegex(flag_state.FlagStateError, "atomic commit"):
            flag_state.check_commit_transition(self.seeded, packet, replace(correct, xer=correct.xer ^ 0x2000_0000))
        with self.assertRaisesRegex(flag_state.FlagStateError, "atomic commit"):
            flag_state.check_commit_transition(self.seeded, packet, replace(correct, cr=correct.cr ^ 0x1000_0000))

    def test_malformed_commit_is_rejected_before_gpr_or_flags_change(self):
        before = self.seeded
        with self.assertRaisesRegex(flag_state.FlagStateError, "five-bit"):
            flag_state.CommitPacket(
                flag_state.WritePermissions(read_so=True, write_cr0=True),
                flag_state.CompletionPayload(0xDEAD_BEEF, cr0=0x8),
                gpr_write=True,
                gpr=32,
            )
        self.assertIs(before, self.seeded)
        self.assertEqual((self.seeded.gprs[31], self.seeded.cr, self.seeded.xer), (0x1000_001F, 0x1234_5678, 0x89AB_CDEF))

    def test_one_owner_exact_finish_and_no_finish_to_commit_bypass(self):
        model = flag_state.FlagOwnerModel(self.seeded)
        tag = flag_state.OwnerTag(2, 9)
        request = flag_state.AllocationRequest(tag, flag_state.WritePermissions(write_ca=True), gpr=4)
        outcome = model.advance(allocate=request)
        self.assertTrue(outcome.acquired)
        self.assertEqual((outcome.captured.ca_in, outcome.captured.so_in), (0, 1))

        wrong = flag_state.OwnerTag(2, 8)
        payload = flag_state.CompletionPayload(0xCAFE_BABE, ca=1)
        self.assertFalse(model.advance(finish=(wrong, payload)).wake)
        same_edge = model.advance(finish=(tag, payload), retire=tag)
        self.assertTrue(same_edge.finished)
        self.assertFalse(same_edge.retired)
        self.assertEqual(model.state, self.seeded)
        committed = model.advance(retire=tag)
        self.assertTrue(committed.retired)
        self.assertEqual((model.state.gprs[4], model.state.xer), (0xCAFE_BABE, 0xA9AB_CDEF))

    def test_read_only_owner_has_no_gpr_wake_and_tags_are_bounded(self):
        model = flag_state.FlagOwnerModel(self.seeded)
        tag = flag_state.OwnerTag(4, 255)
        request = flag_state.AllocationRequest(
            tag, flag_state.WritePermissions(read_ca=True), gpr_write=False
        )
        self.assertTrue(model.advance(allocate=request).acquired)
        finish = model.advance(finish=(tag, flag_state.CompletionPayload(0xDEAD_BEEF)))
        self.assertTrue(finish.finished)
        self.assertFalse(finish.wake)
        with self.assertRaisesRegex(flag_state.FlagStateError, "five completion slots"):
            flag_state.OwnerTag(5, 0)
        with self.assertRaisesRegex(flag_state.FlagStateError, "eight-bit"):
            flag_state.OwnerTag(0, 256)

    def test_release_edge_cannot_acquire_younger_owner(self):
        model = flag_state.FlagOwnerModel(self.seeded)
        old = flag_state.OwnerTag(0, 1)
        new = flag_state.OwnerTag(1, 2)
        permissions = flag_state.WritePermissions(read_so=True, write_cr0=True)
        model.advance(allocate=flag_state.AllocationRequest(old, permissions, gpr=3))
        model.advance(finish=(old, flag_state.CompletionPayload(7, cr0=0x5)))
        release_edge = model.advance(
            retire=old,
            allocate=flag_state.AllocationRequest(new, permissions, gpr=5),
        )
        self.assertTrue(release_edge.retired)
        self.assertFalse(release_edge.acquired)
        self.assertFalse(model.busy)
        following = model.advance(allocate=flag_state.AllocationRequest(new, permissions, gpr=5))
        self.assertTrue(following.acquired)

    def test_killed_same_edge_finish_cannot_wake_or_change_state(self):
        model = flag_state.FlagOwnerModel(self.seeded)
        tag = flag_state.OwnerTag(4, 12)
        request = flag_state.AllocationRequest(tag, flag_state.WritePermissions(write_ca=True), gpr=7)
        model.advance(allocate=request)
        before = model.state
        outcome = model.advance(
            finish=(tag, flag_state.CompletionPayload(0xBAD0_0001, ca=1)),
            post_commit_survivors=(),
        )
        self.assertTrue(outcome.killed)
        self.assertFalse(outcome.finished)
        self.assertFalse(outcome.wake)
        self.assertFalse(model.busy)
        self.assertEqual(model.state, before)

    def test_redirect_keep_finish_and_post_commit_owner_release(self):
        model = flag_state.FlagOwnerModel(self.seeded)
        tag = flag_state.OwnerTag(3, 21)
        request = flag_state.AllocationRequest(tag, flag_state.WritePermissions(read_so=True, write_cr0=True), gpr=8)
        model.advance(allocate=request)
        payload = flag_state.CompletionPayload(0, cr0=0x3)
        unfinished = model.advance(finish=(tag, payload), retire=tag, post_commit_survivors=(tag,))
        self.assertTrue(unfinished.finished)
        self.assertFalse(unfinished.retired)
        committed = model.advance(retire=tag, post_commit_survivors=())
        self.assertTrue(committed.retired)
        self.assertFalse(committed.killed)
        self.assertFalse(model.busy)
        self.assertEqual((model.state.gprs[8], model.state.cr), (0, 0x3234_5678))

    def test_malformed_recovery_owner_snapshots_are_rejected_before_mutation(self):
        tag = flag_state.OwnerTag(3, 21)
        other = flag_state.OwnerTag(4, 22)
        permissions = flag_state.WritePermissions(read_so=True, write_cr0=True)

        model = flag_state.FlagOwnerModel(self.seeded)
        model.advance(allocate=flag_state.AllocationRequest(tag, permissions, gpr=8))
        before_owner, before_state = model.owner, model.state
        with self.assertRaisesRegex(flag_state.FlagStateError, "exact allocated"):
            model.advance(post_commit_survivors=(other,))
        self.assertEqual((model.owner, model.state), (before_owner, before_state))
        with self.assertRaisesRegex(flag_state.FlagStateError, "duplicate"):
            model.advance(post_commit_survivors=(tag, tag))
        self.assertEqual((model.owner, model.state), (before_owner, before_state))

        payload = flag_state.CompletionPayload(0, cr0=0x3)
        model.advance(finish=(tag, payload))
        before_owner, before_state = model.owner, model.state
        with self.assertRaisesRegex(flag_state.FlagStateError, "absent from post-commit"):
            model.advance(retire=tag, post_commit_survivors=(tag,))
        self.assertEqual((model.owner, model.state), (before_owner, before_state))

        empty = flag_state.FlagOwnerModel(self.seeded)
        with self.assertRaisesRegex(flag_state.FlagStateError, "none is allocated"):
            empty.advance(post_commit_survivors=(other,))
        self.assertEqual(empty.state, self.seeded)

    def test_gpr_only_commit_and_flag_free_dispatch_ignore_busy_token(self):
        prepared = flag_state.prepare_logical("or", 0x8000_0000, 1, rc=0, ca_in=1, ov_in=1, so_in=1)
        self.assertFalse(prepared.permissions.needs_flags)
        after = flag_state.apply_commit(
            self.seeded,
            flag_state.CommitPacket(prepared.permissions, prepared.payload, gpr_write=True, gpr=0),
        )
        self.assertEqual(after.gprs[0], 0x8000_0001)
        self.assertEqual((after.cr, after.xer), (self.seeded.cr, self.seeded.xer))

        model = flag_state.FlagOwnerModel(self.seeded)
        model.advance(allocate=flag_state.AllocationRequest(flag_state.OwnerTag(0, 1), flag_state.WritePermissions(write_ca=True)))
        flag_free = flag_state.AllocationRequest(flag_state.OwnerTag(1, 1), prepared.permissions, gpr=2)
        self.assertTrue(model.advance(allocate=flag_free).acquired)
        self.assertEqual(model.owner.request.tag, flag_state.OwnerTag(0, 1))

    def test_shift_ca_permissions_and_explicit_boundary_values(self):
        anchors = (
            ("sraw", 0xF000_0001, 1, 0xF800_0000, 1),
            ("sraw", 0x8000_0000, 32, 0xFFFF_FFFF, 1),
            ("srawi", 0xF000_0000, 1, 0xF800_0000, 0),
        )
        for family, source, count, value, ca in anchors:
            prepared = flag_state.prepare_shift(family, source, count, rc=1, so_in=1)
            self.assertEqual((prepared.payload.value, prepared.payload.ca, prepared.payload.cr0), (value, ca, 0x9))
            self.assertTrue(prepared.permissions.write_ca)
            self.assertFalse(prepared.permissions.write_ov_so)

    def test_deterministic_random_mask_preservation_and_atomicity(self):
        rng = random.Random(0x603E_C001)
        families = tuple(("add", "addc", "adde", "addme", "addze"))
        for _ in range(500):
            cr = rng.getrandbits(32)
            xer = rng.getrandbits(32)
            gprs = tuple(rng.getrandbits(32) for _ in range(32))
            before = flag_state.ArchitecturalState(cr, xer, gprs)
            family = rng.choice(families)
            oe, rc, ca_in = rng.randrange(2), rng.randrange(2), rng.randrange(2)
            prepared = flag_state.prepare_add(
                family, rng.getrandbits(32), rng.getrandbits(32), ca_in=ca_in,
                oe=oe, rc=rc, ov_in=int(bool(xer & flag_state.XER_OV_MASK)),
                so_in=int(bool(xer & flag_state.XER_SO_MASK)), old_cr0=cr >> 28,
            )
            gpr = rng.randrange(32)
            packet = flag_state.CommitPacket(prepared.permissions, prepared.payload, True, gpr)
            after = flag_state.apply_commit(before, packet)
            self.assertEqual(after.gprs[gpr], prepared.payload.value)
            self.assertEqual(after.cr & ~prepared.permissions.cr_mask, cr & ~prepared.permissions.cr_mask)
            self.assertEqual(after.xer & ~prepared.permissions.xer_mask, xer & ~prepared.permissions.xer_mask)
            self.assertEqual(after.cr & prepared.permissions.cr_mask, (prepared.payload.cr0 << 28) & prepared.permissions.cr_mask)
            packed_xer = (prepared.payload.so << 31) | (prepared.payload.ov << 30) | (prepared.payload.ca << 29)
            self.assertEqual(after.xer & prepared.permissions.xer_mask, packed_xer & prepared.permissions.xer_mask)
            flag_state.check_commit_transition(before, packet, after)


if __name__ == "__main__":
    unittest.main()
