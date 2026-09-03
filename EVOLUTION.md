# How this project evolved

A chronological account. Each phase states the question asked, what was done,
what came back, and — the important part — **what that result forced next.**
Nothing here was planned in advance; each step exists because the previous one
produced a result that demanded it.

---

## Phase 0 — June. The naive design

**Question:** is modular composition physically possible at all?

**Done:** each module built by its own `debootstrap`. Packages installed.
Squashed. Stacked with OverlayFS. Packed into an image. Booted, logged in.

**Result:** it worked. The image booted.

**But three things were wrong, none visible at the time:**
- Every module contained a **full second copy of Ubuntu** — you cannot install
  nginx into an empty directory, so apt needed a complete system to install
  into. Zero deduplication, which was the entire point.
- Each module carried its own `/var/lib/dpkg/status`. Unnoticed.
- Validation used `apt --simulate` against the *live* archive — which tests
  whether package **names** co-install today, not whether the **frozen
  binaries** in the modules are consistent. Wrong question.

**Forced next:** the "is it possible" question was closed. The real question —
"is the obvious way correct?" — was not yet asked.

---

## Phase 1 — 29 July. Verify the assumptions before building

**Question:** the new design depends on two things being true. Are they?

- **A:** can the archive be pinned to a fixed date?
- **B:** does an OverlayFS upperdir survive compression?

B was the risk nobody had checked. A deletion in an overlay is not an absence —
it is a **character device `0:0`**, a file whose only purpose is to say "hide
what is below me." A directory replacement is an xattr, `trusted.overlay.opaque`.
If SquashFS dropped either, delta modules could add files but never remove or
replace one, and the architecture was dead.

**Done:** `00_verify.sh` fabricated exactly that situation with three text
files — one kept, one deleted, one directory replaced — squashed the upperdir,
remounted it, and asserted all three behaved.

**Result: 30 checks, 30 passed.** All three archive pockets resolved under the
pinned snapshot URL.

**Forced next:** deltas are viable. Build the delta builder.

---

## Phase 2 — The delta builder

**Question:** how do you build a module containing only what changed?

**Done:** mount the parent read-only as lowerdir, overlay an empty upperdir,
`chroot` into the **merged** view, `apt install`, then squash **only the
upperdir**. Because apt looks at the merged view, it sees base as already
installed and writes only what is genuinely new. The filesystem captures the
diff; nothing computes it.

**Result:** base 40 MB / 113 packages · webserver 21 MB / +42 · pytools
25 MB / +24. Against ~176 MB per module under the June design.

**Forced next:** with two real deltas in hand, the question became: what happens
when you actually stack them?

---

## Phase 3 — Measure the overlap instead of guessing it

**Question:** which files appear in both deltas, and which of those actually
differ?

**Done:** `03_analyse_overlap.sh` byte-compared every shared file with `cmp` —
not size, not hash, so two files of equal size but different content are
correctly separated.

**Result:** ~5 000 files, **28 shared, 17 byte-identical, 11 differ.**

A prediction failed and was recorded: `/etc/passwd` and `/etc/group` were
expected to collide. They did not — base already provides `www-data`.

All 11 differing files were **generated during the build** (`status`, logs,
caches). Nothing unpacked from a `.deb` differed. That sharpened the claim:
**shipped files never conflict under pinning; only generated state does.**

**Forced next:** one of those 11 was `/var/lib/dpkg/status`. That needed
investigating.

---

## Phase 4 — The dpkg state defect

**Question:** if every module carries its own package database, what does the
merged system believe?

**Done:** composed base + webserver + pytools and counted.

**Result:**

```
packages the catalogue lists : 137
packages actually installed  : 178
INVISIBLE                    :  41

dpkg says 'nginx' : NOT INSTALLED
  but on disk:  PRESENT: /usr/sbin/nginx
```

The system was running software it did not know it had. On a real node `apt`
would reinstall packages already present, and `autoremove` could delete files
another module depends on.

**Fix:** compute the correct catalogue as a union of stanzas and write it into a
reconciliation layer above all modules. **178/178, 0 invisible.** It also makes
composition **order-independent** — without it, stacking order decides which
packages disappear.

**Forced next:** an arithmetic discrepancy in Phase 3's output — pytools
reported 27 added packages but only 24 new stanzas — was still unexplained.

---

## Phase 5 — Class 6, found by chasing a three-package discrepancy

**Question:** why 27 versus 24?

**Done:** compared pytools' package versions against base's, by hand.

**Result:** three packages were not *added* but **upgraded**:
`gcc-12-base`, `libgcc-s1`, `libstdc++6`.

Traced the chain:

```
python3-numpy → liblapack3 → libgfortran5 → gcc-12-base (= 12.3.0-1ubuntu1~22.04.3)
```

`libgfortran5` has an **exact-equality** dependency on `gcc-12-base`, and the
GCC runtime packages are version-locked to each other. One transitive dependency
dragged an entire lock-step cluster forward.

**Root cause:** `debootstrap` populates base from the plain `jammy` pocket while
delta builds see `jammy` + `-updates` + `-security`. Base was a year behind
before a single module was built.

**Fix:** one `apt-get full-upgrade` during the base build — 61 packages moved.
Checker now reports 0 upgrades.

**Forced next:** this was a conflict class nobody had listed. It became class 6,
and it proved the taxonomy was incomplete — which meant it needed tooling to
find classes, not just intuition.

---

## Phase 6 — The checker

**Question:** can a module set be validated without building anything?

**Done:** `05_check.sh`, reading metadata only. Detects base drift with
dependency-chain tracing, version skew, benign overlap, declared conflicts.

**Result:** ~1 second, no root, no network, no mounting. Verified to reject
synthetic faults.

**Forced next:** it was reading `/var/lib/dpkg/status` out of the *build tree* —
hundreds of MB of scratch data per module. A real server stores only `.sqsh`
files. That coupling had to go.

---

## Phase 7 — Manifests

**Done:** `06_extract_metadata.sh` writes `module.json` beside each artefact —
full relations, versions, snapshot, parent. Deltas store only their own
contribution, classified `added` / `upgraded` / `removed`.

**Found in passing:** the installed-test was `'installed' in status`, which is
also true of `purge ok not-installed`. Purged packages were counted as
installed.

**Forced next:** a claim recorded on a fresh machine — "byte-identical
artefacts" — had never actually been checked.

---

## Phase 8 — Determinism. Four causes, each hiding the next

**Question:** why do two builds of the same module produce different files?

This took four rounds because **each cause was invisible until the one above it
was fixed.**

| # | Cause | Fix |
|---|---|---|
| 1 | `mksquashfs` writes wall-clock time into the superblock and preserves mtimes | `-mkfs-time` / `-all-time` from `SNAPSHOT_ID` |
| 2 | Six build logs contain literal timestamps (`dpkg.log`, `apt/history.log`, `term.log`, `eipp.log.xz`, `alternatives.log`, `bootstrap.log`) | excluded — they record *how* the build went, not what the module *is* |
| 3 | OverlayFS xattrs | `-xattrs-exclude` for `uuid` and `origin`, keeping `opaque` |
| 4 | systemd's random `/etc/machine-id` | emptied, regenerates at first boot |

**Cause 3 is the interesting one.** The webserver delta carried 131 files with
overlay xattrs:

- **`opaque`, 59 files** — semantic. Directory replacement. **Assumption B
  depends on this.**
- **`origin`, 71 files** — an encoded file handle containing the *host
  filesystem's* UUID and the lower file's inode number
- **`impure`, 28** — constant, inert
- **`uuid`, 1** — random per mount

`origin` meant the artefacts carried 71 fingerprints of the specific disk they
were built on. Cross-host byte-identity was not unverified — it was
**impossible**.

And Assumption B, one of the 30 passing checks, had only ever asked *does
`opaque` survive?* It never asked **what else came along.** That gap is the
finding.

**Result:** all three artefacts byte-identical across rebuilds *and* across a
base rebuild — webserver's hash did not move even though base's **content**
changed underneath it twice.

Cause 4 has a nice convergence: emptying `machine-id` is correct golden-image
practice anyway, since otherwise every deployed node shares one identity and
collides on DHCP and journal IDs. The right answer for node identity turned out
to be the right answer for reproducibility.

**Forced next:** the taxonomy was still six classes measured on **two** modules.
That is anecdote, not evidence.

---

## Phase 9 — The catalogue and the sweep

**Question:** are there six classes because six exist, or because two modules can
only produce six?

**Done:** 27 modules chosen **adversarially** — picked to provoke specific
classes, not for realism. `vim`/`emacs`/`gawk`/`original-awk` for alternatives,
`nc-openbsd`/`nc-traditional` for file collision, `webserver`/`apache`/`redis`
for port conflicts, two MTAs for virtual packages, 15 fillers.

**Result:** 351 pairs, **all ACCEPT.**

**And that was the problem.** A working checker finding nothing and a broken
checker finding nothing produce identical output.

**Forced next:** the sweep had to be able to prove itself alive.

---

## Phase 10 — Self-validation, and two real defects

**Done, three things:**

1. **A positive control** — `control-oldsnap`, `curl` built from a **2025**
   snapshot while everything else is pinned to **2026**. Known-bad by
   construction. The smoke-alarm test.
2. **Virtual package resolution** — both MTAs declare
   `Conflicts: mail-transport-agent`. No package has that name; it is a
   *category* both claim membership in. The checker searched for a literal
   package, found none, reported nothing. Fixed with a category→members map,
   honouring the rule that an unversioned `Provides` satisfies only an
   unversioned relation.
3. **Class 4 detection** via `.files.json.zst` sidecars — each package's owned
   paths, extracted at build time because the build tree gets deleted.

**Result:** 378 pairs → **350 ACCEPT, 28 REJECT** (27 control + 1 MTA pair).
An all-ACCEPT sweep would now mean the sweep is broken.

Class 4 across 19 069 paths: exactly **4 collisions**, all MTA, all correctly
**suppressed** by `Replaces` — and reported as suppressed rather than dropped,
so the check is visibly alive on real data.

**A second failed prediction, and a good one.** `nc-openbsd` + `nc-traditional`
was expected to be class 4. It is not — they own `/bin/nc.openbsd` and
`/bin/nc.traditional`. `/bin/nc` is an alternatives symlink owned by **no
package at all**, so it appears in no file list and is structurally invisible to
ownership checking.

**Three of four adversarial pairs turned out to be class 5**, not the classes
predicted. Alternatives is where the collision pressure actually lives.

**Storage, now measured:** six modules built both ways. Extrapolation validated
to under 1 % across two orders of magnitude. Calibrated **5.35×**. The 0.7 %
bias has an explanation — a monolithic build compresses base and module
together, recovering cross-file redundancy separate compression cannot reach.

**Forced next:** class 5 was the last unhandled row, and three adversarial pairs
were sitting in it.

---

## Phase 11 — Triples, and the coverage argument

**Done:** all 3 654 pair and triple combinations.

**Result:** every triple rejection is **arithmetically accounted for** by a
rejecting pair inside it.

```
not composable:  378 = 27 pairs + C(27,2)=351 triples containing the control
declared conflict: 27 =  1 pair + C(26,1)= 26 triples containing both MTAs
REJECT triples:   376 = 351 + 26 − 1
```

Since every check is pairwise or per-module, triples **cannot** produce a
finding no pair produces. Exhaustive combination testing buys confirmation, not
coverage — so the combinatorial explosion is not where the risk lies.

---

## Phase 12 — Class 5 reconciliation

**Done:** one shared reconciler (`reconcile.py`) used by both `04` and `07`,
replacing two divergent implementations. Merges all four registries — dpkg
`status`, alternatives, diversions, `extended_states`.

**A deliberate non-decision:** `/etc/alternatives/*` symlinks and
`/etc/ld.so.cache` were **not** reimplemented. Neither is owned by a package;
both are *derived* from the merged registry. So `update-alternatives --auto`
and `ldconfig` compute them inside the merged chroot. Writing bespoke priority
and slave-resolution rules would have been a second implementation of something
that already exists.

**Result:**

| Set | Group | Before → After | Packages visible |
|---|---|---|---|
| base + vim + emacs | `editor` | 1 → 2 | 126 → 140/140 |
| base + gawk + original-awk | `awk` | 2 → 3 | 114 → 119/119 |
| base + nc-openbsd + nc-traditional | `nc` | 1 → 2 | 114 → 117/117 |

`awk` is 2→3 rather than 1→3 because `original-awk`'s registry already inherited
`mawk` from base — recorded honestly rather than rounded up.

**The best result of the session:** the linker cache went **107 → 140**, the
exact union, verified against the layers. Before reconciliation the composed
cache was simply the top layer's — roughly **35 of webserver's libraries were
missing from it.** And nothing broke, because they sit in the linker's default
search paths.

Which is precisely why it matters: **the smoke test could never have caught it.**
`nginx -t` passes either way. A defect invisible to functional testing,
detectable only by direct comparison against the inputs.

**§4 now reads 11 → 1.** Of the eleven originally-differing files, only
`status-old` remains, and that is a one-line exclusion.

---

## The theme that recurs

**Four times, a check that could not run degraded to silence instead of
failure:**

1. `05_check.sh` printed ACCEPT when `dpkg` was missing — every version
   comparison silently returned "no conflict"
2. `05_check.sh` exited 0 on REJECT — a broken run and a real conflict were
   indistinguishable
3. `07_smoke_test.sh` reported "functional" having executed **zero** probes
4. `ACCEPT WITH WARNINGS` hardcoded "base drift detected", which went stale the
   moment a second warning type existed

Plus one bug of the same family: a variable named `GROUPS` — which **bash owns**,
holding the caller's group IDs. The assignment was silently discarded and
`"$GROUPS"` expanded to `1000`. `set -u` cannot catch it, because the variable
is always set.

**Validation tooling fails silently by default.** Every silent-success path has
to be converted into a hard failure, and the positive control is the systematic
answer.

**The second theme:** each fix revealed the next problem. Nothing below cause 1
was visible until cause 1 was fixed. That masking structure is the finding, not
just the final configuration.

---

## Where it stands

| Class | Status |
|---|---|
| 1 Benign overlap | detected, measured |
| 2 Version skew | 0 across 378 pairs |
| 3 Declared conflict | detected, incl. virtual packages |
| 4 File collision | detected, 4 suppressed instances |
| 5 State divergence | **reconciled — all four registries** |
| 6 Implicit base upgrade | prevented, 0 across 28 modules |

**Verified:** 5.35× storage reduction (measured, six-point calibration) ·
byte-reproducible artefacts, four causes diagnosed · dpkg state defect
demonstrated and fixed, 41 → 0 · taxonomy swept over 3 654 combinations ·
self-validating harness · cross-machine reproduction.

**Honest gaps:**
- Tier 2 has **four** compositions against tier 1's 3 654
- **Nothing tested above N = 3**, while the design promises arbitrary N
- **Nothing has booted** in this architecture
- Runtime conflicts (`webserver` + `apache`, both wanting port 80) are detected
  by nothing — and that is the sharpest experiment still available

---

## Phase 13 — Tier 2 at scale, one real boot, and an audit that found the class we could not see

Three of those four gaps closed, and the fourth turned out to be the smallest
of the problems.

**Tier 2 at scale.** 96 compositions from N=2 to N=27, then all 351 pairs
exhaustively. Everything passed structurally. The cost model in the
methodology was wrong by 64×: tier 2 costs 155 ms, not the assumed 10 s, so
the asymmetry the three-tier argument rests on is *not* between tiers 1 and 2
— it is between tier 2 and tier 3.

**One real boot.** `base + webserver + apache` packed into a UEFI image and
booted under QEMU. nginx started, Apache failed, `multi-user.target` was
reached, the guest powered off cleanly. Getting there cost three fixes, and
all three were the same finding: `SQUASH_EXCLUDES` removes *directories*, not
just their contents, so a composed tree has no `/proc`, `/sys`, `/dev`,
`/run`, `/tmp`, no apt scratch space, and a dangling `/etc/resolv.conf`
symlink. **A module artefact is not a bootable image and was never meant to
be.** It carries content; mountpoints, kernel and bootloader belong to the
image builder. Tiers 1 and 2 could not have found that, because
`mount_chroot_fs` happens to `mkdir -p` exactly the four directories they
needed.

**Then the audit.** An external read-only assessment found what the project's
own checks could not:

- **Class 7, identity collision.** Four modules — `mta-msmtp`, `redis`,
  `tcpdump`, `memcached` — independently allocate **uid 103 / gid 104** to
  four different names. `/etc/passwd` is not package-owned, so class 4 never
  looked at it, and OverlayFS takes the top layer's copy entire. `User=redis`
  resolves nowhere in a memcached-highest composition, while Redis's files at
  `103:104` read as `memcache`. Both tiers had been accepting that pair.
  Six of 351 pairs are affected. It is not repairable by union: the numbers
  disagree, and files are owned by numbers.
- **Admission was never enforced.** Tier 2 composed the tier-1-rejected MTA
  pair and printed `PASS`. Run A bypassed admission entirely and died inside
  APT — it is *not* a failed boot, it is a failed pre-boot transaction on a
  set that should never have been assembled.
- **`--name` fed an unvalidated string to a root `rm -rf`.** `../../modules`
  would have deleted the artefact store.
- **The newest work was untracked**, and the 96-row tier-2 CSV had already
  been overwritten by the exhaustive run.

The pattern from Phase 12 held again, one level up: the checks were sound
about the things they modelled, and silent about the thing they did not model
at all. Identity was never in the model.

**What this cycle changed:** identifier validation everywhere a name reaches a
path or a deletion; class 7 detection (reject only — repair is Future Work);
integrity → admission → compose → verify enforced, with an explicit
`--known-negative` mode that never says "verified"; timestamped immutable run
bundles with `run.json`, `result.json` and `source.txt`; and a causal boot
matrix that records `journalctl` and `ss` per expected unit, so the port-80
story stops being an inference.

**Still honest gaps:** the four-run causal matrix has not been executed; H1–H12
and M1–M7 from the audit are listed in ARCHITECTURE §10 and untouched; and
"tier 3 passes" remains a claim nobody has earned — one set booted, once.
