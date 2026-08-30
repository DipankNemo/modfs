#!/usr/bin/env bash
#
# Reproducibility diagnostic. Answers ONE question when two builds of the same
# module produce different bytes:
#
#   H1  the build TREES genuinely differ  -> some file still needs excluding
#                                            or normalising; it names the file
#   H2  the trees are identical but mksquashfs emits different bytes
#                                         -> layout/ordering, not content
#
#   sudo ./tests/repro_check.sh <name> <pkg> [pkg...]
#   sudo ./tests/repro_check.sh webserver nginx
#
# Costs two delta builds plus ~150 MB of scratch under $BUILD_DIR. Test A
# needs no rebuild at all and often answers the question on its own.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${HERE}/config.sh"
source "${HERE}/scripts/lib.sh"
need_root

MOD_VERSION=""
if [ "${1:-}" = "--version" ]; then
    [ $# -ge 2 ] || die "--version needs a value"
    MOD_VERSION="$2"; shift 2
fi

[ $# -ge 1 ] || die "usage: $0 [--version V] <name> [pkg...]   (packages required unless name is 'base')"
NAME="$1"; shift
PKGS=("$@")

W="${BUILD_DIR}/repro-${NAME}"
SQSH="${MOD_DIR}/${NAME}.sqsh"

# base is not a delta: it lives in <name>.dir, is built by stage 01, and has
# to be torn down before each rebuild because 01 is idempotent on its stamp.
if [ "$NAME" = "base" ]; then
    TREE="${MOD_DIR}/${NAME}.dir"
    build_once() {
        rm -rf "${MOD_DIR}/${NAME}.dir" "${MOD_DIR}/${NAME}.sqsh"
        local a=(); [ -n "$MOD_VERSION" ] && a+=(--version "$MOD_VERSION")
        "${HERE}/scripts/01_build_base.sh" "${a[@]}" "${PKGS[@]}"
    }
    warn "two full base builds -- expect this to take 10-15 minutes"
else
    [ ${#PKGS[@]} -ge 1 ] || die "packages required for a delta module"
    TREE="${MOD_DIR}/${NAME}.upper"
    build_once() {
        local a=(); [ -n "$MOD_VERSION" ] && a+=(--version "$MOD_VERSION")
        "${HERE}/scripts/02_build_delta.sh" "${a[@]}" "$NAME" "${PKGS[@]}"
    }
fi

rm -rf "$W"; mkdir -p "$W"

# Exactly the invocation 02_build_delta.sh uses. If these ever drift apart the
# diagnostic is measuring the wrong thing, so keep them in step.
squash() {              # squash <tree> <out>
    # shellcheck disable=SC2086
    mksquashfs "$1" "$2" \
        -comp "$SQUASH_COMP" -Xcompression-level "$SQUASH_LEVEL" \
        -mkfs-time "$SOURCE_EPOCH" -all-time "$SOURCE_EPOCH" \
        -xattrs-exclude "$SQUASH_XATTR_EXCLUDE" \
        -noappend -no-progress -e $SQUASH_EXCLUDES >> "$W/mksquashfs.log" 2>&1 \
        || die "mksquashfs failed, see $W/mksquashfs.log"
}
sha() { sha256sum "$1" | cut -d' ' -f1; }

# ---------------------------------------------------------------- A
# Is mksquashfs deterministic for ONE fixed tree? No rebuild needed, so this
# is nearly free -- and if it fails, the tree was never the problem.
[ -d "$TREE" ] || die "no ${TREE} -- build ${NAME} once first"

log "A. squashing the SAME tree twice (no rebuild)"
squash "$TREE" "$W/a1.sqsh"; A1=$(sha "$W/a1.sqsh")
squash "$TREE" "$W/a2.sqsh"; A2=$(sha "$W/a2.sqsh")
log "     ${A1:0:48}"
log "     ${A2:0:48}"
if [ "$A1" != "$A2" ]; then
    log ""
    log "  VERDICT: H2 -- mksquashfs is NOT deterministic for a fixed tree."
    log "  The build tree is not the cause. Next step: re-run these two"
    log "  squashes with -processors 1 to test whether it is thread-dependent."
    exit 1
fi
log "     identical -- deterministic for a fixed tree  [OK]"

# ---------------------------------------------------------------- B
log ""
log "B. building ${NAME} twice (${PKGS[*]})"
build_once > "$W/build1.log" 2>&1 || die "build 1 failed, see $W/build1.log"
cp -a "$TREE" "$W/upper1"
cp "$SQSH" "$W/b1.sqsh"
build_once > "$W/build2.log" 2>&1 || die "build 2 failed, see $W/build2.log"
cp "$SQSH" "$W/b2.sqsh"

B1=$(sha "$W/b1.sqsh"); B2=$(sha "$W/b2.sqsh")
log "     ${B1:0:48}"
log "     ${B2:0:48}"
if [ "$B1" = "$B2" ]; then
    log ""
    log "  REPRODUCIBLE -- two full builds produced identical bytes."
    rm -rf "$W/upper1"
    exit 0
fi
log "     DIFFER"

# ---------------------------------------------------------------- C
log ""
log "C. diagnosing"

log "  C1. files differing between the two build trees:"
diff -rq --no-dereference "$W/upper1" "$TREE" 2>/dev/null > "$W/tree-diff.raw"
sed -n "s#^Files ${W}/upper1/\(.*\) and .* differ\$#\1#p" "$W/tree-diff.raw" \
    > "$W/tree-diff.txt"
# "Only in <dir>: <name>" loses the path, and the file may be missing from
# either side, so rebuild the relative path for all four shapes.
sed -n -e "s#^Only in ${W}/upper1/\(.*\): \(.*\)\$#\1/\2#p" \
       -e "s#^Only in ${W}/upper1: \(.*\)\$#\1#p" \
       -e "s#^Only in ${TREE}/\(.*\): \(.*\)\$#\1/\2#p" \
       -e "s#^Only in ${TREE}: \(.*\)\$#\1#p" \
       "$W/tree-diff.raw" >> "$W/tree-diff.txt"

UNEXPLAINED=0
if [ ! -s "$W/tree-diff.txt" ]; then
    log "      (none -- the trees are byte-identical)"
else
    while read -r rel; do
        verdict="NOT EXCLUDED  <-- this is a real cause"
        for e in $SQUASH_EXCLUDES; do
            case "$rel" in "$e"|"$e"/*) verdict="excluded, harmless"; break ;; esac
        done
        case "$verdict" in "NOT EXCLUDED"*) UNEXPLAINED=$((UNEXPLAINED+1)) ;; esac
        printf '      %-46s %s\n' "$rel" "$verdict"
    done < "$W/tree-diff.txt"
fi

log ""
log "  C2. are the two IMAGES logically identical?"
unsquashfs -ll "$W/b1.sqsh" > "$W/ll1" 2>/dev/null
unsquashfs -ll "$W/b2.sqsh" > "$W/ll2" 2>/dev/null
LISTING_SAME=0; diff -q "$W/ll1" "$W/ll2" >/dev/null 2>&1 && LISTING_SAME=1

rm -rf "$W/x1" "$W/x2"
unsquashfs -n -d "$W/x1" "$W/b1.sqsh" >/dev/null 2>&1
unsquashfs -n -d "$W/x2" "$W/b2.sqsh" >/dev/null 2>&1
diff -rq --no-dereference "$W/x1" "$W/x2" > "$W/img-diff.txt" 2>&1
CONTENT_SAME=0; [ -s "$W/img-diff.txt" ] || CONTENT_SAME=1
rm -rf "$W/x1" "$W/x2"

log "      listing identical : $([ $LISTING_SAME -eq 1 ] && echo yes || echo NO)"
log "      content identical : $([ $CONTENT_SAME -eq 1 ] && echo yes || echo NO)"
[ $CONTENT_SAME -eq 1 ] || sed 's/^/        /' "$W/img-diff.txt" | head -10

log ""
log "  C3. first differing byte:"
cmp "$W/b1.sqsh" "$W/b2.sqsh" 2>&1 | sed 's/^/      /'

# ---------------------------------------------------------------- verdict
# ---- C4/C5: the two things squashfs stores that diff and the listing miss
# Both need root: trusted.overlay.* lives in a namespace only CAP_SYS_ADMIN
# can read, which is exactly why an unprivileged comparison sees nothing.
log ""
log "  C4. extended attributes (trusted.overlay.* included):"
( cd "$W/upper1" && getfattr -Rd -m- -P . 2>/dev/null ) > "$W/xattr1.txt"
( cd "$TREE"    && getfattr -Rd -m- -P . 2>/dev/null ) > "$W/xattr2.txt"
XATTR_SAME=0
if diff -q "$W/xattr1.txt" "$W/xattr2.txt" >/dev/null 2>&1; then
    XATTR_SAME=1
    log "      identical ($(grep -c '^# file:' "$W/xattr1.txt") files carry xattrs)"
else
    diff "$W/xattr1.txt" "$W/xattr2.txt" > "$W/xattr-diff.txt"
    log "      DIFFER -- $(grep -c '^[<>]' "$W/xattr-diff.txt") line(s):"
    head -20 "$W/xattr-diff.txt" | sed 's/^/        /'
fi

log ""
log "  C5. link counts and file types:"
( cd "$W/upper1" && find . -printf '%n %y %P\n' | sort ) > "$W/links1.txt"
( cd "$TREE"    && find . -printf '%n %y %P\n' | sort ) > "$W/links2.txt"
LINKS_SAME=0
if diff -q "$W/links1.txt" "$W/links2.txt" >/dev/null 2>&1; then
    LINKS_SAME=1; log "      identical"
else
    log "      DIFFER:"
    diff "$W/links1.txt" "$W/links2.txt" | head -20 | sed 's/^/        /'
fi

log ""
if [ "$UNEXPLAINED" -gt 0 ]; then
    log "  VERDICT: H1 -- ${UNEXPLAINED} file(s) differ that are NOT excluded."
    log "  Those files are the cause. Exclude, drop or normalise them."
elif [ $LISTING_SAME -eq 1 ] && [ $CONTENT_SAME -eq 1 ] && [ $XATTR_SAME -eq 0 ]; then
    log "  VERDICT: H2a -- XATTRS. The images are logically identical and the"
    log "  content matches, but the extended attributes differ. See"
    log "  ${W}/xattr-diff.txt for which files and which attribute."
elif [ $LISTING_SAME -eq 1 ] && [ $CONTENT_SAME -eq 1 ] && [ $LINKS_SAME -eq 0 ]; then
    log "  VERDICT: H2b -- HARD LINKS. Content and xattrs match but link counts"
    log "  differ, so mksquashfs grouped hard links differently between builds."
elif [ $LISTING_SAME -eq 1 ] && [ $CONTENT_SAME -eq 1 ]; then
    log "  VERDICT: H2c -- content, xattrs and link counts ALL match, yet the"
    log "  bytes differ. That points at mksquashfs internal ordering. Compare"
    log "  the superblock table offsets of ${W}/b1.sqsh and b2.sqsh to see"
    log "  which section moved."
else
    log "  VERDICT: the trees agree on everything not excluded, but the"
    log "  extracted images differ. See ${W}/img-diff.txt"
fi
log ""
log "  evidence kept in ${W} (rm -rf it when done)"
exit 1
