#!/usr/bin/env bash
#
# TIER 2 sweep: actually compose module sets at increasing N and verify the
# composed system, rather than checking metadata about it.
#
#   sudo ./scripts/10_compose_sweep.sh
#   sudo ./scripts/10_compose_sweep.sh --seed 7 --plan 2:5,3:5
#
# Tier 1 (09_run_combinations.sh) has thousands of data points but never
# mounts anything. Tier 2 had four, all at N<=3, while the design promises
# arbitrary N. This closes that gap: 96 real compositions from N=2 to N=27.
#
# Per composition it verifies:
#   V1  reconciliation completed
#   V2  merged dpkg status is the EXACT UNION of the layers (sets, not counts)
#   V3  every alternatives group holds every candidate any layer offered
#   V4  /etc/ld.so.cache is the union of the layers' caches
#   V5  dpkg --audit is clean
# and records mount, reconcile and total time so cost against N is measurable.
#
# The positive control is excluded: it is built from a different snapshot and
# is meant to be rejected at tier 1, so composing it proves nothing.
#
# Exit: 0 every sample verified, 1 some sample failed, 2 the harness broke.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${HERE}/config.sh"
source "${HERE}/scripts/lib.sh"

die2() { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 2; }
[ "$(id -u)" -eq 0 ] || die2 "must run as root (mounts + chroot)"

SEED=1; PLAN="2:30,3:30,5:20,10:10,20:5,27:1"; CSV="${LOG_DIR}/compose-sweep.csv"
KNOWN_NEG=0
while [ $# -gt 0 ]; do
    case "$1" in
        --seed) [ $# -ge 2 ] || die2 "--seed needs a value"; SEED="$2"; shift 2 ;;
        --plan) [ $# -ge 2 ] || die2 "--plan needs a value"; PLAN="$2"; shift 2 ;;
        --out)  [ $# -ge 2 ] || die2 "--out needs a value";  CSV="$2";  shift 2 ;;
        --known-negative) KNOWN_NEG=1; shift ;;
        *) die2 "unknown option: $1" ;;
    esac
done

W="${BUILD_DIR}/csweep"
rm -rf "$W"; mkdir -p "$W"
mkdir -p "$(dirname "$CSV")" 2>/dev/null || true

# ---- sample plan ----------------------------------------------------------
# Seeded, so the sampled sets are reproducible: an evaluation that cannot be
# re-run is not evidence.
SAMPLES="$W/samples.txt"
python3 - "${SPEC_DIR}/modules.yaml" "$MOD_DIR" "$SEED" "$PLAN" "$SAMPLES" <<'PY' || die2 "cannot build the sample plan"
import itertools, json, os, random, sys, yaml
spec, mod_dir, seed, plan, out = sys.argv[1:6]

doc = yaml.safe_load(open(spec, encoding='utf-8')) or {}
mods = []
for m in (doc.get('modules') or []):
    n = m.get('name')
    if not n or n == 'base':
        continue
    if m.get('snapshot'):            # the positive control: excluded by design
        continue
    if os.path.exists(os.path.join(mod_dir, n + '.sqsh')):
        mods.append(n)
mods.sort()
if len(mods) < 2:
    sys.stderr.write("fewer than 2 usable modules\n"); sys.exit(2)

rng = random.Random(int(seed))
rows, skipped = [], []
for part in plan.split(','):
    n_s, _, c_s = part.partition(':')
    n, want = int(n_s), int(c_s)
    if n > len(mods):
        skipped.append("N=%d (only %d modules)" % (n, len(mods))); continue
    total = 1
    for k in range(n): total = total * (len(mods) - k) // (k + 1)
    take = min(want, total)
    seen, picked = set(), []
    if total <= 20000:               # small space: sample exactly, no rejection loop
        allc = list(itertools.combinations(mods, n))
        rng.shuffle(allc)
        picked = allc[:take]
    else:
        while len(picked) < take:
            c = tuple(sorted(rng.sample(mods, n)))
            if c in seen: continue
            seen.add(c); picked.append(c)
    for c in picked: rows.append((n, list(c)))

with open(out, 'w', encoding='utf-8') as f:
    for n, c in rows:
        f.write("%d\t%s\n" % (n, ' '.join(c)))
print("  modules usable      : %d  (control excluded)" % len(mods))
print("  compositions planned: %d" % len(rows))
for s in skipped: print("  SKIPPED %s" % s)
PY

require_uint "$SEED" 0 4294967295 "--seed"
TOTAL=$(wc -l < "$SAMPLES")
log "tier-2 sweep: ${TOTAL} compositions, seed ${SEED}"

# do_mount() dies on failure, which would abort the whole sweep; a failed
# composition is a RESULT here, not a reason to stop.
try_mount() {
    local target="${*: -1}"
    if mount "$@" 2>>"$W/mount.err"; then track_mount "$target"; return 0; fi
    return 1
}
now_ms() { date +%s%3N; }

echo "sample,n,modules,admitted,mount_ms,reconcile_ms,total_ms,pkg_expected,pkg_actual,pkg_ok,alt_groups,alt_groups_bad,ld_expected,ld_actual,ld_ok,audit_ok,result" > "$CSV"

# C3: integrity before anything else. A composed artefact that does not match
# its own manifest invalidates every downstream measurement.
log "verifying bundle integrity"
ALLMODS=$(cut -f2 "$SAMPLES" | tr ' ' '\n' | sort -u | tr '\n' ' ')
# shellcheck disable=SC2086
verify_bundle base $ALLMODS || die2 "bundle integrity failed; refusing to compose"

IDX=0; FAILED=0
while IFS=$'\t' read -r N MODS; do
    IDX=$((IDX+1))
    SET=(base $MODS)
    for m in "${SET[@]}"; do valid_ident "$m" || die2 "invalid module name: '$m'"; done

    # C3: tier-1 admission BEFORE composing. A structural PASS on a set tier 1
    # rejects is not a verification of anything; it is a physical experiment on
    # an inconsistent set, and must be labelled as such.
    tier1_admit "$W/tier1.log" "${SET[@]}"; ADM=$?
    if [ "$ADM" -eq 2 ]; then
        printf '%d,%d,%s,broken,,,,,,,,,,,,,TIER1_BROKEN\n' "$IDX" "$N" "${SET[*]}" >> "$CSV"
        FAILED=$((FAILED+1)); continue
    fi
    if [ "$ADM" -eq 1 ] && [ "$KNOWN_NEG" -eq 0 ]; then
        printf '%d,%d,%s,no,,,,,,,,,,,,,NOT_ADMITTED\n' "$IDX" "$N" "${SET[*]}" >> "$CSV"
        printf '      tier-1 REJECT -- not composed (use --known-negative to force)\n'
        continue
    fi
    ADM_LABEL=yes; [ "$ADM" -eq 1 ] && ADM_LABEL=known-negative
    C="$W/c"; rm -rf "$C"; mkdir -p "$C"/{upper,work,merged}
    M="$C/merged"
    printf '  [%3d/%3d] N=%-3d %s\n' "$IDX" "$TOTAL" "$N" "${MODS:0:64}"

    T0=$(now_ms); OK=1; LAYERS=(); LOWERS=()
    for m in "${SET[@]}"; do
        mp="$C/ro_${m}"; mkdir -p "$mp"
        if try_mount -o loop,ro "${MOD_DIR}/${m}.sqsh" "$mp"; then
            LOWERS=("$mp" "${LOWERS[@]}"); LAYERS+=("${m}=${mp}")
        else
            warn "mount failed: ${m}"; OK=0; break
        fi
    done
    if [ "$OK" -eq 1 ]; then
        LOWERDIR=$(IFS=:; echo "${LOWERS[*]}")
        try_mount -t overlay overlay \
            -o "lowerdir=${LOWERDIR},upperdir=${C}/upper,workdir=${C}/work" "$M" \
            || { warn "overlay failed at N=${N}"; OK=0; }
    fi
    if [ "$OK" -eq 1 ]; then mount_chroot_fs "$M" || OK=0; fi
    T1=$(now_ms)

    if [ "$OK" -eq 0 ]; then
        printf '%d,%d,%s,%s,,,,,,,,,,,,COMPOSE_FAIL\n' "$IDX" "$N" "${SET[*]}" "$ADM_LABEL" >> "$CSV"
        FAILED=$((FAILED+1)); unmount_all; continue
    fi

    # ---- reconcile, then regenerate what is derived -----------------------
    if ! python3 "${HERE}/scripts/reconcile.py" --merged "$M" \
             --groups-out "$C/alt.groups" "${LAYERS[@]}" > "$C/reconcile.log" 2>&1; then
        warn "reconciliation failed at N=${N}"
        printf '%d,%d,%s,%s,,,,,,,,,,,,RECONCILE_FAIL\n' "$IDX" "$N" "${SET[*]}" "$ADM_LABEL" >> "$CSV"
        FAILED=$((FAILED+1)); unmount_all; continue
    fi
    while read -r g; do
        [ -n "$g" ] || continue
        in_chroot "$M" update-alternatives --auto "$g" >/dev/null 2>&1 </dev/null || true
    done < "$C/alt.groups"
    in_chroot "$M" ldconfig >/dev/null 2>&1 </dev/null || true
    T2=$(now_ms)

    # ---- collect what the composed system actually reports ----------------
    in_chroot "$M" dpkg-query -W -f '${binary:Package}\n' 2>/dev/null </dev/null \
        | sort -u > "$C/actual.pkgs"
    in_chroot "$M" ldconfig -p 2>/dev/null </dev/null > "$C/actual.ld"
    in_chroot "$M" dpkg --audit 2>&1 </dev/null > "$C/audit.txt"

    ROW=$(python3 "${HERE}/scripts/verify_compose.py" \
              --scripts "${HERE}/scripts" --merged "$M" --work "$C" \
              --index "$IDX" --n "$N" --admitted "$ADM_LABEL" \
              --mount-ms "$((T1-T0))" --reconcile-ms "$((T2-T1))" \
              --total-ms "$((T2-T0))" "${LAYERS[@]}" 2>>"$W/verify.err")
    if [ -z "$ROW" ]; then
        warn "verification crashed at N=${N}; see $W/verify.err"
        printf '%d,%d,%s,%s,,,,,,,,,,,,VERIFY_CRASH\n' "$IDX" "$N" "${SET[*]}" "$ADM_LABEL" >> "$CSV"
        FAILED=$((FAILED+1)); unmount_all; continue
    fi
    printf '%s\n' "$ROW" >> "$CSV"
    # A known-negative that passes structurally is NOT a verification.
    case "$ROW" in *,PASS) ;; *) FAILED=$((FAILED+1)); warn "VERIFY FAILED: ${SET[*]}" ;; esac
    unmount_all
done < "$SAMPLES"

rm -rf "$W/c"

# ---- summary --------------------------------------------------------------
echo
echo "========================================================================"
echo " TIER-2 COMPOSE SWEEP: ${TOTAL} compositions, ${FAILED} failed"
echo "========================================================================"
python3 - "$CSV" <<'PY'
import csv, statistics, sys
rows = list(csv.DictReader(open(sys.argv[1], encoding='utf-8')))
byn = {}
for r in rows: byn.setdefault(int(r['n']), []).append(r)
print("\n    N   samples   pass   fail    mount ms   reconcile ms   total ms   packages")
for n in sorted(byn):
    rs = byn[n]
    ok = [r for r in rs if r['result'] == 'PASS']
    def med(k):
        v = [int(r[k]) for r in rs if r.get(k)]
        return int(statistics.median(v)) if v else 0
    pk = [int(r['pkg_actual']) for r in rs if r.get('pkg_actual')]
    print("  %3d   %7d %6d %6d %11d %14d %10d %10s"
          % (n, len(rs), len(ok), len(rs)-len(ok), med('mount_ms'),
             med('reconcile_ms'), med('total_ms'),
             "%d-%d" % (min(pk), max(pk)) if pk else "-"))
bad = [r for r in rows if r['result'] != 'PASS']
if bad:
    print("\n  failures:")
    for r in bad[:15]:
        print("    N=%-3s %-12s %s" % (r['n'], r['result'], r['modules'][:70]))
PY
echo
echo " csv: ${CSV}"
echo "========================================================================"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
