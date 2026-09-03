#!/usr/bin/env python3
"""Verify one composed module set and emit a CSV row. Used by 10_compose_sweep.sh.

    verify_compose.py --scripts DIR --merged DIR --work DIR --index I --n N
                      --mount-ms MS --reconcile-ms MS --total-ms MS
                      NAME=LAYERDIR ...

Every check compares SETS, not counts: two sets of equal size can still differ,
and a count-only check would pass a composition that silently swapped a package
for another. The caller has already collected what the composed system reports
into <work>/actual.pkgs, actual.ld and audit.txt from inside the chroot.
"""
import os, subprocess, sys

def arg(argv, name, default=None):
    return argv[argv.index(name) + 1] if name in argv else default

def cache_libs(text):
    """`ldconfig -p` output -> set of soname strings (first line is a header)."""
    out = set()
    for line in text.split('\n'):
        if '=>' not in line: continue
        out.add(line.split('(')[0].strip())
    return out

def main(argv):
    scripts = arg(argv, '--scripts'); merged = arg(argv, '--merged')
    work = arg(argv, '--work')
    idx, n = arg(argv, '--index'), arg(argv, '--n')
    admitted = arg(argv, '--admitted', 'unknown')
    mount_ms = arg(argv, '--mount-ms'); rec_ms = arg(argv, '--reconcile-ms')
    tot_ms = arg(argv, '--total-ms')
    layers = [(a.split('=', 1)[0], a.split('=', 1)[1]) for a in argv if '=' in a
              and not a.startswith('--')]
    if not (scripts and merged and work and layers):
        sys.stderr.write(__doc__); return 2

    sys.path.insert(0, scripts)
    from reconcile import stanzas, field, parse_alt, read

    # ---- V2: dpkg status is the exact union of the layers -----------------
    expected = set()
    for _, root in layers:
        for s in stanzas(read(os.path.join(root, 'var/lib/dpkg/status'))):
            pkg = field(s, 'Package')
            st = (field(s, 'Status') or '').split()
            if pkg and len(st) == 3 and st[2] == 'installed':
                expected.add(pkg.split(':')[0])
    actual = {l.split(':')[0] for l in
              (read(os.path.join(work, 'actual.pkgs')) or '').split('\n') if l.strip()}
    pkg_ok = (expected == actual)

    # ---- V3: every alternatives group holds every candidate offered -------
    want = {}
    for _, root in layers:
        d = os.path.join(root, 'var/lib/dpkg/alternatives')
        if not os.path.isdir(d): continue
        for g in os.listdir(d):
            try:
                _, _, _, alts = parse_alt(read(os.path.join(d, g)) or '')
            except Exception:
                continue
            want.setdefault(g, set()).update(p for p, _, _ in alts)
    got = {}
    md = os.path.join(merged, 'var/lib/dpkg/alternatives')
    if os.path.isdir(md):
        for g in os.listdir(md):
            try:
                _, _, _, alts = parse_alt(read(os.path.join(md, g)) or '')
            except Exception:
                continue
            got[g] = {p for p, _, _ in alts}
    alt_bad = sorted(g for g, cands in want.items() if not cands <= got.get(g, set()))

    # ---- V4: linker cache is the union of the layers' caches --------------
    ld_expected = set()
    for _, root in layers:
        c = os.path.join(root, 'etc/ld.so.cache')
        if not os.path.exists(c): continue
        try:
            out = subprocess.run(['ldconfig', '-p', '-C', c],
                                 capture_output=True, text=True).stdout
        except Exception:
            continue
        ld_expected |= cache_libs(out)
    ld_actual = cache_libs(read(os.path.join(work, 'actual.ld')) or '')
    ld_ok = ld_expected <= ld_actual        # regeneration may legitimately add

    # ---- V5 ---------------------------------------------------------------
    audit_ok = not (read(os.path.join(work, 'audit.txt')) or '').strip()

    ok = pkg_ok and not alt_bad and ld_ok and audit_ok
    print(','.join(str(x) for x in [
        idx, n, ' '.join(name for name, _ in layers), admitted,
        mount_ms, rec_ms, tot_ms,
        len(expected), len(actual), int(pkg_ok),
        len(want), len(alt_bad),
        len(ld_expected), len(ld_actual), int(ld_ok), int(audit_ok),
        # A structurally clean composition of a tier-1-rejected set is a
        # known-negative observation, never a verification.
        ('PASS' if admitted != 'known-negative' else 'KNOWN_NEGATIVE')
        if ok else 'FAIL']))
    if not ok:
        miss = sorted(expected - actual)[:5]
        if miss: sys.stderr.write("  missing packages: %s\n" % ', '.join(miss))
        if alt_bad: sys.stderr.write("  alternatives short: %s\n" % ', '.join(alt_bad))
        if not ld_ok:
            sys.stderr.write("  linker cache missing: %s\n"
                             % ', '.join(sorted(ld_expected - ld_actual)[:5]))
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
