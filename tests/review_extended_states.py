#!/usr/bin/env python3
"""M1: manual selection wins over another sibling's dependency flag."""
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('subject', os.environ.get(
    'MODFS_RECONCILE_SCRIPT', REPO / 'scripts/reconcile.py'))
subject = importlib.util.module_from_spec(spec)
spec.loader.exec_module(subject)


class ExtendedStateTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix='auto-test-', dir='/srv/modfs/build'))
        self.base = self.layer('base', ['base', 'base-dep'], ['base-dep'])

    def layer(self, name, packages, auto, arch='amd64'):
        root = self.root / name
        (root / 'var/lib/dpkg').mkdir(parents=True)
        (root / 'var/lib/dpkg/status').write_text('\n\n'.join(
            'Package: %s\nStatus: install ok installed\nVersion: 1\nArchitecture: %s'
            % (p, arch) for p in packages) + '\n')
        if auto is not None:
            (root / 'var/lib/apt').mkdir(parents=True)
            (root / 'var/lib/apt/extended_states').write_text('\n\n'.join(
                'Package: %s\nArchitecture: amd64\nAuto-Installed: 1' % p
                for p in auto) + '\n')
        return name, str(root)

    def merged_auto(self, *layers):
        merged = self.root / 'merged'
        subject.merge_extended_states([self.base, *layers], str(merged))
        path = merged / 'var/lib/apt/extended_states'
        return {subject.field(s, 'Package') for s in subject.stanzas(path.read_text())
                if subject.field(s, 'Auto-Installed') == '1'}

    def test_manual_request_wins_both_orders(self):
        requested = self.layer('requested', ['base', 'base-dep', 'tool'], ['base-dep'])
        dependency = self.layer('dependency', ['base', 'base-dep', 'tool'], ['base-dep', 'tool'])
        self.assertEqual(self.merged_auto(requested, dependency), {'base-dep'})
        self.assertEqual(self.merged_auto(dependency, requested), {'base-dep'})

    def test_auto_only_stays_auto(self):
        dependency = self.layer('dep', ['base', 'base-dep', 'tool'], ['base-dep', 'tool'])
        self.assertEqual(self.merged_auto(dependency), {'base-dep', 'tool'})

    def test_missing_file_inherits_base_flags(self):
        delta = self.layer('delta', ['base', 'base-dep', 'tool'], None)
        self.assertEqual(self.merged_auto(delta), {'base-dep'})

    def test_arch_all_matches_native_apt_flag(self):
        dependency = self.layer('dep', ['base', 'base-dep', 'tool'],
                                ['base-dep', 'tool'], arch='all')
        self.assertEqual(self.merged_auto(dependency), {'base-dep', 'tool'})

    def test_empty_result_overwrites_stale_auto_state(self):
        self.assertEqual(self.merged_auto(), {'base-dep'})
        manual = self.layer('manual', ['base', 'base-dep'], [])
        self.assertEqual(self.merged_auto(manual), set())


if __name__ == '__main__':
    unittest.main(verbosity=2)
