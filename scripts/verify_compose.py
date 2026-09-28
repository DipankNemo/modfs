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
import os, time, stat, subprocess, sys

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
    # Time the verification itself: the caller's total_ms covers mounting and
    # reconciling only, so it never includes the cost of verifying.
    _t0 = time.monotonic()
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
    from account_schema import FIELDS as _FIELDS

    # ---- V2: dpkg status is the exact union of the layers -----------------
    # Compares (name, version) pairs, not names: a composition that keeps only
    # one of two offered versions of a package fails. The caller reports
    # ${Version} from the running system, not from metadata.
    expected, exp_names = set(), set()
    for _, root in layers:
        for s in stanzas(read(os.path.join(root, 'var/lib/dpkg/status'))):
            pkg = field(s, 'Package')
            st = (field(s, 'Status') or '').split()
            if pkg and len(st) == 3 and st[2] == 'installed':
                nm = pkg.split(':')[0]
                expected.add((nm, field(s, 'Version'))); exp_names.add(nm)
    actual, act_names, versioned = set(), set(), True
    for l in (read(os.path.join(work, 'actual.pkgs')) or '').split('\n'):
        if not l.strip():
            continue
        parts = l.split('\t')
        nm = parts[0].split(':')[0]
        act_names.add(nm)
        if len(parts) > 1:
            actual.add((nm, parts[1].strip()))
        else:
            versioned = False
    # A caller that reports names only (no version column) gets the weaker
    # name comparison.
    pkg_ok = (expected == actual) if versioned else (exp_names == act_names)
    pkg_skew = sorted({n for n, _ in expected} & act_names
                      & {n for n, v in (expected - actual)}) if versioned else []

    # ---- V3: every alternatives group holds every candidate offered -------
    # Named alt_want, not `want`: V6 and V7 rebind `want` before the CSV row
    # at the end is printed.
    alt_want = {}
    for _, root in layers:
        d = os.path.join(root, 'var/lib/dpkg/alternatives')
        if not os.path.isdir(d): continue
        for g in os.listdir(d):
            try:
                _, _, _, alts = parse_alt(read(os.path.join(d, g)) or '')
            except Exception:
                continue
            alt_want.setdefault(g, set()).update(p for p, _, _ in alts)
    got = {}
    md = os.path.join(merged, 'var/lib/dpkg/alternatives')
    if os.path.isdir(md):
        for g in os.listdir(md):
            try:
                _, _, _, alts = parse_alt(read(os.path.join(md, g)) or '')
            except Exception:
                continue
            got[g] = {p for p, _, _ in alts}
    alt_bad = sorted(g for g, cands in alt_want.items()
                     if not cands <= got.get(g, set()))

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

    # ---- V6: all account fields, record shape, access mode and ownership ---
    # Match the declared merge policy, not arbitrary equality to one layer:
    # member lists and subordinate ranges union as sets; other fields and file
    # attributes come from the highest layer providing the record/file.
    # Conflicting numeric identities are never a legitimate override.
    # Field counts come from account_schema.FIELDS; the identity and member
    # columns and the whole-line-union flag are V6's own and stay here.
    account_schema = {
        'etc/passwd':   (_FIELDS['etc/passwd'],   (2, 3),              (),     False),
        'etc/group':    (_FIELDS['etc/group'],    (2,),                (3,),   False),
        'etc/shadow':   (_FIELDS['etc/shadow'],   tuple(range(2, 9)),  (),     False),
        'etc/gshadow':  (_FIELDS['etc/gshadow'],  (),                  (2, 3), False),
        'etc/subuid':   (_FIELDS['etc/subuid'],   (1, 2),              (),     True),
        'etc/subgid':   (_FIELDS['etc/subgid'],   (1, 2),              (),     True),
    }
    acct_bad, n_acct = [], 0

    def account_records(root, rel):
        path = os.path.join(root, rel)
        try:
            st = os.lstat(path)
        except FileNotFoundError:
            return {}, None
        if not stat.S_ISREG(st.st_mode):
            raise ValueError('not a regular account database')
        count, numbers, members, ranges = account_schema[rel]
        records = {}
        for line in (read(path) or '').splitlines():
            if not line.strip(): continue
            fields = line.split(':')
            if len(fields) != count or not fields[0]:
                raise ValueError('malformed record (wrong field count or empty name)')
            for i in numbers:
                if rel == 'etc/shadow' and fields[i] == '': continue
                try:
                    fields[i] = int(fields[i])
                except ValueError:
                    raise ValueError('non-numeric identity/range/age field')
                if rel != 'etc/shadow' and fields[i] < 0:
                    raise ValueError('negative identity/range field')
            for i in members:
                fields[i] = frozenset(x for x in fields[i].split(',') if x)
            key = tuple(fields) if ranges else fields[0]
            if not ranges and key in records:
                raise ValueError('duplicate account name')
            records[key] = tuple(fields)
        return records, (stat.S_IMODE(st.st_mode), st.st_uid, st.st_gid)

    for rel, (_, _, member_fields, _) in account_schema.items():
        wanted, expected_attr = {}, None
        for name, root in layers:
            try:
                records, attr = account_records(root, rel)
            except ValueError as exc:
                acct_bad.append('%s in %s: %s' % (rel, name, exc))
                continue
            if attr is not None: expected_attr = attr
            for key, fields in records.items():
                if key in wanted:
                    old = wanted[key]
                    identity = (2, 3) if rel == 'etc/passwd' else ((2,) if rel == 'etc/group' else ())
                    if any(old[i] != fields[i] for i in identity):
                        acct_bad.append('%s: layers disagree on identity for %s' % (rel, key))
                    fields = list(fields)
                    for i in member_fields:
                        fields[i] = old[i] | fields[i]
                wanted[key] = tuple(fields)
        n_acct += len(wanted)
        try:
            got, actual_attr = account_records(merged, rel)
        except ValueError as exc:
            acct_bad.append('%s in composed system: %s' % (rel, exc))
            continue
        if got != wanted:
            # Do not print field values: shadow hashes are sensitive.
            acct_bad.append('%s: missing, extra or changed records' % rel)
        if actual_attr != expected_attr:
            acct_bad.append('%s: mode/uid/gid %r, expected %r'
                            % (rel, actual_attr, expected_attr))
    acct_ok = not acct_bad

    # ---- V8: exact debconf record contents, with Owners treated as sets ----
    # Separate parser from the merger: a missing field/answer must not become
    # invisible merely because the same parser discarded it on both sides.
    DEBCONF = ('var/cache/debconf/config.dat',
               'var/cache/debconf/templates.dat',
               'var/cache/debconf/passwords.dat')

    def dbc_records(root, rel):
        records, fields, key = {}, {}, None
        for line in (read(os.path.join(root, rel)) or '').splitlines() + ['']:
            if not line:
                if fields:
                    name = fields.pop('Name', None)
                    if not name or name in records:
                        raise ValueError('missing or duplicate Name')
                    if 'Owners' in fields:
                        fields['Owners'] = {x.strip() for x in fields['Owners'].split(',')
                                            if x.strip()}
                    records[name], fields = fields, {}
                key = None
            elif line[0].isspace():
                if key is None:
                    raise ValueError('continuation without a field')
                fields[key] += '\n' + line
            else:
                key, sep, value = line.partition(':')
                if not sep or not key or key in fields:
                    raise ValueError('malformed or duplicate field')
                fields[key] = value.lstrip(' ')
        return records

    dbc_bad, n_dbc = [], 0
    for rel in DEBCONF:
        wanted = {}
        for name, root in layers:
            try:
                recs = dbc_records(root, rel)
            except ValueError as exc:
                dbc_bad.append('%s in %s: %s' % (rel, name, exc))
                continue
            for record, fields in recs.items():
                target = wanted.setdefault(record, {})
                for key, value in fields.items():
                    if key == 'Owners':
                        target.setdefault(key, set()).update(value)
                    else:
                        if key in target and target[key] != value:
                            dbc_bad.append('%s: layers disagree on %s field %s'
                                           % (rel, record, key))
                        target[key] = value
        n_dbc += len(wanted)
        try:
            got = dbc_records(merged, rel)
        except ValueError as exc:
            dbc_bad.append('%s in composed system: %s' % (rel, exc))
            continue
        if wanted != got:
            changed = sorted(k for k in wanted.keys() | got.keys()
                             if wanted.get(k) != got.get(k))
            dbc_bad.append('%s: %d missing/extra/changed record(s): %s'
                           % (rel, len(changed), ', '.join(changed[:6])))
    dbc_ok = not dbc_bad

    # ---- V5 ---------------------------------------------------------------
    audit_ok = not (read(os.path.join(work, 'audit.txt')) or '').strip()

    # ---- V7: every file in any layer is visible and is the same file -------
    # Comparing entry names is not enough: a symlinked directory can replace
    # another module's files with same-named decoys; an absolute symlink would
    # resolve against the host's root, because this runs outside the chroot;
    # and a real lib/ directory can shadow base's merged-/usr lib -> usr/lib
    # symlink, leaving every file present but the dynamic loader unreachable.
    # So descend only into real directories (never through a symlink), record
    # (kind, size) per path, and require the merged entry to match some layer's
    # version of it. Last-wins between layers is legal; content from outside
    # every layer is not.
    SKIP_TOP = {'proc', 'sys', 'dev', 'run', 'tmp'}
    # Reconciliation deliberately rewrites these, so they match no single layer.
    RECONCILED = {'etc/passwd', 'etc/group', 'etc/shadow', 'etc/gshadow',
                  'etc/subuid', 'etc/subgid', 'etc/ld.so.cache',
                  'var/lib/dpkg/status', 'var/lib/dpkg/status-old',
                  'var/lib/dpkg/diversions', 'var/lib/apt/extended_states',
                  'var/cache/ldconfig/aux-cache',
                  # reconcile.py merges the debconf databases, so
                  # the merged copies match no single layer.
                  'var/cache/debconf/config.dat',
                  'var/cache/debconf/templates.dat',
                  'var/cache/debconf/passwords.dat'}
    RECONCILED_PREFIX = ('var/lib/dpkg/alternatives/', 'etc/alternatives/')

    def vis_scan(root):
        """rel -> (kind, size/target), without traversing symlinks."""
        out, stack = {}, ['']
        while stack:
            rel = stack.pop()
            try:
                with os.scandir(os.path.join(root, rel) if rel else root) as it:
                    ents = list(it)
            except OSError:
                continue
            for e in ents:
                if not rel and e.name in SKIP_TOP:
                    continue
                r = rel + '/' + e.name if rel else e.name
                try:
                    if e.is_symlink():
                        out[r] = ('l', os.readlink(e.path))
                    elif e.is_dir(follow_symlinks=False):
                        out[r] = ('d', 0); stack.append(r)
                    elif e.is_file(follow_symlinks=False):
                        out[r] = ('f', e.stat(follow_symlinks=False).st_size)
                    else:
                        # A whiteout (character device 0:0) means the
                        # path must be absent from the merged view, so it
                        # gets its own kind 'w' rather than being
                        # reported missing. 02_build_delta.sh currently
                        # refuses to build a module containing one.
                        st = e.stat(follow_symlinks=False)
                        if stat.S_ISCHR(st.st_mode) and st.st_rdev == 0:
                            out[r] = ('w', 0)
                        else:
                            # Distinguish the special-file types and record
                            # a device's major:minor, so swapping a FIFO for a
                            # socket, or /dev/null for /dev/sda, is a change.
                            # Only the few special files reach this branch.
                            m = st.st_mode
                            if   stat.S_ISFIFO(m): out[r] = ('p', 0)
                            elif stat.S_ISSOCK(m): out[r] = ('s', 0)
                            elif stat.S_ISCHR(m):  out[r] = ('c', st.st_rdev)
                            elif stat.S_ISBLK(m):  out[r] = ('b', st.st_rdev)
                            else:                  out[r] = ('o', 0)
                except OSError:
                    out[r] = ('?', 0)
        return out

    vis_expected = {}
    for _, lroot in layers:
        for r, v in vis_scan(lroot).items():
            vis_expected.setdefault(r, set()).add(v)
    vis_got = vis_scan(merged)
    vis_missing, vis_unchecked = [], []
    for r in sorted(vis_expected):
        kinds = {k for k, _ in vis_expected[r]}
        # Reconciled paths are exempt from the (kind, size) comparison, since
        # reconciliation rewrites them on purpose, but they must still exist.
        # Nothing else checks that: V3 reads the alternatives registry, not the
        # symlinks it produces.
        if r in RECONCILED or r.startswith(RECONCILED_PREFIX):
            if 'w' not in kinds and r not in vis_got:
                vis_missing.append('MISSING /%s (reconciled path, so only its '
                                   'existence is checked)' % r)
            continue
        if 'w' in kinds:
            # Some layer deletes this path. Whether the merge should show it
            # depends on stacking order, which V7 does not model, so it is
            # reported as unchecked rather than judged. 02_build_delta.sh
            # currently refuses to build a module containing a whiteout.
            vis_unchecked.append('/%s (a layer deletes it; V7 does not model '
                                 'deletion ordering)' % r)
            continue
        if len(kinds) > 1 and 'l' in kinds:
            vis_missing.append('TYPE CONFLICT /%s: layers disagree %s -- whichever '
                               'loses, paths through it break' % (r, '/'.join(sorted(kinds))))
            continue
        g = vis_got.get(r)
        if g is None:
            vis_missing.append('MISSING /%s' % r)
        elif g not in vis_expected[r]:
            def describe(entry):
                kind, value = entry
                if kind == 'f': return 'f %dB' % value
                if kind == 'l': return 'l -> %r' % value
                return kind
            shape = ','.join(sorted(describe(v) for v in vis_expected[r]))
            vis_missing.append('ALTERED /%s: merged=%s but layers have {%s}'
                               % (r, describe(g), shape))
    vis_ok = not vis_missing

    # Paths V7 declined to judge go to stderr on every run, so vis_ok=1
    # never silently means "did not look".
    for v in vis_unchecked[:5]:
        sys.stderr.write("  V7 DECLINED TO CHECK: %s\n" % v)
    if len(vis_unchecked) > 5:
        sys.stderr.write("  V7 DECLINED TO CHECK: %d more\n" % (len(vis_unchecked) - 5))

    ok = (pkg_ok and not alt_bad and ld_ok and audit_ok and acct_ok
          and dbc_ok and vis_ok)
    print(','.join(str(x) for x in [
        idx, n, ' '.join(name for name, _ in layers), admitted,
        mount_ms, rec_ms, tot_ms,
        len(expected), len(actual), int(pkg_ok),
        len(alt_want), len(alt_bad),
        len(ld_expected), len(ld_actual), int(ld_ok), int(audit_ok),
        n_acct, int(acct_ok),
        n_dbc, int(dbc_ok),
        len(vis_missing), int(vis_ok),
        int((time.monotonic() - _t0) * 1000),
        # A structurally clean composition of a tier-1-rejected set is a
        # known-negative observation, never a verification.
        ('PASS' if admitted != 'known-negative' else 'KNOWN_NEGATIVE')
        if ok else 'FAIL']))
    if not ok:
        # Distinguish "a package is gone" from "the wrong version survived";
        # they are different defects.
        gone = sorted(exp_names - act_names)[:5]
        if gone: sys.stderr.write("  missing packages: %s\n" % ', '.join(gone))
        for n in pkg_skew[:5]:
            offered = sorted(v for nm, v in expected if nm == n)
            kept = sorted(v for nm, v in actual if nm == n)
            sys.stderr.write("  CLASS 2 version skew: %s offered %s, composed has %s\n"
                             % (n, '/'.join(offered), '/'.join(kept) or 'none'))
        if alt_bad: sys.stderr.write("  alternatives short: %s\n" % ', '.join(alt_bad))
        if not ld_ok:
            sys.stderr.write("  linker cache missing: %s\n"
                             % ', '.join(sorted(ld_expected - ld_actual)[:5]))
        for a in acct_bad[:5]:
            sys.stderr.write("  accounts: %s\n" % a)
        for d in dbc_bad[:5]:
            sys.stderr.write("  DEBCONF MISMATCH: %s\n" % d)
        for v in vis_missing[:5]:
            sys.stderr.write("  NOT VISIBLE IN MERGE: %s\n" % v)
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
