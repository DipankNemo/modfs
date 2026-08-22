# modfs — modular, updatable filesystem for BMaaS

BSc thesis prototype. Ubuntu 22.04, APT/dpkg, x86-64.

Modules are **deltas**: built by overlaying a pinned base, installing into the
merged view, and squashing only the upperdir. Composition stacks them read-only
and adds a computed reconciliation layer so the package database matches what is
actually on disk.

See `ARCHITECTURE.md` for the design and `JOURNAL.md` for the work log.

## Layout

    scripts/     pipeline, numbered by stage
    specs/       module definitions
    docs/        thesis material
    reference/   prior chat logs, papers, professor's slides
    tests/       fixtures for the checker

    /srv/modfs/  artefacts (modules, builds, images, logs) — not in git

## Quick start

    sudo ./scripts/00_verify.sh                 # check assumptions
    sudo ./scripts/01_build_base.sh             # ~15 min
    sudo ./scripts/02_build_delta.sh webserver nginx
    sudo ./scripts/02_build_delta.sh pytools python3-numpy python3-pip
    sudo ./scripts/05_check.sh webserver pytools
    sudo ./scripts/04_compose.sh base webserver pytools
