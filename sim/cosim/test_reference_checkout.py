# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
import contextlib
import io
from pathlib import Path
import subprocess
import tempfile
import unittest

from reference_checkout import positive_seed, verify, xrand_build_flags, xrand_run_args


class ReferenceCheckoutTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.ref = Path(self.tmp.name)
        (self.ref/'cpu/ppc').mkdir(parents=True)
        (self.ref/'cpu/ppc/ppcopcodes.cpp').write_text('')
        git = ['git', '-C', str(self.ref), '-c', 'user.name=t', '-c', 'user.email=t@t']
        subprocess.run([*git, 'init', '-q'], check=True)
        subprocess.run([*git, 'add', '.'], check=True)
        subprocess.run([*git, 'commit', '-qm', 'x'], check=True)

    def tearDown(self):
        self.tmp.cleanup()

    def test_missing_checkout_rejected(self):
        with self.assertRaisesRegex(RuntimeError, 'not found'):
            verify(self.ref/'absent')

    def test_any_commit_accepted_with_log_hint(self):
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr), contextlib.redirect_stdout(io.StringIO()):
            head, dirty = verify(self.ref)
        self.assertEqual(len(head), 40)
        self.assertFalse(dirty)
        self.assertIn('differs from last verified', stderr.getvalue())
        self.assertIn('log --oneline', stderr.getvalue())

    def test_dirty_tree_accepted_and_reported(self):
        (self.ref/'cpu/ppc/ppcopcodes.cpp').write_text('dirty')
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(io.StringIO()):
            _, dirty = verify(self.ref)
        self.assertTrue(dirty)
        self.assertIn('uncommitted changes', stdout.getvalue())


class XrandArgumentsTest(unittest.TestCase):
    def test_no_seed_keeps_zero_initialization(self):
        self.assertEqual(xrand_build_flags(None), [])
        self.assertEqual(xrand_run_args(None), [])

    def test_seed_randomizes_build_and_run(self):
        self.assertEqual(xrand_build_flags(7), ['--x-assign', 'unique', '--x-initial', 'unique'])
        self.assertEqual(xrand_run_args(7), ['+verilator+seed+7', '+verilator+rand+reset+2'])

    def test_nonpositive_seed_rejected(self):
        with self.assertRaises(ValueError):
            positive_seed('0')


if __name__ == '__main__':
    unittest.main()
