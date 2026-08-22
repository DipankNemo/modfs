#!/usr/bin/env bash
#
# Step 1: verify the two assumptions the architecture depends on.
#
#   A. The archive can be pinned to a fixed snapshot.
#   B. An OverlayFS upperdir survives a round trip through SquashFS,
#      including whiteouts (deletions) and opaque directory markers.
#
# If B fails, delta modules are not possible and the design must change.
# Run as root:  sudo ./scripts/00_verify.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${HERE}/config.sh"

PASS=0; FAIL=0
ok()   { printf '  [ ok ] %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
info() { printf '  ...... %s\n' "$1"; }
head_() { printf '\n=== %s ===\n' "$1"; }

if [ "$(id -u)" -ne 0 ]; then
    echo "Must run as root (overlayfs whiteouts need CAP_SYS_ADMIN)." >&2
    exit 1
fi

# --------------------------------------------------------------------------
head_ "1. Host tools"
# --------------------------------------------------------------------------
for t in debootstrap mksquashfs unsquashfs curl mount umount chroot \
         losetup rsync sgdisk mkfs.ext4 getfattr qemu-img; do
    if command -v "$t" >/dev/null 2>&1; then ok "$t"; else bad "$t missing"; fi
done
info "install missing: apt install debootstrap squashfs-tools rsync gdisk"
info "                 attr qemu-utils util-linux curl"

# --------------------------------------------------------------------------
head_ "2. Kernel support"
# --------------------------------------------------------------------------
if grep -qw overlay /proc/filesystems; then ok "overlayfs available"
else
    modprobe overlay 2>/dev/null && ok "overlayfs (loaded via modprobe)" \
        || bad "overlayfs NOT available"
fi
grep -qw squashfs /proc/filesystems && ok "squashfs available" \
    || { modprobe squashfs 2>/dev/null && ok "squashfs (loaded)" \
         || bad "squashfs NOT available"; }

# --------------------------------------------------------------------------
head_ "3. Assumption A: snapshot ${SNAPSHOT_ID} is reachable"
# --------------------------------------------------------------------------
for pocket in "${SUITE}" "${SUITE}-updates" "${SUITE}-security"; do
    url="${SNAPSHOT_BASE}/dists/${pocket}/Release"
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 25 "$url")
    if [ "$code" = "200" ]; then
        ok "${pocket} Release (HTTP 200)"
    else
        bad "${pocket} Release -> HTTP ${code}"
        [ "$pocket" = "${SUITE}-security" ] && \
            info "if only -security fails, use security.ubuntu.com with [snapshot=] instead"
    fi
done
stamp=$(curl -s --max-time 25 "${SNAPSHOT_BASE}/dists/${SUITE}/Release" \
        | grep -m1 '^Date:' || true)
[ -n "$stamp" ] && info "archive ${stamp}"

# --------------------------------------------------------------------------
head_ "4. Assumption B: overlay upperdir survives SquashFS"
# --------------------------------------------------------------------------
T="${BUILD_DIR}/verify_wo"
cleanup_b() {
    umount "$T/merged2" 2>/dev/null || true
    umount "$T/mnt_delta" 2>/dev/null || true
    umount "$T/merged"  2>/dev/null || true
    rm -rf "$T"
}
trap cleanup_b EXIT
cleanup_b; mkdir -p "$T"/{lower,upper,work,merged,upper2,work2,merged2,mnt_delta}

# A base layer with a file to keep, a file to delete, and a dir to replace.
echo keep    > "$T/lower/keep.txt"
echo gone    > "$T/lower/gone.txt"
mkdir -p "$T/lower/subdir"; echo inner > "$T/lower/subdir/inner.txt"

if ! mount -t overlay overlay \
     -o "lowerdir=$T/lower,upperdir=$T/upper,workdir=$T/work" "$T/merged"; then
    bad "cannot mount overlayfs (is upperdir on a fs supporting trusted xattrs?)"
    echo; echo "PASS=${PASS} FAIL=${FAIL}"; exit 1
fi
ok "overlay mounted"

# Produce a whiteout and an opaque directory, exactly as a delta build would.
rm -f "$T/merged/gone.txt"
rm -rf "$T/merged/subdir"; mkdir "$T/merged/subdir"
echo new > "$T/merged/subdir/new.txt"
echo added > "$T/merged/added.txt"
umount "$T/merged"

if [ -c "$T/upper/gone.txt" ]; then ok "whiteout created as char device 0:0"
else bad "no whiteout char device in upperdir"; fi
if getfattr -m 'trusted.overlay' -d "$T/upper/subdir" 2>/dev/null | grep -q opaque
then ok "opaque dir marker present (trusted.overlay.opaque)"
else info "no opaque xattr (kernel may use a different marker; functional test decides)"; fi

# The round trip.
mksquashfs "$T/upper" "$T/delta.sqsh" \
    -comp "$SQUASH_COMP" -noappend -no-progress >/dev/null 2>&1 \
    && ok "delta squashed" || bad "mksquashfs failed"

mount -o loop,ro "$T/delta.sqsh" "$T/mnt_delta" \
    && ok "delta mounted read-only" || bad "cannot mount delta.sqsh"

[ -c "$T/mnt_delta/gone.txt" ] && ok "whiteout SURVIVED squashfs" \
    || bad "whiteout LOST in squashfs"

# Functional test: delta as leftmost (highest priority) lowerdir over base.
if mount -t overlay overlay \
   -o "lowerdir=$T/mnt_delta:$T/lower,upperdir=$T/upper2,workdir=$T/work2" \
   "$T/merged2"; then
    ok "recomposed base + delta"
    [ -f "$T/merged2/keep.txt" ]        && ok "kept file visible"        || bad "kept file missing"
    [ -f "$T/merged2/added.txt" ]       && ok "added file visible"       || bad "added file missing"
    [ ! -e "$T/merged2/gone.txt" ]      && ok "deleted file HIDDEN"      || bad "deleted file still visible -- whiteout not honoured"
    [ -f "$T/merged2/subdir/new.txt" ]  && ok "replaced dir has new file" || bad "new file in replaced dir missing"
    [ ! -e "$T/merged2/subdir/inner.txt" ] && ok "replaced dir masks old content" \
        || bad "old dir content leaks through -- opaque marker not honoured"
else
    bad "cannot recompose with squashed delta as lowerdir"
fi

printf '\n=== RESULT: %d passed, %d failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && echo "Both assumptions hold. Proceed to Step 2 (builder)." \
                  || echo "Fix failures before writing the builder."
exit $(( FAIL > 0 ))
