#!/usr/bin/env bash
# Shared helpers. Sourced by every build script.
# Main job: tear down every mount, in reverse order, even if the script dies
# or is interrupted.

set -uo pipefail

log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

need_root() { [ "$(id -u)" -eq 0 ] || die "must run as root (use sudo)"; }

# ---- identifier and path safety -------------------------------------------
# Module and run names reach file paths, mount options and recursive deletes
# (`--name ../../modules` in a root-run harness would delete the artefact
# store), so every entry point validates them.
#
# Allowlist, not denylist: [A-Za-z0-9][A-Za-z0-9._-]* cannot contain a slash
# or begin with a dot, so it cannot be "." or ".." or traverse.
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

# Prove a path is a direct child of a fixed root before anything destructive
# touches it. The canonical path is printed so the caller uses the proven one.
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
    local p="$1" canon hit
    [ -e "$p" ] || return 0
    [ -L "$p" ] && die "refusing to touch ${p}: it is a symlink"
    # Compare canonical paths: a mount is recorded under its real path, so a
    # relative or symlinked argument would never match.
    canon="$(cd "$p" 2>/dev/null && pwd -P)" || canon="$p"
    # Field 5 of /proc/self/mountinfo is the mount point (field 2 is the
    # parent mount ID). Matching "$canon/" as a prefix also catches mounts
    # nested below the target.
    hit=$(awk -v d="$canon" '
        { mp = $5 }
        mp == d || index(mp, d "/") == 1 { print mp; exit }
    ' /proc/self/mountinfo 2>/dev/null)
    [ -z "$hit" ] || die "refusing to touch ${p}: mount present at ${hit}"
    return 0
}

# The only sanctioned recursive delete: containment-proven, mount-checked.
safe_rm_rf() {           # safe_rm_rf <root> <name>
    local target
    target="$(safe_child "$1" "$2")" || exit 1
    require_no_mounts "$target"
    rm -rf -- "$target"
}

# ---- identity policy: prevent class 7 ------------------------------------
# Debian allocates dynamic system accounts from 100-999 on every build, so two
# independently built siblings can give one number to different names. Each
# module gets a disjoint UID window, which prevents the collision; the class-7
# check in 05 verifies that the policy held.
uid_range_for() {        # uid_range_for <module> -> "START END"
    python3 - "${SPEC_DIR}/uid-ranges.yaml" "$1" <<'URPY'
import sys, yaml
spec, name = sys.argv[1], sys.argv[2]
try:
    d = yaml.safe_load(open(spec, encoding='utf-8')) or {}
except Exception as exc:
    sys.stderr.write("cannot read %s: %s\n" % (spec, exc)); sys.exit(2)
r = (d.get('ranges') or {}).get(name)
if r is None:
    sys.stderr.write(
        "no UID range assigned to '%s' in %s.\n"
        "The file is append-only: add it with the next free start "
        "(see the trailing comment) and never renumber an existing entry.\n"
        % (name, spec))
    sys.exit(2)
print("%d %d" % (int(r), int(r) + int(d.get('width', 100)) - 1))
URPY
}

_idpol_set_eq() {        # <file> <key> <value>   KEY=VALUE form
    sed -i -E "/^[[:space:]]*#?[[:space:]]*${2}[[:space:]]*=/d" "$1"
    printf '%s=%s\n' "$2" "$3" >> "$1"
}
_idpol_set_sp() {        # <file> <key> <value>   KEY VALUE form
    sed -i -E "/^[[:space:]]*#?[[:space:]]*${2}[[:space:]]+/d" "$1"
    printf '%s %s\n' "$2" "$3" >> "$1"
}

# Both files are needed: adduser.conf governs `adduser --system`, login.defs
# governs `useradd -r`, and maintainer scripts use both.
write_identity_policy() {   # write_identity_policy <root> <start> <end> <backupdir>
    local r="$1" lo="$2" hi="$3" bk="$4" f
    mkdir -p "$bk"
    for f in etc/adduser.conf etc/login.defs; do
        [ -f "$r/$f" ] || die "missing $f in the merged view"
        cp -a "$r/$f" "$bk/$(basename "$f").orig"
    done
    _idpol_set_eq "$r/etc/adduser.conf" FIRST_SYSTEM_UID "$lo"
    _idpol_set_eq "$r/etc/adduser.conf" LAST_SYSTEM_UID  "$hi"
    _idpol_set_eq "$r/etc/adduser.conf" FIRST_SYSTEM_GID "$lo"
    _idpol_set_eq "$r/etc/adduser.conf" LAST_SYSTEM_GID  "$hi"
    _idpol_set_sp "$r/etc/login.defs" SYS_UID_MIN "$lo"
    _idpol_set_sp "$r/etc/login.defs" SYS_UID_MAX "$hi"
    _idpol_set_sp "$r/etc/login.defs" SYS_GID_MIN "$lo"
    _idpol_set_sp "$r/etc/login.defs" SYS_GID_MAX "$hi"
}

# The policy is build scaffolding, not module content, so the original files
# are restored. Restored, not deleted: deleting a file that exists in the
# lower layer would leave a whiteout that hides base's copy.
restore_identity_policy() { # restore_identity_policy <root> <backupdir>
    local r="$1" bk="$2"
    [ -f "$bk/adduser.conf.orig" ] && cp -a "$bk/adduser.conf.orig" "$r/etc/adduser.conf"
    [ -f "$bk/login.defs.orig" ]   && cp -a "$bk/login.defs.orig"   "$r/etc/login.defs"
    return 0
}

# Clear a scratch workspace and prove it is empty. As a non-root user, rm -rf
# fails silently on files a previous sudo run created, and stale results would
# then be reused as if fresh.
reset_workdir() {        # reset_workdir <dir>
    local d="$1" left
    require_no_mounts "$d"
    rm -rf -- "$d" 2>/dev/null || true
    if [ -e "$d" ]; then
        left=$(find "$d" -mindepth 1 2>/dev/null | wc -l)
        [ "$left" -eq 0 ] || die "cannot clear workspace ${d}: ${left} file(s) remain
       they are probably owned by a previous sudo run -- remove them and retry,
       otherwise this run would silently reuse stale results"
    fi
    mkdir -p "$d" || die "cannot create workspace ${d}"
}

# ---- admission: integrity, then tier-1 ------------------------------------
# The pipeline order is a rule:
#     bundle integrity -> tier-1 admission -> compose/reconcile -> tier-2
# A physical composition proves structure, never package semantics, so tier 2
# must not report PASS for a set tier 1 rejected.

# Every artefact must match the size and digest its manifest records, and the
# manifest's content fields must match the digest it carries
# (`binding.fields_sha256`, written by 06_extract_metadata.sh over exactly the
# fields the checks read). Rehashing a few kilobytes of JSON is cheap enough
# to run here and in tier 1; re-deriving from the artefact is not.
#
# Integrity, not authenticity: the digest is inside the document it protects.
# See 06_extract_metadata.sh's header.
verify_bundle() {        # verify_bundle <module...>
    python3 - "$MOD_DIR" "$@" <<'VBPY'
import hashlib, json, os, sys
mod_dir, mods = sys.argv[1], sys.argv[2:]

sys.path.insert(0, os.path.join(os.environ['MODFS_SRC'], 'scripts'))
from manifest_binding import validate_manifest, load_sidecar

def file_sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()

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
    if file_sha256(sq) != art['sha256']:
        print("  integrity: %s DIGEST MISMATCH" % m); bad += 1; continue

    try:
        validate_manifest(doc)
        load_sidecar(doc, os.path.join(mod_dir, m + '.files.json.zst'), m)
    except ValueError as exc:
        print("  integrity: %s BINDING MISMATCH: %s" % (m, exc))
        bad += 1
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

# A signal handler that returns lets the script carry on, writing into what is
# no longer a merged overlay and possibly exiting 0. So clean up, restore the
# default disposition and re-raise: the process dies with 130/143.
on_signal() {            # on_signal <SIGNAME>
    local sig="$1"
    unmount_all
    trap - EXIT "$sig"
    kill -s "$sig" $$
}
trap cleanup EXIT
trap 'on_signal INT'  INT
trap 'on_signal TERM' TERM

# ---- chroot plumbing ------------------------------------------------------
# Some maintainer scripts read /proc and /sys and fail quietly without them,
# leaving an incomplete module, so all four are bound.
mount_chroot_fs() {      # mount_chroot_fs <root>
    local r="$1"
    mkdir -p "$r"/{proc,sys,dev,dev/pts,run}
    do_mount -t proc  proc  "$r/proc"
    do_mount -t sysfs sys   "$r/sys"
    do_mount --bind /dev     "$r/dev"
    do_mount --bind /dev/pts "$r/dev/pts"
    # Make every mount private, or unmounting it also unmounts the host's copy:
    # systemd mounts / and /dev shared, so a --bind joins the original's peer
    # group and unmount events propagate. Losing the host's /dev/pts this way
    # breaks every later pty allocation ("sudo: unable to allocate pty").
    local m
    for m in "$r/proc" "$r/sys" "$r/dev" "$r/dev/pts"; do
        mount --make-rprivate "$m" 2>/dev/null \
            || warn "cannot make ${m} private; unmounting it may affect the host"
    done
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

# Everything write_chroot_policy created must come back out; otherwise
# APT::Install-Recommends "false" would ship inside every artefact.
remove_chroot_policy() {
    rm -f "$1/usr/sbin/policy-rc.d"
    rm -f "$1/etc/apt/apt.conf.d/99modfs"
}

in_chroot() {            # in_chroot <root> <command...>
    local r="$1"; shift
    DEBIAN_FRONTEND=noninteractive LC_ALL=C LANG=C \
        chroot "$r" /usr/bin/env \
        DEBIAN_FRONTEND=noninteractive LC_ALL=C LANG=C \
        "$@"
}

# ---- sources.list against the pinned snapshot -----------------------------
# The snapshot ID goes in the URL path, not an apt option: debootstrap does not
# understand [snapshot=], and jammy's apt 2.4.5 predates --snapshot.
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
