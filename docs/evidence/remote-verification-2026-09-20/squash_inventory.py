#!/usr/bin/env python3
"""Read-only SquashFS inventory using unsquashfs 4.6.1's pseudo stream.

No extraction, mounts, repacking, or timestamp changes. Output retains inode
metadata, symlink/hardlink records, xattrs and regular-file SHA256 values.
Pseudo data offsets are replaced by content hashes; archive SHA256 is separate.
Usage: python3 squash_inventory.py /path/to/base.sqsh > inventory.json
"""

import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import sys


def inventory(path):
    whole = hashlib.sha256()
    with path.open('rb') as source:
        header = source.read(96)
        whole.update(header)
        for chunk in iter(lambda: source.read(1 << 20), b''):
            whole.update(chunk)
    superblock = struct.unpack('<5I6H8Q', header)
    if superblock[0] != 0x73717368:
        raise ValueError('not a little-endian SquashFS archive')

    proc = subprocess.Popen(
        ['unsquashfs', '-no-progress', '-pf', '-', str(path)],
        stdout=subprocess.PIPE,
    )
    nodes, payloads = {}, []
    try:
        while True:
            line = proc.stdout.readline()
            if line == b'#\n':
                if proc.stdout.readline() != b'# START OF DATA - DO NOT MODIFY\n':
                    raise ValueError('unexpected pseudo data marker')
                if proc.stdout.readline() != b'#\n':
                    raise ValueError('unterminated pseudo data marker')
                break
            match = re.fullmatch(rb'((?:\\.|[^\\\s])+) (\S) (.*)\n', line)
            if not match:
                raise ValueError('unsupported pseudo record: ' + repr(line[:200]))
            name, kind, record = (s.decode('utf-8', 'surrogateescape')
                                  for s in match.groups())
            name = re.sub(r'\\(.)', r'\1', name)
            if kind == 'x':
                nodes[name].setdefault('xattrs', []).append(record)
                continue
            if name in nodes:
                raise ValueError('duplicate inode record: ' + name)
            node = {'kind': kind, 'metadata': record}
            if kind == 'R':
                fields = record.split()
                if len(fields) != 7:
                    raise ValueError('unsupported regular-file record: ' + record)
                size, offset = int(fields[4]), int(fields[5])
                node['metadata'] = ' '.join(fields[:5] + fields[6:])
                payloads.append((offset, size, name))
            nodes[name] = node

        position = 0
        for offset, size, name in sorted(payloads):
            if offset != position:
                raise ValueError('non-contiguous pseudo stream at ' + name)
            remaining = size
            digest = hashlib.sha256()
            while remaining:
                chunk = proc.stdout.read(min(1 << 20, remaining))
                if not chunk:
                    raise ValueError('truncated file content: ' + name)
                digest.update(chunk)
                remaining -= len(chunk)
            nodes[name]['sha256'] = digest.hexdigest()
            position += size
        if proc.stdout.read(1):
            raise ValueError('unexpected trailing pseudo data')
        if proc.wait() != 0:
            raise ValueError('unsquashfs failed')
    finally:
        proc.stdout.close()
        if proc.poll() is None:
            proc.terminate()
        proc.wait()

    return {'artifact': path.name, 'artifact_sha256': whole.hexdigest(),
            'artifact_bytes': path.stat().st_size,
            'superblock': list(superblock), 'nodes': nodes}


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    print(json.dumps(inventory(Path(sys.argv[1])), sort_keys=True))
