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
        self.layers = [('fixture', self.layer)]
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
                            *[name + '=' + str(path) for name, path in self.layers]],
                           text=True, capture_output=True)
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


class SymlinkTests(VerificationFixture):
    def link(self, root, target):
        p = root / 'usr/bin/python3'
        p.parent.mkdir(parents=True, exist_ok=True)
        p.symlink_to(target)

    def test_relative_control(self):
        self.link(self.layer, 'python3.10')
        self.link(self.merged, 'python3.10')
        self.verify(True)

    def test_absolute_not_traversed(self):
        self.link(self.layer, '/nonexistent-on-host')
        self.link(self.merged, '/nonexistent-on-host')
        self.verify(True)

    def test_different_length_target(self):
        self.link(self.layer, 'python3.10')
        self.link(self.merged, 'no-such-python')
        self.verify(False)

    def test_same_length_target(self):
        self.link(self.layer, 'python3.10')
        self.link(self.merged, 'python9.99')
        self.verify(False)

    def test_offered_replacement_allowed(self):
        self.link(self.layer, 'python3.10')
        upper = self.root / 'upper'
        self.link(upper, 'python3.11')
        self.layers.append(('upper', upper))
        self.link(self.merged, 'python3.11')
        self.verify(True)


class AccountTests(VerificationFixture):
    def test_control(self):
        self.verify(True)

    def test_shadow_names_only(self):
        (self.merged / 'etc/shadow').write_text('root:*\n')
        self.verify(False)

    def test_shadow_password(self):
        p = self.merged / 'etc/shadow'
        p.write_text(p.read_text().replace('root:!', 'root:'))
        self.verify(False)

    def test_shadow_age(self):
        p = self.merged / 'etc/shadow'
        p.write_text(p.read_text().replace('20000', '20001'))
        self.verify(False)

    def test_shadow_mode(self):
        (self.merged / 'etc/shadow').chmod(0o644)
        self.verify(False)

    @unittest.skipUnless(os.geteuid() == 0, 'chown needs root')
    def test_shadow_owner(self):
        os.chown(self.merged / 'etc/shadow', 1234, 1234)
        self.verify(False)

    def test_passwd_shell(self):
        p = self.merged / 'etc/passwd'
        p.write_text(p.read_text().replace('/bin/sh', '/bin/false'))
        self.verify(False)

    def test_extra_account(self):
        p = self.merged / 'etc/passwd'
        p.write_text(p.read_text() + 'extra:x:0:0::/root:/bin/sh\n')
        self.verify(False)

    def test_extra_member(self):
        (self.merged / 'etc/group').write_text('root:x:0:root,extra\n')
        self.verify(False)

    def test_lost_subuid(self):
        (self.merged / 'etc/subuid').write_text('')
        self.verify(False)

    def test_changed_subgid(self):
        (self.merged / 'etc/subgid').write_text('root:200000:65536\n')
        self.verify(False)

    def test_duplicate_account(self):
        p = self.merged / 'etc/passwd'
        p.write_text(p.read_text() * 2)
        self.verify(False)

    def test_member_order(self):
        (self.layer / 'etc/group').write_text('root:x:0:root,other\n')
        (self.merged / 'etc/group').write_text('root:x:0:other,root\n')
        self.verify(True)

    def test_range_order(self):
        (self.layer / 'etc/subuid').write_text('root:100000:65536\nroot:200000:65536\n')
        (self.merged / 'etc/subuid').write_text('root:200000:65536\nroot:100000:65536\n')
        self.verify(True)

    def test_declared_nonidentity_override(self):
        upper = self.root / 'upper'
        text = 'root:x:0:0:root:/srv/root:/bin/bash\n'
        self.put(upper, 'etc/passwd', text)
        self.layers.append(('upper', upper))
        (self.merged / 'etc/passwd').write_text(text)
        self.verify(True)

    def test_member_union(self):
        upper = self.root / 'upper'
        self.put(upper, 'etc/group', 'root:x:0:other\n')
        self.layers.append(('upper', upper))
        (self.merged / 'etc/group').write_text('root:x:0:other,root\n')
        self.verify(True)


if __name__ == '__main__':
    unittest.main(verbosity=2)
