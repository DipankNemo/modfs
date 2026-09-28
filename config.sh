# Central configuration. Every script sources this file.
# Change values here, never inside the individual scripts.

# ---- Archive pinning -------------------------------------------------------
# Snapshot ID, YYYYMMDDTHHMMSSZ (UTC), any time after 2023-03-01. It pins the
# package set of a whole generation: base and every sibling must share it, or
# their package versions drift apart. Override it only for a complete
# generation in a separate MODFS_ROOT, or for the negative control.
SNAPSHOT_ID="${MODFS_SNAPSHOT_ID:-20260701T000000Z}"
SNAPSHOT_BASE="https://snapshot.ubuntu.com/ubuntu/${SNAPSHOT_ID}"

# mksquashfs records the wall clock and every file's mtime. Both are pinned to
# this epoch, derived from the snapshot ID so there is no second value to keep
# in sync.
_snap_ts="${SNAPSHOT_ID:0:4}-${SNAPSHOT_ID:4:2}-${SNAPSHOT_ID:6:2} ${SNAPSHOT_ID:9:2}:${SNAPSHOT_ID:11:2}:${SNAPSHOT_ID:13:2} UTC"
SOURCE_EPOCH="$(date -u -d "$_snap_ts" +%s 2>/dev/null)"
if [ -z "$SOURCE_EPOCH" ]; then
    echo "config.sh: cannot derive SOURCE_EPOCH from SNAPSHOT_ID='${SNAPSHOT_ID}'" >&2
    echo "           expected format YYYYMMDDTHHMMSSZ" >&2
    exit 1
fi
unset _snap_ts

# Overridable so a whole generation can be built for another Ubuntu release
# (e.g. noble) in a separate tree without editing any script. The catalogue
# and all published measurements use jammy.
SUITE="${MODFS_SUITE:-jammy}"
ARCH="amd64"
COMPONENTS="main universe restricted multiverse"

# ---- Layout ---------------------------------------------------------------
# Source, including the hand-written module catalogue in specs/, lives in the
# git repo. Artefacts live under $ROOT and are never committed.
MODFS_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPEC_DIR="${MODFS_SPEC_DIR:-${MODFS_SRC}/specs}"   # hand written, in git

ROOT="${MODFS_ROOT:-/srv/modfs}"

MOD_DIR="${ROOT}/modules"         # built .sqsh + .json artefacts
# Overridable so unprivileged checks (tier 1, subset search) can read the real
# artefacts without write access to a scratch directory a sudo run created.
BUILD_DIR="${MODFS_BUILD_DIR:-${ROOT}/build}"   # scratch: chroots, overlay dirs
IMAGE_DIR="${ROOT}/images"        # final .img files
LOG_DIR="${ROOT}/logs"

# Run bundles are evidence and outlive BUILD_DIR, which is disposable. A run
# directory is timestamped and never reused or overwritten; a name collision
# is an error.
RESULTS_DIR="${ROOT}/results"

# ---- Module catalogue -----------------------------------------------------
# The evaluation builds many modules and checks all pairs and triples, so
# modules are kept small. A module over this size is reported, not rejected.
MODULE_MAX_MB="50"

# ---- Build options --------------------------------------------------------
# zstd compresses roughly 10x faster than xz, at a negligible size cost here.
SQUASH_COMP="zstd"
SQUASH_LEVEL="15"

# Paths that must never end up inside a module artefact.
#
# The apt/dpkg logs are build byproducts with wall-clock timestamps, so they
# make two builds of one module differ; overlayfs would also copy base's
# dpkg.log up into every delta. They are excluded as files, not directories:
# var/log/apt and var/log/nginx stay, and nginx needs the latter at runtime.
# aux-cache is ldconfig's scratch index. It records inode numbers, so it
# differs between otherwise identical builds, and ldconfig regenerates it.
# /etc/ld.so.cache is not excluded: the composed system needs it, and it is
# regenerated at compose time.
SQUASH_EXCLUDES="proc sys dev run tmp var/tmp var/cache/apt/archives var/lib/apt/lists \
                 var/log/dpkg.log var/log/apt/history.log var/log/apt/term.log \
                 var/log/apt/eipp.log.xz var/cache/ldconfig/aux-cache \
                 var/log/alternatives.log var/log/bootstrap.log"

# Extended attributes to strip from artefacts. Squashing an overlay upperdir
# captures overlayfs's own bookkeeping xattrs as well as the file diff:
#
#   trusted.overlay.opaque    "y"  -- strip. Opaque only matters when a lower
#                                     layer has content in the directory. At
#                                     build time none of these directories
#                                     exist in base; at compose time the lower
#                                     layers include sibling modules, and the
#                                     marker would hide their files.
#                                     02_build_delta.sh re-checks the premise on
#                                     every build (parent is base, no whiteouts).
#   trusted.overlay.redirect  path -- records a rename. Keep.
#   trusted.overlay.impure    "y"  -- constant, harmless. Keep.
#   trusted.overlay.uuid      rand -- a random UUID per mount. Strip.
#   trusted.overlay.origin    fh   -- a file handle for the lower filesystem
#                                     (UUID, inode, generation). Host-specific,
#                                     and changes whenever base is rebuilt. Strip.
#
# This is an extended regex; the basic spelling '\(a\|b\)' would match nothing
# and silently strip no attributes.
SQUASH_XATTR_EXCLUDE='^trusted\.overlay\.(uuid|origin|opaque)$'

export SNAPSHOT_ID SNAPSHOT_BASE SOURCE_EPOCH SUITE ARCH COMPONENTS
export SQUASH_XATTR_EXCLUDE
export MODFS_SRC ROOT SPEC_DIR MOD_DIR BUILD_DIR IMAGE_DIR LOG_DIR RESULTS_DIR
export SQUASH_COMP SQUASH_LEVEL SQUASH_EXCLUDES MODULE_MAX_MB
