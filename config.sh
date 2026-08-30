# Central configuration. Every script sources this file.
# Change values here, never inside the individual scripts.

# ---- Archive pinning -------------------------------------------------------
# Snapshot ID format: YYYYMMDDTHHMMSSZ (UTC). Any time after 2023-03-01.
# This single value makes every build reproducible. Do not change it during
# a build generation, or you reintroduce version skew between siblings.
SNAPSHOT_ID="20260701T000000Z"
SNAPSHOT_BASE="https://snapshot.ubuntu.com/ubuntu/${SNAPSHOT_ID}"

# Reproducibility: mksquashfs stamps the superblock with the wall clock and
# preserves every file's mtime, so two builds of the same module produce
# different bytes for reasons that have nothing to do with content. Both are
# pinned to a fixed epoch DERIVED FROM THE SNAPSHOT ID -- the same value that
# already makes the package set reproducible, so there is no second thing to
# keep in sync. Bump the snapshot and this moves with it.
_snap_ts="${SNAPSHOT_ID:0:4}-${SNAPSHOT_ID:4:2}-${SNAPSHOT_ID:6:2} ${SNAPSHOT_ID:9:2}:${SNAPSHOT_ID:11:2}:${SNAPSHOT_ID:13:2} UTC"
SOURCE_EPOCH="$(date -u -d "$_snap_ts" +%s 2>/dev/null)"
if [ -z "$SOURCE_EPOCH" ]; then
    echo "config.sh: cannot derive SOURCE_EPOCH from SNAPSHOT_ID='${SNAPSHOT_ID}'" >&2
    echo "           expected format YYYYMMDDTHHMMSSZ" >&2
    exit 1
fi
unset _snap_ts

SUITE="jammy"
ARCH="amd64"
COMPONENTS="main universe restricted multiverse"

# ---- Layout ---------------------------------------------------------------
ROOT="${MODFS_ROOT:-/srv/modfs}"

SPEC_DIR="${ROOT}/specs"          # module definitions, hand written
MOD_DIR="${ROOT}/modules"         # built .sqsh + .json artefacts
BUILD_DIR="${ROOT}/build"         # scratch: chroots, overlay dirs
IMAGE_DIR="${ROOT}/images"        # final .img files
LOG_DIR="${ROOT}/logs"

# ---- Build options --------------------------------------------------------
# zstd is roughly 10x faster than xz to compress with a negligible size
# penalty at this scale. xz was the main time sink in the earlier prototype.
SQUASH_COMP="zstd"
SQUASH_LEVEL="15"

# Paths that must never end up inside a module artefact.
#
# The apt/dpkg logs are build byproducts, not module content, and they
# are the last thing standing between us and byte-identical artefacts: three
# of them record wall-clock timestamps, so two builds of the same module
# differ no matter what mksquashfs is told about times. Dropping them costs
# 20 KB of 20 568 and resolves one row of the class-5 table in ARCHITECTURE
# section 4 -- overlayfs copies base's dpkg.log UP into every delta, so
# without this every sibling ships its own divergent copy of the same log.
# Note these are FILES, not directories: var/log/apt and var/log/nginx stay,
# which nginx needs at runtime.
# aux-cache is ldconfig's own scratch index. It stores each library's INODE
# NUMBER, so it differs between two builds of the same module even when every
# byte of every library is identical -- confirmed by a real double build of
# webserver, where it was the ONLY remaining difference. ldconfig regenerates
# it, so it is a byproduct too. Excluded as a FILE: /var/cache/ldconfig stays,
# and /etc/ld.so.cache is deliberately NOT here -- the composed system needs
# it, and it is regenerated at compose time instead (ARCHITECTURE section 4).
SQUASH_EXCLUDES="proc sys dev run tmp var/tmp var/cache/apt/archives var/lib/apt/lists \
                 var/log/dpkg.log var/log/apt/history.log var/log/apt/term.log \
                 var/log/apt/eipp.log.xz var/cache/ldconfig/aux-cache \
                 var/log/alternatives.log var/log/bootstrap.log"

# Extended attributes to strip from artefacts. OverlayFS writes four kinds of
# xattr into an upperdir, and squashing the upperdir captures its BOOKKEEPING
# as well as the file diff:
#
#   trusted.overlay.opaque    "y"  -- SEMANTIC. A directory replaced wholesale.
#                                     Assumption B in ARCHITECTURE section 3
#                                     exists to prove this survives. Keep.
#   trusted.overlay.redirect  path -- SEMANTIC. Records a rename. Keep.
#   trusted.overlay.impure    "y"  -- constant, harmless either way. Keep.
#   trusted.overlay.uuid      rand -- an RFC 4122 v4 UUID the kernel generates
#                                     per mount. Pure instance state.
#   trusted.overlay.origin    fh   -- an encoded file handle holding the LOWER
#                                     filesystem's UUID, inode number and
#                                     generation. Host-specific by construction:
#                                     it changes whenever base is rebuilt and
#                                     can never agree across two machines.
#
# The last two are why artefacts were not reproducible. This is an EXTENDED
# regex -- verified, because the basic-regex spelling '\(a\|b\)' matches
# nothing here and would silently strip no attributes at all.
SQUASH_XATTR_EXCLUDE='^trusted\.overlay\.(uuid|origin)$'

export SNAPSHOT_ID SNAPSHOT_BASE SOURCE_EPOCH SUITE ARCH COMPONENTS
export SQUASH_XATTR_EXCLUDE
export ROOT SPEC_DIR MOD_DIR BUILD_DIR IMAGE_DIR LOG_DIR
export SQUASH_COMP SQUASH_LEVEL SQUASH_EXCLUDES
