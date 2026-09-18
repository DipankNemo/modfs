#!/usr/bin/env python3
"""Regression tests for V7, built from the three ways V7 v1 was defeated.

The 2026-09-17 attack session reproduced these and the fixtures were NOT kept,
so they had to be rebuilt to test the fix. They live here now. Run unprivileged:

    python3 tests/v7_attacks.py

Each case is a real failure that V7 v1 passed:
  FN-2b  a module redirects a directory to a decoy carrying the same entry name,
         replacing 1 MB of another module's payload with 5 bytes
  FN-2c  an ABSOLUTE symlink resolved against the HOST's root, so the verdict
         depended on the machine running the check
  FN-8   a module ships a real lib/ directory where merged-/usr base ships a
         lib -> usr/lib symlink; every file is present and nothing can execute
BENIGN is the control: an ordinary last-wins override must NOT be reported.
"""
import io, os, shutil, stat, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))

def v7_from_source():
    """Run the REAL V7 out of verify_compose.py, so this cannot drift from it."""
    src = io.open(os.path.join(HERE, '..', 'scripts', 'verify_compose.py'),
                  encoding='utf-8').read()
    a = src.index('    SKIP_TOP = {')
    b = src.index('    vis_ok = not vis_missing') + len('    vis_ok = not vis_missing')
    blk = src[a:b]
    return '\n'.join(l[4:] if l.startswith('    ') else l for l in blk.split('\n'))

def build(tmp):
    def w(p, data):
        os.makedirs(os.path.dirname(p), exist_ok=True)
        io.open(p, 'wb').write(data)
    j = lambda *p: os.path.join(tmp, *p)

    w(j('la','usr','lib','attlib','data.bin'), b'\0' * 1048576)
    w(j('lb','usr','lib','attdecoy','data.bin'), b'decoy')
    os.symlink('attdecoy', j('lb','usr','lib','attlib'))
    w(j('merged_b','usr','lib','attdecoy','data.bin'), b'decoy')
    os.symlink('attdecoy', j('merged_b','usr','lib','attlib'))

    w(j('le','usr','lib','attetc','passwd'), b'guest-passwd')
    w(j('le','usr','lib','attetc','group'),  b'guest-group')
    os.makedirs(j('lh','usr','lib')); os.symlink('/etc', j('lh','usr','lib','attetc'))
    os.makedirs(j('merged_e','usr','lib')); os.symlink('/etc', j('merged_e','usr','lib','attetc'))

    w(j('lbase','usr','lib','ld.so'), b'ld.so')
    os.symlink('usr/lib', j('lbase','lib'))
    w(j('lmod','lib','modules','x','drv.ko'), b'ko')
    w(j('merged_c','usr','lib','ld.so'), b'ld.so')
    w(j('merged_c','lib','modules','x','drv.ko'), b'ko')

    w(j('ben1','etc','cfg'), b'one')
    w(j('ben2','etc','cfg'), b'twotwo')
    w(j('merged_ben','etc','cfg'), b'twotwo')

CASES = [("FN-2b decoy symlink", ['la','lb'],       'merged_b',   False),
         ("FN-2c host escape",   ['le','lh'],       'merged_e',   False),
         ("FN-8  real lib dir",  ['lbase','lmod'],  'merged_c',   False),
         ("BENIGN last-wins",    ['ben1','ben2'],   'merged_ben', True)]

def main():
    blk = v7_from_source()
    tmp = tempfile.mkdtemp(prefix='v7attacks-')
    try:
        build(tmp)
        bad = 0
        for name, lyrs, merged, want_ok in CASES:
            ns = {'os': os, 'stat': stat,
                  'layers': [(l, os.path.join(tmp, l)) for l in lyrs],
                  'merged': os.path.join(tmp, merged)}
            exec(blk, ns)
            ok = ns['vis_ok']
            good = (ok == want_ok)
            bad += 0 if good else 1
            print("  %-22s vis_ok=%-5s findings=%-3d %s"
                  % (name, ok, len(ns['vis_missing']), "ok" if good else "*** WRONG ***"))
            if not good:
                for x in ns['vis_missing'][:3]:
                    print("      %s" % x)
        print("  %d/%d cases correct" % (len(CASES) - bad, len(CASES)))
        return 1 if bad else 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

if __name__ == '__main__':
    sys.exit(main())
