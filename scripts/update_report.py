#!/usr/bin/env python3
"""Measure whole-artefact transfers between two retained catalogue roots.

Hashes actual bytes, checks the recorded size/digest, and fails on incomplete
catalogues. Size growth is not shipping: a changed artefact ships in full.
The monolithic catalogue total is explicitly a B+d model, not a built image.
"""
import argparse
import csv
import hashlib
import json
from pathlib import Path


def inventory(root):
    result = {}
    for path in sorted((Path(root) / 'modules').glob('*.json')):
        doc = json.loads(path.read_text())
        name = doc['module']
        if path.name != name + '.json' or name in result:
            raise ValueError('ambiguous manifest: ' + str(path))
        artifact = path.with_suffix('.sqsh')
        h = hashlib.sha256()
        with artifact.open('rb') as f:
            for chunk in iter(lambda: f.read(1024 * 1024), b''):
                h.update(chunk)
        size, digest = artifact.stat().st_size, h.hexdigest()
        if (size, digest) != (doc['artifact']['bytes'], doc['artifact']['sha256']):
            raise ValueError('artefact/manifest mismatch: ' + str(path))
        result[name] = dict(bytes=size, sha256=digest, snapshot=doc['snapshot'],
                            packages={n: p['version'] for n, p in doc['packages'].items()})
    if 'base' not in result or len(result) < 2:
        raise ValueError('need a base and at least one module')
    return result


def compare(old, new):
    rows = []
    for name in sorted(set(old) | set(new)):
        a, b = old.get(name), new.get(name)
        changed = a is None or b is None or a['sha256'] != b['sha256']
        rows.append(dict(module=name, status='added' if a is None else 'removed' if b is None
                         else 'changed' if changed else 'identical',
                         old_sha256=a['sha256'] if a else '', new_sha256=b['sha256'] if b else '',
                         old_bytes=a['bytes'] if a else 0, new_bytes=b['bytes'] if b else 0,
                         size_change_bytes=(b['bytes'] if b else 0) - (a['bytes'] if a else 0),
                         ship_bytes=b['bytes'] if b and changed else 0,
                         old_snapshot=a['snapshot'] if a else '', new_snapshot=b['snapshot'] if b else '',
                         contribution_versions_equal=bool(a and b and a['packages'] == b['packages'])))
    return rows


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--old-root', required=True)
    p.add_argument('--new-root', required=True)
    p.add_argument('--out', required=True, help='new CSV path; JSON summary alongside')
    args = p.parse_args()
    old, new = inventory(args.old_root), inventory(args.new_root)
    rows = compare(old, new)
    modules = [r for r in rows if r['module'] != 'base' and r['status'] != 'removed']
    summary = dict(old_root=args.old_root, new_root=args.new_root, unit='bytes (MB = 10^6 bytes)',
                   modules=len(modules), changed=sum(r['status'] != 'identical' for r in modules),
                   identical=sum(r['status'] == 'identical' for r in modules),
                   module_ship_bytes=sum(r['ship_bytes'] for r in modules),
                   module_total_bytes=sum(r['new_bytes'] for r in modules),
                   base_ship_bytes=next(r['ship_bytes'] for r in rows if r['module'] == 'base'),
                   base_total_bytes=new['base']['bytes'],
                   monolithic_catalogue_model_bytes=len(modules) * new['base']['bytes']
                       + sum(r['new_bytes'] for r in modules),
                   same_contribution_package_versions=sum(r['contribution_versions_equal'] for r in modules),
                   negative_controls=[n for n, d in new.items() if d['snapshot'] != new['base']['snapshot']])
    with open(args.out, 'x', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader(); writer.writerows(rows)
    with open(args.out + '.json', 'x') as f:
        json.dump(summary, f, indent=2); f.write('\n')
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
