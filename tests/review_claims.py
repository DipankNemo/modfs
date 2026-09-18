#!/usr/bin/env python3
"""L3: documentation contracts, not new runtime or performance measurements."""
from pathlib import Path
import re
import unittest
DOC = (Path(__file__).resolve().parents[1]/'ARCHITECTURE.md').read_text()

class ClaimTests(unittest.TestCase):
    def test_cost_scope(self):
        self.assertNotIn('| 2 | Compose + verify |', DOC)
        self.assertIn('| 2 | Compose only |', DOC)
    def test_no_mixed_generation_ratios(self):
        self.assertNotIn('tier 2 costs almost exactly 2× tier 1', DOC)
        self.assertNotIn('**230–250×**', DOC)
    def test_account_order_scope(self):
        self.assertNotRegex(DOC, r'identical under order reversal')
        self.assertIn('set-equal under the tested order reversal', DOC)
        self.assertIn('not byte-equal', DOC)
    def test_no_unconditional_order_claim(self):
        self.assertNotIn('makes composition **order-independent**', DOC)
        self.assertIn('No general order-independence guarantee', DOC)
    def test_cost_split_consistent(self):
        text = DOC.split('**The cost model, re-measured.**',1)[1].split('## 8.',1)[0]
        vals = {}
        for label, intercept, slope in re.findall(
                r'(total|mount|reconcile)\s*=\s*([0-9.]+) ms \+\s*([0-9.]+) ms × N', text):
            vals[label] = (float(intercept), float(slope))
        self.assertEqual(set(vals), {'total','mount','reconcile'})
        for col in (0,1):
            self.assertAlmostEqual(vals['total'][col], vals['mount'][col]+vals['reconcile'][col], delta=.11)
    def test_fatbase_evidence(self):
        self.assertIn('fatbase-analysis-2026-09-17T163305Z.txt', DOC)
        self.assertNotIn('Testing that is the obvious next experiment and has not been', DOC)
    def test_hashes_identify_historical_generation(self):
        self.assertIn('Historical reproducibility sample', DOC)
        self.assertIn('not hashes of the current artefacts', DOC)

if __name__ == '__main__': unittest.main(verbosity=2)
