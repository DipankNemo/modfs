# ModFS — A Modular Updatable File System for Bare Metal as a Service

Code and evidence for the Bachelor's thesis of that title, Leibniz University
Hannover, Institute for Systems Engineering (Dependable and Scalable Software
Systems), 2026. Author: Dipanker Dubey.

Target: Ubuntu 22.04 (jammy), APT/dpkg, x86-64.

## What it is

A Bare Metal as a Service platform normally stores one complete disk image per
configuration, so ten configurations sharing one Ubuntu base store that base ten
times. ModFS stores the base once and each configuration as a **module**: a
*delta* made by overlaying a pinned archive snapshot, installing packages into
the merged view, and squashing only the OverlayFS upper directory.

Composition stacks selected modules read-only, **reconciles** the eight registry
files that every module rewrites (dpkg status, alternatives, diversions,
extended states, the account databases, debconf; `ld.so.cache` and
`/etc/alternatives` are regenerated) and flattens the result into an ordinary
ext4 root. The saving is **server-side storage and assembly**; a provisioned
node still receives a conventional image.

Before composing, a set is checked against a taxonomy of nine conflict classes.
Two of them, runtime resource conflicts and opaque-directory erasure, were found
by running the system rather than by reasoning about it.

## Verification, in three tiers

| tier | what it does | script | cost |
|---|---|---|---|
| 1 | admission from metadata only, no mounts | `05_check.sh`, `09_run_combinations.sh` | well under a second per set |
| 2 | compose for real and verify the result (checks V1–V8) | `10_compose_sweep.sh` | compose 92.0 + 30.53 ms × N; verify 96.1 + 39.08 ms × N |
| 3 | pack a UEFI disk image and boot it under QEMU | `11_boot_test.sh` | 183–330 s per boot, median 199 s |

N is the number of modules in the set. Every figure is regenerated from retained
results by `scripts/16_build_evidence.sh` into `thesis/evidence/`, together with
its source file and digest.

## Requirements

Linux x86-64 with root (builds use OverlayFS, loop mounts and chroot) and network
access to `snapshot.ubuntu.com`. The build host needs **squashfs-tools 4.6 or later**
for `mksquashfs -xattrs-exclude`, which Ubuntu 22.04's 4.5 lacks; the results here
were produced on an Ubuntu 24.04 host (4.6.1) building Ubuntu 22.04 targets. On Ubuntu 24.04:

    sudo apt install debootstrap squashfs-tools zstd python3 python3-yaml \
                     rsync gdisk dosfstools e2fsprogs qemu-system-x86 ovmf

Artefacts are written to `/srv/modfs` by default; set `MODFS_ROOT` to use another
location. Inside the repository, the pipeline's only output is `thesis/evidence/`.

## Running it

Every stage, in order, from an empty machine to regenerated tables:
**[`docs/RUNBOOK.md`](docs/RUNBOOK.md)**. In short:

    sudo ./scripts/00_verify.sh              # check the two premises the design rests on
    sudo ./scripts/01_build_base.sh          # the shared base
    sudo ./scripts/08_build_catalogue.sh     # every module in specs/modules.yaml
    ./scripts/09_run_combinations.sh --jobs 8        # tier 1: all pairs and triples
    sudo ./scripts/10_compose_sweep.sh               # tier 2
    sudo ./scripts/11_boot_test.sh base vim emacs    # tier 3, one set
    ./scripts/16_build_evidence.sh           # regenerate thesis/evidence/

## Tests

    for t in tests/*.py; do python3 "$t"; done

Tests that mount artefacts need root and **skip** when run without it. What each
file checks is listed in [`tests/README.md`](tests/README.md).

## Layout

    config.sh         paths and settings every script sources
    scripts/          the pipeline, numbered by stage (00–16), and its Python modules
    specs/            the module catalogue and the per-module UID ranges
    tests/            regression and adversarial test suites
    thesis/evidence/  every published number, regenerated, with provenance
                      (raw/ holds the per-set census and per-composition sweep rows)
    docs/             reference documentation (below) and the cross-machine evidence
    ARCHITECTURE.md   the canonical design
    EVOLUTION.md      how the design developed, phase by phase
    JOURNAL.md        the chronological record of findings, including retractions

## Documentation

- `ARCHITECTURE.md`: the design; if code and this file disagree, the code is wrong
- `docs/RUNBOOK.md`: every command, in order
- `docs/REGISTRY_FORMATS.md`: the eight registries, record by record, and how each is merged
- `docs/DATA_MODEL.md`: manifest, file-ownership sidecar, spec files and the integrity digests
- `docs/SAMPLING_AND_BOOT.md`: how tier 2 chooses sets, and how a composed tree becomes a booting machine
- `docs/evidence/remote-verification-2026-09-20/REPORT.md`: rebuilding the catalogue on a second machine

## AI assistance

The code was written with AI coding assistance (Claude Code; OpenAI Codex),
directed, run and reviewed by the author. The thesis appendix *Verwendete
Hilfsmittel / Tools used* describes this use.
