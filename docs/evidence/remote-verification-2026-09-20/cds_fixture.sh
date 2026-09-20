#!/usr/bin/env bash
# Remote private mount namespace only. Two isolated JVM dumps, no artifact edits.
set -euo pipefail
W=$(mktemp -d /srv/modfs/build/cds-fixture.XXXXXX)
M=/srv/modfs/build/verification/modules
echo "fixture=$W"
df -B1 /srv/modfs/build
[ "$(df --output=avail -B1 /srv/modfs/build | tail -1)" -gt 2000000000 ] || exit 90
mkdir -p "$W"/{base,java,upper,work,merged}
mount -o loop,ro "$M/base.sqsh" "$W/base"
mount -o loop,ro "$M/java.sqsh" "$W/java"
mount -t overlay overlay -o "lowerdir=$W/java:$W/base,upperdir=$W/upper,workdir=$W/work" "$W/merged"
mkdir -p "$W/merged"/{tmp,proc,dev}
mount -t proc proc "$W/merged/proc"
mount --bind /dev "$W/merged/dev"
J=/usr/lib/jvm/java-11-openjdk-amd64/bin/java
chroot "$W/merged" "$J" -version
for run in first second; do
    date -u --iso-8601=seconds
    chroot "$W/merged" "$J" -server -Xshare:dump -XX:SharedArchiveFile=/tmp/$run.jsa > "$W/$run.log" 2>&1
    sha256sum "$W/merged/tmp/$run.jsa"
done
python3 - "$W/merged/tmp" <<'PY'
import hashlib, json
from pathlib import Path
import sys
p=Path(sys.argv[1]);a=(p/'first.jsa').read_bytes();b=(p/'second.jsa').read_bytes()
print(json.dumps({'first_bytes':len(a),'second_bytes':len(b), 'identical':a==b,
    'changed_bytes':sum(x!=y for x,y in zip(a,b))+abs(len(a)-len(b)),
    'first_sha256':hashlib.sha256(a).hexdigest(),'second_sha256':hashlib.sha256(b).hexdigest(),
    'first_80_bytes_hex':a[:80].hex(),'second_80_bytes_hex':b[:80].hex()},indent=2))
PY
umount "$W/merged/dev" "$W/merged/proc" "$W/merged" "$W/java" "$W/base"
