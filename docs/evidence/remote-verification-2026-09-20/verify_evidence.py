#!/usr/bin/env python3
"""Recompute the archived comparison; read-only, no remote access required."""
import csv
import gzip
import hashlib
import json
from pathlib import Path
import re
import tarfile

p = Path(__file__).resolve().parent
def inventories(name):
    with gzip.open(p / name, 'rt') as f:
        values = list(map(json.loads, f))
    result = {Path(v['artifact']).stem: v for v in values}
    assert len(result) == len(values) == 41
    return result

local = inventories('local-inventories.jsonl.gz')
remote = inventories('remote-inventories.jsonl.gz')
with gzip.open(p / 'local-reference-manifests.json.gz', 'rt') as f:
    lm = json.load(f)
with tarfile.open(p / 'catalogue-results-bundle.tar') as t:
    rm = {Path(n).stem: json.load(t.extractfile(n)) for n in t.getnames()
          if n.startswith('payloads/') and n.endswith('.json')}
rows = {r['module']: r for r in csv.DictReader((p / 'cross-machine-comparison.csv').open())}
assert local.keys() == remote.keys() == lm.keys() == rm.keys() == rows.keys()
identical = 0
same_packages = 0
for module, a in local.items():
    b = remote[module]
    for inv, manifest in ((a, lm[module]), (b, rm[module])):
        assert inv['artifact_sha256'] == manifest['artifact']['sha256'], module
        assert inv['artifact_bytes'] == manifest['artifact']['bytes'], module
    assert lm[module]['snapshot'] == rm[module]['snapshot'], module
    an, bn = a['nodes'], b['nodes']
    common = an.keys() & bn.keys()
    measured = {
        'identical': a['artifact_sha256'] == b['artifact_sha256'],
        'local_sha256': a['artifact_sha256'], 'remote_sha256': b['artifact_sha256'],
        'local_bytes': a['artifact_bytes'], 'remote_bytes': b['artifact_bytes'],
        'same_package_map': lm[module]['packages'] == rm[module]['packages'],
        'same_inventory': an == bn,
        'added_paths': len(bn.keys() - an.keys()), 'removed_paths': len(an.keys() - bn.keys()),
        'content_changes': sum(an[k].get('sha256') != bn[k].get('sha256') for k in common),
        'metadata_changes': sum((an[k]['kind'], an[k]['metadata']) !=
                                (bn[k]['kind'], bn[k]['metadata']) for k in common),
        'xattr_changes': sum(an[k].get('xattrs', []) != bn[k].get('xattrs', []) for k in common),
    }
    for field, value in measured.items():
        assert str(value) == rows[module][field], (module, field, value, rows[module][field])
    if module != 'base':
        identical += measured['identical']
        same_packages += measured['same_package_map']

gpu = json.loads((p / 'gpu-runtime-result.json').read_text())
assert gpu['result'] == 'PASS' and gpu['output'] == list(range(7, 39))
bound = 0
for path, digest in gpu['mapped_library_sha256'].items():
    prefix = '/srv/modfs/build/gpu-built/'
    if path.startswith(prefix):
        assert remote['cuda-runtime']['nodes'][path[len(prefix):]]['sha256'] == digest
        bound += 1
assert bound == 3

with tarfile.open(p / 'tcg-boot-results.tar') as t:
    read = lambda n: t.extractfile('tcg-retry/' + n).read()
    assert read('qemu-exit.txt').strip() == b'0'
    assert read('verdict-exit.txt').strip() == b'0'
    serial = read('serial.log')
    assert b'MODFS CHECK audit PASS' in serial and b'MODFS PROBE webserver PASS' in serial
    source = read('measured-11_boot_test.sh').decode()
    start = source.index('import os, re, sys\n', source.index('python3 - "$SERIAL" "$QRC"'))
    end = source.index('\nPY\n', start)
    assert read('verdict.py') == (source[start:end] + '\n').encode()

source_hashes = re.findall(r'^([0-9a-f]{64})  (.+)$',
                         (p / 'packed-image-source-sha256.log').read_text(), re.M)
input_hashes = re.findall(r'^([0-9a-f]{64})  (.+)$',
                        (p / 'tcg-input-sha256.txt').read_text(), re.M)
assert len(source_hashes) == len(input_hashes) == 3
assert [v[0] for v in source_hashes] == [v[0] for v in input_hashes]
assert source_hashes[2][0] == hashlib.sha256(source.encode()).hexdigest()

print(json.dumps({'archives_checked': 41, 'manifest_digests_verified': 82,
                  'module_archives_byte_identical': identical, 'module_count': 40,
                  'module_package_maps_equal': same_packages,
                  'gpu_runtime_library_bindings': bound,
                  'boot_input_hashes_equal_to_source': 3,
                  'tcg_boot': 'PASS; unchanged verdict parser'}, indent=2))
