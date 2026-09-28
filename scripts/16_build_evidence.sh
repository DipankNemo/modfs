#!/usr/bin/env bash
#
# Regenerate thesis/evidence/ from whatever is currently on disk.
#
#   ./scripts/16_build_evidence.sh                    # write thesis/evidence/
#   ./scripts/16_build_evidence.sh --out DIR          # elsewhere
#   ./scripts/16_build_evidence.sh --check            # write nothing, report status
#   ./scripts/16_build_evidence.sh --help             # print this header
#
# Needs no root. It reads artefact sizes, manifests, the retained CSVs under
# $LOG_DIR and the run bundles under $RESULTS_DIR, all of which are
# world-readable. It mounts nothing, builds nothing and deletes nothing.
#
# Why: every number that reaches the thesis must be produced by a script
# that reads the retained evidence, never typed into a document. When the
# artefacts or results change, a re-run moves every table with them and
# nothing is hand-transcribed.
#
# Refusals: if a source file is missing, or is older than the artefacts it
# describes, its table is replaced by a "NO TABLE" block that says which
# file, how old, and what to re-run, so a stale result is never published
# silently. Nothing here prints a number it cannot name a source file for.
#
# Catalogue labelling: numbers from catalogues of different sizes must never
# appear side by side unlabelled, so every table carries the catalogue size
# derived from its own source (the distinct modules named in that CSV or
# bundle), not the catalogue size today. Where the two differ the caption
# says so.
#
# Output: one file per result family, Markdown to read and CSV to \input.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${HERE}/config.sh"
source "${HERE}/scripts/lib.sh"

OUT="${HERE}/thesis/evidence"
CHECK=0
while [ $# -gt 0 ]; do
    case "$1" in
        --out)   [ $# -ge 2 ] || die "--out needs a value"; OUT="$2"; shift 2 ;;
        --check) CHECK=1; shift ;;
        -h|--help) sed -n '2,30p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

[ "$(id -u)" -eq 0 ] && warn "running as root is unnecessary; this script only reads"

command -v python3 >/dev/null 2>&1 || die "python3 not found"
python3 -c 'import yaml' 2>/dev/null || die "python3-yaml not found (already a pipeline dependency)"

[ -d "$MOD_DIR" ] || die "no module directory: ${MOD_DIR}"

# Refuse to publish one generation's numbers into another's directory. A
# leftover MODFS_ROOT in the shell (from `source .../env.sh`) would otherwise
# write another generation's numbers into this repo's thesis/evidence. A
# non-default ROOT may write anywhere except the repo's own evidence directory.
if [ "$ROOT" != "/srv/modfs" ] && [ "$OUT" = "${HERE}/thesis/evidence" ]; then
    die "refusing to write ${ROOT} numbers into ${OUT}
   MODFS_ROOT is ${ROOT}, not the default /srv/modfs -- probably a leftover
   'source .../env.sh' in this shell. Either unset MODFS_ROOT, or pass
   --out DIR to publish this generation somewhere of its own."
fi

# --check writes nothing, not even the output directory: the compare loop
# below treats a missing path as "changed".
if [ "$CHECK" -eq 0 ]; then
    mkdir -p "$OUT" || die "cannot create ${OUT}"
fi

GIT_COMMIT="$(git -C "$HERE" rev-parse HEAD 2>/dev/null || echo unknown)"
GIT_BRANCH="$(git -C "$HERE" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
if git -C "$HERE" diff --quiet HEAD -- 2>/dev/null; then GIT_DIRTY=clean; else GIT_DIRTY=DIRTY; fi

export MODFS_GIT_COMMIT="$GIT_COMMIT" MODFS_GIT_BRANCH="$GIT_BRANCH" MODFS_GIT_DIRTY="$GIT_DIRTY"

python3 - "$OUT" "$MOD_DIR" "$LOG_DIR" "$RESULTS_DIR" "$SPEC_DIR" "$CHECK" <<'PY'
import csv, datetime, hashlib, itertools, json, os, re, sys

OUT, MOD_DIR, LOG_DIR, RESULTS_DIR, SPEC_DIR, CHECK = sys.argv[1:7]
CHECK = CHECK == '1'
import yaml

W = 1000000.0                      # decimal MB: the unit every published figure uses
NOW = datetime.datetime.now(datetime.timezone.utc)
GEN = NOW.strftime('%Y-%m-%d %H:%M:%SZ')
GIT = os.environ.get('MODFS_GIT_COMMIT', 'unknown')
GITB = os.environ.get('MODFS_GIT_BRANCH', 'unknown')
GITD = os.environ.get('MODFS_GIT_DIRTY', 'unknown')

# Which chapter each table belongs to, declared once here, so assembling the
# chapters is a matter of collecting files.
CHAPTER = {
    'tier1':      'Evaluation',
    'tier2':      'Evaluation',
    'tier3':      'Evaluation',
    'storage':    'Evaluation',
    'catalogue':  'Implementation',
    'provenance': 'Evaluation (appendix)',
}

# Modules that are not real workloads. Declared, not inferred from size or
# name, so the classification cannot drift silently as the catalogue grows.
# Keyed to the `provokes` field in specs/modules.yaml.
KIND_BY_PROVOKES = {
    'positive-control':  'control',
    'module-dependency': 'synthetic',
    'dpkg-blindness':    'synthetic',
}
# Declared cohort for the storage split. 13_storage_ratios.sh declares the
# same set, and the two must agree: they split the same catalogue and publish
# ratios that are compared against each other. They are compared below.
LARGE = {'gcc', 'java', 'rust', 'llvm', 'postgres', 'mysql', 'docker',
         'nvidia-driver-535', 'cuda-runtime'}

def sibling_large(path):
    """Parse the LARGE declaration out of a sibling script WITHOUT executing
    it. Returns None if the file or the declaration cannot be found -- which is
    itself reported, because 'I could not check' must never read as 'it agrees'.
    """
    try:
        src = open(path, encoding='utf-8').read()
    except Exception:
        return None
    m = re.search(r'^LARGE\s*=\s*\{(.*?)\}', src, re.S | re.M)
    if not m:
        return None
    return set(re.findall(r"'([^']+)'", m.group(1)))

COHORT_DIVERGENCE = ''
_sib = os.path.join(os.environ.get('MODFS_SRC', ''), 'scripts',
                    '13_storage_ratios.sh')
_other = sibling_large(_sib)
if _other is None:
    COHORT_DIVERGENCE = (
        'COHORT CONSISTENCY UNVERIFIED -- could not read a LARGE declaration '
        'from `%s`, so the storage cohorts published here are NOT known to '
        'match the ones 13_storage_ratios.sh publishes.' % _sib)
elif _other != LARGE:
    only_here = sorted(LARGE - _other)
    only_there = sorted(_other - LARGE)
    COHORT_DIVERGENCE = (
        'COHORT DIVERGENCE -- the LARGE set here and in 13_storage_ratios.sh '
        'disagree, so the two scripts split the same catalogue differently and '
        'their ratios are not comparable.%s%s Reconcile BOTH declarations.'
        % (' Only in 16_build_evidence.sh: %s.' % ', '.join(only_here)
           if only_here else '',
           ' Only in 13_storage_ratios.sh: %s.' % ', '.join(only_there)
           if only_there else ''))

PROV = []          # provenance rows, appended by every source() call
NOTES = []         # operator-visible warnings
if COHORT_DIVERGENCE:              # raised above, before NOTES existed
    NOTES.append(COHORT_DIVERGENCE)

def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for c in iter(lambda: f.read(1 << 20), b''):
            h.update(c)
    return h.hexdigest()

def mtime(path):
    return datetime.datetime.fromtimestamp(os.path.getmtime(path),
                                           datetime.timezone.utc)

def stamp(dt):
    return dt.strftime('%Y-%m-%d %H:%M:%SZ')

def source(table, path, role, catalogue_n=None):
    """Record a source file in the provenance ledger and return its mtime."""
    if not os.path.exists(path):
        PROV.append(dict(table=table, role=role, path=path, exists='no',
                         mtime='', sha256='', bytes='', catalogue_n=''))
        return None
    st = os.stat(path)
    PROV.append(dict(table=table, role=role, path=path, exists='yes',
                     mtime=stamp(mtime(path)),
                     sha256=(sha256(path) if os.path.isfile(path) else ''),
                     bytes=(st.st_size if os.path.isfile(path) else ''),
                     catalogue_n=('' if catalogue_n is None else catalogue_n)))
    return mtime(path)

# ---------------------------------------------------------------- artefacts
def artefacts():
    names = sorted({f[:-5] for f in os.listdir(MOD_DIR) if f.endswith('.json')})
    out = {}
    for n in names:
        j = os.path.join(MOD_DIR, n + '.json')
        s = os.path.join(MOD_DIR, n + '.sqsh')
        rec = dict(name=n, manifest=j, sqsh=(s if os.path.exists(s) else None),
                   bytes=(os.path.getsize(s) if os.path.exists(s) else None),
                   manifest_mtime=mtime(j),
                   sqsh_mtime=(mtime(s) if os.path.exists(s) else None))
        try:
            d = json.load(open(j, encoding='utf-8'))
        except Exception as exc:
            rec['error'] = str(exc); d = {}
        rec['doc'] = d
        out[n] = rec
    return out

ART = artefacts()
DELTAS = {k: v for k, v in ART.items() if k != 'base'}
# The newest artefact byte anything could describe. A result file older than
# this is describing something that has since been rebuilt.
ART_NEWEST = max([v['sqsh_mtime'] for v in ART.values() if v['sqsh_mtime']]
                 or [NOW])
ART_NEWEST_WHO = ', '.join(sorted(k for k, v in ART.items()
                                  if v['sqsh_mtime'] == ART_NEWEST))
CAT_NOW = len(DELTAS)

try:
    SPEC = yaml.safe_load(open(os.path.join(SPEC_DIR, 'modules.yaml'),
                               encoding='utf-8')) or {}
except Exception as exc:
    SPEC = {}; NOTES.append('cannot read modules.yaml: %s' % exc)
SPEC_MODS = {m['name']: m for m in (SPEC.get('modules') or []) if m.get('name')}
try:
    UIDS = yaml.safe_load(open(os.path.join(SPEC_DIR, 'uid-ranges.yaml'),
                               encoding='utf-8')) or {}
except Exception as exc:
    UIDS = {}; NOTES.append('cannot read uid-ranges.yaml: %s' % exc)

def kind(name):
    m = SPEC_MODS.get(name) or {}
    return KIND_BY_PROVOKES.get(m.get('provokes'), 'real')

# ------------------------------------------------------------------ writing
def caption(cat_n, measured, src, extra='', expect=None):
    """Caption carrying the catalogue size THIS table's own source covers.

    `expect` is how many modules the source SHOULD cover: for tier 2 that is
    the catalogue minus the positive control, which stage 10 excludes on
    purpose. Without it, a deliberate exclusion reads as staleness.
    """
    expect = CAT_NOW if expect is None else expect
    bits = ['**Catalogue: %s modules**' % cat_n,
            'measured %s' % (measured or 'unknown'),
            'source `%s`' % src]
    if cat_n not in ('', None) and str(cat_n) != str(expect):
        bits.append('**covers %s of the %d modules it should — this table is '
                    'not current**' % (cat_n, expect))
    if extra:
        bits.append(extra)
    return '_' + ' · '.join(bits) + '_'

def table(rows, head, align=None):
    if not rows:
        return '_(no rows)_\n'
    align = align or ['---'] * len(head)
    # Refuse rows whose width differs from the header. Markdown will not
    # complain: it renders a short row as a short row and silently drops the
    # tail of a long one.
    if len(align) != len(head):
        raise SystemExit('table(): %d alignment spec(s) for %d column(s): %r'
                         % (len(align), len(head), head))
    for i, r in enumerate(rows):
        if len(r) != len(head):
            raise SystemExit(
                'table(): row %d has %d field(s), header has %d: %r vs %r'
                % (i, len(r), len(head), r, head))
    out = ['| ' + ' | '.join(head) + ' |', '|' + '|'.join(align) + '|']
    for r in rows:
        out.append('| ' + ' | '.join('' if c is None else str(c) for c in r) + ' |')
    return '\n'.join(out) + '\n'

def unavailable(what, why, fix):
    return ('> **NO TABLE — %s.**\n>\n> %s\n>\n> Re-run: `%s`\n'
            % (what, why, fix))

FILES = {}
def emit(name, text):
    # Collapse the blank-line noise that comes of assembling a document from
    # chunks, so the Markdown reads like something a person wrote.
    FILES[name] = re.sub(r'\n{3,}', '\n\n', text).rstrip('\n') + '\n'

def write_csv(name, head, rows):
    import io
    # Same guard as table(). The thesis \inputs these CSVs, where a row one
    # field short looks like a different number, and csv.writer accepts any
    # width.
    for i, r in enumerate(rows):
        if len(r) != len(head):
            raise SystemExit(
                '%s: row %d has %d field(s), header has %d: %r vs %r'
                % (name, i, len(r), len(head), r, head))
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator='\n')
    w.writerow(head)
    for r in rows:
        w.writerow(['' if c is None else c for c in r])
    FILES[name] = buf.getvalue()

def fit(xs, ys):
    """Least squares y = a + b x, with R^2. Returns None if degenerate."""
    n = len(xs)
    if n < 3 or len(set(xs)) < 2:
        return None
    mx = sum(xs) / n; my = sum(ys) / n
    sxx = sum((x - mx) ** 2 for x in xs)
    if sxx == 0:
        return None
    b = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sxx
    a = my - b * mx
    sst = sum((y - my) ** 2 for y in ys)
    sse = sum((y - (a + b * x)) ** 2 for x, y in zip(xs, ys))
    r2 = (1 - sse / sst) if sst else float('nan')
    return a, b, r2, n

# =========================================================== TIER 1
T1_HEAD = ['combination', 'n', 'modules', 'verdict', 'exit', 'errors',
           'warnings', 'benign_overlap', 'version_skew', 'declared_conflict',
           'file_collision', 'file_collision_suppressed', 'identity_collision',
           'module_relation', 'base_drift', 'not_composable']
# Class 1 is accepted and measured, so it is never a rejection reason. These
# are the columns that can make a combination REJECT.
REJ_COLS = [('version_skew', 'class 2 version skew'),
            ('declared_conflict', 'class 3 declared conflict'),
            ('file_collision', 'class 4 file collision'),
            ('identity_collision', 'class 7 identity collision'),
            ('module_relation', 'module relation (ARCHITECTURE §5)'),
            ('base_drift', 'class 6 implicit base upgrade'),
            ('not_composable', 'precondition: not composable')]

def pick_tier1():
    """Newest CSV in LOG_DIR carrying the CURRENT stage-09 schema.

    Selecting by schema rather than by name is what keeps an older file with
    fewer columns (combinations-all.csv has no module_relation) from being
    silently read as if its zeros meant 'none found'.
    """
    cands = []
    if not os.path.isdir(LOG_DIR):
        return None, []
    for f in sorted(os.listdir(LOG_DIR)):
        if not f.endswith('.csv'):
            continue
        p = os.path.join(LOG_DIR, f)
        try:
            with open(p, encoding='utf-8') as fh:
                head = (fh.readline().rstrip('\n')).split(',')
        except Exception:
            continue
        if head == T1_HEAD:
            cands.append(p)
    if not cands:
        return None, []
    best = max(cands, key=lambda p: os.path.getmtime(p))
    return best, cands

def build_tier1():
    src, cands = pick_tier1()
    name = 'tier1'
    head = '# Tier 1 — metadata admission over all pairs and higher-N sets\n\n' \
           '**Chapter: %s**\n\n' % CHAPTER[name]
    if src is None:
        emit('tier1.md', head + unavailable(
            'no tier-1 result file with the current schema',
            'No CSV in `%s` carries stage 09\'s current header. '
            '`combinations-all.csv` exists but predates the '
            '`identity_collision` and `module_relation` columns, so reading it '
            'would report zero class-7 and zero module-relation rejections '
            'that were never measured.' % LOG_DIR,
            './scripts/09_run_combinations.sh --jobs 8'))
        write_csv('tier1-totals.csv', ['n'], [])
        return
    smt = source(name, src, 'tier-1 sweep results')
    rows = list(csv.DictReader(open(src, encoding='utf-8')))
    mods_seen = sorted({m for r in rows for m in r['modules'].split()})
    cat_n = len(mods_seen)
    source(name, src, 'tier-1 sweep results (catalogue size)', cat_n)
    PROV.pop()   # the line above only existed to carry cat_n; fold it back
    PROV[-1]['catalogue_n'] = cat_n

    stale = smt is not None and smt < ART_NEWEST
    body = [head]
    if stale:
        body.append(unavailable(
            'tier-1 results are older than the artefacts they describe',
            'The newest `.sqsh` (%s, %s) is newer than `%s` (%s). Every count '
            'below would describe manifests that have since been replaced.'
            % (ART_NEWEST_WHO, stamp(ART_NEWEST), os.path.basename(src),
               stamp(smt)),
            './scripts/09_run_combinations.sh --jobs 8 --out %s' % src))
        emit('tier1.md', '\n'.join(body))
        write_csv('tier1-totals.csv', ['n'], [])
        return

    missing = [m for m in mods_seen if m not in ART]
    absent = [m for m in DELTAS if m not in mods_seen]

    # A set-size coverage check, not just a module coverage check.
    # pick_tier1() takes the newest file with the current schema, so a later
    # `--max-n 2` re-run that covers every module but no triples would win and
    # silently drop every triple (and T1.4 with them). So compare the set sizes
    # each candidate measured.
    ns_best = {int(r['n']) for r in rows if str(r.get('n', '')).isdigit()}
    richer = []
    for cand in cands:
        if os.path.samefile(cand, src):
            continue
        try:
            orows = list(csv.DictReader(open(cand, encoding='utf-8')))
        except Exception:
            continue
        ons = {int(r['n']) for r in orows if str(r.get('n', '')).isdigit()}
        omods = {m for r in orows for m in r['modules'].split()}
        extra = sorted(ons - ns_best)
        # Only a candidate covering at least the same modules is a real
        # alternative; an older, smaller catalogue is already caught by the
        # caption and must not be recommended here.
        if extra and omods >= set(mods_seen):
            richer.append((cand, extra, len(orows)))
    if richer:
        detail = '; '.join(
            '`%s` (%d rows, also measures N=%s)'
            % (os.path.basename(c), nr, ', '.join(str(x) for x in ex))
            for c, ex, nr in richer)
        NOTES.append(
            'TIER-1 SET-SIZE COVERAGE -- the chosen sweep `%s` measures only '
            'N=%s, while an older sweep covering the same modules measures '
            'more: %s. The newest file won on mtime; it is not the most '
            'complete one.'
            % (os.path.basename(src), ', '.join(str(x) for x in sorted(ns_best)),
               detail))
        body.append(
            '> **SET-SIZE COVERAGE WARNING.** This table is built from `%s`, '
            'which measures only **N=%s**. Another sweep on disk covering the '
            'same %d modules measures set sizes this one does not: %s. The '
            'source is chosen as the NEWEST file with the current schema, so a '
            'later partial re-run (`--max-n`) silently replaces a complete one '
            'and every set size it omits disappears from the evidence without '
            'a number changing. Re-run stage 09 over the full range, or point '
            'this table at the complete sweep, before reading anything below '
            'as the tier-1 result.\n\n'
            % (os.path.basename(src), ', '.join(str(x) for x in sorted(ns_best)),
               len(mods_seen), detail))

    # ---- T1.1 totals by N
    ns = sorted({int(r['n']) for r in rows})
    verdicts = sorted({r['verdict'] for r in rows})
    t11 = []
    for n in ns:
        sub = [r for r in rows if int(r['n']) == n]
        t11.append([n, len(sub)] + [sum(1 for r in sub if r['verdict'] == v)
                                    for v in verdicts])
    body.append('## T1.1 Combinations and verdicts by set size\n\n')
    body.append(caption(cat_n, stamp(smt), src) + '\n\n')
    body.append(table(t11, ['N', 'combinations'] + verdicts))
    write_csv('tier1-totals.csv', ['n', 'combinations'] + verdicts, t11)

    # ---- T1.2 rejection breakdown by class
    t12 = []
    for n in ns:
        rej = [r for r in rows if int(r['n']) == n and r['verdict'] == 'REJECT']
        t12.append([n, len(rej)] +
                   [sum(1 for r in rej if int(r[c] or 0) > 0) for c, _ in REJ_COLS])
    body.append('\n## T1.2 Rejections by conflict class\n\n')
    body.append('_A combination may exhibit more than one class, so the class '
                'columns do not sum to the rejection count. Class 1 (benign '
                'overlap) is accepted and measured, not a rejection reason; it '
                'is in T1.3._\n\n')
    body.append(caption(cat_n, stamp(smt), src) + '\n\n')
    body.append(table(t12, ['N', 'REJECT'] + [lab for _, lab in REJ_COLS]))
    write_csv('tier1-classes.csv', ['n', 'reject'] + [c for c, _ in REJ_COLS], t12)

    # ---- T1.3 accepted-and-measured classes
    t13 = []
    for n in ns:
        sub = [r for r in rows if int(r['n']) == n]
        t13.append([n, len(sub),
                    sum(1 for r in sub if int(r['benign_overlap'] or 0) > 0),
                    sum(int(r['benign_overlap'] or 0) for r in sub),
                    sum(1 for r in sub
                        if int(r['file_collision_suppressed'] or 0) > 0),
                    sum(int(r['file_collision_suppressed'] or 0) for r in sub)])
    body.append('\n## T1.3 Classes that are measured rather than rejected\n\n')
    body.append(caption(cat_n, stamp(smt), src) + '\n\n')
    body.append(table(t13, ['N', 'combinations', 'sets with class-1 overlap',
                            'class-1 instances', 'sets with a suppressed '
                            'class-4 collision', 'suppressed instances']))
    write_csv('tier1-measured.csv',
              ['n', 'combinations', 'sets_with_benign_overlap',
               'benign_overlap_instances', 'sets_with_suppressed_collision',
               'suppressed_instances'], t13)

    # ---- T1.4 the arithmetic cross-check
    pairs = {frozenset(r['modules'].split()): r
             for r in rows if int(r['n']) == 2}
    rej_pairs = {k for k, r in pairs.items() if r['verdict'] == 'REJECT'}
    t14 = []
    detail = []
    for n in [x for x in ns if x > 2]:
        sub = [r for r in rows if int(r['n']) == n]
        contains = 0; expl = 0; unexpl = 0; nonmono = 0
        nonmono_why = {}
        for r in sub:
            ms = r['modules'].split()
            bad = [frozenset(p) for p in itertools.combinations(ms, 2)
                   if frozenset(p) in rej_pairs]
            if bad:
                contains += 1
            if r['verdict'] == 'REJECT':
                if bad: expl += 1
                else:   unexpl += 1
            elif bad:
                nonmono += 1
                for b in bad:
                    key = ' + '.join(sorted(c for c, _ in REJ_COLS
                                            if int(pairs[b][c] or 0) > 0)) or '?'
                    nonmono_why[key] = nonmono_why.get(key, 0) + 1
        t14.append([n, len(sub), contains, expl + unexpl, expl, unexpl, nonmono])
        for k, v in sorted(nonmono_why.items(), key=lambda kv: -kv[1]):
            detail.append([n, k, v])
    body.append('\n## T1.4 Arithmetic cross-check: is every higher-N rejection '
                'explained by a rejecting pair inside it?\n\n')
    body.append('_`rejecting pairs in the catalogue` = %d of %d._\n\n'
                % (len(rej_pairs), len(pairs)))
    body.append(caption(cat_n, stamp(smt), src) + '\n\n')
    body.append(table(t14, ['N', 'sets', 'sets containing a rejecting pair',
                            'REJECT', 'REJECT explained by an inner pair',
                            'REJECT **unexplained**',
                            'ACCEPT despite an inner rejecting pair']))
    write_csv('tier1-crosscheck.csv',
              ['n', 'sets', 'sets_containing_rejecting_pair', 'reject',
               'reject_explained', 'reject_unexplained',
               'accept_despite_rejecting_pair'], t14)
    if detail:
        body.append('\n### T1.4a Why a set can be admitted although a pair '
                    'inside it is rejected\n\n')
        body.append('_The class of the inner rejecting pair, counted per '
                    'containing set. Rejection is monotone under adding '
                    'modules for every class EXCEPT an unsatisfied module '
                    'relation, which a third module can satisfy._\n\n')
        body.append(table(detail, ['N', 'class of the inner rejecting pair',
                                   'containing sets admitted']))
        write_csv('tier1-nonmonotone.csv',
                  ['n', 'inner_pair_class', 'containing_sets_admitted'], detail)

    # ---- combinatorial prediction for the positive control
    ctrl = [m for m in mods_seen if kind(m) == 'control']
    if ctrl and len(ns) > 1:
        pred = []
        for c in ctrl:
            for n in ns:
                from math import comb
                pred.append([c, n, comb(cat_n - 1, n - 1),
                             sum(1 for r in rows if int(r['n']) == n
                                 and c in r['modules'].split()
                                 and int(r['not_composable'] or 0) > 0)])
        body.append('\n## T1.5 Self-validation: the positive control\n\n')
        body.append('_`%s` is built from a different archive snapshot and MUST '
                    'be refused against every sibling. Predicted = C(%d, N−1) '
                    'sets contain it; observed = sets flagged `not_composable`. '
                    'An all-ACCEPT sweep would now mean the sweep is broken._\n\n'
                    % (', '.join(ctrl), cat_n - 1))
        body.append(table(pred, ['control', 'N', 'predicted sets containing it',
                                 'observed not-composable']))
        write_csv('tier1-control.csv',
                  ['control', 'n', 'predicted', 'observed'], pred)

    if missing:
        body.append('\n> **%d module(s) named in this sweep no longer have an '
                    'artefact:** %s\n' % (len(missing), ', '.join(missing)))
    if absent:
        body.append('\n> **%d built module(s) are absent from this sweep** — '
                    'pending, catalogue grew after the sweep: %s. Re-run stage '
                    '09 to cover them.\n' % (len(absent), ', '.join(absent)))
    emit('tier1.md', '\n'.join(body))

# =========================================================== TIER 2
# V-number to CSV column. V1 has no column of its own: reconciliation having
# completed is witnessed by the row existing with a recorded reconcile time,
# and that is stated rather than implied.
VMAP = [('V1', 'reconciliation completed', 'reconcile_ms', 'positive'),
        ('V2', 'merged dpkg status is the exact union, by (name, version)',
         'pkg_ok', 'one'),
        ('V3', 'every alternatives group holds every candidate offered',
         'alt_groups_bad', 'zero'),
        ('V4', '/etc/ld.so.cache is the union of the layers\' caches',
         'ld_ok', 'one'),
        ('V5', 'dpkg --audit clean', 'audit_ok', 'one'),
        ('V6', 'account databases are the exact semantic union', 'acct_ok', 'one'),
        ('V7', 'every layer path visible in the merge', 'vis_ok', 'one'),
        ('V8', 'every debconf record any layer answered survives', 'dbc_ok', 'one')]

def build_tier2():
    name = 'tier2'
    src = os.path.join(LOG_DIR, 'compose-sweep.csv')
    head = '# Tier 2 — real compositions, verified against their own layers\n\n' \
           '**Chapter: %s**\n\n' % CHAPTER[name]
    smt = source(name, src, 'tier-2 sweep results')
    if smt is None:
        emit('tier2.md', head + unavailable(
            'tier-2 result file missing', '`%s` does not exist.' % src,
            'sudo ./scripts/10_compose_sweep.sh'))
        return
    rows = list(csv.DictReader(open(src, encoding='utf-8')))
    if not rows:
        emit('tier2.md', head + unavailable(
            'tier-2 result file is empty', '`%s` has a header and no rows.' % src,
            'sudo ./scripts/10_compose_sweep.sh'))
        return
    mods_seen = sorted({m for r in rows for m in r['modules'].split()} - {'base'})
    cat_n = len(mods_seen)
    PROV[-1]['catalogue_n'] = cat_n
    if smt < ART_NEWEST:
        emit('tier2.md', head + unavailable(
            'tier-2 results are older than the artefacts they describe',
            'The newest `.sqsh` (%s, %s) is newer than `%s` (%s).'
            % (ART_NEWEST_WHO, stamp(ART_NEWEST), os.path.basename(src),
               stamp(smt)),
            'sudo ./scripts/10_compose_sweep.sh'))
        return

    have = set(rows[0].keys())
    body = [head]
    # Stage 10 excludes the positive control by design: it is built from a
    # different snapshot and must be refused, so composing it proves nothing.
    controls = {n for n in DELTAS if kind(n) == 'control'}
    body.append('_Excluded by design: the positive control%s — built from a '
                'different snapshot, meant to be rejected at tier 1, so '
                'composing it would prove nothing._\n\n'
                % (' (%s)' % ', '.join(sorted(controls)) if controls else ''))
    cap = caption(cat_n, stamp(smt), src, expect=CAT_NOW - len(controls))

    # ---- T2.1 shape of the sample and cost by N
    ns = sorted({int(r['n']) for r in rows})
    def rng(sub, col):
        if col not in have: return 'n/a'
        v = [int(r[col]) for r in sub if r[col] not in ('', None)]
        if not v: return '-'
        return '%d' % v[0] if min(v) == max(v) else '%d–%d' % (min(v), max(v))
    def mean(sub, col):
        if col not in have: return 'n/a'
        v = [float(r[col]) for r in sub if r[col] not in ('', None)]
        return '%.0f' % (sum(v) / len(v)) if v else '-'
    t21 = []
    for n in ns:
        sub = [r for r in rows if int(r['n']) == n]
        t21.append([n, len(sub), rng(sub, 'pkg_actual'), rng(sub, 'alt_groups'),
                    rng(sub, 'dbc_expected'), mean(sub, 'mount_ms'),
                    mean(sub, 'reconcile_ms'), mean(sub, 'total_ms'),
                    mean(sub, 'verify_ms')])
    body.append('## T2.1 Compositions by set size\n\n')
    body.append(cap + '\n\n')
    body.append(table(t21, ['N', 'samples', 'packages', 'alt groups',
                            'debconf records', 'mount ms', 'reconcile ms',
                            'total ms', 'verify ms']))
    write_csv('tier2-by-n.csv',
              ['n', 'samples', 'packages', 'alt_groups', 'debconf_records',
               'mount_ms_mean', 'reconcile_ms_mean', 'total_ms_mean',
               'verify_ms_mean'], t21)

    # ---- T2.2 per-check outcome
    t22 = []
    for vn, what, col, pol in VMAP:
        if col not in have:
            t22.append([vn, what, '`%s`' % col, 'NOT IN THIS CSV',
                        'column absent — the check may not have run', ''])
            continue
        ok = 0; bad = []
        for r in rows:
            try: v = float(r[col])
            except (TypeError, ValueError): bad.append(r['sample']); continue
            good = (v > 0) if pol == 'positive' else \
                   (v == 1) if pol == 'one' else (v == 0)
            if good: ok += 1
            else: bad.append(r['sample'])
        t22.append([vn, what, '`%s`' % col, '%d / %d' % (ok, len(rows)),
                    'clean' if not bad else 'FAILED',
                    '' if not bad else 'samples ' + ','.join(bad[:10])])
    body.append('\n## T2.2 Per-check outcome, V1–V8\n\n')
    body.append('_V1 has no column of its own; a recorded `reconcile_ms` is the '
                'witness that reconciliation ran to completion, and that is '
                'weaker evidence than V2–V8 carry._\n\n')
    body.append(cap + '\n\n')
    body.append(table(t22, ['check', 'what it asserts', 'CSV column',
                            'passing', 'verdict', 'failures']))
    write_csv('tier2-checks.csv',
              ['check', 'assertion', 'column', 'passing', 'total', 'verdict'],
              [[a, b, c, d.split(' / ')[0], len(rows), e]
               for a, b, c, d, e, _ in t22])

    # ---- T2.3 cost model
    fits = []
    for col, what in (('mount_ms', 'mount'), ('reconcile_ms', 'reconcile'),
                      ('total_ms', 'total (compose only)'),
                      ('verify_ms', 'verify')):
        if col not in have:
            fits.append([what, '`%s`' % col, 'n/a', 'n/a', 'n/a', 'column absent'])
            continue
        xs = [float(r['n']) for r in rows if r[col] not in ('', None)]
        ys = [float(r[col]) for r in rows if r[col] not in ('', None)]
        f = fit(xs, ys)
        if f is None:
            fits.append([what, '`%s`' % col, '-', '-', '-', 'degenerate'])
        else:
            a, b, r2, n = f
            fits.append([what, '`%s`' % col, '%.1f' % a, '%.2f' % b,
                         '%.4f' % r2, n])
    body.append('\n## T2.3 Cost model, fitted to this sweep\n\n')
    body.append('_Ordinary least squares `ms = a + b·N` over every row of this '
                'CSV. These coefficients belong to THIS generation and must not '
                'be differenced against a fit from another one: the catalogue '
                'and the checker both change between sweeps._\n\n')
    body.append(cap + '\n\n')
    body.append(table(fits, ['quantity', 'column', 'a (intercept, ms)',
                             'b (slope, ms per module)', 'R²', 'n']))
    write_csv('tier2-fit.csv',
              ['quantity', 'column', 'intercept_ms', 'slope_ms_per_module',
               'r2', 'n'], fits)

    # ---- the identity that keeps the model honest
    if {'total_ms', 'mount_ms', 'reconcile_ms'} <= have:
        off = [r['sample'] for r in rows
               if int(r['total_ms']) != int(r['mount_ms']) + int(r['reconcile_ms'])]
        body.append('\n**`total_ms = mount_ms + reconcile_ms` holds on %d of %d '
                    'rows%s.** The total fit therefore measures COMPOSING, not '
                    'verifying; `verify_ms` is a separate column and is not '
                    'folded in.\n'
                    % (len(rows) - len(off), len(rows),
                       '' if not off else ' (exceptions: samples %s)'
                       % ','.join(off[:10])))
    absent = [m for m in DELTAS if m not in mods_seen and m not in controls]
    if absent:
        body.append('\n> **%d built module(s) never appear in this sweep** — '
                    'pending, catalogue grew after the sweep: %s. Re-run stage '
                    '10 to cover them.\n' % (len(absent), ', '.join(absent)))
    emit('tier2.md', '\n'.join(body))

# =========================================================== TIER 3
def build_tier3():
    name = 'tier3'
    head = '# Tier 3 — QEMU UEFI boot runs\n\n**Chapter: %s**\n\n' % CHAPTER[name]
    if not os.path.isdir(RESULTS_DIR):
        emit('tier3.md', head + unavailable(
            'no results directory', '`%s` does not exist.' % RESULTS_DIR,
            'sudo ./scripts/11_boot_test.sh --name <run> base <modules...>'))
        return
    bundles = []
    for dirpath, dirnames, filenames in os.walk(RESULTS_DIR):
        if 'run.json' in filenames:
            bundles.append(dirpath)
            dirnames[:] = []           # a bundle is a leaf; never recurse into one
    bundles.sort()
    if not bundles:
        emit('tier3.md', head + unavailable(
            'no run bundles', 'No directory under `%s` contains a `run.json`.'
            % RESULTS_DIR,
            'sudo ./scripts/11_boot_test.sh --name <run> base <modules...>'))
        return

    rows = []; csvrows = []
    for b in bundles:
        rid = os.path.basename(b)
        run = {}; res = {}
        try: run = json.load(open(os.path.join(b, 'run.json'), encoding='utf-8'))
        except Exception as exc: run = {'_err': str(exc)}
        rp = os.path.join(b, 'result.json')
        if os.path.exists(rp):
            try: res = json.load(open(rp, encoding='utf-8'))
            except Exception as exc: res = {'_err': str(exc)}
        mods = res.get('modules') or run.get('modules') or []
        deltas = [m for m in mods if m != 'base']
        state = failed = listen = probes = audit = '—'
        note = []
        sl = os.path.join(b, 'serial.log')
        if os.path.exists(sl):
            s = open(sl, encoding='utf-8', errors='replace').read()
            m = re.search(r'MODFS state: (.+)', s)
            state = m.group(1).strip() if m else '(no marker)'
            f = re.findall(r'MODFS failed-unit (\S+)', s)
            failed = ', '.join(f) if f else '0'
            p = re.findall(r'MODFS PROBE (\S+) (PASS|FAIL)', s)
            probes = '%d/%d' % (sum(1 for _, v in p if v == 'PASS'), len(p)) if p else '—'
            a = re.search(r'MODFS CHECK audit (PASS|FAIL)', s)
            audit = a.group(1) if a else '—'
            L = re.search(r'MODFS LISTEN-BEGIN\n(.*?)MODFS LISTEN-END', s, re.S)
            if L:
                socks = re.findall(
                    r'^(tcp|udp)\s+\S+\s+\S+\s+\S+\s+(\S+)\s+\S+\s*(.*)$',
                    L.group(1), re.M)
                owners = []
                for proto, local, tail in socks:
                    who = re.search(r'users:\(\("([^"]+)"', tail)
                    owners.append('%s→%s' % (local, who.group(1) if who else '?'))
                listen = '; '.join(sorted(set(owners))) or '(none)'
            else:
                listen = '(not recorded)'
                note.append('no LISTEN block in serial.log')
        else:
            note.append('no serial.log — the guest never reached the harness')
        if not res:
            note.append('no result.json — run did not finish')
        # Stale: an artefact in this run has been rebuilt since the run.
        # Checked over `mods` and always over base, not over `deltas` (which
        # excludes base, being the count behind N): every boot image is built
        # on base, whether or not the run recorded it by name.
        watch = set(mods) | {'base'}
        newer = sorted(m for m in watch
                       if m in ART and ART[m]['sqsh_mtime']
                       and ART[m]['sqsh_mtime'] > mtime(os.path.join(b, 'run.json')))
        if newer:
            shown = ', '.join(newer[:4])
            if len(newer) > 4:
                shown += ' and %d more' % (len(newer) - 4)
            note.append('**superseded**: %s rebuilt since this run' % shown)
        source(name, os.path.join(b, 'run.json'), 'tier-3 bundle: %s' % rid,
               len(deltas))
        rows.append([rid, len(deltas), res.get('verdict', 'no result'),
                     res.get('exit_code', '—'), state, failed, probes, audit,
                     listen if len(listen) < 90 else listen[:87] + '…',
                     res.get('duration_s', '—'), '; '.join(note)])
        csvrows.append([rid, len(deltas), ' '.join(deltas),
                        res.get('verdict', ''), res.get('exit_code', ''),
                        run.get('expectation', ''),
                        run.get('known_negative', ''), state,
                        '' if failed == '0' else failed, probes, audit, listen,
                        res.get('duration_s', ''), res.get('started_utc', ''),
                        res.get('finished_utc', ''), '; '.join(note)])

    # ---- T3.0 what the boot history amounts to
    vc = {}
    for r in csvrows:
        vc[r[3] or 'no result.json'] = vc.get(r[3] or 'no result.json', 0) + 1
    current = [r for r in csvrows if 'superseded' not in r[-1]]
    body = [head]
    body.append('## T3.0 Summary\n\n')
    body.append(table([[k, v] for k, v in sorted(vc.items())],
                      ['verdict', 'bundles']))
    body.append('\n_**%d of %d bundles describe artefacts that still exist '
                'unchanged**; the rest were superseded by a later rebuild and '
                'are retained as history, not as current evidence. A `FAIL` '
                'verdict with all probes passing is the signature of class 8: '
                'the packages compose, the services cannot coexist._\n\n'
                % (len(current), len(csvrows)))
    body.append('## T3.1 Every run bundle\n\n')
    body.append('_One row per run bundle under `%s`. A bundle is never '
                'overwritten, so this table is the complete boot history, '
                'including the runs where the harness rather than the system '
                'under test was the failure._\n\n' % RESULTS_DIR)
    # The run date here is the newest bundle's, not this script's clock, so
    # the file is byte-stable when nothing has been measured since -- which is
    # what makes `--check` usable as a drift alarm.
    newest = max((mtime(os.path.join(b, 'run.json')) for b in bundles),
                 default=None)
    body.append('_Catalogue today: %d modules · newest run %s · %d bundles_\n\n'
                % (CAT_NOW, stamp(newest) if newest else 'unknown', len(bundles)))
    body.append(table(rows, ['run', 'N', 'verdict', 'exit', 'systemd state',
                             'failed units', 'probes', 'dpkg audit',
                             'port ownership', 's', 'note']))
    write_csv('tier3.csv',
              ['run', 'n', 'modules', 'verdict', 'exit_code', 'expectation',
               'known_negative', 'systemd_state', 'failed_units', 'probes',
               'dpkg_audit', 'listeners', 'duration_s', 'started_utc',
               'finished_utc', 'note'], csvrows)

    gpu = [m for m in DELTAS if 'nvidia' in m or 'cuda' in m]
    covered = {m for r in csvrows for m in r[2].split()}
    pend = [m for m in gpu if m not in covered]
    if pend:
        body.append('\n> **GPU coverage pending:** %s built but present in no '
                    'boot bundle. Row deliberately left here rather than '
                    'omitted.\n' % ', '.join(sorted(pend)))
    emit('tier3.md', '\n'.join(body))

# =========================================================== STORAGE
def build_storage():
    name = 'storage'
    head = '# Storage — the delta model against a monolithic baseline\n\n' \
           '**Chapter: %s**\n\n' % CHAPTER[name]
    if 'base' not in ART or not ART['base']['bytes']:
        emit('storage.md', head + unavailable(
            'no base artefact', '`%s/base.sqsh` is missing, and every ratio '
            'below is defined against it.' % MOD_DIR,
            'sudo ./scripts/01_build_base.sh'))
        return
    B = ART['base']['bytes']
    names = sorted(n for n, v in DELTAS.items() if v['bytes'])
    nosq = sorted(n for n, v in DELTAS.items() if not v['bytes'])
    source(name, os.path.join(MOD_DIR, 'base.sqsh'), 'base artefact', CAT_NOW)

    EMPTY_COHORTS = []
    unknown = LARGE - set(names)
    if unknown:
        NOTES.append('declared large but not built: %s' % ', '.join(sorted(unknown)))
    sz = lambda n: DELTAS[n]['bytes']

    # The symmetric case: a large module that is built but undeclared would
    # fall silently into "small adversarial", since the split is a membership
    # test against a literal set (e.g. a driver renamed in another release).
    # Same guard as 13_storage_ratios.sh, whose LARGE set is compared above.
    _built_large = [n for n in names if n in LARGE]
    if _built_large:
        _floor = min(sz(n) for n in _built_large)
        _undecl = sorted((n for n in names if n not in LARGE and sz(n) >= _floor),
                         key=sz, reverse=True)
        if _undecl:
            NOTES.append(
                'UNDECLARED LARGE MODULE -- the storage cohorts below are wrong. '
                'At or above the large-cohort floor (%.1f MB): %s. Add it to '
                'LARGE in BOTH 16_build_evidence.sh and 13_storage_ratios.sh, or '
                'state in ARCHITECTURE section 7 why it is small.'
                % (_floor / W,
                   ', '.join('%s (%.1f MB)' % (n, sz(n) / W) for n in _undecl)))
            # And refuse to publish: a note alone scrolls past while the wrong
            # cohort table is written anyway.
            emit('storage.md', head + unavailable(
                'a module is larger than the large cohort and is not declared in it',
                'At or above the large-cohort floor (%.1f MB): %s. Publishing the '
                'cohort split now would put them in "small adversarial" and '
                'understate every ratio.'
                % (_floor / W,
                   ', '.join('`%s` (%.1f MB)' % (n, sz(n) / W) for n in _undecl)),
                'edit LARGE in BOTH scripts/16_build_evidence.sh and '
                'scripts/13_storage_ratios.sh, then re-run'))
            write_csv('storage-cohorts.csv',
                      ['cohort', 'n', 'stored_mb', 'monolithic_mb', 'ratio',
                       'mean_delta_mb'], [])
            return

    def cohort(label, ns):
        d = sum(sz(n) for n in ns); N = len(ns)
        stored = B + d; model = N * B + d
        if not N:
            # An empty cohort has no ratio: print dashes, not a fallback 0.00x
            # that would read as a measurement.
            EMPTY_COHORTS.append(label)
            return [label, 0, '%.1f' % (B / W), '—', '—', '—']
        return [label, N, '%.1f' % (stored / W), '%.1f' % (model / W),
                '%.2f×' % (model / stored if stored else 0),
                '%.1f' % (d / N / W)]
    small = [n for n in names if n not in LARGE]
    large = [n for n in names if n in LARGE]
    t = [cohort('small adversarial', small), cohort('large realistic', large),
         cohort('whole catalogue', names)]

    body = [head]
    body.append('## S1 Cohort ratios, computed from the artefacts on disk\n\n')
    body.append('_Unit: **decimal MB (10⁶)**, which is what every published '
                'figure uses; `mksquashfs` and `lib.sh`\'s `human()` print '
                'binary MiB under the same label, a 4.9 % difference._\n\n')
    body.append('_ratio = (N·B + Σd) / (B + Σd), B = %.1f MB. It tends to N as '
                'deltas shrink and to 1 as they grow._\n\n' % (B / W))
    body.append(caption(CAT_NOW, stamp(ART_NEWEST), MOD_DIR)
                + '\n\n')
    body.append(table(t, ['cohort', 'N', 'stored MB', 'monolithic MB', 'ratio',
                          'mean delta MB'], ['---', '---:', '---:', '---:',
                                             '---:', '---:']))
    write_csv('storage-cohorts.csv',
              ['cohort', 'n', 'stored_mb', 'monolithic_mb', 'ratio',
               'mean_delta_mb'], t)

    # ---- S2 the model checked against real monolithic builds
    # A monolithic baseline is itself an artefact and can go stale. It is a
    # like-for-like comparison only if it is newer than both the base and the
    # delta it is compared against. Nothing else checks this: a
    # `-monolithic.sqsh` carries no manifest, so the artefact inventory never
    # sees it.
    checked = []
    for n in names:
        mono = os.path.join(MOD_DIR, n + '-monolithic.sqsh')
        if os.path.exists(mono):
            meas = os.path.getsize(mono); modl = B + sz(n)
            mmt = mtime(mono)
            against = []
            if DELTAS[n]['sqsh_mtime'] and mmt < DELTAS[n]['sqsh_mtime']:
                against.append('delta')
            if ART['base']['sqsh_mtime'] and mmt < ART['base']['sqsh_mtime']:
                against.append('base')
            checked.append([n, '%.1f' % (meas / W), '%.1f' % (modl / W),
                            '%+.2f %%' % (100.0 * (modl / meas - 1.0)),
                            stamp(mmt),
                            'ok' if not against
                            else 'STALE: predates ' + ' and '.join(against)])
            source(name, mono, 'real monolithic build')
    body.append('\n## S2 Is the `B + d` monolithic model honest?\n\n')
    if checked:
        fresh = [r for r in checked if r[5] == 'ok']
        stale = [r for r in checked if r[5] != 'ok']
        if stale:
            NOTES.append(
                'STALE MONOLITHIC BASELINE -- %d of %d predate the delta or the '
                'base they are compared against, so their model error is not a '
                'like-for-like measurement: %s. Rebuild with '
                './scripts/02_build_delta.sh --compare <name> <pkg>.'
                % (len(stale), len(checked), ', '.join(r[0] for r in stale)))
        body.append('_The monolithic column above is MODELLED as `B + d` for '
                    'every module. Only %d of %d have a real monolithic build '
                    'to check it against._\n\n' % (len(checked), len(names)))
        if fresh:
            errs = [float(r[3].split()[0]) for r in fresh]
            body.append('_Across the %d baseline(s) that are genuinely '
                        'like-for-like the model comes in %.2f–%.2f %% HIGH, '
                        'because squashfs compresses one whole tree slightly '
                        'better than a base and a delta compressed separately '
                        '— so the model mildly OVERSTATES the saving._\n\n'
                        % (len(fresh), min(errs), max(errs)))
        if stale:
            body.append('_**%d of the %d baselines are STALE** — the '
                        '`-monolithic.sqsh` was built BEFORE the delta or the '
                        'base it is compared against, so the `model error` on '
                        'those rows compares two different builds and cannot '
                        'be read as a like-for-like measurement. Whether the '
                        'rebuild actually moved those bytes is not recoverable '
                        'from what is on disk; it needs a rebuild to settle._\n\n'
                        % (len(stale), len(checked)))
        body.append(table(checked, ['module', 'measured MB', 'modelled MB',
                                    'model error', 'built', 'baseline'],
                          ['---', '---:', '---:', '---:', '---', '---']))
        write_csv('storage-model-check.csv',
                  ['module', 'measured_mb', 'modelled_mb', 'model_error_pct',
                   'built_utc', 'baseline_freshness'],
                  [[r[0], r[1], r[2], r[3].split()[0], r[4], r[5]]
                   for r in checked])
        if fresh:
            body.append('\n**The whole-catalogue monolithic column is therefore '
                        '%d modelled figures and %d measured ones, not %d '
                        'rebuilt baselines.** Any sentence calling the '
                        'whole-catalogue baseline "rebuilt like-for-like" is '
                        'wrong; the %d FRESH one(s) are rebuilt like-for-like '
                        'and they calibrate the rest.\n'
                        % (len(names) - len(checked), len(checked), len(names),
                           len(fresh)))
        else:
            body.append('\n**The model is currently UNCALIBRATED.** All %d '
                        'monolithic baselines on disk predate the delta or the '
                        'base they would check, so not one is a like-for-like '
                        'comparison. The whole-catalogue monolithic column is '
                        '%d modelled figures and ZERO usable measured ones. No '
                        'sentence in the thesis may call any part of that '
                        'baseline "rebuilt like-for-like" until these are '
                        'rebuilt.\n' % (len(checked), len(names)))
    else:
        body.append(unavailable(
            'no monolithic baselines on disk',
            'The ratio column above is an unchecked model.',
            'sudo ./scripts/02_build_delta.sh --compare <name> <pkg>'))

    # ---- S3 per-module saving
    per = []
    for n in sorted(names, key=lambda x: -sz(x)):
        modl = B + sz(n)
        per.append([n, kind(n), '%.1f' % (sz(n) / W), '%.1f' % (modl / W),
                    '%.1f %%' % (100.0 * (1.0 - sz(n) / modl))])
    body.append('\n## S3 Per-module saving against its own monolithic image\n\n')
    body.append('_`1 − d/(B+d)`. The thinner the module, the more the delta '
                'model wins; a module much larger than the base shares nothing '
                'to amortise._\n\n')
    body.append(caption(CAT_NOW, stamp(ART_NEWEST), MOD_DIR)
                + '\n\n')
    body.append(table(per, ['module', 'kind', 'delta MB', 'monolithic MB',
                            'saving'], ['---', '---', '---:', '---:', '---:']))
    write_csv('storage-per-module.csv',
              ['module', 'kind', 'delta_mb', 'monolithic_mb', 'saving_pct'],
              [[a, b, c, d, e.replace(' %', '')] for a, b, c, d, e in per])

    # ---- S4 sensitivity: what the catalogue composition does to the headline
    body.append('\n## S4 Sensitivity — the headline ratio is a property of the '
                'catalogue, not only of the method\n\n')
    body.append('_Each row removes one cohort from the whole-catalogue figure '
                'and recomputes. The spread between these rows is the answer to '
                '"why does the published ratio keep changing"._\n\n')
    sens = [cohort('all %d modules (headline)' % len(names), names)]
    for drop, lab in ((LARGE, 'large realistic'),
                      ({n for n in names if kind(n) != 'real'},
                       'control + synthetic')):
        keep = [n for n in names if n not in drop]
        if keep and len(keep) != len(names):
            sens.append(cohort('minus %s (%d left)' % (lab, len(keep)), keep))
    # Largest single contributors, one at a time.
    for n in sorted(names, key=lambda x: -sz(x))[:3]:
        keep = [x for x in names if x != n]
        sens.append(cohort('minus %s alone (%d left)' % (n, len(keep)), keep))
    body.append(table(sens, ['catalogue', 'N', 'stored MB', 'monolithic MB',
                             'ratio', 'mean delta MB'],
                      ['---', '---:', '---:', '---:', '---:', '---:']))
    write_csv('storage-sensitivity.csv',
              ['catalogue', 'n', 'stored_mb', 'monolithic_mb', 'ratio',
               'mean_delta_mb'], sens)

    # ---- S5 reconcile the figures already published in the documents
    # Declared as the literal text of each document, so the comparison below
    # is against what is printed, not against a remembered value.
    PUBLISHED = [
        ('docs/STATE_OF_PLAY_2026-09-18.md', '6', '38 modules, 2026-09-16',
         '5.59x / 1.32x / 2.51x', 'minus-gpu', 1.0),
        ('ARCHITECTURE.md', '7 "Storage depends on the catalogue"',
         '38 modules, 2026-09-16', '5.59x / 1.32x / 2.51x', 'minus-gpu', 1.0),
        ('ARCHITECTURE.md', '7 re-measure block', '40 modules, 2026-09-19',
         '5.59x / 1.20x / 1.84x', 'all', 1.0),
        ('thesis/PLAN.md', 'ch. 6 list', '40 modules',
         '5.59x / 1.20x / 1.84x', 'all', 1.0),
        ('docs/REASSESSMENT_2026-09-10.md', '8.2', '37 modules, 2026-09-10',
         '2.47x whole', 'gone', 0.993),
    ]
    # The two real GPU modules, named exactly: matching on 'nvidia' or 'cuda'
    # would also catch the synthetic fake-nvidia-driver and fake-cuda.
    GPU = {'nvidia-driver-535', 'cuda-runtime'} & set(names)
    recon = []
    for doc, sec, cat, pub, how, cal in PUBLISHED:
        if how == 'all':
            sub = names
        elif how == 'minus-gpu':
            sub = [n for n in names if n not in GPU]
        else:
            recon.append([doc, sec, cat, pub, '-', '-',
                          'NOT REPRODUCIBLE: that generation was overwritten '
                          'by the 2026-09-16 full rebuild'])
            continue
        sm = [n for n in sub if n not in LARGE]
        lg = [n for n in sub if n in LARGE]
        def ratio(ns):
            d = sum(sz(x) for x in ns)
            return ((len(ns) * B + d) * cal) / (B + d) if ns else 0.0
        got = '%.2fx / %.2fx / %.2fx' % (ratio(sm), ratio(lg), ratio(sub))
        recon.append([doc, sec, cat, pub, len(sub), got,
                      'reproduces' if got == pub else '**differs**'])
    body.append('\n## S5 Every published storage figure, recomputed from the '
                'artefacts on disk today\n\n')
    body.append('_Same formula in every row: `(N.B + Sd) / (B + Sd)`, decimal '
                'MB. The only things that differ between the published figures '
                'are WHICH modules were in the catalogue and whether the '
                'x0.993 monolithic calibration was applied. A row that '
                'reproduces shows the published number was right FOR ITS '
                'CATALOGUE: the catalogue moved, not the method._\n\n')
    body.append(table(recon, ['document', 'section', 'catalogue as described',
                              'as published', 'N today', 'recomputed today',
                              'verdict']))
    write_csv('storage-published-reconciliation.csv',
              ['document', 'section', 'catalogue_described', 'published',
               'n_today', 'recomputed', 'verdict'], recon)

    if nosq:
        body.append('\n> **%d module(s) have a manifest but no artefact** and '
                    'are excluded from every figure above — pending: %s.\n'
                    % (len(nosq), ', '.join(nosq)))
    if unknown:
        body.append('\n> **Declared in the large cohort but not built:** %s. '
                    'Pending; the large-cohort ratio will move when they land.\n'
                    % ', '.join(sorted(unknown)))
    if EMPTY_COHORTS:
        seen = sorted(set(EMPTY_COHORTS))
        NOTES.append(
            'EMPTY COHORT -- %s has no members, so it has no ratio; the row is '
            'dashed rather than reported as 0.00x.' % ', '.join(seen))
        body.append('\n> **Empty cohort(s):** %s. A cohort with no members has '
                    'no ratio to report, so those rows are dashed. They are not '
                    'a measured 1.00x and must not be read as one.\n'
                    % ', '.join(seen))
    emit('storage.md', '\n'.join(body))

# =========================================================== CATALOGUE
def build_catalogue():
    name = 'catalogue'
    head = '# Catalogue — every module, what it is, and why it is here\n\n' \
           '**Chapter: %s**\n\n' % CHAPTER[name]
    spec_path = os.path.join(SPEC_DIR, 'modules.yaml')
    uid_path = os.path.join(SPEC_DIR, 'uid-ranges.yaml')
    source(name, spec_path, 'module catalogue (source of truth)', len(SPEC_MODS))
    source(name, uid_path, 'UID window assignments',
           len((UIDS.get('ranges') or {})))
    if not SPEC_MODS:
        emit('catalogue.md', head + unavailable(
            'catalogue spec unreadable', '`%s` could not be parsed.' % spec_path,
            'check specs/modules.yaml'))
        return
    width = int(UIDS.get('width') or 100)
    ranges = UIDS.get('ranges') or {}

    rows = []; csvrows = []
    allnames = sorted(set(SPEC_MODS) | set(DELTAS))
    for n in allnames:
        spec = SPEC_MODS.get(n)
        a = ART.get(n)
        pkgs = ', '.join((spec or {}).get('packages') or []) or '—'
        k = kind(n)
        if spec and spec.get('snapshot'):
            k += ' (snapshot %s)' % spec['snapshot']
        r = ranges.get(n)
        window = '%d–%d' % (int(r), int(r) + width - 1) if r is not None else '**unassigned**'
        if a and a['bytes']:
            size = '%.1f' % (a['bytes'] / W)
            npkg = len((a['doc'].get('packages') or {}))
            built = (a['doc'].get('built') or '')
            status = 'built'
            if a['manifest_mtime'] < a['sqsh_mtime']:
                status = '**manifest stale**'
        elif a:
            size = '—'; npkg = len((a['doc'].get('packages') or {}))
            built = a['doc'].get('built') or ''
            status = 'pending — manifest without artefact'
        else:
            size = '—'; npkg = '—'; built = ''
            status = 'pending — in the spec, not built'
        if spec is None:
            status = 'artefact with no spec entry'
        rows.append([n, k, pkgs if len(pkgs) < 50 else pkgs[:47] + '…',
                     size, npkg, window, (spec or {}).get('provokes', '—'),
                     status])
        csvrows.append([n, k, ' '.join((spec or {}).get('packages') or []),
                        (a['bytes'] if a and a['bytes'] else ''), npkg,
                        (r if r is not None else ''),
                        (int(r) + width - 1) if r is not None else '',
                        (spec or {}).get('provokes', ''), built, status])

    body = [head]
    counts = {}
    for n in allnames:
        counts[kind(n)] = counts.get(kind(n), 0) + 1
    body.append('_%d entries: %s. `base` is not a sibling and has no UID '
                'window._\n\n' % (len(rows), ', '.join('%d %s' % (v, k)
                                  for k, v in sorted(counts.items()))))
    body.append(caption(CAT_NOW, stamp(ART_NEWEST), spec_path,
                        'UID windows are %d wide from %s, append-only'
                        % (width, UIDS.get('first', '?'))) + '\n\n')
    body.append(table(rows, ['module', 'kind', 'requested packages',
                             'artefact MB', 'packages in delta', 'UID window',
                             'provokes', 'status'],
                      ['---', '---', '---', '---:', '---:', '---', '---', '---']))
    write_csv('catalogue.csv',
              ['module', 'kind', 'requested_packages', 'artefact_bytes',
               'package_count', 'uid_start', 'uid_end', 'provokes', 'built_utc',
               'status'], csvrows)

    # cohort declaration has to stay in step with 13_storage_ratios.sh
    body.append('\n## C2 Cohort and kind, as declared\n\n')
    body.append('_`kind` comes from the `provokes` field in `modules.yaml` via a '
                'declared map, and the large/small cohort from a declared set — '
                'neither is inferred from artefact size, so neither can drift '
                'silently as the catalogue grows._\n\n')
    body.append(table([['control', 'built from a different archive snapshot; '
                        'must be refused against every sibling',
                        ', '.join(sorted(n for n in allnames if kind(n) == 'control')) or '—'],
                       ['synthetic', 'exists to exercise a mechanism, not to be '
                        'a realistic workload',
                        ', '.join(sorted(n for n in allnames if kind(n) == 'synthetic')) or '—'],
                       ['large realistic', 'real workload in the large storage '
                        'cohort',
                        ', '.join(sorted(n for n in allnames if n in LARGE)) or '—']],
                      ['kind', 'meaning', 'members']))
    emit('catalogue.md', '\n'.join(body))

# =========================================================== PROVENANCE
def build_provenance():
    name = 'provenance'
    body = ['# Provenance — every table, its source, and that source\'s identity\n\n',
            '**Chapter: %s**\n\n' % CHAPTER[name]]
    body.append('_Generated %s from `%s` at commit `%s` (branch `%s`, working '
                'tree %s). The commit is the state of the PIPELINE when this '
                'table was generated, which is not necessarily the commit the '
                'measurement was taken at — where a run bundle records its own '
                'commit, that file is the authority._\n\n'
                % (GEN, RESULTS_DIR, GIT, GITB, GITD))
    body.append('_Catalogue today: **%d modules** (%d with artefacts). Newest '
                'artefact: `%s` at %s._\n\n'
                % (CAT_NOW, sum(1 for v in DELTAS.values() if v['bytes']),
                   ART_NEWEST_WHO, stamp(ART_NEWEST)))
    rows = [[p['table'], CHAPTER.get(p['table'], '—'), '`%s`' % p['path'],
             p['role'], p['exists'], p['mtime'],
             (p['sha256'][:16] + '…') if p['sha256'] else '—',
             p['catalogue_n'] or '—'] for p in PROV]
    body.append(table(rows, ['table', 'chapter', 'source file', 'role',
                             'exists', 'mtime (UTC)', 'sha256 (first 16)',
                             'catalogue size at the time']))
    write_csv('provenance.csv',
              ['table', 'chapter', 'path', 'role', 'exists', 'mtime_utc',
               'sha256', 'bytes', 'catalogue_n'],
              [[p['table'], CHAPTER.get(p['table'], ''), p['path'], p['role'],
                p['exists'], p['mtime'], p['sha256'], p['bytes'],
                p['catalogue_n']] for p in PROV])
    body.append('\n## P2 Artefact inventory\n\n')
    inv = []
    for n in sorted(ART):
        v = ART[n]
        inv.append([n, v['bytes'] if v['bytes'] else '—',
                    stamp(v['sqsh_mtime']) if v['sqsh_mtime'] else '—',
                    stamp(v['manifest_mtime']),
                    ((v['doc'].get('artifact') or {}).get('sha256') or '')[:16] + '…',
                    'manifest older than artefact'
                    if (v['sqsh_mtime'] and v['manifest_mtime'] < v['sqsh_mtime'])
                    else 'ok'])
    body.append('_The `sha256` column is the digest of the **artefact** '
                '(`<module>.sqsh`) as the manifest RECORDS it -- it is NOT the '
                'digest of the manifest file itself, and it is not recomputed '
                'here; `verify_bundle` in `lib.sh` and `12_verify_binding.sh` '
                'are what check it against the bytes._\n\n')
    body.append(table(inv, ['artefact', 'bytes', 'artefact mtime',
                            'manifest mtime', 'artefact sha256 (recorded)',
                            'freshness'],
                      ['---', '---:', '---', '---', '---', '---']))
    write_csv('provenance-artefacts.csv',
              ['module', 'bytes', 'sqsh_mtime_utc', 'manifest_mtime_utc',
               'artefact_sha256_recorded', 'freshness'],
              [[n, ART[n]['bytes'] or '',
                stamp(ART[n]['sqsh_mtime']) if ART[n]['sqsh_mtime'] else '',
                stamp(ART[n]['manifest_mtime']),
                (ART[n]['doc'].get('artifact') or {}).get('sha256') or '',
                'manifest_older' if (ART[n]['sqsh_mtime'] and
                                     ART[n]['manifest_mtime'] < ART[n]['sqsh_mtime'])
                else 'ok'] for n in sorted(ART)])
    if NOTES:
        body.append('\n## P3 Notes raised while generating\n\n')
        for x in NOTES:
            body.append('- %s\n' % x)
    emit('provenance.md', ''.join(body) if False else '\n'.join(body))

# ------------------------------------------------------------------ run
build_tier1()
build_tier2()
build_tier3()
build_storage()
build_catalogue()
build_provenance()

# README so the directory explains itself to whoever opens it next.
idx = ['# thesis/evidence — generated, do not hand-edit\n',
       '\nEvery file here is written by `scripts/16_build_evidence.sh` from the '
       'retained CSVs, run bundles and artefacts. Re-run it and every number '
       'moves. Hand edits are lost.\n',
       '\nGenerated %s · commit `%s` (%s) · catalogue **%d modules**\n'
       % (GEN, GIT, GITD, CAT_NOW),
       '\n| file | chapter | contents |\n|---|---|---|\n']
for k, ch in (('tier1', 'tier1.md'), ('tier2', 'tier2.md'),
              ('tier3', 'tier3.md'), ('storage', 'storage.md'),
              ('catalogue', 'catalogue.md'), ('provenance', 'provenance.md')):
    idx.append('| `%s` | %s | see the file |\n' % (ch, CHAPTER[k]))
idx.append('\nHand-written companions in this directory, NOT generated and '
           'NOT overwritten by this script:\n\n'
           '- `claims.md` — audit of every quantitative claim in the '
           'documents, marked TRACED / STALE / UNTRACEABLE (Discussion)\n'
           '- `inconsistencies.md` — where the documents disagree with each '
           'other or with the evidence (Discussion)\n'
           '- `storage-resolution.md` — which storage ratio is canonical and '
           'why the others differ (Evaluation + Discussion)\n')
emit('README.md', ''.join(idx))

# ------------------------------------------------------------------ output
changed = []
for fn, text in sorted(FILES.items()):
    p = os.path.join(OUT, fn)
    old = None
    if os.path.exists(p):
        try: old = open(p, encoding='utf-8').read()
        except Exception: old = None
    if old == text:
        continue
    changed.append(fn)
    if not CHECK:
        with open(p, 'w', encoding='utf-8') as f:
            f.write(text)

print('=' * 78)
print(' EVIDENCE  %s  catalogue %d modules  commit %s (%s)'
      % (GEN, CAT_NOW, GIT[:12], GITD))
print('=' * 78)
for fn in sorted(FILES):
    print('  %-28s %7d B  %s' % (fn, len(FILES[fn]),
                                 'CHANGED' if fn in changed else 'unchanged'))
print('=' * 78)
missing = [p['path'] for p in PROV if p['exists'] == 'no']
if missing:
    print(' MISSING SOURCES (the table says so in place of a number):')
    for m in sorted(set(missing)):
        print('   %s' % m)
for x in NOTES:
    print(' note: %s' % x)
print(' %s: %s' % ('would write' if CHECK else 'wrote', OUT))
print('=' * 78)
PY
rc=$?
[ $rc -eq 0 ] || die "evidence generation failed (exit ${rc})"
exit 0
