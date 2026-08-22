# Central configuration. Every script sources this file.
# Change values here, never inside the individual scripts.

# ---- Archive pinning -------------------------------------------------------
# Snapshot ID format: YYYYMMDDTHHMMSSZ (UTC). Any time after 2023-03-01.
# This single value makes every build reproducible. Do not change it during
# a build generation, or you reintroduce version skew between siblings.
SNAPSHOT_ID="20260701T000000Z"
SNAPSHOT_BASE="https://snapshot.ubuntu.com/ubuntu/${SNAPSHOT_ID}"

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

# Directories that must never end up inside a module artefact.
SQUASH_EXCLUDES="proc sys dev run tmp var/tmp var/cache/apt/archives var/lib/apt/lists"

export SNAPSHOT_ID SNAPSHOT_BASE SUITE ARCH COMPONENTS
export ROOT SPEC_DIR MOD_DIR BUILD_DIR IMAGE_DIR LOG_DIR
export SQUASH_COMP SQUASH_LEVEL SQUASH_EXCLUDES
