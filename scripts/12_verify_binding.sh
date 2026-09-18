#!/usr/bin/env bash
#
# Verify that every manifest still describes the artefact it names.
#
#   sudo ./scripts/12_verify_binding.sh              # whole catalogue
#   sudo ./scripts/12_verify_binding.sh curl webserver
#
# WHY THIS STAGE EXISTS. Every tier-1 verdict is computed from <name>.json, and
# until 2026-09-18 nothing checked that document against the .sqsh it describes.
# 00's assumption checks, 05's classes and 09's sweep all read the manifest;
# 06's output IS the manifest; so no stage ever looked at the artefact
# independently. A module could understate its accounts, its file owners or its
# packages and be believed, and the cheapest version of that was not forgery but
# OMISSION -- deleting two keys turned a class-7 REJECT into a clean ACCEPT.
#
# THREE LAYERS, PLACED BY WHAT THEY COST. Measured on this catalogue:
#
#   tier 1, every check, ~0 ms
#       05_check.sh recomputes binding.fields_sha256 from the manifest it just
#       loaded. Catches an edited or removed field. Needs no root and does not
#       touch the artefact.
#
#   before composing, ~sha256 of the artefacts
#       lib.sh's verify_bundle, already called by stages 10 and 11, adds the
#       same digest check plus the class-4 sidecar's.
#
#   here, once per artefact, mount + walk
#       RE-DERIVES the manifest from the mounted .sqsh and compares. This is the
#       only layer that can catch a manifest whose digest was recomputed to
#       match forged content, because it is the only one that reads the artefact.
#
# The artefact is immutable and the check is not, so the expensive work belongs
# on the side that does not repeat. Re-deriving inside tier 1 would cost a mount
# (5-18 ms) and an lstat walk (2-114 ms) per module and would need root, against
# a whole-check budget of 79 ms at N=2.
#
# WHAT IT DOES NOT PROVE. It reuses 06_extract_metadata.sh --check rather than
# reimplementing the derivation, deliberately: a second implementation would
# drift, and the question here is "is this manifest still what this artefact
# produces", not "is the extractor correct". A logic error in 06 is invisible to
# this stage and always will be.
#
# Exit: 0 complete requested coverage, 1 missing/mismatched bundle, 2 invalid request/runner.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${HERE}/config.sh"
source "${HERE}/scripts/lib.sh"

die2() { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 2; }
[ "$(id -u)" -eq 0 ] || die2 "must run as root (it mounts each artefact read-only)"

SPEC="${SPEC_DIR}/modules.yaml"
[ -f "$SPEC" ] || die2 "no catalogue at ${SPEC}"

WANT=("$@")
for m in "${WANT[@]}"; do valid_ident "$m" || die2 "invalid module name: '$m'"; done

# version and snapshot must be re-applied exactly as 08 --refresh-metadata does,
# or the re-derivation would differ from the manifest for a reason that is not a
# defect -- the positive control is built from another snapshot and records it.
PLAN="${BUILD_DIR}/binding.tsv"
mkdir -p "$BUILD_DIR"
if ! python3 - "$SPEC" "${WANT[@]}" > "$PLAN" <<'PY'
import sys, yaml
spec = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))
names = [m['name'] for m in spec['modules']]
if not names or len(set(names)) != len(names) or 'base' in names:
    raise ValueError('empty or duplicate catalogue')
unknown = set(sys.argv[2:]) - set(names) - {'base'}
if unknown:
    raise ValueError('unknown requested modules: ' + ', '.join(sorted(unknown)))
dflt = spec.get('defaults') or {}
for m in spec['modules']:
    print("%s\t%s\t%s" % (m['name'],
                          m.get('version') or dflt.get('version') or '1.0',
                          m.get('snapshot') or '-'))
PY
then
    die2 "cannot construct binding plan"
fi

want_this() {            # want_this <name>
    [ "${#WANT[@]}" -eq 0 ] && return 0
    local w; for w in "${WANT[@]}"; do [ "$w" = "$1" ] && return 0; done
    return 1
}

if [ "${#WANT[@]}" -eq 0 ]; then
    log "re-deriving complete catalogue (base and every module)"
else
    log "re-deriving requested subset: ${WANT[*]}"
fi
OK=0; BAD=0; ABSENT=0
FAILED=()

check_one() {            # check_one <name> <extra args...>
    local name="$1"; shift
    local out
    if out=$("${HERE}/scripts/06_extract_metadata.sh" "$name" "$@" --check 2>&1 </dev/null); then
        printf '  %-20s %s\n' "$name" "matches its artefact"
        OK=$((OK+1))
    else
        printf '  %-20s \033[1;31mDOES NOT MATCH\033[0m\n' "$name"
        printf '%s\n' "$out" | sed -n 's/^  MISMATCH /      /p'
        FAILED+=("$name"); BAD=$((BAD+1))
    fi
}

if want_this base; then
    if [ -f "${MOD_DIR}/base.json" ]; then
        check_one base --parent none --version 1.0
    else
        printf '  %-20s no manifest\n' base; ABSENT=$((ABSENT+1))
    fi
fi

while IFS=$'\t' read -r name version snapshot; do
    want_this "$name" || continue
    [ "$snapshot" = "-" ] && snapshot=""
    if [ ! -f "${MOD_DIR}/${name}.json" ]; then
        printf '  %-20s no manifest\n' "$name"; ABSENT=$((ABSENT+1)); continue
    fi
    MODFS_SNAPSHOT_ID="$snapshot" check_one "$name" --version "$version"
done < "$PLAN"

# Bytes, not only content: verify_bundle also re-hashes each .sqsh against the
# digest its manifest records, which is the half this stage does not repeat.
BUNDLE_OUT=""
BUNDLE_RC=0
BUNDLE_SET=()
while IFS=$'\t' read -r name version snapshot; do
    want_this "$name" || continue
    [ -f "${MOD_DIR}/${name}.json" ] && BUNDLE_SET+=("$name")
done < "$PLAN"
want_this base && [ -f "${MOD_DIR}/base.json" ] && BUNDLE_SET=(base "${BUNDLE_SET[@]}")
if [ "${#BUNDLE_SET[@]}" -gt 0 ]; then
    BUNDLE_OUT=$(verify_bundle "${BUNDLE_SET[@]}" 2>&1) || BUNDLE_RC=1
fi

echo
echo "========================================================================"
printf ' BINDING: %d matched, %d MISMATCHED, %d without a manifest\n' \
       "$OK" "$BAD" "$ABSENT"
if [ "$BUNDLE_RC" -eq 0 ]; then
    printf ' BYTES  : %d artefact(s) match the digest their manifest records\n' \
           "${#BUNDLE_SET[@]}"
else
    printf ' BYTES  : \033[1;31mFAILED\033[0m\n'
    printf '%s\n' "$BUNDLE_OUT"
fi
if [ "$BAD" -gt 0 ]; then
    echo " mismatched: ${FAILED[*]}"
    echo " REJECT -- at least one manifest does not describe its artefact"
fi
echo "========================================================================"
if [ "$ABSENT" -gt 0 ] || [ "$OK" -eq 0 ]; then
    echo " REJECT -- requested coverage is incomplete or empty"
fi
[ "$BAD" -eq 0 ] && [ "$BUNDLE_RC" -eq 0 ] && \
    [ "$ABSENT" -eq 0 ] && [ "$OK" -gt 0 ] || exit 1
exit 0
