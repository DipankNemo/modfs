#!/usr/bin/env bash
#
# Step 1 of 2: convert every PDF to text (keeping its current name), then
# print a digest of what each one actually is. Nothing is renamed yet.
#
#   cd ~/modfs/thesis/refs/pdf
#   bash extract_and_digest.sh | tee /tmp/refs-digest.txt
#
# Paste the digest back to Claude; the verified rename mapping comes from
# what the papers say about themselves, not from a guess at the filename.

set -uo pipefail
TXTDIR="../txt"
mkdir -p "$TXTDIR"
shopt -s nullglob

echo "=== CONVERTING ==="
for f in *.pdf; do
    out="$TXTDIR/${f%.pdf}.txt"
    if pdftotext -layout "$f" "$out" 2>/dev/null; then
        bytes=$(stat -c %s "$out" 2>/dev/null || echo 0)
        if [ "$bytes" -lt 2000 ]; then
            printf '  SCANNED?  %8s B  %s\n' "$bytes" "$f"
        else
            printf '  ok        %8s B  %s\n' "$bytes" "$f"
        fi
    else
        printf '  FAILED               %s\n' "$f"
    fi
done

echo
echo "=== DIGEST ==="
echo "(anything marked SCANNED? above needs OCR: ocrmypdf in.pdf out.pdf)"

n=0
for f in *.pdf; do
    n=$((n+1))
    printf '\n--- [%02d] %s\n' "$n" "$f"
    pages=$(pdfinfo "$f" 2>/dev/null | awk '/^Pages:/{print $2}')
    printf '    pages: %s   size: %s\n' "${pages:-?}" "$(du -h "$f" | cut -f1)"

    # Embedded metadata, when the publisher set it, is often the cleanest source.
    meta_t=$(pdfinfo "$f" 2>/dev/null | sed -n 's/^Title:[[:space:]]*//p')
    meta_a=$(pdfinfo "$f" 2>/dev/null | sed -n 's/^Author:[[:space:]]*//p')
    [ -n "${meta_t:-}" ] && printf '    meta-title:  %s\n' "$meta_t"
    [ -n "${meta_a:-}" ] && printf '    meta-author: %s\n' "$meta_a"

    # First page as printed: title, authors, venue line.
    printf '    first lines of page 1:\n'
    pdftotext -l 1 -layout "$f" - 2>/dev/null \
        | grep -v '^[[:space:]]*$' | head -12 | cut -c1-110 | sed 's/^/      | /'
done

echo
echo "=== END ==="
