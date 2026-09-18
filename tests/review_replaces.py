#!/usr/bin/env python3
"""L2: dpkg permits partial takeover; ModFS must explain its stricter policy."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from review_probes import REPO, command, composition

class ReplacesTests(unittest.TestCase):
    def test_partial_takeover_policy(self):
        root = Path(tempfile.mkdtemp(prefix='replaces-review-', dir='/srv/modfs/build'))
        mods = root/'modules'; mods.mkdir()
        for suffix in ('.json', '.files.json.zst'):
            import shutil
            shutil.copy2('/srv/modfs/modules/base'+suffix, mods/('base'+suffix))
        (mods/'base.sqsh').symlink_to('/srv/modfs/modules/base.sqsh')
        debs = []
        for name in ('a', 'b'):
            package = root/('package-'+name)
            (package/'DEBIAN').mkdir(parents=True)
            payload = package/'usr/share/review-replaces'; payload.mkdir(parents=True)
            (payload/'shared').write_text(name+'\n')
            (payload/('keep-'+name)).write_text(name+'\n')
            (package/'DEBIAN/control').write_text(
                'Package: review-'+name+'\nVersion: 1\nArchitecture: all\n'
                'Maintainer: Review <review@example.invalid>\nDescription: fixture\n'
                + ('Replaces: review-a\n' if name == 'b' else ''))
            deb = root/(name+'.deb'); debs.append(deb)
            command(['dpkg-deb','--build',package,deb])
            with composition('curl') as merged:
                (merged/'tmp/package.deb').write_bytes(deb.read_bytes())
                command(['chroot',merged,'dpkg','-i','/tmp/package.deb'])
                upper = merged.parent/'upper'
            command(['mksquashfs',upper,mods/('review-'+name+'.sqsh'),'-noappend',
                     '-comp','zstd','-no-progress','-processors','2'])
            p = subprocess.run(['scripts/06_extract_metadata.sh','review-'+name,'--version','1'],
                               cwd=REPO, env=dict(os.environ, MODFS_ROOT=str(root)), capture_output=True)
            self.assertEqual(p.returncode,0,p.stdout+p.stderr)
        with composition('curl') as merged:
            for deb in debs:
                (merged/'tmp/package.deb').write_bytes(deb.read_bytes())
                command(['chroot',merged,'dpkg','-i','/tmp/package.deb'])
            status = command(['chroot',merged,'dpkg-query','-W','-f',
                              '${Package} ${Status}\n','review-a','review-b']).stdout
            self.assertEqual(status.count('install ok installed'),2,status)
            self.assertEqual((merged/'usr/share/review-replaces/shared').read_text(),'b\n')
            self.assertEqual(command(['chroot',merged,'dpkg','--audit']).stdout,'')
        p = subprocess.run(['scripts/05_check.sh','review-a','review-b'],cwd=REPO,
                           env=dict(os.environ, MODFS_ROOT=str(root)),text=True,capture_output=True)
        self.assertEqual(p.returncode,1,p.stdout+p.stderr)
        self.assertIn('FILE COLLISION /usr/share/review-replaces/shared',p.stdout)
        self.assertIn('ownership transfer and installation order are not modelled',p.stdout)
        self.assertNotIn('dpkg requires Breaks or Conflicts', (REPO/'scripts/05_check.sh').read_text())

if __name__ == '__main__': unittest.main(verbosity=2)
