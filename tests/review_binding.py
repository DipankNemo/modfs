#!/usr/bin/env python3
"""H1: exercise both consumers with copied real manifests, never originals.

Run with permission to create scratch in /srv/modfs/build. Scratch is retained.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class BindingTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix='binding-test-', dir='/srv/modfs/build'))
        (self.root / 'modules').mkdir()
        for name in ('base', 'curl'):
            for suffix in ('.json', '.files.json.zst'):
                shutil.copy2('/srv/modfs/modules/' + name + suffix,
                             self.root / 'modules' / (name + suffix))
            (self.root / 'modules' / (name + '.sqsh')).symlink_to(
                '/srv/modfs/modules/' + name + '.sqsh')
        self.path = self.root / 'modules/curl.json'
        self.doc = json.loads(self.path.read_text())

    def consumers(self, accepted):
        self.path.write_text(json.dumps(self.doc))
        env = dict(os.environ, MODFS_ROOT=str(self.root))
        for args in (['scripts/05_check.sh', 'curl'],
                     ['bash', '-c', 'source config.sh; source scripts/lib.sh; '
                      'verify_bundle base curl']):
            with self.subTest(consumer=args[0]):
                p = subprocess.run(args, cwd=REPO, env=env, text=True, capture_output=True)
                self.assertEqual(p.returncode == 0, accepted, p.stdout + p.stderr)
                self.assertNotEqual(p.returncode, 2, p.stdout + p.stderr)

    def test_original(self):
        self.consumers(True)

    def test_missing_sidecar_digest(self):
        del self.doc['binding']['sidecar_sha256']
        self.consumers(False)

    def test_empty_sidecar_digest(self):
        self.doc['binding']['sidecar_sha256'] = ''
        self.consumers(False)

    def test_malformed_sidecar_digest(self):
        self.doc['binding']['sidecar_sha256'] = 'not-a-digest'
        self.consumers(False)

    def test_tampered_sidecar(self):
        path = self.root / 'modules/curl.files.json.zst'
        data = json.loads(subprocess.check_output(['zstd', '-dcq', str(path)]))
        data['files'] = {}
        subprocess.run(['zstd', '-q', '-f', '-o', str(path)],
                       input=json.dumps(data).encode(), check=True)
        self.consumers(False)

    def test_missing_sidecar(self):
        (self.root / 'modules/curl.files.json.zst').unlink()
        self.consumers(False)

    def test_resealed_reduced_coverage(self):
        b = self.doc['binding']
        b['fields'].remove('accounts')
        payload = {k: self.doc.get(k) for k in b['fields']}
        b['fields_sha256'] = hashlib.sha256(json.dumps(
            payload, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
        self.consumers(False)

    def test_missing_binding(self):
        del self.doc['binding']
        self.consumers(False)


if __name__ == '__main__':
    unittest.main(verbosity=2)
