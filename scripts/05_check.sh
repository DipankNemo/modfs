#!/usr/bin/env bash
#
# Consistency checker for a set of delta modules.
#
#   ./scripts/05_check.sh webserver pytools
#
# Checks are numbered by the CONFLICT TAXONOMY in ARCHITECTURE section 4, so
# output maps onto the table without a decoder ring:
#   PRE      composability -- same parent, snapshot, suite, arch (section 2)
#   CLASS 1  benign overlap -- same package, same version, two siblings
#   CLASS 2  version skew   -- two siblings disagree on a package version
#   CLASS 3  declared conflict -- Conflicts:/Breaks:, virtual names resolved
#   CLASS 4  file collision -- two packages own one path, Replaces honoured
#   CLASS 6  implicit base upgrade -- a delta replaces an inherited package
# Class 5 (state divergence) is deliberately absent: it ALWAYS occurs, and is
# handled by reconciliation at compose time rather than by rejection.
#
# Exit status -- the batch harness has to tell a real conflict apart from a
# broken checker, so these are a contract, not a detail:
#   0  ACCEPT   -- consistent (warnings included; base drift still composes)
#   1  REJECT   -- the modules genuinely conflict
#   2  BROKEN   -- usage error, missing/unreadable manifest, bad JSON, missing
#                  dpkg, unwritable report, or an unexpected exception
# Never conflate 1 and 2: an unhandled Python exception exits 1 by default,
# which would read as REJECT, so it is remapped to 2 below.
#
# Reads ONLY $MOD_DIR/<name>.json, written by 06_extract_metadata.sh.
# No build tree, no mounting, no building, no network -- and no root.
# This is ARCHITECTURE section 6 tier 1: ~1 s, so thousands of module
# combinations can be screened before anything is actually composed.
#
# Each manifest stores only its module's CONTRIBUTION (packages that differ
# from the parent). The merged view is reconstructed here as
#     effective(m) = base.packages | m.packages  -  m.removed
# which is why base.json must exist alongside the siblings.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${HERE}/config.sh"
source "${HERE}/scripts/lib.sh"

# lib.sh's die() exits 1, which this script reserves for REJECT.
die2() { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 2; }

[ $# -ge 1 ] || die2 "usage: $0 <module> [module...]"

# Probe the report FILE, not its directory. A writable directory is not
# enough: an earlier root-run check leaves a root-owned report behind, and a
# later unprivileged run cannot reopen it. That is an environment wart, not a
# verdict, so fall back rather than failing the check.
TAG="$(IFS=-; echo "$*")"
mkdir -p "$LOG_DIR" 2>/dev/null
OUT="${LOG_DIR}/check-${TAG}.txt"
if ! : > "$OUT" 2>/dev/null; then
    OUT="${TMPDIR:-/tmp}/modfs-check-${TAG}.txt"
    warn "cannot write ${LOG_DIR}/check-${TAG}.txt; report -> ${OUT}"
    : > "$OUT" 2>/dev/null \
        || die2 "cannot write a report to ${LOG_DIR} or ${TMPDIR:-/tmp}"
fi

python3 - "$MOD_DIR" "$OUT" "$@" <<'PY' 2>&1 | tee "$OUT"
import sys, os, json, shutil, subprocess, functools, traceback
from collections import defaultdict, deque

# An uncaught exception would exit 1 -- indistinguishable from REJECT. Remap
# it to 2 so the harness reads it as "the checker broke".
def _unexpected(exc_type, exc, tb):
    traceback.print_exception(exc_type, exc, tb)
    sys.stdout.flush(); sys.stderr.flush()
    os._exit(2)
sys.excepthook = _unexpected

mod_dir, out_path = sys.argv[1], sys.argv[2]
modules = sys.argv[3:]

SCHEMA = 1

def fail(msg):
    print("ERROR: " + msg)
    sys.exit(2)

# ---------------------------------------------------------------- loading
def load_doc(m):
    p = os.path.join(mod_dir, m + '.json')
    if not os.path.exists(p):
        fail("no metadata for '%s': %s\n"
             "       run: sudo ./scripts/06_extract_metadata.sh %s" % (m, p, m))
    try:
        with open(p, encoding='utf-8') as f:
            return json.load(f)
    except ValueError as exc:
        fail("%s is not valid JSON: %s" % (p, exc))

def strip_arch(name):
    return name.split(':')[0]

def parse_relations(field):
    """'a (>= 1) | b, c' -> [[('a','>=','1'),('b',None,None)], [('c',None,None)]]

    The manifest stores relations as raw dpkg strings rather than as nested
    arrays: dpkg's relation grammar is already specified, so re-encoding it
    would mean maintaining a second one. This is the only parser."""
    if not field: return []
    groups = []
    for grp in field.split(','):
        alts = []
        for alt in grp.split('|'):
            alt = alt.strip()
            if not alt: continue
            if '(' in alt:
                name = strip_arch(alt.split('(')[0].strip())
                cons = alt[alt.index('(')+1:alt.rindex(')')].strip()
                parts = cons.split(None, 1)
                op  = parts[0] if parts else None
                ver = parts[1].strip() if len(parts) > 1 else None
                alts.append((name, op, ver))
            else:
                alts.append((strip_arch(alt), None, None))
        if alts: groups.append(alts)
    return groups

def view(entry):
    """One manifest package entry -> the parsed shape the checks work on."""
    return {
        'version':    entry.get('version'),
        'depends':    parse_relations(entry.get('depends')),
        'predepends': parse_relations(entry.get('pre_depends')),
        'conflicts':  parse_relations(entry.get('conflicts')),
        'breaks':     parse_relations(entry.get('breaks')),
        'replaces':   parse_relations(entry.get('replaces')),
        'provides':   parse_relations(entry.get('provides')),
    }

def views(doc):
    return {n: view(e) for n, e in (doc.get('packages') or {}).items()}

def auto_set(doc):
    return {n for n, e in (doc.get('packages') or {}).items() if e.get('auto')}

# Version comparison is delegated to dpkg. Without it vcmp() returns None,
# every versioned Conflicts/Breaks test evaluates false, and the run reports
# ACCEPT for a set it never actually checked. Fail loudly instead.
if shutil.which('dpkg') is None:
    fail("dpkg not found -- cannot compare versions")

@functools.lru_cache(maxsize=None)
def vcmp(v1, op, v2):
    try:
        return subprocess.run(['dpkg', '--compare-versions', v1, op, v2]
                              ).returncode == 0
    except Exception:
        return None

# ---------------------------------------------------------------- load
if 'base' in modules:
    fail("'base' is implicit -- pass only the delta modules")

base_doc  = load_doc('base')
base      = views(base_doc)
base_auto = auto_set(base_doc)
if not base:
    fail("base.json contains no packages")

docs, contrib, effective, autos = {}, {}, {}, {}
for m in modules:
    d = load_doc(m)
    docs[m]    = d
    contrib[m] = views(d)
    if not contrib[m]:
        print("NOTE: %s contributes no packages" % m)
    # Reconstruct the merged view this module was built against. Chain
    # tracing in C1 has to walk through inherited base packages too, so the
    # contribution alone is not enough.
    eff = dict(base)
    for r in (d.get('removed') or []):
        eff.pop(r, None)
    eff.update(contrib[m])
    effective[m] = eff
    autos[m] = base_auto | auto_set(d)

print("=" * 72)
print(" CONSISTENCY CHECK: base + %s" % ' + '.join(modules))
print("=" * 72)
print("\n  base: %s packages   version %s   snapshot %s"
      % (len(base), base_doc.get('version'), base_doc.get('snapshot')))
for m in modules:
    d = docs[m]
    added = sum(1 for e in d['packages'].values() if e.get('origin') == 'added')
    upg   = sum(1 for e in d['packages'].values() if e.get('origin') == 'upgraded')
    rem   = len(d.get('removed') or [])
    print("  %s: version %s, %d added, %d upgraded from base, %d removed"
          % (m, d.get('version'), added, upg, rem))

ERRORS = WARNINGS = 0
WARN_REASONS = []

# ------------------------------------------------- PRE: composability
# ARCHITECTURE section 2: modules are composable only with siblings sharing
# the same base AND the same snapshot. That constraint was documented but
# never enforced -- the manifest is what finally makes it checkable.
print("\n" + "=" * 72)
print(" PRE. COMPOSABILITY PRECONDITIONS  (same parent, snapshot, suite, arch)")
print("=" * 72 + "\n")

for m in modules:
    d = docs[m]
    if d.get('schema') != SCHEMA:
        WARNINGS += 1; WARN_REASONS.append("manifest schema mismatch")
        print("    %s: manifest schema %s, checker expects %d  [WARNING]"
              % (m, d.get('schema'), SCHEMA))
    for key, want in (('parent',   'base'),
                      ('snapshot', base_doc.get('snapshot')),
                      ('suite',    base_doc.get('suite')),
                      ('arch',     base_doc.get('arch'))):
        got = d.get(key)
        if got != want:
            ERRORS += 1
            print("    %s: %s = %r, expected %r  *** NOT COMPOSABLE ***"
                  % (m, key, got, want))
    if not d.get('version') or d.get('version') == '0':
        WARNINGS += 1; WARN_REASONS.append("module without an explicit version")
        print("    %s: no explicit module version  [WARNING]"
              " -- rebuild with --version" % m)

if not ERRORS and not WARNINGS:
    print("    all modules share parent 'base', snapshot %s, %s/%s  [OK]"
          % (base_doc.get('snapshot'), base_doc.get('suite'), base_doc.get('arch')))

# ------------------------------------------------- CLASS 6: base drift
print("\n" + "=" * 72)
print(" CLASS 6. IMPLICIT BASE UPGRADE  (delta replaces a package inherited")
print("     from its parent -- siblings may not expect the new version)")
print("=" * 72)

for m in modules:
    pk = effective[m]
    upgraded = sorted(n for n, e in docs[m]['packages'].items()
                      if e.get('origin') == 'upgraded' and n in base)
    print("\n  --- %s ---" % m)
    if not upgraded:
        print("      no base packages upgraded  [OK]")
        continue
    WARNINGS += len(upgraded); WARN_REASONS.append("base drift (class 6)")
    print("      %d base package(s) upgraded  [WARNING]\n" % len(upgraded))

    # reverse dependency graph over this module's effective package set
    rdeps = defaultdict(set)
    for p, d in pk.items():
        for grp in d['depends'] + d['predepends']:
            for (n, _, _) in grp:
                rdeps[n].add(p)

    added = {n for n, e in docs[m]['packages'].items()
             if e.get('origin') == 'added'}
    # The manifest records what was actually asked for on the build command
    # line, so chain roots no longer have to be guessed from apt's
    # Auto-Installed flags. The old heuristic stays as the fallback.
    req   = {p for p in (docs[m].get('requested') or []) if p in pk}
    roots = req or {p for p in added if p not in autos[m]} or added

    for u in upgraded:
        bv, nv = base[u]['version'], pk[u]['version']
        print("      %s" % u)
        print("          base    : %s" % bv)
        print("          %-8s: %s" % (m, nv))

        # who demanded a version base could not satisfy?
        forcers = []
        for p, d in pk.items():
            for grp in d['depends'] + d['predepends']:
                for (n, op, v) in grp:
                    if n == u and op and v:
                        if vcmp(bv, op, v) is False:
                            forcers.append((p, op, v))
        if forcers:
            print("          forced by:")
            for (p, op, v) in sorted(set(forcers))[:6]:
                print("              %s requires %s (%s %s)"
                      " -- base %s does NOT satisfy" % (p, u, op, v, bv))
        else:
            print("          no unsatisfiable constraint found"
                  " (pocket drift, not a hard requirement)")

        # shortest path from a requested package down to u
        chain, seen, q = None, {u}, deque([[u]])
        while q and not chain:
            path = q.popleft()
            for parent in sorted(rdeps.get(path[-1], ())):
                if parent in seen: continue
                seen.add(parent)
                np = path + [parent]
                if parent in roots:
                    chain = np; break
                if len(np) < 8: q.append(np)
        if chain:
            print("          chain   : " + " -> ".join(reversed(chain)))
        print()

# ------------------------------------------------- CLASS 1/2: siblings
print("=" * 72)
print(" CLASS 1 / CLASS 2. SIBLING COMPARISON  (benign overlap vs version skew)")
print("=" * 72)

pairs = [(a, b) for i, a in enumerate(modules) for b in modules[i+1:]]
if not pairs:
    print("\n  only one module -- nothing to compare")
for a, b in pairs:
    shared = sorted(set(contrib[a]) & set(contrib[b]))
    print("\n  --- %s vs %s ---" % (a, b))
    print("      %d package(s) contributed by both" % len(shared))
    skew = 0
    for p in shared:
        va, vb = contrib[a][p]['version'], contrib[b][p]['version']
        if va == vb:
            print("        %-28s %-26s SAME (benign overlap)" % (p, va))
        else:
            skew += 1; ERRORS += 1
            print("        %-28s %s != %s   *** VERSION SKEW ***" % (p, va, vb))
    if shared and not skew:
        print("      no version skew -- snapshot pinning held  [OK]")

# ------------------------------------------------- CLASS 3: declared
print("\n" + "=" * 72)
print(" CLASS 3. DECLARED CONFLICTS / BREAKS  (virtual names resolved)")
print("=" * 72)

# The composed system: base, minus anything a module removes, with every
# module's contribution layered on top.
union = dict(base)
for m in modules:
    for r in (docs[m].get('removed') or []):
        union.pop(r, None)
    union.update(contrib[m])

# A Conflicts may name a VIRTUAL package. Two mail-transport-agents each
# declaring "Provides: mail-transport-agent" AND "Conflicts:
# mail-transport-agent" is a genuine declared conflict that matching on real
# package names alone cannot see -- measured at exactly 1 pair of 351 in the
# current catalogue.
#
# Debian policy: an UNVERSIONED Provides satisfies only an unversioned
# relation, so "Provides: foo" does not satisfy "Conflicts: foo (<< 2)".
provides_map = defaultdict(list)          # virtual name -> [(pkg, version|None)]
for p, d in union.items():
    for grp in d['provides']:
        for (n, op, v) in grp:
            provides_map[n].append((p, v if op == '=' else None))

found, seen_hits = 0, set()
for p, d in union.items():
    for kind in ('conflicts', 'breaks'):
        for grp in d[kind]:
            for (n, op, v) in grp:
                targets = []
                if n in union and n != p:
                    targets.append((n, union[n]['version'], None))
                for (prov, pver) in provides_map.get(n, ()):
                    # "Provides: X" together with "Conflicts: X" on the SAME
                    # package is the standard "I supersede standalone X"
                    # idiom, not a conflict.
                    if prov == p: continue
                    targets.append((prov, pver, n))
                for (tname, tver, via) in targets:
                    if op:
                        # versioned relation: an unversioned Provides cannot
                        # satisfy it
                        if via is not None and tver is None: continue
                        hit = vcmp(tver, op, v) is True
                    else:
                        hit = True
                    if not hit: continue
                    key = (p, kind, tname)
                    if key in seen_hits: continue
                    seen_hits.add(key)
                    found += 1; ERRORS += 1
                    cons = " (%s %s)" % (op, v) if op else ""
                    shown = tver if tver else union[tname]['version']
                    tail = "  [via virtual %s]" % via if via else ""
                    print("    %s %s %s%s -- present at %s%s"
                          % (p, kind.upper(), tname, cons, shown, tail))
if not found:
    print("\n    none  [OK]")

# ------------------------------------------------- CLASS 4: file collisions
print("\n" + "=" * 72)
print(" CLASS 4. FILE COLLISIONS  (two packages owning one path)")
print("=" * 72)

def load_sidecar(m):
    """<name>.files.json.zst -- path -> owning package, plus diversions."""
    path = os.path.join(mod_dir, m + '.files.json.zst')
    if not os.path.exists(path):
        return None
    try:
        blob = subprocess.run(['zstd', '-dcq', path],
                              capture_output=True, check=True).stdout
        return json.loads(blob)
    except Exception as exc:
        print("    cannot read %s: %s" % (path, exc))
        return None

sidecars = {m: load_sidecar(m) for m in ['base'] + modules}
absent = sorted(m for m, sc in sidecars.items() if sc is None)
if absent:
    # A check that cannot run must never be reported as a check that passed.
    WARNINGS += 1; WARN_REASONS.append("class 4 not checked (no file sidecar)")
    print("\n    SKIPPED -- no file sidecar for: %s" % ', '.join(absent))
    print("    regenerate with 06_extract_metadata.sh; class 4 was NOT checked")
else:
    def replaces_pkg(a, b):
        """Does package a declare a Replaces that package b satisfies?"""
        da, db = union.get(a), union.get(b)
        if not da or not db: return False
        bnames = set([b]) | set(n for grp in db['provides'] for (n, _, _) in grp)
        for grp in da['replaces']:
            for (n, op, v) in grp:
                if n not in bnames: continue
                if not op: return True
                if vcmp(db['version'], op, v) is True: return True
        return False

    owner, diverted = defaultdict(list), set()
    for m, sc in sidecars.items():
        for path, pkg in (sc.get('files') or {}).items():
            owner[path].append((m, pkg))
        for dv in (sc.get('diversions') or []):
            diverted.add(dv.get('path'))

    hard, soft = [], []
    for path, owners in sorted(owner.items()):
        if len(set(pkg for _, pkg in owners)) < 2: continue
        if len(set(m for m, _ in owners)) < 2: continue   # one module: dpkg vetted it
        why = 'diversion' if path in diverted else None
        if not why:
            for (_, p1) in owners:
                for (_, p2) in owners:
                    if p1 != p2 and replaces_pkg(p1, p2):
                        why = 'Replaces: %s supersedes %s' % (p1, p2); break
                if why: break
        (soft if why else hard).append((path, owners, why))

    for path, owners, _ in hard[:20]:
        ERRORS += 1
        print("    FILE COLLISION %s -- %s"
              % (path, ', '.join('%s/%s' % o for o in owners)))
    if len(hard) > 20:
        ERRORS += len(hard) - 20
        print("    ... and %d more" % (len(hard) - 20))
    if soft:
        print("\n    %d collision(s) SUPPRESSED as legitimate:" % len(soft))
        for path, owners, why in soft[:10]:
            print("      %s  [%s]" % (path, why))
        if len(soft) > 10:
            print("      ... and %d more" % (len(soft) - 10))
    if not hard:
        print("\n    no unexplained file collisions  [OK]")

# ------------------------------------------------- verdict
print("\n" + "=" * 72)
print(" VERDICT: %d error(s), %d warning(s)" % (ERRORS, WARNINGS))
if ERRORS:
    print(" REJECT -- module set is not consistently composable")
elif WARNINGS:
    # Say what actually warned. This line used to assert base drift
    # unconditionally, which became untrue the moment a second kind of
    # warning existed.
    seen = []
    for r in WARN_REASONS:
        if r not in seen: seen.append(r)
    print(" ACCEPT WITH WARNINGS -- composable, but: %s" % '; '.join(seen))
else:
    print(" ACCEPT -- module set is consistent")
print("=" * 72)

sys.exit(1 if ERRORS else 0)
PY

# pipefail is set in lib.sh, but grab both statuses explicitly: a tee failure
# must not be mistaken for the checker's own verdict.
STATUS=("${PIPESTATUS[@]}")
CHECK_RC="${STATUS[0]}"

if [ "${STATUS[1]}" -ne 0 ]; then
    warn "could not write report to ${OUT}"
    CHECK_RC=2          # the harness cannot trust a report it was told to read
fi

echo
echo "report: ${OUT}"
exit "$CHECK_RC"
