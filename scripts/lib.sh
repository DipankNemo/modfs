#!/usr/bin/env bash
# Shared helpers. Sourced by every build script.
# Main job: make sure mounts are ALWAYS torn down, in reverse order,
# even if the script dies or is interrupted.

set -uo pipefail

log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

need_root() { [ "$(id -u)" -eq 0 ] || die "must run as root (use sudo)"; }

# ---- identifier and path safety -------------------------------------------
# Module names and run names reach file paths, mount option strings, and
# recursive deletions. `--name ../../modules` in a root-run harness is enough
# to delete the artefact store, so identifiers are validated at every entry
# point rather than trusted because the current catalogue happens to be tame.
#
# Allowlist, not denylist: [A-Za-z0-9][A-Za-z0-9._-]* cannot contain a slash,
# cannot begin with a dot, and therefore cannot be "." or ".." or contain a
# traversal component.
valid_ident() {          # valid_ident <string>
    case "$1" in
        ''|.|..) return 1 ;;
        *[!A-Za-z0-9._-]*) return 1 ;;
        [!A-Za-z0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

require_ident() {        # require_ident <string> <what-it-is>
    valid_ident "$1" || die "invalid ${2:-identifier}: '$1'
       must match [A-Za-z0-9][A-Za-z0-9._-]* -- no slashes, no leading dot"
}

require_uint() {         # require_uint <value> <min> <max> <what>
    case "$1" in
        ''|*[!0-9]*) die "${4:-value} must be a non-negative integer: '$1'" ;;
    esac
    [ "$1" -ge "$2" ] && [ "$1" -le "$3" ] \
        || die "${4:-value} out of range (${2}..${3}): '$1'"
}

# Prove a path is a DIRECT child of a fixed root before anything destructive
# touches it. Printing the canonical path makes the caller use the proven one.
safe_child() {           # safe_child <root> <name> -> canonical path on stdout
    local root="$1" name="$2" parent child
    require_ident "$name" "path component"
    parent="$(cd "$root" 2>/dev/null && pwd -P)" || die "no such root: $root"
    child="${parent}/${name}"
    [ "$(dirname "$child")" = "$parent" ] || die "path escapes ${parent}: ${child}"
    printf '%s\n' "$child"
}

# A stale mount under a deletion target turns rm -rf into a deletion of
# whatever is mounted there, which may be an artefact store or a host path.
require_no_mounts() {    # require_no_mounts <path>
    local p="$1" hit
    [ -e "$p" ] || return 0
    hit=$(awk -v d="$p/" '$2 == substr(d,1,length($2)) || index($2, d) == 1 {print $2}' \
          /proc/self/mountinfo 2>/dev/null | head -1)
    [ -z "$hit" ] || die "refusing to touch ${p}: still mounted at ${hit}"
    mountpoint -q "$p" 2>/dev/null && die "refusing to touch ${p}: it is a mountpoint"
    [ -L "$p" ] && die "refusing to touch ${p}: it is a symlink"
    return 0
}

# The only sanctioned recursive delete: containment-proven, mount-checked.
safe_rm_rf() {           # safe_rm_rf <root> <name>
    local target
    target="$(safe_child "$1" "$2")" || exit 1
    require_no_mounts "$target"
    rm -rf -- "$target"
}

# ---- admission: integrity, then tier-1 ------------------------------------
# C3. The pipeline order is a rule, not a convention:
#     bundle integrity -> tier-1 admission -> compose/reconcile -> tier-2
# Tier 2 composing a tier-1-rejected set and printing PASS made "verified"
# mean less than it looked; a physical composition proves structure, never
# package semantics.

# Every artefact must match the size and digest its own manifest records.
verify_bundle() {        # verify_bundle <module...>
    python3 - "$MOD_DIR" "$@" <<'VBPY'
import hashlib, json, os, sys
mod_dir, mods = sys.argv[1], sys.argv[2:]
bad = 0
for m in mods:
    mp = os.path.join(mod_dir, m + '.json')
    sq = os.path.join(mod_dir, m + '.sqsh')
    if not os.path.exists(mp) or not os.path.exists(sq):
        print("  integrity: %s missing manifest or artefact" % m); bad += 1; continue
    try:
        doc = json.load(open(mp, encoding='utf-8'))
    except Exception as exc:
        print("  integrity: %s unreadable manifest (%s)" % (m, exc)); bad += 1; continue
    art = doc.get('artifact') or {}
    if not art.get('sha256'):
        print("  integrity: %s manifest records no digest" % m); bad += 1; continue
    size = os.path.getsize(sq)
    if art.get('bytes') != size:
        print("  integrity: %s size %d, manifest says %s" % (m, size, art.get('bytes')))
        bad += 1; continue
    h = hashlib.sha256()
    with open(sq, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    if h.hexdigest() != art['sha256']:
        print("  integrity: %s DIGEST MISMATCH" % m); bad += 1
sys.exit(1 if bad else 0)
VBPY
}

# 0 admitted, 1 rejected by tier 1, 2 the checker itself broke.
tier1_admit() {          # tier1_admit <logfile> <module...>
    local logf="$1"; shift
    local deltas=() m
    for m in "$@"; do [ "$m" = base ] || deltas+=("$m"); done
    [ ${#deltas[@]} -ge 1 ] || return 0
    "${MODFS_SRC}/scripts/05_check.sh" "${deltas[@]}" > "$logf" 2>&1
}

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
