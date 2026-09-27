# Tests

    for t in tests/*.py; do python3 "$t"; done

Files marked **root** mount artefacts, repack SquashFS images or chroot. Run
without root, they **skip** rather than fail, so a failure always means a real
defect. The two shell scripts need root and are run individually.

Most suites were written adversarially: each case reproduces a way a check was
once fooled, next to a control that proves the check still passes on good input.
Cases carry one of three labels:

- **FIXED**: a defect that was reproduced and repaired; the case fails if it returns
- **CONTROL**: correct input that must still pass, so a fix cannot work by rejecting everything
- **KNOWN OPEN**: a documented limitation, kept so the test notices if it ever changes

The `round2`, `round3` and `round4` files are named after the review pass that
produced them.

## Tier-2 verification (`scripts/verify_compose.py`, checks V1–V8)

| file | checks |
|---|---|
| `v7_attacks.py` | V7 file visibility: a decoy symlink hiding a file, a symlink resolved against the host instead of the image, a replaced library directory |
| `round2_attacks.py` | V7 node types (FIFO, socket, devices), whiteouts, reconciled paths, and the debconf merge; includes the KNOWN OPEN same-size substitution case |
| `review_verification.py` | mutations of a composed tree against the complete verifier: account records and file modes, debconf records, symlink targets |

## Registry merge and metadata extraction

| file | checks |
|---|---|
| `round4_attacks.py` | malformed and hostile registry records against `reconcile.py` and `06_extract_metadata.sh`: wrong field counts, duplicate members, truncated diversions, conflicting primary groups |
| `review_extended_states.py` | an explicitly installed package is never downgraded to "automatically installed" by another module |
| `review_account_metadata.py` | **root.** Account extraction and admission on a repacked real module |

## Tier-1 admission (`scripts/05_check.sh`)

| file | checks |
|---|---|
| `round4_class7.py` | numeric file-owner coverage on sealed synthetic manifests: a manifest missing its owner lists must not be reported as fully checked |
| `update_generation.py` | the generation identity: modules built on a different base or snapshot are refused, and a missing or forged generation is refused even when the manifest is resealed |
| `review_replaces.py` | **root.** the `Replaces:` policy for files owned by two packages |

## Manifest integrity

| file | checks |
|---|---|
| `review_binding.py` | the manifest and sidecar seals: missing, malformed and tampered digests |
| `review_binding_coverage.py` | **root.** stage 12 verifies every requested bundle, including an empty catalogue |

## Evidence and documentation

| file | checks |
|---|---|
| `round3_evidence.py` | the evidence generator: staleness detection, cohort declarations, empty cohorts, row widths, superseded boot bundles |
| `review_claims.py` | published documents quote the current measurements and no retracted claim |
| `update_report.py` | the update report (`14_report_update.sh`) treats a changed artefact as changed even when its size is unchanged |

## Build pipeline

| file | checks |
|---|---|
| `review_probes.py` | **root.** the PostgreSQL and zstd module probes: a working server passes, a broken one is rejected, and probes are repeatable and leave existing files alone |
| `update_pin.py` | **root.** stage 08's dispatch, including metadata refresh and a negative control |
| `gpu_probe_attacks.sh` | **root.** negative controls for the two GPU-module probes |
| `repro_check.sh` | **root.** diagnoses why two builds of the same module differ |

`legacy_generation.py` is not a test. It is a helper that other tests import.
