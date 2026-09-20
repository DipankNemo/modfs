#!/usr/bin/env bash
# Run ONLY in a remote private mount namespace; no artifact is rewritten.
set -euo pipefail
W=$(mktemp -d /srv/modfs/build/impure-fixture.XXXXXX)
echo "fixture=$W"
uname -r
for mode in raw filtered; do
    C=$W/$mode
    mkdir -p "$C"/{lower,upper,work,merged}
    mkdir -p "$C/lower/var/cache/apt" "$C/lower/var/lib/apt" "$C/lower/var/log/apt"
    if [ "$mode" = raw ]; then
        mkdir -p "$C/lower/var/cache/apt/archives" "$C/lower/var/lib/apt/lists"
        echo old > "$C/lower/var/log/apt/history.log"
    fi
    mount -t overlay overlay -o "lowerdir=$C/lower,upperdir=$C/upper,workdir=$C/work" "$C/merged"
    mkdir -p "$C/merged/var/cache/apt/archives" "$C/merged/var/lib/apt/lists"
    chmod 700 "$C/merged/var/cache/apt/archives" "$C/merged/var/lib/apt/lists"
    echo new > "$C/merged/var/log/apt/history.log"
    echo "mode=$mode"
    getfattr -d -m '^trusted.overlay.impure$' "$C/upper/var/cache/apt" "$C/upper/var/lib/apt" "$C/upper/var/log/apt"
    umount "$C/merged"
done
