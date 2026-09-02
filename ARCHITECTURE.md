# ARCHITECTURE

Modular, updatable filesystem for Bare Metal as a Service.
BSc thesis. Submission **29 September 2026**. Code freeze **2 September 2026**.

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

`debconf/config.dat` and `templates.dat` sit outside this count and remain
open — union, or documented limitation.

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
version; no `conflicts` pair both present; no capability with two providers.

Checks in `05_check.sh` are numbered by these classes — `CLASS 3`, `CLASS 4`
and so on — rather than in the order they happen to run, so output maps onto
the table above directly. Class 5 has no check: it always occurs, and is
answered by reconciliation rather than rejection.

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

---

## 6. Evaluation methodology

Exhaustive validation is infeasible: jammy has ~65 000 binary packages, so pairs
alone are ~2×10⁹. Three tiers exploit the cost asymmetry:

| Tier | Operation | Cost | Feasible |
|---|---|---|---|
| 1 | Metadata check | ~1 s | thousands |
| 2 | Actual composition | ~10 s | hundreds |
| 3 | QEMU boot test | ~60 s | tens |

Build 30–40 small modules once; check all pairs and triples exhaustively;
compose a stratified sample; boot-test the interesting cases. Module selection
is **adversarial** — chosen to provoke classes — not representative.

The catalogue is `specs/modules.yaml`: 27 modules, each carrying the class it
exists to provoke and a `probe` command that must exit 0 inside a composed
chroot. 27 modules is 351 pairs and 2 925 triples. Tier 1 needs no root and no
build tree — only the manifests — so the whole sweep parallelises freely.

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

**Full catalogue, 28 modules** (`specs/modules.yaml`, including one
deliberately-broken positive control), built in ~6 minutes:

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

Reconciliation also makes composition **order-independent**.

**Artefacts are byte-reproducible.** Two full builds of each module, on one
host, produce identical `sha256`:

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
| `06_extract_metadata.sh` | Write `<name>.json` beside each artefact, plus `<name>.files.json.zst` mapping every owned path to its package (class 4) |
| `07_smoke_test.sh` | Compose a set, chroot in, and check it actually works: `dpkg --audit`, `apt-get -s install`, `ldconfig -p`, per-module probes |
| `08_build_catalogue.sh` | Batch-build every module in `specs/modules.yaml`; reports sizes against `MODULE_MAX_MB` |
| `09_run_combinations.sh` | Run `05_check.sh` over all pairs and triples; tabulate verdicts by conflict class into a CSV |

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

## 9. Plan

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

## 10. Open questions
- debconf: reconcile or document as limitation?
- Runtime conflicts: implement the systemd/port heuristic, or document only?
- How many generations of artefacts to retain, given no rollback requirement?
