#!/usr/bin/env bash
# Shared helpers. Sourced by every build script.
# Main job: make sure mounts are ALWAYS torn down, in reverse order,
# even if the script dies or is interrupted.

set -uo pipefail

log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

need_root() { [ "$(id -u)" -eq 0 ] || die "must run as root (use sudo)"; }

# ---- mount tracking -------------------------------------------------------
# Every mount we make gets pushed onto a stack. cleanup() pops it in reverse.
MOUNTS=()

track_mount() { MOUNTS+=("$1"); }

do_mount() {           # do_mount <mount args...> <target>
    local target="${*: -1}"
    mount "$@" || die "mount failed: $*"
    track_mount "$target"
}

unmount_all() {
    local i
    for (( i=${#MOUNTS[@]}-1 ; i>=0 ; i-- )); do
        local m="${MOUNTS[i]}"
        mountpoint -q "$m" 2>/dev/null || continue
        umount "$m" 2>/dev/null || umount -l "$m" 2>/dev/null || \
            warn "could not unmount $m"
    done
    MOUNTS=()
}

cleanup() {
    local rc=$?
    unmount_all
    return $rc
}
trap cleanup EXIT INT TERM

# ---- chroot plumbing ------------------------------------------------------
# June's build only bound /dev and /dev/pts. Some maintainer scripts read
# /proc and /sys and fail quietly without them, producing a subtly
# incomplete module. Bind all four.
mount_chroot_fs() {      # mount_chroot_fs <root>
    local r="$1"
    mkdir -p "$r"/{proc,sys,dev,dev/pts,run}
    do_mount -t proc  proc  "$r/proc"
    do_mount -t sysfs sys   "$r/sys"
    do_mount --bind /dev     "$r/dev"
    do_mount --bind /dev/pts "$r/dev/pts"
}

# Stop daemons from starting inside the chroot, and silence interactive
# prompts from packages like tzdata.
write_chroot_policy() {  # write_chroot_policy <root>
    local r="$1"
    mkdir -p "$r/usr/sbin"
    printf '#!/bin/sh\nexit 101\n' > "$r/usr/sbin/policy-rc.d"
    chmod +x "$r/usr/sbin/policy-rc.d"
    mkdir -p "$r/etc"
    printf '%s\n' \
        'APT::Install-Recommends "false";' \
        'APT::Install-Suggests "false";' \
        > "$r/etc/apt/apt.conf.d/99modfs"
}

remove_chroot_policy() { rm -f "$1/usr/sbin/policy-rc.d"; }

in_chroot() {            # in_chroot <root> <command...>
    local r="$1"; shift
    DEBIAN_FRONTEND=noninteractive LC_ALL=C LANG=C \
        chroot "$r" /usr/bin/env \
        DEBIAN_FRONTEND=noninteractive LC_ALL=C LANG=C \
        "$@"
}

# ---- sources.list against the pinned snapshot -----------------------------
# The snapshot ID goes in the URL PATH, not as an apt option. debootstrap
# does not understand apt's [snapshot=] syntax, and jammy ships apt 2.4.5
# which predates the --snapshot flag. The URL form works regardless.
write_sources_list() {   # write_sources_list <root>
    local r="$1"
    mkdir -p "$r/etc/apt"
    cat > "$r/etc/apt/sources.list" <<EOF
deb ${SNAPSHOT_BASE} ${SUITE} ${COMPONENTS}
deb ${SNAPSHOT_BASE} ${SUITE}-updates ${COMPONENTS}
deb ${SNAPSHOT_BASE} ${SUITE}-security ${COMPONENTS}
EOF
}

human() { numfmt --to=iec --suffix=B "$1" 2>/dev/null || echo "$1"; }
