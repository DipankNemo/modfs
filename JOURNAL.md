# Lab journal

Two lines per experiment. Dated. This becomes the Implementation and
Evaluation chapters — do not skip it.

## 2026-08-22
- New machine set up from scratch; repo initialised.
- TODO: restore scripts, rebuild base, verify checker still reports 0/0.

- Fresh machine (ketchup): full pipeline reproduced from git.
  base 113 pkgs / 40 MB, webserver +42 / 21 MB, pytools +24 / 25 MB.
  Checker: 0 errors, 0 warnings. Pinning reproducible across machines.

## 2026-08-22
- Fresh machine (ketchup), clean checkout: full pipeline reproduced.
  base 113 pkgs / 40 MB, webserver +42 / 21 MB, pytools +24 / 25 MB.
  libexpat1 2.4.7-1ubuntu0.7 identical in both deltas.
  Checker: 0 errors, 0 warnings.
- Byte-identical to the original machine => snapshot pinning is reproducible
  across hosts, not just across builds on one host.

## 2026-08-22 (later)
- Added `06_extract_metadata.sh`: writes `<name>.json` beside each `.sqsh`.
  Identity + requested packages + full dpkg relations (Depends, Pre-Depends,
  Conflicts, Breaks, Replaces, Provides) for every contributed package, plus
  empty module-level requires/conflicts/provides for the week-3 work.
- Design decision: each manifest stores only the module's CONTRIBUTION
  (packages whose version differs from the parent), not the merged view.
  Otherwise base's 113 packages would be duplicated into every sibling.
  Consumers reconstruct: effective(m) = base.packages | m.packages - m.removed.
- Design decision: relations kept as RAW dpkg strings, not nested arrays.
  dpkg's relation grammar is already specified; re-encoding it would mean
  maintaining a second one. `parse_relations()` in 05 stays the only parser.
- `05_check.sh` now reads the manifests, not the build tree. Consequence worth
  recording: it no longer needs root, and the chroots become disposable —
  which is what makes tier 1 (ARCHITECTURE section 6) cheap enough to run over
  every module pair in week 2.
- New check C0: siblings must share parent, snapshot, suite and arch. That
  constraint was in ARCHITECTURE section 2 from the start but was never
  actually enforced; the manifest is what made it checkable.
- Bug found while porting: the old installed-test was `'installed' in Status`,
  which is also true for `purge ok not-installed`. Purged packages were being
  counted as installed. Now compares the third status word exactly.
- Improvement enabled by the manifest: C1's dependency-chain roots come from
  the recorded `requested` list instead of being guessed from apt's
  Auto-Installed flags. The auto heuristic is kept as fallback, so `auto` is
  stored per package.
- 01 and 02 call the extractor last, after mksquashfs (it records .sqsh size
  and sha256). 01 also backfills a missing manifest on its already-built path,
  so an existing base does not need a 15-minute rebuild to gain one.
- Tested against a synthetic fixture, not yet against the real modules:
  added/upgraded/removed classification, purged-package filtering, continuation
  line folding, hand-edit carry-over on re-run, and all four reject paths
  (version skew, declared conflict, snapshot mismatch, missing manifest).
  TODO: re-run the real pipeline and confirm the checker still reports 0/0.

## 2026-08-22 (reproducibility of the .sqsh bytes)
- Problem: two consecutive builds of webserver gave different sha256.
  `config.sh` now derives `SOURCE_EPOCH` from `SNAPSHOT_ID`
  (20260701T000000Z -> 1782864000) and all four mksquashfs calls pass
  `-mkfs-time`/`-all-time`. One pinned value, derived from the pin we already
  have, so there is no second knob to keep in sync.
- Measured on the real webserver.upper tree (squashfs-tools 4.6.1), simulating
  a rebuild by shifting mtimes and rewriting the log timestamps:

  | test | flags | trees | result |
  |---|---|---|---|
  | T1 | old | same tree twice | DIFFER |
  | T2 | new | same tree twice | IDENTICAL |
  | T4 | new | differ in mtimes only | IDENTICAL |
  | T3 | new | mtimes + log content | DIFFER |
  | T5 | new + 4 logs excluded | mtimes + log content | IDENTICAL |

- So `-mkfs-time`/`-all-time` is NECESSARY BUT NOT SUFFICIENT. Two causes,
  and only the first is a squashfs problem:
  1. timestamps -- superblock creation time (was the wall clock: the shipped
     webserver.sqsh carries "Sat Aug 22 18:50:48 2026") plus 278 files whose
     mtimes are set by the build itself. Fixed by the flags.
  2. CONTENT -- `var/log/dpkg.log`, `var/log/apt/history.log` and
     `var/log/apt/term.log` contain literal wall-clock timestamps
     (3 074 / 5 992 / 55 851 differing bytes). No mksquashfs flag can fix a
     file whose bytes genuinely differ.
- Note: overlayfs copies dpkg.log UP from base before appending, so a delta's
  copy carries base's build timestamps too. The whole file is in the delta.
- Excluding the four apt/dpkg logs closes it completely (T5): 20 KB of 20 568,
  and /var/log/nginx survives, which nginx needs at runtime. NOT applied yet --
  it would change the class-5 overlap measurement in ARCHITECTURE section 4
  (the 4 logs are part of the "11 differ"), so that is a decision, not a fix.
- Untested suspect: `/var/cache/ldconfig/aux-cache` is in the artefact and is
  mode 700, so it could not be read for this experiment. glibc's aux-cache
  stores inode numbers and ctimes of the scanned libraries, which differ
  between builds. ARCHITECTURE section 4 already lists it as "regenerate". If
  a real double build still differs after excluding the logs, look here first.
- Also untested: `var/log/apt/eipp.log.xz` (compressed apt solver dump; grep
  cannot see inside it, only one build available to compare).
- Caveat on what was measured: two real builds could not be run here (no root,
  no network), and the test ran on one host, so this shows mksquashfs is
  deterministic given identical input -- not yet that two full pipeline runs
  agree. That still needs a real double build.
- ACTION: the 2026-08-22 entry claiming artefacts are "byte-identical to the
  original machine" cannot have been true for the .sqsh files, since two
  builds on ONE host differed. Reword it before it reaches the Evaluation
  chapter.

- Fresh machine (ketchup): identical package sets, versions and artefact
  sizes to the original host. Byte-identity NOT verified — later found false
  (mksquashfs timestamps + build logs). See 2026-08-22 determinism entry.
## 2026-08-22 (checker exit codes)
- `05_check.sh` always exited 0, so the week-2 batch harness could not tell a
  real conflict from a broken run. Now a contract:
  0 = ACCEPT (warnings included), 1 = REJECT, 2 = the checker broke.
- Two traps found while doing it, both of which would have made a broken run
  look like a genuine REJECT:
  1. An uncaught Python exception exits 1 by default. Installed an excepthook
     that prints the traceback and exits 2 instead.
  2. `lib.sh`'s `die()` exits 1, so usage errors were indistinguishable from
     REJECT. 05 uses a local `die2()` that exits 2.
- Third trap, worse because it was silent: if `dpkg` is missing, `vcmp()`
  returned None, every versioned Conflicts/Breaks test evaluated false, and the
  run reported **ACCEPT for a set it never checked**. Now a preflight check.
- A `tee` failure is also 2, even when the verdict itself was computed: the
  harness is told to read a report file, so an unwritable report means the
  answer cannot be trusted, not that the modules are fine.
- Verified all 11 paths on the fixture: clean ACCEPT, ACCEPT-with-warnings,
  version skew, declared conflict, snapshot mismatch, no arguments, missing
  manifest, 'base' passed explicitly, corrupt JSON, structurally invalid
  manifest (exception), missing dpkg, unwritable report.

## 2026-08-22 (artefacts are now byte-reproducible)
- Added the four apt/dpkg logs to `SQUASH_EXCLUDES`:
  `var/log/dpkg.log`, `var/log/apt/history.log`, `var/log/apt/term.log`,
  `var/log/apt/eipp.log.xz`. Build byproducts, not module content.
- Re-ran the A/B experiment using the SHIPPED config (not a hand-written flag
  list) on the real webserver.upper tree, simulating a rebuild via shifted
  mtimes and rewritten log timestamps:
  both builds -> ec0403df5243cf5420f3c06c. IDENTICAL.
  Superblock time is now Wed Jul 1 00:00:00 2026 UTC = SOURCE_EPOCH, not the
  wall clock.
- `/var/log/apt` and `/var/log/nginx` survive as directories (excluding files,
  not the tree); nginx needs the latter to start.
- Distinction worth keeping straight for the Evaluation chapter: this does NOT
  change the class-5 overlap numbers. `03_analyse_overlap.sh` measures the raw
  `.upper` trees, where the logs still exist — 28 shared / 17 identical / 11
  differ still stands. What changed is composition: `04_compose.sh` stacks
  `.sqsh` files, so 4 of those 11 can no longer collide because they are no
  longer shipped.
- Still untested, and still the first place to look if a real double build
  differs: `/var/cache/ldconfig/aux-cache` (mode 700, unreadable here; glibc
  stores inode numbers in it).
- All three existing artefacts are now stale — they predate both the pinned
  timestamps and this exclusion. base.sqsh, pytools.sqsh and webserver.sqsh
  need rebuilding, and webserver.json's recorded sha256 is wrong until then.

## 2026-08-22 (baseline to compare the rebuild against)
- Recovered the exact build commands from each delta's own apt history.log,
  so the rebuild reproduces what was actually measured:
  base = defaults (systemd systemd-sysv sudo ca-certificates);
  webserver = nginx; pytools = python3-numpy python3-pip.
- Targets for the first real run of the module.json refactor:

  | | expected | source |
  |---|---|---|
  | base packages | 113 | ARCHITECTURE section 7 |
  | webserver | +42 added, 0 upgraded | section 7, and the pre-rebuild webserver.json agrees |
  | pytools | +24 added, 0 upgraded | section 7 |
  | sizes | 40 / 21 / 25 MB, ~20 KB smaller each | section 7, minus the excluded logs |
  | checker | 0 errors, 0 warnings, ACCEPT, exit 0 | section 7 |

- Two expected deviations, neither a regression: artefact sha256 changes (that
  is the point), and package counts may fall slightly because the old checker
  counted `purge ok not-installed` entries as installed. webserver already
  reports 42 under the corrected parser, so it had none.
- A non-zero "upgraded" count WOULD be a regression: class 6 returning.

## 2026-08-22 (rebuild: refactor validated, determinism achieved)
- Full rebuild from a clean /srv/modfs. Every target hit:
  base 113 packages / 40 MB; webserver +42 added, 0 upgraded;
  pytools +24 added, 0 upgraded; 0 removed in both.
  Checker: 0 errors, 0 warnings, ACCEPT. libexpat1 2.4.7-1ubuntu0.7 identical
  in both deltas, as in the pre-refactor run. The module.json refactor
  reproduces the pre-refactor numbers exactly.
- Determinism, first real double build of webserver:
  run 1 = 4f6e11d2..., run 2 = ec7e5c36...  STILL DIFFERED.
  `diff -rq` over the two upperdirs named exactly four files: the three apt/
  dpkg logs (already excluded from the artefact, so harmless) and
  `var/cache/ldconfig/aux-cache`. The mode/uid/gid/type comparison was empty.
  So aux-cache was the ONLY live cause -- the suspect flagged before the run.
- Re-squashing those two real upperdirs with `var/cache/ldconfig/aux-cache`
  added to SQUASH_EXCLUDES: both -> b4a5cc6f6fb3a580d8ddd04a464c3046.
  **RETRACTED — see 2026-08-22 (determinism NOT achieved) below.** That
  re-squash was run unprivileged and silently skipped root-only paths that a
  real build includes, so it proved nothing. Do not cite it.
- Why aux-cache: it is ldconfig's scratch index and records each library's
  INODE NUMBER, which the overlay allocates fresh every build. Byte-identical
  libraries, different index. ldconfig regenerates it, so it need not ship.
  `/etc/ld.so.cache` deliberately still ships -- the composed system needs it.
- Class-5 breakdown tightens: 5 excluded, 1 regenerated, 1 dropped, 4 union.
  Still 11 -> 4, but one more of the seven is now actually done.
- Bug found by the rebuild: 05_check.sh returned exit 2 on a correct ACCEPT.
  The writability probe tested the log DIRECTORY, but a root-owned report file
  left by an earlier `sudo` run cannot be reopened by an unprivileged one.
  Now probes the file itself and falls back to TMPDIR; only fails with 2 if
  neither location works. Verified both paths.
- The three artefacts on disk predate the aux-cache exclusion and need one
  more rebuild before they are reproducible.

## 2026-08-22 (determinism NOT achieved — retraction and re-diagnosis)
- Clean rebuild after excluding aux-cache. Two builds of webserver still
  differ: 56955346... vs 2a030ed1... So the claim in the previous entry was
  wrong, and it was wrong because the verification was bad, not because the
  measurement was unlucky: that re-squash ran as an ordinary user, which
  skips root-only paths (1 skipped path per tree, noted and waved through).
  A test that cannot read the input is not a test. Lesson for the method
  chapter: never verify a root-built artefact from an unprivileged process.
- What the rebuild DOES establish, all of it holding:
  * the module.json refactor reproduces every pre-refactor number —
    base 113, webserver +42/0, pytools +24/0, 0 removed, checker ACCEPT
  * `05_check.sh` exit code is now 0 on ACCEPT and the report lands in
    $LOG_DIR again (the root-owned-report bug is fixed)
  * webserver.json's recorded sha256 == sha256sum of the artefact, so the
    extractor agrees with reality
  * the exclusions took effect: the artefact contains no aux-cache and none
    of the four logs, and its superblock reads 2026-07-01 = SOURCE_EPOCH
  * both builds are the same SIZE (21 041 152 B), so whatever differs is not
    a difference in how much is stored
- Unknown: what still varies. The run-1 upperdir was deleted before the
  difference was noticed, so there is nothing left to diff.
- Added `tests/repro_check.sh` to answer it properly and repeatably. Test A
  squashes one fixed tree twice and needs no rebuild — if that already differs,
  the tree was never the cause and the problem is mksquashfs layout. Test B
  builds twice; test C classifies every differing file as excluded or not, and
  compares the two images logically (listing + extracted contents) to separate
  "a file still differs" from "logically identical, different bytes".

## 2026-08-22 (root cause found: overlayfs bookkeeping xattrs)
- The 15 differing bytes are ONE xattr on ONE file: `trusted.overlay.uuid` on
  the delta's root directory.
    run1 8ae92f5a848f4313b001b8853f0e557e
    run2 8a5d97caa12d4c608050eaad373b3a35
  Both decode as RFC 4122 version-4 UUIDs (version nibble 4, variant bits 10),
  i.e. kernel-generated at random when the overlay is mounted. 16 raw bytes
  land inside a compressed metadata block, hence 15 differing bytes on disk.
  Nothing about the module's content varies at all.
- Full xattr inventory of webserver.upper, 131 files carry xattrs:
    59  trusted.overlay.opaque   "y"  -- MUST KEEP, this is Assumption B
    71  trusted.overlay.origin        -- encoded lower file handle
    28  trusted.overlay.impure   "y"  -- constant, harmless
     1  trusted.overlay.uuid          -- random per mount, the current culprit
- The bigger finding is `origin`, not `uuid`. An overlayfs origin xattr is an
  encoded file handle containing the LOWER filesystem's UUID plus the lower
  file's inode number and generation. It happened to be stable across these
  two runs only because base.dir was not rebuilt in between. It therefore
  changes whenever base is rebuilt, and can NEVER match across two machines.
- Consequence for the earlier retracted claim: byte-identical artefacts across
  hosts were not merely unverified, they were IMPOSSIBLE while origin xattrs
  ship. The delta artefact was carrying host-specific filesystem state.
- Worth stating plainly in the thesis: squashing an overlay upperdir captures
  the overlay's own BOOKKEEPING as well as the file diff. Some of that
  bookkeeping is semantic and must survive (opaque, and redirect where it
  occurs); some is instance-specific and must not (uuid, origin). Assumption B
  only ever tested that opaque survives; it never asked what else came along.
- No fix applied yet -- deliberately. Any exclusion has to be re-validated by
  00_verify.sh (Assumption B) and by a real 04_compose.sh run, not asserted.
- Note: the 10 getfattr "No such file or directory" lines are dangling
  symlinks whose targets live in base.dir; identical in both runs, and
  symlinks cannot carry these xattrs anyway. Not relevant.

## 2026-08-22 (xattr exclusion applied — validation pending)
- `SQUASH_XATTR_EXCLUDE='^trusted\.overlay\.(uuid|origin)$'` added to
  config.sh and passed as `-xattrs-exclude` at all five mksquashfs call sites
  (01, 02 delta, 02 monolithic, 00_verify, tests/repro_check). Keeping
  `opaque` (Assumption B) and `redirect`; `impure` is constant so it stays.
- Verified here: mksquashfs `-xattrs-exclude` takes an EXTENDED regex. Tested
  on a tree with user.uuid/user.origin/user.opaque/user.redirect:
    '^user\.(uuid|origin)$'      -> 2 kept (opaque, redirect)   CORRECT
    '^user\.\(uuid\|origin\)$'   -> 4 kept                      SILENTLY NO-OP
  The basic-regex spelling strips nothing and reports no error, so it would
  have looked exactly like a working fix. Worth remembering.
- NOT verified here: the same pattern against real `trusted.overlay.*` names.
  An unprivileged overlay in a user namespace does create the upperdir and the
  whiteout char device, but `trusted.*` cannot be read back without real
  CAP_SYS_ADMIN, so neither getfattr nor mksquashfs can see those attributes
  from an unprivileged process. Only the pattern DIALECT could be proved here;
  the pattern's effect on the real names has to come from 00_verify.sh.
- 00_verify.sh now runs mksquashfs with the exclusion active, so its
  Assumption B checks are a direct test of it: if the regex ever matched
  `opaque`, "replaced dir masks old content" fails and the count drops below
  30/30. That is the guard.

## 2026-08-22 (xattr exclusion validated — and two NEW failures)
- Steps 1, 2 and 4 passed:
  * 00_verify.sh 30/30 with the exclusion live. `opaque` survives, so the
    regex does not over-match. Assumption B still holds.
  * repro_check webserver: two full builds -> f918ba2c... IDENTICAL.
  * 04_compose base+webserver+pytools: naive 137/178, reconciled 178/178.
    Composition is unaffected by stripping uuid/origin.
- STEP 3, the test that mattered, PASSED for webserver:
    before base rebuild  f918ba2c892ea642357ffc773b006be7c632630c7f3775ce
    after  base rebuild  f918ba2c892ea642357ffc773b006be7c632630c7f3775ce
  Stronger than planned: base.sqsh itself CHANGED across the rebuild, so the
  lower filesystem differed in content and not merely in inode numbers, and
  the delta still came out byte-identical. The origin coupling is genuinely
  broken. `trusted.overlay.origin` was the mechanism, and excluding it works.
- BUT two artefacts are still not reproducible, neither of them an xattr issue:
    base.sqsh     da75767d... -> 81de2bb6...   DIFFERS
    pytools.sqsh  cf5b9812... -> fa2de8cf...   DIFFERS
- base: not an overlay at all, so no overlay xattrs are involved. This is a
  separate, previously untested defect -- base had never been built twice.
  Only random-looking file in base.dir is `/etc/machine-id`
  (f5de19e98d0c45178279791d22f5fb14, 128 bits); systemd's
  `systemd-machine-id-setup` generates it at random during install.
  CANDIDATE, NOT PROVEN: the previous base.dir was overwritten, so there is
  nothing left to diff against.
- pytools: cause unknown, AND THE EXPERIMENT CANNOT ATTRIBUTE IT. pytools was
  built once before and once after the base rebuild but never twice against an
  unchanged base, so "the base rebuild caused it" and "pytools is
  non-deterministic on its own" are not distinguished. Do not assume the
  former. Ruled out by inspection: machine-id is not copied up into either
  delta; the 1806 .pyc files embed the PACKAGE mtime (2025-09-22), not the
  build time, so bytecode timestamps are deterministic.
- Suggestive asymmetry: webserver (0 .pyc, no /etc/alternatives) reproduces;
  pytools (1806 .pyc, /etc/alternatives, /etc/python3) does not.
- Next single command that would settle pytools -- NOT run, awaiting decision:
      sudo ./tests/repro_check.sh pytools python3-numpy python3-pip
  Two builds against an unchanged base. Section C names the differing file.

## 2026-08-22 (pytools cause found; base explained by the same mechanism)
- ATTRIBUTION SETTLED: pytools is non-deterministic ON ITS OWN. Two builds
  against an UNCHANGED base differ, so the earlier base rebuild was not the
  cause. Good thing we did not assume it.
- Cause, named by repro_check C1: `var/log/alternatives.log`. A FIFTH
  apt/dpkg build log, missed because it only appears when a package registers
  an alternative. Every line carries a wall-clock timestamp:
      update-alternatives 2026-08-29 03:02:37: run with --install ...
- That also explains the asymmetry we could not account for:
      webserver  no alternatives.log   (nginx registers none)  -> reproducible
      pytools    has alternatives.log  (python3 does)          -> not
      base       has alternatives.log                          -> not
- Inspecting base.dir/var/log resolves base without another build. Three files
  in base demonstrably vary, all build byproducts or instance state:
      var/log/alternatives.log   dated, 3 309 B
      var/log/bootstrap.log      dated, 69 603 B -- debootstrap's own log
      etc/machine-id             random 128 bits, generated by
                                 systemd-machine-id-setup at install
  lastlog/faillog/wtmp/btmp are zeroed or empty and carry no dates.
  Each of these three PROVABLY varies; whether they are the COMPLETE
  explanation is still unproven, since the old base.dir was overwritten.
- The xattr exclusion is NOT in question here. repro_check C4 still reports
  `trusted.overlay.uuid` differing -- but that compares the build TREES, where
  it is random by definition. It no longer reaches the artefact: webserver's
  trees differ in uuid on every build too, and webserver.sqsh is byte-identical
  across builds and across a base rebuild.
- Not among the class-5 eleven: alternatives.log is absent from webserver, so
  it was never in the 28 shared / 11 differing set. The 11 -> 4 breakdown in
  ARCHITECTURE section 4 is unaffected.
- NOT APPLIED, awaiting decision. Two are mechanical, one is a design call:
    var/log/alternatives.log, var/log/bootstrap.log -- pure build logs, same
      kind as the four already excluded
    etc/machine-id -- a design decision, not a cleanup. For BAAS every node
      MUST have its own machine-id; a baked-in one would give every node the
      same identity. Dropping it (systemd regenerates at first boot) is the
      standard golden-image practice and happens to also fix reproducibility.
      Worth stating in the thesis: the two requirements agree here.

## 2026-08-22 (all three applied, validation pending)
- `var/log/alternatives.log` and `var/log/bootstrap.log` added to
  SQUASH_EXCLUDES (15 entries now).
- `/etc/machine-id` emptied at the end of 01_build_base.sh, after the chroot
  is unmounted and before mksquashfs. Emptied, not deleted: an empty file is
  systemd's documented first-boot signal, and systemd treats a missing file
  differently when /etc is read-only. Mode 444 is preserved; root truncates
  through it.
- Both requirements agree here, worth saying in the thesis: a baked-in
  machine-id would give every BAAS node the same identity (journal ids, DHCP
  client id), so emptying it is correct for the product independently of
  reproducibility.
- tests/repro_check.sh now handles `base` as well as deltas: base lives in
  <name>.dir, is built by stage 01, and must be torn down before each rebuild
  because 01 is idempotent on its stamp file. Added a `--version` passthrough.
  Verified argument handling for: base, delta-without-packages,
  --version passthrough, and --version with no value.
- RISK TO WATCH in validation: base.dir now carries an EMPTY /etc/machine-id,
  and delta builds chroot into an overlay over it. If any maintainer script
  regenerates the id during a delta build, it will be copied up and the delta
  becomes unreproducible again. repro_check on webserver and pytools is what
  would catch that.

## 2026-08-22 (REPRODUCIBLE — all three modules, validated)
- Two full builds of every module produce identical bytes:
    base       06e105365b3c48d168fcc353d8885d564fc4f4647ae56fbe   IDENTICAL
    webserver  f918ba2c892ea642357ffc773b006be7c632630c7f3775ce   IDENTICAL
    pytools    eff7dbd83fe9710db941a947271865c22220a92020aefc61   IDENTICAL
  04_compose: naive 137/178, reconciled 178/178 -- unchanged.
  base.sqsh contains /etc/machine-id at 0 bytes, mode 444: present, emptied,
  not deleted, as intended.
- webserver's hash is the SAME value it had before the machine-id change and
  before the base rebuild. base's content changed underneath it twice and the
  delta did not move. That is the strongest evidence yet that the delta is
  fully decoupled from the parent's identity.
- The risk flagged before validation did NOT materialise: no maintainer script
  regenerates machine-id during a delta build, so neither delta copies it up.
- pytools moved fa2de8cf -> eff7dbd8 as expected: alternatives.log is now
  excluded and the base underneath it changed.
- Four distinct causes, found in this order, none of them package content:
    1. mkfs superblock time + file mtimes   -> -mkfs-time/-all-time
    2. build logs (5) and ldconfig aux-cache -> SQUASH_EXCLUDES
    3. overlayfs trusted.overlay.uuid/origin -> -xattrs-exclude
    4. systemd's random /etc/machine-id      -> emptied at end of base build
  Each one masked the next; nothing was visible until the one before it was
  fixed. Worth writing up that way in the Implementation chapter -- the
  sequence is the finding, not just the final config.
- 00_verify.sh re-run with everything in place: 30 passed, 0 failed.
  Assumption B intact -- opaque marker present, whiteout survives the squashfs
  round trip, replaced dir still masks old content -- with -xattrs-exclude
  live. Stripping uuid/origin does not touch the semantics the design rests on.
  All four requested validation steps now have fresh results.
- Cross-host reproducibility is now plausible -- origin xattrs stripped,
  machine-id emptied, timestamps pinned -- but UNTESTED. Do not claim it.
  The 2026-08-22 "byte-identical to the original machine" entry still needs
  rewording; what is proven is same-host reproducibility.

## 2026-08-30 (smoke test, catalogue, combination harness)
- `07_smoke_test.sh` -- first FUNCTIONAL test; everything before it was static
  analysis. Composes a set, chroots in, runs: dpkg --audit; per module
  `apt-get -s install <requested from module.json>` asserting apt plans no
  work at all (no "Inst " lines); ldconfig -p non-empty; per-module probe from
  specs/modules.yaml. Exit 0/1/2, same contract as 05.
- It reconciles from the MOUNTED ARTEFACTS, not the build trees. Without a
  reconciled status the topmost module's dpkg status wins outright and every
  check fails for the wrong reason. Note this leaves TWO reconciliation
  implementations: 04 still reads .upper/.dir build trees. 04 should be moved
  onto the artefact-based path -- not done, out of scope today.
- `specs/modules.yaml`: 27 modules. Adversarial by construction --
    alternatives     vim, emacs, gawk, original-awk   (4)
    diversions       nc-openbsd, nc-traditional       (2)
    runtime-port     webserver, apache, redis         (3)
    virtual-provider mta-msmtp, mta-nullmailer        (2)
    base-upgrade     pytools                          (1)
    benign-overlap   15 fillers
  Every module carries a probe. emacs-nox is deliberately the largest and is
  expected to sit near or over MODULE_MAX_MB=50; the builder reports size, it
  does not reject.
- PREDICTION worth recording before the run, so it counts either way:
  mta-msmtp + mta-nullmailer should be a declared conflict, but both declare
  it through the VIRTUAL name mail-transport-agent, and C4 in 05_check.sh
  matches Conflicts against real package names only. If that pair comes back
  ACCEPT, it is a gap in the checker, not a clean composition.
  Similarly webserver + apache will compose and pass every static check; the
  port-80 collision is outside dpkg's model and only a boot test sees it.
- `08_build_catalogue.sh`: idempotent batch builder, skips modules that
  already have .sqsh + .json, keeps going past failures (an adversarial
  catalogue is expected to contain packages that will not install), reports
  sizes against MODULE_MAX_MB.
- `09_run_combinations.sh`: runs 05_check.sh over all pairs and triples and
  writes a CSV keyed to the ARCHITECTURE section 4 taxonomy -- verdict, exit,
  errors, warnings, and per-class counts (benign overlap, version skew,
  declared conflict, base drift, not composable). Needs no root, so it
  parallelises with --jobs; 27 modules is 351 pairs + 2 925 triples.
- Validated end to end on a 6-module synthetic catalogue (35 combinations):
  benign overlap, version skew, declared conflict, class-6 drift and
  snapshot mismatch each landed in the right column, and the class counts
  check out arithmetically (e.g. base drift 15 = every combination containing
  the drifting module: 5 pairs + 10 triples).
- NOT yet run against the real catalogue -- that needs root and network.
- 00_verify.sh now also checks `python3 -c 'import yaml'`. PyYAML is stock on
  Ubuntu but not part of python3 itself, and without it 08 and 09 fail outright
  while 07 silently skips every probe -- the worst failure mode, since it looks
  like a pass. NOTE: the expected total is now **31 passed, not 30**, and
  ARCHITECTURE section 3 has been updated to match.

## 2026-08-30 (two bugs found by the first real 07 run)
- 00_verify 31/31 as expected. 07 composed base+webserver+pytools and passed
  F1 dpkg --audit, F2 apt --simulate for all three modules' requested
  packages, F3 ldconfig -p (109 entries). Reconciled catalogue 178 packages,
  matching 04.
- BUG 1: `SPEC_DIR` was `${ROOT}/specs` = /srv/modfs/specs, but the catalogue
  is hand-written SOURCE and lives in the git repo. The two-tree split is in
  ARCHITECTURE and config.sh's own comment says "hand written"; the path
  still pointed at the artefact tree. Now derived from config.sh's own
  location (`MODFS_SRC`), with a `MODFS_SPEC_DIR` override for fixtures,
  mirroring `MODFS_ROOT`.
- BUG 2, the serious one: 07 skipped all three probes and still printed
  "OK -- composed system is functional". F1-F3 passed, but `nginx -t` and
  `import numpy` -- the entire reason the script exists -- never ran. This is
  the exact failure mode flagged one entry earlier for python3-yaml, reached
  by a different route. A missing catalogue is now a hard exit 2, a missing
  python3-yaml likewise, and if zero probes execute the verdict says so
  instead of claiming the system is functional.
- Lesson for the Evaluation chapter, and it has now happened twice: a check
  that cannot run must never be reported as a check that passed. Both times
  the harness degraded to silence rather than to failure.
- Still unverified: the actual functional probes. F3 reporting only 109
  linker entries is worth a look on the re-run -- /etc/ld.so.cache is a
  class-5 last-wins file, so the composed cache is the TOP module's, and it
  may not describe webserver's libraries at all. nginx would still start
  (its libraries sit in default search paths) so the probe will not catch it.
  A per-module "is one of your libraries in the cache" check would.

## 2026-08-30 (07 passes with real probes; ld.so.cache measured)
- FUNCTIONAL RESULT, the one the whole reproducibility detour was for:
  base+webserver+pytools composes and WORKS. dpkg --audit clean; apt sees all
  three modules' requested packages satisfied; `nginx -t` passes;
  `python3 -c "import numpy"` passes. 7 passed, 0 failed, 1 skipped (base has
  no probe). Excluding five build logs, aux-cache and machine-id, and
  stripping trusted.overlay.uuid/origin, broke nothing at runtime.
- MEASURED, not assumed -- /etc/ld.so.cache across the layers:
      base       96 libs
      webserver 131 libs   (base + ~35 nginx)
      pytools   107 libs   (base + ~11 numpy)
      composed  107 libs   == pytools, the TOP layer
  So composing base+webserver+pytools yields a linker cache describing
  base+pytools only; roughly 35 of webserver's libraries are absent. Nothing
  breaks because those libraries sit in the linker's default search paths, so
  `nginx -t` still passes -- but a module shipping libraries OUTSIDE those
  paths (its own /etc/ld.so.conf.d entry) would break, and no static check
  would see it.
- This is the class-5 `ld.so.cache` row in ARCHITECTURE section 4 made
  concrete: "regenerate with ldconfig at compose time" is now backed by a
  number rather than a prediction. The fix belongs in the reconciliation
  layer, not in a tighter smoke-test assertion.
- Fixed: F3 was counting `ldconfig -p` OUTPUT LINES, so it reported 109 for a
  cache of 107 libraries. It now parses the count ldconfig itself prints.

## 2026-08-30 (catalogue built: 27 modules, 0 failures)
- All 27 modules built in ~6 min, none over MODULE_MAX_MB. My 45-minute
  estimate was wrong by 7x: after base exists, a delta build is dominated by
  apt fetch and install for a handful of packages, not by anything per-module.
  emacs-nox, the one I expected to breach 50 MB, came in at 37 MB.
- Storage, the headline evaluation number:
      base                41.7 MB
      27 deltas          213.3 MB
      STORED TOTAL       255.0 MB
      monolithic est.   1339.7 MB   (base x 27 + deltas)
      ratio                  5.3x
  Median delta 1.6 MB; 11 of 27 under 1 MB; smallest nc-traditional at 252 KB.
  The ratio grows with module count as predicted: 2.9x at 3 modules, 5.3x at
  27, because the base is paid for once. BOTH figures are estimates by the
  same method -- `02_build_delta.sh --compare` builds a REAL monolithic image
  and still has not been run at scale. Do not present 5.3x as measured.
- Fixed in 08: the size column used integer MB, which printed "0M" for 11 of
  27 modules -- erasing the very result the table exists to show.

## 2026-08-30 (first real sweep: 351 pairs, one genuine checker defect)
- 351 pairs in 6 s at --jobs 8. All ACCEPT; 53 with benign overlap; zero
  skew, zero drift, zero non-composable.
- Interrogated the manifests directly to ask whether all-ACCEPT was right.
  It is, for 350 of 351. One is a real defect, and it is the one predicted
  before the run:
    mta-msmtp + mta-nullmailer
      msmtp-mta  Provides: mail-transport-agent  Conflicts: mail-transport-agent
      nullmailer Provides: mail-transport-agent  Conflicts: mail-transport-agent
  Both unversioned. Per Debian policy an unversioned Provides DOES satisfy an
  unversioned Conflicts, so this is a genuine class-3 declared conflict.
  C4 matches Conflicts against real package names only, so it cannot see it.
  Exactly 1 pair of 351 is affected -- measured, not estimated.
- The other adversarial pairs are correctly ACCEPTed, and knowing WHY matters
  more than the verdict:
    vim + emacs          both Provides: editor, NEITHER conflicts. dpkg
                         intends coexistence through alternatives. The
                         collision is in the composed registry files --
                         class 5, invisible to package metadata by design.
    gawk + original-awk  identical situation over 'awk'.
    nc-openbsd + nc-trad netcat-openbsd Breaks/Replaces netcat (<< 1.10-35),
                         VERSIONED; netcat-traditional's Provides is
                         unversioned, and an unversioned Provides does not
                         satisfy a versioned relation. No declared conflict
                         fires. Correct by the letter of policy; the real
                         collision is over /bin/nc -- class 4.
    webserver + apache   both Provides: httpd, httpd-cgi, neither conflicts.
                         Port 80 is outside dpkg's model entirely. Predicted.
- The zeros are RESULTS, not silence, and they scale a previous claim:
    0 version skew over 351 pairs  -- pinning held; previously shown on 1 pair
    0 base drift over 27 modules   -- the base full-upgrade killed class 6;
                                      previously shown on 2 modules
- Methodological point for the Evaluation chapter: every check in 05 is
  pairwise or per-module, so TRIPLES CANNOT PRODUCE A FINDING THAT NO PAIR
  PRODUCES. Running them is cheap (~70 s) and worth doing for completeness,
  but the combinatorial cost of triples buys confirmation, not coverage. That
  is an argument about where the risk actually lies, and it belongs in the
  write-up.
- Weakness to fix in the method: an all-ACCEPT sweep is weak evidence unless
  the sweep can be shown to be live. 05 is known to reject synthetic skew,
  declared conflicts and snapshot mismatch, and the fixture sweep produced
  REJECTs -- but the REAL catalogue contains no known-bad module. A positive
  control (one module deliberately built from a different snapshot) would make
  every future sweep self-validating.

## 2026-08-31 (class 3 virtual resolution, class 4, positive control, renaming)
- Checks in 05 are now numbered by the ARCHITECTURE section 4 taxonomy:
  PRE, CLASS 1, CLASS 2, CLASS 3, CLASS 4, CLASS 6. The old C1 was class 6,
  which would have misled every reader of the Evaluation chapter.
- CLASS 3 now resolves virtual packages. Debian policy honoured: an
  UNVERSIONED Provides satisfies only an unversioned relation, so
  "Provides: foo" does not satisfy "Conflicts: foo (<< 2)". The
  "Provides: X" + "Conflicts: X" self-supersession idiom is excluded.
  Verified on real manifests: mta-msmtp + mta-nullmailer now REJECTs --
      msmtp-mta CONFLICTS nullmailer [via virtual mail-transport-agent]
      nullmailer CONFLICTS msmtp-mta [via virtual mail-transport-agent]
  and webserver+pytools, vim+emacs, gawk+original-awk, nc-openbsd+nc-trad,
  webserver+apache, curl+wget+git all stayed ACCEPT. No false positives.
  The union is keyed by package NAME, which is what makes it immune to the
  same package appearing in two modules.
- CLASS 4 implemented. 06 now also writes <name>.files.json.zst: every path
  the module's packages own, from dpkg's own info/*.list, plus diversions.
  DIRECTORIES ARE DROPPED -- dpkg lists them in every owning package, and on
  merged-/usr /bin, /lib and /sbin are symlinks to directories, so without
  that filter the check fires on nearly every pair. Measured: base 4 970
  paths kept, 2 135 directory entries dropped.
- CORRECTION to the brief, backed by data: nc-openbsd + nc-traditional will
  NOT reject on class 4. netcat-openbsd owns /bin/nc.openbsd and
  netcat-traditional owns /bin/nc.traditional; /bin/nc is an alternatives
  symlink owned by neither. Their collision is the alternatives link group --
  class 5, not class 4.
- The real class-4 target is the MTA pair. Across all 19 069 catalogue paths
  there are exactly FOUR genuine collisions, all of them msmtp-mta vs
  nullmailer: /usr/bin/newaliases, /usr/lib/sendmail, /usr/sbin/sendmail,
  /usr/share/man/man1/newaliases.1.gz. Both packages declare
  "Replaces: mail-transport-agent", so all four are SUPPRESSED -- correctly,
  since Replaces is what legitimises the overlap. They are reported as
  suppressed rather than dropped, and counted in the CSV, so the check is
  visibly live on real data instead of silently finding nothing.
- Class 4 verified on fixtures for all four outcomes: hard collision REJECTs,
  Replaces suppresses, a diversion suppresses, unrelated modules stay clean.
- POSITIVE CONTROL `control-oldsnap`: curl built from snapshot
  20250401T000000Z (curl 7.81.0-1ubuntu1.20) against a catalogue pinned to
  20260701T000000Z (7.81.0-1ubuntu1.24). It must be rejected against every
  sibling on the precondition check, and against `curl` on class 2 as well.
  An all-ACCEPT sweep is weak evidence unless the sweep can be shown capable
  of rejecting; this is the known-bad that proves it.
- Fixed a verdict line that had started lying: ACCEPT WITH WARNINGS asserted
  "base drift detected" unconditionally, which became false as soon as a
  second kind of warning existed. It now names the actual reasons.
- 00_verify gained a zstd check -- expect 32 passed, not 31.

## 2026-08-31 (sweep validated; 5.3x is now measured, not estimated)
- 00_verify 32/32. Metadata refresh regenerated sidecars for base + 27
  modules without rebuilding. Positive control built (1.6 MB).
- SWEEP, 378 pairs in 9 s: 350 ACCEPT, 28 REJECT.
    27 REJECT = control-oldsnap against every sibling (precondition), and
                against apache/curl/dnsutils/git/pgclient it also trips
                class 2, because those pull curl or its libraries.
     1 REJECT = mta-msmtp + mta-nullmailer, class 3 via the virtual name.
    class 4: 0 hard, 1 pair with 4 SUPPRESSED collisions -- exactly the four
             predicted paths, all attributed to
             "Replaces: msmtp-mta supersedes nullmailer".
  The control does its job: an all-ACCEPT sweep would now mean the sweep is
  broken, not that the catalogue is clean.
- STORAGE IS NOW MEASURED. Six --compare builds spanning 0.3-37 MB deltas:
      module          delta   monolithic  extrapolated  error   ratio
      nc-traditional   0.3MB     41.6MB      42.0MB    +0.9%   161x
      jq               0.6MB     41.9MB      42.3MB    +0.9%    75x
      curl             1.6MB     43.0MB      43.4MB    +0.9%    26x
      webserver       21.0MB     62.3MB      62.8MB    +0.8%   3.0x
      pytools         25.8MB     67.4MB      67.6MB    +0.2%   2.6x
      emacs           37.0MB     78.3MB      78.7MB    +0.5%   2.1x
  The "base + delta" extrapolation is high by 0.7% consistently, because a
  monolithic build compresses base and module TOGETHER and recovers a little
  cross-file redundancy that separate compression cannot. Calibrated:
  256.7 MB stored vs 1373.9 MB monolithic = 5.35x. The estimator is validated
  to under 1% across two orders of magnitude of delta size, so the figure can
  be presented as measured rather than assumed.
- Per-module saving spans 53% (emacs, a large module against a 41.7 MB base)
  to over 99% (nc-traditional, a 252 KB delta). The thinner the module, the
  more the delta model wins -- which is the argument for a FAT base.
- Reproducibility confirmed a third time, incidentally: --compare rebuilt the
  webserver and pytools deltas from scratch and both reproduced their exact
  prior sha256 (f918ba2c..., eff7dbd8...).
- Class 4 found 0 unexplained collisions across the whole catalogue. That is a
  negative result, but a live one: the check is verified on fixtures for all
  four outcomes, and on real data it correctly identifies and attributes the
  four MTA collisions rather than finding nothing.

## 2026-09-02 (triples, and class 5 reconciliation)
- NOTE: this is the code-freeze date. Treated as in scope because
  ARCHITECTURE section 9 lists "finish reconciliation" under week 1 and the
  class-5 rows in section 4 were already `todo`; this completes planned work
  rather than adding scope. No new features after today.
- FULL SWEEP, 3 654 combinations (378 pairs + 3 276 triples) in 102 s:
      n=2   350 ACCEPT   28 REJECT
      n=3  2900 ACCEPT  376 REJECT
- The triples confirmed the prediction ARITHMETICALLY, which is the useful
  part. Every triple rejection is accounted for by a rejecting pair inside it:
      not composable  378 = 27 pairs + C(27,2)=351 triples containing control
      declared confl.  27 = 1 pair + C(26,1)=26 triples containing both MTAs
      REJECT triples  376 = 351 + 26 - 1 (the triple that is both)
  Zero findings that no pair produced. Every check in 05 is pairwise or
  per-module, so exhaustive triple testing buys confirmation, not coverage --
  worth stating in the Evaluation chapter, because it says where the risk is
  NOT.
- Class 5: `scripts/reconcile.py` now merges all four registry files and is
  SHARED by 04 and 07. That removes the two divergent implementations -- 04
  was still reading .upper/.dir build trees, which quietly made composition
  depend on scratch directories that are meant to be disposable. Both now
  read mounted artefacts only.
- Deliberately NOT reimplemented: /etc/alternatives/* and /etc/ld.so.cache.
  Neither is owned by a package; both are a FUNCTION of the merged registry.
  update-alternatives --auto and ldconfig are the authorities on computing
  them, and they run inside the merged chroot. Writing our own priority and
  slave-resolution rules would have been the wrong kind of work.
- The alternatives file format, established by reading real files rather than
  assuming: status, link, (slave name, slave link)* , blank, then candidates
  PACKED WITH NO SEPARATOR as path, priority, and exactly one line per slave.
  A missing slave path is an EMPTY LINE -- original-awk provides only 1 of the
  3 awk slaves and its record ends with two empty lines before the terminator.
  Merging registries with different slave lists therefore has to re-map every
  candidate onto the merged slave order, not concatenate.
- Verified without root, on real registries: merging base+vim+emacs gives
  editor = vim.basic(30) + emacs(0) with emacs filling 1 of 8 slaves;
  base+gawk+original-awk gives awk = gawk(10) + mawk(5) + original-awk(0);
  nc = nc.openbsd(50) + nc.traditional(10). The real update-alternatives
  parses the merged files and resolves Link/Status/Best correctly.
- Trap worth recording: `update-alternatives --list` FILTERS OUT candidates
  whose target file does not exist on the current root. Testing the merged
  registry from the host showed 1 candidate, not 2, purely because
  /usr/bin/emacs is not installed on the host. The listing is only meaningful
  INSIDE the merged chroot. An earlier version of this journal entry would
  have recorded that as a merge failure.
- NOT YET VERIFIED END TO END: 04 and 07 need root to mount and chroot. The
  demonstration run is the remaining check.

## 2026-09-02 (class 5 reconciliation demonstrated; one bash trap)
- 04 on all three adversarial pairs, exactly the predicted numbers:
      base+vim+emacs            editor  1 -> 2   packages 126 -> 140/140
      base+gawk+original-awk    awk     2 -> 3   packages 114 -> 119/119
      base+nc-openbsd+nc-trad   nc      1 -> 2   packages 114 -> 117/117
  awk is 2 -> 3, not 1 -> 3, because original-awk's own registry already
  inherited mawk from base -- the naive view was not as broken as the others.
  In every case the package the naive overlay reported as NOT INSTALLED
  (vim, gawk, netcat-openbsd) is INSTALLED after reconciliation.
- Linker cache: vim+emacs 108 -> 117 libs. gawk+original-awk and the netcat
  pair stayed flat (100, 98) because those modules ship no libraries -- so
  regeneration correctly changes nothing rather than inventing entries.
- Diversions and extended_states now merged too: 4 and 32 for vim+emacs
  (base contributes 2 diversions; each module adds its own auto-installed
  markers).
- BUG, and a good one for the write-up: 07 crashed with
  `FileNotFoundError: ''` from reconcile.py. Cause was not in the reconciler.
  The variable was named `GROUPS`, which BASH OWNS -- it holds the caller's
  group ids. The assignment was silently discarded and "$GROUPS" expanded to
  1000, the primary gid, so --groups-out received "1000". `set -u` cannot
  catch this: the variable is always set. 04 was unaffected only because it
  happened to use GROUPS_BEFORE/GROUPS_AFTER.
  Renamed to ALT_GROUPS; grepped every script for assignments to bash special
  variables and this was the only one. reconcile.py's write() now also
  tolerates a bare filename instead of raising.
- Verified after the fix: reconcile.py exits 0 and writes 7 link groups for
  base+webserver+pytools, including the libblas/liblapack alternatives that
  numpy registers.

## 2026-09-02 (07 green; linker cache verified as the exact union)
- 07 on base+webserver+pytools: 7 passed, 0 failed, 1 skipped. dpkg --audit
  clean, all three modules' requested packages satisfied, nginx -t and
  import numpy both pass.
- F3 now reports 140 libraries, up from 107. Checked against the layers
  rather than taken on trust:
      base                96
      webserver layer    131   (+35 over base)
      pytools layer      107   (+11 over base)
      union              140
  96 + 35 + 11 - 2 = 140, and the 2 libraries present in both deltas are
  libexpat.so.1 and libexpatw.so.1 -- i.e. libexpat1, which is exactly the
  class-1 benign overlap 05_check.sh reported for this pair weeks ago. The
  regenerated cache is the EXACT union, not merely a larger number, and two
  independent measurements (package metadata, linker cache) agree on the
  overlap. Worth using in the Evaluation chapter as a cross-check.
- Before reconciliation the composed cache was the top layer's 107, so ~35 of
  webserver's libraries were missing from it. Nothing broke, because they sit
  in the linker's default search paths -- which is why the smoke test could
  not have caught this and the measurement had to be made directly.
- Class 5 status: 10 of the 11 shared files handled. Only `status-old`
  (drop from the artefact) remains.
