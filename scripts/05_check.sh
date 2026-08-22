#!/usr/bin/env bash
#
# Consistency checker for a set of delta modules.
#
#   sudo ./scripts/05_check.sh webserver pytools
#
# Checks performed:
#   C1  base drift    -- does a delta UPGRADE a package inherited from base?
#                        (implicit base upgrade) + WHY, traced through deps
#   C2  version skew  -- do two siblings disagree on a package version?
#   C3  benign overlap-- same package, same version, in two siblings
#   C4  declared conflicts -- Conflicts:/Breaks: between modules
#
# Reads only metadata. No mounting, no building, no network.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${HERE}/config.sh"
source "${HERE}/scripts/lib.sh"

[ $# -ge 1 ] || die "usage: $0 <module> [module...]"

OUT="${LOG_DIR}/check-$(IFS=-; echo "$*").txt"
mkdir -p "$LOG_DIR"

python3 - "$MOD_DIR" "$OUT" "$@" <<'PY' 2>&1 | tee "$OUT"
import sys, os, subprocess, functools
from collections import defaultdict, deque

mod_dir, out_path = sys.argv[1], sys.argv[2]
modules = sys.argv[3:]

# ---------------------------------------------------------------- parsing
def read_stanzas(path):
    if not os.path.exists(path): return []
    with open(path, encoding='utf-8', errors='replace') as f:
        return [s for s in f.read().split('\n\n') if s.strip()]

def get(stanza, key):
    out, grab = [], False
    for line in stanza.split('\n'):
        if line.startswith(key + ':'):
            out.append(line[len(key)+1:].strip()); grab = True
        elif grab and line.startswith((' ', '\t')):
            out.append(line.strip())
        elif grab:
            break
    return ' '.join(out) if out else None

def strip_arch(name):
    return name.split(':')[0]

def parse_relations(field):
    """'a (>= 1) | b, c' -> [[('a','>=','1'),('b',None,None)], [('c',None,None)]]"""
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

def load(path):
    """-> {name: {'version':v, 'depends':[...], 'conflicts':[...], ...}}"""
    pkgs = {}
    for s in read_stanzas(path):
        n = get(s, 'Package')
        if not n: continue
        st = get(s, 'Status') or ''
        if 'installed' not in st: continue
        pkgs[strip_arch(n)] = {
            'version':   get(s, 'Version'),
            'depends':   parse_relations(get(s, 'Depends')),
            'predepends':parse_relations(get(s, 'Pre-Depends')),
            'conflicts': parse_relations(get(s, 'Conflicts')),
            'breaks':    parse_relations(get(s, 'Breaks')),
            'provides':  parse_relations(get(s, 'Provides')),
        }
    return pkgs

def load_auto(root):
    """packages marked Auto-Installed in apt's extended_states"""
    p = os.path.join(root, 'var/lib/apt/extended_states')
    auto = set()
    for s in read_stanzas(p):
        n = get(s, 'Package')
        if n and (get(s, 'Auto-Installed') or '0').strip() == '1':
            auto.add(strip_arch(n))
    return auto

@functools.lru_cache(maxsize=None)
def vcmp(v1, op, v2):
    try:
        return subprocess.run(['dpkg', '--compare-versions', v1, op, v2]
                              ).returncode == 0
    except Exception:
        return None

def moddir(m):
    d = os.path.join(mod_dir, m + '.upper')
    return d if os.path.isdir(d) else os.path.join(mod_dir, m + '.dir')

def status_of(m):
    return os.path.join(moddir(m), 'var/lib/dpkg/status')

# ---------------------------------------------------------------- load
base = load(status_of('base'))
if not base:
    print("ERROR: cannot read base status"); sys.exit(2)

mods, autos = {}, {}
for m in modules:
    mods[m] = load(status_of(m))
    autos[m] = load_auto(moddir(m))
    if not mods[m]:
        print(f"ERROR: cannot read status for {m}"); sys.exit(2)

print("=" * 72)
print(f" CONSISTENCY CHECK: base + {' + '.join(modules)}")
print("=" * 72)
print(f"\n  base: {len(base)} packages")
for m in modules:
    added = {p for p in mods[m] if p not in base}
    upg   = {p for p in mods[m] if p in base and mods[m][p]['version'] != base[p]['version']}
    print(f"  {m}: {len(mods[m])} total, {len(added)} added, {len(upg)} upgraded from base")

ERRORS = WARNINGS = 0

# ------------------------------------------------- C1: base drift + chain
print("\n" + "=" * 72)
print(" C1. IMPLICIT BASE UPGRADE  (delta replaces a package inherited")
print("     from its parent -- siblings may not expect the new version)")
print("=" * 72)

for m in modules:
    pk = mods[m]
    upgraded = sorted(p for p in pk
                      if p in base and pk[p]['version'] != base[p]['version'])
    print(f"\n  --- {m} ---")
    if not upgraded:
        print("      no base packages upgraded  [OK]")
        continue
    WARNINGS += len(upgraded)
    print(f"      {len(upgraded)} base package(s) upgraded  [WARNING]\n")

    # reverse dependency graph over this module's package set
    rdeps = defaultdict(set)
    for p, d in pk.items():
        for grp in d['depends'] + d['predepends']:
            for (n, _, _) in grp:
                rdeps[n].add(p)

    added  = {p for p in pk if p not in base}
    roots  = {p for p in added if p not in autos.get(m, set())} or added

    for u in upgraded:
        bv, nv = base[u]['version'], pk[u]['version']
        print(f"      {u}")
        print(f"          base    : {bv}")
        print(f"          {m:<8}: {nv}")

        # who demanded a version base could not satisfy?
        forcers = []
        for p, d in pk.items():
            for grp in d['depends'] + d['predepends']:
                for (n, op, v) in grp:
                    if n == u and op and v:
                        ok = vcmp(bv, op, v)
                        if ok is False:
                            forcers.append((p, op, v))
        if forcers:
            print("          forced by:")
            for (p, op, v) in sorted(set(forcers))[:6]:
                print(f"              {p} requires {u} ({op} {v})"
                      f" -- base {bv} does NOT satisfy")
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
    aa = {p for p in mods[a] if p not in base or mods[a][p]['version'] != base[p]['version']}
    bb = {p for p in mods[b] if p not in base or mods[b][p]['version'] != base[p]['version']}
    shared = sorted(aa & bb)
    print(f"\n  --- {a} vs {b} ---")
    print(f"      {len(shared)} package(s) contributed by both")
    skew = 0
    for p in shared:
        va, vb = mods[a][p]['version'], mods[b][p]['version']
        if va == vb:
            print(f"        {p:<28} {va:<26} SAME (benign overlap)")
        else:
            skew += 1; ERRORS += 1
            print(f"        {p:<28} {va} != {vb}   *** VERSION SKEW ***")
    if shared and not skew:
        print("      no version skew -- snapshot pinning held  [OK]")

# ------------------------------------------------- C4: declared conflicts
print("\n" + "=" * 72)
print(" C4. DECLARED CONFLICTS / BREAKS")
print("=" * 72)

union = dict(base)
for m in modules:
    for p, d in mods[m].items():
        union[p] = d

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
                    cons = f" ({op} {v})" if op else ""
                    print(f"    {p} {kind.upper()} {n}{cons}"
                          f" -- present at {ov}")
if not found:
    print("\n    none  [OK]")

# ------------------------------------------------- verdict
print("\n" + "=" * 72)
print(f" VERDICT: {ERRORS} error(s), {WARNINGS} warning(s)")
if ERRORS:
    print(" REJECT -- module set is not consistently composable")
elif WARNINGS:
    print(" ACCEPT WITH WARNINGS -- composable, but base drift detected;")
    print(" siblings run against package versions they were not built with")
else:
    print(" ACCEPT -- module set is consistent")
print("=" * 72)
PY

echo
echo "report: ${OUT}"
