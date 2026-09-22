#!/usr/bin/env python3
"""L3: documentation contracts, not new runtime or performance measurements."""
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[1]
DOC = (ROOT/'ARCHITECTURE.md').read_text()

# EVERY document that publishes a claim, not just the canonical one.
#
# Until 2026-09-21 all seven assertions below read ARCHITECTURE.md and no test
# read any other file. The consequence was mechanical and was measured: of the
# 24 inconsistencies found that day, every entry a test covered was CLOSED and
# every entry it did not was LIVE -- including corrections already applied to
# ARCHITECTURE that were still wrong in STATE_OF_PLAY, PLAN, EVOLUTION and
# MEETING, because nothing looked there.
#
# That is the same defect shape as V7 comparing names rather than files, V2
# comparing name sets rather than versions, and 00_verify checking that a tool
# exists rather than that it works: THE CHECK ONLY LOOKS WHERE IT WAS POINTED.
# Retiring a claim means retiring it everywhere, so a phrase banned from the
# canonical document is banned from all of them.
#
# JOURNAL.md is deliberately excluded: it is an append-only chronological record
# and MUST keep its retracted claims, which is the whole of its evidentiary
# value. CLAUDE.md is instructions, not claims.
CLAIM_DOCS = {}
for _name in ('ARCHITECTURE.md', 'EVOLUTION.md', 'MEETING.md', 'README.md',
              'thesis/PLAN.md', 'docs/STATE_OF_PLAY_2026-09-18.md'):
    _p = ROOT/_name
    if _p.exists():
        CLAIM_DOCS[_name] = _p.read_text()

def _asserted_anywhere(case, phrase, qualifier, why):
    """Flag a claim only where it is ASSERTED, not where it is quoted to be
    corrected. A document is allowed to say "X said 'phrase'; that is wrong",
    and a check that fires on that is a false positive -- which is as damaging
    as one that misses, and is the defect this project has found most often.
    So the test is line-scoped: the phrase is a finding only on a line that does
    not also carry its own correction."""
    hits = []
    for name, text in CLAIM_DOCS.items():
        for i, line in enumerate(text.split('\n'), 1):
            if phrase in line and qualifier not in line:
                hits.append('%s:%d' % (name, i))
    case.assertEqual(hits, [], "%s -- asserted at: %s" % (why, ', '.join(hits)))

class ClaimTests(unittest.TestCase):
    def test_cost_scope(self):
        self.assertNotIn('| 2 | Compose + verify |', DOC)
        # NOT a ban: 148 + 27.2 N is correct where it is labelled as the cost of
        # COMPOSING. What is wrong is publishing it as the cost of tier 2, which
        # also verifies. total_ms is exactly mount_ms + reconcile_ms -- checked
        # across all 152 rows at maximum difference 0 ms -- so any document
        # quoting the compose fit must also quote the verify fit beside it.
        # Match the FIGURES, not one spelling of them: ARCHITECTURE writes
        # "161.3 ms + 41.80 ms × N" and a literal-substring test called that a
        # violation. A brittle matcher that fires on correct content is the same
        # defect as a check that misses -- both report something that is not so.
        _verify = re.compile(r'161\.3\s*(?:ms)?\s*\+\s*41\.8')
        half = [n for n, t in CLAIM_DOCS.items()
                if '148 + 27.2' in t and not _verify.search(t)]
        self.assertEqual(half, [], 'quotes the compose fit without the verify fit '
                                   '(161.3 + 41.8 N): %s' % ', '.join(half))
        self.assertIn('| 2 | Compose only |', DOC)
    def test_cost_fit_is_the_current_generation(self):
        """A cost claim must quote the CURRENT sweep, not merely be labelled.

        test_cost_scope above checks the LABEL -- that a compose fit is not
        published as the cost of tier 2, which also verifies. It passed for
        three days while every document published `148 + 27.2 N`, the fit of a
        superseded CSV, because a correctly labelled stale number satisfies a
        label check. thesis/evidence/claims.md had already traced it and marked
        it STALE; nothing read that file.

        Same shape as V7 comparing names rather than files: the check only
        looks at what it was pointed at. So this one reads the coefficients out
        of the regenerated evidence and fails if a document publishes different
        ones without saying they are superseded."""
        import csv
        fit = ROOT/'thesis'/'evidence'/'tier2-fit.csv'
        if not fit.exists():
            self.skipTest('run scripts/16_build_evidence.sh to regenerate the fit')
        row = next(r for r in csv.DictReader(fit.open())
                   if r['quantity'] == 'total (compose only)')
        current = '%s + %s' % (row['intercept_ms'], row['slope_ms_per_module'])
        # A line may quote a superseded fit only while saying so.
        # A line is exempt when it RETRACTS the figure, or when it ATTRIBUTES it
        # to a named retained CSV -- "<file> yields <fit>" is provenance, and a
        # check that fires on provenance is a false positive, which this project
        # has found to be as damaging as a check that misses.
        SUPERSEDED = re.compile(r'pre-round|supersed|older|earlier|historical|'
                                r'must not be published|not the fit of the current|'
                                r'yields|\bcsv\b',
                                re.I)
        # Match the FIGURES, not one spelling of them. A literal '148 + 27.2'
        # misses '148.3 + 27.20N' and '148.286 + 27.200 N', which is how the
        # superseded fit is actually written elsewhere -- and writing a
        # literal-substring check is the precise brittleness that
        # test_cost_scope's own comment warns about, committed one function
        # away from that warning.
        OLD_FIT = re.compile(r'148(?:\.\d+)?\s*\+\s*27\.2\d*')
        stale = []
        for name, text in CLAIM_DOCS.items():
            for i, line in enumerate(text.split('\n'), 1):
                # Exempt a line that supersedes itself: either it says so in
                # words, or it carries the current slope right beside the old
                # one, which is a dated comparison rather than a claim.
                if (OLD_FIT.search(line)
                        and not SUPERSEDED.search(line)
                        and row['slope_ms_per_module'] not in line):
                    stale.append('%s:%d' % (name, i))
        self.assertEqual(stale, [],
                         'publishes the superseded compose fit 148 + 27.2 N with no '
                         'marker saying so; the current sweep gives %s -- at: %s'
                         % (current, ', '.join(stale)))
        # And whoever publishes a tier-2 cost must publish the current one.
        for name, text in CLAIM_DOCS.items():
            if OLD_FIT.search(text) or '30.55' in text:
                self.assertIn(current.split(' + ')[0], text,
                              '%s discusses the tier-2 cost but never states the '
                              'current intercept %s' % (name, current))

    def test_no_mixed_generation_ratios(self):
        self.assertNotIn('tier 2 costs almost exactly 2× tier 1', DOC)
        self.assertNotIn('**230–250×**', DOC)
    def test_account_order_scope(self):
        self.assertNotRegex(DOC, r'identical under order reversal')
        _asserted_anywhere(self, 'identical under order reversal', 'set-equal',
                           'order reversal is set-equal, not byte-equal')
        self.assertIn('set-equal under the tested order reversal', DOC)
        self.assertIn('not byte-equal', DOC)
    def test_no_unconditional_order_claim(self):
        self.assertNotIn('makes composition **order-independent**', DOC)
        _asserted_anywhere(self, 'makes composition **order-independent**', 'not',
                           'order independence is semantic, not byte-wise')
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
