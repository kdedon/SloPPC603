import contextlib
import io
from pathlib import Path
import subprocess
import tempfile
import unittest

from reference_checkout import verify


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
            verify(self.ref/'absent', False)

    def test_unpinned_commit_rejected(self):
        with self.assertRaisesRegex(RuntimeError, 'allow-unpinned-reference'):
            verify(self.ref, False)

    def test_override_warns_and_records(self):
        (self.ref/'cpu/ppc/ppcopcodes.cpp').write_text('dirty')
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            head, dirty = verify(self.ref, True)
        self.assertEqual(len(head), 40)
        self.assertTrue(dirty)
        self.assertIn('uncommitted', stderr.getvalue())


if __name__ == '__main__':
    unittest.main()
