#!/usr/bin/env python3
import sys
from pathlib import Path
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from update_report import compare


class TransferTests(unittest.TestCase):
    def test_ship_full_changed_artifact_even_when_same_size(self):
        def item(digest, size):
            return dict(sha256=digest, bytes=size, snapshot='pin', packages={})
        old = {'same': item('a', 10), 'changed': item('b', 20), 'removed': item('c', 30)}
        new = {'same': item('a', 10), 'changed': item('z', 20), 'added': item('d', 40)}
        rows = {r['module']: r for r in compare(old, new)}
        self.assertEqual(rows['changed']['size_change_bytes'], 0)
        self.assertEqual(rows['changed']['ship_bytes'], 20)
        self.assertEqual(rows['same']['ship_bytes'], 0)
        self.assertEqual(rows['removed']['ship_bytes'], 0)
        self.assertEqual(rows['added']['ship_bytes'], 40)


if __name__ == '__main__':
    unittest.main(verbosity=2)
