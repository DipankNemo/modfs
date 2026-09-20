#!/usr/bin/env bash
# Measurement orchestration only; run INSIDE the remote build VM.
# Pipeline source must be a clean clone. All disposable paths stay under build.
set -euo pipefail
export MODFS_ROOT=/srv/modfs/build/verification
export MODFS_SNAPSHOT_ID=20260701T000000Z
export PYTHONDONTWRITEBYTECODE=1
SOURCE=${1:?usage: run_catalogue.sh /absolute/path/to/clean/modfs/clone}
source "$SOURCE/config.sh"
source "$SOURCE/scripts/lib.sh"
need_root
E=/srv/modfs/results/remote-verification-2026-09-20
case "$(readlink -m "$ROOT")" in /srv/modfs/build/*) ;; *) die 'unsafe root';; esac
test -z "$(git -C "$SOURCE" status --porcelain)" || die 'dirty source clone'
test "$(git -C "$SOURCE" rev-parse HEAD)" = a69111baedb576ea9d093626e883b6f7cd5bd3ce
test -f "$MOD_DIR/base.json"
test ! -e "$E/catalogue-status.csv" || die 'refusing to overwrite earlier results'
require_no_mounts "$ROOT"
df -B1 "$ROOT"
test "$(df --output=avail -B1 "$ROOT" | tail -1)" -gt 40000000000
mkdir -p "$E/payloads" "$E/module-logs"
cp -a "$MOD_DIR/base.sqsh" "$MOD_DIR/base.json" "$MOD_DIR/base.files.json.zst" "$E/payloads/"
cp -a "$BUILD_DIR" "$E/base-scratch"
safe_rm_rf "$MOD_DIR" base.dir
reset_workdir "$BUILD_DIR"
mapfile -t names < <(python3 - "$SPEC_DIR/modules.yaml" <<'PY'
import sys, yaml
for module in yaml.safe_load(open(sys.argv[1]))['modules']:
    print(module['name'])
PY
)
test "${#names[@]}" -eq 40
printf 'module,exit,started_utc,finished_utc,free_bytes_before\n' > "$E/catalogue-status.csv"
failed=0
for name in "${names[@]}"; do
    require_ident "$name" 'module'
    available=$(df --output=avail -B1 "$ROOT" | tail -1 | tr -d ' ')
    # Scratch is cleared after each success; even the largest single module
    # has ample headroom. Stop before invoking a builder if this reserve is gone.
    test "$available" -gt 10000000000 || die "insufficient space before $name: $available"
    require_no_mounts "$ROOT"
    started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    log "START $name at $started; free=$available bytes"
    rc=0
    /usr/bin/time -p unshare --mount --propagation private \
        "$SOURCE/scripts/08_build_catalogue.sh" --only "$name" \
        > "$E/module-logs/$name.wrapper.log" 2>&1 || rc=$?
    finished=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    printf '%s,%s,%s,%s,%s\n' "$name" "$rc" "$started" "$finished" "$available" >> "$E/catalogue-status.csv"
    cp -a "$LOG_DIR/catalogue-$name.log" "$E/module-logs/"
    require_no_mounts "$ROOT"
    if [ "$rc" -eq 0 ]; then
        cp -a "$MOD_DIR/$name.sqsh" "$MOD_DIR/$name.json" "$MOD_DIR/$name.files.json.zst" "$E/payloads/"
        sha256sum "$MOD_DIR/$name.sqsh"
        safe_rm_rf "$MOD_DIR" "$name.upper"
        reset_workdir "$BUILD_DIR"
        log "DONE $name; scratch cleared"
    else
        failed=$((failed + 1))
        warn "FAILED $name (exit $rc); its upperdir retained"
        tail -n 12 "$LOG_DIR/catalogue-$name.log"
    fi
done
printf 'catalogue_failed=%s\n' "$failed"
df -B1 "$ROOT"
test "$failed" -eq 0
