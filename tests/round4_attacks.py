#!/usr/bin/env python3
"""Round-four registry attacks against the shipped reconcile.py.

FIXED cases are reproduced defects; CONTROL cases cover valid input and
format edges that the hardening must continue to accept. No root is needed.
"""
import pathlib
import os
import subprocess
import sys
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = REPO / 'scripts' / 'reconcile.py'


class RegistryAttacks(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='round4-')
        self.addCleanup(self.tmp.cleanup)
        self.root = pathlib.Path(self.tmp.name)

    def put(self, layer, rel, body):
        path = self.root / layer / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(body.encode())

    def run_merge(self, *layers):
        merged = self.root / 'merged'
        args = [sys.executable, str(SCRIPT), '--merged', str(merged)]
        args += [f'{name}={self.root / name}' for name in layers]
        result = subprocess.run(args, capture_output=True, text=True)
        return result, merged

    def test_fixed_primary_gid_conflict(self):
        self.put('base', 'etc/passwd', 'svc:x:2500:2500::/srv:/bin/false\n')
        self.put('delta', 'etc/passwd', 'svc:x:2500:2600::/srv:/bin/false\n')
        result, merged = self.run_merge('base', 'delta')
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn('primary gid 2500 and 2600', result.stdout)
        self.assertEqual((merged / 'etc/passwd').read_text(),
                         'svc:x:2500:2600::/srv:/bin/false\n')

    def test_fixed_duplicate_member_normalisation(self):
        self.put('base', 'etc/group', 'grp:x:2500:alice,alice,,bob\n')
        self.put('delta', 'etc/group', 'grp:x:2500:bob,carol,carol,\n')
        result, merged = self.run_merge('base', 'delta')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((merged / 'etc/group').read_text(),
                         'grp:x:2500:alice,bob,carol\n')

    def test_fixed_incomplete_diversion_is_reported(self):
        self.put('base', 'var/lib/dpkg/diversions',
                 '/one\n/one.distrib\npkg\n/two\n/two.distrib\n')
        result, merged = self.run_merge('base')
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn('malformed diversions', result.stdout)
        self.assertFalse((merged / 'var/lib/dpkg/diversions').exists())

    def test_control_valid_diversions_without_final_newline(self):
        self.put('base', 'var/lib/dpkg/diversions', '/one\n/one.distrib\npkg')
        result, merged = self.run_merge('base')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((merged / 'var/lib/dpkg/diversions').read_text(),
                         '/one\n/one.distrib\npkg\n')

    def test_control_crlf_accounts_and_empty_members(self):
        self.put('base', 'etc/group', 'grp:x:2500:alice,,bob\r\n')
        result, merged = self.run_merge('base')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((merged / 'etc/group').read_text(),
                         'grp:x:2500:alice,bob\n')

    def test_control_case_distinct_account_names(self):
        self.put('base', 'etc/passwd', 'Alice:x:2500:2500::/srv:/bin/false\n')
        self.put('delta', 'etc/passwd', 'alice:x:2501:2501::/srv:/bin/false\n')
        result, merged = self.run_merge('base', 'delta')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len((merged / 'etc/passwd').read_text().splitlines()), 2)

    def test_fixed_extra_account_field_is_reported(self):
        self.put('base', 'etc/passwd', 'svc:x:2500:2500::/srv:/bin/false:extra\n')
        result, merged = self.run_merge('base')
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn('malformed record', result.stdout)
        self.assertEqual((merged / 'etc/passwd').read_text(), '')

    def test_fixed_short_subuid_record_is_reported(self):
        self.put('base', 'etc/subuid', 'svc:100000\n')
        result, merged = self.run_merge('base')
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn('etc/subuid malformed record', result.stdout)
        self.assertEqual((merged / 'etc/subuid').read_text(), '')

    def test_control_valid_subuid_without_final_newline(self):
        self.put('base', 'etc/subuid', 'svc:100000:65536')
        result, merged = self.run_merge('base')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((merged / 'etc/subuid').read_text(),
                         'svc:100000:65536\n')

    def test_fixed_repeated_unit_identity_uses_last_value(self):
        # Execute the actual unit extraction block in its minimal tree context.
        source = (REPO / 'scripts' / '06_extract_metadata.sh').read_text()
        start = source.index('units = {}\n')
        end = source.index('# ---------------------------------------------------------------- assemble', start)
        self.put('tree', 'usr/lib/systemd/system/sample.service',
                 '[Service]\nUser=root\nUser=missinguser\nGroup=root\nGroup=missinggroup\n')
        scope = {'tree': str(self.root / 'tree'), 'os': os}
        exec(source[start:end], scope)
        self.assertEqual(scope['units']['sample.service'],
                         {'user': 'missinguser', 'group': 'missinggroup',
                          'supplementary': []})

    def test_control_single_unit_identity(self):
        source = (REPO / 'scripts' / '06_extract_metadata.sh').read_text()
        start = source.index('units = {}\n')
        end = source.index('# ---------------------------------------------------------------- assemble', start)
        self.put('tree', 'usr/lib/systemd/system/sample.service',
                 '[Service]\nUser=service\nGroup=service\n')
        scope = {'tree': str(self.root / 'tree'), 'os': os}
        exec(source[start:end], scope)
        self.assertEqual(scope['units']['sample.service']['user'], 'service')

    def account_view(self, body):
        source = (REPO / 'scripts' / '06_extract_metadata.sh').read_text()
        start = source.index('def colon_table(')
        end = source.index('own_u, own_g,', start)
        self.put('tree', 'etc/passwd', body)
        scope = {'os': os, 'warn': lambda *_: None}
        exec(source[start:end], scope)
        return scope['account_view'](str(self.root / 'tree'))

    def test_fixed_short_account_record_rejected_at_extraction(self):
        with self.assertRaisesRegex(ValueError, 'malformed etc/passwd'):
            self.account_view('svc:x:2500:2500\n')

    def test_fixed_duplicate_account_rejected_at_extraction(self):
        with self.assertRaisesRegex(ValueError, 'duplicate etc/passwd'):
            self.account_view('svc:x:2500:2500::/srv:/bin/false\n'
                              'svc:x:2501:2501::/srv:/bin/false\n')

    def test_control_valid_account_without_final_newline(self):
        users, _, _, _ = self.account_view('svc:x:2500:2500::/srv:/bin/false')
        self.assertEqual(users['svc'], {'uid': '2500', 'gid': '2500'})

    def extracted_diversions(self, body):
        source = (REPO / 'scripts' / '06_extract_metadata.sh').read_text()
        start = source.index('diversions = []\n')
        end = source.index("sidecar = {'schema'", start)
        self.put('tree', 'var/lib/dpkg/diversions', body)
        scope = {'tree': str(self.root / 'tree'), 'os': os,
                 'warn': lambda *_: None}
        exec(source[start:end], scope)
        return scope['diversions']

    def test_fixed_incomplete_diversion_rejected_at_extraction(self):
        with self.assertRaisesRegex(ValueError, 'malformed diversions'):
            self.extracted_diversions('/one\n/one.distrib\npkg\n/two\n/two.distrib\n')

    def test_control_valid_diversion_extraction_without_final_newline(self):
        self.assertEqual(self.extracted_diversions('/one\n/one.distrib\npkg'),
                         [{'path': '/one', 'to': '/one.distrib', 'by': 'pkg'}])


if __name__ == '__main__':
    unittest.main(verbosity=2)
