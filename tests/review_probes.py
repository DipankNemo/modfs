#!/usr/bin/env python3
"""Real SquashFS/OverlayFS probe regressions; root required, scratch retained."""
from contextlib import contextmanager
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import yaml
REPO = Path(__file__).resolve().parents[1]

def command(args):
    return subprocess.run([str(a) for a in args], text=True, capture_output=True, check=True)

@contextmanager
def composition(module):
    root = Path(tempfile.mkdtemp(prefix='probe-review-', dir='/srv/modfs/build'))
    mounts = []
    def mount(args, target):
        target.mkdir(parents=True, exist_ok=True)
        command(['mount', *args, target])
        mounts.append(target)
    try:
        layers = []
        for name in ('base', module):
            target = root / ('ro_' + name)
            mount(['-o', 'loop,ro', '/srv/modfs/modules/'+name+'.sqsh'], target)
            layers.append(name+'='+str(target))
        for name in ('upper', 'work', 'merged'):
            (root/name).mkdir()
        merged = root/'merged'
        opts = 'lowerdir=%s:%s,upperdir=%s,workdir=%s' % (
            root/('ro_'+module), root/'ro_base', root/'upper', root/'work')
        mount(['-t', 'overlay', 'overlay', '-o', opts], merged)
        for rel in ('tmp', 'var/tmp', 'run/lock'):
            (merged/rel).mkdir(parents=True, exist_ok=True)
            (merged/rel).chmod(0o1777)
        mount(['--bind', '/dev'], merged/'dev')
        command(['python3', REPO/'scripts/reconcile.py', '--merged', merged,
                 '--groups-out', root/'groups', *layers])
        for group in (root/'groups').read_text().split():
            command(['chroot', merged, 'update-alternatives', '--auto', group])
        command(['chroot', merged, 'ldconfig'])
        yield merged
    finally:
        for target in reversed(mounts):
            command(['umount', target])

def probe(merged, name):
    entries = yaml.safe_load((REPO/'specs/modules.yaml').read_text())['modules']
    shell = next(m['probe'] for m in entries if m['name'] == name)
    return subprocess.run(['chroot', str(merged), 'timeout', '45', 'sh', '-c', shell],
                          input='', text=True, capture_output=True)

class PostgresTests(unittest.TestCase):
    def test_server_loads(self):
        with composition('postgres') as merged:
            p = probe(merged, 'postgres')
            self.assertEqual(p.returncode, 0, p.stdout+p.stderr)
    def test_broken_server_rejected(self):
        with composition('postgres') as merged:
            server = merged/'usr/lib/postgresql/14/bin/postgres'
            server.write_text('#!/bin/sh\nexit 99\n')
            server.chmod(0o755)
            p = probe(merged, 'postgres')
            self.assertNotEqual(p.returncode, 0, 'broken server passed its catalogue probe')

class ZstdTests(unittest.TestCase):
    def test_repeatable(self):
        with composition('zstd') as merged:
            for attempt in range(2):
                p = probe(merged, 'zstd')
                self.assertEqual(p.returncode, 0, 'attempt %d: %s' % (attempt, p.stderr))

    def test_existing_temporary_files_untouched(self):
        with composition('zstd') as merged:
            paths = [merged/'tmp'/n for n in ('z1', 'z1.zst', 'z2')]
            for path in paths:
                path.write_text('existing user data')
            p = probe(merged, 'zstd')
            self.assertEqual(p.returncode, 0, p.stderr)
            for path in paths:
                self.assertEqual(path.read_text(), 'existing user data')

if __name__ == '__main__': unittest.main(verbosity=2)
