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
import csv, hashlib, io, json, os, re, shutil, subprocess, sys, tempfile

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


# ============================================================== R3-2  FIXED
def _mono_case(tmp, mono_offset):
    """A fixture with one real monolithic baseline, built `mono_offset`
    seconds relative to the delta it is compared against."""
    root = newroot(tmp, [('base', 1 << 20), ('curl', 1 << 18)])
    md = os.path.join(root, 'modules')
    mono = os.path.join(md, 'curl-monolithic.sqsh')
    io.open(mono, 'wb').write(b'M' * ((1 << 20) + (1 << 18)))
    delta_mt = os.path.getmtime(os.path.join(md, 'curl.sqsh'))
    os.utime(mono, (delta_mt + mono_offset, delta_mt + mono_offset))
    out = tempfile.mkdtemp(dir=tmp)
    rc, log = generate(root, out)
    rows = readcsv(out, 'storage-model-check.csv')
    head, body = rows[0], rows[1:]
    md_text = io.open(os.path.join(out, 'storage.md'), encoding='utf-8').read()
    return rc, log, head, body, md_text

def t_stale_monolithic_is_flagged(tmp):
    """R3-2 FIXED -- S2 published a `model error` for every `-monolithic.sqsh`
    on disk with NO staleness check, while the header promises that a source
    older than what it describes is replaced by a STALE block.

    A monolithic baseline is only a like-for-like comparison if it is newer
    than both the base and the delta it is measured against. On the real
    artefacts ALL SIX predate their delta -- the monolithics were built
    2026-09-16 15:10-15:39Z and every delta was rebuilt after that, two of them
    (curl, jq) two days later -- yet S2 stated "the SIX are rebuilt
    like-for-like and they calibrate the rest".

    This is STATE_OF_PLAY 5c's "monolithic baselines two weeks stale"
    recurring in the REPORTING layer. The staleness machinery existed and was
    pointed only at the tier-1 and tier-2 CSVs; a `-monolithic.sqsh` carries no
    manifest, so the artefact inventory never saw it either.
    """
    rc, log, head, body, md_text = _mono_case(tmp, -3600)   # baseline 1h OLDER
    check('FIXED', 'R3-2 generator exits 0', rc, 0)
    check('FIXED', 'R3-2 CSV carries a freshness column',
          'baseline_freshness' in head, True)
    if 'baseline_freshness' not in head:
        return
    col = head.index('baseline_freshness')
    check('FIXED', 'R3-2 stale baseline marked STALE',
          body[0][col].startswith('STALE'), True)
    check('FIXED', 'R3-2 stale baseline says what it predates',
          'delta' in body[0][col], True)
    check('FIXED', 'R3-2 operator note raised', 'STALE MONOLITHIC' in log, True)
    check('FIXED', 'R3-2 like-for-like claim withdrawn',
          'UNCALIBRATED' in md_text, True)
    check('FIXED', 'R3-2 no unqualified like-for-like sentence',
          'the SIX are rebuilt like-for-like' in md_text, False)

def t_fresh_monolithic_is_not_flagged(tmp):
    """R3-2 CONTROL -- a baseline built AFTER its delta is a genuine
    like-for-like comparison and must not be flagged. A generator that cries
    stale over fresh evidence would be as useless as one that published stale
    numbers silently, and would push someone into a rebuild costing hours.
    """
    rc, log, head, body, md_text = _mono_case(tmp, +3600)   # baseline 1h NEWER
    check('CONTROL', 'R3-2 generator exits 0', rc, 0)
    if 'baseline_freshness' not in head:
        return                      # already reported by the FIXED case above
    col = head.index('baseline_freshness')
    check('CONTROL', 'R3-2 fresh baseline marked ok', body[0][col], 'ok')
    check('CONTROL', 'R3-2 no stale note raised',
          'STALE MONOLITHIC' in log, False)
    check('CONTROL', 'R3-2 model reported as calibrated',
          'UNCALIBRATED' in md_text, False)
    check('CONTROL', 'R3-2 calibration range still published',
          '% HIGH' in md_text, True)


# ============================================================== R3-3  FIXED
T1_HEAD = ['combination', 'n', 'modules', 'verdict', 'exit', 'errors',
           'warnings', 'benign_overlap', 'version_skew', 'declared_conflict',
           'file_collision', 'file_collision_suppressed', 'identity_collision',
           'module_relation', 'base_drift', 'not_composable']

def write_t1(path, mods, maxn):
    """A tier-1 sweep over `mods` covering set sizes 2..maxn."""
    import itertools
    with io.open(path, 'w', newline='', encoding='utf-8') as fh:
        w = csv.writer(fh)
        w.writerow(T1_HEAD)
        for n in range(2, maxn + 1):
            for c in itertools.combinations(mods, n):
                d = dict.fromkeys(T1_HEAD, '0')
                d['combination'] = '-'.join(c); d['n'] = str(n)
                d['modules'] = ' '.join(c)
                rej = 'a' in c and 'b' in c
                d['verdict'] = 'REJECT' if rej else 'ACCEPT'
                d['exit'] = '1' if rej else '0'
                d['version_skew'] = '1' if rej else '0'
                w.writerow([d[k] for k in T1_HEAD])

def _t1_case(tmp, full_maxn, newer_maxn):
    """Two schema-matching sweeps: an OLDER one to `full_maxn`, and a NEWER one
    to `newer_maxn`. The generator picks the newest."""
    mods = ['a', 'b', 'c', 'd']
    root = newroot(tmp, [('base', 1 << 20)] + [(m, 1 << 18) for m in mods])
    logs = os.path.join(root, 'logs')
    old = os.path.join(logs, 'combinations-full.csv')
    new = os.path.join(logs, 'combinations.csv')
    write_t1(old, mods, full_maxn)
    write_t1(new, mods, newer_maxn)
    os.utime(old, (1600000000, 1600000000))          # decisively older
    out = tempfile.mkdtemp(dir=tmp)
    rc, log = generate(root, out)
    md_text = io.open(os.path.join(out, 'tier1.md'), encoding='utf-8').read()
    return rc, log, readcsv(out, 'tier1-totals.csv'), md_text

def t_partial_resweep_is_flagged(tmp):
    """R3-3 FIXED -- the tier-1 source is the NEWEST file carrying the current
    schema, and the only coverage guard compares MODULE NAMES. A later
    `09_run_combinations.sh --max-n 2` re-run covers every module and every
    column and is missing every triple. It wins on mtime, the caption reads
    clean because the module set is complete, and every triple leaves the
    evidence in silence -- taking T1.4, the arithmetic cross-check that is the
    integrity argument for higher N, with them.

    This was not hypothetical. `/srv/modfs/logs` holds BOTH files right now:
    `combinations-gpu-full.csv` (10,660 rows, N=2 and 3, 40 modules,
    09-19 01:10:29) and `combinations.csv` (780 rows, N=2 ONLY, 40 modules,
    09-19 01:02:45). The complete one wins by EIGHT MINUTES of mtime, and
    because both cover all 40 modules no name-based check can tell them apart.
    A `touch`, a restore from backup, or one fast `--max-n 2` re-run would have
    deleted "9880 triples, ACCEPT 7807 / REJECT 2073" from the thesis with no
    number visibly changing.

    This is the V7/V2 shape: a coverage check comparing NAME SETS cannot see
    that half the measurement is gone. The fix compares what was MEASURED.
    """
    rc, log, totals, md_text = _t1_case(tmp, full_maxn=3, newer_maxn=2)
    check('FIXED', 'R3-3 generator exits 0', rc, 0)
    check('FIXED', 'R3-3 only pairs were published',
          [r[0] for r in totals[1:]], ['2'])
    check('FIXED', 'R3-3 operator note raised',
          'TIER-1 SET-SIZE COVERAGE' in log, True)
    check('FIXED', 'R3-3 warning block in the table',
          'SET-SIZE COVERAGE WARNING' in md_text, True)
    check('FIXED', 'R3-3 warning names the richer sweep',
          'combinations-full.csv' in md_text, True)
    check('FIXED', 'R3-3 warning names the missing set size',
          'also measures N=3' in md_text, True)

def t_complete_newest_sweep_is_not_flagged(tmp):
    """R3-3 CONTROL -- when the newest sweep IS the most complete one, which is
    the situation on the real artefacts today, nothing must be reported. This
    is the case the real `/srv/modfs/logs` is in, and a false alarm here would
    send someone into a re-run of 10,660 combinations for nothing.
    """
    rc, log, totals, md_text = _t1_case(tmp, full_maxn=2, newer_maxn=3)
    check('CONTROL', 'R3-3 generator exits 0', rc, 0)
    check('CONTROL', 'R3-3 pairs and triples published',
          [r[0] for r in totals[1:]], ['2', '3'])
    check('CONTROL', 'R3-3 no operator note',
          'TIER-1 SET-SIZE COVERAGE' in log, False)
    check('CONTROL', 'R3-3 no warning block',
          'SET-SIZE COVERAGE WARNING' in md_text, False)


# ========================================================= R3-4  --check
def t_check_writes_nothing(tmp):
    """R3-4 FIXED -- `--check` is documented as "write nothing, report status",
    and the generator buffers every file and gates the write on CHECK, so no
    file content was ever at risk. But the bash preamble ran `mkdir -p "$OUT"`
    before that gate, unconditionally, so `--check --out DIR` created DIR (and
    any missing parents) and left them behind. A directory is something.

    Minor on its own. It matters because `--check` is the one entry point whose
    whole contract is that it is safe to point at anything, including a path
    the operator only wants to ask about.
    """
    root = newroot(tmp, [('base', 1 << 20), ('gcc', 1 << 18)])
    want = os.path.join(tempfile.mkdtemp(dir=tmp), 'a', 'b')
    env = dict(os.environ, MODFS_ROOT=root)
    p = subprocess.run(['bash', SCRIPT, '--check', '--out', want], env=env,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    check('FIXED', 'R3-4 --check exits 0', p.returncode, 0)
    check('FIXED', 'R3-4 --check created no directory',
          os.path.exists(os.path.dirname(want)), False)
    check('FIXED', 'R3-4 --check still reports',
          b'would write' in p.stdout, True)
    # CONTROL: the writing path must still write.
    out = tempfile.mkdtemp(dir=tmp)
    rc, log = generate(root, os.path.join(out, 'fresh'))
    check('CONTROL', 'R3-4 --out still creates and writes',
          os.path.exists(os.path.join(out, 'fresh', 'storage.md')), True)

# ================================================ R3-5  row/header width
def _extract(fn_name):
    """Pull a function's source straight out of the shipped script, the way
    round2_attacks.py pulls V7's block out of verify_compose.py."""
    src = io.open(SCRIPT, encoding='utf-8').read()
    a = src.index('def %s(' % fn_name)
    b = src.index('\ndef ', a + 1)
    return src[a:b]

def _ns():
    ns = {'csv': csv, 'io': io, 'FILES': {}, 're': __import__('re')}
    exec(_extract('table'), ns)
    exec(_extract('write_csv'), ns)
    return ns

def t_short_row_is_refused(tmp):
    """R3-5 FIXED (hardening) -- neither `table()` nor `write_csv()` compared a
    row's width against its header. Both were hand-fed lists built at a dozen
    call sites.

    STATE_OF_PLAY 5c records what that costs: "Adding two columns without
    updating six hand-counted printfs put every failure label in the wrong
    column and left `result` empty -- so correct summary logic that separated
    refusals from failures was silently defeated by a data bug one layer down."
    A short CSV row does not look wrong to a reader. It looks like a different
    number, because every field after the gap has shifted left into a column
    that means something else.

    Every one of the 18 CSVs the generator emits today is correctly aligned --
    this was checked, column by column, and is a clean result. The defect is
    the absence of the guard, not a present misalignment; adding a column to
    storage-model-check.csv during THIS review was one more chance to make it.
    """
    ns = _ns()
    head = ['module', 'measured_mb', 'modelled_mb', 'result']
    for label, rows, why in (
            ('short', [['curl', '43.0', '43.4']],        'one field missing'),
            ('long',  [['curl', '43.0', '43.4', 'x', 'y']], 'one field extra')):
        for fname in ('write_csv', 'table'):
            try:
                if fname == 'write_csv':
                    ns['write_csv']('t.csv', head, rows)
                else:
                    ns['table'](rows, head)
                got = 'accepted silently'
            except SystemExit:
                got = 'refused'
            check('FIXED', 'R3-5 %s() refuses a %s row (%s)'
                  % (fname, label, why), got, 'refused')

def t_correct_row_is_accepted(tmp):
    """R3-5 CONTROL -- a correctly shaped row, and a correctly sized alignment
    spec, must pass untouched. A guard that rejected valid input would stop the
    thesis being generated at all.
    """
    ns = _ns()
    head = ['module', 'measured_mb', 'modelled_mb', 'result']
    rows = [['curl', '43.0', '43.4', 'ok'], ['jq', '41.9', '42.3', 'ok']]
    try:
        ns['write_csv']('t.csv', head, rows)
        out = ns['FILES']['t.csv']
        got = 'accepted'
    except SystemExit:
        out = ''; got = 'refused'
    check('CONTROL', 'R3-5 write_csv() accepts an aligned row', got, 'accepted')
    check('CONTROL', 'R3-5 write_csv() content is right',
          out, 'module,measured_mb,modelled_mb,result\n'
               'curl,43.0,43.4,ok\njq,41.9,42.3,ok\n')
    try:
        md = ns['table'](rows, head, ['---', '---:', '---:', '---'])
        got = 'accepted'
    except SystemExit:
        md = ''; got = 'refused'
    check('CONTROL', 'R3-5 table() accepts an aligned row', got, 'accepted')
    check('CONTROL', 'R3-5 table() emits one row per input',
          len([l for l in md.strip().split('\n')]), 4)   # head + rule + 2 rows
    # and a mis-sized alignment spec is refused
    try:
        ns['table'](rows, head, ['---', '---:'])
        got = 'accepted silently'
    except SystemExit:
        got = 'refused'
    check('FIXED', 'R3-5 table() refuses a short alignment spec', got, 'refused')


# ========================================================= R3-6  empty cohort
def _cohort_case(tmp, mods):
    root = newroot(tmp, [('base', 1 << 20)] + mods)
    out = tempfile.mkdtemp(dir=tmp)
    rc, log = generate(root, out)
    rows = {r[0]: r for r in readcsv(out, 'storage-cohorts.csv')[1:]}
    return rc, log, rows

def t_empty_cohort_has_no_ratio(tmp):
    """R3-6 FIXED -- `cohort()` guarded its two divisions (`if stored`, `if N`)
    and then formatted the fallback ZERO as a measurement. A cohort with no
    members therefore published:

        large realistic,0,1.0,0.0,0.00x,0.0

    `0.00x` is not a missing value, it is a claim: that the monolithic baseline
    for that cohort costs nothing. Guarding against a ZeroDivisionError is not
    the same as guarding against a meaningless number, and the generator's own
    header promises it "never prints a number it cannot name a file for".

    Reachable whenever no declared-large module is built -- an early catalogue,
    a small experimental one, or a branch where the declared name has moved
    (the noble catalogue's driver is nvidia-driver-580, not -535). The
    "declared large but not built" note fired in that case, but the TABLE still
    printed a ratio, and the table is what a reader reads.
    """
    rc, log, rows = _cohort_case(tmp, [('tiny', 1000)])   # nothing in LARGE
    check('FIXED', 'R3-6 generator exits 0', rc, 0)
    lr = rows['large realistic']
    check('FIXED', 'R3-6 empty cohort has N=0', lr[1], '0')
    check('FIXED', 'R3-6 empty cohort ratio is not 0.00x',
          lr[4] == '0.00\u00d7', False)
    check('FIXED', 'R3-6 empty cohort ratio is dashed', lr[4], '\u2014')
    check('FIXED', 'R3-6 empty cohort monolithic is dashed', lr[3], '\u2014')
    check('FIXED', 'R3-6 empty cohort mean delta is dashed', lr[5], '\u2014')
    check('FIXED', 'R3-6 operator note raised', 'EMPTY COHORT' in log, True)
    # the non-empty cohorts in the same table are unaffected
    check('FIXED', 'R3-6 populated cohort still reports a ratio',
          rows['whole catalogue'][4].endswith('\u00d7'), True)

def t_populated_cohort_still_reports(tmp):
    """R3-6 CONTROL -- a cohort that DOES have members must report its ratio
    exactly as before. `gcc` is in the declared LARGE set, so this fixture
    populates both cohorts; neither may be dashed and no note may be raised.
    """
    rc, log, rows = _cohort_case(tmp, [('tiny', 1000), ('gcc', 1 << 22)])
    check('CONTROL', 'R3-6 generator exits 0', rc, 0)
    for lab in ('small adversarial', 'large realistic', 'whole catalogue'):
        check('CONTROL', 'R3-6 %s reports a ratio' % lab,
              rows[lab][4].endswith('\u00d7') and rows[lab][4] != '0.00\u00d7',
              True)
    check('CONTROL', 'R3-6 no empty-cohort note', 'EMPTY COHORT' in log, False)


# ================================================ R3-7  cross-script cohort
def _repo_copy(tmp):
    """A scratch copy of the repo's scripts/, specs/ and config.sh, so the
    sibling script can be perturbed without touching the real tree."""
    d = tempfile.mkdtemp(dir=tmp)
    for sub in ('scripts', 'specs'):
        shutil.copytree(os.path.join(REPO, sub), os.path.join(d, sub))
    shutil.copy(os.path.join(REPO, 'config.sh'), os.path.join(d, 'config.sh'))
    return d

def _run_copy(repo, root, out):
    env = dict(os.environ, MODFS_ROOT=root)
    p = subprocess.run(['bash', os.path.join(repo, 'scripts',
                                             '16_build_evidence.sh'),
                        '--out', out], env=env,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return p.returncode, p.stdout.decode('utf-8', 'replace')

def t_cohort_divergence_is_detected(tmp):
    """R3-7 FIXED -- the LARGE cohort is declared TWICE, in
    16_build_evidence.sh and in 13_storage_ratios.sh, and the two must agree:
    they split the same catalogue and publish ratios compared against each
    other. Three comments in 16_build_evidence.sh asserted a "consistency
    check" kept them in step -- "kept in step with it by the consistency check
    below, not by hope", "the two LARGE sets are kept in step by the
    consistency check".

    There was no such check. All four mentions of 13_storage_ratios.sh in the
    file were comments and message text; the script never opened it. The two
    sets were equal only by hand.

    This is the shape STATE_OF_PLAY records as found three times before -- a
    script documenting itself as doing something it does not do -- in its worse
    direction: 10_compose_sweep.sh under-claimed (ran V7 and V8 while
    advertising V1-V6), and this over-claimed. And the stakes are the ones the
    21 September cohort bug already demonstrated: one module moving between
    cohorts takes the headline ratio from 5.59x to 2.59x.
    """
    repo = _repo_copy(tmp)
    sib = os.path.join(repo, 'scripts', '13_storage_ratios.sh')
    src = io.open(sib, encoding='utf-8').read()
    io.open(sib, 'w', encoding='utf-8').write(
        src.replace("'nvidia-driver-535', 'cuda-runtime'}",
                    "'nvidia-driver-535', 'cuda-runtime', 'emacs'}", 1))
    root = newroot(tmp, [('base', 1 << 20), ('gcc', 1 << 22), ('emacs', 1 << 21)])
    rc, log = _run_copy(repo, root, tempfile.mkdtemp(dir=tmp))
    check('FIXED', 'R3-7 generator exits 0', rc, 0)
    check('FIXED', 'R3-7 divergence detected', 'COHORT DIVERGENCE' in log, True)
    check('FIXED', 'R3-7 names the diverging module', 'emacs' in log, True)
    check('FIXED', 'R3-7 names the sibling script',
          '13_storage_ratios.sh' in log, True)

def t_unreadable_sibling_is_not_silence(tmp):
    """R3-7 FIXED (second half) -- "I could not check" must never read as "it
    agrees". If the sibling's LARGE declaration cannot be found -- renamed,
    moved, rewritten -- the generator says the cohorts are UNVERIFIED rather
    than passing quietly, which is the failure mode that let every check in
    this project's history pass while proving nothing.
    """
    repo = _repo_copy(tmp)
    sib = os.path.join(repo, 'scripts', '13_storage_ratios.sh')
    src = io.open(sib, encoding='utf-8').read()
    io.open(sib, 'w', encoding='utf-8').write(
        re.sub(r'^LARGE\s*=\s*\{.*?\}', 'COHORT = {}', src, count=1,
               flags=re.S | re.M))
    root = newroot(tmp, [('base', 1 << 20), ('gcc', 1 << 22)])
    rc, log = _run_copy(repo, root, tempfile.mkdtemp(dir=tmp))
    check('FIXED', 'R3-7 generator exits 0', rc, 0)
    check('FIXED', 'R3-7 unreadable sibling reported',
          'COHORT CONSISTENCY UNVERIFIED' in log, True)

def t_agreeing_cohorts_are_silent(tmp):
    """R3-7 CONTROL -- the two declarations agree in the shipped tree, as they
    do today, and nothing may be reported. A false cohort alarm would cast
    doubt on the headline storage ratios every time the generator runs.
    """
    repo = _repo_copy(tmp)
    root = newroot(tmp, [('base', 1 << 20), ('gcc', 1 << 22)])
    rc, log = _run_copy(repo, root, tempfile.mkdtemp(dir=tmp))
    check('CONTROL', 'R3-7 generator exits 0', rc, 0)
    check('CONTROL', 'R3-7 no divergence reported', 'COHORT DIVERGENCE' in log,
          False)
    check('CONTROL', 'R3-7 no unverified warning',
          'COHORT CONSISTENCY UNVERIFIED' in log, False)

# =================================================================== driver
def main():
    tmp = tempfile.mkdtemp(prefix='round3-evidence-')
    try:
        print('R3-1  the digest column in provenance-artefacts.csv')
        t_sha_column_names_what_it_holds(tmp)
        print('R3-2  staleness of the monolithic baselines in storage S2')
        t_stale_monolithic_is_flagged(tmp)
        t_fresh_monolithic_is_not_flagged(tmp)
        print('R3-3  set-size coverage of the tier-1 sweep')
        t_partial_resweep_is_flagged(tmp)
        t_complete_newest_sweep_is_not_flagged(tmp)
        print('R3-4  --check must write nothing at all')
        t_check_writes_nothing(tmp)
        print('R3-5  row width against header width')
        t_short_row_is_refused(tmp)
        t_correct_row_is_accepted(tmp)
        print('R3-6  a cohort with no members')
        t_empty_cohort_has_no_ratio(tmp)
        t_populated_cohort_still_reports(tmp)
        print('R3-7  the cohort consistency check that did not exist')
        t_cohort_divergence_is_detected(tmp)
        t_unreadable_sibling_is_not_silence(tmp)
        t_agreeing_cohorts_are_silent(tmp)
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
