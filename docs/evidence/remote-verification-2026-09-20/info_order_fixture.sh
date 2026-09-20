#!/usr/bin/env bash
# Remote scratch only. Regenerate diagnostic Info indexes, never an artifact.
set -euo pipefail
W=$(mktemp -d /srv/modfs/build/info-order.XXXXXX)
M=/srv/modfs/build/verification/modules
echo "fixture=$W"
df -B1 /srv/modfs/build
unsquashfs -no-progress -d "$W/base" "$M/base.sqsh" usr/share/info
unsquashfs -no-progress -d "$W/emacs" "$M/emacs.sqsh" usr/share/info usr/bin/install-info
python3 - "$W" <<'PY'
import hashlib, json, os
from pathlib import Path
import re, subprocess as sp, sys
w=Path(sys.argv[1])
files={}
for part in ('base','emacs'):
    for p in (w/part/'usr/share/info').iterdir():
        if p.is_file() and p.name not in ('dir','dir.old') and not re.search(r'-\d+(\.gz)?$',p.name):
            files[p.name]=p
out=[]
for locale in ('C','C.UTF-8'):
    for reverse in (False,True):
        target=w/('index-'+locale+'-'+str(reverse))
        for name in sorted(files,reverse=reverse):
            sp.run([str(w/'emacs/usr/bin/install-info'),str(files[name]),str(target)],check=True,
                   env={**os.environ,'LC_ALL':locale},stdout=sp.DEVNULL,stderr=sp.PIPE)
        data=target.read_bytes()
        out.append({'locale':locale,'reverse_input_order':reverse,'sha256':hashlib.sha256(data).hexdigest(),
                    'dir_entries':[line for line in data.decode().splitlines() if line.startswith(('* dir:', '* dircolors:', '* dirname:'))]})
print(json.dumps(out,indent=2))
PY
