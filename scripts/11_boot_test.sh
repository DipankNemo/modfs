#!/usr/bin/env bash
#
# TIER 3: boot a composed module set for real, under UEFI, and check it from
# inside the running system.
#
#   sudo ./scripts/11_boot_test.sh base webserver apache
#   sudo ./scripts/11_boot_test.sh --name runA base curl jq ...
#
# Tiers 1 and 2 verify metadata and the composed filesystem. Neither can see a
# conflict that only exists at runtime -- two modules both binding port 80
# compose perfectly and fail the moment systemd starts them.
#
# What it does:
#   1. compose the set and reconcile it (same path as 04/07)
#   2. install a kernel INTO THE IMAGE ONLY -- boot scaffolding is not module
#      content, so no artefact and no module definition changes
#   3. pack a GPT/UEFI disk: ESP with systemd-boot, ext4 root
#   4. boot headless under OVMF with the console on ttyS0
#   5. in the guest: dpkg --audit, systemctl state and failed units, and every
#      per-module probe from specs/modules.yaml -- then power off
#   6. parse the serial log for the verdict
#
# Exit: 0 everything passed, 1 something in the guest failed, 2 the harness
# broke (no boot, timeout, missing tool). Run B below is EXPECTED to exit 1 --
# that is the finding, not a malfunction.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${HERE}/config.sh"
source "${HERE}/scripts/lib.sh"

die2() { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 2; }
[ "$(id -u)" -eq 0 ] || die2 "must run as root (mounts, chroot, loop devices)"

NAME=""; TIMEOUT=600; MEM=2048; IMG_MB=3072; KNOWN_NEG=0; EXPECT="all-green"
while [ $# -gt 0 ]; do
    case "$1" in
        --name)    [ $# -ge 2 ] || die2 "--name needs a value";    NAME="$2"; shift 2 ;;
        --timeout) [ $# -ge 2 ] || die2 "--timeout needs a value"; TIMEOUT="$2"; shift 2 ;;
        --mem)     [ $# -ge 2 ] || die2 "--mem needs a value";     MEM="$2"; shift 2 ;;
        --size-mb) [ $# -ge 2 ] || die2 "--size-mb needs a value"; IMG_MB="$2"; shift 2 ;;
        --known-negative) KNOWN_NEG=1; EXPECT="tier-1 rejection"; shift ;;
        --expect) [ $# -ge 2 ] || die2 "--expect needs a value"; EXPECT="$2"; shift 2 ;;
        -*) die2 "unknown option: $1" ;;
        *) break ;;
    esac
done
[ $# -ge 2 ] || die2 "usage: $0 [--name TAG] base <module> [module...]"
MODULES=("$@")
[ -n "$NAME" ] || NAME="$(IFS=-; echo "${MODULES[*]}")"
NAME="${NAME:0:60}"

# C1. --name reached a root `rm -rf` unvalidated; "../../modules" would have
# deleted the artefact store. Validate every identifier, bound every number.
require_ident "$NAME" "run name"
for m in "${MODULES[@]}"; do require_ident "$m" "module name"; done
require_uint "$TIMEOUT" 30 7200 "--timeout"
require_uint "$MEM"     256 65536 "--mem"
require_uint "$IMG_MB"  512 131072 "--size-mb"

for t in qemu-system-x86_64 sgdisk mkfs.vfat mkfs.ext4 losetup rsync; do
    command -v "$t" >/dev/null 2>&1 || die2 "missing tool: $t"
done
OVMF_CODE=/usr/share/OVMF/OVMF_CODE_4M.fd
OVMF_VARS=/usr/share/OVMF/OVMF_VARS_4M.fd
[ -f "$OVMF_CODE" ] || OVMF_CODE=/usr/share/ovmf/OVMF.fd
[ -f "$OVMF_CODE" ] || die2 "no OVMF firmware (apt install ovmf)"

# C5. Run bundles are timestamped and immutable. Reusing --name can no
# longer delete prior evidence, because nothing is ever deleted: a collision
# is an error. The bundle also lives outside BUILD_DIR, which config.sh calls
# scratch.
RUN_TS="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_ID="${NAME}-${RUN_TS}"
BOOT_ROOT="${RESULTS_DIR}/boot"
mkdir -p "$BOOT_ROOT"
B="$(safe_child "$BOOT_ROOT" "$RUN_ID")"
C_IMG=""; C_VARS=""
[ -e "$B" ] && die2 "run bundle already exists: $B"
mkdir -p "$B" || die2 "cannot create run bundle: $B"
SERIAL="$B/serial.log"; IMG="$C_IMG"; VARS="$C_VARS"
# Scratch for this run stays in BUILD_DIR; only evidence lands in the bundle.
C="${BUILD_DIR}/boot-${RUN_ID}"
C_IMG="$C/disk.img"; C_VARS="$C/OVMF_VARS.fd"
require_no_mounts "$C"
rm -rf -- "$C"; mkdir -p "$C"/{upper,work,merged}
M="$C/merged"

# Written BEFORE any mount, chroot, apt transaction or image write, so an
# aborted run still leaves a record of what was attempted and why.
python3 - "$B/run.json" "$RUN_ID" "$RUN_TS" "$EXPECT" "$KNOWN_NEG" "$TIMEOUT" \
         "$MEM" "$IMG_MB" "${MODULES[@]}" <<'RJ'
import json, os, sys
out, run_id, ts, expect, kn, timeout, mem, img, mods = (
    sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5],
    sys.argv[6], sys.argv[7], sys.argv[8], sys.argv[9:])
json.dump({'run_id': run_id, 'started_utc': ts, 'tier': 3,
           'expectation': expect, 'known_negative': kn == '1',
           'modules': mods, 'timeout_s': int(timeout),
           'mem_mb': int(mem), 'image_mb': int(img),
           'argv': sys.argv[1:], 'status': 'started'},
          open(out, 'w'), indent=2)
RJ
{
    echo "commit      $(git -C "$HERE" rev-parse HEAD 2>/dev/null || echo unknown)"
    echo "dirty       $(git -C "$HERE" status --porcelain 2>/dev/null | wc -l) file(s) modified"
    git -C "$HERE" status --porcelain 2>/dev/null | sed 's/^/  /'
    echo "host        $(uname -srm)  $(hostname)"
    echo "qemu        $(qemu-system-x86_64 --version 2>/dev/null | head -1)"
    echo "ovmf        $OVMF_CODE"
    for f in config.sh scripts/11_boot_test.sh scripts/reconcile.py \
             scripts/05_check.sh specs/modules.yaml; do
        [ -f "$HERE/$f" ] && echo "sha256      $(sha256sum "$HERE/$f" | cut -c1-16)  $f"
    done
} > "$B/source.txt" 2>&1

finish() {               # finish <verdict> <exit-code>
    python3 - "$B/result.json" "$B/run.json" "$1" "$2" <<'FJ' 2>/dev/null || true
import json, sys, time, os
out, runf, verdict, rc = sys.argv[1:5]
try:    run = json.load(open(runf))
except Exception: run = {}
started = run.get('started_utc', '')
json.dump({'run_id': run.get('run_id'), 'verdict': verdict, 'exit_code': int(rc),
           'expectation': run.get('expectation'),
           'known_negative': run.get('known_negative'),
           'modules': run.get('modules'),
           'started_utc': started,
           'finished_utc': time.strftime('%Y%m%dT%H%M%SZ', time.gmtime()),
           'duration_s': int(time.time() - os.path.getmtime(runf))},
          open(out, 'w'), indent=2)
FJ
    return 0
}

# Loop devices are not tracked by lib.sh's mount stack, so they need their own
# teardown -- a leaked loop device survives the script and blocks the image.
LOOPDEV=""
boot_cleanup() {
    [ -n "$LOOPDEV" ] && { umount "$C/mnt/esp" 2>/dev/null; umount "$C/mnt/root" 2>/dev/null
                           losetup -d "$LOOPDEV" 2>/dev/null; }
    return 0
}
trap 'boot_cleanup; cleanup' EXIT INT TERM

# ---- 0. admission --------------------------------------------------------
# C3. Run A died inside APT because a tier-1-rejected set (the MTA pair) was
# composed anyway. Integrity and admission come first, always; a deliberate
# negative must say so explicitly and is never called "admitted".
log "verifying bundle integrity"
verify_bundle "${MODULES[@]}" > "$B/integrity.txt" 2>&1 || {
    cat "$B/integrity.txt" >&2; finish INTEGRITY_FAIL 2; die2 "bundle integrity failed"; }

tier1_admit "$B/tier1.txt" "${MODULES[@]}"; ADM=$?
case "$ADM" in
    0) ADMITTED=yes;  log "tier-1: ADMITTED" ;;
    1) ADMITTED=no;   log "tier-1: REJECTED" ;;
    *) ADMITTED=broken; log "tier-1: CHECKER BROKE" ;;
esac
if [ "$ADM" -ne 0 ] && [ "$KNOWN_NEG" -eq 0 ]; then
    tail -20 "$B/tier1.txt" | sed 's/^/    /'
    finish NOT_ADMITTED 2
    die2 "set not admitted by tier 1; re-run with --known-negative to boot it anyway"
fi
[ "$ADM" -eq 0 ] || log "proceeding as a KNOWN NEGATIVE -- this result is not a verification"

# ---- 1. compose ----------------------------------------------------------
log "composing: ${MODULES[*]}"
LAYERS=(); LOWERS=()
for m in "${MODULES[@]}"; do
    sq="${MOD_DIR}/${m}.sqsh"; [ -f "$sq" ] || die2 "missing artefact ${sq}"
    mp="$C/ro_${m}"; mkdir -p "$mp"
    do_mount -o loop,ro "$sq" "$mp"
    LOWERS=("$mp" "${LOWERS[@]}"); LAYERS+=("${m}=${mp}")
done
do_mount -t overlay overlay \
    -o "lowerdir=$(IFS=:; echo "${LOWERS[*]}"),upperdir=${C}/upper,workdir=${C}/work" "$M"
mount_chroot_fs "$M"
write_sources_list "$M"
write_chroot_policy "$M"

python3 "${HERE}/scripts/reconcile.py" --merged "$M" --groups-out "$C/alt.groups" \
        "${LAYERS[@]}" > "$B/reconcile.log" 2>&1 || die2 "reconciliation failed"
while read -r g; do
    [ -n "$g" ] || continue
    in_chroot "$M" update-alternatives --auto "$g" >/dev/null 2>&1 </dev/null || true
done < "$C/alt.groups"
in_chroot "$M" ldconfig >/dev/null 2>&1 </dev/null || true
log "reconciled: $(grep -c . <<<"$(in_chroot "$M" dpkg-query -W -f '${binary:Package}\n' 2>/dev/null </dev/null)") packages"

# ---- 2. kernel: scaffolding, into the image only -------------------------
# The artefacts exclude /run by design, so base's /etc/resolv.conf -- a
# symlink to ../run/systemd/resolve/stub-resolv.conf -- DANGLES in a composed
# view and apt cannot resolve anything. 02_build_delta.sh never hits this
# because it builds on base.dir, the raw tree, which still has /run.
# Supply a real resolver for the pack step only, and put the symlink back
# before the image is written so no host DNS config ships in it.
# Same story for directories. SQUASH_EXCLUDES drops proc, sys, dev, run, tmp,
# var/tmp, var/lib/apt/lists and var/cache/apt/archives -- the DIRECTORIES,
# not merely their contents -- so a composed tree has neither the mountpoints
# systemd needs nor the scratch space apt needs. mount_chroot_fs happens to
# create proc/sys/dev/run, which is why nothing noticed until now; it does not
# create /tmp, and apt fails on its first temporary file.
log "creating runtime directories the artefacts exclude"
mkdir -p "$M"/tmp "$M"/var/tmp \
         "$M"/var/lib/apt/lists/partial "$M"/var/cache/apt/archives/partial
chmod 1777 "$M/tmp" "$M/var/tmp"
chmod 755  "$M/var/lib/apt/lists" "$M/var/cache/apt/archives"
chmod 700  "$M/var/lib/apt/lists/partial" "$M/var/cache/apt/archives/partial"

RESOLV_SRC=/run/systemd/resolve/resolv.conf
[ -r "$RESOLV_SRC" ] || RESOLV_SRC=/etc/resolv.conf
[ -r "$RESOLV_SRC" ] || die2 "no usable resolv.conf on the host for the pack step"
rm -f "$M/etc/resolv.conf"
cp -L "$RESOLV_SRC" "$M/etc/resolv.conf" || die2 "cannot stage resolv.conf"

log "installing kernel into the image (not into any module)"
in_chroot "$M" apt-get update -qq </dev/null > "$B/apt.log" 2>&1 \
    || die2 "apt update failed in the merged view, see $B/apt.log"
in_chroot "$M" apt-get install -y -qq --no-install-recommends \
    linux-image-generic initramfs-tools </dev/null >> "$B/apt.log" 2>&1 \
    || die2 "kernel install failed, see $B/apt.log"
# Back to what the modules actually ship, so the image carries no host DNS.
rm -f "$M/etc/resolv.conf"
ln -s ../run/systemd/resolve/stub-resolv.conf "$M/etc/resolv.conf"

KVER=$(in_chroot "$M" sh -c 'ls -1 /boot/vmlinuz-* 2>/dev/null | sed "s|.*/vmlinuz-||" | sort -V | tail -1' </dev/null)
[ -n "$KVER" ] || die2 "no kernel in /boot after install"
log "kernel ${KVER}"

# ---- 3. in-guest test harness -------------------------------------------
python3 - "${SPEC_DIR}/modules.yaml" "$M/etc/modfs-probes" "${MODULES[@]}" <<'PY' \
    || die2 "cannot build the probe list"
import sys, yaml
spec, out, mods = sys.argv[1], sys.argv[2], sys.argv[3:]
doc = yaml.safe_load(open(spec, encoding='utf-8')) or {}
probes = {m['name']: str(m['probe']) for m in (doc.get('modules') or [])
          if m.get('name') and m.get('probe')}
with open(out, 'w', encoding='utf-8') as f:
    for m in mods:
        if m in probes: f.write("%s|%s\n" % (m, probes[m]))
print("  probes for %d module(s)" % sum(1 for m in mods if m in probes))
PY

# The boot matrix needs to know which units are EXPECTED to start. Take that
# from what the composed tree actually enables, not from a hand-written list:
# a unit that is absent, masked or never enabled is exactly the failure mode a
# "list the failed units" check cannot see.
: > "$M/etc/modfs-units"
for wants in "$M"/etc/systemd/system/*.target.wants "$M"/usr/lib/systemd/system/*.target.wants; do
    [ -d "$wants" ] || continue
    for u in "$wants"/*.service; do
        [ -e "$u" ] || continue
        basename "$u"
    done
done | sort -u > "$M/etc/modfs-units"
log "expected units: $(tr '\n' ' ' < "$M/etc/modfs-units")"

cat > "$M/usr/local/sbin/modfs-boottest" <<'GUEST'
#!/bin/sh
# Runs inside the booted guest. Everything goes to the serial console, which
# is the only channel the harness can read.
exec > /dev/ttyS0 2>&1

# The steady-state race: this used to be a startup oneshot ordered after
# multi-user.target, so `is-system-running --wait` could never return -- the
# harness was itself an unfinished job in the boot transaction. It is now
# started by a timer OUTSIDE that transaction, so waiting is safe, but the
# wait is still bounded rather than trusted.
timeout 120 systemctl is-system-running --wait >/dev/null 2>&1
i=0
while [ "$i" -lt 60 ]; do
    n=$(systemctl list-jobs --no-legend --plain 2>/dev/null | grep -c . || echo 0)
    [ "$n" = "0" ] && break
    i=$((i + 1)); sleep 1
done

echo "===MODFS-BOOTTEST-BEGIN==="
echo "MODFS state: $(systemctl is-system-running 2>&1)"
echo "MODFS jobs-remaining: $(systemctl list-jobs --no-legend --plain 2>/dev/null | grep -c . || echo 0)"

echo "MODFS failed-begin"
systemctl list-units --state=failed --no-legend --plain 2>/dev/null \
    | awk '{print "MODFS failed-unit " $1}'
echo "MODFS failed-end"

# Per expected unit: enabled/active state, substate, exit status, restarts,
# and the unit's own journal. This is what turns "apache failed" from an
# inference about port 80 into recorded cause.
if [ -r /etc/modfs-units ]; then
    while read -r u; do
        [ -n "$u" ] || continue
        en=$(systemctl is-enabled "$u" 2>&1 | head -1)
        ac=$(systemctl is-active  "$u" 2>&1 | head -1)
        sub=$(systemctl show -p SubState --value "$u" 2>/dev/null)
        st=$(systemctl show -p ExecMainStatus --value "$u" 2>/dev/null)
        nr=$(systemctl show -p NRestarts --value "$u" 2>/dev/null)
        rs=$(systemctl show -p Result --value "$u" 2>/dev/null)
        echo "MODFS UNIT $u enabled=$en active=$ac sub=$sub exec=$st restarts=$nr result=$rs"
        echo "MODFS UNITLOG-BEGIN $u"
        journalctl -b -u "$u" --no-pager -o short 2>/dev/null | tail -25
        echo "MODFS UNITLOG-END $u"
    done < /etc/modfs-units
fi

# Who actually owns the listening sockets. With two web servers this is the
# difference between "apache failed" and "nginx holds 0.0.0.0:80".
echo "MODFS LISTEN-BEGIN"
ss -ltnup 2>/dev/null || echo "(ss unavailable)"
echo "MODFS LISTEN-END"

dpkg --audit > /tmp/audit.out 2>&1
if [ $? -eq 0 ] && [ ! -s /tmp/audit.out ]; then
    echo "MODFS CHECK audit PASS"
else
    echo "MODFS CHECK audit FAIL"
    sed 's/^/MODFS auditline /' /tmp/audit.out | head -20
fi

if [ -r /etc/modfs-probes ]; then
    while IFS='|' read -r name probe; do
        [ -n "$probe" ] || continue
        out=$(timeout 30 sh -c "$probe" 2>&1); rc=$?
        if [ "$rc" -eq 0 ]; then echo "MODFS PROBE $name PASS"
        else
            echo "MODFS PROBE $name FAIL rc=$rc"
            printf '%s\n' "$out" | head -5 | sed 's/^/MODFS probeout /'
        fi
    done < /etc/modfs-probes
fi

echo "===MODFS-BOOTTEST-END==="
sync
systemctl poweroff -i 2>/dev/null || poweroff -f
GUEST
chmod +x "$M/usr/local/sbin/modfs-boottest"

# Triggered by a TIMER, not wanted by multi-user.target. As part of the boot
# transaction the harness could never observe boot completing, because it was
# itself the job holding it open.
cat > "$M/etc/systemd/system/modfs-boottest.service" <<'UNIT'
[Unit]
Description=modfs tier-3 boot test
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/modfs-boottest
StandardOutput=journal+console
TimeoutStartSec=300
UNIT
cat > "$M/etc/systemd/system/modfs-boottest.timer" <<'TIMER'
[Unit]
Description=run the modfs tier-3 boot test after boot settles
[Timer]
OnBootSec=5s
AccuracySec=1s
[Install]
WantedBy=timers.target
TIMER
mkdir -p "$M/etc/systemd/system/timers.target.wants"
ln -sf ../modfs-boottest.timer \
       "$M/etc/systemd/system/timers.target.wants/modfs-boottest.timer"
printf 'modfs-guest\n' > "$M/etc/hostname"
# Without this systemd waits 90 s for a root fs entry that does not exist.
printf 'LABEL=modfsroot / ext4 defaults 0 1\n' > "$M/etc/fstab"

remove_chroot_policy "$M"

# ---- 4. pack a UEFI disk -------------------------------------------------
log "packing ${IMG_MB} MB UEFI image"
rm -f "$IMG"; truncate -s "${IMG_MB}M" "$IMG"
sgdisk -Z "$IMG" >/dev/null 2>&1
sgdisk -n 1:0:+128M -t 1:ef00 -c 1:ESP \
       -n 2:0:0     -t 2:8300 -c 2:modfsroot "$IMG" >/dev/null 2>&1 \
    || die2 "sgdisk failed"
LOOPDEV=$(losetup --show -f -P "$IMG") || die2 "losetup failed"
[ -e "${LOOPDEV}p1" ] || die2 "no partitions on ${LOOPDEV}"
mkfs.vfat -F32 -n ESP "${LOOPDEV}p1" >/dev/null 2>&1 || die2 "mkfs.vfat failed"
mkfs.ext4 -q -L modfsroot "${LOOPDEV}p2"            || die2 "mkfs.ext4 failed"

mkdir -p "$C/mnt/esp" "$C/mnt/root"
mount "${LOOPDEV}p1" "$C/mnt/esp"  || die2 "cannot mount ESP"
mount "${LOOPDEV}p2" "$C/mnt/root" || die2 "cannot mount root"

log "copying the composed tree"
rsync -aHAX --numeric-ids \
      --exclude='/proc/*' --exclude='/sys/*' --exclude='/dev/*' --exclude='/run/*' \
      "$M/" "$B/mnt/root/" > "$B/rsync.log" 2>&1 || die2 "rsync failed, see $B/rsync.log"

# SQUASH_EXCLUDES drops proc, sys, dev, run, tmp and var/tmp from every
# artefact -- the DIRECTORIES, not just their contents. That is right for an
# artefact (they are runtime, not module content) but it means a composed tree
# has no mountpoints, and systemd cannot mount the API filesystems without
# them. Tiers 1 and 2 never saw this because mount_chroot_fs mkdir -p's them
# first. Creating them here is image scaffolding, exactly like the kernel.
log "creating runtime mountpoints (excluded from artefacts by design)"
for d in proc sys dev run tmp var/tmp; do mkdir -p "$B/mnt/root/$d"; done
chmod 555 "$B/mnt/root/proc" "$B/mnt/root/sys"
chmod 755 "$B/mnt/root/dev"  "$B/mnt/root/run"
chmod 1777 "$B/mnt/root/tmp" "$B/mnt/root/var/tmp"

# systemd-boot ships inside systemd, which base already has. BOOTX64.EFI is
# the removable-media path, so it boots without writing UEFI NVMRAM.
STUB="$M/usr/lib/systemd/boot/efi/systemd-bootx64.efi"
[ -f "$STUB" ] || die2 "no systemd-bootx64.efi in the composed tree"
mkdir -p "$B/mnt/esp/EFI/BOOT" "$B/mnt/esp/loader/entries" "$B/mnt/esp/modfs"
cp "$STUB" "$B/mnt/esp/EFI/BOOT/BOOTX64.EFI"
cp "$M/boot/vmlinuz-${KVER}"    "$B/mnt/esp/modfs/vmlinuz"
cp "$M/boot/initrd.img-${KVER}" "$B/mnt/esp/modfs/initrd.img"
printf 'default modfs\ntimeout 0\nconsole-mode max\n' > "$B/mnt/esp/loader/loader.conf"
cat > "$B/mnt/esp/loader/entries/modfs.conf" <<ENTRY
title   modfs composed system
linux   /modfs/vmlinuz
initrd  /modfs/initrd.img
options root=LABEL=modfsroot rw console=ttyS0,115200 systemd.log_target=console panic=10
ENTRY

sync
umount "$C/mnt/esp"; umount "$C/mnt/root"
losetup -d "$LOOPDEV"; LOOPDEV=""
unmount_all                       # release the composed overlay before booting

# ---- 5. boot -------------------------------------------------------------
cp "$OVMF_VARS" "$VARS" 2>/dev/null || die2 "no OVMF vars template"
ACCEL=tcg; [ -w /dev/kvm ] && ACCEL=kvm
log "booting under QEMU (accel=${ACCEL}, timeout ${TIMEOUT}s)"
: > "$SERIAL"
timeout --foreground "$TIMEOUT" qemu-system-x86_64 \
    -machine q35,accel="${ACCEL}" -m "$MEM" -smp 2 \
    -drive if=pflash,format=raw,unit=0,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,unit=1,file="$VARS" \
    -drive file="$IMG",format=raw,if=virtio \
    -display none -serial "file:$SERIAL" -no-reboot \
    > "$B/qemu.log" 2>&1
QRC=$?
log "qemu exited ${QRC}, serial log $(wc -c < "$SERIAL") bytes"

# ---- 6. verdict ----------------------------------------------------------
echo
echo "========================================================================"
echo " TIER-3 BOOT TEST: ${MODULES[*]}"
echo "========================================================================"
python3 - "$SERIAL" "$QRC" "$TIMEOUT" "$B" "$ADMITTED" "$KNOWN_NEG" <<'PY'
import os, re, sys
serial_path, qrc, timeout, bundle, admitted, known_neg = sys.argv[1:7]
serial = open(serial_path, errors='replace').read()
qrc, known_neg = int(qrc), known_neg == '1'

def bail(msg, extra=()):
    print("\n  " + msg)
    for line in extra: print("    " + line[:110])
    sys.exit(2)

if '===MODFS-BOOTTEST-BEGIN===' not in serial:
    tail = [l for l in serial.split('\n') if l.strip()][-15:]
    if qrc == 124:
        bail("QEMU hit the %ss timeout -- boot hung or never started." % timeout, tail)
    if not tail:
        bail("serial log is EMPTY: firmware never handed off, or no console.")
    bail("the guest never reached the test harness.", tail)
if '===MODFS-BOOTTEST-END===' not in serial:
    bail("harness started but did not finish -- guest died mid-test.",
         [l for l in serial.split('\n') if l.strip()][-15:])

state = (re.search(r'MODFS state: (.+)', serial) or [None, '?'])[1].strip()
jobs  = (re.search(r'MODFS jobs-remaining: (\d+)', serial) or [None, '?'])[1]
failed = re.findall(r'MODFS failed-unit (\S+)', serial)
checks = re.findall(r'MODFS CHECK (\S+) (PASS|FAIL)', serial)
probes = re.findall(r'MODFS PROBE (\S+) (PASS|FAIL)', serial)
units  = re.findall(r'MODFS UNIT (\S+) enabled=(\S*) active=(\S*) sub=(\S*)'
                    r' exec=(\S*) restarts=(\S*) result=(\S*)', serial)

# Preserve the matrix as evidence, not only as terminal output.
with open(os.path.join(bundle, 'units.txt'), 'w') as f:
    for u in units:
        f.write("%-28s enabled=%-10s active=%-10s sub=%-10s exec=%-4s restarts=%-3s result=%s\n" % u)
listen = re.search(r'MODFS LISTEN-BEGIN\n(.*?)MODFS LISTEN-END', serial, re.S)
open(os.path.join(bundle, 'listeners.txt'), 'w').write(listen.group(1) if listen else '')
with open(os.path.join(bundle, 'journal.txt'), 'w') as f:
    for m in re.finditer(r'MODFS UNITLOG-BEGIN (\S+)\n(.*?)MODFS UNITLOG-END', serial, re.S):
        f.write("===== %s =====\n%s\n" % (m.group(1), m.group(2)))

print("\n  tier-1 admission : %s%s" % (admitted, "  (KNOWN NEGATIVE)" if known_neg else ""))
print("  systemd state    : %s   (jobs remaining: %s)" % (state, jobs))
print("  failed units     : %d%s" % (len(failed), "  " + ", ".join(failed) if failed else ""))
if units:
    print("\n  unit matrix")
    for name, en, ac, sub, ex, nr, res in units:
        flag = "" if ac == 'active' else "   <-- not active"
        print("    %-26s %-9s %-9s sub=%-9s exit=%-3s result=%s%s"
              % (name, en, ac, sub, ex, res, flag))
if listen:
    rows = [l for l in listen.group(1).split('\n')
            if l.strip() and not l.startswith('Netid')]
    if rows:
        print("\n  listening sockets")
        for l in rows[:10]: print("    " + l.strip()[:104])
for n, r in checks: print("\n  check %-10s %s" % (n, r))
for n, r in probes: print("  probe %-10s %s" % (n, r))

bad = [n for n, r in checks + probes if r == 'FAIL']
print()
if qrc != 0:
    print("  NOTE: QEMU exited %d despite a complete run -- treated as broken." % qrc)
    sys.exit(2)
if bad:    print("  FAILED checks/probes: %s" % ', '.join(bad))
if failed: print("  FAILED units: %s" % ', '.join(failed))
if known_neg:
    print("  KNOWN NEGATIVE -- this run is an observation of a rejected set,")
    print("  not a verification. Nothing here says the set is composable.")
    sys.exit(1)
if not bad and not failed:
    print("  ALL GREEN -- every expected unit active, every probe passed")
print("========================================================================")
sys.exit(0 if (not bad and not failed) else 1)
PY
RC=$?
case "$RC" in
    0) finish PASS 0 ;;
    1) finish "$([ "$KNOWN_NEG" -eq 1 ] && echo KNOWN_NEGATIVE_OBSERVED || echo FAIL)" 1 ;;
    *) finish BROKEN 2 ;;
esac
echo
echo " serial log: ${SERIAL}"
echo " disk image: ${IMG}  (scratch; delete with: rm -rf ${C})"
echo " run bundle: ${B}  (evidence -- do not delete)"
exit "$RC"
