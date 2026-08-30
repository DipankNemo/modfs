#!/usr/bin/env bash
#
# Consistency checker for a set of delta modules.
#
#   ./scripts/05_check.sh webserver pytools
#
# Checks performed:
#   C0  composability -- do the modules share parent, snapshot, suite, arch?
#   C1  base drift    -- does a delta UPGRADE a package inherited from base?
#                        (implicit base upgrade) + WHY, traced through deps
#   C2  version skew  -- do two siblings disagree on a package version?
#   C3  benign overlap-- same package, same version, in two siblings
#   C4  declared conflicts -- Conflicts:/Breaks: between modules
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

# ------------------------------------------------- C0: composability
# ARCHITECTURE section 2: modules are composable only with siblings sharing
# the same base AND the same snapshot. That constraint was documented but
# never enforced -- the manifest is what finally makes it checkable.
print("\n" + "=" * 72)
print(" C0. COMPOSABILITY PRECONDITIONS  (same parent, snapshot, suite, arch)")
print("=" * 72 + "\n")

for m in modules:
    d = docs[m]
    if d.get('schema') != SCHEMA:
        WARNINGS += 1
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
        WARNINGS += 1
        print("    %s: no explicit module version  [WARNING]"
              " -- rebuild with --version" % m)

if not ERRORS and not WARNINGS:
    print("    all modules share parent 'base', snapshot %s, %s/%s  [OK]"
          % (base_doc.get('snapshot'), base_doc.get('suite'), base_doc.get('arch')))

# ------------------------------------------------- C1: base drift + chain
print("\n" + "=" * 72)
print(" C1. IMPLICIT BASE UPGRADE  (delta replaces a package inherited")
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
    WARNINGS += len(upgraded)
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

# ------------------------------------------------- C2/C3: sibling compare
print("=" * 72)
print(" C2/C3. SIBLING COMPARISON  (version skew vs benign overlap)")
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

# ------------------------------------------------- C4: declared conflicts
print("\n" + "=" * 72)
print(" C4. DECLARED CONFLICTS / BREAKS")
print("=" * 72)

# The composed system: base, minus anything a module removes, with every
# module's contribution layered on top.
union = dict(base)
for m in modules:
    for r in (docs[m].get('removed') or []):
        union.pop(r, None)
    union.update(contrib[m])

found = 0
for p, d in union.items():
    for kind in ('conflicts', 'breaks'):
        for grp in d[kind]:
            for (n, op, v) in grp:
                if n == p or n not in union: continue
                ov = union[n]['version']
                hit = True if not op else (vcmp(ov, op, v) is True)
                if hit:
                    found += 1; ERRORS += 1
                    cons = " (%s %s)" % (op, v) if op else ""
                    print("    %s %s %s%s -- present at %s"
                          % (p, kind.upper(), n, cons, ov))
if not found:
    print("\n    none  [OK]")

# Note: Replaces and Provides are now carried in the manifest but not yet
# checked. They are what conflict class 4 (file collision) and virtual
# package resolution will need.

# ------------------------------------------------- verdict
print("\n" + "=" * 72)
print(" VERDICT: %d error(s), %d warning(s)" % (ERRORS, WARNINGS))
if ERRORS:
    print(" REJECT -- module set is not consistently composable")
elif WARNINGS:
    print(" ACCEPT WITH WARNINGS -- composable, but base drift detected;")
    print(" siblings run against package versions they were not built with")
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
