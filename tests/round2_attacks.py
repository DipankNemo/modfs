#!/usr/bin/env python3
"""Regression tests from the 2026-09-18 round-2 attack session.

    python3 tests/round2_attacks.py        # unprivileged, no artefacts needed

Like tests/v7_attacks.py this EXECUTES THE REAL CODE -- V7's block is pulled out
of verify_compose.py and the debconf merge is imported from reconcile.py -- so
the tests cannot drift from what ships.

Three kinds of case, and the third is the point of keeping them together:

  FIXED      a defect found in round 2 and closed. The test fails if it returns.
  CONTROL    legitimate composition that must NOT be reported. A check that
             rejects correct input is as damaging as one that misses a defect,
             and every hardening in this project has had to prove this.
  KNOWN OPEN a defect found in round 2 and deliberately NOT closed, with the
             reason recorded in JOURNAL.md. The expected value is today's
             BEHAVIOUR, not today's wish, so the suite stays green -- and the
             day someone closes it, this file fails and says so instead of the
             limitation quietly disappearing from the evidence.
"""
import io, os, shutil, socket, stat, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'scripts'))

def v7_block():
    src = io.open(os.path.join(HERE, '..', 'scripts', 'verify_compose.py'),
                  encoding='utf-8').read()
    a = src.index('    SKIP_TOP = {')
    b = src.index('    vis_ok = not vis_missing') + len('    vis_ok = not vis_missing')
    return '\n'.join(l[4:] if l.startswith('    ') else l
                     for l in src[a:b].split('\n'))

def run_v7(tmp, layers, merged):
    ns = {'os': os, 'stat': stat,
          'layers': [(l, os.path.join(tmp, l)) for l in layers],
          'merged': os.path.join(tmp, merged)}
    exec(v7_block(), ns)
    return ns['vis_ok'], ns['vis_missing'], ns.get('vis_unchecked', [])

def w(p, data):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    io.open(p, 'wb').write(data)

# --------------------------------------------------------------- V7 fixtures
def build_v7(t):
    j = lambda *p: os.path.join(t, *p)

    # R2-2 KNOWN OPEN: (kind, size) is not content. Same size, different bytes,
    # matching no layer. Reproduced on the real artefacts by replacing
    # /usr/bin/curl with 260328 bytes of 'X': the tier-2 row did not move.
    w(j('A1', 'usr/share/app/table.dat'), b'REAL-TABLE-0123456789')
    w(j('Am', 'usr/share/app/table.dat'), b'EVIL-TABLE-9876543210')

    # R2-2 KNOWN OPEN: a sparse hole preserves st_size and destroys the content.
    w(j('C1', 'var/lib/db/store'), b'D' * 4096)
    os.makedirs(j('Cm', 'var/lib/db'))
    f = io.open(j('Cm', 'var/lib/db/store'), 'wb'); f.truncate(4096); f.close()

    # R2-3 FIXED 2026-09-19: FIFO, socket, char and block devices used to all
    # score ('o', 0), so swapping one special file for another compared equal.
    # They now score 'p'/'s'/'c'/'b', and device nodes carry st_rdev, so
    # /dev/null becoming /dev/sda is a change of content and not only of kind.
    os.makedirs(j('B1', 'usr/lib/svc')); os.mkfifo(j('B1', 'usr/lib/svc/ctl'))
    os.makedirs(j('Bm', 'usr/lib/svc'))
    s = socket.socket(socket.AF_UNIX); s.bind(j('Bm', 'usr/lib/svc/ctl')); s.close()

    # R2-4 FIXED: a RECONCILED path is exempt from COMPARISON, never from
    # EXISTENCE. Both /etc/alternatives entries deleted from the merge.
    os.makedirs(j('F1', 'etc/alternatives'))
    os.symlink('/usr/bin/vim', j('F1', 'etc/alternatives/editor'))
    w(j('F1', 'etc/alternatives/README'), b'not a symlink at all')
    os.makedirs(j('F2', 'etc/alternatives')); os.makedirs(j('Fm', 'etc/alternatives'))

    # R2-4 CONTROL: reconciliation legitimately rewrites the content of a
    # reconciled path. Present but different must still pass.
    w(j('R1', 'var/lib/dpkg/status'), b'Package: a\n')
    w(j('R2', 'var/lib/dpkg/status'), b'Package: b\n')
    w(j('Rm', 'var/lib/dpkg/status'), b'Package: a\n\nPackage: b\n')

    # R2-5 FIXED: a whiteout is a char device 0:0 and means the path must be
    # ABSENT. V7 used to demand to find it and report MISSING.
    w(j('G1', 'etc/keepme'), b'base file')
    os.makedirs(j('G2', 'etc')); os.makedirs(j('Gm', 'etc'))
    try:
        os.mknod(j('G2', 'etc/keepme'), stat.S_IFCHR | 0o600, os.makedev(0, 0))
        have_whiteout = True
    except OSError:
        have_whiteout = False

    # CONTROL: ordinary last-wins between two layers is legal and must be silent.
    w(j('L1', 'etc/cfg'), b'one'); w(j('L2', 'etc/cfg'), b'twotwo')
    w(j('Lm', 'etc/cfg'), b'twotwo')
    return have_whiteout

V7_CASES = [
    ("R2-2 same-size swap",   "KNOWN OPEN", ['A1'],       'Am', True),
    ("R2-2 sparse hole",      "KNOWN OPEN", ['C1'],       'Cm', True),
    ("R2-3 FIFO -> socket",   "FIXED",      ['B1'],       'Bm', False),
    ("R2-4 reconciled wiped", "FIXED",      ['F1', 'F2'], 'Fm', False),
    ("R2-4 reconciled merge", "CONTROL",    ['R1', 'R2'], 'Rm', True),
    ("R2-5 whiteout",         "FIXED",      ['G1', 'G2'], 'Gm', True),
    ("last-wins override",    "CONTROL",    ['L1', 'L2'], 'Lm', True),
]

# --------------------------------------------------------------- debconf cases
def debconf_cases(t):
    from reconcile import merge_debconf
    out = []
    def layer(n, text):
        p = os.path.join(t, n, 'var/cache/debconf/config.dat')
        os.makedirs(os.path.dirname(p), exist_ok=True)
        io.open(p, 'w').write(text)
        return (n, os.path.join(t, n))

    def merge(tag, layers):
        m = os.path.join(t, 'M' + tag); os.makedirs(m, exist_ok=True)
        summary, problems = merge_debconf(layers, m)
        body = io.open(os.path.join(m, 'var/cache/debconf/config.dat')).read()
        return summary, problems, body

    # R2-6 FIXED: a stanza with no Name was discarded in silence.
    _, pr, body = merge('6', [layer('d6',
        "Name: q/a\nValue: yes\n\nTemplate: q/orphan\nValue: SECRET\n")])
    out.append(("R2-6 Name-less stanza", "FIXED",
                any('has no Name' in p for p in pr)))

    # R2-7 FIXED: three layers disagreeing named layer 1 as the source twice.
    _, pr, _ = merge('7', [layer('a', "Name: q/a\nValue: AAA\n"),
                           layer('b', "Name: q/a\nValue: BBB\n"),
                           layer('c', "Name: q/a\nValue: CCC\n")])
    out.append(("R2-7 three-way attribution", "FIXED",
                len(pr) == 2 and "'BBB' in b" in pr[1] and "'AAA' in a" in pr[0]))

    # CONTROL: Owners unions, whitespace and duplicates normalise, no conflict.
    _, pr, body = merge('o', [layer('o1', "Name: q/a\nOwners: alpha, beta\nValue: 1\n"),
                              layer('o2', "Name: q/a\nOwners: beta,gamma\nValue: 1\n"),
                              layer('o3', "Name: q/a\nOwners: gamma , delta\nValue: 1\n")])
    out.append(("Owners union", "CONTROL",
                not pr and 'Owners: alpha, beta, gamma, delta' in body))

    # CONTROL: templates.dat continuation lines survive the round trip.
    _, pr, body = merge('c', [layer('c1',
        "Name: q/a\nDescription: short\n line two\n line three\nValue: yes\n")])
    out.append(("continuation lines", "CONTROL",
                not pr and ' line two\n line three' in body))
    return out

# --------------------------------------------------------------------- driver
def main():
    tmp = tempfile.mkdtemp(prefix='round2-')
    bad = 0
    try:
        have_whiteout = build_v7(tmp)
        print("  V7")
        for name, kind, lyrs, merged, want_ok in V7_CASES:
            if name.startswith('R2-5') and not have_whiteout:
                print("    %-24s %-10s SKIPPED (mknod needs privilege here)"
                      % (name, kind)); continue
            ok, missing, declined = run_v7(tmp, lyrs, merged)
            good = (ok == want_ok)
            bad += 0 if good else 1
            print("    %-24s %-10s vis_ok=%-5s findings=%-2d declined=%-2d %s"
                  % (name, kind, ok, len(missing), len(declined),
                     "ok" if good else "*** WRONG ***"))
            if not good:
                for x in (missing or declined)[:3]:
                    print("        %s" % x)
        print("  debconf")
        for name, kind, good in debconf_cases(tmp):
            bad += 0 if good else 1
            print("    %-24s %-10s %s" % (name, kind, "ok" if good else "*** WRONG ***"))
        total = len(V7_CASES) + 4
        print("  %d/%d cases correct" % (total - bad, total))
        return 1 if bad else 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

if __name__ == '__main__':
    sys.exit(main())
