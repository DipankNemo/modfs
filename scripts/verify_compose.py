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
import os, stat, subprocess, sys

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
    # NAME AND VERSION. Comparing name sets left tier 2 with no independent view
    # of class 2 whatsoever: on 2026-09-17, 05_check.sh REJECTED
    # curl+control-oldsnap with five version skews and every tier-2 column came
    # back green, because both layers offer a package called `curl`. That made
    # stage 10's admission gate load-bearing rather than convenient, which is a
    # much weaker claim than "tier 2 verifies the composed system against its
    # own layers". A composition holding one of two offered versions is now a
    # failure here too, and the caller reports ${Version} so this can be checked
    # against the running system rather than against metadata.
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
    # Fall back to names if the caller predates the versioned format, and say so
    # rather than silently reporting a weaker check as if it were the strong one.
    pkg_ok = (expected == actual) if versioned else (exp_names == act_names)
    pkg_skew = sorted({n for n, _ in expected} & act_names
                      & {n for n, v in (expected - actual)}) if versioned else []

    # ---- V3: every alternatives group holds every candidate offered -------
    # NAMED alt_want, not `want`. It used to be `want`, and BOTH V6's loop
    # variable (`for rel, want in acct_expected.items()`) and a local inside
    # V7's ALTERED branch rebound it before the CSV was printed at the bottom.
    # The column labelled `alt_groups` therefore reported the number of
    # /etc/gshadow records: 42 for `base nc-traditional rust`, which has 10
    # alternatives groups. `alt_groups_bad` was computed here, before the
    # rebinding, so the VERDICT was always right and only the count was wrong --
    # but the count is published in ARCHITECTURE section 7's tier-2 table.
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

    # ---- V6: account databases are the exact semantic union ---------------
    # The invariant that was missing. Numeric uniqueness (disjoint UID windows)
    # and database composition are different properties: OverlayFS shows one
    # complete passwd, so without reconciliation a composed system silently
    # loses every account except the top layer's. This compares the COMPOSED
    # files against the union of the layers, by record, not by count.
    def accounts(root):
        out = {}
        for rel, key_at, member_at in (('etc/passwd', 0, ()), ('etc/group', 0, (3,)),
                                       ('etc/shadow', 0, ()), ('etc/gshadow', 0, (2, 3))):
            recs = {}
            for line in (read(os.path.join(root, rel)) or '').split('\n'):
                if not line.strip():
                    continue
                f = line.split(':')
                if len(f) < 3 and rel in ('etc/passwd', 'etc/group'):
                    continue
                recs[f[key_at]] = f
            out[rel] = recs
        return out

    acct_expected, acct_bad = {}, []
    for _, root in layers:
        for rel, recs in accounts(root).items():
            tgt = acct_expected.setdefault(rel, {})
            for k, f in recs.items():
                if k not in tgt:
                    tgt[k] = list(f); continue
                member_at = {'etc/group': (3,), 'etc/gshadow': (2, 3)}.get(rel, ())
                cur = tgt[k]
                new = list(f)
                for mi in member_at:
                    if mi < len(cur) and mi < len(f):
                        mem = [x for x in cur[mi].split(',') if x]
                        for x in f[mi].split(','):
                            if x and x not in mem:
                                mem.append(x)
                        new[mi] = ','.join(mem)
                tgt[k] = new
    got = accounts(merged)
    for rel, acct_want in acct_expected.items():
        missing = sorted(set(acct_want) - set(got.get(rel, {})))
        if missing:
            acct_bad.append("%s missing %d: %s" % (rel, len(missing), ', '.join(missing[:6])))
            continue
        for k, f in acct_want.items():
            g = got[rel][k]
            # identity fields only: gecos/home/shell may legitimately differ
            id_fields = (2, 3) if rel == 'etc/passwd' else ((2,) if rel == 'etc/group' else ())
            for i in id_fields:
                if i < len(f) and i < len(g) and f[i] != g[i]:
                    acct_bad.append("%s '%s' field %d is %s, union says %s"
                                    % (rel, k, i, g[i], f[i]))
            for mi in {'etc/group': (3,), 'etc/gshadow': (2, 3)}.get(rel, ()):
                if mi < len(f) and mi < len(g):
                    wm = {x for x in f[mi].split(',') if x}
                    gm = {x for x in g[mi].split(',') if x}
                    if wm - gm:
                        acct_bad.append("%s '%s' lost members %s"
                                        % (rel, k, ','.join(sorted(wm - gm))))
    acct_ok = not acct_bad
    n_acct = sum(len(v) for v in acct_expected.values())

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

    # ---- V7: every file in any layer is VISIBLE, AND IS THE SAME FILE ----
    # V7 v1 compared directory ENTRY NAMES and was defeated three ways on
    # 2026-09-17, each with a reproduction:
    #   (a) a module shipping `dir -> decoy` plus decoy/<same name> replaced
    #       1 MB of another module's payload with 6 bytes. The name was present,
    #       so v1 passed. This is EXACTLY what V7 was written to catch.
    #   (b) an ABSOLUTE symlink (/etc) was resolved by os.path.join against the
    #       HOST's root, because this runs outside the chroot. v1's verdict
    #       therefore depended on the checking machine in both directions:
    #       false negative when the host had matching names, false positive
    #       when it did not. That breaks "artefact + manifest is self-sufficient".
    #   (c) jammy is merged-/usr, so base ships lib -> usr/lib. A module shipping
    #       a REAL lib/ directory outranks the symlink, /lib/x86_64-linux-gnu/
    #       ld-linux-*.so becomes unreachable and NOTHING in the system can
    #       execute -- with every file still present and v1 clean.
    #
    # So: descend only into REAL directories (no symlink is ever traversed, which
    # is what confines resolution to the artefacts), record (kind, size) rather
    # than names, and require the merged entry to match SOME layer's version of
    # that path. Last-wins between layers stays legal; content arriving from
    # outside every layer does not.
    SKIP_TOP = {'proc', 'sys', 'dev', 'run', 'tmp'}
    # Reconciliation deliberately rewrites these, so they match no single layer.
    RECONCILED = {'etc/passwd', 'etc/group', 'etc/shadow', 'etc/gshadow',
                  'etc/subuid', 'etc/subgid', 'etc/ld.so.cache',
                  'var/lib/dpkg/status', 'var/lib/dpkg/status-old',
                  'var/lib/dpkg/diversions', 'var/lib/apt/extended_states',
                  'var/cache/ldconfig/aux-cache',
                  # reconcile.py merges the debconf databases as of 2026-09-18,
                  # so the merged copies deliberately match no single layer.
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
                        # A WHITEOUT is a character device 0:0, and it means the
                        # opposite of everything else here: the path must be
                        # ABSENT from the merged view. Scored as 'o' it made V7
                        # demand to find the deletion marker in the merge and
                        # report MISSING when OverlayFS had correctly honoured
                        # it -- a false positive on legitimate composition,
                        # waiting for the day removal support lands (H6).
                        # Latent today only because 02_build_delta.sh refuses to
                        # build a module containing one.
                        st = e.stat(follow_symlinks=False)
                        out[r] = ('w', 0) if (stat.S_ISCHR(st.st_mode)
                                              and st.st_rdev == 0) else ('o', 0)
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
        # RECONCILED paths are exempt from the (kind, size) COMPARISON, because
        # reconciliation rewrites them on purpose and they match no single
        # layer. They were also exempt from the EXISTENCE test, which is a
        # different concession and nothing justified it: a merged
        # templates.dat truncated to zero bytes, or an /etc/alternatives
        # emptied of every link, passed with vis_ok=1 and no other check covers
        # either -- V3 reads the dpkg alternatives REGISTRY, never the symlinks
        # it is supposed to produce. Existence is still required here.
        if r in RECONCILED or r.startswith(RECONCILED_PREFIX):
            if 'w' not in kinds and r not in vis_got:
                vis_missing.append('MISSING /%s (reconciled path, so only its '
                                   'existence is checked)' % r)
            continue
        if 'w' in kinds:
            # Some layer DELETES this path. Whether the merge should show it
            # depends on stacking order, which this check does not model. It
            # declines to judge rather than guessing -- but it says so, out of
            # band, instead of counting a correct deletion as file loss or
            # skipping it in silence. Zero on the present catalogue, because
            # 02_build_delta.sh refuses to build a module containing a whiteout.
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

    # Not a failure and not silence: a path V7 declined to judge is written to
    # stderr on every run, so "vis_ok=1" never quietly means "did not look".
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
        # A structurally clean composition of a tier-1-rejected set is a
        # known-negative observation, never a verification.
        ('PASS' if admitted != 'known-negative' else 'KNOWN_NEGATIVE')
        if ok else 'FAIL']))
    if not ok:
        # Distinguish "a package is gone" from "the wrong version survived" --
        # they are different defects and the second was previously invisible.
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
