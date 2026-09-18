#!/usr/bin/env python3
"""Independent mutation tests invoking the complete tier-2 verifier.

Scratch stays under /srv/modfs/build and is retained. No mounts required.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
# Point at a saved pre-fix script to demonstrate the regression without reverting.
VERIFIER = Path(os.environ.get('MODFS_VERIFY_SCRIPT', REPO / 'scripts/verify_compose.py'))


class VerificationFixture(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix='verify-test-', dir='/srv/modfs/build'))
        self.layer = self.root / 'layer'
        self.merged = self.root / 'merged'
        self.layer.mkdir()
        self.put(self.layer, 'var/lib/dpkg/status',
                 'Package: fixture\nStatus: install ok installed\nVersion: 1\n')
        self.put(self.layer, 'var/cache/debconf/config.dat',
                 'Name: q\nTemplate: q\nValue: yes\nOwners: alpha, beta\n')
        self.put(self.layer, 'var/cache/debconf/templates.dat',
                 'Name: q\nType: string\nDescription: text\n continuation\nOwners: alpha\n')
        for name, text in {
            'passwd': 'root:x:0:0:root:/root:/bin/sh\n',
            'group': 'root:x:0:root\n',
            'shadow': 'root:!:20000:0:99999:7:::\n',
            'gshadow': 'root:!::root\n',
            'subuid': 'root:100000:65536\n',
            'subgid': 'root:100000:65536\n',
        }.items():
            self.put(self.layer, 'etc/' + name, text)
            (self.layer / 'etc' / name).chmod(0o640 if 'shadow' in name else 0o644)
        shutil.copytree(self.layer, self.merged)
        (self.root / 'actual.pkgs').write_text('fixture\t1\n')
        (self.root / 'actual.ld').write_text('')
        (self.root / 'audit.txt').write_text('')

    def put(self, root, relative, text):
        p = root / relative
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
        return p

    def verify(self, good):
        p = subprocess.run(['python3', str(VERIFIER),
                            '--scripts', str(REPO / 'scripts'),
                            '--merged', str(self.merged), '--work', str(self.root),
                            '--index', '1', '--n', '1', '--admitted', 'yes',
                            '--mount-ms', '0', '--reconcile-ms', '0', '--total-ms', '0',
                            'fixture=' + str(self.layer)], text=True, capture_output=True)
        self.assertEqual(p.stdout.strip().split(',')[-1], 'PASS' if good else 'FAIL',
                         p.stdout + p.stderr)
        # This CSV-producing helper returns 0 for a completed FAIL observation.
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)


class DebconfTests(VerificationFixture):
    def test_control(self):
        self.verify(True)

    def test_names_only(self):
        for leaf in ('config', 'templates'):
            self.put(self.merged, 'var/cache/debconf/' + leaf + '.dat', 'Name: q\n')
        self.verify(False)

    def test_changed_answer(self):
        p = self.merged / 'var/cache/debconf/config.dat'
        p.write_text(p.read_text().replace('Value: yes', 'Value: no'))
        self.verify(False)

    def test_missing_owner(self):
        p = self.merged / 'var/cache/debconf/config.dat'
        p.write_text(p.read_text().replace('alpha, beta', 'alpha'))
        self.verify(False)

    def test_owner_order_is_semantic(self):
        p = self.merged / 'var/cache/debconf/config.dat'
        p.write_text(p.read_text().replace('alpha, beta', 'beta, alpha, beta'))
        self.verify(True)

    def test_duplicate_name(self):
        p = self.merged / 'var/cache/debconf/config.dat'
        p.write_text(p.read_text() + '\n' + p.read_text())
        self.verify(False)

    def test_extra_record(self):
        p = self.merged / 'var/cache/debconf/config.dat'
        p.write_text(p.read_text() + '\nName: unexpected\nValue: yes\n')
        self.verify(False)

    def test_duplicate_field(self):
        p = self.merged / 'var/cache/debconf/config.dat'
        p.write_text(p.read_text() + 'Value: no\n')
        self.verify(False)


if __name__ == '__main__':
    unittest.main(verbosity=2)
