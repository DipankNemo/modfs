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

---

## Phase 14 — Class 7 was a claim about numbers, not about composition

**16 September.** An external reassessment said the class-7 work proved less than
it claimed. Checking it independently confirmed the charge: UID *range
partitioning* guaranteed two modules never allocate the same number, and the
manifest comparison checked that. Neither looked at the account **databases**.
`/etc/passwd`, `group`, `shadow` and `gshadow` are rewritten whole by maintainer
scripts, are owned by no package, and OverlayFS takes the top layer's copy
*entire*. Two modules that each created users produced a composed system holding
only one module's records.

"Class 7 prevented" was true of the numbers and false of the records.

**What it forced:** account databases became the fifth reconciled registry —
union by record, member lists merged, modes preserved because `/etc/shadow` is
0640 root:shadow. Tier 2 gained **V6**, asserting the composed databases are the
exact semantic union of the layers, compared record by record rather than line
by line. Proven at runtime on 17 September: `base postgres mysql` and `base
mysql postgres` both boot with `mariadbd` on 3306 and `postgres` on 5432, each
under its own reconciled identity, in both orders.

---

## Phase 15 — The instrument was the thing under test

Five defects in three days where **the harness, not the system, set the limit**.
Each was invisible while N stayed small or the probes stayed weak.

- `require_no_mounts` parsed **field 2** of `/proc/self/mountinfo` instead of
  field 5. The guard was completely inert.
- Signal handlers `return`ed instead of re-raising, so scripts **continued after
  Ctrl-C and exited 0**.
- **The observer was the job.** The boot harness waited for a steady state its
  own queued job prevented: `systemctl is-system-running --wait` could never
  succeed at any timeout. 180 s wasted per run. Compounded by `grep -c . || echo
  0` yielding the two-line string `0\n0`, so the drain loop could not break *even
  on an empty queue* — one symptom, two sufficient causes.
- **A 4096-byte ceiling.** OverlayFS packs every lower layer into one mount
  option string. A 37-layer set succeeded or failed *depending on how long its
  scratch directory name was*. Relative lowerdirs took it from 4319 bytes to 419.
- `07_smoke_test.sh` **never created `/tmp`**. Nine probes "failed"; all nine
  were the harness. Invisible for the life of the project because no probe had
  ever written a file.

**What it forced:** the recognition that a stronger probe does not only test the
module better — it tests the harness. Nine harness defects surfaced the moment
the probes started doing real work.

---

## Phase 16 — Class 9, and a design assumption that was true and wrong

**16 September.** A 36-module boot lost the whole of `pytools`' numpy tree.
`dpkg` correctly reported `python3-numpy` installed; the files were absent. **No
file collided** — the modules ship different filenames — so class 4 could never
see it.

Cause: `pyyaml` carried `trusted.overlay.opaque` on `/usr/lib/python3`, which
tells OverlayFS to ignore every lower layer at that path. Measured across 38
modules: **869 markers, 456 distinct directories, 178 claimed by two or more**.

`config.sh` had classified that xattr as *"SEMANTIC. A directory replaced
wholesale. Keep."* The reasoning was sound; its **premise** was false and nobody
had measured it. Of the 456 directories, **zero exist in base**, zero modules
carry a whiteout, and every parent is base — so no marker was ever hiding
anything. Each was written when the only layer below was base; at compose time
"below" becomes the *sibling modules*, which did not exist when the marker was
made.

**What it forced:** `opaque` joined `uuid` and `origin` in
`SQUASH_XATTR_EXCLUDE`; `02_build_delta.sh` now *asserts* the premise on every
build rather than trusting a comment; and tier 2 gained **V7**, requiring every
name present in any layer to be visible in the merge — the first check in the
project that looks at the composed filesystem rather than its metadata.

---

## Phase 17 — Three adversarial passes, and the checkers lost

**17–18 September.** Three independent sessions were told to attack the
checkers, each without being shown what the previous one found.

- **Round 1** reproduced **seven false negatives**, six of which V7 passed.
- **Round 2**, attacking the fixes for round 1, found **thirteen more** — including
  that V7 v2 was defeated by a relative symlink to a decoy carrying the same
  entry name (1 MB of payload replaced by 6 bytes, `vis_ok=1`), and that V7
  resolved absolute symlinks against the **checking host's** filesystem, so its
  verdict depended on the machine running it.
- **Round 3**, a different model entirely, found **twelve more**, including that
  the new manifest-binding seal was *optional*: `binding.sidecar_sha256` lives
  inside `binding`, which cannot be inside its own digest, so deleting one field
  disabled the check while the manifest seal still verified.

Two findings needed no fixtures at all. `postgres` + `java`: postgres' debconf
database silently replaced by java's, all checkers green. `curl` +
`control-oldsnap`: tier 1 rejects it for five version skews and **tier 2 passed
every column**, because V2 compared package *name sets*.

**What it forced:** V2 compares `(name, version)`; a bare `Replaces:` no longer
excuses a file collision (Policy §7.6 requires `Breaks` or `Conflicts` for
side-by-side installs); alternatives priority disagreement is a conflict rather
than a last-wins merge; class 7 compares the **numeric owners of shipped files**,
not only declared records; debconf became the sixth reconciled registry with its
own **V8**; and the seal became mandatory. Every finding is now a regression
test.

**And one line worth keeping:** *V7 is a check that the right names are present,
and it was being read as a check that the right files are present.*

---

## Phase 18 — Rebuilding everything, and the storage claim narrowing again

The catalogue was rebuilt from scratch: base plus 38 modules in 19 minutes.
`/etc/apt/apt.conf.d/99modfs` — which disabled apt recommends on any provisioned
node — was found in base and unevenly through modules, and is now gone from all
of them. `pipdemo` built for the first time since 10 September, having failed on
an `IFS=$'\t'` empty-field collapse that put its `post_install` into the snapshot
variable.

**Storage was not comparable and nobody had noticed:** `08 --force` does *not*
rebuild the monolithic baselines, so fresh deltas were being measured against
monoliths built on the leaked base. Rebuilt like-for-like, the model was then
*checked* rather than assumed — measured monolithic sizes run 0.2–0.9 % **below**
the modelled `B + d`, so the model mildly overstates the saving.

**Base fattening**, named in §7 as "the obvious next experiment and has not been
run", was run. Server-side it is an unconditional **−24.1 %**. Per node it is
not: **no single-module node can ever win, structurally**, because the shared set
is chosen by "appears in ≥2 modules", so `dB` always exceeds any one module's
saving. Server-side and per-node metrics give **opposite answers for the same
build**.

---

## Phase 19 — What "updatable" actually costs

**19–20 September.** The title claims a *modular, updatable* filesystem; §11
scheduled an update manager for week 3 and it was never built. The word
"updatable" appeared once in the whole document — in the title.

Within a pin nothing can change: same pin plus same spec gives the same bytes,
re-verified on `curl`, `jq` and `zstd`. So an update *means* a new spec or a new
pin. The design decision taken was that **the pin is atomic across the
catalogue** — one snapshot, one generation, mixed pins never valid.

- **Intra-generation** (a module's packages change): `jq` gains `moreutils`, only
  the new `jq` ships — 10.43 MB of 51.65 MB, a **4.95× saving**.
- **Inter-generation** (the pin moves): **all 40 modules rehash. 100 % reships.**
  No free modules. The hoped-for incremental result did not hold, and was
  reported rather than engineered around — no timestamp normalisation, no
  binary patching, no chunk deduplication.

Three mechanisms explain it, and two are incidental rather than fundamental:
`SOURCE_EPOCH` is derived from the snapshot id and stamps every file's mtime;
every delta ships the new snapshot URL in `sources.list`; and each delta carries
a dpkg status containing base's package versions, of which 36 of 113 changed.

---

## Phase 20 — A second machine, and what the pin actually guarantees

**20 September.** The whole catalogue was rebuilt on rented hardware. Result:
**0 of 41 artefacts byte-identical** — and a mechanism identified for every
single mismatch.

The finding is not the zero. It is what sits underneath it: **40 of 41 modules
have identical package maps across machines and dates**, the one exception being
the module we ourselves respecced. **The pin does exactly what it claims.** What
differs is state generated at *install* time — shadow password-change days,
nullmailer embedding the hostname, MySQL's Aria UUID encoding the build date and
the NIC MAC, PostgreSQL's cluster ids and snakeoil certificates, Java's JKS
timestamps, Emacs info-dir ordering from an unsorted `find`.

Java is the sharpest case: its CDS dump differs between **two runs on the same
machine**, so that artefact cannot be byte-reproducible by anyone.

**What it forced:** §8's claim narrows from "byte-reproducible artefacts" to
**deterministic package resolution, with byte-identity holding only for modules
whose packages generate no install-time state**. That is a property of the
package set, not of the build system — which is why `curl`, `jq` and `zstd`
reproduced perfectly and the daemons did not.

The same run found `00_verify.sh` checks that a tool *exists* but not that it is
*capable*: SquashFS 4.5 lacks `-xattrs-exclude`, and the checker hid the decisive
`mksquashfs` error.

---

## Phase 21 — GPU modules, and the limit of the claim

A 680 MB CUDA runtime and a 232 MB driver module were built from the pinned
snapshot. The method carries them: byte-exact, V1–V8 clean to N=38, boots, and at
matched N composes **no more expensively than a 0.5 MB module** — cost tracks
layer count, not size. What it does *not* do is save anything at that size: 99 %
return on `nc-traditional` against **5.8 %** on the CUDA runtime.

The brief given to that session was wrong in three ways it caught: Ubuntu ships
prebuilt nvidia *objects* plus a link script rather than a prebuilt `.ko`, so
`binutils` is required; Canonical's unsigned build leaves **zero-byte `.ko`**
files where `depmod` scans, which a `test -e` probe would have passed; and the
sizes quoted were roughly half the truth.

**The honest limit:** the driver targets kernel ABI `5.15.0-185`, and no machine
available ran it — the workstation is on 7.0, the rented instance was on 6.8. So
the module is shown to be well-formed for the system ModFS builds, and *not*
shown to bind real hardware.

---

## Phase 22 — Making the evidence regenerable, and finding the prior art

**21 September.** Every thesis number now comes from `16_build_evidence.sh`
reading retained CSVs and run bundles, so the tables update when the artefacts
do. It refuses rather than reports stale: a source older than the artefacts it
describes is replaced by a block naming both timestamps.

An audit of 132 quantitative claims across the documents returned **58 TRACED, 41
UNTRACEABLE, 13 STALE** — most of the untraceable ones died in the 16 September
rebuild. A consistency pass found 24 disagreements, and explained *why* they
persist: the documentation contract test holds seven assertions and **all seven
read `ARCHITECTURE.md`**. Everything a test covers is closed; everything it does
not is live. The same defect shape as V7, V2 and `00_verify` — *the check only
looks where it was pointed.*

And the literature was finally read against the claims. **`pendry1995union`
(1995) already contains the opaque attribute and its `rm -rf`/`mkdir`
rationale.** Class 9's mechanism is thirty-one-year-old prior art; what remains
novel is the **build-time versus compose-time marker mismatch** and the
measurement. `treinen2008solving` already gives class 4's detection method.
`vouillon2013coinstallability` formalises classes 2 and 3 — but has no
file-level model, so class 4 genuinely sits outside it.

---

## The theme, restated after six more weeks

Phase 12 said it once: the checks were sound about the things they modelled and
silent about the things they did not model at all. Everything since has been the
same sentence with a different subject.

- Class 7 modelled **numbers**, not records.
- Class 4 modelled **paths**, so it could not see a directory erasing a sibling.
- V2 modelled **names**, not versions.
- V7 modelled **names**, not files.
- `00_verify` modelled **presence**, not capability.
- The documentation test modelled **one file**, not five.

Twenty-plus defects across three adversarial passes, and not one of them was a
composition failing. Every one was a *check* that passed something it did not
model. The strongest claim this project can make is not that delta composition
works — it is that **verifying it is harder than performing it**, and that each
strengthening of a check found something the weaker version had been passing.
