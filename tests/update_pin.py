#!/usr/bin/env python3
"""Exercise stage 08's real dispatch, including refresh and the negative control."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]

# Stage 08 refuses to run without root (delta builds mount and chroot), so an
# unprivileged run reported this as a FAILURE rather than as a skip -- the same
# defect four other root-only test files had until 2026-09-21.
ROOT_ONLY = unittest.skipUnless(os.geteuid() == 0,
                               'needs root: stage 08 mounts and chroots')


@ROOT_ONLY
class PinTests(unittest.TestCase):
    def test_dispatch(self):
        # Retained scratch, no cleanup outside the permitted build tree.
        root = Path(tempfile.mkdtemp(prefix='update-pin-', dir='/srv/modfs/build'))
        for d in ('scripts', 'specs', 'modules/base.dir', 'logs'):
            (root / d).mkdir(parents=True)
        shutil.copy2(REPO / 'config.sh', root / 'config.sh')
        for name in ('lib.sh', '08_build_catalogue.sh'):
            shutil.copy2(REPO / 'scripts' / name, root / 'scripts' / name)
        (root / 'specs/modules.yaml').write_text('''modules:
  - {name: ordinary, packages: [jq]}
  - {name: control, packages: [curl], snapshot: 20250401T000000Z}
''')
        for name in ('base', 'ordinary', 'control'):
            (root / 'modules' / (name + '.json')).write_text('{}')
            (root / 'modules' / (name + '.sqsh')).write_bytes(b'fixture')
        for name in ('02_build_delta.sh', '06_extract_metadata.sh'):
            p = root / 'scripts' / name
            p.write_text('#!/usr/bin/env bash\nprintf "%s %s\\n" "$MODFS_SNAPSHOT_ID" "$*" >> "$MODFS_ROOT/dispatch"\n')
            p.chmod(0o755)
        env = dict(os.environ, MODFS_ROOT=str(root), MODFS_SNAPSHOT_ID='20260901T000000Z')
        for args in (['--force'], ['--refresh-metadata']):
            p = subprocess.run([str(root / 'scripts/08_build_catalogue.sh')] + args,
                               env=env, capture_output=True, text=True)
            self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        lines = (root / 'dispatch').read_text().splitlines()
        self.assertEqual([x.split()[0] for x in lines],
                         ['20260901T000000Z', '20250401T000000Z',
                          '20260901T000000Z', '20260901T000000Z', '20250401T000000Z'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
