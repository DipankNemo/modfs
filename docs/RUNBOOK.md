# Runbook — building and evaluating ModFS from nothing

Every command here was read out of the script's own argument parser, not
remembered. `[root]` means it mounts, chroots or writes to root-owned paths.
Artefacts land in `/srv/modfs` (`$MODFS_ROOT`), never in the repo.

Recorded full-catalogue wall times: **13 min** (38 modules) and **19 min**
(38 modules, 7 oversize). The catalogue is 40 now and two of the additions are
the GPU modules (680 MB and 232 MB stored), so budget longer for those two.

---

## 0. Prove the design is possible at all `[root]`

```sh
sudo ./scripts/00_verify.sh
```

Checks the two assumptions everything else rests on: (A) the archive can be
pinned to a fixed snapshot, (B) an OverlayFS upperdir survives a round trip
through SquashFS, **including whiteouts and opaque markers**. If B fails, delta
modules are not possible and the design must change. Run this first on any new
machine.

## 1. Build the base `[root]`

```sh
sudo ./scripts/01_build_base.sh
```

A minimal Ubuntu rootfs from the pinned snapshot. Writes `base.sqsh`, and keeps
`base.dir/` because every delta build needs it as a lowerdir.

## 2. Build the catalogue `[root]`

```sh
sudo ./scripts/08_build_catalogue.sh              # build what is missing
sudo ./scripts/08_build_catalogue.sh --force      # rebuild everything
sudo ./scripts/08_build_catalogue.sh --only vim,emacs
sudo ./scripts/08_build_catalogue.sh --dry-run
```

This is the one-stop builder: it calls `02_build_delta.sh` and then
`06_extract_metadata.sh` for every entry in `specs/modules.yaml`. To do a single
module by hand instead:

```sh
sudo ./scripts/02_build_delta.sh webserver nginx
sudo ./scripts/06_extract_metadata.sh webserver --version 1.0
```

**`--force` does not rebuild the monolithic baselines.** They are built by
`02_build_delta.sh --compare` and have gone stale before; see `storage.md` §S2.

## 3. Prove each manifest still describes its artefact `[root]`

```sh
sudo ./scripts/12_verify_binding.sh               # whole catalogue
sudo ./scripts/12_verify_binding.sh curl webserver
```

Every tier-1 verdict is computed from `<name>.json`. Until 2026-09-18 nothing
checked that document against the `.sqsh` it names. Run this before trusting any
sweep.

---

## Tier 1 — metadata admission, no mounts

```sh
./scripts/09_run_combinations.sh --jobs 8         # pairs and triples
./scripts/09_run_combinations.sh --max-n 2        # pairs only, fast
./scripts/09_run_combinations.sh --out /tmp/x.csv
```

No root. 780 pairs + 9,880 triples on the 40-module catalogue. To check one set
by hand:

```sh
./scripts/05_check.sh webserver pytools
```

## Tier 2 — compose for real and verify V1–V8 `[root]`

```sh
sudo ./scripts/10_compose_sweep.sh
sudo ./scripts/10_compose_sweep.sh --seed 7 --plan 2:5,3:5
sudo ./scripts/10_compose_sweep.sh --pairs /srv/modfs/logs/combinations.csv
```

`--plan N:count,...` draws `count` sets at size `N`. Tier 1 has thousands of data
points and never mounts anything; this one mounts and checks.

## Tier 3 — UEFI boot under QEMU `[root]`

```sh
sudo ./scripts/11_boot_test.sh base webserver apache
sudo ./scripts/11_boot_test.sh --name runA base curl jq
```

183–331 s per run, median 199 s. Writes an evidence bundle under
`$RESULTS_DIR/boot/<run>/` which is **never overwritten** — the boot history is
the complete record, including runs where the harness was the failure.

---

## Reporting

```sh
./scripts/13_storage_ratios.sh                    # cohort table, no root
./scripts/13_storage_ratios.sh --csv out.csv
./scripts/16_build_evidence.sh                    # regenerate thesis/evidence/
./scripts/16_build_evidence.sh --check            # write nothing, report status
./scripts/16_build_evidence.sh --out DIR
```

Neither needs root. **`16` is the only thing that should ever produce a number
for the thesis** — nothing is hand-transcribed. Re-run it and every table moves
with whatever is on disk.

## Diagnostics, not pipeline

```sh
sudo ./scripts/03_analyse_overlap.sh webserver pytools   # PAIRWISE overlap only
sudo ./scripts/04_compose.sh base webserver pytools      # demonstrate class 5
sudo ./scripts/07_smoke_test.sh base webserver pytools   # functional probes
MODFS_ROOT=... sudo -E ./scripts/15_measure_monolith.sh jq
```

`03` is pairwise and answers "which files collide between these two" — it is not
an aggregate storage command. `04` exists to *show* naive overlay breaking and
reconciliation fixing it, which is a teaching artefact rather than a stage.

---

## Tests

```sh
for t in tests/review_*.py tests/*attacks*.py; do python3 "$t"; done
```

Ten files. Six run unprivileged; four mount artefacts or repack squashfs and skip
cleanly with `ROOT_ONLY` unless run as root. A red file means a real failure.

---

## A full rebuild is not a routine operation

**0 of 40 module archives are byte-identical across machines** — see
`docs/evidence/remote-verification-2026-09-20/REPORT.md`, where every difference
is diagnosed to a mechanism. Package *resolution* is deterministic because the
snapshot is pinned; install-time generated state is not. `/etc/shadow` alone
stores the password-change **day**, so the same machine rebuilding tomorrow
produces different bytes.

Consequences, before you run `--force`:

- Artefact sizes shift, so **every storage ratio in the thesis moves**.
- Retained tier-3 boot bundles become *superseded*: they describe artefacts that
  no longer exist.
- Any evidence regenerated afterwards cannot be diffed against evidence from
  before, so a rebuild destroys the baseline that makes drift visible.

Rebuild when the catalogue or the builder changes. Do not rebuild to "refresh"
numbers that are already correct for the generation they name.
