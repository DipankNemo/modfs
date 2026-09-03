# Comprehensive Read-Only Assessment of ModFS

**Audit date:** 3 September 2026  
**Repository:** `/home/kaptan/modfs`  
**Audited Git revision:** `24111f0072005898c14d4ab62c2dd8fc7b110d9c` (`24111f0`)  
**Current platform scope:** Ubuntu 22.04 (jammy), amd64, APT/dpkg, OverlayFS, SquashFS  
**Purpose:** objective technical and thesis-readiness assessment; no implementation changes

## 1. Scope, method, and evidence language

This assessment covers every text source presently visible in the repository: the top-level documentation and configuration, stages `00` through `11`, both Python helpers, the module catalogue, and the reproducibility test. The two directories named `docs/` and `reference/` are currently empty. In particular, the IDE context mentioned `reference/chatlog.txt`, but no such file is present in the filesystem, so an unsaved or no-longer-present editor buffer could not be audited.

The review also inspected, read-only, the generated evidence under `/srv/modfs`: 29 SquashFS/manifest/sidecar bundles (base plus 28 catalogue modules), the tier-1 and tier-2 CSVs, build trees relevant to shared-state analysis, and the two tier-3 run directories. No builder, composition script, QEMU run, package transaction, or other mutating project command was executed during this assessment.

Repository source was checked with `bash -n`; the Python files parsed successfully with `ast.parse`; and `specs/modules.yaml` parsed successfully with 28 module entries. `shellcheck` is not installed, so this was not a ShellCheck audit. Syntax success is not semantic correctness.

The report uses three evidence labels:

- **Observed:** read directly from source, a manifest/artifact, CSV, or preserved log.
- **Inferred:** follows strongly from observed state and documented system semantics, but the exact runtime symptom was not captured.
- **Potential:** a credible failure mode not yet exercised by the present catalogue or logs.

Severity means:

- **Critical:** can destroy data, invalidate a central correctness claim, or produce an accepted composition with a serious correctness/security defect.
- **High:** materially threatens correctness, reproducibility, or thesis validity and should be resolved or explicitly scoped out.
- **Medium:** weakens robustness, diagnostics, portability, or the precision of a claim.
- **Low:** documentation, ergonomics, or maintainability issue with limited immediate effect.

## 2. Executive verdict

### 2.1 Is the project thesis-worthy?

**Yes. It is already clearly thesis-worthy as a bachelor-level systems prototype and empirical investigation.** It is substantially more complex than a typical CRUD-style bachelor project: it crosses Linux filesystem semantics, image construction, Debian package metadata, global package-manager state, reproducible builds, combinatorial testing, and real UEFI/systemd boot validation.

The strongest parts are not just the amount of code. They are the research process and the negative results:

- the move from monolithic images to sibling upperdir deltas;
- empirical validation that whiteouts survive the SquashFS round trip;
- discovery and treatment of package-version drift;
- discovery that apparently ordinary files are actually shared registries;
- delegation of alternatives and linker-cache regeneration to their authoritative tools;
- a positive control from another snapshot;
- exhaustive pair coverage and sampled high-`N` structural composition;
- reproducibility investigation down to timestamps, logs, inode-dependent caches, hard links, and OverlayFS xattrs;
- and, now, a real boot that demonstrates the boundary between static correctness and runtime health.

That is a coherent systems thesis story. The project has a real problem, a designed artifact, a failure taxonomy, quantitative evaluation, and falsifiable experiments.

The objective limitation is this: **engineering complexity alone is not the thesis contribution, and the implementation is not yet watertight.** The remaining work is primarily about defining exactly what each tier proves, closing two newly demonstrated correctness gaps, preserving reproducible evidence, and narrowing claims to match the observations.

My overall rubric, not a predicted university grade, is:

| Dimension | Current assessment | Reason |
|---|---:|---|
| Engineering depth | Very strong | Privileged filesystem/image pipeline, package semantics, reconciliation, combinatorial and boot testing |
| Research question | Strong | Clear storage-versus-composability trade-off with testable hypotheses |
| Experimental creativity | Very strong | Adversarial catalogue, positive control, tiered tests, negative runtime case |
| Methodological maturity | Good, not final | Strong evolution, but verdict meanings and independent oracles need tightening |
| Evidence preservation | Weak to moderate | Important results live in mutable scratch; one raw dataset was overwritten |
| Generalizability | Moderate | One distro/release/architecture/snapshot/host and a deliberately non-representative catalogue |
| Production readiness | Low | Several accepted-set, identity, lifecycle, safety, and integrity gaps remain |
| Bachelor-thesis readiness | Strong, conditional | Strong contribution if the final claims, controls, and evidence ledger are corrected |

### 2.2 The best defensible central claim

The current broad claim should be replaced by something close to:

> This thesis designs and evaluates sibling filesystem deltas built from one pinned base generation. For the selected Ubuntu package catalogue, the approach substantially reduces stored root-filesystem payload while preserving same-generation package versions. The evaluation also shows that correct composition requires separate provenance, package-semantic, filesystem/state, and runtime validation tiers; snapshot pinning alone does not solve generated-state or runtime conflicts.

That claim is stronger academically than “pinning solves conflicts,” because the project now contains direct evidence of where pinning stops helping.

### 2.3 The most important current conclusion

There are **four different meanings of “works”** in the current project:

1. **Generation compatibility:** the delta belongs to the exact base generation and its artifact/metadata are authentic and mutually bound.
2. **Package consistency:** installed versions, negative relations, positive dependencies, removals, and virtual providers form a valid fixed package set.
3. **Structural coherence:** OverlayFS mounts and global registries/caches describe the visible filesystem after reconciliation.
4. **Runtime health:** the packed system boots to a stable state and the intended services, identities, listeners, and behaviors work together.

The current pipeline proves useful subsets of all four, but no single existing `PASS` proves all four. Making that explicit is the intellectual center of the thesis.

## 3. Current state: what has actually been achieved

### 3.1 Source and artifact state

At the start of this report, Git showed two pre-existing untracked project files:

```text
?? EVOLUTION.md
?? scripts/11_boot_test.sh
```

This matters because the newest narrative and the entire tier-3 harness are not protected by the current commit. `ASSESSMENT.md` is the only file intentionally added by this audit.

The external artifact catalogue presently contains:

- 29 manifests: base plus 28 catalogue entries;
- 29 corresponding SquashFS artifacts;
- 29 corresponding compressed file-ownership sidecars;
- 113 packages in the base manifest;
- 256,667,648 bytes across the base and all 28 deltas;
- zero modules with a non-empty `removed` set.

A read-only integrity cross-check found that all **29/29 current artifacts** match the byte count and SHA-256 recorded in their manifest, and all **29/29 sidecars** carry the expected module name and schema. This is good evidence about the present files. It does not remove the design gap that consumers never enforce those recorded hashes.

### 3.2 Build and reproducibility achievements

The implementation has achieved all of the following:

- a minimal pinned jammy/amd64 base from `snapshot.ubuntu.com`;
- alignment of the base with release, updates, and security pockets before sibling builds;
- deltas constructed as real OverlayFS upperdirs rather than copied full root filesystems;
- preservation of deletion whiteouts and opaque-directory semantics through SquashFS in the synthetic assumption test;
- deterministic SquashFS timestamps derived from the snapshot identifier;
- exclusion of time-varying package logs and inode-dependent linker auxiliary cache state;
- exclusion of host-specific OverlayFS `origin` and random `uuid` xattrs while retaining semantic overlay attributes;
- same-host byte-identical SquashFS payloads demonstrated for base, webserver, and pytools across two builds, with a documented webserver check across a base rebuild.

The safe wording is: **same-host byte reproducibility of selected SquashFS payloads has been demonstrated.** Cross-host payload reproducibility, all-module reproducibility, and whole-bundle reproducibility remain unproven. The JSON manifest intentionally includes a wall-clock `built` value, so the bundle as a whole is not byte-identical even when the `.sqsh` file is.

### 3.3 Storage result

The documented headline is approximately:

```text
modular base + catalogue deltas:    256.7 MB
calibrated monolithic estimate:   1,373.9 MB
reported ratio:                       5.35x
```

This is substantial and thesis-relevant. It must be described precisely as a **calibrated estimate for the selected root-filesystem workload under an independent-monolithic-image baseline**, not as a universal BMaaS storage factor.

Important qualifications are:

- the catalogue says explicitly that it is adversarial and mostly small, not representative of production BMaaS images;
- only six monolithic calibration points were directly built;
- the current monolithic comparison path is not guaranteed package-equivalent to the modular base because it does not perform the same full upgrade and does not fail hard on every comparison step;
- the total includes the deliberately incompatible `control-oldsnap` delta;
- metadata, a kernel, bootloader, disk filesystem, output-image retention, and runtime/persistent data are outside that 256.7 MB payload number;
- a content-addressed or block-deduplicating baseline would answer a different question and may narrow the advantage.

The result remains valuable if these boundaries are stated and the six baselines are rebuilt or validated for equivalence.

### 3.4 Tier-1 results

The preserved tier-1 CSV contains 3,654 combinations across 28 catalogue modules:

| Size | Total | ACCEPT | REJECT |
|---:|---:|---:|---:|
| pairs | 378 | 350 | 28 |
| triples | 3,276 | 2,900 | 376 |

For pairs, the 28 rejections consist of:

- 27 pairs containing the different-snapshot positive control; and
- one ordinary pair, `mta-msmtp + mta-nullmailer`, rejected through the virtual `mail-transport-agent` conflict.

No current module removes a package and no current same-generation module has class-6 base drift. The triple counts are the expected propagation of pairwise/precondition failures through triples; they do not prove that every future conflict property is pairwise.

The tier-1 work is a strong contribution. Its current limitation is that `ACCEPT` means “passes the implemented PRE/classes 1, 2, 3, 4, and 6 checks,” not “all installed package relations and all system state are consistent.”

### 3.5 Tier-2 results

The current `/srv/modfs/logs/compose-sweep.csv` contains all 351 pairs among the 27 ordinary same-snapshot modules. All 351 rows report structural `PASS`. Current medians in that CSV are approximately 29 ms for mounts, 131 ms for reconciliation, and 163 ms total, with 115–182 package names observed across pairs.

This is useful exhaustive coverage of the selected pair space. The accurate statement is:

> All 351 physical same-snapshot pairs mounted, reconciled, and passed the implemented package-name-union, alternatives-candidate, linker-cache, and `dpkg --audit` checks. Of those pairs, 350 were admitted by tier 1. The MTA pair was deliberately or accidentally composed despite tier-1 rejection and demonstrates that structural success is not package-semantic success.

The earlier 96-row sample from `N=2` through `N=27` is summarized in the journal and architecture, but its raw CSV was overwritten by the exhaustive pair run. Therefore the high-`N` timing/verification claim currently has narrative evidence, not the same retained raw evidence as the 351-pair run.

### 3.6 Tier-3 results

Two named directories exist under `/srv/modfs/build/boot/`:

- `runA`: stopped during pre-boot kernel installation; it has no disk image, QEMU log, or serial log.
- `runB`: contains a 3 GiB raw disk, OVMF variables, APT/reconciliation/rsync/QEMU logs, and a 52,709-byte serial log.

Run B is a real and valuable result:

- UEFI handed off to the kernel;
- the ext4 root mounted;
- systemd started;
- nginx started;
- Apache failed;
- `multi-user.target` was reached;
- `dpkg --audit` and both configuration probes printed `PASS`;
- the guest performed a clean system shutdown.

This directly demonstrates that static package/configuration success does not establish runtime coexistence. The expected explanation is port 80 contention because nginx starts and Apache then fails, but the exact Apache journal and `ss` port-owner output were not preserved. That causal explanation is therefore a strong inference, not yet a directly recorded fact.

Run A is **not a failed boot**. It is a failed pre-boot package transaction caused by an invalid selected set that contains the tier-1-rejected MTA pair. More importantly, simply removing one MTA still does not create a clean large-set test because the catalogue contains a newly confirmed account-identity collision described below.

## 4. Immediate critical findings

### C1. Unvalidated boot-run names can redirect a root recursive deletion

**Evidence:** observed in `scripts/11_boot_test.sh:34-59`.  
**Impact:** destructive local data loss.  
**Priority:** fix before another privileged tier-3 run.

`--name` is truncated but not validated, then used in:

```text
B="${BUILD_DIR}/boot/${NAME}"
rm -rf "$B"
```

A value such as `../../modules` resolves out of the boot directory and can make a root-run harness delete `/srv/modfs/modules`. The same general trust problem exists for module names used in paths and OverlayFS option strings. This is a direct safety defect, even if the current operator is trusted.

Required invariant:

- identifiers match a strict allowlist such as `[A-Za-z0-9][A-Za-z0-9._-]*`;
- `.` and `..` components are impossible;
- the canonical run path is proven to be a direct child of a fixed boot-results root;
- an existing mount or unexpected symlink under the target aborts the run;
- destructive deletion is performed only after that containment proof;
- numeric options have sane lower and upper bounds.

This pattern should be applied consistently to stages `02`, `04`, `05`, `06`, `07`, `08`, `09`, `10`, and `11`, because module identifiers enter file paths, report names, or mount option strings in all of them.

### C2. Four accepted ordinary modules collide in the system UID/GID namespace

**Evidence:** observed directly inside the SquashFS artifacts; runtime consequences partly inferred.  
**Impact:** missing service identities, service failure, wrong ownership interpretation, and possible privilege-isolation failure.  
**Priority:** central thesis finding; resolve or reject before claiming clean arbitrary composition.

Four independently built sibling deltas allocate the same numbers to different identities:

| Module | Account | UID | Primary group | GID |
|---|---|---:|---|---:|
| `mta-msmtp` | `msmtp` | 103 | `msmtp` | 104 |
| `redis` | `redis` | 103 | `redis` | 104 |
| `tcpdump` | `tcpdump` | 103 | `tcpdump` | 104 |
| `memcached` | `memcache` | 103 | `memcache` | 104 |

Each artifact contains its own complete changed copies of `/etc/passwd`, `/etc/group`, `/etc/shadow`, `/etc/gshadow`, and backup files. These files are created or rewritten by maintainer scripts and are not captured as ordinary package-owned files by the current class-4 sidecar.

OverlayFS uses the highest layer's complete file. It cannot union text records. Run A's observed layer-creation order ends in `memcached`, so the resulting account view would contain `memcache` but not `redis`, `tcpdump`, or `msmtp`.

Direct consequences visible from artifact contents include:

- Redis's unit declares `User=redis` and `Group=redis`, but those names would not resolve in a memcached-highest composition.
- Redis configuration and data are numerically owned by `103:104`; those numbers resolve to `memcache` in that composition.
- `/usr/bin/msmtp` is setgid 104 and its service requests `SupplementaryGroups=msmtp`; the name disappears while the numeric group is reinterpreted.

Tier 1 accepts `memcached + redis`; tier 2 also records that pair as `PASS`. Thus this is not merely a theoretical future class—it is a directly present accepted-set defect that the current invariants do not observe.

Required identity invariant:

1. A name maps to exactly one numeric ID.
2. A non-base numeric ID maps to exactly one intended name.
3. The final account databases contain the union of required users, groups, memberships, and shadow records.
4. Every systemd `User=`, `Group=`, and `SupplementaryGroups=` resolves.
5. Every relevant non-root numeric filesystem owner resolves to its intended identity.
6. Reversing module order does not change identity or ownership meaning.

Possible policies, in increasing implementation complexity, are:

- reject any set with independent allocations that collide;
- reserve deterministic global module/package UID/GID ranges before builds;
- create identities only at final image construction and remap every affected inode into a writable output;
- investigate a carefully constrained id-mapping design, while recognizing that per-layer numeric ownership and shared account names still require one coherent final namespace.

A plain record union is not sufficient because the numbers themselves conflict.

### C3. Tier 2 currently composes a tier-1-rejected set and labels it `PASS`

**Evidence:** observed in both preserved CSVs and Run A.  
**Impact:** the words “verified” and “admitted” currently overstate what tier 2 proves.

The exact contradiction is:

```text
Tier 1: mta-msmtp + mta-nullmailer -> REJECT
Tier 2: base + mta-msmtp + mta-nullmailer -> PASS
Tier 3 Run A: kernel APT transaction -> unmet dependencies before QEMU
```

This is possible because tier 2 checks structural properties after forcibly unioning installed status stanzas. `dpkg --audit` checks package-database sanity and partially installed or missing control data; it is not a proof that `Depends`, `Pre-Depends`, `Conflicts`, and `Breaks` form a satisfiable installed set. Debian documents `apt-get check` as the diagnostic that checks broken dependencies. See the official [`dpkg --audit` description](https://manpages.debian.org/bookworm/dpkg/dpkg.1.en.html) and [`apt-get check` description](https://manpages.debian.org/bookworm/apt/apt-get.8.en.html).

Required pipeline rule:

```text
bundle integrity -> tier-1 package admission -> compose/reconcile -> tier-2 structural verification
```

Known-negative experiments may bypass admission only in an explicit mode that records the expected rejection and never calls the physical result “admitted.”

### C4. Positive dependency closure is parsed but never verified globally

**Evidence:** observed in `scripts/05_check.sh`.  
**Impact:** a set can pass static admission after a required dependency is removed, hidden, or replaced incompatibly.

The checker parses `Depends` and `Pre-Depends`, but uses them mainly to explain class-6 upgrade chains. It does not verify that every installed package has at least one satisfying real or virtual provider in each positive relation group after module contributions and removals are combined.

This is not the same as writing a full dependency solver. Once the installed set is fixed, checking each relation against the fixed set is verification. It needs correct Debian version and virtual-package semantics, then should be cross-checked against APT on selected compositions.

This gap matters for:

- one module removing a base package another assumes;
- versioned dependencies after a sibling replaces a shared package;
- alternative dependencies;
- versioned and unversioned virtual providers;
- future multi-architecture names;
- and the MTA-style case where an apparently complete status union is semantically impossible.

### C5. The newest implementation and narrative are untracked, while raw evidence is mutable scratch

**Evidence:** observed Git status and result locations.  
**Impact:** source/evidence loss and an irreproducible final thesis record.

`scripts/11_boot_test.sh` and `EVOLUTION.md` are not in the audited commit. Boot output lives under `$BUILD_DIR`, which `config.sh` explicitly describes as scratch. Reusing `--name` recursively removes the prior directory. The original 96-row tier-2 raw CSV was overwritten by the exhaustive pair CSV. Run A has no terminal transcript or result record beyond phase logs.

Before final evaluation, preserve each result as an immutable, self-describing run bundle containing at least:

```text
run.json                    exact command, expectation, timestamps, duration
source.txt                  commit, dirty status, hashes of relevant scripts/config/spec
environment.txt             host, kernel, filesystem, tool/QEMU/OVMF versions
artifacts.txt               module names, manifest and SquashFS hashes
tier1.txt or tier1.json     admission result
reconcile.log
apt.log
qemu.log
serial.raw.log
serial.normalized.log
journal.txt
service-status.txt
listeners.txt
result.json                 machine-readable oracle outcome
COMPLETE                    written only after all prior evidence is durable
```

Large raw disks do not need to be committed, but their hashes, construction manifest, compact logs, CSVs, and result summaries should be archived outside mutable scratch and referenced from the thesis.

## 5. High-severity technical findings

### H1. Artifact, manifest, sidecar, and exact parent generation are not cryptographically bound at consumption time

**Current evidence:** all 29 present bundles match today.  
**Design risk:** high; stale, swapped, partially rebuilt, or modified inputs can pass using unrelated metadata.

Stage `06` records an artifact filename, size, and SHA-256, but stages `04`, `05`, `07`, `10`, and `11` do not verify that hash before trusting or mounting the artifact. The class-4 sidecar has its own module/schema fields but no hash binding to either the manifest or SquashFS payload. The precondition checker binds a delta to the string `parent: base` and a snapshot/suite/architecture, not to the exact base artifact, recipe, package set, builder revision, or generation identifier.

Consequently, all of the following are possible without a failing precondition:

- rebuilding `base` differently while retaining the same snapshot ID;
- leaving an old `.sqsh` beside newly extracted metadata;
- swapping two artifacts while retaining their JSON names;
- modifying an artifact after metadata extraction;
- using a sidecar from another build;
- changing `config.sh`, exclusion rules, or builder code without changing the declared module version.

The positive control demonstrates the distinction indirectly: it records an old module snapshot but was still constructed over the current `base.dir`, so it is a useful metadata alarm, not a coherent old-base generation.

Recommended bundle identity:

```text
generation_id = hash(canonical base manifest + base artifact hash
                     + config hash + builder revision + toolchain contract)

delta manifest contains:
  exact parent generation_id
  exact delta artifact size/hash
  exact sidecar size/hash
  module-spec hash
  schema/policy version
```

Every checker/composer should verify the complete bundle before privileged operations. Signatures are future work if artifacts cross a trust boundary; hashes and exact parent binding are correctness requirements even in a trusted lab.

### H2. Publication is only partly atomic and can mix generations

The JSON manifest uses a temporary file and `os.replace`, which is good. The overall bundle does not.

Observed risks:

- SquashFS is written directly to its final path after the old path is removed.
- The compressed sidecar is written directly with `zstd -f -o`.
- Stage `08` treats only `.sqsh + .json` existence as a complete, skippable build; it does not require the sidecar, matching hashes, current schema, expected snapshot, or parent generation.
- Stage `02` removes the upper/work/merged trees before rebuilding but keeps an older `.sqsh` and JSON until late. A failed install can therefore leave the last artifact beside a new partial upperdir. A later metadata refresh reads that partial upperdir while hashing the old artifact, creating a mixed manifest.
- The base completion stamp does not bind the snapshot, extra package list, configuration, or code revision. A config change can be silently ignored as “already built.”
- Fixed scratch directories and final filenames have no locks; concurrent builds or compositions can delete or write into each other's state.

Use a per-run generation directory and publish only by an atomic directory/symlink switch after every component verifies. A `COMPLETE` marker should be last and should contain the hashes it certifies. Skipping must mean “the complete expected generation verifies,” not “two filenames exist.” Keep the old generation explicitly as last-known-good or remove it explicitly—do not obtain that behavior accidentally.

### H3. Class-4 `Replaces` suppression does not implement Debian's file-overwrite semantics

`scripts/05_check.sh:409-419` treats the real package name **or any virtual name it provides** as satisfying `Replaces` for a file collision. Debian Policy distinguishes two uses of `Replaces`: virtual packages may participate when resolving whole-package replacement together with `Conflicts`, but for overwriting files the replaced package must be named by its **real name**. See [Debian Policy §7.6.1–7.6.2](https://www.debian.org/doc/debian-policy/ch-relationships.html#overwriting-files-and-replacing-packages-replaces).

Therefore the four MTA collisions reported as “SUPPRESSED as legitimate” are not evidence of legitimate file co-ownership. Both MTAs use the standard:

```text
Provides:  mail-transport-agent
Conflicts: mail-transport-agent
Replaces:  mail-transport-agent
```

That policy means only one MTA may be unpacked. The class-3 rejection is correct; the class-4 explanation is not. The overall current verdict remains `REJECT`, but the suppressed-collision count must not be presented as a successful coexistence case.

Even a real-name `Replaces` is not automatically enough for arbitrary layer stacking. During a normal dpkg transaction, ownership is transferred and versioned `Breaks`/replacement ordering is enforced. Static OverlayFS composition instead keeps both package database records and lets layer order choose bytes. A safe policy must either reproduce the package-manager takeover semantics, prove one package is no longer effective, or reject the composition.

### H4. Class-4 inventory covers only part of filesystem semantics

The sidecar is a useful scalable optimization, but its current meaning is narrower than “no file conflicts”:

- It is derived from dpkg `*.list` files. The official `dpkg-query` documentation states that such listings omit extra files created by maintainer scripts and alternatives. See [`dpkg-query --listfiles`](https://manpages.debian.org/bookworm/dpkg/dpkg-query.1.en.html).
- It deliberately drops directories, so file-versus-directory, symlink-versus-directory, and opaque-directory conflicts can be missed.
- One `path -> package` value overwrites any earlier owner inside a sidecar; multiple ownership is not preserved.
- It compares ownership declarations, not the visible object's bytes, symlink target, mode, UID/GID, ACL, xattrs, Linux capabilities, device type, hard-link group, or security label.
- It only reports different package names. The same package/version can still have different conffile or maintainer-generated content in two sibling builds.
- Any diversion record for a path currently suppresses the collision without proving that the diverter, diverted target, package ownership, versions, and final visible object agree.

The exact safe claim today is: **no unexplained collision was found among the package-owned, non-directory paths represented by the current sidecars, under the checker's current `Replaces` and diversion rules.**

A fuller filesystem oracle should compare complete upperdir/artifact inventories and capture at least object type, content or symlink target, mode, numeric owner, capabilities, xattrs, and whiteout/opaque markers. Not every difference is a rejection; each needs an explicit merge, regenerate, order, or reject policy.

### H5. Class 5 is not closed: debconf and dpkg trigger registrations demonstrably last-win

The current reconciler addresses:

- `/var/lib/dpkg/status`;
- `/var/lib/dpkg/alternatives/*`;
- `/var/lib/dpkg/diversions`;
- `/var/lib/apt/extended_states`;
- regenerated `/etc/alternatives/*`;
- regenerated `/etc/ld.so.cache`.

This was an excellent response to the early `webserver + pytools` evidence. The expanded catalogue now supplies direct counterexamples to the claim that these are the complete class-5 surface.

#### Debconf: observed

Every delta carries `/var/cache/debconf/config.dat` and `templates.dat`. Direct comparison shows:

- base `config.dat`: 14,151 bytes;
- webserver: 14,627 bytes with a different hash;
- mta-msmtp: 14,905 bytes with a different hash;
- mta-nullmailer: 14,500 bytes with a different hash;
- many unrelated later modules, including Apache, carry copies byte-identical to base.

In Run B, Apache is the highest of the tested package layers and its debconf databases are base-identical, so nginx's larger debconf state is hidden. nginx still starts, which shows why boot health and package lifecycle health are different properties. Future `dpkg-reconfigure`, removal, or upgrade can still be wrong.

#### dpkg trigger registry: observed

`/var/lib/dpkg/triggers/File` differs across current modules:

- base registers Debian utilities and the systemd catalog;
- Apache adds mailcap paths;
- Emacs adds `install-info`;
- msmtp adds GLib/GIO paths.

The topmost copy loses the other registrations. Immediate boot may succeed, while a later package transaction fails to invoke the needed triggers.

Other registries that require an explicit inventory and policy include `status-old`, dpkg selections/updates and trigger state, `statoverride`, UCF, debconf, sysusers/tmpfiles state, initramfs and application caches, certificate stores, PAM/NSS-related files, font/icon/GSettings/MIME caches, and any persistent application schema registry.

The governing invariant should be:

> Every semantic state object modified by more than one layer is explicitly classified as union/merge, regenerate, select-by-policy, reject, or deliberately unsupported. Silent last-writer-wins is never an implicit correctness policy.

If in-image APT upgrade/reconfiguration is outside thesis scope, say so clearly and call the result a fresh-deployment rootfs. If “updatable” includes normal future package transactions, debconf and trigger correctness cannot remain only a footnote.

### H6. Removal, whiteout, and opaque-directory composition are effectively untested

All 28 current delta manifests report `removed: []`. Stage `00` proves that one synthetic whiteout and opaque directory survive a SquashFS round trip, which validates the mechanism but not the multi-module policy.

The unresolved questions are more difficult:

- What if module A removes a base package that module B inherits and requires?
- What if one sibling whiteouts a path another sibling adds?
- Does module order decide whether an addition or deletion wins?
- What happens when an opaque directory masks unrelated files contributed by another module?
- Does the reconciled package database agree with the visible files after those operations?

The current implementations are not aligned. Tier 1 subtracts manifest removals while constructing its package view. `reconcile.py` instead unions every installed stanza found in every layer, so a base or sibling stanza can reintroduce the removed package into status. Tier 2's expected package set is also a raw union and will certify that reintroduction as correct.

OverlayFS explicitly represents deletion with whiteouts and opaque directories and gives the upper entry precedence; those semantics are documented by the [Linux kernel OverlayFS documentation](https://www.kernel.org/doc/html/latest/filesystems/overlayfs.html#whiteouts-and-opaque-directories). The thesis needs a policy above that mechanism.

At minimum, add one real removal module and test:

- it alone over base;
- it with a module that does not care;
- it with a module that depends on the removed object/package;
- both layer orders;
- package status, file visibility, dependency closure, and runtime behavior.

### H7. Reconciler conflict handling is incomplete and sometimes order-dependent

Specific observed issues in `scripts/reconcile.py`:

- package version divergence is printed but does not change the exit code;
- later status stanzas win even though a divergence should normally have been rejected before composition;
- `status-old` remains whichever layer wins;
- `extended_states` uses later-wins for the entire stanza, so auto/manual policy depends on layer order;
- if alternatives layers disagree on manual versus auto, the reconciler forces auto, which is a policy choice rather than a pure merge;
- an alternatives slave name first-wins its link without detecting a different link in a later layer;
- the same candidate path later-wins priority/slave maps without reporting disagreement;
- diversions are unioned as exact triples, but conflicting records for the same original path are not rejected;
- writes are direct, not atomic as one reconciliation transaction.

Reasonable policies would be:

- divergence reaching reconciliation is an error unless an explicit winner/version policy was admitted;
- manual-vs-auto selection is either forbidden across modules or represented in a separate deployment policy;
- all alternatives link, slave, priority, and candidate disagreements are validated;
- same-original diversions must be compatible, not merely distinct tuples;
- backups such as `status-old` are regenerated or removed consistently;
- the reconciliation layer is built in a temporary upper and published only if every registry and regenerated cache passes.

### H8. Tier-2 verification is materially weaker than its documentation says

The five checks are worthwhile, but their exact implementation is:

- **V2:** equality of package **name sets** only; versions, architectures, status stanzas, conffiles, and removal semantics are ignored.
- **V3:** expected alternatives candidate paths must be a subset of parsed merged paths; extra/stale groups, priorities, slave links, selection mode, and actual `/etc/alternatives` symlink targets are not checked. Parse failures are skipped.
- **V4:** the set of SONAME strings from layer caches must be a subset of the regenerated output. It is not an exact union despite the prose, and it does not validate target paths, visible library bytes, ABI, or stale entries.
- **V5:** `audit.txt` must be empty; the command's exit status is not recorded. Empty output from a failed command can pass.
- failures from `update-alternatives --auto` and `ldconfig` are ignored before verification.

In addition, `verify_compose.py` returns process status 0 even when its row says `FAIL`; the caller relies on parsing the row. That is intentional enough to work today but makes the helper's own exit status an unreliable oracle.

Recommended tier-2 contract:

- run only admitted sets unless an explicit negative mode is selected;
- compare architecture-qualified package name, version, and installed state against a removal-aware expected set;
- require reconciliation and regeneration commands to exit successfully;
- validate actual alternatives link group mode, candidates, priorities, slaves, and selected symlinks;
- validate linker entries against the visible filesystem and target existence, not merely the union of old caches;
- check `dpkg --audit` status and output;
- run `apt-get check` where APT indexes are available, or run the independently tested fixed-set dependency checker;
- make any failed invariant return nonzero as well as emitting a failed row.

### H9. The monolithic comparison path is not a controlled equivalent baseline

The optional stage-`02` comparison debootstraps plain jammy, writes the full pocket list, and installs base/module packages, but does not perform the same `full-upgrade` used by `01_build_base.sh`. Several comparison commands have no `|| die`, and the project deliberately does not use global `set -e`. A failed APT install or failed/stale monolithic SquashFS can therefore flow into `stat` and the storage calculation.

For every calibration module, preserve and compare:

- exact requested packages;
- complete installed package/version/architecture set;
- snapshot/source configuration;
- base recipe and APT options;
- cleanup/exclusion/compression options;
- successful exit status and artifact hash.

Ideally build a true jointly installed monolithic reference for selected multi-module compositions as an independent semantic oracle, not just singleton storage baselines. Compare its filesystem inventory, package state, identities, services, and generated registries against the modular composition.

### H10. Signal cleanup can tear down resources and then continue execution

`scripts/lib.sh:42` installs the same returning handler for `EXIT`, `INT`, and `TERM`. Stage `11` replaces it with another returning combined handler. A trapped interrupt can run cleanup and then allow the shell to continue into commands that assume mounts or loop devices still exist.

Separate normal-exit cleanup from signal termination. A signal handler should preserve a signal-derived exit code, disable recursive traps, clean up once, verify teardown, and terminate. Stage `11` should not clear `LOOPDEV` unless detachment succeeds. Critical unmount/detach failures need to affect the result.

Fixed shared scratch locations such as `build/compose`, `build/smoke`, and `build/csweep` also make concurrent runs unsafe. Use unique run directories and locks, and verify that no mount lies beneath a directory before recursively replacing it.

### H11. The tier-1 sweep can report success when workers or output accounting fail

In stage `09`, a worker maps checker failures to `BROKEN` in CSV but always exits 0. The main process prints broken rows but also exits 0. A missing-row count emits only a warning. This contradicts the documented exit contract that runner failure returns 2.

The final harness result should require all of:

- `xargs`/worker execution succeeded;
- expected row count equals actual unique row count;
- no `BROKEN` result;
- every row parses with the expected schema;
- the known controls produce their expected outcomes;
- the output was atomically finalized.

The old-snapshot control validates preconditions/class 2, and the MTA pair validates virtual class 3. They do not validate the entire checker. Retain synthetic fixtures for hard class 4, missing/corrupt sidecars, class 6, dependency closure, removal interactions, and internal exceptions.

### H12. Privileged composition executes artifact-controlled code on the host side of the VM boundary

Builders and composers chroot as host root into assembled filesystems while exposing host `/proc`, `/sys`, `/dev`, and `/dev/pts`. They execute the artifact's shell, Python, dpkg/APT maintainer hooks, `update-alternatives`, and `ldconfig`. Stage `11` then starts QEMU as root and does not explicitly disable networking.

This is acceptable only under an explicit **trusted official artifacts** threat model. A chroot is not a security boundary. If modules can be supplied or modified by another party, verify hash/signature-bound inputs before mounting and execute construction inside a disposable VM or stronger sandbox with minimized device exposure. Run QEMU unprivileged where possible and make networking explicit (`none` for offline tests, a controlled network for network tests).

## 6. Medium-severity and robustness findings

### M1. Stage `07` can finish successfully after partial harness failure

- `update-alternatives` and `ldconfig` errors produce warnings but do not increment failure count.
- zero functional probes prints a warning but exits 0.
- unreadable JSON can silently produce an empty requested set and a skip.
- `dpkg --audit` output is checked, not its exit code.
- linker validity is reduced to an arbitrary “more than ten entries” threshold.
- probe commands are trusted shell text executed as root in the chroot.
- there is no mandatory tier-1 preflight.

The script is a valuable smoke test, but “functional” should mean an exact expected probe count and successful prerequisite/regeneration commands. Configuration/version output is not equivalent to service health.

### M2. `03_analyse_overlap.sh` overstates what byte-identical regular files prove

It scans `find -type f` in disposable upperdirs and compares bytes. It does not examine symlinks, directories, whiteouts, device nodes, metadata, capabilities, xattrs, or hard-link relationships. “Identical -> last-wins harmless” is only true if all relevant metadata and semantics are also identical.

It is useful exploratory tooling; it should not be the final filesystem oracle, and artifact-based analysis is preferable when the design claims build trees are disposable.

### M3. Reproducibility normalization can affect semantics

Forcing every SquashFS inode mtime to the snapshot epoch is effective for byte stability, but mtimes can be application inputs. Timestamp-based bytecode, generated caches, `make`-style logic, or first-run update decisions may react differently after normalization. This is a test requirement, not evidence of a current failure: verify representative Python/cache behavior and document the normalization contract.

Maintainer scripts also observe the host kernel, devices, clock, randomness, filesystem, and tool versions through the bound chroot environment. The current same-host result does not establish hermetic or cross-host builds.

### M4. Architecture and multiarch handling is intentionally narrow but should be explicit

Several paths strip an architecture suffix from package names, and tier 2 compares unqualified names. That is consistent with the current amd64-only scope but not safe for future `Multi-Arch: same` compositions. `Architecture: all` still exists inside the current package universe, so schema and comparison language should say whether keys are binary package name alone or `(name, architecture)`.

### M5. Module-level dependency declarations exist in schema but are not enforced

The manifests preserve top-level `requires`, `conflicts`, and `provides`, and `ARCHITECTURE.md` says module relationships/capabilities are checked. Stage `05` does not implement those checks. Today those fields are schema provision for future use, not an admission guarantee.

A future capability model also needs cardinality: some capabilities are alternatives with many valid providers; others are exclusive. A blanket “only one provider” rule is not generally correct.

### M6. Current names, CSV, and TSV formats assume trusted simple tokens

Module names and package lists are moved through whitespace-separated strings, TSV, unquoted CSV, pathnames, and mount options. The current catalogue names are safe, but commas, tabs, newlines, spaces, `:`, backslashes, or leading option characters can corrupt parsing or change command meaning. Validate identifiers at catalogue load and use a real structured output writer for result files.

### M7. Documentation and status drift are now material

Examples include:

- `ARCHITECTURE.md` says 31 checks while the journal records 32;
- tier 3 is still listed as estimated/unrun;
- the pipeline table ends at stage 10;
- “all 351 admitted” conflicts with the MTA tier-1 rejection;
- module-level relationship checks are described as implemented;
- early rootfs combinations are called “bootable” before a kernel/bootloader image existed;
- `EVOLUTION.md` ends with “nothing booted” and claims cross-machine reproduction;
- the MTA catalogue note still predicts a virtual-conflict checker bug that has been fixed;
- the netcat note says both packages own `/bin/nc`, while later evidence shows the generic path is managed by alternatives;
- `README.md` omits stages 06–11 and refers to checker fixtures that are not present;
- `reconcile.py` says five registries, then lists four merged and two regenerated objects;
- `MEETING.md` is useful historical material but can be mistaken for current status.

Keep the journal chronological, including retractions. Make `ARCHITECTURE.md` the corrected current-state specification, mark `MEETING.md` archival, and create a separate final evidence ledger.

## 7. Reassessment of the historical six conflict classes

The six-class taxonomy was productive: it guided implementation and experiments. It should be retained as the historical taxonomy, but it mixes observations, conflicts, state-repair obligations, and build-invariant violations. The final thesis should acknowledge that and place it inside the broader model in section 8.

### Class 1 — same package, same version in sibling modules

**Current status:** well measured as package-level benign overlap.  
**Current evidence:** 60 pairs exhibit at least one such overlap, with 200 pair-level overlap occurrences in the retained sweep.

Snapshot pinning has done exactly what it was intended to do for this class: ordinary siblings repeatedly converge on the same package version. This is strong evidence that the base/pocket alignment and shared snapshot remove a major source of package-version skew.

However, “same package version” only proves a metadata equality. It does not prove:

- identical generated conffiles or maintainer-script outputs;
- identical modes, xattrs, ownership, or capabilities;
- equivalent account allocation;
- identical bytes if the repository or build input is mutable;
- correct trigger/debconf/alternatives state;
- or correct runtime interaction.

Class 1 is therefore a **benign package-overlap observation**, not proof of total filesystem harmlessness.

### Class 2 — sibling package-version skew

**Current status:** correctly detected for represented package contributions.  
**Current evidence:** no ordinary same-snapshot pair shows it; the old-snapshot control provokes it on selected shared packages.

This is a genuine success. The safe claim is that pinning plus base pocket alignment eliminated observed same-generation package-version skew in this catalogue.

Remaining assumptions:

- both deltas must bind to the exact same base generation, not merely the same parent name/snapshot string;
- package identity should include architecture where multiarch is in scope;
- the checker must reject or explicitly resolve any divergence that reaches `reconcile.py`;
- equal versions should be backed by repository/artifact integrity if same-version content replacement is in the threat model.

### Class 3 — declared `Conflicts`/`Breaks`

**Current status:** substantially implemented, including virtual providers.  
**Current evidence:** the two-MTA pair is correctly rejected via `mail-transport-agent`.

The correction for virtual package semantics is an important success. Remaining work:

- add positive dependency closure, not just negative relations;
- test versioned virtual `Provides` thoroughly;
- distinguish package self-conflict conventions from true cross-package conflicts;
- validate the parser against Debian control grammar fixtures;
- avoid reusing class-3 virtual semantics for class-4 file-overwrite `Replaces`, where Debian's rules differ.

The MTA pair should become a named negative control that is never part of a positive composition plan.

### Class 4 — undeclared package-owned path collision

**Current status:** implemented but partial, with one semantic error in `Replaces` suppression.  
**Current evidence:** no hard collision under the present sidecar rules; four MTA collisions are suppressed, but that suppression is not a valid coexistence case.

This class needs two levels:

1. a scalable package-owned-path screen using sidecars; and
2. a more complete artifact/upperdir semantic inventory for selected experiments and controls.

Add a retained hard-collision fixture. Otherwise “zero hard collisions” proves only that the current dataset did not reach that branch, not that the branch is correct.

### Class 5 — shared/generated state divergence

**Current status:** the central design insight, but the handled registry list is incomplete.  
**Current evidence:** status, alternatives, diversions, extended APT state, and linker cache were identified and selected parts reconciled; account databases, debconf, and dpkg trigger registrations now provide concrete missed cases.

Class 5 should be reframed as a **registry recipe framework**, not a fixed list. For every shared object, define one of:

- immutable and identical;
- set/stanza union with conflict rules;
- regenerated by an authoritative tool;
- selected by explicit deployment policy;
- order-sensitive by declared design;
- unsupported/rejected.

The account collision shows why generic “merge the files” is insufficient: some registries contain globally allocated identifiers whose meanings must be reconciled with inode metadata and service configuration.

### Class 6 — implicit base upgrade

**Current status:** successfully eliminated in the present catalogue after full-upgrading the base against the same pocket view.  
**Current evidence:** zero current class-6 hits.

This is a good example of removing a conflict class by strengthening the build invariant rather than writing a complex composition policy. The remaining decision is whether recurrence should be a warning. If the architecture requires sibling deltas against one exact base, an implicit inherited-package upgrade normally indicates a generation violation and should reject unless explicitly declared as an upgrade module with its own policy.

### Unnumbered precondition — parent/snapshot/suite/architecture compatibility

**Current status:** string-level validation implemented.  
**Missing:** exact parent artifact/recipe generation binding, module/artifact identity, sidecar binding, and policy/schema version compatibility.

This deserves a first-class provenance layer rather than an unnumbered preamble, because every later result depends on it.

## 8. Expanded conflict and failure taxonomy

The table below is the recommended comprehensive model. “Conflict” here includes incompatibilities, state-loss mechanisms, and invalid evidence paths; the historical six classes map into it without being discarded.

| ID | Layer | Failure mechanism | Present status | Minimum useful oracle/policy |
|---|---|---|---|---|
| P0 | Provenance | Delta built from a different exact base recipe/artifact/toolchain generation | Snapshot/name checked; exact generation missing | Parent generation hash and policy version must match |
| P1 | Integrity | Artifact, JSON, or sidecar stale, swapped, corrupt, or tampered | Hash recorded; 29/29 match now; consumers do not verify | Verify complete hash-bound bundle before use; optional signatures |
| P2 | Publication | Partial/interrupted/concurrent build mixes generations | JSON atomic only | Staged generation, locks, atomic publish, final `COMPLETE` marker |
| K1 | Package identity | Same package appears at incompatible versions/architectures | Historical class 2; ordinary catalogue clean | Compare `(name, arch, version)` and reject undeclared divergence |
| K2 | Negative relation | `Conflicts`/`Breaks` including virtual provider makes coexistence invalid | Historical class 3 implemented | Debian-policy fixture corpus plus known MTA negative control |
| K3 | Positive relation | `Depends`/`Pre-Depends` alternative has no satisfying real/virtual provider | Missing | Fixed-set closure verifier cross-checked with `apt-get check` |
| K4 | Base mutation | A delta silently upgrades/removes inherited base state | Historical class 6 detected; removals untested | Exact-parent invariant; declare or reject mutations |
| K5 | Module relation | Module-level `requires`/`conflicts`/capability cardinality violated | Schema exists; checker missing | Versioned module graph with explicit exclusive/non-exclusive capabilities |
| F1 | Owned path | Different packages claim the same non-directory path | Historical class 4 partial | Correct real-name/versioned `Replaces`, `Breaks`, diversion, and ownership policy |
| F2 | Generated path | Maintainer scripts create conflicting paths absent from dpkg lists | Accounts observed; general detection missing | Complete upper/artifact inventory with attribution where possible |
| F3 | Object semantics | Same path differs in type, target, mode, UID/GID, xattr, capability, ACL, hard links | Mostly missing | Compare full lstat/xattr/capability signature, not bytes alone |
| F4 | Deletion/order | Whiteout or opaque directory removes/masks another module's contribution | Mechanism tested synthetically; policy untested | Real removal fixtures, dependency checks, all relevant permutations |
| S1 | Package registry | Status, info files, backups, selections, diversions, alternatives disagree | Selected reconciliation implemented | Registry-specific semantic recipes and transaction-wide validation |
| S2 | Identity registry | User/group names or numeric IDs collide; memberships/ownership become wrong | Directly observed in four modules | Global allocation/rewrite or admission rejection; `getent` and inode-owner oracle |
| S3 | Package lifecycle state | Debconf, UCF, statoverride, triggers, pending updates lose information | Debconf/triggers observed, unreconciled | Merge/regenerate/reject; then exercise reconfigure/install/remove |
| S4 | Derived cache | Linker, initramfs, MIME, font, icon, GSettings, certificates, catalogs describe only one layer | Linker handled; broader inventory missing | Run authoritative generator and compare against visible inputs |
| C1 | Configuration | Separate valid files/snippets interact semantically without sharing a path | Application probes only | Application-specific validator and monolithic-reference comparison |
| B1 | Boot chain | Kernel, initramfs, firmware, bootloader, mountpoints, fstab, resolver or root fs contract inconsistent | Stage 11 exists; fsck issue observed | Formal packer contract, initrd inspection, positive/negative boots |
| B2 | Platform identity | Machine ID, hostname, MAC, FS UUID/label, SSH keys or entropy duplicated/invalid | Machine ID reset; other policy partial | Explicit per-instance identity generation and uniqueness assertions |
| R1 | Runtime resource | TCP/UDP port, Unix socket, D-Bus name, PID/lock file, mountpoint, device claimed twice | nginx/Apache negative observed | Declare expected resources; inspect actual listener/owner after startup |
| R2 | Service graph | Unit name/alias/mask/drop-in/enablement or ordering cycle changes startup | Mostly missing | `systemd-analyze verify`, unit graph comparison, enabled/active assertions |
| R3 | Health/readiness | Service starts then fails, is disabled, never starts, or is semantically unhealthy | Failed-unit snapshot and weak probes | Stable-state gate, dwell, expected unit/listener, request-response health tests |
| N1 | Network | Interface, route, DNS, firewall, address, port exposure, or network-online contract conflicts | Not demonstrated | Controlled network topology and explicit readiness/connectivity oracle |
| Q1 | Security policy | AppArmor, capabilities, PAM/NSS, sudoers, polkit, sysctl, udev, firewall weaken/block another module | Missing | Policy inventory plus targeted least-privilege/runtime tests |
| H1 | Hardware/ABI | Kernel ABI, DKMS, firmware, CPU feature, GPU/device requirement cannot coexist | Out of current sample | Declared hardware requirements and representative VM/real-hardware matrix |
| U1 | Update transition | Adding/removing/upgrading a module against persistent state breaks schemas or ownership | Missing | Generation-transition tests with retained `/var`/application data and rollback |
| X1 | Capacity | Combined disk, inode, RAM, CPU, FD, loop-device, lowerdir-length, or boot-time limits exceeded | Fixed 3 GiB boot image already near limit | Preflight sizing plus cumulative stress/threshold tests |
| E1 | Evidence | Mutable/overwritten/under-specified logs make a result irreproducible | One tier-2 CSV overwritten; boot results scratch | Immutable run bundle tied to code, environment, and artifacts |

### 8.1 Conflict families not covered by pairwise package metadata

These are especially important because an exhaustive pair sweep can still miss them:

- cumulative memory/disk/inode/startup-time exhaustion that appears only at larger `N`;
- a three-unit dependency or ordering cycle;
- several individually valid configuration snippets whose aggregate is invalid;
- global “exactly one” or “at least one” capability constraints;
- lowerdir/mount-option length, loop-device, or kernel stack-depth limits;
- identifier allocation exhaustion or conflicts introduced only after remapping;
- persistent-data schema transitions across generations;
- a security policy combination that becomes over-broad or contradictory only in aggregate.

The 2,925 triple checks are valuable for regression coverage, but because the current tier-1 properties are mostly pairwise/per-module, the arithmetic outcome is expected. Higher-order claims require higher-order oracles.

### 8.2 Recommended module specification additions

The catalogue should evolve from `name/packages/probe/provokes` toward a testable contract such as:

```yaml
name: redis
version: "1.0"
packages: [redis-server]
expects:
  packages: [redis-server]
  users: [redis]
  groups: [redis]
  services:
    redis-server.service: active
  listeners: ["tcp:127.0.0.1:6379"]
  files:
    - /etc/redis/redis.conf
  health:
    - redis-cli ping
resources:
  exclusive: []
  provides: [redis-service]
scope:
  package_lifecycle: true
```

This is illustrative, not a demand to implement a generic orchestration language before submission. For the thesis, a small explicit schema for expected users, units, listeners, and health commands would greatly strengthen tier 3.

## 9. Tier-3 boot forensics

### 9.1 Where the boot-test evidence is stored

Stage `11` writes named runs to:

```text
/srv/modfs/build/boot/<name>/
```

For a completed run, the important paths are:

```text
apt.log
reconcile.log
rsync.log
qemu.log
serial.log
disk.img
OVMF_VARS.fd
compose/alt.groups
```

These are under `BUILD_DIR`, not `LOG_DIR`. The same name is deleted at the beginning of the next run. The main terminal summary, QEMU return code, exact invocation, and parsed result are not written to a durable result file.

### 9.2 Test A: precise interpretation

Observed state:

- `runA/reconcile.log` reports 270 installed package stanzas, 22 alternatives groups, four diversions, and no version divergence.
- `runA/apt.log` contains only the APT unmet-dependencies error.
- no disk, QEMU log, serial log, or firmware-variable copy exists.
- the module mounts show base plus 26 deltas, including both MTA providers and the four conflicting account-allocating modules.

Therefore:

> Test A never reached image packing or boot. It is evidence that a structural registry union can remain unusable by APT when tier-1 admission is bypassed.

The immediate invalidity is the known MTA pair. After removing one MTA, the set still contains the Redis/TCPdump/Memcached identity collision. If that is resolved or avoided, the next likely harness problem is capacity: Run B's kernel transaction creates roughly 2.5 GiB in the writable upper, while the output disk is fixed at 3 GiB and the APT lists/archives are not cleaned before copying.

A genuine large positive set should be generated automatically from tier-1-admitted modules, exclude or explicitly resolve identity collisions, preflight its required disk size, and record the exact selected list.

### 9.3 Test B: what is proven and what is not

Observed in `runB/serial.log`:

- root filesystem mount and switch-root succeeded;
- systemd 249 started on Ubuntu 22.04.5;
- `systemd-resolved` and nginx started;
- Apache exited with status 1 and entered failed state;
- `multi-user.target` and the graphical target were reached;
- the tier-3 harness began and ended;
- `MODFS state: starting` was printed;
- `apache2.service` was listed as failed;
- `dpkg --audit`, `nginx -t`, and `apache2ctl configtest` all printed `PASS`;
- a clean shutdown reached system power-off.

This proves:

- the current packer can produce at least one UEFI-bootable composed rootfs;
- systemd can start services from multiple sibling deltas;
- configuration syntax probes can pass while one intended service fails at runtime;
- the tiered testing argument is empirically justified.

This does not yet prove:

- that Apache failed specifically because nginx owned port 80;
- that either module boots cleanly alone;
- that the result is independent of module order;
- that the system reached a stable state;
- that networking is configured and usable;
- that future package transactions retain nginx's debconf/trigger state;
- or that an arbitrary admitted set boots.

The correct current wording is “one successful UEFI/systemd boot that produced the expected runtime-negative service interaction,” not “tier 3 is generally passed.”

### 9.4 Boot-harness defects and missing observables

#### The steady-state race

The guest prints `starting`, and the parser extracts that value but excludes it from the verdict. Ubuntu's `systemctl` documentation states that `is-system-running --wait` blocks past `initializing`/`starting` until a later state such as `running` or `degraded`; see the [jammy systemctl manual](https://manpages.ubuntu.com/manpages/jammy/man1/systemctl.1.html). Because the harness itself is a startup oneshot, simply waiting inside that unit can deadlock the definition of “boot complete.” Use a separate timer/test target or another design that samples after the initial job queue is idle.

#### The exact service failure is discarded

Capture, for every expected unit:

- `systemctl is-enabled` and `is-active`;
- `systemctl show` result, substate, exit status, restart count;
- `systemctl status --no-pager --full`;
- `journalctl -b -u <unit>`;
- `ss -ltnup`/`ss -lxnp`;
- a real request-response health check.

That would turn the inferred port collision into direct causal evidence.

#### Expected services are not asserted

Listing failed loaded units does not catch a service that is absent, disabled, masked, or never attempted. The harness must know the exact units/listeners/users expected from each module.

#### Probe completeness and diagnostics are not enforced

Unknown/no-probe modules are silently omitted. The parser has no expected count, and probe stdout/stderr are discarded. Each probe needs an individual timeout, captured bounded output, duration, and a one-to-one expected-result record.

#### Command statuses can be lost

The guest checks whether `dpkg --audit` output is empty, not whether it exited successfully. `systemctl list-units` errors are suppressed. The host parser ignores an abnormal/timeout QEMU exit if both markers were already seen. A complete success predicate should be:

```text
ordered begin/end markers
AND exact expected check/probe count
AND every command exit status valid
AND acceptable stable systemd state
AND expected services/listeners/users healthy
AND guest requested a clean shutdown
AND QEMU exited successfully without timeout
```

#### The harness makes its own unit fail

After printing its end marker, the oneshot calls `systemctl poweroff`. Shutdown sends it SIGTERM before it returns, and the serial log records `modfs-boottest.service` failed with signal. Schedule shutdown separately so the test unit first exits successfully.

### 9.5 Image-construction findings

#### Root fsck is absent from the initramfs

Run B prints:

```text
Warning: fsck not present, so skipping root file system
```

The base artifact contains `/usr/sbin/fsck`, `e2fsck`, and `fsck.ext4`, but read-only `lsinitramfs` inspection finds none in Run B's initrd. The likely cause is directly visible in stage ordering: the kernel/initramfs is generated at lines 124–129, but the root `fstab` entry is written only at lines 192–194.

Finalize fstab before initramfs creation or regenerate the initramfs afterward. Then assert both that the executable is present in the initrd and that the serial warning disappears.

#### Boot scaffolding changes the experimental subject

Installing `linux-image-generic` and `initramfs-tools` into the composed overlay adds roughly twenty packages, including firmware, kernel modules, udev/kmod, microcode, and tooling. It performs another APT/dpkg transaction after reconciliation, can run triggers and modify registries, requires network/archive access, and leaves large APT lists/archives in the copied image.

The actual subject is therefore “composed rootfs plus a large post-compose boot transaction.” A cleaner experiment would use one pinned reusable boot-scaffold layer or a prebuilt kernel/initrd contract, then rerun package/structural checks after adding it.

#### Fixed disk sizing is fragile

Run B's raw image is 3,221,225,472 bytes, with approximately 3.06 GB of host blocks allocated, and the generated upper is about 2.5 GiB. Calculate required visible bytes and inodes plus explicit headroom, clean package caches, and reject an undersized request before partitioning/copying.

#### Missing/implicit base-machine configuration

- Run B has no `/etc/hosts` in base, webserver, Apache, or the generated upper despite setting hostname `modfs-guest`.
- Run A happens to inherit `/etc/hosts` from a different module, making basic host setup module-dependent.
- the NIC is discovered, but no address, DHCP completion, route, DNS query, or network-online condition is proven;
- the QEMU default MAC, fixed hostname, and fixed root label are fine for one isolated test but not a multi-instance uniqueness policy;
- early random-read warnings occur around first-boot identity generation; a virtual RNG would make the test environment clearer.

If the boot test is intentionally offline, disable networking explicitly. If BMaaS network readiness is a claim, add a controlled network oracle.

#### Portability details

The OVMF fallback changes the code firmware path without selecting a corresponding fallback variables template. QEMU reports two unsupported SVM feature warnings; they did not prevent this boot but environment/tool versions and selected acceleration should be captured.

### 9.6 Minimum causal test matrix for the nginx/Apache result

Run and retain:

| Case | Purpose |
|---|---|
| base | packer/boot baseline |
| base + webserver | nginx positive control |
| base + apache | Apache positive control |
| base + webserver + apache | interaction, nginx higher/lower as currently ordered |
| base + apache + webserver | reverse-order interaction |
| repeated pair runs | rule out transient timing behavior |

For both pair orders, record exact listener ownership, unit journals, active states, HTTP response identity, and stable systemd state. If the intended product policy allows only one HTTP provider, this may become a declared exclusive capability rejected in tier 1. If coexistence is intended, the composition policy must allocate distinct ports/addresses/configuration.

### 9.7 Minimum identity-conflict test matrix

Run only after the safe-path and cleanup defects are fixed:

```text
base + redis
base + memcached
base + redis + memcached
base + memcached + redis
base + tcpdump + redis
```

Assert `getent passwd/group`, unit identity resolution, numeric ownership of `/etc/redis` and `/var/lib/redis`, service health, and both orders. This is a stronger research experiment than quietly excluding the modules, because it demonstrates a real class-5 conflict created by independent sibling installation.

## 10. File-by-file assessment

This section is intentionally explicit because the audit request was to examine the whole codebase one file at a time.

### `.gitignore`

**Good:** excludes large regenerable artifacts, disk images, build outputs, editor noise, and Python caches.  
**Risk:** because all raw results are external/ignored, the evaluation needs a deliberately versioned compact evidence directory or immutable external archive. “Regenerable” is not the same as “sufficiently specified to reproduce.”

### `README.md`

**Good:** gives the core architecture concisely.  
**Issues:** stops at early stages, does not describe the three verdict tiers or result paths, and says `docs/` and `tests/` contain material/fixtures that are currently absent. It should become the operational entry point for the final frozen pipeline.

### `CLAUDE.md`

**Good:** establishes scope, code-freeze discipline, privilege boundary, and a canonical architecture.  
**Issues:** the canonical document is stale; the journal should be source material for thesis chapters rather than pasted as current truth; the rule “every script sources config and lib” has an intentional exception in stage `00`. The 29 September deadline makes scope control more important than broad new features.

### `ARCHITECTURE.md`

**Good:** unusually strong design rationale, explicit assumptions, conflict taxonomy, quantitative results, and acknowledgement of open questions.  
**Issues:** mixes current specification, proposal, historical results, and stale plans. Correct the 31/32 check count, module-level check claims, 351/350 admission language, boot status, “bootable” wording, pipeline table, state-registry scope, arbitrary-`N` wording, and current results. Narrow the central pinning claim.

### `EVOLUTION.md`

**Good:** excellent potential thesis narrative because it explains why the design changed and preserves failed hypotheses.  
**Issues:** untracked and ends before the latest pair/boot/account evidence. “Shipped files never conflict,” “cross-machine reproduction,” and “nothing booted” are no longer valid current statements. Preserve historical claims as dated beliefs and explicitly state their later falsification.

### `JOURNAL.md`

**Good:** one of the strongest assets in the project. It records concrete measurements, mistakes, corrections, and design decisions. That honesty improves scientific quality.  
**Issues:** early retracted claims remain searchable beside current ones; aggregate storage is sometimes called measured too broadly; “zero file collisions” needs sidecar scope; the 96-run overwrite and absence of post-boot entries are evidence gaps. Add a separate current evidence ledger rather than rewriting history.

### `MEETING.md`

**Good:** useful dated presentation artifact.  
**Issues:** contains intentionally old counts, scripts, storage estimates, and “bootable” language. Mark it prominently as an archived 6 August snapshot so it cannot be cited as current state.

### `config.sh`

**Good:** centralizes snapshot/platform/layout; derives a reproducible epoch; documents every exclusion and OverlayFS xattr decision unusually well.  
**Issues:** one snapshot string is not an exact generation; unsafe `MODFS_ROOT` values are not rejected; exclusion of entire runtime directories creates a packer contract that is only repaired later; forced mtimes need semantic testing; the trust/build environment is not hermetic.

### `scripts/lib.sh`

**Good:** central mount tracking, reverse unmount order, chroot environment, daemon suppression, and pinned source generation.  
**Issues:** returning signal traps, lazy-unmount fallback without a hard teardown invariant, host `/dev`/`sys` exposure, no run locking, and no general safe-path/name helpers. `remove_chroot_policy` removes `policy-rc.d` but deliberately leaves the APT no-recommends configuration; document that as final image policy.

### `scripts/00_verify.sh`

**Good:** tests the two architecture-enabling assumptions rather than assuming them, including functional whiteout and opacity behavior.  
**Issues:** a single synthetic tree does not test sibling deletion policy, nested/current-kernel variations, or all metadata. The tool list predates tier 3 (`qemu-system-x86_64`, `mkfs.vfat`, OVMF and timeout are not all covered there, although stage 11 checks several itself). Documentation count is stale.

### `scripts/01_build_base.sh`

**Good:** robust debootstrap error pipeline, full pocket alignment, package-state measurements, daemon suppression, cache cleanup, machine-ID reset, reproducible SquashFS options, and metadata extraction.  
**Issues:** the completion stamp is not configuration/generation-bound; artifact publication is not atomic; a rebuild removes prior base state in-place; the base recipe/package list is not recorded as a canonical input hash; privileged maintainer scripts observe the host-facing chroot.

### `scripts/02_build_delta.sh`

**Good:** constructs the true sibling upperdir, measures added packages, cleans build caches, unmounts before squashing, and extracts metadata last.  
**Issues:** unvalidated names and paths; stale artifact/partial-upper mixing after failure; no complete-generation publish; account IDs are independently allocated here; real removal behavior is absent from the catalogue; the optional monolithic baseline is not equivalent or fail-closed; several cleanup/comparison commands can fail without stopping.

### `scripts/03_analyse_overlap.sh`

**Good:** was an effective empirical discovery tool for shared files and package overlaps.  
**Issues:** regular files/bytes only, disposable upperdirs rather than published artifacts, no metadata/type checks, fixed shared assumptions, and “identical is harmless” language that is too broad.

### `scripts/04_compose.sh`

**Good:** clearly demonstrates naive last-wins failure and reuses the single reconciler; mounts published artifacts, not build trees; delegates regeneration to authoritative tools.  
**Issues:** no bundle/tier-1 gate, unsafe names/mount options, fixed scratch directory, version divergence can continue, and its success metrics are counts rather than a full semantic oracle. It is best described as a demonstration tool.

### `scripts/05_check.sh`

**Good:** explicit 0/1/2 contract, exception remapping, atomic-ish report handling, exact Debian version comparison via dpkg, virtual `Conflicts` support, positive-control preconditions, and scalable sidecar use.  
**Issues:** no artifact/hash/parent-generation binding; no positive dependency or module-level closure; order/removal ambiguity; incomplete path semantics; incorrect virtual `Replaces` file suppression; over-broad diversion suppression; no identity/debconf/trigger awareness; warnings still return accept, including class 6.

### `scripts/06_extract_metadata.sh`

**Good:** captures package contributions, requested/removed packages, six relation fields, artifact hash/size, automatic state, and class-4 sidecar; JSON uses atomic replacement; preserves hand-written module fields.  
**Issues:** sidecar is not atomically/hash-bound; directory and multi-owner information is lost; generated/unowned paths are absent; architecture suffixes are stripped; `built` prevents whole-bundle byte reproducibility; parent identity is weak; metadata can be refreshed from a partial upper beside an old artifact.

### `scripts/07_smoke_test.sh`

**Good:** composes real artifacts, performs APT simulations and module probes, and detects failures separately from harness breakage in its intended design.  
**Issues:** no tier-1/hash gate; regeneration failures only warn; zero probes and some metadata-read failures can still exit 0; `dpkg --audit` status is ignored; linker threshold is weak; probes often test versions/config syntax instead of service health; trusted YAML is executed as root.

### `scripts/08_build_catalogue.sh`

**Good:** deterministic catalogue iteration, duplicate-name detection, dry-run/selective/refresh modes, continues expected package failures, reports oversize artifacts.  
**Issues:** “idempotent” means two files exist; sidecar/hash/schema/generation are not verified; names/package tokens are not strictly validated; old artifacts can survive failed forced builds; TSV and unquoted package expansion assume safe tokens; logs are mutable filenames.

### `scripts/09_run_combinations.sh`

**Good:** exhaustive, seeded by a concrete catalogue, parallelizes independent checks safely at the row-file level, separates rejection as data, and records conflict categories.  
**Issues:** broken workers do not fail the harness; missing rows only warn; CSV is not robustly quoted; result parsing depends on human output strings; controls cover only some branches; default output overwrites prior runs.

### `scripts/10_compose_sweep.sh`

**Good:** seeded sample plans, actual mounts across `N`, real reconciliation, timing, exact name-set rather than count-only comparison, and exhaustive current pair evidence.  
**Issues:** includes tier-1-invalid sets; fixed scratch/output overwrite; ignored alternatives/linker failures; raw package union ignores removals; verification semantics are weaker than prose; `dpkg --audit` status is lost; the overwritten high-`N` dataset weakens reproducibility.

### `scripts/11_boot_test.sh`

**Good:** closes a major evidence gap with real GPT/UEFI/ext4/kernel/systemd boot, serial machine markers, failed-unit collection, probes, timeout, and clean guest shutdown. It has already generated valuable negative evidence.  
**Issues:** critical path traversal, no tier-1/hash gate, account collision, signal cleanup, fixed sizing and cache bloat, mutable evidence directory, packer transaction changes the subject, fstab/initramfs ordering, unstable-state verdict, incomplete expected-result count, discarded diagnostics, QEMU-status weakness, self-failing test unit, implicit network/identity choices, and no current clean positive run.

### `scripts/reconcile.py`

**Good:** single shared implementation; stanza-aware status union; structured alternatives parsing; delegates symlink/cache computation; reports divergence and malformed alternatives.  
**Issues:** incomplete registry universe; version divergence nonfatal; order-dependent extended state; alternatives conflicts partly silent; diversion conflicts not keyed by original path; status backup omitted; direct non-transactional writes; no account/debconf/trigger reconciliation.

### `scripts/verify_compose.py`

**Good:** independently constructs expected sets from mounted layers and avoids count-only package validation.  
**Issues:** unqualified names only; no versions/stanzas/removals; alternatives candidates only and subset semantics; parser errors skipped; SONAME-only linker subset; output-only audit; helper exits 0 on failed row.

### `specs/modules.yaml`

**Good:** adversarial selection is explicit; includes alternatives, diversions, virtual providers, runtime services, benign overlap, and a different-snapshot positive control.  
**Issues:** not representative by design; no coverage matrix or expected runtime identities/units/listeners; several probes can pass using the wrong provider; Redis/memcached only print versions; MTA/netcat notes are stale; account collision was not declared; “only boot can detect” a port conflict is too absolute because future static resource declarations could detect it.

### `tests/repro_check.sh`

**Good:** exemplary hypothesis-driven debugging of nondeterminism, fixed-tree versus rebuild distinction, tree diffs, inode/hard-link/xattr analysis, and retained evidence path.  
**Issues:** destructive targets still depend on validated environment/name assumptions; evidence is mutable scratch; same-host only; the final automated regression suite lacks the checker/reconciler/boot fixtures described elsewhere.

### Empty `docs/` and `reference/`

These directories currently contain no readable files. Any unsaved IDE buffer, including the mentioned `reference/chatlog.txt`, is outside this audit. Do not treat an open editor tab as preserved thesis evidence until the file exists on disk and is backed up.

## 11. Claim-to-evidence matrix

This matrix is the quickest way to prevent overclaiming in the thesis.

| Candidate claim | Current status | Defensible wording now | What would strengthen it |
|---|---|---|---|
| OverlayFS upperdir deltas survive SquashFS | Supported in current environment | One synthetic whiteout/opaque-directory round trip passed on the tested host/kernel/tools | Real package removal, multiple siblings/orders, another host/kernel |
| Pinning removes ordinary sibling version skew | Strongly supported for catalogue | No class-2 skew was found among ordinary siblings from the pinned generation | Exact parent hash, all-module provenance, multiarch-aware comparison |
| Pinning removes file conflicts | Contradicted as a broad claim | Pinning removes observed package-version skew; it does not remove generated-state, identity, owned-path, deletion, or runtime conflicts | Do not seek this broad claim; retain narrower result |
| Artifacts are byte-reproducible | Partially supported | Selected SquashFS payloads were byte-identical across repeated builds on one host | Repeat all or stratified modules; second host; record toolchain; distinguish JSON bundle |
| Current bundles are internally intact | Observed snapshot only | All 29 current payload sizes/hashes and sidecar identities match their manifests | Make every consumer verify; bind and optionally sign complete bundles |
| Class 3 catches declared conflicts | Supported for represented cases | The current checker rejects the two MTA providers through the virtual name | Policy fixture corpus including versioned virtual relations and self-conflict idioms |
| Class 4 finds all file collisions | Not supported | It screens package-owned non-directory paths under current suppression rules | Fix `Replaces`; full object inventory; generated files; hard negative control |
| Class 5 is reconciled | Partially supported | Four registries are merged and two derived objects regenerated | Accounts, debconf, triggers, backups, lifecycle tests, explicit registry inventory |
| Tier 1 proves composability | Not yet | Tier 1 enforces implemented provenance strings and selected package/path rules | Positive dependency closure, exact bundle/generation identity, identities/removals/module rules |
| All 351 ordinary pairs are admitted | False | 350 are tier-1-admitted; all 351 were physically composed in tier 2 | Filter tier 2 or label negative bypass explicitly |
| All 351 physical pairs pass selected structural invariants | Supported | Yes, for the current V2–V5 implementation | Stronger version/removal/state/link/command-status oracles |
| Composition scales to arbitrary `N` | Partially supported | A retained narrative reports 96 runs up to N=27, with one N=27 composition | Preserve raw run; repeat; probe resource/lowerdir limits; admitted high-N set |
| The result is order-independent | Not supported | Some selected set-union outputs are intended to be order-neutral; filesystem/config precedence remains ordered | Define order policy; reverse-order tests; reject order-sensitive safety state |
| Composed root filesystems work | Partially supported | Selected smoke tests passed; one UEFI boot reached multi-user | Strong probes, clean positive boots, identities/state/lifecycle checks |
| Run B proves a port-80 collision | Strong inference, not direct proof | nginx started and Apache failed in the designed interaction case; exact cause was not logged | Unit journal, listener ownership, single controls, reverse order |
| A clean large composition boots | Not established | No valid large positive tier-3 result exists yet | Correct set selection, identity policy, adequate disk, stable-state boot |
| Images are updatable | Ambiguous/unproven | Package metadata is partly reconciled; future transaction state is not complete | Define “updatable”; debconf/triggers/UCF/accounts; install/reconfigure/remove/upgrade tests |
| 5.35x storage saving applies generally | Not supported | 5.35x is a calibrated result for this selected workload/baseline | Equivalent baselines, uncertainty, representative workload, alternative dedup baseline |
| Boot images are byte-reproducible | Not supported and not required by current evidence | Module SquashFS reproducibility is separate from disk-image reproducibility | Deterministic GPT/FS/OVMF/identity process if this becomes a goal |
| Composition is safe for untrusted modules | False under current threat model | Current workflow assumes trusted artifacts and trusted catalogue input | Isolation, signatures, least privilege, safe path validation, unprivileged QEMU |

## 12. Threats to validity

### 12.1 Internal validity

- Artifact runs are not automatically tied to a Git commit, config/spec hash, toolchain, or exact base generation.
- `/srv/modfs` is mutable scratch, and a major raw dataset has already been overwritten.
- Some expected outputs and the verifier are derived from the same layer files, reducing oracle independence.
- The tier-2 package oracle defines correctness as the same raw union produced by the reconciler; it cannot detect a shared mistake such as ignoring removals.
- Repeated mount/build timings may use warm page cache and are not accompanied by repeated-run variance.
- Maintainer scripts observe host kernel/device/time/random/environment state.
- Tier 2 includes a known tier-1-invalid pair.
- Stage 11's post-compose kernel transaction can both expose and modify composition state.
- Fixed scratch paths and missing locks make simultaneous runs a confounder.

### 12.2 Construct validity

- `ACCEPT`, structural `PASS`, smoke-test success, and boot success currently denote different properties.
- `dpkg --audit` is not dependency/conflict satisfiability.
- package-name-set equality is not package-state equality.
- alternatives candidate inclusion is not selected/slave-link correctness.
- a SONAME set is not full linker target/ABI correctness.
- version/help/configuration probes are not service health.
- no failed unit does not prove an expected unit was enabled or started.
- rootfs SquashFS bytes are not complete deployable-image storage.
- same-host `.sqsh` equality is not cross-host or bundle reproducibility.
- sidecar “no collision” is not whole-filesystem “no conflict.”
- reaching `multi-user.target` while state is `starting` is not a defined stable state.

### 12.3 External validity

- one Ubuntu release, one architecture, one principal host/toolchain/kernel/filesystem environment;
- one archive generation;
- official repository packages rather than custom workloads;
- deliberately adversarial, mostly small modules rather than representative BMaaS configurations;
- no GPU, DKMS, vendor firmware stack, custom kernel, or real hardware;
- no cross-host rebuild result;
- no realistic persistent application data or generation transition;
- no alternative image storage baseline such as content-addressed layers or block deduplication;
- one runtime-negative pair and no retained clean positive boot matrix.

### 12.4 Conclusion/statistical validity

- 351 pairs are exhaustive relationships among 27 builds, not 351 independent module-build observations.
- 2,925 triples largely repeat pairwise properties and are not evidence for unimplemented higher-order checks.
- the high-`N` timing dataset has no retained raw CSV, repetition, confidence interval, or cache-condition study.
- the 5.35x aggregate is based on six selected calibration points; residuals and uncertainty should be reported.
- one Apache failure cannot quantify runtime-conflict prevalence.
- an adversarial catalogue estimates mechanism coverage, not population frequency in real deployments.

None of these invalidate the work. A good thesis states them and limits each conclusion accordingly.

## 13. A watertight target architecture

### 13.1 The pipeline contract

The final conceptual pipeline should be:

```text
source/spec/config
      |
      v
isolated build ---> complete hash-bound bundle ---> immutable publication
                                               |
                                               v
                              provenance + package admission
                                      | reject / admit
                                      v
                              filesystem composition
                                      v
                         registry recipes + regeneration
                                      v
                       structural and dependency validation
                                      v
                            deterministic boot packing
                                      v
                         stable-state runtime validation
                                      v
                         immutable evidence + conclusion
```

No later tier should silently bypass an earlier tier unless it is a named negative experiment with an expected result.

### 13.2 Core invariants

#### I0 — Exact generation

Every delta identifies the exact base payload, base manifest/recipe, snapshot, architecture, and policy/schema generation from which it was built.

#### I1 — Complete bundle integrity

Artifact, manifest, ownership/object sidecar, module spec, and parent identity are mutually hash-bound and verified before use.

#### I2 — Fail-closed publication

Interrupted, stale, concurrent, or partially rebuilt outputs cannot be mistaken for a complete generation.

#### I3 — Package semantic closure

The effective fixed set satisfies versions, `Depends`, `Pre-Depends`, negative relations, virtual providers, removals, and declared module constraints.

#### I4 — Filesystem semantic compatibility

Every cross-layer path difference has an explicit policy that accounts for type, content, metadata, whiteouts, opacity, and package-manager takeover/diversion semantics.

#### I5 — Global state completeness

Every shared registry/cache is inventoried and classified as merge, regenerate, explicit selection, reject, or unsupported.

#### I6 — Identity coherence

Users/groups and numeric ownership have one consistent, order-independent meaning.

#### I7 — Explicit order semantics

Either composition is commutative for a property, or precedence is a documented input and both the checker and tests reason about it. Safety-critical package/identity state must not change meaning merely because CLI order changed.

#### I8 — Boot-packer separation

Kernel/initramfs/firmware/fstab/resolver/mountpoints/identity are a declared scaffold. Adding them does not silently repair or corrupt the tested composition, and post-pack invariants are rerun.

#### I9 — Runtime contract

Boot reaches a defined stable state; every expected identity, unit, listener, and health behavior is present; unexpected failures are preserved with diagnostics.

#### I10 — Evidence provenance

Every reported number/result can be traced to immutable raw output, exact source and artifact hashes, environment, command, expectation, and oracle version.

### 13.3 Registry-recipe model

A small data-driven registry catalogue would make class 5 extensible:

| Object | Type | Example policy |
|---|---|---|
| dpkg status | stanza registry | removal-aware union; reject version divergence |
| dpkg alternatives DB | structured registry | merge candidates; validate link/slave/priority/mode conflicts |
| `/etc/alternatives` | derived links | regenerate with authoritative tool and verify targets |
| linker cache | derived cache | regenerate and verify visible target paths |
| passwd/group/shadow | global allocated namespace | global allocation/remap or reject conflicts |
| debconf DB | lifecycle registry | semantic merge/tooling or explicitly unsupported |
| dpkg trigger files | lifecycle registry | union with format-aware validation; run required pending triggers |
| initramfs | derived boot artifact | regenerate after final boot config; inspect expected contents |
| status backups/locks/logs | backup/ephemeral | regenerate, reset, or exclude by explicit policy |

The valuable design principle already present in the project is “use the authoritative tool where possible.” Extend that principle, but do not assume every registry has a safe authoritative union command.

## 14. Recommended validation programme

### 14.1 Unit and fixture layer

Create small, retained fixtures for each checker/reconciler rule. The oracle must state the expected exit class and explanation.

Minimum cases:

- exact parent hash match/mismatch;
- missing, corrupt, swapped, and hash-mismatched artifact/sidecar;
- same package/same version and same package/different version;
- real and virtual unversioned/versioned `Conflicts`;
- self-provided virtual conflict exception;
- real-name versioned `Replaces` versus virtual `Replaces` in file takeover;
- genuine hard package-owned path collision;
- diversion success, unrelated diversion, and same-original conflicting diversions;
- satisfied/unsatisfied alternative and virtual `Depends`/`Pre-Depends`;
- removal of an unused package and removal of another module's dependency;
- same name/different UID, different name/same UID, group membership conflicts;
- alternatives link/slave/priority/mode disagreements;
- debconf/trigger registry divergence;
- internal parser/command failure returning `BROKEN`, never `REJECT` or `PASS`.

Property tests can then generate module order permutations and assert that set-like registries are commutative/idempotent and conflict results do not depend on input ordering.

### 14.2 Artifact reproducibility layer

- Repeat base, small stateless module, large module, service-user module, alternatives module, and control on the same host at least three times.
- Run at least base plus one representative delta on a second host or clean VM.
- Compare `.sqsh`, sidecar, and canonical manifest separately.
- Record host filesystem, kernel, mksquashfs/dpkg/APT versions, locale, umask, CPU count, and environment.
- If whole-bundle reproducibility is desired, replace/exclude `built` from the canonical signed content or record it outside the reproducible manifest.

### 14.3 Storage layer

- Define the workload unit exactly: singleton module images, admitted combinations, or deployable node images.
- Rebuild calibration monoliths with the identical archive view and package recipe.
- Assert exact installed package/version equivalence before comparing size.
- Report direct points, model/formula, residuals, cross-validation or prediction error, and an uncertainty band.
- Report modular totals with and without the positive control and metadata.
- Add at least one representative larger server workload.
- State whether final per-node disks are cached and compare against one realistic alternative baseline if time permits.

### 14.4 Tier-1 combinatorial layer

- Rerun all 378 pairs and 3,276 triples after checker corrections.
- Preserve unique raw output and a run manifest.
- Require controls for every implemented rejection/warning path.
- Report 27 ordinary builds as the primary experimental units and pair/triple relations as exhaustive derived coverage.
- Produce an explicit catalogue-coverage matrix: target class, provoking modules, positive control, negative control, oracle, observed result.

### 14.5 Tier-2 structural layer

- Filter to the 350 currently admitted ordinary pairs; record the MTA pair separately as an expected preflight reject.
- Rerun the seeded `N=2..27` plan into a unique file and retain its selected sets.
- Make one high-`N` set package-, identity-, and removal-valid.
- Repeat timings and report median/IQR or range under documented warm/cold cache conditions.
- Check versions/removals, dependency closure, identities, actual alternatives symlinks/slaves, linker target existence, command statuses, and registry recipes.

### 14.6 Tier-3 runtime layer

At minimum preserve these groups:

1. **Packer baseline:** base only.
2. **Clean positive:** one ordinary module with strong runtime behavior.
3. **Large clean positive:** admitted and identity-safe high-`N` set.
4. **Port negative:** nginx and Apache, each alone and both orders.
5. **Identity negative:** Redis and memcached, each alone and both orders.
6. **Removal negative/positive:** after a real removal module exists.
7. **Lifecycle sample:** if updatability is claimed, perform `apt-get check`, one install that exercises triggers, one reconfigure, and one removal/upgrade against the composed image.

Every run needs stable-state gating, exact expected probe count, service journals, listener ownership, user/group resolution, package checks, filesystem capacity, QEMU exit status, and immutable evidence.

### 14.7 Differential monolithic oracle

For a small but representative subset, build the same requested packages together in one normal APT transaction from the pinned base. Compare the monolith against the modular result at four levels:

- installed package/version/architecture set;
- complete filesystem object inventory, with a documented normalization policy;
- global registries and account identities;
- enabled/active services and runtime health.

The monolith is not automatically perfect, but it is a substantially more independent oracle than deriving both expected and actual state from the same sibling layers.

## 15. Thesis framing and chapter plan

### 15.1 Suggested research questions

1. **RQ1 — Storage:** How much root-filesystem artifact storage can sibling deltas save for the defined workload compared with independently compressed monolithic images?
2. **RQ2 — Reproducibility:** Under what controlled conditions are the base and delta SquashFS payloads byte-reproducible?
3. **RQ3 — Static compatibility:** Which package/provenance/filesystem conflicts can be detected cheaply before composition, and what are the false-negative boundaries?
4. **RQ4 — Structural composition:** Which shared registries require reconciliation, and how does the measured reconciliation cost scale with module count?
5. **RQ5 — Runtime boundary:** Which failures remain invisible until boot/runtime, and what additional declarations/oracles are needed?

### 15.2 Suggested thesis structure

1. Introduction and precisely scoped problem statement.
2. System model, deployment lifecycle, trust model, and meaning of “updatable.”
3. Related work: layered images/OCI, OverlayFS/SquashFS, Debian package semantics, reproducible builds, content-addressed systems, system extensions, and BMaaS image delivery.
4. Design evolution from monoliths to sibling deltas.
5. Historical six classes and the expanded layered failure model.
6. Implementation: builder, manifest, checker, reconciler, structural verifier, and boot packer.
7. Experimental method: catalogue, controls, baselines, environment, oracles, repetition, evidence protocol.
8. Results organized by RQ, not by chronological script number.
9. Negative results: base drift, xattrs/hard links, virtual providers, generated state, account collision, invalid Run A, runtime Run B, fsck.
10. Threats to validity and limitations.
11. Future work.
12. Narrow evidence-matched conclusion.

### 15.3 Why the negative results help rather than hurt

A bachelor thesis does not need to deliver a production-ready universal modular OS. It does need to show rigorous reasoning and honest evaluation. The account collision, debconf/trigger loss, and nginx/Apache boot outcome are valuable because they falsify simpler hypotheses and produce a more accurate model.

If there is not enough time to implement every registry before submission, the academically sound choice is:

- fix safety defects before further privileged runs;
- correct the central admission/identity cases or explicitly reject them;
- preserve strong positive and negative controls;
- state exactly which lifecycle is supported;
- present remaining registry/runtime families as demonstrated limitations and future work.

Do not hide a negative result or relabel it as success. Explain how it changed the architecture.

## 16. Priority backlog under the current deadline

The repository declares a 2 September code freeze and a 29 September submission. Work should now be validity-driven, not feature-driven.

### P0 — before any further root-run test

1. Validate/canonicalize run and module identifiers; protect every recursive deletion target.
2. Correct signal termination and verify mounts/loops are gone after cleanup.
3. Preserve/commit or otherwise back up the untracked `EVOLUTION.md` and stage-11 script.
4. Make boot run directories unique and write a machine-readable result/invocation before deletion can occur.

### P0 — before final conclusions

1. Define the four verdict meanings and correct all 351-versus-350 language.
2. Add a mandatory tier-1/bundle-integrity gate to positive tier-2/tier-3 workflows.
3. Resolve or reject UID/GID/account conflicts; update the class-5 conclusion.
4. Correct virtual `Replaces` treatment and stop calling the four MTA collisions legitimate.
5. Preserve a fresh valid large positive test plan; do not call Run A a boot test.
6. Fix fstab/initramfs ordering and require a stable, count-complete guest verdict.
7. Record Run B honestly: boot success, Apache service failure, inferred-not-proven port cause.
8. Rebuild or validate equivalent monolithic calibration points and scope the 5.35x claim.
9. Freeze a final immutable evidence set tied to the exact commit/artifacts/environment.
10. Update `ARCHITECTURE.md`, `README.md`, and the current-results narrative; retain the journal history.

### P1 — highest evidential return per unit effort

1. Add fixed-set dependency closure and/or `apt-get check` to selected compositions.
2. Run base, nginx-only, Apache-only, both orders, with journals and `ss` output.
3. Run Redis-only, memcached-only, and both orders after defining expected rejection/repair behavior.
4. Add one real removal module and both orders.
5. Add one hard class-4 fixture and policy fixtures for `Replaces`/diversions.
6. Preserve a new raw high-`N` run and repeat timings.
7. Reproduce one representative artifact on a second host/clean VM.
8. Perform one monolithic-versus-modular differential comparison.
9. Decide whether debconf/trigger correctness is in scope; test it if “updatable” means future APT transactions.

### P2 — valuable if time remains

- complete bundle/generation hashing and atomic publication;
- data-driven registry recipe catalogue;
- stronger alternatives/linker/file metadata verification;
- explicit runtime expectations in YAML;
- automatic image sizing and reusable boot scaffold;
- network-ready boot test;
- representative larger workload and alternate storage baseline.

### P3 — future research/engineering

- signed/content-addressed module repository;
- module constraint/capability language with a solver;
- automatic UID/GID allocation and ownership remapping;
- persistent-data schema and rollback/migration framework;
- real BMaaS/MAAS provisioning integration;
- multiarch and cross-distribution support;
- GPU/DKMS/firmware and real-hardware evaluation;
- security-policy reconciliation;
- fuzz/property-based generation of package/state conflicts;
- comparison with OCI layering, OSTree/composefs, Nix/Guix-style stores, and systemd system extensions;
- deterministic full disk-image construction if operationally required.

## 17. Decisions that must be explicit in the thesis

These are not implementation details; different answers materially change the claim:

1. Does “updatable” mean selecting a new immutable module generation and reprovisioning, or running arbitrary future APT transactions inside the composed machine?
2. Are module artifacts fully trusted, or can tenants/third parties supply them?
3. Is module order a meaningful user policy, or should all admitted sets be order-independent?
4. Are packages allowed to remove/upgrade base packages, or are sibling deltas addition-only?
5. Is the kernel/boot scaffold part of the shared base, a separate reusable layer, or generated per composition?
6. Are nginx and Apache supposed to be mutually exclusive providers or configurable co-residents?
7. What is the unit represented by the storage denominator: singleton rootfs, configuration, deployable disk, or cached fleet state?
8. Are persistent `/var` and application data part of composition, or supplied separately per node?
9. Must outputs be byte-reproducible across hosts, logically reproducible, or only package-version reproducible?
10. What exact subset of Debian package lifecycle state is guaranteed after composition?

Answering these clearly can reduce required implementation work because unsupported behaviors become honest scope boundaries rather than accidental gaps.

## 18. Final objective assessment

### What is already excellent

- The core delta architecture is implemented, not merely proposed.
- The work is measurement-driven and records several genuine hypothesis revisions.
- Snapshot pinning and base pocket alignment have eliminated observed ordinary package-version skew.
- The project found and repaired real OverlayFS/SquashFS reproducibility causes.
- It recognized that package/global state needs semantic reconciliation rather than ordinary last-wins files.
- The adversarial catalogue, known-bad controls, exhaustive pair sweep, sampled high-`N` sweep, and real boot form a strong multi-tier methodology.
- Run B is exactly the kind of negative result that gives a systems thesis intellectual depth.
- The newly exposed account collision is a strong additional contribution because it shows that expanding the catalogue changed the known correctness boundary.

### What is not yet justified

- universal or arbitrary module composability;
- a claim that pinning reduces all relevant conflicts to package metadata;
- all 351 ordinary pairs being semantically admitted;
- complete class-5 reconciliation;
- order independence;
- cross-machine artifact reproduction;
- a clean high-`N` boot;
- causal proof of port 80 ownership in Run B;
- normal future APT/update correctness;
- production or untrusted-artifact safety;
- or a generally applicable 5.35x BMaaS storage factor.

### Bottom line

The project is not “too incomplete to be a thesis.” It has reached the more interesting stage where the prototype has produced evidence that refines the original theory. With disciplined scoping, corrected safety/admission/identity handling, preserved experiments, and exact claim wording, it can support a very strong bachelor thesis.

The single best final message is:

> Sibling deltas are a practical and storage-efficient representation under a pinned exact base, but composability is layered. Package metadata can reject some sets cheaply; filesystem/global state must be reconciled with type-specific policies; and runtime boot tests remain necessary. The prototype quantifies each tier and exposes concrete counterexamples—virtual-package conflicts, account namespace collisions, lost lifecycle registries, and service resource contention—that define the limits of a purely file-layer approach.

## 19. Primary technical references used in this assessment

- [Debian Policy: package relationships, virtual packages, Conflicts, Breaks, and Replaces](https://www.debian.org/doc/debian-policy/ch-relationships.html)
- [Debian Policy: files and configuration files](https://www.debian.org/doc/debian-policy/ch-files.html)
- [`dpkg(1)`: audit semantics](https://manpages.debian.org/bookworm/dpkg/dpkg.1.en.html)
- [`apt-get(8)`: `check` and simulation semantics](https://manpages.debian.org/bookworm/apt/apt-get.8.en.html)
- [`dpkg-query(1)`: ownership-list limitations](https://manpages.debian.org/bookworm/dpkg/dpkg-query.1.en.html)
- [Linux kernel OverlayFS documentation](https://www.kernel.org/doc/html/latest/filesystems/overlayfs.html)
- [Ubuntu jammy `systemctl(1)` documentation](https://manpages.ubuntu.com/manpages/jammy/man1/systemctl.1.html)

These references support interpretation of package-manager, OverlayFS, and systemd behavior. Project-specific results come from the audited source and preserved `/srv/modfs` evidence described above.
