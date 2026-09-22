#!/usr/bin/env python3
"""FIXED/CONTROL: run the full tier-one checker on sealed synthetic manifests.

A missing nested gid-owner field must never print the ownership [OK] claim.
No artefact mounts or writes outside TemporaryDirectory are needed.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / 'scripts'))
from generation import generation
from manifest_binding import BIND_FIELDS, bind_digest


@unittest.skipUnless(shutil.which('zstd'), 'project sidecar codec unavailable')
class Class7OwnerFields(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='round4-class7-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.mod_dir = self.root / 'modules'
        self.mod_dir.mkdir()
        gen = generation('20260701T000000Z', 'jammy', 'amd64', 'a' * 64)
        for name in ('base', 'delta'):
            art = {'file': name + '.sqsh', 'bytes': 1,
                   'sha256': ('a' if name == 'base' else 'b') * 64}
            doc = {'schema': 1, 'module': name, 'version': '1',
                   'parent': None if name == 'base' else 'base',
                   'snapshot': '20260701T000000Z', 'suite': 'jammy',
                   'arch': 'amd64', 'generation': gen,
                   'requires': [], 'conflicts': [], 'provides': [],
                   'requested': [], 'removed': [], 'uid_range': None,
                   'accounts': {'users': {}, 'groups': {}, 'shadow': [],
                                'gshadow': [], 'file_uids': [0],
                                'file_gids': [0]},
                   'units': {}, 'artifact': art,
                   'packages': {'basepkg': {'version': '1', 'origin': 'added'}}
                   if name == 'base' else {}}
            side = json.dumps({'schema': 1, 'module': name,
                               'files': {}, 'diversions': []}).encode()
            subprocess.run(['zstd', '-q', '-f', '-o',
                            str(self.mod_dir / (name + '.files.json.zst'))],
                           input=side, check=True)
            doc['binding'] = {'schema': 1, 'source': 'artifact',
                              'artifact_sha256': art['sha256'],
                              'sidecar_sha256': hashlib.sha256(side).hexdigest(),
                              'fields': BIND_FIELDS,
                              'fields_sha256': bind_digest(doc)}
            self.write_doc(name, doc)

    def write_doc(self, name, doc):
        (self.mod_dir / (name + '.json')).write_text(json.dumps(doc))

    def change_delta(self, gid=None, omit=False):
        path = self.mod_dir / 'delta.json'
        doc = json.loads(path.read_text())
        if omit:
            del doc['accounts']['file_gids']
        else:
            doc['accounts']['file_gids'] = None if gid is None else [gid]
        doc['binding']['fields_sha256'] = bind_digest(doc)
        self.write_doc('delta', doc)

    def checker(self):
        return subprocess.run(['bash', str(REPO / 'scripts/05_check.sh'), 'delta'],
                              cwd=REPO, env={**os.environ, 'MODFS_ROOT':
                                             str(self.root)},
                              capture_output=True, text=True)

    def test_control_complete_clean_owners(self):
        result = self.checker()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('every file owner resolves', result.stdout)

    def test_control_present_bad_gid_rejects(self):
        self.change_delta(gid=2500)
        result = self.checker()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('IDENTITY BORROWED', result.stdout)

    def test_fixed_missing_gid_field_cannot_claim_checked(self):
        self.change_delta(omit=True)
        result = self.checker()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('numeric file ownership NOT CHECKED for: delta', result.stdout)
        self.assertIn('ACCEPT WITH WARNINGS', result.stdout)
        self.assertNotIn('every file owner resolves', result.stdout)

    def test_fixed_null_gid_field_cannot_claim_checked(self):
        self.change_delta(gid=None)
        result = self.checker()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('numeric file ownership NOT CHECKED for: delta', result.stdout)
        self.assertNotIn('every file owner resolves', result.stdout)

    def test_fixed_non_numeric_gid_field_cannot_claim_checked(self):
        self.change_delta(gid='not-a-gid')
        result = self.checker()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('numeric file ownership NOT CHECKED for: delta', result.stdout)
        self.assertNotIn('every file owner resolves', result.stdout)


if __name__ == '__main__':
    unittest.main(verbosity=2)
