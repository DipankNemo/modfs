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
