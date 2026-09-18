# ARCHITECTURE

Modular, updatable filesystem for Bare Metal as a Service.
BSc thesis. Submission **29 September 2026**. (Code freeze of 2 September 2026 lifted on 18 September.)

Scope: Ubuntu 22.04 (jammy), APT/dpkg, x86-64.

---

## 1. Problem

BAAS stores each machine image as an opaque whole-disk blob. Ten use cases
sharing one Ubuntu base means ten full copies. Updating one package means
rebuilding and re-shipping every image.

Goal: ship the base once plus thin per-use-case modules, know which modules
compose validly, and update at module granularity.

---

## 2. Core design: pinned sibling deltas

1. **Pin.** Every build draws from one fixed archive snapshot
   (`snapshot.ubuntu.com/ubuntu/<ID>`). The ID goes in the URL path — debootstrap
   does not understand apt's `[snapshot=]` option, and jammy ships apt 2.4.5
   which predates `--snapshot`.
2. **Base.** Built once by debootstrap, then `full-upgrade`d so it matches the
   same archive view deltas will see.
3. **Modules.** Built by overlaying the parent read-only, installing into the
   **merged** view, and squashing **only the upperdir**. apt sees base as already
   installed, so the upperdir holds only what is new. The filesystem captures the
   diff; we never compute it.
4. **Compose.** Stack modules as read-only lowerdirs (leftmost = highest
   priority) plus a computed reconciliation layer on top.

**Central claim:** pinning reduces an intractable *file-level* conflict problem
to a small, declarative *package-level* one.

### Constraints
- Modules always sit directly on base. No delta-on-delta.
- Composable only with siblings sharing the same base **and** snapshot.
- Snapshot bump ⇒ rebuild base **and all siblings**, atomically per generation.
- No rollback required (old artefacts may simply remain on disk).
- Nodes are fully re-flashed; the pipeline must also work standalone.
- Base may be fat; larger base ⇒ smaller deltas.

---

## 3. Verified assumptions

**A. Archive pinning works.** All three pockets (`jammy`, `-updates`,
`-security`) resolve under the snapshot URL.

**B. Deltas survive SquashFS.** OverlayFS stores deletions as character devices
`0:0` and directory replacements as `trusted.overlay.opaque` xattrs. Both
survive a mksquashfs round trip and still function when the compressed delta is
remounted as a lowerdir. **31 checks, 31 passed** — 30 until a `python3-yaml` check was added for the module catalogue.

> **Revised 2026-09-16.** The assumption is *true* and was the wrong thing to
> want. Opaque markers did survive, faithfully — and that is what broke
> composition. A marker is written against the stack present at BUILD time,
> where the only lower layer is base; at COMPOSE time the lower layers are the
> sibling modules, which did not exist when the marker was made. It then tells
> OverlayFS to ignore them. In the 36-module boot, `pyyaml`'s opaque
> `/usr/lib/python3` erased the whole of `pytools`' numpy tree, and every
> metadata check passed because `dpkg` was correctly reporting a package whose
> files were not visible.
>
> Measured across 38 modules: **869 markers, 456 distinct directories, 178
> claimed by two or more modules.** Of those 456, **zero exist in base**, **zero
> modules carry a whiteout**, and **every module's parent is base** — so no
> marker was ever hiding anything, and none can be honouring a deletion. With
> **zero file collisions across all 703 pairs**, merging those directories is
> safe by construction.
>
> `trusted.overlay.opaque` is therefore now stripped at squash time alongside
> `uuid` and `origin`. Whiteouts are untouched, so file-level deletion semantics
> are unchanged; only "replace this whole directory" is dropped, and nothing
> used it. `02_build_delta.sh` asserts the two preconditions on every build
> rather than trusting this paragraph, and tier 2 gained **V7**, which requires
> every path present in any layer to be visible in the merged view, as the same
> kind of file, at the same size for regular files (and, after H3, with a
> target offered by a source layer for symlinks) — the check that would have caught this on the
> day it was introduced.
>
> **What V7 does NOT check, measured 2026-09-18 (round 2): content.** It records
> `(kind, size)` for regular files, so a regular-file substitution that preserves
> size passes. Correction H3 additionally compares symlink target text without
> following links.
> Reproduced on the real artefacts: compose `base + curl`, overwrite
> `/usr/bin/curl` in the merged view with 260 328 bytes of the letter `X`
> (the binary's exact size), and the tier-2 row is byte-identical to the
> baseline — `vis_ok=1`, `vis_missing=0`, verdict PASS — while `curl --version`
> no longer runs inside the chroot. V7 catches the shape of this failure where
> the size moves, which is the shape the opaque-directory bug had; a padded one
> it does not. Content verification is a per-file hash and was measured as too
> expensive for the tier it would sit in (§6); this is a stated limitation, not
> an oversight.

---

## 4. Conflict taxonomy

| # | Class | Cause | Detection | Policy |
|---|---|---|---|---|
| 1 | Benign overlap | Same package, same version, two siblings | Version match in union | Accept; measure duplication |
| 2 | Version skew | Different snapshots, parents, or explicit pins | Version mismatch | Reject |
| 3 | Declared conflict | `Conflicts:` / `Breaks:` | Match declarations vs union, **resolving virtual names** | Reject |
| 4 | File collision | Different packages own the same path | Intersect per-module `<name>.files.json.zst` sidecars; honour `Replaces:` and diversions | Reject — **implemented** |
| 5 | State divergence | Registry files rewritten by every module | Structural, always occurs | Reconcile or regenerate |
| 6 | Implicit base upgrade | Delta upgrades a package inherited from base | Compare delta vs parent versions | Prevent; detect recurrence |
| 7 | **Identity collision** | Two modules independently allocate the same UID/GID to different names | Compare account records across manifests | Reject — **implemented** |

### Class 7 — identity collision

Discovered by external audit, not by any check the project had. `/etc/passwd`,
`/etc/group`, `/etc/shadow` and `/etc/gshadow` are rewritten wholesale by
maintainer scripts. They are **not package-owned**, so class 4 never sees them,
and OverlayFS takes the top layer's copy *entire* — it cannot union text
records.

Four modules in the catalogue independently allocate the **same numbers to
different names**:

| Module | Account | UID | Group | GID |
|---|---|---:|---|---:|
| `mta-msmtp` | `msmtp` | 103 | `msmtp` | 104 |
| `redis` | `redis` | 103 | `redis` | 104 |
| `tcpdump` | `tcpdump` | 103 | `tcpdump` | 104 |
| `memcached` | `memcache` | 103 | `memcache` | 104 |

In a memcached-highest composition, `redis-server.service` declares
`User=redis` which resolves nowhere, while Redis's files — owned by the number
`103:104` — read as `memcache`. Both tier 1 and tier 2 previously accepted
`memcached + redis`.

This is **not repairable by a record union**: the numbers themselves disagree,
and files on disk are owned by the number, not the name.

**Prevention.** `specs/uid-ranges.yaml` gives every module a disjoint 100-wide
window starting at 2000. Before any package is installed, `02_build_delta.sh`
points **both** allocators at that window — `adduser.conf`
(`FIRST_SYSTEM_UID`/`LAST_SYSTEM_UID` and the GID pair) for `adduser --system`,
and `login.defs` (`SYS_UID_MIN`/`SYS_UID_MAX` and the GID pair) for
`useradd -r` — because maintainer scripts use both. The policy is restored to
base's bytes before squashing: it is build scaffolding, not module content.
Restored rather than deleted, since deleting a file present in the lower layer
would leave a whiteout and hide base's copy from every composition.

The file is **append-only**. An assigned range is permanent, because changing
one changes the numeric ownership already baked into a built artefact. A new
module takes the next free window; nothing is ever renumbered or reused.

**Detection stays.** `06` audits every account a module created and classifies
it as *static-reserved* (uid < 100, Debian-global, e.g. `www-data=33`),
*in-range*, or *out-of-range*; anything out of range is reported, never
silently accepted. The class-7 check in `05` remains as the guard. This is the
same relationship as class 6 and the base `full-upgrade`: **prevention is the
policy, detection is the proof that the policy held.**

Before partitioning: **6 of 351 ordinary pairs** rejected by class 7 — exactly
the C(4,2) combinations of the four colliding modules. After: **0 of 666**,
with all 14 accounts created across the catalogue landing in-range.

### Numeric uniqueness is not database composition

Disjoint windows fix the *numbers*. They do not compose the *records*, and the
10 September reassessment was right that this was claimed too broadly.

`/etc/passwd`, `/etc/group`, `/etc/shadow`, `/etc/gshadow`, `/etc/subuid` and
`/etc/subgid` are rewritten **whole** by maintainer scripts, so every
account-writing delta carries a complete copy. OverlayFS exposes only the top
layer's, which means a naive composition of `base + postgres + mysql` shows
*either* `postgres` *or* `mysql` — never both — and `User=postgres` fails to
resolve in the order where it loses. Seven catalogue modules write accounts,
so **21 pairs were affected**, all previously recorded `ACCEPT`.

They are registry files in exactly the sense class 5 already defined, and they
were simply missing from `reconcile.py`. They are now merged there: records
unioned by name, group and gshadow member lists merged rather than
overwritten, and file mode and ownership preserved — `/etc/shadow` is
`0640 root:shadow` and reconciliation must not widen it.

Verified on the real artefacts: after reconciliation `base + postgres + mysql`
contains both accounts and `ssl-cert` keeps its `postgres` member, and the
merged `passwd`, `group`, `shadow` and `gshadow` are **set-equal under the tested order reversal,
not byte-equal**. V6 checks all fields in all six account databases, membership
and subordinate-range sets, and file mode/ownership against their source layers.
Non-identity fields and file attributes follow the reconciler's highest-layer
policy; conflicting numeric identities are rejected. This does not make
arbitrary conflicting shell, password or home-directory values order-independent.

> **Record-identical, not byte-identical, and the earlier wording said
> "identical".** Measured 2026-09-18 on the real artefacts,
> `base+postgres+mysql+java+webserver` merged forward and reversed: `passwd`,
> `group`, `shadow`, `gshadow`, `subuid` and `subgid` are set-equal in every
> case and byte-equal in none, because record order follows first appearance
> and reversing the stack reorders the output. The same holds for the debconf
> databases — same 79 records, none differing in content, different order,
> different sha256. The SEMANTIC claim is what V6 tests and it holds; a
> composed system is nevertheless not byte-reproducible with respect to layer
> order, which is worth stating beside §8's reproducibility claims.

**What may be claimed:** disjoint pre-install windows eliminated the six
observed numeric collisions, and account records are now reconciled and
verified at tier 2. **What may not yet be claimed:** that a high-N set boots
with all identities working — that requires the tier-3 runs below.

**Known limitation (unresolved).** The module windows span 2000–5799, which
lies inside the 1000–60000 range `login.defs` uses for ordinary users. Nothing
in the final image reserves it, so a sufficiently long-lived node could later
assign a human account a UID already baked into module-owned files. Reserving
the span in the deployed image's allocation policy is required before this is
production-safe, and is not done.

### Untested candidates
- **Whiteouts** — a module removing a base file; changes ordering semantics
- **Alternatives** — `/var/lib/dpkg/alternatives/*` registry is per-module and
  unions badly (`vim` + `emacs-nox`). Files themselves are safe: Ubuntu already
  routes them through `/etc/alternatives` symlinks.
- **Diversions / `Replaces`** — `/var/lib/dpkg/diversions`, same union problem
- **Maintainer script side effects** — postinst appending to a shared config
- **Trigger interactions** — ldconfig, initramfs, font caches
- **Runtime resource conflicts** — two modules claiming port 80. Outside dpkg's
  model; heuristically detectable via systemd units, not statically solvable.

### Class 6 — found, diagnosed, fixed
`pytools` silently upgraded `gcc-12-base`, `libgcc-s1`, `libstdc++6`.
Chain: `python3-numpy → liblapack3 → libgfortran5 → gcc-12-base (= 12.3.0-…)`.
`libgfortran5` has an exact-equality dependency; the GCC runtime packages are
version-locked, so one transitive dependency dragged the cluster forward.
Root cause: debootstrap populates base from the plain `jammy` pocket while delta
builds see `jammy` + `-updates` + `-security`. Fix: `full-upgrade` during the
base build (moved 61 packages). Checker now reports 0 upgrades.

### Class 5 — measured, not assumed
Of ~5 000 files across two deltas: **28** appear in both, **17** byte-identical
(391 KB duplicated, harmless), **11** differ.

Those eleven are not one problem but four, and only the last needs to
understand what it is merging:

| # | Files | Treatment | Status |
|---|---|---|---|
| 5 | `/var/log/dpkg.log`, `/var/log/apt/history.log`, `/var/log/apt/term.log`, `/var/log/apt/eipp.log.xz`, `/var/cache/ldconfig/aux-cache` | **exclude** — build byproducts, never module content | **done** |
| 1 | `/etc/ld.so.cache` | **regenerate** with `ldconfig` at compose time | **done** |
| 1 | `/var/lib/dpkg/status-old` | **drop** — a backup dpkg rewrites on every run | todo |
| 4 | `/var/lib/dpkg/status`, `/var/lib/apt/extended_states`, `/var/lib/dpkg/alternatives/*`, `/var/lib/dpkg/diversions` | **semantic union** — must parse the file to merge it | **done** |

`aux-cache` is ldconfig's scratch index and stores each library's *inode
number*, so it differs between two builds whose libraries are byte-identical.
A real double build of `webserver` confirmed it was the single remaining
source of non-determinism once the logs were gone. ldconfig regenerates it, so
it does not need to ship. `/etc/ld.so.cache` is a different matter and stays:
the composed system needs it, so it is regenerated at compose time instead.

**Result: 11 → 1.** Seven of the eleven are mechanical — a path is excluded,
regenerated, or dropped, and nothing has to know what is inside it. The four
registry files are merged by `scripts/reconcile.py`, shared by `04_compose.sh`
and `07_smoke_test.sh`. One item remains: dropping `status-old`.

This is the real shape of class 5 — not "modules corrupt shared state", but
"four registries need a merge function". It is also why the class is
reconcilable at all: the count that matters is 4, not 5 000.

Two of the five are **regenerated rather than merged**, and the distinction
matters. `/etc/alternatives/*` symlinks are owned by no package: they are a
*function* of the merged registry and its priorities, so there is nothing to
union. The same holds for `/etc/ld.so.cache`. Both are recomputed by the tool
that owns them — `update-alternatives --auto` and `ldconfig` — inside the
merged chroot, rather than reimplemented.

The exclusion does not change the numbers above: `03_analyse_overlap.sh`
measures the raw `.upper` trees, where the logs still exist. What changes is
composition — `04_compose.sh` stacks `.sqsh` files, so those four can no longer
collide, because they are no longer shipped. `/var/log/apt` and `/var/log/nginx`
survive as directories; nginx needs the latter at runtime. Three of the four
logs also record wall-clock timestamps, which is why shipping them made
artefacts impossible to reproduce byte-for-byte (section 8).

`debconf/config.dat` and `templates.dat` sit outside that count. They were open
until 2026-09-18; they are now reconciled and verified by **V8**, and the
measurement that motivated it stands: **7 of 37 modules carry a debconf
database that differs from base's** — `docker`, `java`, `mta-msmtp`,
`mta-nullmailer`, `mysql`, `postgres`, `webserver` — so 21 pairs have two
diverging copies and **231 of 666 pairs have at least one**. Under last-wins
every one of those lost its debconf state. Merging recovers it, and measured
across all 39 artefact trees and all 741 tree pairs there are **zero
(Name, field) disagreements** outside `Owners`, so on this catalogue the merge
is pure recovery and nothing has to be arbitrated. The cost is real and is in
§7's slope.

> **V8 was added in round 2, and the gap it closes is instructive.** The account
> databases gained V6 on the day they were reconciled. debconf was reconciled on
> 18 September and, hours later, added to V7's RECONCILED exemption so V7 would
> stop reporting the merged copy as ALTERED — leaving the newest and
> least-tested merge in the project as the only reconciled registry with no
> verification at all. A merged `templates.dat` truncated to zero bytes passed
> every column. V8 is V6's invariant for debconf, by record.

### How do we know the registry list is complete?

We did not, until now. Each reconciled registry was found by a failure:
`status` by invisible packages, alternatives/diversions/`extended_states` by
the class-5 survey, `ld.so.cache` by measurement, the account databases by
external audit. That is discovery by accident, and a thesis should say so.

An enumeration is possible and has now been run. Take every file present in
two or more module upperdirs that is **not owned by any package** — package
ownership is already recorded in the class-4 sidecars — and the result is the
complete candidate set. Of 1 479 such files:

| Category | Count | Status |
|---|---:|---|
| already reconciled, excluded, or regenerated | 252 | handled |
| `/var/lib/dpkg/info/*` control files | ~1 200 | benign: byte-identical copies of the same package version |
| lock files (`dpkg/lock`, `archives/lock`, …) | 4 | benign: zero length |
| `debconf/*.dat` | 3 | initially open in this survey; now merged and verified by V8 |
| `/etc/apt/apt.conf.d/99modfs` | 1 | **was a leak**, now removed after build |
| `/etc/apt/sources.list` | 1 | deliberate: records the pinned generation |

This historical survey identified debconf as an unhandled registry and the
APT-policy leak as a defect. Both have since been addressed; the survey is not
a proof that every form of shared state is handled (see the trigger limitation
in §10). The method generalises:
*non-package-owned files shared by two or more modules* is a computable
definition of "registry", and it should be run whenever the catalogue grows
rather than waiting for the next failure.

Failed prediction, worth recording: `/etc/passwd` and `/etc/group` were expected
to collide. They did not — base already provides `www-data`.

Comparison is **byte-by-byte** (`cmp`), not size and not hash: faster (early
exit), exact (no collision risk), simpler.

---

## 5. Module-level dependencies

Package dependencies cannot express cross-module requirements — apt only ever
sees one module's build. A second layer is needed:

```json
{
  "module": "cuda-toolkit", "version": "12.4",
  "parent": "base", "snapshot": "20260701T000000Z",
  "requires":  [{"module": "nvidia-driver", "constraint": ">= 550"}],
  "conflicts": [{"module": "nouveau-tools"}],
  "provides":  ["gpu-compute"],
  "packages":  []
}
```

Checker verifies: every `requires` satisfied by the set at an acceptable
version, and no `conflicts` pair both present.

It does **not** reject a capability with two providers, though this document
previously said it did. Verified with a fixture: two modules each declaring
`Provides: mail-transport-agent`, neither declaring a conflict, are ACCEPTed.
Whether that is even correct is open — some capabilities are alternatives with
many valid providers and some are exclusive, and the schema records no
cardinality. Stated as unimplemented rather than described as working.

Checks in `05_check.sh` are numbered by these classes — `CLASS 3`, `CLASS 4`
and so on — rather than in the order they happen to run, so output maps onto
the table above directly. Class 5 has no check: it always occurs, and is
answered by reconciliation rather than rejection.

These fields are now **enforced** by `05_check.sh`: each `requires` must be
satisfied by a module in the set whose name or `provides` matches, at a version
meeting the constraint; each `conflicts` must match nothing in the set. This
closes audit finding M5, which observed that the schema had carried these
fields for weeks without any check reading them.

**Verification only, never search.** Full installability in Debian-style systems
is NP-complete (Di Cosmo et al., EDOS/Mancoosi). apt resolves once at build
time when the problem is small; composition afterwards is linear checking.

Modules therefore need **explicit version numbers**, not implicit
`(snapshot, parent)` identity. `01`/`02` take `--version` and forward it.

The example above is the hand-written half. `06_extract_metadata.sh` writes the
generated half into the same file: `snapshot`, `suite`, `arch`, `built`,
`artifact` (`.sqsh` size + sha256), `requested`, `removed`, and a `packages`
map carrying each package's version plus all six dpkg relations — `Depends`,
`Pre-Depends`, `Conflicts`, `Breaks`, `Replaces`, `Provides` — as raw dpkg
strings. Only the module's **contribution** is stored (packages whose version
differs from the parent's); consumers rebuild the merged view as
`base.packages ∪ m.packages − m.removed`. Re-running the extractor preserves
hand-written `requires`/`conflicts`/`provides`.

This is what decouples tier 1 from the build tree: `base.sqsh` + `base.json`
is everything a consistency check needs, so the chroots become disposable
scratch and `05_check.sh` no longer requires root.

> **And until 2026-09-18 the manifest was derived from the build tree it claims
> to have replaced.** `06` read `<name>.upper`, so every content field described
> the scratch chroot while `artifact.sha256` beside it described bytes nobody
> read. Measured across all 39 artefacts, the difference is exactly
> `SQUASH_EXCLUDES`: `curl.json` recorded file owner uid 100 (`_apt`) when *no
> file in curl.sqsh is owned by 100* — the apt caches and build logs that carry
> that ownership are excluded from the artefact. `status`, `passwd`, `group`,
> `shadow` and `gshadow` were byte-identical between the two, so `packages`,
> `removed` and `accounts` were right; `file_uids`/`file_gids` were a statement
> about scratch, and they are what class 7's numeric-ownership check reads.
>
> `06` now mounts the artefact — and the parent's artefact, since `removed` and
> every package's origin are computed against it — and records
> `binding.source`. Regenerating all 39 manifests changed `file_uids` in 39 and
> `file_gids` in 35 and nothing else, and re-running the 703-pair tier-1 sweep
> moved no column in any row.
>
> **Binding.** `binding.fields_sha256` is a canonical digest over exactly the
> mandatory fields the checks read (the consumer requires the complete
> BIND_FIELDS set, rather than trusting an arbitrary `binding.fields` list).
> `binding.sidecar_sha256` covers the uncompressed class-4 sidecar; a missing
> digest is rejected. `05_check.sh` and `verify_bundle` recompute it. Earlier
> digest-only timings predate mandatory sidecar consumption checks and are not
> a timing claim for the corrected code. `12_verify_binding.sh` re-derives
> metadata from the artefact's filesystem contents and compares it; byte hashing
> alone cannot catch a manifest resealed to match forged metadata.
>
> It is **integrity, not authenticity**: the digest lives in the document it
> protects, exactly as `artifact.sha256` always has. What it closes is drift,
> partial refreshes and quiet omission — and omission was the live attack:
> deleting `file_uids` from one manifest turned a class-7 REJECT into a clean
> ACCEPT with no warning. Authenticity needs a key outside the artefact set and
> stays out of scope.

---

## 6. Evaluation methodology

Exhaustive validation is infeasible: jammy has ~65 000 binary packages, so pairs
alone are ~2×10⁹. Three tiers exploit the cost asymmetry:

The following are historical measurements made before the independent-review
corrections. The tier-2 row uses the 18 September round-2 generation shown in
§7; the tier-1 and tier-3 rows are separate measurements, not a matched timing
experiment. They must not be divided to claim a precise cross-tier ratio.

| Tier | Operation | Historical cost (N=2 → N=36) | Scope |
|---|---|---|---|
| 1 | Metadata check | **89 ms → 398 ms** | 152 sequential sets, before correction H1 |
| 2 | Compose only | **203 ms → 1090 ms** | round-2 table in §7, 152 compositions; verification excluded |
| 3 | QEMU boot test | **189–204 s** | two N=36 runs; not a catalogue-wide boot census |

`total_ms` in the tier-2 CSV equals `mount_ms + reconcile_ms` on every row.
Neither verification nor the preceding integrity/admission checks are included.
The earlier **181–808 ms** table described a pre-debconf generation; it cannot
be combined with the later **148 + 27.2 N** fit or labelled “Compose + verify”.
The former 2× and 230–250× comparisons mixed generations and omitted verification;
they are withdrawn. A matched full-pipeline timing experiment is still needed.

For provenance, the post-debconf pre-round2 CSV is retained at
`/srv/modfs/results/tier2/compose-sweep-2026-09-18-pre-round2.csv` and yields
`148.285629 + 27.200303 N`. The round-2 CSV is preserved at
`/srv/modfs/results/review-fixes-2026-09-18-before/compose-sweep.csv`
(SHA256 `b383725ee699bde86ebeaba74ec344694e7e6e383233a772c3c17cf197fe64df`)
and yields `160.696749 + 27.013002 N`. These are two measured composition-only
fits, not competing fits to one dataset. New correction-run measurements are
reported separately in JOURNAL.md rather than silently replacing these values.

Tier 1's old flat 28 ms figure was eight-worker throughput, not single-call
latency. Its historical sequential fit was `101 + 9.6 N` over 152 sets.
Mandatory sidecar verification added by correction H1 changes the work measured;
that historical fit is not a performance claim about the corrected checker.

**Admission order is a rule, not a convention:**

    manifest binding -> bundle integrity -> tier-1 admission
                     -> compose/reconcile -> tier-2/3 verification

Tier 2 previously composed a tier-1-rejected set and labelled it `PASS`, and
tier-3 Run A bypassed admission entirely and died inside APT. Stages `10` and
`11` now verify each artefact against the digest in its own manifest, then run
tier-1 admission, and refuse to compose a rejected set. A deliberate negative
requires `--known-negative`, which records the expected rejection and reports
`KNOWN_NEGATIVE` — never `admitted` or `verified`.

Build 30–40 small modules once; check all pairs and triples exhaustively;
compose a stratified sample; boot-test the interesting cases. Tier 1 is
`09_run_combinations.sh`; tier 2 is `10_compose_sweep.sh`, which samples
152 sets — 30 pairs, 30 triples, 20 at N=5, 10 each at N=10, 15, 20, 25, 27
and 30, then 6, 4 and 2 at N=33, 35 and 36, where the admissible space runs
out — and verifies each composed system against its own layers rather than
against metadata. Sampling is seeded, so the sample set is reproducible.
Module selection is **adversarial** — chosen to provoke classes — not
representative.

**The sample must be drawn against the constraints, not filtered by them.**
Sampling was uniform over N-subsets until 2026-09-17, which works only while
almost every draw happens to be admissible. It does not survive scale: of all
uniform N-subsets of the 37 usable modules, 94.6 % are admissible at N=2,
38.1 % at N=27 and 5.4 % at N=36, because a large random subset almost always
sweeps up both mail-transport agents. The plan then allocated its *fewest*
samples where acceptance was *lowest* — one draw at N=27 — so the top of the
cost-vs-N curve had a 0.62 probability of coming out empty, and did.
`sample_sets.py` now draws sets that satisfy the constraint model by
construction. Two properties of it matter:

- **Exclusions are measured, not declared.** The model learns them from a real
  tier-1 pair sweep, because the one exclusion this catalogue has is expressed
  only through a virtual package name and appears in no module manifest.
- **A rejected pair is not automatically an exclusion.** `fake-cuda` is
  rejected against 35 of 36 siblings and still belongs in the largest admitted
  set, because the driver it requires is in there too. Requirements (§5)
  *explain* 35 of the 36 rejections; only the unexplained residue becomes an
  edge. Conflating the two would have banished `fake-cuda` from every high-N
  sample — the same error the `--maximal-subset` search made and corrected.

The model only **proposes**. Tier-1 admission still runs on every set before
anything is mounted, so a set the model gets wrong is recorded `NOT_ADMITTED`,
never composed on the model's word. In the 2026-09-17 run the two agreed on
all 152 sets.

The catalogue is `specs/modules.yaml`: 38 modules — 37 usable plus the
positive control — each carrying the class it exists to provoke and a `probe`
command that must exit 0 inside a composed chroot. 37 usable modules is 666
pairs and 7 770 triples. Tier 1 needs no root and no build tree — only the
manifests — so the whole sweep parallelises freely.

**The catalogue cannot be composed whole, by construction.** It contains a
deliberate conflict pair, so the largest admissible set is **36 of 37**
modules and there are exactly **two** such sets. N=37 is not a gap in the
evidence; it is infeasible, and the sampler reports it as such rather than
drawing sets that tier 1 will refuse.

Baseline: monolithic, one image per use case.

---

## 7. Current results

| Artefact | Compressed | Packages |
|---|---|---|
| `base.sqsh` | 40 MB | 113 |
| `webserver.sqsh` | 21 MB | +42 |
| `pytools.sqsh` | 25 MB | +24 |
| **stored** | **86 MB** | |

86 MB expresses four bootable configurations. Monolithic ≈ 252 MB (estimate;
comparison build not yet run) → ~2.9×, growing per module.

> **Superseded — see "Storage depends on the catalogue" below.** The figures
> in this subsection describe the original 28-module catalogue of small
> adversarial modules. Adding seven realistic modules changed the headline
> ratio from 5.35× to 2.51×, and that change is itself the result.

**Original catalogue, 28 modules** (small adversarial modules only), built in
~6 minutes:

| | |
|---|---|
| base | 41.7 MB |
| 28 deltas | 215.0 MB |
| **stored total** | **256.7 MB** |
| monolithic equivalent | 1 373.9 MB |
| **ratio** | **5.35×** |

Median delta 1.6 MB; 11 are under 1 MB; the largest is `emacs-nox` at 37 MB.
The ratio grows with module count as predicted — 2.9× at three modules, 5.35×
at twenty-eight — because the base is paid for once.

The monolithic figure is an extrapolation, but a **calibrated** one.
`02_build_delta.sh --compare` built six real monolithic images spanning two
orders of magnitude of delta size, and the extrapolation `base + delta` was
accurate to under 1 % on every one:

| Module | Delta | Monolithic (measured) | Extrapolated | Error | Delta ratio |
|---|---|---|---|---|---|
| `nc-traditional` | 0.3 MB | 41.6 MB | 42.0 MB | +0.9 % | 161× |
| `jq` | 0.6 MB | 41.9 MB | 42.3 MB | +0.9 % | 75× |
| `curl` | 1.6 MB | 43.0 MB | 43.4 MB | +0.9 % | 26× |
| `webserver` | 21.0 MB | 62.3 MB | 62.8 MB | +0.8 % | 3.0× |
| `pytools` | 25.8 MB | 67.4 MB | 67.6 MB | +0.2 % | 2.6× |
| `emacs` | 37.0 MB | 78.3 MB | 78.7 MB | +0.5 % | 2.1× |

The extrapolation is consistently *high* by about 0.7 %, because a monolithic
build compresses base and module together and finds a little cross-file
redundancy that separate compression cannot. Applying that calibration gives
the 1 373.9 MB above. Per-module saving ranges from **53 %** (`emacs-nox`, a
large module against a 41.7 MB base) to **over 99 %** (`nc-traditional`, a
252 KB delta) — the thinner the module, the more the delta model wins.

Composition, base + webserver + pytools:

```
naive:      137 listed / 178 real   → 41 invisible; dpkg says nginx NOT INSTALLED
reconciled: 178 listed / 178 real   → 0 invisible; nginx INSTALLED
```

Tested reversals preserve record contents for the measured account, debconf,
dpkg-status and extended-state examples; record order and file bytes differ.
No general order-independence guarantee follows: non-identity account fields
use highest-layer precedence, and these examples do not cover all permutations.

**Historical reproducibility sample — 2026-08-22.** JOURNAL.md records two full
builds of each of these three modules on one host with identical hashes. These
are not hashes of the current artefacts and do not establish reproducibility
of every subsequent catalogue generation:

| Module | sha256 (first 16) |
|---|---|
| `base.sqsh` | `06e105365b3c48d1` |
| `webserver.sqsh` | `f918ba2c892ea642` |
| `pytools.sqsh` | `eff7dbd83fe9710d` |

`webserver.sqsh` is additionally unchanged across a full base rebuild, so a
delta no longer depends on the lower filesystem's identity. Getting there took
four distinct fixes, none of them about package content: pinned `mkfs`/file
timestamps, excluded build logs and `aux-cache`, stripped overlayfs
`uuid`/`origin` xattrs, and an emptied `/etc/machine-id`. Cross-host
reproducibility is now plausible but **untested**.

### Storage depends on the catalogue, not only on the method

Re-measured on 2026-09-16 against a **fully rebuilt catalogue** — base and all
38 modules rebuilt on the same day from the same snapshot, and the six
monolithic baselines rebuilt alongside them, so both halves of the comparison
come from one system. The earlier table mixed Sep 16 deltas with Aug 31
monoliths and is superseded:

| Cohort | N | Stored | Monolithic | Ratio |
|---|---:|---:|---:|---:|
| small adversarial modules | 31 | 272.8 MB | 1 524.3 MB | **5.59×** |
| large realistic modules | 7 | 792.8 MB | 1 043.1 MB | **1.32×** |
| whole catalogue | 38 | 1 023.8 MB | 2 567.4 MB | **2.51×** |

The ratio is

    (N·B + Σd) / (B + Σd)

so it tends to N as deltas shrink and to 1 as they grow. With B = 41.7 MB, a
mean delta of 7.5 MB gives 5.59×; a mean delta of 107.3 MB gives 1.32×. The
seven large modules are 78 % of all delta bytes and return almost nothing.

The monolithic column is MODELLED as `B + d`, and the six rebuilt monolithic
artefacts let that model be checked rather than assumed. Measured monolithic
sizes come in **0.2–0.9 % below** the model across all six, because squashfs
compresses one whole tree slightly better than a base and a delta compressed
separately. The model therefore mildly OVERSTATES the saving, by under 1 %:

| | curl | jq | nc-traditional | webserver | pytools | emacs |
|---|---:|---:|---:|---:|---:|---:|
| measured | 43.0 | 41.9 | 41.6 | 62.3 | 67.4 | 78.3 |
| modelled | 43.4 | 42.3 | 42.0 | 62.8 | 67.6 | 78.7 |

**This is the honest form of the storage claim.** The earlier 5.35× was a
property of a catalogue deliberately built from tiny modules, not a property
of sibling deltas. The method's benefit is `B·(N−1)/(B+Σd)`: it pays when many
modules share a large base, and approaches zero when modules are large and
independent.

That is not a refutation — it is the operating envelope, and it points at a
design parameter the project already names. §2 says "Base may be fat; larger
base ⇒ smaller deltas", yet the built base is `minbase` plus four packages.
Among the seven large modules, **53 packages appear in two or more** and 32 in
three or more (`gcc`+`rust` share 31, `gcc`+`llvm` 24, `llvm`+`rust` 23).
Moving that shared toolchain into the base would shrink every large delta and
raise the ratio. A larger-base experiment was recorded on 2026-09-17 in
`/srv/modfs/results/fatbase/fatbase-analysis-2026-09-17T163305Z.txt` and its
per-module CSV. The independent review inspected those retained results but
did not rebuild that generation. Its existence must not be described as an
unrun experiment; its ratios also need their own baseline definition.

One framing correction that follows: `11_boot_test.sh` flattens the composed
overlay into an ext4 root, so a provisioned node receives a conventional
image. The saving is **server-side storage and assembly**, not a node-side
filesystem. On-node overlay composition is listed out of scope in §11, and the
storage figures should be read accordingly.

**Combination sweep**, all 378 pairs of the 28-module catalogue, 9 s at
`--jobs 8`:

| | |
|---|---|
| ACCEPT | 350 |
| REJECT | 28 |
| class 1 benign overlap | 60 |
| class 2 version skew | 5 |
| class 3 declared conflict | 1 |
| class 4 file collision | 0 (4 suppressed by `Replaces`) |
| class 6 implicit base upgrade | 0 |
| precondition failure | 27 |

Twenty-seven of the rejections are the positive control, which is built from a
different snapshot and *must* be rejected against every sibling; the sweep is
self-validating, and an all-ACCEPT result would now mean the sweep itself is
broken. The twenty-eighth is `mta-msmtp` + `mta-nullmailer`, a real declared
conflict expressed only through the virtual name `mail-transport-agent`.

Zero version skew and zero base drift among the 27 well-formed modules is the
central result: snapshot pinning and the base `full-upgrade` hold across 351
sibling pairs, not just the three originally measured.

**All 351 ordinary pairs were physically composed and passed every structural
check**, in 58.8 s total (median 163 ms each): dpkg status the exact union of
the layers, no alternatives group short a candidate, `/etc/ld.so.cache`
*exactly* the union in all 351, `dpkg --audit` clean throughout.

The admission wording matters, and the earlier phrasing was wrong. That sweep
**bypassed tier-1 admission**: it composed every pair regardless of verdict. Of
the 351, tier 1 as it then stood admitted **350 and rejected 1** — the
`mta-msmtp + mta-nullmailer` virtual-conflict pair, which was composed anyway
and reported `PASS`. Structural success is not package-semantic success, and
that single row is the proof.

Under the checks as they now stand, class 7 rejects a further 6 pairs, so the
same space is **344 admitted, 7 rejected**. Stage `10` no longer composes a
rejected set without `--known-negative`, and labels such runs
`KNOWN_NEGATIVE`.

Above N=2 the coverage is a stratified sample. The 2026-09-18 round-2 run used a
constraint-aware sampler (§6): **152 real compositions from N=2 to N=36, 152
passed, 0 failed, 0 refused**. Every composed system's dpkg status was the
exact union of its layers, every alternatives group held every candidate any
layer offered, `/etc/ld.so.cache` was exactly the union in all 152, `dpkg
--audit` was clean throughout, and no layer's files were invisible in the
merged view (V7).

| N | samples | packages | alt groups | debconf records | mount ms | reconcile ms | total ms |
|---|---|---|---|---|---|---|---|
| 2 | 30 | 119–184 | 5–46 | 90–148 | 33 | 169 | 203 |
| 3 | 30 | 120–223 | 5–44 | 90–162 | 44 | 193 | 235 |
| 5 | 20 | 137–203 | 5–48 | 90–122 | 56 | 219 | 278 |
| 10 | 10 | 163–247 | 8–24 | 90–160 | 91 | 293 | 392 |
| 15 | 10 | 217–311 | 12–59 | 106–172 | 133 | 425 | 576 |
| 20 | 10 | 290–317 | 15–61 | 110–174 | 175 | 494 | 680 |
| 25 | 10 | 267–344 | 28–68 | 112–172 | 217 | 628 | 859 |
| 27 | 10 | 328–360 | 28–67 | 112–174 | 211 | 664 | 872 |
| 30 | 10 | 330–382 | 60–67 | 118–174 | 264 | 734 | 1000 |
| 33 | 6 | 359–382 | 59–68 | 166–174 | 285 | 753 | 1050 |
| 35 | 4 | 371–391 | 68 | 168–174 | 300 | 780 | 1080 |
| 36 | 2 | 384–391 | 68 | 168–174 | 309 | 781 | 1090 |

> **This table is re-measured 2026-09-18 (round 2) and replaces one that was
> stale in two independent ways.**
>
> **The timings predated the debconf merge.** The version above it ended
> `36 | 2 | 387 | ... | 254 | 554 | 808`, which is inconsistent with the cost
> model printed a few paragraphs earlier in the same section: `148 + 27.2 N`
> gives 1 127 ms at N=36, not 808. The model was updated when debconf
> reconciliation landed and the table was not. The fresh measurement, 152
> compositions over the same plan, gives **`total = 160.7 + 27.01 ms × N`
> (R² = 0.970)** — the slope reproduces the published 27.2 almost exactly, so
> the 18 September re-fit was right and only its table was left behind.
> `mount = 18.9 + 8.03 N` (R² = 0.972), `reconcile = 141.8 + 18.98 N`
> (R² = 0.953), and `total_ms − mount_ms − reconcile_ms` is 0 on all 152 rows,
> so this is still the cost of COMPOSING and not of verifying.
>
> **The "alt groups" column was measuring /etc/gshadow.** `verify_compose.py`
> built V3's expectation in a variable called `want`, and both V6's loop
> variable and a local inside V7 rebound it before the CSV line was printed, so
> the column carried the gshadow record count. Confirmed against the old CSV's
> own sample 1, `base nc-traditional rust`: it published 42, the true count is
> **10** (5 base + 1 nc-traditional + 4 rust), and the union of `/etc/gshadow`
> across those layers is 42. The old column's smooth 42→50 progression was
> itself the evidence that something was wrong and read as reassurance instead:
> the true count depends on WHICH modules are in the set, not how many, so it
> ranges 5–46 at N=2. `java` alone carries 33 alternatives groups; `tmux`
> carries none. Verified independently at both extremes — the union for
> `base java vim` is 46 and for `base mysql tmux` is 6, exactly what the
> corrected column now reports.
>
> `alt_groups_bad` was computed before the rebinding and was never affected, so
> "no alternatives group was short a candidate in 152/152" stands unchanged.
>
> The "cache libs" column is replaced by **debconf records**, the new V8 count
> (below). `ld_ok` is still checked and still clean in all 152.

**This table replaces one whose top row was a fossil.** The previous version
ended `27 | 1 | 281 | 23 | 205 | 622`, measured on 2026-09-02 when the
catalogue held exactly 27 usable modules — so "the single N=27" was not a
sample at all but a **census of the whole catalogue**, one deterministic set.
The catalogue then grew to 37 usable modules and that plan point silently
became a one-draw random sample of 27-of-37, with a 0.62 probability of being
refused. In the last run before this one it was refused, and the row read
zero. The old 622 ms figure describes a 27-module catalogue that no longer
exists, not a 27-module *composition* in the round-2 table above, which reports 872 ms.

The union grows sub-linearly in N because modules share dependencies, and the
arithmetic cross-check holds at the top of the range as it did at N=27: the 36
modules of sample 151 contribute **527 package instances that collapse to 278
distinct** new packages, a sharing factor of **1.90**, and the composed system
holds **391 packages — exactly base's 113 plus those 278**, reproduced from the
artefacts alone. The composition and the manifest arithmetic agree from two
independent measurements at the largest set the catalogue admits.

**The cost model, re-measured.** Keep the measurement generations separate:
2026-09-02's 96-composition model was `115 + 18.8 N`; the post-debconf
pre-round2 152-composition model was `148 + 27.2 N`. The round-2 table above
and its preserved CSV (§6) instead have this internally consistent split:

    total     = 160.7 ms + 27.01 ms × N     (R² = 0.970)
    mount     =  18.9 ms +  8.03 ms × N     (R² = 0.972)
    reconcile = 141.8 ms + 18.98 ms × N     (R² = 0.953)

The rounded component fits sum to the rounded total fit. The former split
with slope 6.7 + 13.2 = 19.9 belonged to a pre-debconf generation; the former
“18.8 → 19.9, +6%” comparison did too. Neither supports the 27.2 slope.
Reconciliation accounts for about 70% of the round-2 per-module slope.
These coefficients describe composition, not verification or full tier-2 latency.

The fit describes an average over sampled sets, not an individual composition.
At N=36 there are only two admissible sets, differing by one module; high-N
samples overlap heavily. Their spread is not evidence of independent workload
draws or a universal latency bound. The correction-run fits and any changes
in counters are recorded separately in JOURNAL.md.

---

## 8. Pipeline

| Script | Role |
|---|---|
| `00_verify.sh` | Assumption checks: tools, kernel, snapshot, whiteout round trip |
| `01_build_base.sh` | debootstrap + full-upgrade + core packages → `base.sqsh` |
| `02_build_delta.sh` | Overlay parent, install into merged view, squash upperdir |
| `03_analyse_overlap.sh` | Byte-compare files shared by two deltas (research tool, run once) |
| `04_compose.sh` | Stack modules; demonstrate defect; write reconciled state layer |
| `05_check.sh` | Metadata-only consistency check over `module.json` → ACCEPT/REJECT |
| `06_extract_metadata.sh` | Mount `<name>.sqsh` read-only and write `<name>.json` beside it, plus `<name>.files.json.zst` mapping every owned path to its package (class 4). Records the assigned UID window, audits every account against it, and seals the result with `binding.fields_sha256`. `--check` re-derives and compares instead of writing |
| `07_smoke_test.sh` | Compose a set, chroot in, and check it actually works: `dpkg --audit`, `apt-get -s install`, `ldconfig -p`, per-module probes |
| `08_build_catalogue.sh` | Batch-build every module in `specs/modules.yaml`; reports sizes against `MODULE_MAX_MB` |
| `09_run_combinations.sh` | Tier 1: run `05_check.sh` over all pairs and triples; tabulate verdicts by conflict class into a CSV |
| `10_compose_sweep.sh` | Tier 2: compose admitted sets from N=2 to N=36 and verify status, alternatives, linker cache and dpkg state against the layers |
| `11_boot_test.sh` | Tier 3: pack a UEFI image, boot it under QEMU, and record a per-unit causal matrix from inside the running system |
| `12_verify_binding.sh` | Re-derive every manifest from its artefact and compare. Run once per catalogue, not per check: 12.5 s for all 39 |
| `reconcile.py`, `verify_compose.py` | Shared helpers: class-5 registry merge; per-composition verification |

`specs/uid-ranges.yaml` holds the append-only UID/GID partition.
`config.sh` holds snapshot ID, suite, paths, compression.
`lib.sh` holds logging, mount tracking with guaranteed teardown, chroot helpers.

Build-time hygiene, all learned the hard way: `--variant=minbase`; bind all four
of `/proc`, `/sys`, `/dev`, `/dev/pts`; `policy-rc.d` to stop daemons starting in
chroot; stamp file written **last** so interrupted builds aren't mistaken for
complete; zstd not xz; `-mkfs-time`/`-all-time` pinned to `SOURCE_EPOCH`
(derived in `config.sh` from `SNAPSHOT_ID`), the apt/dpkg logs and
`aux-cache` excluded, overlayfs's own `trusted.overlay.uuid`/`origin` stripped
via `-xattrs-exclude`, and `/etc/machine-id` emptied at the end of the base
build, so artefact bytes do not move with the wall clock or the host.

Emptying `/etc/machine-id` is not only a reproducibility fix. `systemd-machine-id-setup`
writes a random id at install time, and a baked-in id would give every node
flashed from the image the same identity. An empty file is systemd's
documented first-boot signal: each node generates its own. Reproducibility and
correct node identity happen to require the same thing.

---

## 9. Tier-3 status

The initial two tier-3 attempts are described here; only one booted.
The later causal matrix below contains four further runs, not a two-run census.

**Run A** — 26 modules — **did not boot.** It failed during the pre-boot kernel
transaction with `Unmet dependencies`, because the set contained the
tier-1-rejected `mta-msmtp + mta-nullmailer` pair and admission was never
consulted. It is evidence for the admission-gating defect, not a boot result.
The set is also rejected by class 7, since it contains all four
UID-103 modules.

**Run B** — `base + webserver + apache` — is **one successful UEFI/systemd
boot** in which the expected service failure occurred: nginx started, Apache
did not, `multi-user.target` was reached, `dpkg --audit` and both
configuration probes passed, and the guest powered off cleanly. The port-80
explanation was an inference; it has since been replaced by direct evidence.

### The causal boot matrix

Four gated runs, each an admitted set, each an immutable bundle under
`$RESULTS_DIR/boot/`:

| Run | Set | systemd | nginx | apache2 | Port 80 owner |
|---|---|---|---|---|---|
| m1 | `base webserver` | running | active | — | nginx |
| m2 | `base apache` | running | — | active | apache2 |
| m3 | `base webserver apache` | degraded | active | **failed** | nginx |
| m4 | `base apache webserver` | degraded | active | **failed** | nginx |

The cause is now recorded rather than inferred. From `journal.txt`:

```
(98)Address already in use: AH00072: could not bind to address 0.0.0.0:80
(98)Address already in use: AH00072: could not bind to address [::]:80
no listening sockets available, shutting down
```

and `listeners.txt` shows nginx holding both `0.0.0.0:80` and `[::]:80`.

Each service binds successfully when it is alone, and they do it differently:
nginx opens two sockets (`0.0.0.0:80` and `[::]:80`), Apache one dual-stack
wildcard (`*:80`). Either is valid; they are simply incompatible with each
other on one host.

**The order reversal is the informative part.** m3 and m4 stack the two
modules in opposite orders and produce the *same* outcome: Apache fails in
both. **Layer priority does not decide port ownership.** OverlayFS precedence
governs which file wins; it has no bearing on which process reaches `bind()`
first. That is a startup race between two units systemd has no ordering
constraint between, and the composition model cannot influence it.

Two samples do not establish that nginx *always* wins — only that the layer
order did not change it. The mechanism is a race, and it should be described
as one.

Each run alone is green: the conflict exists only in the union, is invisible
to every static tier, and — importantly — **both configuration probes pass in
the failing runs**. `apache2ctl configtest` reports valid syntax while the
service cannot start. Configuration validity is not service health, and that
distinction is what tier 3 buys.

Nothing here licenses "tier 3 passes". The defensible claim is: *four composed
sets booted under UEFI; two single-service sets reached a running state, and
both two-service sets reproduced a runtime-negative interaction whose cause is
recorded.*

## 10. Future Work

Carried from the external audit of 3 September 2026 (`docs/ASSESSMENT.md`),
deliberately **not** implemented in this cycle. Listed so the boundary between
what is verified and what is merely intended stays explicit.

**High severity**

| | |
|---|---|
| H1 | ~~Artifact, manifest, sidecar and parent generation are not cryptographically bound at consumption time~~ — **narrowed 2026-09-18**: the manifest is derived from the mounted artefact, the fields the checks read are covered by `binding.fields_sha256` and the sidecar by `binding.sidecar_sha256`, both verified at tier 1 and by `verify_bundle`, and `12_verify_binding.sh` re-derives from the artefact. What remains is AUTHENTICITY — the digests sit inside the document they protect, so a signing key outside the artefact set is still required, and is still out of scope |
| H2 | Publication is only partly atomic and can mix generations |
| H3 | Class-4 `Replaces` suppression does not implement Debian's file-overwrite semantics |
| H4 | Class-4 inventory covers only part of filesystem semantics |
| H5 | ~~Class 5 is not closed: debconf and dpkg trigger registrations still last-win~~ — **partly done**: debconf is reconciled (§4) and verified by **V8**. dpkg trigger registrations are still last-win |
| H6 | Removal, whiteout and opaque-directory composition are effectively untested |
| H7 | Reconciler conflict handling is incomplete and sometimes order-dependent |
| H8 | Tier-2 verification is materially weaker than its documentation says — narrowed by V7 v2 and V8; the residue is now specific: V7 compares regular-file `(kind, size)` and symlink targets, not regular-file content (§3), and the published cost model covers composition only, not verification |
| H9 | The monolithic comparison path is not a controlled equivalent baseline |
| H10 | Signal cleanup can tear down resources and then continue execution |
| H11 | The tier-1 sweep can report success when workers or output accounting fail |
| H12 | Privileged composition executes artifact-controlled code on the host side of the VM boundary |

**Medium severity**

| | |
|---|---|
| M1 | Stage `07` can finish successfully after partial harness failure |
| M2 | `03_analyse_overlap.sh` overstates what byte-identical regular files prove |
| M3 | Reproducibility normalization can affect semantics |
| M4 | Architecture and multiarch handling is intentionally narrow but should be explicit |
| ~~M5~~ | ~~Module-level dependency declarations exist in schema but are not enforced~~ — **done**: enforced in `05_check.sh` |
| M6 | Names, CSV and TSV formats assume trusted simple tokens |
| M7 | Documentation and status drift are material |

Also deferred: the class-7 *repair* path — deterministic global UID/GID
allocation, or creating identities at image construction and remapping every
affected inode. Stage `05` detects and rejects only.

## 11. Plan

| Week | Dates | Work |
|---|---|---|
| 1 | 6–12 Aug | `module.json`; module catalogue + batch build; finish reconciliation |
| 2 | 13–19 Aug | Combination harness: 30–40 modules, all pairs/triples, auto-classify |
| 3 | 20–26 Aug | QEMU boot verification; module-level deps (fake modules); update manager |
| 4 | 27 Aug–2 Sep | Collect all measurements; monolithic baseline; **freeze 2 Sep** |
| 5–7 | 3–23 Sep | Writing |
| 8 | 24–29 Sep | Buffer, formatting, submission |

Related Work can be drafted during weeks 1–4; it doesn't depend on the code.

### Out of scope
BAAS Go integration (endpoint mapping table only) · on-node boot composition ·
bulk CUDA testing (machinery on fake modules; one real demo if time) ·
real hardware · multi-distro · any dependency solver of our own.

---

## 12. Open questions
- dpkg trigger registrations: reconcile or retain the stated limitation?
- Runtime conflicts: implement the systemd/port heuristic, or document only?
- How many generations of artefacts to retain, given no rollback requirement?
