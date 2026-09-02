#!/usr/bin/env bash
#
# FUNCTIONAL test of a composed module set. Everything up to stage 05 is
# static analysis of metadata; this composes the union and asks whether it
# still works.
#
#   sudo ./scripts/07_smoke_test.sh base webserver pytools
#
# Order = stacking order; later modules have higher priority, as in 04.
#
# Checks:
#   F1  dpkg --audit             -- no half-installed or half-configured state
#   F2  apt-get -s install <req> -- every module's REQUESTED packages must
#                                   already be satisfied, so apt plans no work
#                                   at all (no "Inst " lines)
#   F3  ldconfig -p              -- the dynamic linker cache is populated
#   F4  per-module probe         -- from specs/modules.yaml, e.g. `nginx -t`
#
# Exit status, same contract as 05_check.sh:
#   0  all checks passed
#   1  a check FAILED -- the composed system is broken
#   2  the harness broke -- usage, missing artefact, compose failure
#
# Why it reconciles first: a naive overlay lets the topmost module's
# /var/lib/dpkg/status win outright, so dpkg would report most packages
# missing and every check below would fail for the wrong reason. The union is
# built from the MOUNTED ARTEFACTS, not the build trees -- an artefact plus
# its manifest is meant to be self-sufficient.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${HERE}/config.sh"
source "${HERE}/scripts/lib.sh"

# lib.sh's die() exits 1, which this script reserves for "a check failed".
die2() { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 2; }

[ "$(id -u)" -eq 0 ] || die2 "must run as root (mounts + chroot)"
[ $# -ge 2 ] || die2 "usage: $0 base <module> [module...]"
MODULES=("$@")

# The probes ARE the functional test. Without the catalogue this script
# degenerates into static checks that would still print a pass, which is the
# most dangerous outcome it could have. Treat a missing catalogue as a broken
# harness, not as a skip.
SPEC="${SPEC_DIR}/modules.yaml"
[ -f "$SPEC" ] || die2 "no ${SPEC} -- cannot run functional probes without the catalogue"
python3 -c 'import yaml' >/dev/null 2>&1 \
    || die2 "python3-yaml missing -- cannot read ${SPEC} (apt install python3-yaml)"

C="${BUILD_DIR}/smoke"
rm -rf "$C"; mkdir -p "$C"/{upper,work,merged}

PASS=0; FAIL=0; SKIP=0; PROBED=0
ok()   { printf '  \033[1;32m[ ok ]\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
no()   { printf '  \033[1;31m[FAIL]\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
skip() { printf '  \033[1;33m[skip]\033[0m %s\n' "$*"; SKIP=$((SKIP+1)); }
detail() { printf '%s\n' "$1" | sed 's/^/           /' | head -12; }

# ---- compose --------------------------------------------------------------
LOWERS=()
for m in "${MODULES[@]}"; do
    sq="${MOD_DIR}/${m}.sqsh"
    [ -f "$sq" ] || die2 "missing artefact ${sq}"
    mp="${C}/ro_${m}"; mkdir -p "$mp"
    do_mount -o loop,ro "$sq" "$mp"
    LOWERS=("$mp" "${LOWERS[@]}")          # prepend: later module wins
done
LOWERDIR=$(IFS=:; echo "${LOWERS[*]}")

do_mount -t overlay overlay \
    -o "lowerdir=${LOWERDIR},upperdir=${C}/upper,workdir=${C}/work" \
    "${C}/merged"
M="${C}/merged"
mount_chroot_fs "$M"
write_chroot_policy "$M"

echo
echo "========================================================================"
echo " SMOKE TEST: ${MODULES[*]}"
echo "========================================================================"

# ---- reconcile + gather per-module facts ----------------------------------
META="${C}/modules.tsv"
if ! python3 - "$C" "$MOD_DIR" "$SPEC_DIR" "$META" "${MODULES[@]}" <<'PY'
import json, os, sys

compose_dir, mod_dir, spec_dir, meta_path = sys.argv[1:5]
modules = sys.argv[5:]

def stanzas(path):
    if not os.path.exists(path): return []
    with open(path, encoding='utf-8', errors='replace') as f:
        return [s for s in f.read().split('\n\n') if s.strip()]

def field(s, k):
    for line in s.split('\n'):
        if line.startswith(k + ': '):
            return line[len(k)+2:]
    return None

# Union of dpkg status across the MOUNTED layers, later module wins. Same
# last-wins order as the overlay itself, so the catalogue matches the files.
merged, order, diverged = {}, [], []
for m in modules:
    src = os.path.join(compose_dir, 'ro_' + m, 'var/lib/dpkg/status')
    if not os.path.exists(src):
        sys.stderr.write("no status in mounted artefact for %s\n" % m)
        sys.exit(2)
    for s in stanzas(src):
        name = field(s, 'Package')
        if not name: continue
        st = (field(s, 'Status') or '').split()
        if len(st) != 3 or st[2] != 'installed':
            continue
        ver = field(s, 'Version')
        if name in merged:
            if merged[name][0] != ver:
                diverged.append((name, merged[name][1], merged[name][0], m, ver))
            merged[name] = (ver, m, s)
        else:
            merged[name] = (ver, m, s); order.append(name)

out = os.path.join(compose_dir, 'merged', 'var/lib/dpkg/status')
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, 'w', encoding='utf-8') as f:
    f.write('\n\n'.join(merged[n][2] for n in order) + '\n')
print("  reconciled catalogue : %d packages" % len(order))
if diverged:
    print("  version divergence   : %d" % len(diverged))
    for n, m1, v1, m2, v2 in diverged:
        print("      %-28s %s=%s -> %s=%s" % (n, m1, v1, m2, v2))

# Per-module probes come from the hand-written catalogue, not the artefact:
# a probe describes the module's intent, which is spec, not build output.
probes = {}
spec = os.path.join(spec_dir, 'modules.yaml')
if os.path.exists(spec):
    try:
        import yaml
        with open(spec, encoding='utf-8') as f:
            doc = yaml.safe_load(f) or {}
        for entry in (doc.get('modules') or []):
            if entry.get('name') and entry.get('probe'):
                probes[entry['name']] = str(entry['probe'])
    except Exception as exc:
        sys.stderr.write("could not read %s (%s); probes skipped\n" % (spec, exc))
else:
    sys.stderr.write("no %s; probes skipped\n" % spec)

with open(meta_path, 'w', encoding='utf-8') as f:
    for m in modules:
        req = []
        jp = os.path.join(mod_dir, m + '.json')
        if os.path.exists(jp):
            try:
                with open(jp, encoding='utf-8') as jf:
                    req = json.load(jf).get('requested') or []
            except Exception:
                pass
        f.write("%s\t%s\t%s\n" % (m, ' '.join(req), probes.get(m, '')))
PY
then
    die2 "reconciliation failed"
fi

# ---- F1: dpkg state -------------------------------------------------------
echo
echo "F1. dpkg --audit  (half-installed / half-configured state)"
AUDIT=$(in_chroot "$M" dpkg --audit 2>&1 </dev/null)
if [ -z "$AUDIT" ]; then
    ok "no broken package state"
else
    no "dpkg --audit reported problems"; detail "$AUDIT"
fi

# ---- F2: every module's requested packages are satisfied ------------------
echo
echo "F2. apt-get --simulate  (requested packages must already be satisfied)"
while IFS=$'\t' read -r name reqs probe; do
    [ -n "$reqs" ] || { skip "${name}: no requested packages recorded"; continue; }
    # shellcheck disable=SC2086
    OUT=$(in_chroot "$M" apt-get install --simulate -o Debug::NoLocking=1 \
              $reqs 2>&1 </dev/null); RC=$?
    PLANNED=$(printf '%s\n' "$OUT" | grep -c '^Inst ' || true)
    if [ "$RC" -ne 0 ]; then
        no "${name}: apt-get --simulate failed (rc=${RC})"; detail "$OUT"
    elif [ "$PLANNED" -ne 0 ]; then
        no "${name}: apt would install ${PLANNED} package(s) -- NOT satisfied"
        detail "$(printf '%s\n' "$OUT" | grep '^Inst ')"
    else
        ok "${name}: ${reqs} already satisfied"
    fi
done < "$META"

# ---- F3: dynamic linker ---------------------------------------------------
echo
echo "F3. ldconfig -p  (linker cache populated)"
# Count what ldconfig itself reports, not output lines: the first line is a
# header, so `wc -l` overstates by one.
LDOUT=$(in_chroot "$M" ldconfig -p 2>/dev/null </dev/null)
LDN=$(printf '%s\n' "$LDOUT" | sed -n 's/^\([0-9][0-9]*\) libs found.*/\1/p' | head -1)
[ -n "$LDN" ] || LDN=0
if [ "$LDN" -gt 10 ]; then
    ok "linker cache lists ${LDN} libraries"
    # NOTE: non-empty is a weak assertion. /etc/ld.so.cache is a class-5
    # last-wins file, so the composed cache is the TOP module's and omits
    # every library the other modules added. Measured on base+webserver+
    # pytools: base 96, webserver 131, pytools 107, composed 107 -- about 35
    # of webserver's libraries are missing. Nothing breaks, because they live
    # in the linker's default search paths, but a module shipping libraries
    # outside those paths WOULD break. The fix is to regenerate the cache in
    # the reconciliation layer (ARCHITECTURE section 4, still todo), not to
    # tighten this check.
else
    no "ldconfig -p reported ${LDN} libraries -- cache empty or unreadable"
fi

# ---- F4: per-module functional probes -------------------------------------
echo
echo "F4. per-module probes  (from ${SPEC_DIR}/modules.yaml)"
while IFS=$'\t' read -r name reqs probe; do
    [ -n "$probe" ] || { skip "${name}: no probe defined"; continue; }
    PROBED=$((PROBED+1))
    if OUT=$(in_chroot "$M" sh -c "$probe" 2>&1 </dev/null); then
        ok "${name}: ${probe}"
    else
        no "${name}: ${probe}"; detail "$OUT"
    fi
done < "$META"

# ---- verdict --------------------------------------------------------------
echo
echo "========================================================================"
echo " RESULT: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
if [ "$FAIL" -gt 0 ]; then
    echo " BROKEN -- the composed system does not work"
    echo "========================================================================"
    exit 1
fi
if [ "$PROBED" -eq 0 ]; then
    echo " PASSED, BUT NO FUNCTIONAL PROBE RAN -- ${SKIP} module(s) have no"
    echo " probe in ${SPEC}. Static checks only; this does NOT show the"
    echo " composed system works."
    echo "========================================================================"
    exit 0
fi
echo " OK -- composed system is functional (${PROBED} probe(s) executed)"
echo "========================================================================"
exit 0
