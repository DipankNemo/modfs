#!/usr/bin/env bash
# Execute on the outer remote container. Reuses stage 11's packed image and
# unchanged verdict parser; explicitly TCG, no passthrough, no host reboot.
set -euo pipefail
E=/srv/modfs/results/remote-verification-2026-09-20/tcg-retry
W=/srv/modfs/build/tcg-retry
G=(ssh -o BatchMode=yes -o ConnectTimeout=15 -o UserKnownHostsFile=/srv/modfs/build/verification-vm/known_hosts -i /srv/modfs/build/verification-vm/guest-key -p 2222 root@127.0.0.1)
C=/srv/modfs/build/verification/build/boot-remote-webserver-20260920T190147Z
mkdir -p "$E" "$W"
date -u --iso-8601=seconds
df -B1 /srv/modfs/build
[ "$(df --output=avail -B1 /srv/modfs/build | tail -1)" -gt 10000000000 ] || exit 90
"${G[@]}" "tar -S -C $C -cf - disk.img" | tar -S -C "$W" -xf -
"${G[@]}" cat /usr/share/OVMF/OVMF_CODE_4M.fd > "$W/OVMF_CODE_4M.fd"
"${G[@]}" cat /usr/share/OVMF/OVMF_VARS_4M.fd > "$W/OVMF_VARS.fd"
"${G[@]}" cat /root/modfs/scripts/11_boot_test.sh > "$E/measured-11_boot_test.sh"
sha256sum "$W/disk.img" "$W/OVMF_CODE_4M.fd" "$E/measured-11_boot_test.sh" | tee "$E/input-sha256.txt"
python3 - "$E" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=(p/'measured-11_boot_test.sh').read_text()
start=s.index('import os, re, sys\n', s.index('python3 - "$SERIAL" "$QRC"'))
end=s.index('\nPY\n',start)
(p/'verdict.py').write_text(s[start:end]+'\n')
PY
qemu-system-x86_64 --version
date -u --iso-8601=seconds > "$E/started-utc.txt"
set +e
timeout --foreground 3600 qemu-system-x86_64 \
 -machine q35,accel=tcg -m 2048 -smp 2 \
 -drive if=pflash,format=raw,unit=0,readonly=on,file="$W/OVMF_CODE_4M.fd" \
 -drive if=pflash,format=raw,unit=1,file="$W/OVMF_VARS.fd" \
 -drive file="$W/disk.img",format=raw,if=virtio \
 -display none -serial "file:$E/serial.log" -no-reboot > "$E/qemu.log" 2>&1
qrc=$?
echo "$qrc" > "$E/qemu-exit.txt"
python3 "$E/verdict.py" "$E/serial.log" "$qrc" 3600 "$E" ADMITTED 0 > "$E/verdict.log" 2>&1
rc=$?
echo "$rc" > "$E/verdict-exit.txt"
date -u --iso-8601=seconds > "$E/finished-utc.txt"
cat "$E/verdict.log"
exit "$rc"
