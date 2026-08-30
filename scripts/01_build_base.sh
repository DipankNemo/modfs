#!/usr/bin/env bash
#
# Build the BASE module: a minimal Ubuntu rootfs from the pinned snapshot.
# Every other module is a delta on top of this one.
#
#   sudo ./scripts/01_build_base.sh [--version V] [extra packages...]
#
# Output: $MOD_DIR/base.sqsh   (the artefact)
#         $MOD_DIR/base.json   (metadata manifest, written by stage 06)
#         $MOD_DIR/base.dir/   (kept, needed as lowerdir for delta builds)

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${HERE}/config.sh"
source "${HERE}/scripts/lib.sh"
need_root

NAME="base"

# --version is forwarded to the metadata extractor. ARCHITECTURE section 5:
# modules need explicit version numbers rather than implicit (snapshot,
# parent) identity, otherwise the module-level dependency layer has nothing
# to constrain. Omitting it is allowed but warns.
MOD_VERSION=""
EXTRA_PKGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --version)
            [ $# -ge 2 ] || die "--version needs a value"
            MOD_VERSION="$2"; shift 2 ;;
        *)
            EXTRA_PKGS+=("$1"); shift ;;
    esac
done
[ ${#EXTRA_PKGS[@]} -eq 0 ] && EXTRA_PKGS=(systemd systemd-sysv sudo ca-certificates)

# Base has no parent, so every installed package is its own contribution.
extract_metadata() {
    local args=("$NAME" --parent none --requested "${EXTRA_PKGS[*]}")
    [ -n "$MOD_VERSION" ] && args+=(--version "$MOD_VERSION")
    "${HERE}/scripts/06_extract_metadata.sh" "${args[@]}" \
        || die "metadata extraction failed"
}

ROOTFS="${MOD_DIR}/${NAME}.dir"
SQSH="${MOD_DIR}/${NAME}.sqsh"
STAMP="${ROOTFS}/.modfs-complete"

mkdir -p "$MOD_DIR" "$BUILD_DIR" "$LOG_DIR"

# Idempotency via a stamp file written LAST. Checking for /bin is unreliable:
# debootstrap creates it in the first seconds, so an interrupted run looks
# complete. That was the source of the half-built chroot problem.
if [ -f "$STAMP" ] && [ -f "$SQSH" ]; then
    log "base already built (remove $ROOTFS to rebuild)"
    # A base built before stage 06 existed has no manifest. Generate one
    # rather than forcing a 15-minute rebuild just to get it.
    if [ ! -f "${MOD_DIR}/${NAME}.json" ]; then
        log "no manifest yet -- extracting metadata"
        extract_metadata
    fi
    exit 0
fi

log "removing any partial build"
rm -rf "$ROOTFS"; mkdir -p "$ROOTFS"

log "debootstrap ${SUITE}/${ARCH} from snapshot ${SNAPSHOT_ID}"
log "  (this takes 5-15 min, downloads ~150 MB)"
debootstrap \
    --variant=minbase \
    --arch="${ARCH}" \
    --components="$(echo "$COMPONENTS" | tr ' ' ',')" \
    "${SUITE}" "${ROOTFS}" "${SNAPSHOT_BASE}" \
    2>&1 | tee "${LOG_DIR}/base-debootstrap.log" | grep -E '^I:' | tail -5 \
    || die "debootstrap failed, see ${LOG_DIR}/base-debootstrap.log"

log "configuring chroot"
write_sources_list "$ROOTFS"
write_chroot_policy "$ROOTFS"
mount_chroot_fs "$ROOTFS"
echo "modfs-node" > "${ROOTFS}/etc/hostname"

log "apt update"
in_chroot "$ROOTFS" apt-get update -qq || die "apt update failed"

# debootstrap installs only from the plain '<suite>' pocket, but every delta
# build sees <suite> + -updates + -security. That mismatch let deltas pull
# newer versions of packages base already had (implicit base upgrade).
# Bringing base up to the same archive view removes the whole class.
log "aligning base with snapshot archive view (release + updates + security)"
in_chroot "$ROOTFS" dpkg-query -f '${binary:Package} ${Version}\n' -W \
    2>/dev/null | sort > "${BUILD_DIR}/base-preupgrade.pkgs"
in_chroot "$ROOTFS" apt-get full-upgrade -y -qq 2>&1 | tail -3 \
    || die "base full-upgrade failed"
in_chroot "$ROOTFS" dpkg-query -f '${binary:Package} ${Version}\n' -W \
    2>/dev/null | sort > "${BUILD_DIR}/base-postupgrade.pkgs"
UPG=$(comm -13 "${BUILD_DIR}/base-preupgrade.pkgs" \
                "${BUILD_DIR}/base-postupgrade.pkgs" | wc -l)
log "  ${UPG} package(s) moved to -updates level"
[ "$UPG" -gt 0 ] && comm -13 "${BUILD_DIR}/base-preupgrade.pkgs" \
    "${BUILD_DIR}/base-postupgrade.pkgs" | head -20 | sed 's/^/           /'

log "installing base packages: ${EXTRA_PKGS[*]}"
in_chroot "$ROOTFS" apt-get install -y -qq --no-install-recommends \
    "${EXTRA_PKGS[@]}" 2>&1 | tail -5 || die "package install failed"

log "cleaning apt caches"
in_chroot "$ROOTFS" apt-get clean
rm -rf "${ROOTFS}/var/lib/apt/lists"/* "${ROOTFS}/var/cache/apt/archives"/*.deb

remove_chroot_policy "$ROOTFS"
unmount_all

PKG_COUNT=$(chroot "$ROOTFS" dpkg-query -f '${binary:Package}\n' -W 2>/dev/null | wc -l)
log "base contains ${PKG_COUNT} packages"

log "squashing -> ${SQSH}"
rm -f "$SQSH"
# shellcheck disable=SC2086
mksquashfs "$ROOTFS" "$SQSH" \
    -comp "$SQUASH_COMP" -Xcompression-level "$SQUASH_LEVEL" \
    -noappend -no-progress -e $SQUASH_EXCLUDES \
    > "${LOG_DIR}/base-mksquashfs.log" 2>&1 || die "mksquashfs failed"

touch "$STAMP"

# ---- metadata manifest ----------------------------------------------------
# Written next to the artefact so 05_check.sh never has to open this rootfs
# again. Must come after mksquashfs: it records the .sqsh size and sha256.
log "extracting metadata -> ${MOD_DIR}/${NAME}.json"
extract_metadata

DIR_SZ=$(du -sb "$ROOTFS" | cut -f1)
SQ_SZ=$(stat -c %s "$SQSH")
log "DONE"
log "  rootfs : $(human "$DIR_SZ")"
log "  squash : $(human "$SQ_SZ")"
log "  packages: ${PKG_COUNT}"
log "next: sudo ./scripts/02_build_delta.sh webserver nginx"
