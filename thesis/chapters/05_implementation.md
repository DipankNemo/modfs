# 5 Implementation

## 5.1 Pipeline and build inputs

The implementation turns a module specification into a sealed filesystem bundle, admits a selected set of bundles, and assembles it for verification or packing. The script numbers identify tools, not a mandatory linear sequence. In particular, metadata extraction follows an artefact build; binding verification precedes measurement; and the overlap and demonstration scripts are diagnostic tools rather than prerequisites for every image. Table 5.1 follows the operational sequence in `docs/RUNBOOK.md`, with the exact-parent requirement from `ARCHITECTURE.md` §13.

| Operation | Entry point | Output or condition |
|---|---|---|
| Check environmental assumptions | `00_verify.sh` | Required tools, mount capabilities, archive access, and delta representation checks. |
| Build the shared base | `01_build_base.sh` | Pinned, upgraded base root and `base.sqsh`. |
| Build a sibling or catalogue | `02_build_delta.sh`, orchestrated by `08_build_catalogue.sh` | Package installation captured as a SquashFS upperdir delta. |
| Extract metadata | `06_extract_metadata.sh` | Manifest and path-ownership sidecar derived from stored artefacts. |
| Re-derive and check bindings | `12_verify_binding.sh` | Manifest content agrees with its actual artefact and parent. |
| Admit combinations | `05_check.sh`, swept by `09_run_combinations.sh` | Metadata verdicts and the Tier-1 CSV. |
| Compose and verify sampled sets | `10_compose_sweep.sh` | Physical registry and visibility checks, with separate phase timings. |
| Exercise selected commands | `07_smoke_test.sh` | Chroot probes; useful before the more expensive boot. |
| Pack and boot | `11_boot_test.sh` | Bootable image and immutable run bundle. |
| Measure storage and updates | `13_storage_ratios.sh`, `14_report_update.sh`, `15_measure_monolith.sh` | Repository ratios, artefact hash/byte comparisons, and measured monolithic roots. |
| Generate thesis evidence | `16_build_evidence.sh` | Tables with source identity, coverage, and freshness checks. |

Table 5.1: Operational sequence. Sources: `docs/RUNBOOK.md` and `ARCHITECTURE.md` §§8, 13. `03_analyse_overlap.sh` and `04_compose.sh` support diagnosis and demonstrations outside this sequence.

`specs/modules.yaml` declares each module's requested packages, version, `requires`, `conflicts`, `provides`, a functional probe, and a `provokes` classification. Requested packages describe intent; resolved package contributions describe the installation actually obtained. The classification states why a catalogue member exists: `vim` and `emacs` exercise alternatives, `fake-cuda` exercises module requirements, and `control-oldsnap` deliberately violates the common snapshot. It is not a label inferred from artefact size (`docs/DATA_MODEL.md`).

`specs/uid-ranges.yaml` is the other authored input. Its windows are permanent and append-only. The current catalogue assigns windows of width 100 beginning at 2000; for example, `postgres` has 5200–5299 and `mysql` 5300–5399 (`thesis/evidence/catalogue.md`). Renumbering a window after building would change the intended owner of already stored numeric file identities. New modules therefore receive new ranges rather than reusing old ones.

## 5.2 Capturing a delta against the exact parent

The base builder uses `debootstrap`, then upgrades the base against the same snapshot pockets that sibling installations will see. This prevents a module from receiving newer base libraries merely because its APT view includes updates absent from the initial bootstrap. The snapshot identity is in the archive URL so both bootstrap and subsequent APT operations use the same archive view (`ARCHITECTURE.md` §§2–4).

A sibling build mounts the exact parent `base.sqsh` read-only and uses it as the lower filesystem of an OverlayFS mount. Packages are installed into the merged view, with an upperdir capturing newly written files, copies of modified base files, and deletion markers. The builder compresses only that upperdir. The exact-parent requirement matters: a leftover unpacked `base.dir` could contain bytes different from the archive whose digest is recorded in the generation. `ARCHITECTURE.md` §13 requires the archive itself as the parent; the runbook's older `base.dir` explanation must not weaken that requirement.

Before APT runs, both account allocators are redirected to the assigned window: `adduser.conf` controls `adduser --system`, and `login.defs` controls `useradd -r`. Both are needed because package scripts use both tools. The builder restores the original allocator configuration before squashing. Deleting a base file instead would leave a whiteout that hides the base policy during composition. The extractor later checks declared accounts and numeric owners of shipped files, because a file can borrow another module's UID even when its own module never declared that account (`ARCHITECTURE.md` §4; `docs/DATA_MODEL.md`).

Build-only mounts and daemon-start suppression let maintainer scripts run in the target root without treating it as a booted machine. A `policy-rc.d` hook prevents service startup; apt/dpkg logs and transient caches are excluded; the base machine identity is cleared; and archive inode timestamps are pinned. Completion markers are written after successful work. These measures remove specific unwanted outputs, but do not erase a password-change date embedded in `/etc/shadow`, a generated database identifier, or a host-dependent post-install result. They must not be described as a proof of byte reproducibility (`ARCHITECTURE.md` §8).

The builder also removes `trusted.overlay.opaque` under the checked flat-sibling preconditions. Such a marker was created against the base but would later hide entries from a sibling that did not exist at build time. The storage representation preserves ordinary file whiteouts, but the current builder conservatively refuses an upperdir containing them before applying this opaque-marker policy (`02_build_delta.sh`, pre-squash assertions). Thus representation support for deletion is not demonstrated support for building arbitrary deleting siblings. The evaluated pattern is additive; removals and directory replacement remain a separate validation problem (`ARCHITECTURE.md` §§3–4, 10).

## 5.3 Bundle schema and integrity checks

### 5.3.1 Artefact, manifest, and sidecar

Each module consists of `<name>.sqsh`, `<name>.json`, and `<name>.files.json.zst`. The manifest is small enough for routine admission; the sidecar supplies per-path ownership when Class 4 needs it; physical composition mounts the archive. Thus Tier 1 avoids mounts and root privileges, although it does consume the relevant sidecars as well as manifests. It does not rehash all SquashFS bytes on every metadata decision: artefact consumption and re-derivation have their own checks (`ARCHITECTURE.md` §5).

| Manifest group | Fields and meaning |
|---|---|
| Identity | `schema`, `module`, `version`, `parent`, `snapshot`, `suite`, `arch`, `built`, `generation`. |
| Installation | `requested`, contribution `packages`, and `removed`; each package retains its version and raw Debian relations. |
| Module policy | `requires`, `conflicts`, `provides`. |
| Identity and service observations | `uid_range`, `accounts`, `identity_audit`, `units`. |
| Artefact identity | `artifact.file`, `artifact.bytes`, `artifact.sha256`. |
| Integrity policy | `binding`, including required field coverage, source, and digests. |

Table 5.2: Manifest responsibilities. Sources: `docs/DATA_MODEL.md` and `ARCHITECTURE.md` §5. The sealed field set is explicit; ancillary metadata is not assumed to be covered merely because it appears in the document.

A module records only package contributions that differ from its parent, plus removals. Consumers reconstruct an effective package map from the base and contributions. If two selected sources offer incompatible versions, admission rejects the set before a map overwrite could conceal the disagreement. Package relations and module relations remain distinct: the latter require a selected module name or provided capability at an acceptable module version. Multiple providers of one capability are not automatically rejected unless an explicit conflict expresses that policy; provider cardinality is not represented (`ARCHITECTURE.md` §5).

The sidecar maps paths to owning package names and records diversions. Extraction operates on the stored module and parent artefacts so excluded build scratch cannot be mistaken for shipped content. This also lets the build tree be discarded. A sealed manifest can still describe the wrong *requested specification* if no one compares the spec with the installation; `jq`'s earlier missing `moreutils` is the project's concrete example (`docs/DATA_MODEL.md`; `thesis/evidence/catalogue.md`). Bundle consistency and fulfilment of operator intent are distinct conditions.

### 5.3.2 What each digest proves

| Commitment | Bytes or fields covered | Consumer obligation |
|---|---|---|
| Artefact digest | The exact `.sqsh` bytes, named by `artifact.sha256` and repeated in `binding.artifact_sha256`. | Check agreement of the recorded fields and hash the actual archive when consuming its bytes. |
| Sidecar digest | **Decompressed JSON bytes** from `.files.json.zst`. | Decompress, verify `binding.sidecar_sha256`, then parse and use ownership data. |
| Field digest | Canonical JSON of the required, named manifest fields. | Require the complete field list and presence of its members, then recompute `binding.fields_sha256`. |

Table 5.3: Bundle integrity contracts. Source: `ARCHITECTURE.md` §5; corroborated by `scripts/manifest_binding.py`. The data-model guide's compressed-sidecar wording is imprecise: changing a zstd encoding without changing its decompressed JSON is outside this digest's scope.

The field digest includes the `artifact` record and `generation`. The field list is required by the consumer, not negotiated by the document being checked. Otherwise a shortened document could announce a shorter list and pass its own hash. The sidecar digest is required separately because the `binding` object is not part of the field payload. This is a schema-policy issue, not an inherent cryptographic rule that a sidecar digest could never itself be covered by another digest.

`12_verify_binding.sh` mounts artefacts and re-derives metadata, which is stronger than checking that a document's hashes agree internally. Even re-derivation does not establish the identity of a trusted publisher. Someone able to replace the whole bundle and reseal it can create a consistent different bundle. Signing and an external trust root are outside scope (`ARCHITECTURE.md` §5).

A generation consists of snapshot, suite, architecture, and exact base digest, together with an identifier derived from those values. Module specifications are deliberately absent: a specification may change within one generation. A metadata refresh preserves the recorded generation rather than relabelling old bytes as children of the current base. Adoption for legacy artefacts is an explicit assertion about their origin, not reconstruction of missing historical proof (`ARCHITECTURE.md` §13).

## 5.4 Registry reconciliation

The composer mounts each selected SquashFS layer and overlays a writable reconciliation layer above them. It supplies the reconciler with layer roots in the intended precedence order. The reconciler writes parsed registry results into the top layer, then the native tools regenerate derived state. Relative lowerdir paths keep mount-option length manageable at high N. Mount creation, reconciliation, regeneration, and teardown must all preserve an observable failure rather than allowing partial scratch state to become a publishable result (`docs/SAMPLING_AND_BOOT.md`; `ARCHITECTURE.md` §§3–4).

### 5.4.1 Package status and installation marks

`dpkg/status` uses blank-line-separated stanzas. The format-level identity is package plus architecture, and different versions of the same effective package are incompatible. The current implementation, in the documented single-architecture scope, indexes status by package name. Consequently it should not be presented as a general multiarch union; the broader key described by `docs/REGISTRY_FORMATS.md` is a required extension for that claim. Repeated installed stanzas at the same version retain a selected source stanza, while version disagreement contributes an error. Fields outside the compared version can still depend on the selected layer.

`extended_states` also uses stanzas, but its semantics differ. APT generally records automatic installation positively; manual installation can be represented by the **absence** of an automatic stanza. Combining only explicit entries would miss a sibling's manual request. The reconciler considers the installed package records together with automatic marks, lets manual intent dominate, and inherits base marks when a delta has no replacement file. An empty output can therefore be necessary to clear a top layer's obsolete automatic flags. This is not ordinary last-layer precedence (`docs/REGISTRY_FORMATS.md` §4; `scripts/reconcile.py`, `merge_extended_states`).

### 5.4.2 Alternatives and diversions

An alternatives registry is positional: mode, generic link, slave-link definitions, then candidate paths, priorities, and slave targets. It must be parsed with that structure. `vim` offers `/usr/bin/vim.basic` at priority 30 and `emacs` offers `/usr/bin/emacs` at priority 0; retaining both candidates and running automatic selection chooses vim (`docs/REGISTRY_FORMATS.md` §2). If layers assign different priorities to the *same* candidate, the merger reports a conflict. It may retain the higher priority in the scratch output, but its nonzero result means that tree is not accepted. A diagnostic choice is not successful conflict resolution.

A diversion is a consecutive triple: original path, diverted path, and responsible package. Malformed or partial triples must fail rather than silently disappearing. The reference model identifies a diversion by original path. Inspection of `merge_diversions()` shows that the present implementation deduplicates whole triples; it does not independently reject different triples sharing the same original path. Thus malformed-record rejection is implemented, but a complete conflicting-diversion arbitration guarantee is not established. The intended original-path key and this implementation behavior must be distinguished when assessing supported compositions.

### 5.4.3 Accounts and debconf

The account group comprises `passwd`, `group`, `shadow`, `gshadow`, `subuid`, and `subgid`. Their record shapes are centralized in `account_schema.py`; names identify the ordinary account records, while subordinate ranges are retained as whole-line sets. Numeric UID, GID, and primary-group disagreement is an error. Group and gshadow membership is unioned as sets rather than overwritten. Other fields follow the declared highest-layer policy, and sensitive modes and ownership are preserved. Disjoint allocation windows prevent ordinary numeric collisions, but do not remove the need for this record union (`ARCHITECTURE.md` §4; `docs/REGISTRY_FORMATS.md` §5).

Debconf's `config.dat`, `templates.dat`, and `passwords.dat` contain records keyed by `Name`. `Owners` is a set, so overlapping owners are deduplicated; continuation fields in templates must survive parsing. Conflicting values or other incompatible shared fields are reported, and `passwords.dat` retains its sensitive attributes. Missing record keys are errors. The parser cannot legitimately call a merge successful merely because it recognized a subset of the source (`docs/REGISTRY_FORMATS.md` §6).

The reconciler accumulates problems and returns failure even if it has already written diagnostic output to the scratch tree. Its caller must discard a failed composition. Tested order reversals preserve semantic record sets for the documented examples, but record order and bytes differ, and conflicting highest-layer fields do not acquire general order independence from this mechanism.

### 5.4.4 Derived state and verification coverage

`/etc/alternatives/*` is regenerated by `update-alternatives --auto` from the merged candidates. `/etc/ld.so.cache` is regenerated by `ldconfig` from the composed library tree. These are the last two of the eight registry groups. They are functions of the merged inputs, so unioning their old outputs is inappropriate. Failure of either native tool is a failed composition (`docs/REGISTRY_FORMATS.md` §§7–8).

V2 checks package status, V3 alternatives, V4 the linker result, V6 accounts, and V8 debconf. V5 asks dpkg to audit its view, while V7 checks path visibility and selected file properties. This coverage does not give every registry an equally strong independent oracle: diversions and extended states do not have dedicated V-numbered semantic checks in the generated list (`thesis/evidence/tier2-checks.csv`). Trigger registrations also remain outside the handled registry set (`ARCHITECTURE.md` §10). These limits matter when interpreting a clean V1–V8 row.

## 5.5 Choosing compositions and constructing a machine

A requested plan maps layer counts to sample counts. The sampler combines declared requirements with exclusions learned from Tier-1 observations. It first explains a pair rejection that a later provider could satisfy; only irreducible exclusions belong in the pair-conflict model. Otherwise `fake-cuda` would be systematically excluded from high-layer sets despite belonging to an admissible set with its driver (`docs/SAMPLING_AND_BOOT.md`, Part 1).

When the admissible space or its complement can be enumerated, `exact` mode samples uniformly from it and reports its cardinality. For larger spaces, `sampled` mode uses a seeded, closure-aware greedy construction and is reproducible without being uniform. Every proposal still goes through `05_check.sh`. Refused proposals are evidence of model/checker disagreement, not observations to drop. The plan, seed, mode, attempted sets, and module coverage are needed to interpret a sweep; aggregate timing means alone cannot recover them.

Boot construction begins with bundle validation and admission. An explicit known-negative run may bypass the ordinary admission requirement for a stated experiment, but must not be labelled admitted. The same reconciliation mechanism then assembles the selected root. The packing stage adds a bootable kernel image, creates GPT/EFI and ext4 filesystems, copies the composed tree with numeric identities and attributes, and writes the boot configuration. Siblings do not contain the boot kernel image, although the driver sibling does contain kernel module objects; calling every sibling a purely userspace delta would conceal that ABI dependency (`ARCHITECTURE.md` §5; `docs/SAMPLING_AND_BOOT.md`, Part 2).

The guest harness records systemd state, foreign pending jobs, failed units, package audit, per-module probes, and listeners through serial markers. Its wait must exclude its own job, or the observer prevents the steady state it is waiting for. Probe observations prefixed for the harness are retained even on success. Partition devices must be usable before filesystem creation, and the disk must be sized for the actual root contents. These details determine whether the experiment tests the composed system or only a failure in its apparatus.

The bundle retains the serial log, verdict, run identity, and resolved kernel information. Recording a kernel digest establishes which boot input was used; it does not by itself make the whole build reproducible. Old bundles remain immutable, while later evidence generation assesses their currency against the artefact inventory. Current evidence uses freshness checks and recorded identities with the limits described in `provenance.md`; a freshness label should not be mistaken for a new content re-verification of every old run.

Ubuntu 24.04 portability required explicit `adduser` and `systemd-boot-efi` inputs, release-appropriate CUDA and driver package names, and sufficient image sizing (`docs/DATA_MODEL.md`; `docs/SAMPLING_AND_BOOT.md`). These observations explain where the procedure depended on distribution packaging. They do not import a Noble performance or storage result into the Jammy evaluation.
