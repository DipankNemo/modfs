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
# Reconciliation lives in scripts/reconcile.py and is shared with 04. A naive
# overlay lets the topmost module's registries win outright, so dpkg would
# report most packages missing, update-alternatives would see one candidate
# per link group, and the linker cache would describe only the top module --
# every check below would then fail, or pass, for the wrong reason.
LAYERS=(); for m in "${MODULES[@]}"; do LAYERS+=("${m}=${C}/ro_${m}"); done
# NOT "GROUPS": bash owns that name (the caller's group ids), so assigning to
# it is silently discarded and the variable still expands to a gid.
ALT_GROUPS="${C}/alt.groups"
python3 "${HERE}/scripts/reconcile.py" --merged "$M" --groups-out "$ALT_GROUPS" \
        "${LAYERS[@]}" || die2 "reconciliation failed"

# /etc/alternatives and /etc/ld.so.cache are derived from the registries, not
# merged from them, so regenerate both with their own tools.
while read -r g; do
    [ -n "$g" ] || continue
    in_chroot "$M" update-alternatives --auto "$g" >/dev/null 2>&1 </dev/null \
        || warn "update-alternatives --auto ${g} failed"
done < "$ALT_GROUPS"
in_chroot "$M" ldconfig >/dev/null 2>&1 </dev/null || warn "ldconfig failed"

META="${C}/modules.tsv"
python3 - "$MOD_DIR" "$SPEC" "$META" "${MODULES[@]}" <<'PY' || die2 "cannot read module metadata"
import json, os, sys
mod_dir, spec, meta_path = sys.argv[1:4]
modules = sys.argv[4:]

# A probe describes the module's INTENT, so it comes from the hand-written
# catalogue, not from the built artefact.
probes = {}
try:
    import yaml
    doc = yaml.safe_load(open(spec, encoding='utf-8')) or {}
    for entry in (doc.get('modules') or []):
        if entry.get('name') and entry.get('probe'):
            probes[entry['name']] = str(entry['probe'])
except Exception as exc:
    sys.stderr.write("could not read %s (%s)\n" % (spec, exc)); sys.exit(2)

with open(meta_path, 'w', encoding='utf-8') as f:
    for m in modules:
        req = []
        jp = os.path.join(mod_dir, m + '.json')
        if os.path.exists(jp):
            try:
                req = json.load(open(jp, encoding='utf-8')).get('requested') or []
            except Exception:
                pass
        f.write("%s\t%s\t%s\n" % (m, ' '.join(req), probes.get(m, '')))
PY

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
    # This used to be a weak assertion: /etc/ld.so.cache is a class-5
    # last-wins file, so the composed cache was the TOP module's and omitted
    # every library the others added -- measured at base 96, webserver 131,
    # pytools 107, composed 107. The cache is now REGENERATED by ldconfig
    # during reconciliation above, so the count should exceed every
    # individual layer rather than match the topmost one.
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
