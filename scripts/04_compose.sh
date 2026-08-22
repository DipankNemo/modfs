#!/usr/bin/env bash
#
# Compose modules and demonstrate the dpkg state problem + the fix.
#
#   sudo ./scripts/04_compose.sh base webserver pytools
#
# Order = stacking order; later modules have higher priority.
#
# PHASE 1: naive overlay -> the package catalogue undercounts
# PHASE 2: reconciled status written to a top layer -> catalogue correct

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${HERE}/config.sh"
source "${HERE}/scripts/lib.sh"
need_root

[ $# -ge 2 ] || die "usage: $0 base <module> [module...]"
MODULES=("$@")

C="${BUILD_DIR}/compose"
rm -rf "$C"; mkdir -p "$C"/{upper,work,merged}

# ---- mount each artefact read-only ---------------------------------------
LOWERS=()
for m in "${MODULES[@]}"; do
    sq="${MOD_DIR}/${m}.sqsh"
    [ -f "$sq" ] || die "missing ${sq}"
    mp="${C}/ro_${m}"; mkdir -p "$mp"
    do_mount -o loop,ro "$sq" "$mp"
    LOWERS=("$mp" "${LOWERS[@]}")     # prepend: later module = higher priority
done

LOWERDIR=$(IFS=:; echo "${LOWERS[*]}")
log "lowerdir = ${LOWERDIR}"

do_mount -t overlay overlay \
    -o "lowerdir=${LOWERDIR},upperdir=${C}/upper,workdir=${C}/work" \
    "${C}/merged"
M="${C}/merged"
mount_chroot_fs "$M"

# ---- expected union ------------------------------------------------------
EXPECTED=$(
  for m in "${MODULES[@]}"; do
      d="${MOD_DIR}/${m}.upper"; [ -d "$d" ] || d="${MOD_DIR}/${m}.dir"
      awk '/^Package: /{print $2}' "${d}/var/lib/dpkg/status" 2>/dev/null
  done | sort -u | wc -l
)

echo
echo "==========================================================="
echo " PHASE 1 -- NAIVE COMPOSITION"
echo "==========================================================="
NAIVE=$(chroot "$M" dpkg-query -f '${binary:Package}\n' -W 2>/dev/null | wc -l)
echo
echo "  packages the catalogue lists : ${NAIVE}"
echo "  packages actually installed  : ${EXPECTED}"
echo "  INVISIBLE                    : $(( EXPECTED - NAIVE ))"
echo
for probe in nginx python3-numpy; do
    if chroot "$M" dpkg-query -W "$probe" >/dev/null 2>&1; then
        echo "  dpkg says '${probe}' : INSTALLED"
    else
        echo "  dpkg says '${probe}' : NOT INSTALLED"
    fi
done
echo
echo "  but on disk:"
for f in /usr/sbin/nginx /usr/lib/python3/dist-packages/numpy/__init__.py; do
    [ -e "${M}${f}" ] && echo "    PRESENT: ${f}" || echo "    absent : ${f}"
done

# ---- PHASE 2: reconcile --------------------------------------------------
echo
echo "==========================================================="
echo " PHASE 2 -- RECONCILED STATE LAYER"
echo "==========================================================="

python3 - "$MOD_DIR" "$M" "${MODULES[@]}" <<'PY'
import sys, os
mod_dir, merged = sys.argv[1], sys.argv[2]
modules = sys.argv[3:]

def stanzas(path):
    if not os.path.exists(path): return []
    with open(path, encoding='utf-8', errors='replace') as f:
        return [s for s in f.read().split('\n\n') if s.strip()]

def field(s, k):
    for line in s.split('\n'):
        if line.startswith(k + ': '): return line[len(k)+2:]
    return None

merged_pkgs, order, conflicts = {}, [], []
for m in modules:
    d = os.path.join(mod_dir, m + '.upper')
    if not os.path.isdir(d): d = os.path.join(mod_dir, m + '.dir')
    for s in stanzas(os.path.join(d, 'var/lib/dpkg/status')):
        name = field(s, 'Package')
        if not name: continue
        ver = field(s, 'Version')
        if name in merged_pkgs:
            if merged_pkgs[name][0] != ver:
                conflicts.append((name, merged_pkgs[name][1],
                                  merged_pkgs[name][0], m, ver))
                merged_pkgs[name] = (ver, m, s)
        else:
            merged_pkgs[name] = (ver, m, s); order.append(name)

out = os.path.join(merged, 'var/lib/dpkg/status')
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, 'w', encoding='utf-8') as f:
    f.write('\n\n'.join(merged_pkgs[n][2] for n in order) + '\n')

print(f"\n  merged stanzas written : {len(order)}")
if conflicts:
    print(f"  VERSION DIVERGENCE     : {len(conflicts)}")
    for n, m1, v1, m2, v2 in conflicts:
        print(f"      {n:<28} {m1}={v1}  ->  {m2}={v2}")
else:
    print("  version divergence     : none")
PY

echo
RECON=$(chroot "$M" dpkg-query -f '${binary:Package}\n' -W 2>/dev/null | wc -l)
echo "  packages the catalogue lists : ${RECON}"
echo "  packages actually installed  : ${EXPECTED}"
echo "  INVISIBLE                    : $(( EXPECTED - RECON ))"
echo
for probe in nginx python3-numpy; do
    if chroot "$M" dpkg-query -W "$probe" >/dev/null 2>&1; then
        echo "  dpkg says '${probe}' : INSTALLED"
    else
        echo "  dpkg says '${probe}' : NOT INSTALLED"
    fi
done

echo
echo "==========================================================="
printf "  naive: %s listed / %s real    reconciled: %s / %s\n" \
       "$NAIVE" "$EXPECTED" "$RECON" "$EXPECTED"
echo "==========================================================="
