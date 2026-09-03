#!/usr/bin/env bash
#
# Build a DELTA module: install packages on top of an existing parent module
# and keep ONLY the difference.
#
#   sudo ./scripts/02_build_delta.sh [--version V] <name> <pkg> [pkg...]
#   sudo ./scripts/02_build_delta.sh webserver nginx
#
# How it works:
#   1. mount parent rootfs read-only as lowerdir
#   2. overlay it with an empty upperdir -> merged view
#   3. chroot into MERGED and apt-get install
#      (apt sees the parent as already installed, so it writes only new files)
#   4. squash the UPPERDIR alone -> the delta
#
# Output: $MOD_DIR/<name>.sqsh       delta artefact (small)
#         $MOD_DIR/<name>.json       metadata manifest, written by stage 06
#         $MOD_DIR/<name>.upper/     raw upperdir, kept for inspection
#
# Also builds a MONOLITHIC comparison build when --compare is passed, so the
# storage difference can be measured directly.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${HERE}/config.sh"
source "${HERE}/scripts/lib.sh"
need_root

PARENT="base"
COMPARE=0
# Forwarded to the metadata extractor. ARCHITECTURE section 5: modules need
# explicit version numbers, not implicit (snapshot, parent) identity.
MOD_VERSION=""
ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --parent) [ $# -ge 2 ] || die "--parent needs a value"
                  PARENT="$2"; shift 2 ;;
        --version) [ $# -ge 2 ] || die "--version needs a value"
                  MOD_VERSION="$2"; shift 2 ;;
        --compare) COMPARE=1; shift ;;
        *) ARGS+=("$1"); shift ;;
    esac
done

[ ${#ARGS[@]} -ge 2 ] || die "usage: $0 [--parent NAME] [--version V] [--compare] <name> <pkg> [pkg...]"
NAME="${ARGS[0]}"
PKGS=("${ARGS[@]:1}")
# C1: identifiers reach paths and mount options; validate at the boundary.
require_ident "$NAME" "module name"
require_ident "$PARENT" "parent module name"

PARENT_DIR="${MOD_DIR}/${PARENT}.dir"
[ -d "$PARENT_DIR" ] || die "parent rootfs missing: ${PARENT_DIR} (build base first)"

UPPER="${MOD_DIR}/${NAME}.upper"
WORK="${BUILD_DIR}/${NAME}.work"
MERGED="${BUILD_DIR}/${NAME}.merged"
SQSH="${MOD_DIR}/${NAME}.sqsh"

log "delta module '${NAME}' on parent '${PARENT}'"
log "  packages: ${PKGS[*]}"

rm -rf "$UPPER" "$WORK" "$MERGED"
mkdir -p "$UPPER" "$WORK" "$MERGED" "$LOG_DIR"

# ---- overlay the parent ---------------------------------------------------
do_mount -t overlay overlay \
    -o "lowerdir=${PARENT_DIR},upperdir=${UPPER},workdir=${WORK}" \
    "$MERGED"
log "overlay mounted: ${PARENT} (ro) + empty upper"

write_sources_list "$MERGED"
write_chroot_policy "$MERGED"
mount_chroot_fs "$MERGED"

log "apt update"
in_chroot "$MERGED" apt-get update -qq || die "apt update failed"

# Record what was installed BEFORE, so we can report exactly what this
# delta added rather than guessing.
in_chroot "$MERGED" dpkg-query -f '${binary:Package}\n' -W \
    2>/dev/null | sort > "${BUILD_DIR}/${NAME}.before"

log "installing: ${PKGS[*]}"
in_chroot "$MERGED" apt-get install -y -qq --no-install-recommends \
    "${PKGS[@]}" 2>&1 | tail -5 || die "install failed"

in_chroot "$MERGED" dpkg-query -f '${binary:Package}\n' -W \
    2>/dev/null | sort > "${BUILD_DIR}/${NAME}.after"

ADDED=$(comm -13 "${BUILD_DIR}/${NAME}.before" "${BUILD_DIR}/${NAME}.after" | wc -l)
log "delta adds ${ADDED} packages"

log "cleaning caches"
in_chroot "$MERGED" apt-get clean
rm -rf "${MERGED}/var/lib/apt/lists"/* "${MERGED}/var/cache/apt/archives"/*.deb

remove_chroot_policy "$MERGED"
unmount_all
log "overlay unmounted; upperdir now holds the delta"

# ---- squash the UPPERDIR ONLY --------------------------------------------
# -no-strip is not needed; mksquashfs preserves char devices (whiteouts)
# and trusted.* xattrs (opaque markers). Verified in step 1.
log "squashing upperdir -> ${SQSH}"
rm -f "$SQSH"
# shellcheck disable=SC2086
mksquashfs "$UPPER" "$SQSH" \
    -comp "$SQUASH_COMP" -Xcompression-level "$SQUASH_LEVEL" \
    -mkfs-time "$SOURCE_EPOCH" -all-time "$SOURCE_EPOCH" \
    -xattrs-exclude "$SQUASH_XATTR_EXCLUDE" \
    -noappend -no-progress -e $SQUASH_EXCLUDES \
    > "${LOG_DIR}/${NAME}-mksquashfs.log" 2>&1 || die "mksquashfs failed"

UP_SZ=$(du -sb "$UPPER" | cut -f1)
SQ_SZ=$(stat -c %s "$SQSH")
PARENT_SQ="${MOD_DIR}/${PARENT}.sqsh"
P_SZ=$(stat -c %s "$PARENT_SQ" 2>/dev/null || echo 0)

log "DELTA DONE"
log "  upperdir raw : $(human "$UP_SZ")"
log "  delta .sqsh  : $(human "$SQ_SZ")"
log "  parent .sqsh : $(human "$P_SZ")"

# ---- metadata manifest ----------------------------------------------------
# Written next to the artefact so 05_check.sh never has to open this upperdir
# again -- that is what makes tier-1 checking cheap enough to run over every
# module pair. Must come after mksquashfs: it records .sqsh size and sha256.
# Any hand-written module-level requires/conflicts/provides already in the
# manifest are carried over, not overwritten.
log "extracting metadata -> ${MOD_DIR}/${NAME}.json"
META_ARGS=("$NAME" --parent "$PARENT" --requested "${PKGS[*]}")
[ -n "$MOD_VERSION" ] && META_ARGS+=(--version "$MOD_VERSION")
"${HERE}/scripts/06_extract_metadata.sh" "${META_ARGS[@]}" \
    || die "metadata extraction failed"

# ---- optional: monolithic build for comparison ---------------------------
if [ "$COMPARE" -eq 1 ]; then
    MONO="${MOD_DIR}/${NAME}-monolithic.dir"
    MONO_SQSH="${MOD_DIR}/${NAME}-monolithic.sqsh"
    log ""
    log "=== COMPARISON: building '${NAME}' the naive way (own debootstrap) ==="
    rm -rf "$MONO"; mkdir -p "$MONO"
    debootstrap --variant=minbase --arch="${ARCH}" \
        --components="$(echo "$COMPONENTS" | tr ' ' ',')" \
        "${SUITE}" "${MONO}" "${SNAPSHOT_BASE}" \
        > "${LOG_DIR}/${NAME}-mono-debootstrap.log" 2>&1 \
        || die "comparison debootstrap failed"
    write_sources_list "$MONO"
    write_chroot_policy "$MONO"
    mount_chroot_fs "$MONO"
    in_chroot "$MONO" apt-get update -qq
    in_chroot "$MONO" apt-get install -y -qq --no-install-recommends \
        systemd systemd-sysv sudo ca-certificates "${PKGS[@]}" 2>&1 | tail -3
    in_chroot "$MONO" apt-get clean
    rm -rf "${MONO}/var/lib/apt/lists"/* "${MONO}/var/cache/apt/archives"/*.deb
    remove_chroot_policy "$MONO"
    unmount_all
    # shellcheck disable=SC2086
    mksquashfs "$MONO" "$MONO_SQSH" -comp "$SQUASH_COMP" \
        -Xcompression-level "$SQUASH_LEVEL" \
        -mkfs-time "$SOURCE_EPOCH" -all-time "$SOURCE_EPOCH" \
        -xattrs-exclude "$SQUASH_XATTR_EXCLUDE" \
        -noappend -no-progress \
        -e $SQUASH_EXCLUDES > /dev/null 2>&1
    M_SZ=$(stat -c %s "$MONO_SQSH")
    log ""
    log "  ===== STORAGE COMPARISON for '${NAME}' ====="
    log "  monolithic module : $(human "$M_SZ")"
    log "  delta module      : $(human "$SQ_SZ")"
    log "  saving            : $(( 100 - (SQ_SZ * 100 / M_SZ) ))%"
fi
