#!/usr/bin/env python3
"""Regression tests from the 2026-09-21 adversarial review of the evidence
generator, `scripts/16_build_evidence.sh`.

    python3 tests/round3_evidence.py       # unprivileged, no artefacts needed

Like tests/round2_attacks.py this EXECUTES THE REAL CODE. It does not import
anything out of the generator -- the generator is a bash wrapper around an
embedded python heredoc, so there is nothing to import. Instead each test
builds a synthetic `$MODFS_ROOT` (a `modules/`, `logs/` and `results/` tree of
its own) and RUNS THE SHIPPED SCRIPT against it, then reads the files it wrote.
That is the same discipline: the tests cannot drift from what ships, because
they run what ships.

Three kinds of case, as in round 2:

  FIXED      a defect found in round 3 and closed. The test fails if it returns.
  CONTROL    correct input that must NOT raise an alarm. A generator that cries
             stale on fresh evidence is as useless as one that publishes stale
             numbers silently.
  KNOWN OPEN a defect found in round 3 and deliberately NOT closed, with the
             reason recorded in JOURNAL.md. The expected value is today's
             BEHAVIOUR, not today's wish.
"""
import csv, hashlib, io, json, os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
SCRIPT = os.path.join(REPO, 'scripts', '16_build_evidence.sh')

FAILED = []

def check(label, name, got, want):
    ok = got == want
    print('  %-10s %-52s %s' % (label, name, 'ok' if ok else 'FAIL'))
    if not ok:
        print('             got:  %r' % (got,))
        print('             want: %r' % (want,))
        FAILED.append(name)

# ------------------------------------------------------------------ fixtures
def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for c in iter(lambda: f.read(1 << 20), b''):
            h.update(c)
    return h.hexdigest()

def mkmod(moddir, name, nbytes, recorded_sha=None):
    """Write a <name>.sqsh of nbytes and a manifest that records its digest."""
    p = os.path.join(moddir, name + '.sqsh')
    blob = (name.encode() * (nbytes // max(len(name), 1) + 1))[:nbytes]
    io.open(p, 'wb').write(blob)
    doc = dict(schema=1, module=name, version='1.0', parent='base',
               snapshot='20260701T000000Z', suite='jammy', arch='amd64',
               built='2026-09-18T13:10:56Z', requires=[], conflicts=[],
               provides=[], requested=[name], removed=[], uid_range=None,
               accounts=[], identity_audit={}, units=[],
               artifact=dict(file=name + '.sqsh', bytes=nbytes,
                             sha256=recorded_sha or sha256(p)),
               packages={name: '1.0'}, binding={})
    json.dump(doc, io.open(os.path.join(moddir, name + '.json'), 'w',
                           encoding='utf-8'))
    return p

def newroot(tmp, mods):
    """A synthetic $MODFS_ROOT holding just the modules named."""
    root = tempfile.mkdtemp(dir=tmp)
    for sub in ('modules', 'logs', 'results'):
        os.makedirs(os.path.join(root, sub))
    md = os.path.join(root, 'modules')
    for name, nbytes in mods:
        mkmod(md, name, nbytes)
    return root

def generate(root, out):
    """Run the shipped generator against `root`. Returns (rc, stdout)."""
    env = dict(os.environ, MODFS_ROOT=root)
    p = subprocess.run(['bash', SCRIPT, '--out', out], env=env,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return p.returncode, p.stdout.decode('utf-8', 'replace')

def readcsv(out, name):
    with io.open(os.path.join(out, name), encoding='utf-8') as fh:
        return list(csv.reader(fh))

# ============================================================== R3-1  FIXED
def t_sha_column_names_what_it_holds(tmp):
    """R3-1 FIXED -- `provenance-artefacts.csv` published a column headed
    `manifest_sha256` whose content was the ARTEFACT's digest, taken from the
    manifest's `artifact.sha256` field. Never once, on any of the 41 real rows,
    did it equal the sha256 of the manifest FILE. A reader checking the
    published evidence the obvious way (`sha256sum <module>.json`) got 41
    mismatches and would conclude the evidence had been tampered with.

    The underlying value was right and every recorded digest verified against
    the bytes; only the label was wrong. This is the round-2 `alt_groups` shape
    exactly: a column header and its content drifted apart.
    """
    root = newroot(tmp, [('base', 1 << 20), ('gcc', 4 << 20)])
    out = tempfile.mkdtemp(dir=tmp)
    rc, log = generate(root, out)
    check('FIXED', 'R3-1 generator exits 0', rc, 0)
    rows = readcsv(out, 'provenance-artefacts.csv')
    head = rows[0]
    # The header must not claim to be the manifest's digest.
    check('FIXED', 'R3-1 column not headed manifest_sha256',
          'manifest_sha256' in head, False)
    check('FIXED', 'R3-1 column names the artefact',
          'artefact_sha256_recorded' in head, True)
    # And the value must be the artefact digest, not the manifest file digest.
    md = os.path.join(root, 'modules')
    if 'artefact_sha256_recorded' not in head:
        return                      # already reported above; nothing to index
    col = head.index('artefact_sha256_recorded')
    by = {r[0]: r[col] for r in rows[1:]}
    check('FIXED', 'R3-1 value is the artefact digest',
          by['gcc'], sha256(os.path.join(md, 'gcc.sqsh')))
    check('FIXED', 'R3-1 value is NOT the manifest-file digest',
          by['gcc'] == sha256(os.path.join(md, 'gcc.json')), False)

# =================================================================== driver
def main():
    tmp = tempfile.mkdtemp(prefix='round3-evidence-')
    try:
        print('R3-1  the digest column in provenance-artefacts.csv')
        t_sha_column_names_what_it_holds(tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print()
    if FAILED:
        print('FAILED: %d' % len(FAILED))
        for f in FAILED:
            print('  - %s' % f)
        return 1
    print('all round-3 evidence-generator checks pass')
    return 0

if __name__ == '__main__':
    sys.exit(main())
