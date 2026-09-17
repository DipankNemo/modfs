#!/usr/bin/env python3
"""Draw tier-1-ADMISSIBLE module sets for the tier-2 compose sweep.

    sample_sets.py --spec specs/modules.yaml --mod-dir DIR --seed N
                   --plan 2:30,27:10,36:2 --out samples.txt [--pairs pairs.csv]

The previous sampler drew N modules uniformly at random and let tier-1
admission throw the draw away afterwards.  That is fine while almost every
draw is admissible and useless once it is not:

    N=2   94.6 % of uniform draws admissible     N=27  38.1 %
    N=20  53.3 %                                 N=36   5.4 %

With one planned sample at N=27 the probability of composing NOTHING there was
0.62, and that is exactly what happened -- the top of the cost-vs-N curve was
empty because the sampler could not see the constraints, not because tier 2
could not compose high-N sets.

So the draw is made constraint-aware.  The model PROPOSES, tier 1 still
DECIDES: every set this script emits is still put through 05_check.sh by the
caller, and a set the model believes admissible but tier 1 rejects is a
disagreement worth reporting, not something to paper over.

THE MODEL HAS TWO HALVES, and conflating them is the mistake this file exists
to avoid.  A tier-1 rejection of {a, b} can mean either of two things:

  EXCLUSION     a and b cannot coexist        (mta-msmtp + mta-nullmailer,
                                               a Conflicts: expressed only
                                               through a virtual name)
  IMPLICATION   a needs something b is not    (fake-cuda requires a module
                                               providing nvidia-driver)

They look identical in a pair sweep and behave oppositely at scale.  fake-cuda
is rejected against 35 of 36 siblings, yet it belongs in the largest admitted
set the catalogue has -- because the driver is in there too.  Treating its
rejections as exclusion edges would banish it from every high-N sample and
quietly shrink the catalogue.  So requirements are read from the manifests
(ARCHITECTURE section 5) and used to EXPLAIN rejections; only the unexplained
residue becomes an exclusion edge.

Exclusions are therefore MEASURED, not declared: they come from a real tier-1
pair sweep, so a conflict nobody wrote down in modules.yaml is still learned.
Without --pairs the model knows only what the manifests declare, which for
this catalogue misses the mail-transport-agent pair; the caller passes one.

Sampling method per plan point, reported in the output because it changes what
the sample means:

  exact     the admissible space (or its complement) is small enough to
            enumerate, so sets are drawn uniformly from ALL admissible sets
            and the count printed is exact.  Covers the top of the range,
            where the complement is tiny: at N=36 of 37 there are exactly 2
            admissible sets, and a plan asking for 5 must say so rather than
            spin.
  sampled   the space is too large to enumerate; sets are built by a seeded
            closure-aware greedy draw.  Reproducible, but NOT uniform over
            admissible sets -- stated rather than glossed.

Exit: 0 a plan was written, 2 the inputs are unusable.
"""
import csv
import itertools
import json
import os
import random
import subprocess
import sys

ENUM_MAX = 200000          # combinations we are willing to enumerate outright
ATTEMPT_MULT = 200         # greedy draws attempted per set actually wanted


def die(msg):
    sys.stderr.write("sample_sets: %s\n" % msg)
    sys.exit(2)


def arg(argv, name, default=None, required=False):
    if name in argv:
        i = argv.index(name)
        if i + 1 >= len(argv):
            die("%s needs a value" % name)
        return argv[i + 1]
    if required:
        die("%s is required" % name)
    return default


# ---------------------------------------------------------------- versions
_vcache = {}


def vcmp(v1, op, v2):
    """dpkg version comparison, memoised -- the same few pairs recur."""
    key = (v1, op, v2)
    if key not in _vcache:
        try:
            _vcache[key] = subprocess.run(
                ['dpkg', '--compare-versions', v1, op, v2]).returncode == 0
        except Exception:
            _vcache[key] = False
    return _vcache[key]


# ---------------------------------------------------------------- the model
class Model:
    """Module-level admissibility: exclusions and requirements.

    Mirrors the module-level half of 05_check.sh deliberately.  It is a
    PREDICTION of that checker's verdict, never a replacement for it.
    """

    def __init__(self, mods, docs):
        self.mods = mods
        self.version = {}
        self.requires = {}                  # module -> [(capability, constraint)]
        self.excl = set()                   # frozenset({a, b})
        self.providers = {}                 # capability -> [(module, version)]

        for m in ['base'] + mods:
            d = docs.get(m) or {}
            ver = str(d.get('version') or '0')
            self.version[m] = ver
            self.providers.setdefault(m, []).append((m, ver))
            for cap in (d.get('provides') or []):
                self.providers.setdefault(str(cap), []).append((m, ver))

        for m in ['base'] + mods:
            d = docs.get(m) or {}
            reqs = []
            for r in (d.get('requires') or []):
                if isinstance(r, dict) and r.get('module'):
                    reqs.append((str(r['module']), (r.get('constraint') or '').strip()))
            self.requires[m] = reqs
            # Declared module-level conflicts are exclusions by definition;
            # measured ones arrive later via learn_exclusions().
            for c in (d.get('conflicts') or []):
                want = str(c.get('module') or '') if isinstance(c, dict) else str(c)
                for other in mods:
                    if other != m and want in (other, *(docs.get(other, {}).get('provides') or [])):
                        self.excl.add(frozenset((m, other)))

    # -- requirement satisfaction, exactly as 05_check.sh computes it -------
    def _sat(self, cap, cons, present):
        """Is capability `cap` at `cons` provided by a module in `present`?"""
        for pm, pv in self.providers.get(cap, ()):
            if pm not in present:
                continue
            if not cons:
                return True
            parts = cons.split(None, 1)
            if len(parts) > 1 and vcmp(pv, parts[0], parts[1].strip()):
                return True
        return False

    def unmet(self, members):
        """Modules in `members` whose requirements the set does not satisfy."""
        present = set(members) | {'base'}
        bad = []
        for m in present:
            for cap, cons in self.requires.get(m, ()):
                if not self._sat(cap, cons, present):
                    bad.append(m)
                    break
        return bad

    def excluded_pair(self, members):
        """First exclusion edge wholly inside `members`, or None."""
        s = set(members)
        for e in self.excl:
            if e <= s:
                return e
        return None

    def admissible(self, members):
        return not self.unmet(members) and self.excluded_pair(members) is None

    # -- learn exclusions from measured pair verdicts ----------------------
    def learn_exclusions(self, pair_rows):
        """A rejected pair the requirement model cannot explain is an edge.

        This is the whole point of the file: fake-cuda's 35 rejections ARE
        explained (its requirement is unmet in those pairs) and must not
        become edges; mta-msmtp + mta-nullmailer is not explained by anything
        in the manifests and must.
        """
        learned, explained = [], 0
        known = set(self.mods)
        for r in pair_rows:
            if (r.get('verdict') or '').startswith('ACCEPT'):
                continue
            pair = (r.get('modules') or '').split()
            if len(pair) != 2 or not set(pair) <= known:
                continue                    # control-oldsnap and friends
            if self.unmet(pair):
                explained += 1
                continue
            e = frozenset(pair)
            if e not in self.excl:
                self.excl.add(e)
                learned.append(sorted(e))
        return learned, explained

    # -- drawing -----------------------------------------------------------
    def closure(self, m, have, rng):
        """{m} plus whatever must join it, or None if that is impossible.

        A module with an unmet requirement is not a dead end: it is a module
        that drags a provider in with it.  Refusing to model that is what
        would have excluded fake-cuda from every high-N set.
        """
        need, usable = {m}, set(self.mods)
        changed = True
        while changed:
            changed = False
            present = have | need | {'base'}
            for x in sorted(need):
                for cap, cons in self.requires.get(x, ()):
                    if self._sat(cap, cons, present):
                        continue
                    cands = [pm for pm, pv in self.providers.get(cap, ())
                             if pm in usable and pm not in present
                             and (not cons or self._sat(cap, cons, {pm}))]
                    # A provider that conflicts with what we already hold is
                    # no provider at all.
                    cands = [pm for pm in cands
                             if self.excluded_pair(present | {pm}) is None]
                    if not cands:
                        return None
                    rng.shuffle(cands)
                    need.add(cands[0])
                    changed = True
                    break
                if changed:
                    break
        if self.unmet(have | need):
            return None
        return need

    def draw_greedy(self, n, rng):
        """One closure-aware greedy draw, or None if this shuffle ran short."""
        order = list(self.mods)
        rng.shuffle(order)
        have = set()
        for m in order:
            if len(have) >= n:
                break
            if m in have:
                continue
            group = self.closure(m, have, rng)
            if group is None or len(have) + len(group) > n:
                continue
            cand = have | group
            if self.excluded_pair(cand) is not None:
                continue
            have = cand
        if len(have) != n or not self.admissible(have):
            return None
        return frozenset(have)

    def enumerate_admissible(self, n, cap):
        """All admissible N-sets, or None if that would cost more than `cap`.

        Enumerates whichever of the set or its COMPLEMENT is smaller.  At the
        top of the range the complement is what is small: at N=36 of 37 there
        are 37 candidate sets to filter, not 37-choose-36 worth of work in the
        other direction.  That is precisely the region this task is about.
        """
        M = len(self.mods)
        k = min(n, M - n)
        total = 1
        for i in range(k):
            total = total * (M - i) // (i + 1)
            if total > cap:
                return None
        out = []
        if n <= M - n:
            for c in itertools.combinations(self.mods, n):
                if self.admissible(c):
                    out.append(frozenset(c))
        else:
            allm = set(self.mods)
            for c in itertools.combinations(self.mods, M - n):
                s = allm - set(c)
                if self.admissible(s):
                    out.append(frozenset(s))
        return out


# ---------------------------------------------------------------- inputs
def load_modules(spec_path, mod_dir):
    """Catalogue entries that actually built, minus the positive control."""
    import yaml
    try:
        doc = yaml.safe_load(open(spec_path, encoding='utf-8')) or {}
    except Exception as exc:
        die("cannot read %s: %s" % (spec_path, exc))
    mods, control = [], []
    for m in (doc.get('modules') or []):
        n = m.get('name')
        if not n or n == 'base':
            continue
        if not os.path.exists(os.path.join(mod_dir, n + '.sqsh')):
            continue
        if m.get('snapshot'):
            control.append(n)               # different snapshot: excluded by design
            continue
        mods.append(n)
    return sorted(mods), sorted(control)


def load_docs(mod_dir, mods):
    docs = {}
    for m in ['base'] + mods:
        p = os.path.join(mod_dir, m + '.json')
        try:
            docs[m] = json.load(open(p, encoding='utf-8'))
        except Exception as exc:
            die("cannot read manifest %s: %s" % (p, exc))
    return docs


def main(argv):
    spec = arg(argv, '--spec', required=True)
    mod_dir = arg(argv, '--mod-dir', required=True)
    seed = int(arg(argv, '--seed', '1'))
    plan = arg(argv, '--plan', required=True)
    out = arg(argv, '--out', required=True)
    pairs_csv = arg(argv, '--pairs')
    enum_max = int(arg(argv, '--enum-max', str(ENUM_MAX)))

    mods, control = load_modules(spec, mod_dir)
    if len(mods) < 2:
        die("fewer than 2 usable modules under %s" % mod_dir)
    model = Model(mods, load_docs(mod_dir, mods))

    print("  modules usable      : %d  (control excluded: %s)"
          % (len(mods), ', '.join(control) or 'none'))

    if pairs_csv:
        try:
            rows = list(csv.DictReader(open(pairs_csv, encoding='utf-8')))
        except Exception as exc:
            die("cannot read pair verdicts %s: %s" % (pairs_csv, exc))
        learned, explained = model.learn_exclusions(rows)
        print("  pair verdicts read  : %d" % len(rows))
        print("  rejections explained by an unmet requirement: %d" % explained)
        print("  exclusion edges learned: %d%s"
              % (len(learned),
                 ''.join("\n      %s + %s" % (a, b) for a, b in learned)))
    else:
        print("  NO --pairs given: exclusions are only those DECLARED in the")
        print("  manifests. A conflict expressed through a virtual package name")
        print("  will not be known, and high-N draws may be refused by tier 1.")

    # Feasibility ceiling. A catalogue containing a deliberate conflict pair
    # cannot be composed whole, and saying which N is the real top of the
    # range beats letting a plan point quietly produce nothing.
    rng = random.Random(seed)
    ceiling = 0
    for n in range(len(mods), 1, -1):
        got = model.enumerate_admissible(n, enum_max)
        if got is None:                     # too big to enumerate: assume feasible
            ceiling = n
            break
        if got:
            ceiling = n
            break
    print("  largest admissible N: %d of %d modules" % (ceiling, len(mods)))

    rows, notes = [], []
    for part in plan.split(','):
        part = part.strip()
        if not part:
            continue
        n_s, _, c_s = part.partition(':')
        try:
            n, want = int(n_s), int(c_s)
        except ValueError:
            die("bad plan element '%s' -- expected N:COUNT" % part)
        if n < 2:
            notes.append("N=%d skipped (a composition needs at least 2 modules)" % n)
            continue
        if n > len(mods):
            notes.append("N=%d skipped (only %d modules usable)" % (n, len(mods)))
            continue

        pool = model.enumerate_admissible(n, enum_max)
        if pool is not None:
            method, avail = 'exact', len(pool)
            if not pool:
                notes.append("N=%d INFEASIBLE: no admissible set of this size exists"
                             % n)
                continue
            rng.shuffle(pool)
            picked = pool[:want]
        else:
            method, seen, picked = 'sampled', set(), []
            budget = max(200, want * ATTEMPT_MULT)
            for _ in range(budget):
                if len(picked) >= want:
                    break
                s = model.draw_greedy(n, rng)
                if s is None or s in seen:
                    continue
                seen.add(s)
                picked.append(s)
            avail = None
            if not picked:
                notes.append("N=%d: %d draws produced no admissible set" % (n, budget))
                continue

        if len(picked) < want:
            notes.append("N=%d: asked for %d, %s"
                         % (n, want,
                            "only %d admissible sets exist" % avail if avail is not None
                            else "only %d distinct sets found" % len(picked)))
        for s in picked:
            rows.append((n, sorted(s), method))

    with open(out, 'w', encoding='utf-8') as f:
        for n, c, _ in rows:
            f.write("%d\t%s\n" % (n, ' '.join(c)))

    print("  compositions planned: %d" % len(rows))
    print("    %-5s %-8s %-8s %s" % ("N", "planned", "method", "admissible sets"))
    for n in sorted({r[0] for r in rows}):
        same = [r for r in rows if r[0] == n]
        pool = model.enumerate_admissible(n, enum_max)
        avail = "%d (exact)" % len(pool) if pool is not None else "too many to count"
        print("    %-5d %-8d %-8s %s" % (n, len(same), same[0][2], avail))
    for s in notes:
        print("  NOTE %s" % s)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
