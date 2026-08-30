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
remounted as a lowerdir. **30 checks, 30 passed.**

---

## 4. Conflict taxonomy

| # | Class | Cause | Detection | Policy |
|---|---|---|---|---|
| 1 | Benign overlap | Same package, same version, two siblings | Version match in union | Accept; measure duplication |
| 2 | Version skew | Different snapshots, parents, or explicit pins | Version mismatch | Reject |
| 3 | Declared conflict | `Conflicts:` / `Breaks:` | Match declarations vs union | Reject |
| 4 | File collision | Different packages own the same path | Intersect `dpkg/info/*.list`; honour `Replaces:` | Warn/reject — **not implemented** |
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

| Files | Treatment | Status |
|---|---|---|
| `/var/lib/dpkg/status` | union | **done** |
| `/var/lib/apt/extended_states` | union | todo |
| `/etc/ld.so.cache`, `/var/cache/ldconfig/aux-cache` | regenerate (`ldconfig`) | todo |
| `/var/lib/dpkg/alternatives/*`, `/etc/alternatives/*` | union | todo |
| `/var/lib/dpkg/diversions` | union | todo |
| `debconf/config.dat`, `templates.dat` | union or documented limitation | open |
| `/var/lib/dpkg/status-old` | drop (backup) | todo |
| 4 × `/var/log/*` | concatenate or drop | todo |

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

Composition, base + webserver + pytools:

```
naive:      137 listed / 178 real   → 41 invisible; dpkg says nginx NOT INSTALLED
reconciled: 178 listed / 178 real   → 0 invisible; nginx INSTALLED
```

Reconciliation also makes composition **order-independent**.

Checker on the current set: `0 errors, 0 warnings — ACCEPT`.
Verified to reject synthetic version skew and declared conflicts.

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
| `06_extract_metadata.sh` | Write `<name>.json` beside each artefact: identity, requested packages, full dpkg relations for every contributed package |

`config.sh` holds snapshot ID, suite, paths, compression.
`lib.sh` holds logging, mount tracking with guaranteed teardown, chroot helpers.

Build-time hygiene, all learned the hard way: `--variant=minbase`; bind all four
of `/proc`, `/sys`, `/dev`, `/dev/pts`; `policy-rc.d` to stop daemons starting in
chroot; stamp file written **last** so interrupted builds aren't mistaken for
complete; zstd not xz.

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
