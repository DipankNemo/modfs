# Modular, updatable filesystem for BMaaS — status

**Date:** 6 August 2026 · Scope: Ubuntu 22.04 (jammy), APT/dpkg, x86-64

---

## 1. Since the last meeting

| June (shown last time) | Now |
|---|---|
| Modules = full rootfs copies (own `debootstrap` each) | Modules = **deltas**, only changed files |
| Packages from the live archive | Packages from a **pinned snapshot** (`20260701T000000Z`) |
| Metadata = package name + version | Full relations: `Depends`, `Conflicts`, `Breaks`, `Provides` |
| Validation = `apt --simulate` (wrong question) | **Own checker** over frozen module metadata |
| "It boots" | Measured storage, measured conflicts, measured defect |
| — | **A demonstrated defect in the naive design, and its fix** |

June answered *is this physically possible?* — yes. That question is closed.
Now: *is the obvious way correct?* — **no**, and here is what replaces it.

---

## 2. The defect I found

Each module carries its own `/var/lib/dpkg/status` — the package catalogue.
OverlayFS shows only the topmost copy. Composing three modules:

```
packages the catalogue lists : 137
packages actually installed  : 178
INVISIBLE                    :  41

dpkg says 'nginx' : NOT INSTALLED
  but on disk:  PRESENT: /usr/sbin/nginx
```

The node runs software it does not know it has. `apt` on that machine is
unreliable: it would re-install packages already present, and `autoremove`
could delete files another module depends on.

**Fix:** compute the correct catalogue as a union of stanzas and write it to a
reconciliation layer above all modules.

```
reconciled: 178 listed / 178 real     INVISIBLE: 0
dpkg says 'nginx' : INSTALLED
```

This also makes the result **order-independent**: without reconciliation the
stacking order decides which packages disappear.

---

## 3. Architecture

Layered deltas over one common pinned snapshot.

1. **Pin** every build to a fixed archive snapshot → no version drift by construction
2. **Base** built once by `debootstrap`, aligned to the same archive view
3. **Modules** built by overlaying the parent, installing into the *merged* view,
   and squashing **only the upperdir** → the diff
4. **Compose** = stack read-only modules + a computed reconciliation layer

Key argument: pinning reduces an intractable **file-level** conflict problem to
a small, declarative **package-level** one.

---

## 4. Conflict taxonomy

Every way two modules can fail to compose, and the policy for each.

| # | Class | Cause | Detection | Policy |
|---|---|---|---|---|
| 1 | **Benign overlap** | Same package, same version, two siblings | Version match in union | Accept; measure duplication |
| 2 | **Version skew** | Siblings from different snapshots, parents, or explicit pins | Version mismatch | **Reject** |
| 3 | **Declared conflict** | `Conflicts:` / `Breaks:` between modules | Match declarations vs union | **Reject** |
| 4 | **File collision** | Different packages own the same path | Compare `dpkg/info/*.list` | Warn / reject *(not yet implemented)* |
| 5 | **State divergence** | Registry files: `status`, `extended_states`, caches, logs | Structural — always occurs | **Reconcile / regenerate** |
| 6 | **Implicit base upgrade** | A delta upgrades a package inherited from base | Compare delta vs parent versions | **Prevent**; detect if it recurs |

Class 6 was found in this work and is not addressed by pinning alone.

### Class 6 — found, diagnosed, fixed

`pytools` silently upgraded three base packages. Traced:

```
python3-numpy → liblapack3 → libgfortran5 → gcc-12-base (= 12.3.0-...)
```

`libgfortran5` has an **exact-equality** dependency on `gcc-12-base`, and the
GCC runtime packages are version-locked to each other, so one transitive
dependency dragged the whole cluster forward.

**Root cause:** `debootstrap` populates base from the plain `jammy` pocket,
while delta builds see `jammy` + `-updates` + `-security`. Base was a year
behind before a single module was built.

**Fix:** one `apt-get full-upgrade` during the base build. It moved 61
packages. The checker now reports **0 upgraded** for both modules.

### Class 5 — measured, not assumed

Of ~5 000 files across two deltas, **28** appear in both; **17** are
byte-identical (391 KB duplicated, harmless); **11** differ and need handling:

| Files | Treatment |
|---|---|
| `/var/lib/dpkg/status` | **union** — implemented |
| `/var/lib/apt/extended_states` | **union** — same shape, pending |
| `/etc/ld.so.cache`, `/var/cache/ldconfig/aux-cache` | **regenerate** (`ldconfig`) |
| `debconf/config.dat`, `templates.dat` | union via debconf tooling, or documented limitation |
| `/var/lib/dpkg/status-old` | **drop** (backup file) |
| 4 × `/var/log/*` | concatenate or drop |

A prediction that failed: `/etc/passwd` and `/etc/group` were expected to
collide. They did not — base already provides `www-data`.

---

## 5. The pipeline

Five scripts. Each answers one question.

| Script | Does | Why it exists |
|---|---|---|
| `00_verify.sh` | Checks host tools, kernel support, snapshot reachability, and whether an OverlayFS upperdir survives a SquashFS round trip | The architecture assumes deltas can be compressed and restacked. Deletions are stored as character devices `0:0`, directory replacements as `trusted.overlay.opaque` xattrs — if SquashFS dropped either, delta modules could add files but never remove or replace one. **30 checks, 30 passed.** |
| `01_build_base.sh` | `debootstrap` a minimal rootfs from the pinned snapshot, align it to the same archive view, install core packages, squash | The single common parent. `--variant=minbase`, all four pseudo-filesystems bound, `policy-rc.d` so daemons don't start in the chroot, stamp file written last so an interrupted build is never mistaken for a finished one. The `full-upgrade` step is the fix for class 6. |
| `02_build_delta.sh` | Mounts the parent read-only, overlays an empty upperdir, `chroot`s into the **merged** view, installs, then squashes **only the upperdir** | The core mechanism. Because apt looks at the merged view, it sees base as already installed and writes only what is genuinely new. The upperdir *is* the delta — captured by the filesystem, not computed. 21 MB instead of 176 MB. |
| `03_analyse_overlap.sh` | Byte-compares every file appearing in two deltas (`cmp`, not size or hash); reports identical vs differing; lists packages contributed by both | A microscope, run once as research. Answers *what must my composer handle?* Found: of ~5 000 files, 28 overlap, 17 byte-identical, **11 differ**. Also produced the anomaly that led to class 6. |
| `05_check.sh` | Reads package metadata only. Detects base drift with dependency-chain tracing, sibling version skew, benign overlap, declared conflicts. Verdict: ACCEPT / REJECT | An instrument, run on every composition. No mounting, no building, no network, ~1 s. Verified to reject synthetic version skew and declared conflicts. |
| `04_compose.sh` | Stacks the modules, shows the naive catalogue undercount, then writes a merged `status` into the top layer and re-measures | Demonstrates the defect **and** the fix in one run: 41 invisible → 0. |

**Design note:** `03` and `05` look similar but operate at different levels — `03`
compares *files*, `05` reasons about *packages*. `03` answered a design question
once; `05` runs forever.

---

## 6. Results

**Verification (architecture assumptions):** 30 checks, 30 passed.
OverlayFS whiteouts and opaque-directory markers survive a SquashFS round
trip — delta modules are viable.

**Storage**

| Artefact | Compressed | Packages |
|---|---|---|
| `base.sqsh` | 40 MB | 113 |
| `webserver.sqsh` | 21 MB | +42 |
| `pytools.sqsh` | 25 MB | +24 |
| **stored total** | **86 MB** | — |

86 MB expresses four bootable configurations (base; +web; +py; +web+py).
Monolithic equivalent ≈ 252 MB → **~2.9×**, growing with each module.
*(Estimate — the monolithic comparison build has not yet been run.)*

**Consistency check** — metadata only, no mounting, no build, no network, ~1 s:

```
VERDICT: 0 error(s), 0 warning(s)   ACCEPT -- module set is consistent
```

Also verified to **reject** synthetic version skew and declared conflicts.

**Why no dependency solver:** full installability in Debian-style systems is
NP-complete (Di Cosmo et al., EDOS/Mancoosi). Resolution is done once by `apt`
at build time, when the problem is small. Composition afterwards is pure
verification against frozen metadata — linear, no solver, no network.

---

## 7. Conflict classes not yet tested

The six classes came from what the current modules exercise. These are
plausible additional classes the present module set cannot produce:

| Candidate | Mechanism | Cheapest test |
|---|---|---|
| **Whiteouts** | A module *removes* a file from base. Deletion is stored as a marker; a higher layer restoring the path can override it, so ordering matters far more than it does today. Nothing built so far removes anything. | Build a module that purges a base package |
| **Alternatives** | Two modules both register for the same generic name via `update-alternatives` — `/usr/bin/editor`, `java`. The `/etc/alternatives` symlinks and `/var/lib/dpkg/alternatives` registry differ; last-wins silently discards one. | `vim` vs `emacs-nox` |
| **Diversions / `Replaces`** | A package deliberately overrides another's file. Legitimate when declared, dangerous when two modules do it independently. | `netcat-openbsd` vs `netcat-traditional` |
| **Maintainer script side effects** | `postinst` appends to a shared config rather than shipping a file. Two modules each append; the merge keeps one. | Two modules editing the same conf |
| **Trigger interactions** | `ldconfig`, `update-initramfs`, font caches fire in one module and not another, leaving caches that describe only part of the system. | Already visible: `ld.so.cache` differs |
| **Runtime resource conflicts** | Both modules install services claiming port 80. Composes cleanly, fails at boot — outside dpkg's model entirely. | `nginx` + `apache2` |

Modules for these should be chosen **adversarially**, to provoke classes, rather
than for realism.

---

## 8. Not yet done

- Reconciliation for the remaining 10 files (1 of 11 implemented)
- `module.json` — metadata beside each artefact, so validation needs no build tree
- File-collision detection (class 4)
- Monolithic comparison build for exact storage figures
- Update manager at module level
- Boot verification under the new architecture
- REST API and BAAS integration

---

## 9. Questions

1. **Server-side composition only**, with on-node overlay at boot as future work — confirm?
2. **Standalone prototype + documented REST API**, no integration into the Go BAAS
   codebase — acceptable?
3. Combinability restricted to **siblings sharing a base and a snapshot** — acceptable?
4. For the evaluation chapter: storage and build-time measurements, or something else?
5. Given the submission date, is this scope right, or should it be cut further?
