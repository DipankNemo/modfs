#!/usr/bin/env python3
"""M3: success must cover every requested bundle, including empty catalogues."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
REPO = Path(__file__).resolve().parents[1]

class CoverageTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix='binding-coverage-', dir='/srv/modfs/build'))
        (self.root / 'modules').mkdir()
    def check(self, names, code, valid=False, malformed=False):
        if valid:
            for name in ('base', 'curl'):
                for suffix in ('.json', '.files.json.zst'):
                    shutil.copy2('/srv/modfs/modules/'+name+suffix, self.root/'modules'/(name+suffix))
                (self.root/'modules'/(name+'.sqsh')).symlink_to('/srv/modfs/modules/'+name+'.sqsh')
        env = dict(os.environ, MODFS_ROOT=str(self.root))
        if malformed:
            spec = self.root/'specs'; spec.mkdir()
            (spec/'modules.yaml').write_text('modules: [')
            env['MODFS_SPEC_DIR'] = str(spec)
        p = subprocess.run(['scripts/12_verify_binding.sh']+names, cwd=REPO,
                           env=env, text=True, capture_output=True)
        self.assertEqual(p.returncode, code, p.stdout+p.stderr)
        if code == 0:
            self.assertIn('1 matched', p.stdout)
            self.assertIn('requested subset', p.stdout)
    def test_absent(self): self.check(['curl'], 1)
    def test_unknown(self): self.check(['curll'], 2)
    def test_empty_catalogue(self): self.check([], 1)
    def test_malformed_catalogue(self): self.check([], 2, malformed=True)
    def test_mixed_unknown(self): self.check(['curl','curll'], 2, valid=True)
    def test_partial_present(self): self.check(['curl','jq'], 1, valid=True)
    def test_valid_subset(self): self.check(['curl'], 0, valid=True)
if __name__ == '__main__': unittest.main(verbosity=2)
