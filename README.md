# modfs — modular, updatable filesystem for BMaaS

BSc thesis prototype. Ubuntu 22.04 (jammy), APT/dpkg, x86-64.

Modules are **deltas**: built by overlaying a pinned archive snapshot, installing
into the merged view, and squashing only the upperdir. Composition stacks them
read-only, reconciles the eight registry files that every module rewrites, and
flattens the result into a conventional ext4 root — so the saving is **server-side
storage and assembly**, and a provisioned node receives an ordinary image.

## What is verified, and how

Three tiers of increasing cost. The gaps are **not** uniform, and saying "two
orders of magnitude at each step" overstates the first one by more than tenfold:
tier 1 → tier 2 is **5–7×**, tier 2 → tier 3 is **68–414×** (the spread is
because tier 3 barely depends on N while tier 2 grows with it).

| tier | what it does | cost |
|---|---|---|
| 1 | metadata only, no mounts (`05_check.sh`) | 89 ms at N=2 → 398 ms at N=36 |
| 2 | compose for real and verify V1–V8 (`10_compose_sweep.sh`) | compose 175.2 + 30.55 ms × N; verify 161.3 + 41.8 ms × N |
| 3 | pack a UEFI image and boot under QEMU (`11_boot_test.sh`) | 183–331 s, median 199 s |

Every command, in order, from an empty machine to regenerated thesis tables:
**`docs/RUNBOOK.md`**.

Nine conflict classes are catalogued in `ARCHITECTURE.md` §4. Two of them —
runtime resource conflict and opaque directory erasure — were found by running
the system rather than by reasoning about it.

## Layout

    scripts/        pipeline, numbered by stage (00–16)
    specs/          module catalogue and UID ranges
    tests/          regression suites, including the adversarial fixtures
    thesis/         chapter plan, evidence tables, references
    docs/           assessments, reviews, state of play
    ARCHITECTURE.md canonical design — if the code disagrees, the code is wrong
    EVOLUTION.md    how the project got here, phase by phase
    JOURNAL.md      append-only findings log, including retractions

## Regenerating every published number

    ./scripts/16_build_evidence.sh          # writes thesis/evidence/, no root
    ./scripts/16_build_evidence.sh --check  # reports drift, writes nothing

Every table is produced from the retained CSVs and run bundles rather than
transcribed, and the generator **refuses** to emit a figure whose source is older
than the artefacts it describes.

## Reading order

`EVOLUTION.md` for the narrative, `docs/STATE_OF_PLAY_2026-09-18.md` for where
things stand, `thesis/evidence/` for any specific number and its provenance.
