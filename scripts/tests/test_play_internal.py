import hashlib
import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('publisher', Path(__file__).parents[1] / 'play_internal.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PublishingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.bundle = Path(self.temp.name) / 'test.aab'
        self.bundle.write_bytes(b'synthetic bundle')
        self.calls = []
        self.fail = None
        self.used = 17

    def request(self, session, method, url, **kwargs):
        self.calls.append((method, url, kwargs))
        if self.fail and self.fail in url:
            raise RuntimeError('synthetic failure')
        if url.endswith('/edits'):
            return {'id': 'edit-1'}
        if url.endswith('/bundles'):
            return {'bundles': [{'versionCode': self.used}]}
        if url.endswith('/apks'):
            return {}
        if 'uploadType=media' in url:
            return {'versionCode': 18, 'sha256': hashlib.sha256(self.bundle.read_bytes()).hexdigest()}
        return {}

    def run_publish(self):
        with patch.object(module, 'call', self.request):
            return module.publish(None, self.bundle, 18, '1.0.18', 'Test release')

    def test_only_internal_and_validate_before_commit(self):
        self.assertEqual(self.run_publish()['status'], 'committed')
        puts = [c for c in self.calls if c[0] == 'PUT']
        self.assertEqual(len(puts), 1)
        self.assertTrue(puts[0][1].endswith('/tracks/internal'))
        self.assertEqual(puts[0][2]['json']['releases'][0]['versionCodes'], ['18'])
        self.assertTrue(self.calls[-2][1].endswith(':validate'))
        self.assertTrue(self.calls[-1][1].endswith(':commit'))

    def test_reused_version_does_not_upload_and_discards_edit(self):
        self.used = 18
        with self.assertRaisesRegex(RuntimeError, 'not newer'):
            self.run_publish()
        self.assertFalse(any('uploadType=' in c[1] for c in self.calls))
        self.assertEqual(self.calls[-1][0], 'DELETE')

    def test_validation_failure_never_commits(self):
        self.fail = ':validate'
        with self.assertRaises(RuntimeError):
            self.run_publish()
        self.assertFalse(any(c[1].endswith(':commit') for c in self.calls))
        self.assertEqual(self.calls[-1][0], 'DELETE')

    def test_uncertain_commit_is_not_retried_or_deleted(self):
        self.fail = ':commit'
        with self.assertRaises(RuntimeError):
            self.run_publish()
        self.assertEqual(sum(c[1].endswith(':commit') for c in self.calls), 1)
        self.assertNotIn('DELETE', [c[0] for c in self.calls])


if __name__ == '__main__':
    unittest.main()
