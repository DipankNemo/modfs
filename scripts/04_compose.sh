#!/usr/bin/env bash
#
# Compose modules and demonstrate conflict class 5 -- state divergence -- and
# the reconciliation that answers it.
#
#   sudo ./scripts/04_compose.sh base webserver pytools
#   sudo ./scripts/04_compose.sh base vim emacs
#
# Order = stacking order; later modules have higher priority.
#
# PHASE 1: naive overlay. Every module rewrites the same registry files, so
#          the topmost copy wins outright and the rest of the system becomes
#          invisible to dpkg, to update-alternatives and to the linker.
# PHASE 2: reconcile those registries, then regenerate what is derived from
#          them, and measure the same things again.
#
# Reads MOUNTED ARTEFACTS only. It used to read the .upper/.dir build trees,
# which quietly made composition depend on scratch directories that are
# supposed to be disposable -- and left two divergent reconciliation
# implementations in the tree. Both 04 and 07 now call scripts/reconcile.py.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${HERE}/config.sh"
source "${HERE}/scripts/lib.sh"
need_root

[ $# -ge 2 ] || die "usage: $0 base <module> [module...]"
MODULES=("$@")
# C1: identifiers reach paths and mount options; validate at the boundary.
for m in "${MODULES[@]}"; do require_ident "$m" "module name"; done

C="${BUILD_DIR}/compose"
rm -rf "$C"; mkdir -p "$C"/{upper,work,merged}

# ---- mount each artefact read-only ---------------------------------------
LAYERS=(); LOWERS=()
for m in "${MODULES[@]}"; do
    sq="${MOD_DIR}/${m}.sqsh"
    [ -f "$sq" ] || die "missing ${sq}"
    mp="${C}/ro_${m}"; mkdir -p "$mp"
    do_mount -o loop,ro "$sq" "$mp"
    LOWERS=("$mp" "${LOWERS[@]}")        # prepend: later module = higher priority
    LAYERS+=("${m}=${mp}")               # reconcile.py wants lowest-first
done

LOWERDIR=$(IFS=:; echo "${LOWERS[*]}")
log "lowerdir = ${LOWERDIR}"

do_mount -t overlay overlay \
    -o "lowerdir=${LOWERDIR},upperdir=${C}/upper,workdir=${C}/work" \
    "${C}/merged"
M="${C}/merged"
mount_chroot_fs "$M"

# ---- what the union actually contains, read from the mounts --------------
EXPECTED=$(
  for m in "${MODULES[@]}"; do
      awk '/^Package: /{p=$2} /^Status: /{if ($4=="installed" && p!="") print p}' \
          "${C}/ro_${m}/var/lib/dpkg/status" 2>/dev/null
  done | sort -u | wc -l
)

# Probe one requested package per module, from its manifest, so the
# demonstration is not hard-wired to nginx and numpy.
PROBES=$(python3 - "$MOD_DIR" "${MODULES[@]}" <<'PY'
import json, os, sys
mod_dir, mods = sys.argv[1], sys.argv[2:]
for m in mods:
    p = os.path.join(mod_dir, m + '.json')
    try:
        req = json.load(open(p, encoding='utf-8')).get('requested') or []
    except Exception:
        req = []
    if req: print(req[0])
PY
)

alt_groups() {           # groups visible in the merged view right now
    in_chroot "$M" sh -c 'ls /var/lib/dpkg/alternatives 2>/dev/null' </dev/null \
        | tr -d '\r' | grep -vE '^\s*$' || true
}
alt_count() {            # alt_count <group> -> number of candidates
    in_chroot "$M" update-alternatives --list "$1" 2>/dev/null </dev/null \
        | grep -c . || true
}
ld_count() {
    in_chroot "$M" ldconfig -p 2>/dev/null </dev/null \
        | sed -n 's/^\([0-9][0-9]*\) libs found.*/\1/p' | head -1
}

echo
echo "==========================================================="
echo " PHASE 1 -- NAIVE COMPOSITION"
echo "==========================================================="
NAIVE=$(in_chroot "$M" dpkg-query -f '${binary:Package}\n' -W 2>/dev/null </dev/null | wc -l)
echo
echo "  packages the catalogue lists : ${NAIVE}"
echo "  packages actually installed  : ${EXPECTED}"
echo "  INVISIBLE                    : $(( EXPECTED - NAIVE ))"
echo
for probe in $PROBES; do
    if in_chroot "$M" dpkg-query -W "$probe" >/dev/null 2>&1 </dev/null; then
        echo "  dpkg says '${probe}' : INSTALLED"
    else
        echo "  dpkg says '${probe}' : NOT INSTALLED"
    fi
done

GROUPS_BEFORE="${C}/groups.before"; alt_groups > "$GROUPS_BEFORE"
: > "${C}/alt.before"
while read -r g; do
    [ -n "$g" ] || continue
    printf '%s\t%s\n' "$g" "$(alt_count "$g")" >> "${C}/alt.before"
done < "$GROUPS_BEFORE"
LD_BEFORE=$(ld_count)
echo
echo "  alternatives link groups     : $(wc -l < "$GROUPS_BEFORE")"
echo "  linker cache libraries       : ${LD_BEFORE:-0}"

# ---- PHASE 2: reconcile --------------------------------------------------
echo
echo "==========================================================="
echo " PHASE 2 -- RECONCILED STATE"
echo "==========================================================="
echo
GROUPS_AFTER="${C}/groups.after"
python3 "${HERE}/scripts/reconcile.py" --merged "$M" \
        --groups-out "$GROUPS_AFTER" "${LAYERS[@]}" \
    || die "reconciliation failed"

# /etc/alternatives/* is owned by no package: there is nothing to merge, it is
# a FUNCTION of the merged registry and its priorities. update-alternatives is
# the authority on computing it, so let it, rather than reimplementing the
# rules for slaves and ties.
AUTO_OK=0; AUTO_FAIL=0
while read -r g; do
    [ -n "$g" ] || continue
    if in_chroot "$M" update-alternatives --auto "$g" >/dev/null 2>&1 </dev/null; then
        AUTO_OK=$((AUTO_OK+1))
    else
        AUTO_FAIL=$((AUTO_FAIL+1)); warn "update-alternatives --auto ${g} failed"
    fi
done < "$GROUPS_AFTER"
echo "  /etc/alternatives  : ${AUTO_OK} group(s) recomputed by priority$([ $AUTO_FAIL -gt 0 ] && echo ", ${AUTO_FAIL} failed")"

# Same argument for the linker cache: derived, so regenerate it.
if in_chroot "$M" ldconfig >/dev/null 2>&1 </dev/null; then
    echo "  /etc/ld.so.cache   : regenerated by ldconfig"
else
    warn "ldconfig failed in the merged view"
fi

RECON=$(in_chroot "$M" dpkg-query -f '${binary:Package}\n' -W 2>/dev/null </dev/null | wc -l)
LD_AFTER=$(ld_count)
echo
echo "  packages the catalogue lists : ${RECON}"
echo "  packages actually installed  : ${EXPECTED}"
echo "  INVISIBLE                    : $(( EXPECTED - RECON ))"
echo
for probe in $PROBES; do
    if in_chroot "$M" dpkg-query -W "$probe" >/dev/null 2>&1 </dev/null; then
        echo "  dpkg says '${probe}' : INSTALLED"
    else
        echo "  dpkg says '${probe}' : NOT INSTALLED"
    fi
done

# ---- alternatives before/after -------------------------------------------
echo
echo "  --- update-alternatives --list, per link group ---"
printf '      %-14s %8s %8s\n' "GROUP" "BEFORE" "AFTER"
CHANGED=0
while read -r g; do
    [ -n "$g" ] || continue
    before=$(awk -F'\t' -v g="$g" '$1==g{print $2}' "${C}/alt.before" 2>/dev/null)
    [ -n "$before" ] || before=0
    after=$(alt_count "$g")
    if [ "${after:-0}" -ne "${before:-0}" ]; then
        CHANGED=$((CHANGED+1))
        printf '      %-14s %8s %8s   <- recovered %s\n' \
               "$g" "$before" "$after" "$(( after - before ))"
    fi
done < "$GROUPS_AFTER"
[ "$CHANGED" -eq 0 ] && echo "      (no group gained candidates: no alternatives collision in this set)"

echo
echo "==========================================================="
printf "  packages   naive: %s / %s      reconciled: %s / %s\n" \
       "$NAIVE" "$EXPECTED" "$RECON" "$EXPECTED"
printf "  linker     naive: %s libs      reconciled: %s libs\n" \
       "${LD_BEFORE:-0}" "${LD_AFTER:-0}"
printf "  alt groups gaining candidates: %s\n" "$CHANGED"
echo "==========================================================="
