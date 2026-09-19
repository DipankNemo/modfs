#!/usr/bin/env bash
# Controlled monolithic comparator: flatten exactly base + one delta, reconcile
# identically, and use the same compression/timestamps/exclusions. No kernel or
# disk envelope: these are server-side rootfs transfer bytes, not node traffic.
# Usage: MODFS_ROOT=... sudo -E scripts/15_measure_monolith.sh jq
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${HERE}/config.sh"
source "${HERE}/scripts/lib.sh"
need_root
[ $# -eq 1 ] || die "usage: $0 MODULE"
NAME="$1"; require_ident "$NAME" module
OUT="${IMAGE_DIR}/${NAME}-monolithic.sqsh"
[ ! -e "$OUT" ] || die "refusing to overwrite ${OUT}"
C="${BUILD_DIR}/monolithic-${NAME}"
reset_workdir "$C"
mkdir -p "$C"/{upper,work,merged} "$IMAGE_DIR"
verify_bundle base "$NAME" || die "invalid bundle"
tier1_admit "$C/tier1.log" base "$NAME" || die "tier 1 refused set"
LAYERS=(); LOWERS=()
for m in base "$NAME"; do
    mkdir -p "$C/ro_${m}"
    do_mount -o loop,ro "${MOD_DIR}/${m}.sqsh" "$C/ro_${m}"
    LOWERS=("$C/ro_${m}" "${LOWERS[@]}")
    LAYERS+=("${m}=$C/ro_${m}")
done
LOWERDIR=$(IFS=:; echo "${LOWERS[*]}")
M="$C/merged"
do_mount -t overlay overlay -o "lowerdir=${LOWERDIR},upperdir=$C/upper,workdir=$C/work" "$M"
mount_chroot_fs "$M"
python3 "$HERE/scripts/reconcile.py" --merged "$M" --groups-out "$C/groups" "${LAYERS[@]}" \
    > "$C/reconcile.log" 2>&1 || die "reconciliation failed"
while read -r g; do
    [ -z "$g" ] || in_chroot "$M" update-alternatives --auto "$g" > /dev/null 2>&1 \
        || die "alternatives failed: $g"
done < "$C/groups"
in_chroot "$M" ldconfig || die "ldconfig failed"
in_chroot "$M" dpkg-query -W -f '${binary:Package}\t${Version}\n' > "$C/actual.pkgs"
in_chroot "$M" ldconfig -p > "$C/actual.ld"
in_chroot "$M" dpkg --audit > "$C/audit.txt" 2>&1
python3 "$HERE/scripts/verify_compose.py" --scripts "$HERE/scripts" --merged "$M" --work "$C" \
    --index 1 --n 1 --admitted yes --mount-ms 0 --reconcile-ms 0 --total-ms 0 "${LAYERS[@]}" \
    > "$C/verification.csv" || die "verification crashed"
grep -q ',PASS$' "$C/verification.csv" || die "tier 2 failed"
for mp in dev/pts dev sys proc; do umount "$M/$mp" || die "cannot unmount $mp"; done
# shellcheck disable=SC2086
mksquashfs "$M" "$OUT" -comp "$SQUASH_COMP" -Xcompression-level "$SQUASH_LEVEL" \
    -mkfs-time "$SOURCE_EPOCH" -all-time "$SOURCE_EPOCH" \
    -xattrs-exclude "$SQUASH_XATTR_EXCLUDE" -noappend -no-progress -e $SQUASH_EXCLUDES \
    > "$C/mksquashfs.log" 2>&1 || die "squash failed"
stat -c '%n %s bytes' "$OUT"
sha256sum "$OUT"
