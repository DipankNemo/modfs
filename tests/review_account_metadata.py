#!/usr/bin/env python3
"""M2: repack the real curl delta, then exercise honest extraction and admission.
Root required. All changed artefacts and scratch are retained under build.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]

class AccountMetadataTests(unittest.TestCase):
    def check_case(self, rel=None, name=None, field=None, value=None, remove=False):
        root = Path(tempfile.mkdtemp(prefix='account-metadata-', dir='/srv/modfs/build'))
        mods = root / 'modules'
        mods.mkdir()
        for suffix in ('.json', '.files.json.zst', '.sqsh'):
            if suffix == '.sqsh':
                (mods / ('base' + suffix)).symlink_to('/srv/modfs/modules/base' + suffix)
            else:
                shutil.copy2('/srv/modfs/modules/base' + suffix, mods / ('base' + suffix))
        def run(args):
            p = subprocess.run(args, cwd=REPO, env=dict(os.environ, MODFS_ROOT=str(root)),
                               text=True, capture_output=True)
            self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
            return p.stdout
        run(['unsquashfs', '-no-progress', '-d', str(root / 'delta'), '/srv/modfs/modules/curl.sqsh'])
        if rel:
            contents = run(['unsquashfs', '-cat', '/srv/modfs/modules/base.sqsh', rel])
            rows = []
            for line in contents.splitlines():
                parts = line.split(':')
                if parts[0] == name:
                    if remove:
                        continue
                    parts[field] = value
                rows.append(':'.join(parts))
            (root / 'delta' / rel).write_text('\n'.join(rows) + '\n')
        run(['mksquashfs', str(root / 'delta'), str(mods / 'curl.sqsh'), '-noappend',
             '-comp', 'zstd', '-no-progress', '-processors', '2'])
        run(['scripts/06_extract_metadata.sh', 'curl', '--version', '1.0'])
        run(['scripts/12_verify_binding.sh', 'curl'])
        p = subprocess.run(['scripts/05_check.sh', 'curl'], cwd=REPO,
                           env=dict(os.environ, MODFS_ROOT=str(root)), text=True, capture_output=True)
        rejected = remove or (rel and field in (2, 3) and rel == 'etc/passwd') or (rel == 'etc/group' and field == 2)
        self.assertEqual(p.returncode, 1 if rejected else 0, p.stdout + p.stderr)
        if rejected:
            self.assertRegex(p.stdout, r'IDENTITY (COLLISION|REMOVAL)')

    def test_inherited_unchanged(self): self.check_case()
    def test_changed_uid(self): self.check_case('etc/passwd', '_apt', 2, '0')
    def test_changed_primary_gid(self): self.check_case('etc/passwd', '_apt', 3, '0')
    def test_changed_group_gid(self): self.check_case('etc/group', 'nogroup', 2, '0')
    def test_removed_user(self): self.check_case('etc/passwd', '_apt', remove=True)
    def test_removed_group(self): self.check_case('etc/group', 'nogroup', remove=True)
    def test_legitimate_membership(self): self.check_case('etc/group', 'adm', 3, 'root')

if __name__ == '__main__': unittest.main(verbosity=2)
