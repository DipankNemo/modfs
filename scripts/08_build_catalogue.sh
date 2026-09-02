#!/usr/bin/env bash
#
# Batch-build every module in specs/modules.yaml.
#
#   sudo ./scripts/08_build_catalogue.sh                 # build what is missing
#   sudo ./scripts/08_build_catalogue.sh --force         # rebuild everything
#   sudo ./scripts/08_build_catalogue.sh --only vim,emacs
#   sudo ./scripts/08_build_catalogue.sh --dry-run
#   sudo ./scripts/08_build_catalogue.sh --refresh-metadata
#
# --refresh-metadata re-runs stage 06 over base and every built module without
# rebuilding anything. Needed whenever the manifest schema grows -- the file
# sidecars for class-4 checking were added long after these artefacts existed.
#
# Idempotent: a module with both a .sqsh and a .json is skipped unless
# --force. Build failures do NOT stop the run -- a catalogue chosen
# adversarially is expected to contain packages that will not install, and
# the harness needs whatever did build.
#
# Exit: 0 all requested modules present, 1 some failed, 2 the runner broke.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${HERE}/config.sh"
source "${HERE}/scripts/lib.sh"

die2() { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 2; }
[ "$(id -u)" -eq 0 ] || die2 "must run as root (delta builds mount and chroot)"

FORCE=0; DRY=0; ONLY=""; REFRESH=0
while [ $# -gt 0 ]; do
    case "$1" in
        --force)   FORCE=1; shift ;;
        --dry-run) DRY=1; shift ;;
        --only)    [ $# -ge 2 ] || die2 "--only needs a value"; ONLY="$2"; shift 2 ;;
        --refresh-metadata) REFRESH=1; shift ;;
        *)         die2 "unknown option: $1" ;;
    esac
done

SPEC="${SPEC_DIR}/modules.yaml"
[ -f "$SPEC" ] || die2 "no catalogue at ${SPEC}"
[ -d "${MOD_DIR}/base.dir" ] || die2 "base not built -- run 01_build_base.sh first"

# ---- read the catalogue ---------------------------------------------------
PLAN="${BUILD_DIR}/catalogue.tsv"
mkdir -p "$BUILD_DIR"
python3 - "$SPEC" "$PLAN" "$ONLY" <<'PY' || die2 "cannot read ${SPEC}"
import sys, yaml
spec, out, only = sys.argv[1], sys.argv[2], sys.argv[3]
doc = yaml.safe_load(open(spec, encoding='utf-8')) or {}
defaults = doc.get('defaults') or {}
wanted = set(x.strip() for x in only.split(',') if x.strip()) if only else None
rows, seen = [], set()
for m in (doc.get('modules') or []):
    name = m.get('name')
    pkgs = m.get('packages') or []
    if not name or not pkgs:
        sys.stderr.write("skipping malformed entry: %r\n" % (m,)); continue
    if name in seen:
        sys.stderr.write("duplicate module name: %s\n" % name); sys.exit(2)
    seen.add(name)
    if wanted is not None and name not in wanted: continue
    rows.append((name, str(m.get('version') or defaults.get('version') or '1.0'),
                 ' '.join(str(p) for p in pkgs), str(m.get('snapshot') or '')))
if wanted:
    missing = wanted - {r[0] for r in rows}
    if missing:
        sys.stderr.write("not in catalogue: %s\n" % ', '.join(sorted(missing)))
        sys.exit(2)
with open(out, 'w', encoding='utf-8') as f:
    for r in rows: f.write('\t'.join(r) + '\n')
print("  catalogue: %d module(s)" % len(rows))
PY

BUILT=(); SKIPPED=(); FAILED=(); OVERSIZE=()

# ---- metadata-only refresh ------------------------------------------------
if [ "$REFRESH" -eq 1 ]; then
    log "refreshing metadata for base + every built module"
    "${HERE}/scripts/06_extract_metadata.sh" base --parent none --version 1.0 \
        > "${LOG_DIR}/refresh-base.log" 2>&1 </dev/null \
        || die2 "metadata refresh failed for base"
    RC=0
    while IFS=$'\t' read -r name version pkgs snapshot; do
        [ -f "${MOD_DIR}/${name}.json" ] || continue
        # A module built from another snapshot must have that snapshot
        # recorded, so the override has to be re-applied on refresh too --
        # otherwise the positive control would silently record the wrong one.
        if MODFS_SNAPSHOT_ID="${snapshot}" \
           "${HERE}/scripts/06_extract_metadata.sh" "$name" --version "$version" \
               > "${LOG_DIR}/refresh-${name}.log" 2>&1 </dev/null; then
            printf '  %-18s refreshed%s\n' "$name" \
                "$([ -n "$snapshot" ] && echo "  (snapshot ${snapshot})" || true)"
        else
            warn "${name}: metadata refresh FAILED, see ${LOG_DIR}/refresh-${name}.log"
            RC=1
        fi
    done < "$PLAN"
    exit "$RC"
fi

while IFS=$'\t' read -r name version pkgs snapshot; do
    sqsh="${MOD_DIR}/${name}.sqsh"
    json="${MOD_DIR}/${name}.json"
    if [ "$FORCE" -eq 0 ] && [ -f "$sqsh" ] && [ -f "$json" ]; then
        SKIPPED+=("$name"); continue
    fi
    if [ "$DRY" -eq 1 ]; then
        printf '  would build %-16s %s\n' "$name" "$pkgs"; continue
    fi
    if [ -n "$snapshot" ]; then
        log "building ${name}: ${pkgs}   [snapshot ${snapshot}]"
    else
        log "building ${name}: ${pkgs}"
    fi
    # MODFS_SNAPSHOT_ID is empty for every normal module, so config.sh keeps
    # its default; only a declared control overrides it.
    # shellcheck disable=SC2086
    if MODFS_SNAPSHOT_ID="${snapshot}" \
       "${HERE}/scripts/02_build_delta.sh" --version "$version" "$name" $pkgs \
           > "${LOG_DIR}/catalogue-${name}.log" 2>&1 </dev/null; then
        BUILT+=("$name")
    else
        FAILED+=("$name")
        warn "${name} FAILED -- see ${LOG_DIR}/catalogue-${name}.log"
        tail -3 "${LOG_DIR}/catalogue-${name}.log" | sed 's/^/           /'
    fi
done < "$PLAN"

[ "$DRY" -eq 1 ] && exit 0

# ---- report ---------------------------------------------------------------
echo
echo "========================================================================"
printf " %-16s %10s  %s\n" "MODULE" "SIZE" "STATUS"
echo "========================================================================"
while IFS=$'\t' read -r name version pkgs snapshot; do
    sqsh="${MOD_DIR}/${name}.sqsh"
    if [ ! -f "$sqsh" ]; then
        printf " %-16s %10s  %s\n" "$name" "-" "FAILED"; continue
    fi
    bytes=$(stat -c %s "$sqsh"); mb=$(( bytes / 1024 / 1024 ))
    flag=""
    if [ "$mb" -gt "$MODULE_MAX_MB" ]; then
        flag=" OVER ${MODULE_MAX_MB}MB"; OVERSIZE+=("$name")
    fi
    # Integer MB rounds 11 of 27 real modules to "0M", which hides the whole
    # point of a delta. Print the actual size.
    printf " %-16s %10s  %s%s\n" "$name" "$(human "$bytes")" "ok" "$flag"
done < "$PLAN"
echo "========================================================================"
echo " built ${#BUILT[@]}, skipped ${#SKIPPED[@]}, failed ${#FAILED[@]}, oversize ${#OVERSIZE[@]}"
[ ${#FAILED[@]}   -gt 0 ] && echo " failed  : ${FAILED[*]}"
[ ${#OVERSIZE[@]} -gt 0 ] && echo " oversize: ${OVERSIZE[*]}  (reported, not rejected)"
echo "========================================================================"
[ ${#FAILED[@]} -eq 0 ] || exit 1
exit 0
