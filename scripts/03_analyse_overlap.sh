#!/usr/bin/env bash
#
# Empirically determine which files need reconciliation when two delta
# modules are composed.
#
#   sudo ./scripts/03_analyse_overlap.sh webserver pytools
#
# Answers three questions with evidence:
#   Q1  Which files appear in BOTH deltas?          -> collision candidates
#   Q2  Of those, which have DIFFERENT content?     -> must be reconciled
#   Q3  Which packages appear in both, same version? -> benign overlap ("X")
#
# Output: a report on stdout and a copy in $LOG_DIR/overlap-<a>-<b>.txt

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${HERE}/config.sh"
source "${HERE}/scripts/lib.sh"
need_root

[ $# -eq 2 ] || die "usage: $0 <moduleA> <moduleB>"
A="$1"; B="$2"
UA="${MOD_DIR}/${A}.upper"
UB="${MOD_DIR}/${B}.upper"
[ -d "$UA" ] || die "missing ${UA}"
[ -d "$UB" ] || die "missing ${UB}"

OUT="${LOG_DIR}/overlap-${A}-${B}.txt"
mkdir -p "$LOG_DIR"
TMP="${BUILD_DIR}/overlap.$$"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

exec > >(tee "$OUT") 2>&1

echo "==============================================================="
echo " OVERLAP ANALYSIS: ${A}  vs  ${B}"
echo " $(date -Is)"
echo "==============================================================="

# ---------------------------------------------------------------------------
echo
echo "### 0. Size of each delta"
echo
for m in "$A" "$B"; do
    u="${MOD_DIR}/${m}.upper"
    n=$(find "$u" -type f 2>/dev/null | wc -l)
    s=$(du -sh "$u" 2>/dev/null | cut -f1)
    printf '  %-14s %6s files, %s raw\n' "$m" "$n" "$s"
done
bs=$(du -sh "${MOD_DIR}/base.dir" 2>/dev/null | cut -f1)
bn=$(find "${MOD_DIR}/base.dir" -type f 2>/dev/null | wc -l)
printf '  %-14s %6s files, %s raw   (parent)\n' "base" "$bn" "$bs"

# ---------------------------------------------------------------------------
echo
echo "### Q1. Files present in BOTH deltas"
echo

find "$UA" -type f 2>/dev/null | sed "s|^${UA}||" | sort > "$TMP/a.files"
find "$UB" -type f 2>/dev/null | sed "s|^${UB}||" | sort > "$TMP/b.files"
comm -12 "$TMP/a.files" "$TMP/b.files" > "$TMP/both.files"

BOTH=$(wc -l < "$TMP/both.files")
echo "  ${BOTH} files appear in both deltas."
echo

if [ "$BOTH" -gt 0 ]; then
    # ---- Q2: same path, same content, or different? -----------------------
    : > "$TMP/identical"; : > "$TMP/differs"
    while IFS= read -r f; do
        if cmp -s "${UA}${f}" "${UB}${f}"; then
            echo "$f" >> "$TMP/identical"
        else
            echo "$f" >> "$TMP/differs"
        fi
    done < "$TMP/both.files"

    NID=$(wc -l < "$TMP/identical")
    NDIF=$(wc -l < "$TMP/differs")

    echo "### Q2. Of those, content comparison"
    echo
    echo "  ${NID} identical  -> BENIGN, last-wins is harmless (duplicate storage only)"
    echo "  ${NDIF} differ     -> MUST BE HANDLED, last-wins loses information"
    echo
    echo "  --- files that DIFFER (the reconciliation set) ---"
    if [ "$NDIF" -eq 0 ]; then
        echo "      (none)"
    else
        while IFS= read -r f; do
            sa=$(stat -c %s "${UA}${f}"); sb=$(stat -c %s "${UB}${f}")
            printf '      %-52s  %8s / %8s bytes\n' "$f" "$sa" "$sb"
        done < "$TMP/differs"
    fi

    echo
    echo "  --- identical duplicates, largest 15 (wasted storage) ---"
    if [ "$NID" -eq 0 ]; then
        echo "      (none)"
    else
        while IFS= read -r f; do
            printf '%s\t%s\n' "$(stat -c %s "${UA}${f}")" "$f"
        done < "$TMP/identical" | sort -rn | head -15 | \
        while IFS=$'\t' read -r s f; do
            printf '      %-52s  %8s bytes\n' "$f" "$s"
        done
        WASTE=$(while IFS= read -r f; do stat -c %s "${UA}${f}"; done \
                < "$TMP/identical" | paste -sd+ | bc)
        echo
        echo "      total duplicated: $(human "${WASTE:-0}")"
    fi
fi

# ---------------------------------------------------------------------------
echo
echo "### Q3. Packages installed by both deltas"
echo

# The delta's own status file lists base + that module's additions.
# Subtracting base's list gives what the module actually added.
status_pkgs() {   # status_pkgs <rootdir>
    local s="$1/var/lib/dpkg/status"
    [ -f "$s" ] || return 0
    awk '/^Package: /{p=$2} /^Version: /{if(p)print p" "$2; p=""}' "$s" | sort
}

status_pkgs "${MOD_DIR}/base.dir" > "$TMP/base.pkgs"
status_pkgs "$UA" > "$TMP/a.pkgs"
status_pkgs "$UB" > "$TMP/b.pkgs"

if [ ! -s "$TMP/a.pkgs" ] || [ ! -s "$TMP/b.pkgs" ]; then
    echo "  (a delta has no copied-up status file - unexpected, investigate)"
else
    comm -13 "$TMP/base.pkgs" "$TMP/a.pkgs" > "$TMP/a.added"
    comm -13 "$TMP/base.pkgs" "$TMP/b.pkgs" > "$TMP/b.added"
    printf '  %s adds %s packages\n' "$A" "$(wc -l < "$TMP/a.added")"
    printf '  %s adds %s packages\n' "$B" "$(wc -l < "$TMP/b.added")"
    echo

    cut -d' ' -f1 "$TMP/a.added" | sort > "$TMP/a.names"
    cut -d' ' -f1 "$TMP/b.added" | sort > "$TMP/b.names"
    comm -12 "$TMP/a.names" "$TMP/b.names" > "$TMP/shared.names"
    NSH=$(wc -l < "$TMP/shared.names")

    echo "  ${NSH} packages installed by BOTH (this is the real 'X' set)"
    echo
    if [ "$NSH" -gt 0 ]; then
        SKEW=0
        while IFS= read -r p; do
            va=$(grep -m1 "^${p} " "$TMP/a.added" | cut -d' ' -f2)
            vb=$(grep -m1 "^${p} " "$TMP/b.added" | cut -d' ' -f2)
            if [ "$va" = "$vb" ]; then
                printf '      %-34s %-22s  SAME (benign)\n' "$p" "$va"
            else
                printf '      %-34s %-22s  vs %-22s  *** SKEW ***\n' "$p" "$va" "$vb"
                SKEW=$((SKEW+1))
            fi
        done < "$TMP/shared.names"
        echo
        if [ "$SKEW" -eq 0 ]; then
            echo "      No version skew. Pinning to snapshot ${SNAPSHOT_ID} held."
        else
            echo "      ${SKEW} packages differ in version -- pinning was violated!"
        fi
    fi
fi

# ---------------------------------------------------------------------------
echo
echo "### Q4. dpkg status stanza counts (the catalogue problem)"
echo
for pair in "base:${MOD_DIR}/base.dir" "${A}:${UA}" "${B}:${UB}"; do
    n="${pair%%:*}"; d="${pair#*:}"
    c=$(grep -c '^Package: ' "${d}/var/lib/dpkg/status" 2>/dev/null || echo 0)
    printf '  %-14s status lists %s packages\n' "$n" "$c"
done
echo
echo "  On merge, ONE of these files wins. Any package listed only in the"
echo "  loser becomes invisible to apt, though its files remain on disk."

echo
echo "==============================================================="
echo " report saved: ${OUT}"
echo "==============================================================="
