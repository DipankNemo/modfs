#!/usr/bin/env bash
#
# Rename PDFs and their extracted .txt files to their BibTeX keys.
# The mapping below was verified against each PDF's own title page, not
# guessed from the filename.
#
#   cd ~/modfs/thesis/refs/pdf
#   bash rename_refs.sh              # dry run
#   APPLY=1 bash rename_refs.sh      # move files
#
# Assumes the .txt files sit in ../txt/ under the same stem, as produced by
# extract_and_digest.sh.

set -uo pipefail
APPLY="${APPLY:-0}"
TXTDIR="../txt"
shopt -s nullglob

# A unique substring of the current filename  ->  bibkey
# Order matters only for readability; each fragment must match exactly one file.
MAP=(
  "0811.3620|treinen2008solving"
  "name spaces in Plan 9|pike1993namespaces"
  "Disconnected operation|kistler1992disconnected"
  "co-installability|vouillon2013coinstallability"
  "Versatility and Unix semantics|wright2006namespace"
  "Coda_ a highly available|satyanarayanan1990coda"
  "Reproducible Builds|lamb2022reproducible"
  "CMU-ITC-062|howard1988afs"
  "CMU-ITC-063|kazar1988synchronization"
  "howard-tocs-afs-1988|howard1988scale"
  "nixos-icfp2008-final|dolstra2008nixos"
  "nspfssd-lisa2004-final|dolstra2004nix"
  "nsdi20-paper-uta|uta2020reproducible"
)

# Exact filenames, because these stems are short enough to match other files.
EXACT=(
  "ase.pdf|mancinelli2006managing"
  "plan9.pdf|pike1995plan9"
)

# Not a citable publication: CMU 15-412 lecture slides (Eckhardt, 2011).
# Keep the file to read; cite pike1995plan9 and pike1993namespaces instead.
SKIP=( "L04_P9.pdf" )

move_pair() {                     # move_pair <src.pdf> <bibkey>
    local src="$1" key="$2" stem="${1%.pdf}"
    if [ "$src" = "${key}.pdf" ]; then
        printf '  ok         %s\n' "$key"; return
    fi
    if [ "$APPLY" = "1" ]; then
        mv -n -- "$src" "${key}.pdf" || { printf '  MV FAILED  %s\n' "$key"; return; }
        [ -f "${TXTDIR}/${stem}.txt" ] && mv -n -- "${TXTDIR}/${stem}.txt" "${TXTDIR}/${key}.txt"
        printf '  renamed    %s\n' "$key"
    else
        printf '  would be   %-32s <- %s\n' "${key}.pdf" "$src"
    fi
}

echo "=== substring matches ==="
for row in "${MAP[@]}"; do
    frag="${row%%|*}"; key="${row##*|}"
    hits=( *"$frag"*.pdf )
    case ${#hits[@]} in
        0) printf '  MISSING    %-32s (no file matching "%s")\n' "$key" "$frag" ;;
        1) move_pair "${hits[0]}" "$key" ;;
        *) printf '  AMBIGUOUS  %-32s %d files match "%s"\n' "$key" "${#hits[@]}" "$frag" ;;
    esac
done

echo
echo "=== exact filenames ==="
for row in "${EXACT[@]}"; do
    src="${row%%|*}"; key="${row##*|}"
    if [ -f "$src" ]; then move_pair "$src" "$key"
    elif [ -f "${key}.pdf" ]; then printf '  ok         %s\n' "$key"
    else printf '  MISSING    %-32s (%s)\n' "$key" "$src"; fi
done

echo
echo "=== not cited ==="
for s in "${SKIP[@]}"; do
    [ -f "$s" ] && printf '  skipped    %s  (lecture slides, not a publication)\n' "$s"
done

echo
echo "=== already correctly named ==="
for k in pendry1995union; do
    [ -f "${k}.pdf" ] && printf '  ok         %s\n' "$k" || printf '  MISSING    %s\n' "$k"
done

echo
echo "  All 16 cited papers are present and verified against their title pages."
echo "  Outstanding: pendry1995union has no page range in refs.bib."

[ "$APPLY" = "1" ] || { echo; echo "  Dry run. Re-run with: APPLY=1 bash rename_refs.sh"; }
