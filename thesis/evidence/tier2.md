# Tier 2 — real compositions, verified against their own layers

**Chapter: Evaluation**

_Excluded by design: the positive control (control-oldsnap) — built from a different snapshot, meant to be rejected at tier 1, so composing it would prove nothing._

## T2.1 Compositions by set size

_**Catalogue: 39 modules** · measured 2026-09-23 12:04:27Z · source `/srv/modfs/logs/compose-sweep.csv`_

| N | samples | packages | alt groups | debconf records | mount ms | reconcile ms | total ms | verify ms |
|---|---|---|---|---|---|---|---|---|
| 2 | 30 | 117–178 | 5–38 | 90–114 | 46 | 114 | 160 | 175 |
| 3 | 30 | 126–187 | 5–17 | 90–156 | 56 | 118 | 173 | 205 |
| 5 | 20 | 131–216 | 5–52 | 90–156 | 75 | 174 | 249 | 305 |
| 10 | 10 | 174–273 | 7–49 | 90–156 | 128 | 256 | 384 | 460 |
| 15 | 10 | 224–305 | 12–54 | 100–164 | 188 | 380 | 567 | 680 |
| 20 | 10 | 230–351 | 14–68 | 112–172 | 237 | 468 | 706 | 903 |
| 25 | 10 | 307–371 | 26–67 | 120–166 | 298 | 573 | 872 | 1103 |
| 27 | 10 | 325–383 | 29–67 | 114–174 | 321 | 597 | 918 | 1180 |
| 30 | 10 | 339–381 | 25–67 | 112–174 | 359 | 617 | 976 | 1238 |
| 33 | 6 | 367–395 | 34–68 | 118–168 | 437 | 674 | 1111 | 1350 |
| 35 | 4 | 388–408 | 35–68 | 172–174 | 455 | 703 | 1158 | 1454 |
| 38 | 2 | 406–413 | 68 | 168–174 | 504 | 764 | 1268 | 1582 |

## T2.2 Per-check outcome, V1–V8

_V1 has no column of its own; a recorded `reconcile_ms` is the witness that reconciliation ran to completion, and that is weaker evidence than V2–V8 carry._

_**Catalogue: 39 modules** · measured 2026-09-23 12:04:27Z · source `/srv/modfs/logs/compose-sweep.csv`_

| check | what it asserts | CSV column | passing | verdict | failures |
|---|---|---|---|---|---|
| V1 | reconciliation completed | `reconcile_ms` | 152 / 152 | clean |  |
| V2 | merged dpkg status is the exact union, by (name, version) | `pkg_ok` | 152 / 152 | clean |  |
| V3 | every alternatives group holds every candidate offered | `alt_groups_bad` | 152 / 152 | clean |  |
| V4 | /etc/ld.so.cache is the union of the layers' caches | `ld_ok` | 152 / 152 | clean |  |
| V5 | dpkg --audit clean | `audit_ok` | 152 / 152 | clean |  |
| V6 | account databases are the exact semantic union | `acct_ok` | 152 / 152 | clean |  |
| V7 | every layer path visible in the merge | `vis_ok` | 152 / 152 | clean |  |
| V8 | every debconf record any layer answered survives | `dbc_ok` | 152 / 152 | clean |  |

## T2.3 Cost model, fitted to this sweep

_Ordinary least squares `ms = a + b·N` over every row of this CSV. These coefficients belong to THIS generation and must not be differenced against a fit from another one: the catalogue and the checker both change between sweeps._

_**Catalogue: 39 modules** · measured 2026-09-23 12:04:27Z · source `/srv/modfs/logs/compose-sweep.csv`_

| quantity | column | a (intercept, ms) | b (slope, ms per module) | R² | n |
|---|---|---|---|---|---|
| mount | `mount_ms` | 17.4 | 11.73 | 0.9746 | 152 |
| reconcile | `reconcile_ms` | 74.5 | 18.80 | 0.9630 | 152 |
| total (compose only) | `total_ms` | 92.0 | 30.53 | 0.9813 | 152 |
| verify | `verify_ms` | 96.1 | 39.08 | 0.9649 | 152 |

**`total_ms = mount_ms + reconcile_ms` holds on 152 of 152 rows.** The total fit therefore measures COMPOSING, not verifying; `verify_ms` is a separate column and is not folded in.
