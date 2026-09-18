# ModFS — state of play, 18 September 2026

What exists, what it actually does, and what was found to be lying about itself.
Written after three independent review passes in two days. `ARCHITECTURE.md`
remains canonical for design; this is an orientation map.

---

## 1. What the system is, in one paragraph

A base Ubuntu 22.04 root filesystem is built once from a pinned archive snapshot.
Each *module* is built by mounting that base read-only, installing packages into
an OverlayFS upper directory, and squashing **only the upper** into a `.sqsh`
artefact — so a module is a *delta*, not an image. Composition stacks modules as
read-only lower layers, merges the registry files that every module rewrites,
and flattens the result into a conventional ext4 root. The saving is
**server-side storage and assembly**; the node receives an ordinary image.

---

## 2. The conflict taxonomy

Nine classes. Seven were designed; classes 8 and 9 were **discovered by running
the system** and are not yet in `ARCHITECTURE.md` §4.

| # | Class | What goes wrong | Handling | Status |
|---|---|---|---|---|
| 1 | Benign overlap | Two modules carry the same package at the same version | Accept, measure duplication | designed |
| 2 | Version skew | Same package, different versions | Reject at tier 1; tier 2 now compares `(name, version)` | **was invisible to tier 2 until 18 Sep** |
| 3 | Declared conflict | Debian `Conflicts:`/`Breaks:`, including virtual names | Reject | designed |
| 4 | File collision | Two *different packages* own the same path | Reject; suppressed only by `Replaces:` **plus** `Breaks`/`Conflicts` | tightened 18 Sep |
| 5 | State divergence | Registry files every module rewrites | **Reconcile** — see §3 | the core mechanism |
| 6 | Implicit base upgrade | A module upgrades a package inherited from base | Prevent, detect recurrence | designed |
| 7 | Identity collision | Two modules allocate the same UID/GID to different names | UID-range partitioning + record comparison + **numeric file-owner comparison** | extended 18 Sep |
| **8** | **Runtime resource conflict** | Packages compose; *services* cannot coexist | **No detection possible below tier 3** | **open, by nature** |
| **9** | **Opaque directory erasure** | One module silently deletes another's files with *no* file collision | Fixed at source: opaque markers stripped at squash time | **fixed 16 Sep** |

### Class 8 — runtime resource conflict
`apache2` and `nginx` both bind `:80`. As *installed packages* they compose
perfectly; as *running services* they cannot. Nothing in dpkg metadata expresses
this, so tiers 1 and 2 cannot see it and never could. It is also a **startup
race**, therefore nondeterministic. Visible since 3 September in the `m3`/`m4`
boot runs as `degraded` + `failed-unit apache2.service`, and undiagnosed until
17 September.

### Class 9 — opaque directory erasure
`trusted.overlay.opaque` tells OverlayFS to ignore every lower layer at a path.
`pyyaml` carried it on `/usr/lib/python3`, which erased the whole of `pytools`'
numpy tree. **No file collided** — the two modules ship different filenames —
so class 4 could never see it, and `dpkg` correctly reported numpy installed
while the files were absent.

Measured across 38 modules: **869 markers, 456 distinct directories, 178 claimed
by two or more modules**. Each marker was written when the only lower layer was
base, which has nothing at those paths, so it hid nothing at build time; at
compose time "below" becomes the sibling modules, which did not exist when the
marker was made.

Fixed by adding `opaque` to `SQUASH_XATTR_EXCLUDE` in `config.sh`. Whiteouts are
untouched, so file-level deletion still works; only "replace this whole
directory" is dropped, and nothing used it.

---

## 3. Class 5 in detail — the registries

These files are **not package-owned**, so class 4 never sees them, and OverlayFS
takes the top layer's copy **entire**. Every one of them had to be found the
hard way.

| Registry | Handling | Found |
|---|---|---|
| `/var/lib/dpkg/status` | union, later layer wins | original |
| `/var/lib/dpkg/alternatives/*` | union of candidates; **priority disagreement is now a conflict** | original; priority bug 17 Sep |
| `/var/lib/dpkg/diversions` | union | original |
| `/var/lib/apt/extended_states` | union | original |
| `/etc/passwd`, `group`, `shadow`, `gshadow`, `subuid`, `subgid` | union by record, member lists merged | **16 Sep** |
| `/var/cache/debconf/{config,templates,passwords}.dat` | union by `Name`, `Owners` merged | **18 Sep** |
| `/etc/alternatives/*` | **regenerated** by `update-alternatives --auto` | original |
| `/etc/ld.so.cache` | **regenerated** by `ldconfig` | original |

Two are *regenerated rather than merged*, because they are functions of the
merged registry rather than content in their own right.

---

## 4. Verification

| Tier | What it does | Cost |
|---|---|---|
| 1 | Metadata only, no mounts (`05_check.sh`) | 89 ms at N=2 → 398 ms at N=36 |
| 2 | Compose for real, verify (`10_compose_sweep.sh`) | 148 + 27.2 ms × N |
| 3 | Pack a UEFI image, boot under QEMU (`11_boot_test.sh`) | ~3 min |

Tier-2 checks, in `verify_compose.py`:

- **V1** reconciliation completed
- **V2** merged dpkg status is the exact union — **now `(name, version)`**
- **V3** every alternatives group holds every candidate offered
- **V4** `/etc/ld.so.cache` is the union of the layers' caches
- **V5** `dpkg --audit` clean
- **V6** account databases are the exact semantic union, record by record
- **V7** every path in any layer is visible in the merge, compared by `(kind, size)`
- **V8** every debconf record any layer answered survives the merge

> **Documentation drift:** `10_compose_sweep.sh`'s own header still advertises
> only V1–V6. V7 and V8 exist but the script describing them does not mention
> them. Same defect as before: the script that runs the check documenting itself
> as not having it.

---

## 5. The bugs — and the pattern worth understanding

This is the part with thesis value. Nearly every defect fell into one of three
shapes.

### 5a. Checks that passed while proving nothing

| What it claimed | What it did | Consequence |
|---|---|---|
| V7 "every file is visible" | compared directory **entry names** | a decoy symlink replaced 1 MB with 5 bytes, `vis_ok=1` |
| V7 (again) | `os.path.join` against the merged root | an absolute symlink resolved against the **checking host's** `/etc` — verdict depended on the machine |
| V2 "dpkg status is the exact union" | compared package **name sets** | tier 1 rejected `curl`+`control-oldsnap` for five version skews; tier 2 passed every column |
| class 7 "no id reused" | compared declared **records** | a module shipping a file owned by uid 2500 without declaring it inherits another module's identity |
| class 4 `Replaces:` suppression | accepted a **bare** `Replaces` | a collision flipped REJECT→ACCEPT by adding one manifest line; artefact bytes unchanged |
| alternatives merge | last layer wins on **priority** | a module owning *zero files* silently changed which binary `/usr/bin/editor` resolves to |
| `reconcile.py` divergence | detected it, printed it, **dropped it** before `problems` | exited 0 while resolving a class-2 skew by last-wins |
| `alt_groups` CSV column | a **shadowed variable** — the gshadow record count | a published number was wrong: 42 where the truth was 10 |

### 5b. The harness constraining the measurement

Four separate cases where **the instrument, not the system, was the limit** —
and every one was invisible while N was small or probes were weak.

1. **`require_no_mounts` parsed field 2** of `/proc/self/mountinfo` instead of field 5. The guard was completely inert.
2. **Signal handlers `return`ed** instead of re-raising, so scripts continued after Ctrl-C and exited 0.
3. **The observer was the job.** The boot harness waited for a steady state its own queued job prevented — `systemctl is-system-running --wait` could never succeed at any timeout. 180 s wasted per run. Compounded by `grep -c . || echo 0` producing the two-line string `0\n0`, so the drain loop could not break *even on an empty queue*: one symptom, two sufficient causes.
4. **The 4096-byte mount-data ceiling.** OverlayFS packs every lower layer into one option string. A 37-layer set failed or succeeded *depending on how long its scratch directory name was*. Fixed with relative lowerdirs: 4319 bytes → 419.
5. **`07_smoke_test.sh` never created `/tmp`.** Nine probes "failed"; all nine were the harness. Invisible for the life of the project because no probe had ever written a file.

### 5c. Evidence that was quietly false

- **Stale-workspace republication.** Sweeps cleared scratch with `rm -rf` and never checked it worked. A root-owned leftover made a sweep **republish 666 stale result files as a fresh run**. Fixed with `reset_workdir()`, which proves the directory is empty.
- **The `99modfs` leak.** `APT::Install-Recommends "false"` shipped inside base and unevenly through modules, so deployed nodes silently had recommends disabled.
- **Monolithic baselines two weeks stale.** `08 --force` does not rebuild them, so a storage comparison would have measured fresh deltas against monoliths built on the leaked base.
- **A census that rotted into a sample.** The tier-2 plan said `27:1`. When written, the catalogue held exactly 27 usable modules — so that was a *census*, one deterministic set. The catalogue grew to 37 and the plan never moved, silently becoming a single random draw where only 38% of draws are admissible. **A constant meaning "all of them" decayed when the population changed.**
- **CSV column misalignment.** Adding two columns without updating six hand-counted `printf`s put every failure label in the wrong column and left `result` empty — so correct summary logic that separated refusals from failures was silently defeated by a data bug one layer down.
- **Probes measuring the harness.** `fake-cuda`'s `command -v sl` failed because systemd's PATH omits `/usr/games` — a false *negative*. Nine others were false *positives*: `postgres` and `pgclient` both ran `psql --version`, and `psql` comes from a package **both** ship, so postgres passed with no server anywhere.

---

## 6. Current evidence

| | |
|---|---|
| Tier 1 | 703 pairs, **ACCEPT 630 / REJECT 73** — matches an independent combinatorial prediction |
| Tier 2 | 152 compositions, N=2→36, **152 PASS** |
| Tier 3 | 36 probes pass under systemd; only `apache2.service` fails (class 8) |
| Smoke | 75 passed, 0 failed at N=37 |
| Regression | `v7_attacks.py` 4/4, `round2_attacks.py` 11/11 |
| Storage | 5.59× small / 1.32× large / **2.51× whole catalogue** |
| Cost | tier 2 = 148 + 27.2 ms × N |

**Base fattening** (measured, not adopted): server-side **−24.1%**, but *no
single-module node can ever win* — structurally, because the shared set is
chosen by "appears in ≥2 modules", so `dB` always exceeds any one module's
saving. Server-side and per-node metrics give **opposite answers for the same
build**; the thesis must state which it claims.

---

## 7. Known open

1. **Class 8** — no detection below tier 3, by nature.
2. **V7 same-size substitution** — `(kind, size)` cannot see same-size content replacement. Encoded as a `KNOWN OPEN` test.
3. **V7 non-regular nodes** — FIFOs, sockets, device nodes collapse together.
4. **Order-independence is semantic, not byte-wise.** `ARCHITECTURE` §4 says the merged account files are "identical under order reversal". Measured: **set-equal yes, byte-equal no.** The claim is too strong as written.
5. **Four probes satisfied by a sibling** — `gawk`, `gcc`, `rsync` and one more. Documented with `probe_note` rather than fixed.
6. **The sidecar seal is optional** — `binding.sidecar_sha256` lives *inside* `binding`, which cannot be inside its own digest, so deleting that one field disables the check while the manifest seal still verifies. A tampered sidecar can invent collisions or erase evidence. *(Codex H1; fix pending.)*
7. **No Related Work section** exists.
8. **Verification cost is outside the published model.** `total_ms` is exactly `mount_ms + reconcile_ms` — it measures composing, not verifying.
9. **CUDA/TensorFlow**: costed, not built. The blocker is *not* the absence of a kernel — the kernel is pinned and deterministic. It is that the resolved ABI is **recorded nowhere**. TensorFlow is a separate problem: it exists only on PyPI, which has no snapshot service, so it cannot satisfy the pinning premise at all.

---

## 8. Where things live

```
~/modfs/                      code (git)
  ARCHITECTURE.md             canonical design — if code disagrees, the code is wrong
  JOURNAL.md                  running findings log; becomes Implementation + Evaluation
  config.sh                   paths, SQUASH_EXCLUDES, SQUASH_XATTR_EXCLUDE
  specs/modules.yaml          the 38-module catalogue: packages, probes, requires
  specs/uid-ranges.yaml       100-wide UID windows from 2000, append-only
  scripts/00..12_*.sh         pipeline, numbered by stage
  scripts/reconcile.py        the registry merges (class 5)
  scripts/verify_compose.py   V1–V8
  scripts/sample_sets.py      constraint-aware sampler
  tests/                      v7_attacks.py, round2_attacks.py, repro_check.sh

/srv/modfs/                   artefacts (NOT git)
  modules/<name>.sqsh         the delta artefact
  modules/<name>.json         manifest — what tier 1 reads
  modules/<name>.files.json.zst   class-4 file-ownership sidecar
  modules/<name>.upper        build tree (scratch, not the artefact)
  logs/combinations.csv       tier-1 results
  logs/compose-sweep.csv      tier-2 results
  results/boot/<run>/         tier-3 evidence bundles — irreplaceable
  build/                      pure scratch, safe to delete
```

---

## 9. The one sentence worth keeping

Across three review passes, **the checkers were wrong more often than the system
under test.** Tier 2 has never failed a composition for a genuine composition
defect that a checker did not first have to be taught to see — and every time a
check was strengthened, it found something the weaker version had been passing.
That is the honest shape of this project's evidence, and it is a better result
than a clean run would have been.
