#!/usr/bin/env bash
# Compare preserved roots; writes a new CSV plus a JSON summary, never artefacts.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${HERE}/config.sh"
source "${HERE}/scripts/lib.sh"
python3 "${HERE}/scripts/update_report.py" "$@"
