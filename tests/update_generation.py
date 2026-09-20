#!/usr/bin/env python3
"""Generation attacks against the actual tier-1 consumer using copied metadata.

No original artefacts are modified. Scratch is retained under /srv/modfs/build.
"""
import copy
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
from generation import generation, extraction_generation
from manifest_binding import BIND_FIELDS, bind_digest


class GenerationTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix='update-generation-', dir='/srv/modfs/build'))
        (self.root / 'modules').mkdir()
        self.docs = {}
        for name in ('base', 'curl', 'jq'):
            self.docs[name] = json.loads(Path('/srv/modfs/modules/' + name + '.json').read_text())
            shutil.copy2('/srv/modfs/modules/' + name + '.files.json.zst',
                         self.root / 'modules' / (name + '.files.json.zst'))
        b = self.docs['base']
        g = generation(b['snapshot'], b['suite'], b['arch'], b['artifact']['sha256'])
        for doc in self.docs.values():
            doc['generation'] = copy.deepcopy(g)

    def check(self, code, reason=''):
        for name, doc in self.docs.items():
            doc['binding']['fields'] = list(BIND_FIELDS)
            doc['binding']['fields_sha256'] = bind_digest(doc)
            (self.root / 'modules' / (name + '.json')).write_text(json.dumps(doc))
        result = subprocess.run([str(REPO / 'scripts/05_check.sh'), 'curl', 'jq'],
                                env=dict(os.environ, MODFS_ROOT=str(self.root)),
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        self.assertIn(reason, result.stdout + result.stderr)

    def test_same_generation(self):
        self.check(0)

    def test_same_pin_different_base_no_package_skew(self):
        b = self.docs['base']
        b['artifact']['sha256'] = 'a' * 64
        b['binding']['artifact_sha256'] = 'a' * 64
        b['generation'] = generation(b['snapshot'], b['suite'], b['arch'], 'a' * 64)
        self.check(1, 'NOT COMPOSABLE')

    def test_same_versions_different_snapshot(self):
        d = self.docs['jq']
        d['snapshot'] = '20260901T000000Z'
        d['generation'] = generation(d['snapshot'], d['suite'], d['arch'], d['generation']['base_sha256'])
        self.check(1, 'NOT COMPOSABLE')

    def test_missing_generation_even_resealed(self):
        del self.docs['jq']['generation']
        self.check(1, 'BINDING MISMATCH')

    def test_forged_generation_id_even_resealed(self):
        self.docs['jq']['generation']['id'] = 'a' * 64
        self.check(1, 'BINDING MISMATCH')

    def test_refresh_cannot_relabel(self):
        d = self.docs['jq']
        with self.assertRaisesRegex(ValueError, 'generation changed'):
            extraction_generation(d, d, 'a' * 64, adopt=True)

    def test_legacy_requires_explicit_adoption(self):
        d = self.docs['jq']; digest = d['generation']['base_sha256']
        with self.assertRaisesRegex(ValueError, 'legacy'):
            extraction_generation(d, {}, digest)
        self.assertEqual(extraction_generation(d, {}, digest, adopt=True), d['generation'])

    def test_spec_change_preserves_generation(self):
        d = self.docs['jq']; d['requested'].append('moreutils')
        self.assertEqual(extraction_generation(d, d, d['generation']['base_sha256'], new_build=True),
                         d['generation'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
