#!/usr/bin/env bash
#
# Run 05_check.sh over every pair and triple of built modules and tabulate the
# verdicts by conflict class into a CSV.
#
#   ./scripts/09_run_combinations.sh                     # pairs and triples
#   ./scripts/09_run_combinations.sh --max-n 2           # pairs only (fast)
#   ./scripts/09_run_combinations.sh --jobs 8
#   ./scripts/09_run_combinations.sh --out /tmp/x.csv
#
# Needs no root: it reads only module.json manifests, which is the whole point
# of stage 06. ARCHITECTURE section 6 tier 1 -- ~1 s per combination, so
# thousands are feasible where composition (tier 2) and boot (tier 3) are not.
#
# 27 modules is 351 pairs and 2 925 triples. Sequential that is roughly an
# hour; --jobs 8 brings it to minutes. Each 05_check.sh run is independent,
# so parallelism is safe.
#
# Exit: 0 the sweep completed, 2 the runner broke. A REJECT verdict is DATA,
# not a failure of this script, so it never exits 1.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${HERE}/config.sh"
source "${HERE}/scripts/lib.sh"

die2() { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 2; }
SELF="${HERE}/scripts/09_run_combinations.sh"

# ---- worker mode: one combination -----------------------------------------
# Invoked by xargs. Writes one CSV line to its own file so parallel writers
# never interleave.
if [ "${1:-}" = "--worker" ]; then
    OUTDIR="$2"; KEEP="$3"; shift 3
    read -r -a MODS <<< "$1"
    TAG=$(IFS=-; echo "${MODS[*]}")
    OUT=$("${HERE}/scripts/05_check.sh" "${MODS[@]}" 2>&1); RC=$?

    ERR=$(printf '%s\n' "$OUT" | sed -n 's/^ VERDICT: \([0-9][0-9]*\) error.*/\1/p' | head -1)
    WARN=$(printf '%s\n' "$OUT" | sed -n 's/^ VERDICT: [0-9][0-9]* error(s), \([0-9][0-9]*\) warning.*/\1/p' | head -1)
    [ -n "$ERR" ]  || ERR=-1
    [ -n "$WARN" ] || WARN=-1

    # Conflict classes, keyed to the taxonomy in ARCHITECTURE section 4.
    BENIGN=$(printf '%s\n' "$OUT" | grep -c 'SAME (benign overlap)' || true)   # class 1
    SKEW=$(printf   '%s\n' "$OUT" | grep -c 'VERSION SKEW' || true)            # class 2
    DECL=$(printf   '%s\n' "$OUT" | grep -cE '^ +[^ ]+ (CONFLICTS|BREAKS) ' || true)  # class 3
    DRIFT=$(printf  '%s\n' "$OUT" | grep -c 'base package(s) upgraded' || true)       # class 6
    NOCOMP=$(printf '%s\n' "$OUT" | grep -c 'NOT COMPOSABLE' || true)          # PRE
    # Anchor on the finding lines' indent: the section HEADER also contains
    # the words "IDENTITY COLLISION", and matching it counts every run.
    IDENT=$(printf  '%s\n' "$OUT" | grep -cE '^    (IDENTITY COLLISION|UNRESOLVED IDENTITY)' || true)  # class 7
    FILES=$(printf  '%s\n' "$OUT" | grep -c '^    FILE COLLISION ' || true)   # class 4
    # Suppressed collisions are not errors, but they are the evidence that
    # class 4 actually ran against real data rather than finding nothing.
    FSUP=$(printf   '%s\n' "$OUT" | sed -n 's/^ *\([0-9][0-9]*\) collision(s) SUPPRESSED.*/\1/p' | head -1)
    [ -n "$FSUP" ] || FSUP=0

    case "$RC" in
        0) [ "$WARN" -gt 0 ] && VERDICT=ACCEPT_WARN || VERDICT=ACCEPT ;;
        1) VERDICT=REJECT ;;
        *) VERDICT=BROKEN ;;
    esac

    printf '%s,%d,%s,%s,%d,%s,%s,%d,%d,%d,%d,%d,%d,%d,%d\n' \
        "$TAG" "${#MODS[@]}" "${MODS[*]}" "$VERDICT" "$RC" \
        "$ERR" "$WARN" "$BENIGN" "$SKEW" "$DECL" "$FILES" "$FSUP" "$IDENT" "$DRIFT" "$NOCOMP" \
        > "${OUTDIR}/${TAG}.csv"

    [ "$KEEP" = "1" ] || rm -f "${LOG_DIR}/check-${TAG}.txt"
    exit 0
fi

# ---- main -----------------------------------------------------------------
MAXN=3; JOBS=1; KEEP=0; CSV="${LOG_DIR}/combinations.csv"
while [ $# -gt 0 ]; do
    case "$1" in
        --max-n) [ $# -ge 2 ] || die2 "--max-n needs a value"; MAXN="$2"; shift 2 ;;
        --jobs)  [ $# -ge 2 ] || die2 "--jobs needs a value";  JOBS="$2";  shift 2 ;;
        --out)   [ $# -ge 2 ] || die2 "--out needs a value";   CSV="$2";   shift 2 ;;
        --keep-reports) KEEP=1; shift ;;
        *) die2 "unknown option: $1" ;;
    esac
done
case "$MAXN" in 2|3) ;; *) die2 "--max-n must be 2 or 3" ;; esac
require_uint "$JOBS" 1 256 "--jobs"
[ -f "${MOD_DIR}/base.json" ] || die2 "no ${MOD_DIR}/base.json -- build base first"

# Modules are the catalogue entries that actually built. A module that failed
# to install is simply absent; the sweep uses what exists.
mapfile -t MODULES < <(
    python3 - "${SPEC_DIR}/modules.yaml" "$MOD_DIR" <<'PY'
import os, sys, yaml
spec, mod_dir = sys.argv[1], sys.argv[2]
doc = yaml.safe_load(open(spec, encoding='utf-8')) or {}
for m in (doc.get('modules') or []):
    n = m.get('name')
    if n and n != 'base' and os.path.exists(os.path.join(mod_dir, n + '.json')):
        print(n)
PY
)
[ "${#MODULES[@]}" -ge 2 ] || die2 "fewer than 2 built modules found -- run 08_build_catalogue.sh"
# C1: identifiers reach paths and mount options; validate at the boundary.
for m in "${MODULES[@]}"; do valid_ident "$m" || die2 "invalid module name in catalogue: '$m'"; done

W="${BUILD_DIR}/combinations"
rm -rf "$W"; mkdir -p "$W/lines"
COMBOS="$W/combos.txt"
python3 - "$MAXN" "$COMBOS" "${MODULES[@]}" <<'PY'
import itertools, sys
maxn, out = int(sys.argv[1]), sys.argv[2]
mods = sorted(sys.argv[3:])
with open(out, 'w', encoding='utf-8') as f:
    for n in range(2, maxn + 1):
        for combo in itertools.combinations(mods, n):
            f.write(' '.join(combo) + '\n')
PY
TOTAL=$(wc -l < "$COMBOS")
log "${#MODULES[@]} modules -> ${TOTAL} combinations (n=2..${MAXN}), ${JOBS} job(s)"

START=$(date +%s)
xargs -a "$COMBOS" -P "$JOBS" -I COMBO "$SELF" --worker "$W/lines" "$KEEP" COMBO
ELAPSED=$(( $(date +%s) - START ))

mkdir -p "$(dirname "$CSV")" 2>/dev/null || true
{
    echo "combination,n,modules,verdict,exit,errors,warnings,benign_overlap,version_skew,declared_conflict,file_collision,file_collision_suppressed,identity_collision,base_drift,not_composable"
    cat "$W"/lines/*.csv | sort
} > "$CSV" || die2 "cannot write ${CSV}"

DONE=$(( $(wc -l < "$CSV") - 1 ))
[ "$DONE" -eq "$TOTAL" ] || warn "expected ${TOTAL} rows, wrote ${DONE}"

# ---- summary --------------------------------------------------------------
echo
echo "========================================================================"
echo " COMBINATION SWEEP: ${#MODULES[@]} modules, ${DONE} combinations, ${ELAPSED}s"
echo "========================================================================"
python3 - "$CSV" <<'PY'
import csv, sys
from collections import Counter
rows = list(csv.DictReader(open(sys.argv[1], encoding='utf-8')))
by_n = Counter((r['n'], r['verdict']) for r in rows)
print("\n  verdict by size")
for n in sorted({r['n'] for r in rows}):
    tot = sum(v for (k, _), v in by_n.items() if k == n)
    parts = ["%s=%d" % (v, c) for (k, v), c in sorted(by_n.items()) if k == n]
    print("    n=%s  %-5d  %s" % (n, tot, '  '.join(parts)))
print("\n  conflict classes (combinations exhibiting each)")
for label, col in (("1 benign overlap", 'benign_overlap'),
                   ("2 version skew", 'version_skew'),
                   ("3 declared conflict", 'declared_conflict'),
                   ("4 file collision", 'file_collision'),
                   ("4 collisions suppressed", 'file_collision_suppressed'),
                   ("7 identity collision", 'identity_collision'),
                   ("6 implicit base upgrade", 'base_drift'),
                   ("0 not composable", 'not_composable')):
    hit = sum(1 for r in rows if int(r[col]) > 0)
    print("    %-26s %5d" % (label, hit))
broken = [r['combination'] for r in rows if r['verdict'] == 'BROKEN']
if broken:
    print("\n  CHECKER BROKE on %d combination(s): %s" % (len(broken), ', '.join(broken[:5])))
rej = [r for r in rows if r['verdict'] == 'REJECT']
if rej:
    print("\n  rejected pairs (first 15)")
    for r in sorted(rej, key=lambda r: r['n'])[:15]:
        why = []
        if int(r['version_skew']): why.append('skew')
        if int(r['declared_conflict']): why.append('declared')
        if int(r['file_collision']): why.append('file-collision')
        if int(r['identity_collision']): why.append('identity')
        if int(r['not_composable']): why.append('not-composable')
        print("    %-34s %s" % (r['modules'], ','.join(why) or '?'))
PY
echo
echo " csv: ${CSV}"
echo "========================================================================"
exit 0
