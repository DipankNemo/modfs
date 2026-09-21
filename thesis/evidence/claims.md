# Claims audit — every quantitative claim in the four documents, traced or not

**Chapter: Discussion**

> **Status update 2026-09-21.** This file is hand-written and is NOT refreshed by
> `scripts/16_build_evidence.sh`, so the verdicts below are the state at the time
> of the audit. **All 21 rows marked STALE have since been applied** — see
> `inconsistencies.md`, whose index carries the per-item status. Two of them
> deserve to be read rather than ticked off:
>
> - the `148 + 27.2 ms × N` rows (`:106`, `:146`) were traced and marked STALE
>   here, and then published as current in four documents for three more days,
>   because nobody read the trace and the test covering that claim checked the
>   number's *label* and never its *currency* (`inconsistencies.md` I-28);
> - the rows reading "TRACED for the 38-module catalogue, STALE as current" are
>   not errors in the original measurement. Each reproduces exactly for the
>   catalogue it was taken on — `storage.md` §S5 demonstrates this for every
>   published storage figure — and they moved because the catalogue grew to 40,
>   not because the method changed.
>
> The verdict vocabulary below is therefore worth keeping in the thesis: **TRACED
> to a retained file** and **STALE against the current generation** are different
> statements, and a number can honestly be both.


_Hand-written, not generated. `scripts/16_build_evidence.sh` does not touch this
file. Audit taken **2026-09-21** against the artefacts, CSVs and run bundles then
on disk, at commit `7402b0a`, catalogue **40 modules**._

---

## Scope and method

Documents walked, in full:

| document | last changed | size |
|---|---|---:|
| `ARCHITECTURE.md` | 2026-09-20 | 76 174 B |
| `EVOLUTION.md` | 2026-09-03 | 19 775 B |
| `docs/STATE_OF_PLAY_2026-09-18.md` | 2026-09-19 | 14 861 B |
| `README.md` | 2026-08-22 | 1 115 B |

**Inclusion rule.** A row exists for every number, ratio, count or percentage
*asserted about the system*. Version strings (`22.04`, `5.15.0-185`), snapshot
IDs, dates, section numbers, script stage numbers and check numbers (V1–V8) are
excluded: they are identifiers, not measurements. Where one claim is repeated
verbatim in two places both lines are given on one row.

**Verdicts.**

- **TRACED** — a retained file contains this exact number.
- **STALE** — a retained file contains a *different* number for the same thing.
  Both are given, and which is newer.
- **UNTRACEABLE** — no retained file supports it; the source was overwritten or
  never kept. `JOURNAL.md` narrating a number does **not** make it TRACED:
  `JOURNAL.md` is a document, and the whole point of the audit is
  document-to-evidence, not document-to-document.

**A distinction the verdicts depend on.** Many numbers here are correct
*for the catalogue they were measured on* and wrong as statements about today.
Those are marked **TRACED (historical)** where the document labels its own
generation, and **STALE** where it does not. The difference is whether a reader
would be misled, not whether the arithmetic was ever right.

## Summary

Counted from the rows below (`scripts/16_build_evidence.sh` does not produce
this table; it was counted mechanically over this file and is reproducible by
grepping the verdict column).

| verdict | rows |
|---|---:|
| TRACED | 58 |
| UNTRACEABLE | 41 |
| STALE | 13 |
| split — part of the claim TRACED, part UNTRACEABLE | 10 |
| TRACED for its own generation, STALE as a current statement | 5 |
| TRACED (historical, and the document labels it as such) | 3 |
| context row, not a verdict | 1 |
| unresolved split | 1 |
| **total rows** | **132** |

Per document: README 5, STATE_OF_PLAY 27, PLAN 14, EVOLUTION 27,
ARCHITECTURE 59.

**Where the UNTRACEABLE rows come from.** The large majority describe catalogue
generations that no longer exist: the full rebuild of **2026-09-16** replaced
base and every module artefact in one day, so every figure measured against the
27-, 28- or 37-module catalogues is now unreconstructible except where a CSV of
that sweep was retained. The exceptions — measurements taken *after* the rebuild
that are still untraceable — are worth separating, because they are the ones
that could still be fixed by writing a file:

| untraceable, post-rebuild | where it is claimed | why |
|---|---|---|
| `869` opaque markers / `456` directories / `178` shared | STATE_OF_PLAY §2 | the xattr survey printed to a terminal; the `.upper` trees still exist, so it is re-runnable |
| `1 479` non-package-owned shared files and its 6-row breakdown | ARCHITECTURE §4 | same: the enumeration is defined and repeatable, the run wrote nothing |
| `7 of 37` modules with a divergent debconf database | ARCHITECTURE §4 | the per-module diff wrote nothing; the `231 of 666` that depends on it inherits the gap |
| `94.6 % / 38.1 % / 5.4 %` admissibility | ARCHITECTURE §6 | `sample_sets.py` computes it; no run output retained |
| `522` and `55` paths for the two GPU modules | ARCHITECTURE §7 | the `.files.json.zst` sidecars hold the data; the counts were never written out |
| `14` accounts created across the catalogue, all in range | ARCHITECTURE §4 | `06_extract_metadata.sh` audits this per module; no aggregate is retained |

---

## 1. `README.md` — last changed 2026-08-22

README is 1 115 bytes and asserts almost nothing numeric, so it contains almost
nothing that *can* be stale by number. Its staleness is structural, and the last
two rows record it as such.

| claim (verbatim) | document and line | supporting file | verified? |
|---|---|---|---|
| "Ubuntu 22.04, APT/dpkg, x86-64" | `README.md:3` | `config.sh` (`SUITE=jammy`, `ARCH=amd64`); every `*.json` manifest records `"suite": "jammy"`, `"arch": "amd64"` | **TRACED** |
| "`sudo ./scripts/01_build_base.sh` `# ~15 min`" | `README.md:25` | none | **UNTRACEABLE** — no build timing is retained. `/srv/modfs/logs/base-debootstrap.log` (2026-09-16 16:43) and `base-mksquashfs.log` (16:44) bracket only the final minute |
| "BSc thesis prototype" | `README.md:3` | none | **UNTRACEABLE** — no file in the repository records the degree level. Flagged rather than corrected; see `inconsistencies.md` I-23 |
| structural: five pipeline stages listed (`00`, `01`, `02`, `05`, `04`) | `README.md:14`, `24–29` | `scripts/` holds **17** stages, `00`–`16` | **STALE** — 5 of 17 |
| structural: layout omits `specs/uid-ranges.yaml`, `thesis/`, and the three verification tiers entirely | `README.md:12–20` | `specs/`, `thesis/`, `scripts/09`,`10`,`11` | **STALE** |

## 2. `docs/STATE_OF_PLAY_2026-09-18.md` — last changed 2026-09-19

| claim (verbatim) | document and line | supporting file | verified? |
|---|---|---|---|
| "Nine classes. Seven were designed" | `:23` | `ARCHITECTURE.md` §4 taxonomy table — 7 rows | **TRACED** |
| "classes 8 and 9 … are not yet in `ARCHITECTURE.md` §4" | `:24` | `ARCHITECTURE.md:104–111` — still 7 rows on 2026-09-21 | **TRACED** (still true; see `inconsistencies.md` I-06) |
| "Measured across 38 modules: **869 markers, 456 distinct directories, 178 claimed by two or more modules**" | `:53` | none | **UNTRACEABLE** — the xattr survey wrote no result file. The `.upper` trees still exist under `/srv/modfs/modules/*.upper`, so it is re-runnable, but the number as published is unsupported |
| "89 ms at N=2 → 398 ms at N=36" (tier-1 cost) | `:91` | none | **UNTRACEABLE** — no tier-1 timing CSV is retained. `ARCHITECTURE.md:499–501` independently says this fit predates correction H1 and "is not a performance claim about the corrected checker" |
| "148 + 27.2 ms × N" (tier-2 cost) | `:92`, `:163` | `/srv/modfs/results/tier2/compose-sweep-2026-09-18-pre-round2.csv` → refits to `148.286 + 27.200 N` (R²=0.974) | **STALE** — exact for that CSV, but the current sweep (`/srv/modfs/logs/compose-sweep.csv`, 2026-09-18 23:15Z) gives **175.2 + 30.55 N** (R²=0.975). The newer figure is the current one |
| tier-2 row labelled "Compose for real, **verify**" while carrying that fit | `:92` | same CSV: `total_ms = mount_ms + reconcile_ms` on 152/152 rows | **STALE** — the fit excludes verification. Verification is a separate column and fits `161.3 + 41.80 N` |
| "~3 min" (tier-3 cost) | `:93` | 16 bundles with a `duration_s` in `/srv/modfs/results/boot/*/result.json`: 119, 170, 183, 189, 191, 194, 198, 199, 204, 232, 284, 316, 324, 330, 331 s (plus one 3 s and one 2 142 s abort) | **STALE** — completed runs span 183–331 s; "~3 min" describes the lower half only |
| "703 pairs, **ACCEPT 630 / REJECT 73**" | `:157` | `/srv/modfs/results/review-fixes-2026-09-18-{before,after}/combinations.csv` — 703 rows, 630 ACCEPT / 73 REJECT, 38 distinct modules | **TRACED** for the 38-module catalogue, **STALE** as current: today's 40-module sweep is **780 pairs, 667 / 113** |
| "matches an independent combinatorial prediction" | `:157` | `thesis/evidence/tier1.md` T1.5: predicted C(39,1)=39 and C(39,2)=741 control-bearing sets, observed 39 and 741 | **TRACED** |
| "152 compositions, N=2→36, **152 PASS**" | `:158` | `/srv/modfs/results/review-fixes-2026-09-18-before/compose-sweep.csv` — 152 rows, N=2…36, 152 PASS | **TRACED** for that generation, **STALE** as current: the live sweep is 152 compositions **N=2→38** |
| "36 probes pass under systemd; only `apache2.service` fails (class 8)" | `:159` | `/srv/modfs/results/boot/probes-20260918T123806Z/serial.log` — 36 `MODFS PROBE … PASS`, 0 FAIL, one `MODFS failed-unit apache2.service` | **TRACED** |
| "Smoke: 75 passed, 0 failed at N=37" | `:160` | `/srv/modfs/results/review-fixes-2026-09-18-after/evidence/final-smoke-clean-env.log` — "RESULT: 75 passed, 0 failed, 1 skipped" | **TRACED**. Note the N convention: that log's set is `base` + **36** modules and it reports "36 probe(s) executed", so "N=37" counts layers while tier 2's N counts modules. See `inconsistencies.md` I-17 |
| (the same run, uncorrected environment) | — | `…/evidence/final-smoke.log` — "74 passed, 1 failed, 1 skipped / BROKEN" | context for the row above: the failing probe is `rust`, failing on a missing `TMPDIR`, i.e. the harness. Both logs are retained and the clean-env one is the claim's source |
| "`v7_attacks.py` 4/4" | `:161` | `…/evidence/final-v7.log` — "4/4 cases correct" | **TRACED** |
| "`round2_attacks.py` 11/11" | `:161` | `…/evidence/final-round2.log` — "11/11 cases correct" | **TRACED** |
| "5.59× small / 1.32× large / **2.51× whole catalogue**" | `:162` | `thesis/evidence/storage.md` S5 reconstructs the 38-module catalogue from today's artefacts and recovers 5.59× / 1.32× / 2.51× exactly | **TRACED** for 38 modules, **STALE** as current: **5.59× / 1.20× / 1.84×** at 40 |
| "server-side **−24.1 %**" (base fattening) | `:165` | `/srv/modfs/results/fatbase/fatbase-analysis-2026-09-17T163305Z.txt` — whole catalogue 1 023.8 MB thin → 777.2 MB fat = −24.08 % | **TRACED**, at the **38-module** catalogue; the line does not say so |
| "*no single-module node can ever win*" | `:165–167` | same file, BREAK-EVEN §(1): "modules whose own saving exceeds dB: NONE; best single module: gcc saves 69.6 MB against dB 113.5 MB" | **TRACED**, 38-module catalogue |
| "`nvidia-driver-535` (231.6 MB stored) and `cuda-runtime` (680.2 MB stored)" | `:§7.9` | `/srv/modfs/modules/*.sqsh`: 231 550 976 B and 680 222 720 B | **TRACED** |
| "Both pass tier 1, tier 2 at every N up to 38, and a tier-3 UEFI boot" | `:§7.9` | `compose-sweep.csv` max N = 38; `results/boot/gpu-stack-20260918T231943Z/result.json` verdict PASS | **TRACED** |
| "a decoy symlink replaced 1 MB with 5 bytes, `vis_ok=1`" | `:122` | none | **UNTRACEABLE** — the defect is reproduced by `tests/v7_attacks.py`, but no artefact of the original failing run is retained |
| "a published number was wrong: 42 where the truth was 10" | `:129` | `/srv/modfs/results/tier2/compose-sweep-2026-09-18-pre-round2.csv` sample 1 (`base nc-traditional rust`) → `alt_groups=42`; `/srv/modfs/results/gpu-2026-09-19/logs-before/compose-sweep.csv` sample 1, same set → `alt_groups=10` | **TRACED**, both halves, in two retained files |
| "180 s wasted per run" | `:138` | none | **UNTRACEABLE** |
| "4319 bytes → 419" (mount-data ceiling) | `:139` | none | **UNTRACEABLE** |
| "Nine probes 'failed'; all nine were the harness" | `:140` | none | **UNTRACEABLE** |
| "republish **666 stale result files** as a fresh run" | `:144` | none | **UNTRACEABLE**. 666 = C(37,2), consistent with a 37-module catalogue, but no such CSV is retained |
| "the catalogue held exactly 27 usable modules … grew to 37 … only 38 % of draws are admissible" | `:147` | `ARCHITECTURE.md:528–530` gives 38.1 % at N=27 | **UNTRACEABLE** — document-to-document only; `sample_sets.py` can recompute it but no run output is retained |

## 3. `thesis/PLAN.md` — last changed 2026-09-19

PLAN.md is not one of the four documents named for the walk, but every line of
its chapter-6 list is a quantitative claim that will become thesis text, and two
of them are the most load-bearing errors found. Audited in full.

| claim (verbatim) | document and line | supporting file | verified? |
|---|---|---|---|
| "conflict taxonomy: 9 classes, 2 discovered by running the system" | `:19` | `docs/STATE_OF_PLAY_2026-09-18.md` §2 | **TRACED** to a document; `ARCHITECTURE.md` §4 still lists 7 (I-06) |
| "tier 1: 703 pairs, ACCEPT 630 / REJECT 73" | `:20` | `results/review-fixes-2026-09-18-*/combinations.csv` (38 modules) | **STALE** — current is 780 / 667 / 113 at 40 modules |
| "10,660 combinations at higher N" | `:21` | `/srv/modfs/logs/combinations-gpu-full.csv` — **10 660 rows total**, of which **780 are pairs and 9 880 are triples** | **STALE** — the higher-N count is 9 880; 10 660 is the total. Also: this figure is from the **40-module** catalogue while "703 pairs" on the line above is from the **38-module** one, so the two halves of one sentence describe different catalogues |
| "tier 2: 152 compositions, N=2→38, V1–V8 clean" | `:22` | `/srv/modfs/logs/compose-sweep.csv` — 152 rows, N=2…38, every V column clean | **TRACED** |
| "tier 3: boots, **0 failed units**, per-unit causal matrix" | `:23` | `thesis/evidence/tier3.csv` — every completed 36-module run records `failed_units = apache2.service`; the two-webserver runs `m3`/`m4` likewise | **STALE** — contradicted. 0 failed units holds only for single-webserver and GPU-stack runs |
| "storage: 5.59× / 1.20× / 1.84× (40 modules)" | `:24` | `thesis/evidence/storage.md` S1 | **TRACED** |
| "with the monolithic baseline **rebuilt like-for-like**" | `:24–25` | `storage.md` S2 — 6 real monolithic builds of 40; the other 34 are modelled `B + d` | **STALE** — overclaim. See `storage-resolution.md` §4 and `inconsistencies.md` I-14 |
| "and the model validated against 6 measured monoliths" | `:25` | `storage.md` S2 — `curl`, `emacs`, `jq`, `nc-traditional`, `pytools`, `webserver`, model 0.25–0.95 % high | **TRACED** |
| "cost: compose **148 + 27.2 ms × N**" | `:26` | `results/tier2/compose-sweep-2026-09-18-pre-round2.csv` | **STALE** — current is 175.2 + 30.55 N |
| "verify **161.3 + 41.8 ms × N**" | `:26` | `/srv/modfs/logs/compose-sweep.csv` → 161.3 + 41.80 N (R²=0.961) | **TRACED** — and note the two halves of this one line come from **different sweeps**: the compose fit is the 18 September generation, the verify fit the 19 September one |
| "base fattening: server-side −24.1 %" | `:27` | `results/fatbase/fatbase-analysis-2026-09-17T163305Z.txt` | **TRACED**, at 38 modules, unlabelled here |
| "GPU: a 680 MB module … saves 5.8 %" | `:28` | `storage.md` S3 — `cuda-runtime` 680.2 MB, saving 5.8 % | **TRACED** |
| "…composes at the same per-layer cost" | `:28` | `ARCHITECTURE.md` §7 asserts it within the 19 September generation; `compose-sweep.csv` carries the rows but no retained per-module cost breakdown | **UNTRACEABLE as stated** — recomputable from the retained CSV, not recorded |
| "the verification findings: 20+ defects across three independent review passes" | `:29` | `docs/ASSESSMENT.md` (H1–H12, M1–M7 = 19), `docs/REVIEW_CODEX_2026-09-18.md`, `STATE_OF_PLAY` §5 (17 rows) | **TRACED** to documents, not to a result file |

## 4. `EVOLUTION.md` — last changed 2026-09-03

EVOLUTION is a phase history and most of its numbers are correctly presented as
belonging to a past phase. Those are **TRACED (historical)** where a retained
file still carries them and **UNTRACEABLE** where the generation is gone. Two
rows are wrong as written, not merely old.

| claim (verbatim) | document and line | supporting file | verified? |
|---|---|---|---|
| "**Result: 30 checks, 30 passed.**" | `:50` | none | **UNTRACEABLE** — `00_verify.sh` writes no retained output |
| "base 40 MB / 113 packages · webserver 21 MB / +42 · pytools 25 MB / +24" | `:67` | manifests: base 41 717 760 B / **113** pkgs, webserver 21 045 248 B / **42**, pytools 25 845 760 B / **24** | package counts **TRACED**; sizes are rounded and base is 41.7 MB, not 40 |
| "Against ~176 MB per module under the June design" | `:68` | none | **UNTRACEABLE** — the June prototype produced no retained artefact |
| "~5 000 files, **28 shared, 17 byte-identical, 11 differ**" | `:84` | none | **UNTRACEABLE** — `03_analyse_overlap.sh` is described in `ARCHITECTURE.md` §8 as a research tool "run once"; no output retained |
| "packages the catalogue lists : 137 / actually installed : 178 / INVISIBLE : 41" | `:108–110` | none | **UNTRACEABLE** |
| "**178/178, 0 invisible**" | `:121` | none | **UNTRACEABLE** for these exact figures. The modern equivalent is retained: `…/evidence/final-smoke-clean-env.log` records 391 packages for base + 36 modules |
| "why 27 versus 24?" / "three packages" | `:126`, `:132` | none | **UNTRACEABLE** |
| "one `apt-get full-upgrade` … **61 packages moved**" | `:153` | none | **UNTRACEABLE** |
| "**Result:** 351 pairs, **all ACCEPT.**" | `:249` | none | **UNTRACEABLE** — the pre-control 27-module sweep CSV is not retained. The earliest retained sweep is the 28-module `combinations-all.csv` |
| "**378 pairs → 350 ACCEPT, 28 REJECT** (27 control + 1 MTA pair)" | `:274` | `/srv/modfs/logs/combinations-all.csv`, n=2: 378 rows, 350 ACCEPT / 28 REJECT, `not_composable` in 27, `declared_conflict` in 1 | **TRACED**, every component |
| "Class 4 across **19 069 paths**: exactly **4 collisions**, all MTA" | `:277` | same CSV: one pair with `file_collision_suppressed = 4` | the **4** is **TRACED**; the **19 069** path count is **UNTRACEABLE** |
| "Calibrated **5.35×**" | `:291` | none reconstructible — the 28-module generation was overwritten on 2026-09-16 | **UNTRACEABLE**. The six-point calibration it rests on *is* retained (`storage.md` S2) |
| "all **3 654** pair and triple combinations" | `:302` | `combinations-all.csv` — 3 654 rows | **TRACED** |
| "not composable: 378 = 27 pairs + C(27,2)=351 triples" | `:308` | same CSV: `not_composable` in 27 pairs and 351 triples | **TRACED** |
| "declared conflict: 27 = 1 pair + C(26,1)= 26 triples" | `:309` | same CSV: 1 and 26 | **TRACED** |
| "REJECT triples: 376 = 351 + 26 − 1" | `:310` | same CSV, n=3: 376 REJECT | **TRACED** |
| alternatives table: `editor` 1→2, 126→140/140; `awk` 2→3, 114→119/119; `nc` 1→2, 114→117/117 | `:336–338` | none | **UNTRACEABLE** |
| "the linker cache went **107 → 140** … roughly **35** of webserver's libraries" | `:343–345` | none | **UNTRACEABLE** |
| "2 Version skew \| **0 across 378 pairs**" | `:391` | `combinations-all.csv`: **5** of the 378 pairs record `version_skew > 0` — `apache+control-oldsnap`, `control-oldsnap+curl`, `+dnsutils`, `+git`, `+pgclient` | **STALE / wrong as written**. The true statement is 0 among the 27 well-formed modules and 5 against the positive control, which is what `ARCHITECTURE.md:766–769` says |
| "6 Implicit base upgrade \| prevented, **0 across 28 modules**" | `:395` | `combinations-all.csv`: `base_drift = 0` on all 3 654 rows | **TRACED** |
| "**5.35×** storage reduction (measured, six-point calibration)" | `:397` | calibration **TRACED** (`storage.md` S2); the ratio's catalogue is gone | **split: UNTRACEABLE ratio, TRACED calibration** |
| "invisible packages … **41 → 0**" | `:399` | none | **UNTRACEABLE** |
| "taxonomy swept over **3 654** combinations" | `:399` | `combinations-all.csv` | **TRACED** |
| "Tier 2 has **four** compositions against tier 1's 3 654" | `:403` | none for the four; 3 654 **TRACED** | **split** |
| "**96 compositions** from N=2 to N=27" | `:416` | `/srv/modfs/results/tier2/compose-sweep-2026-09-17-uniform-sampler.csv` — 96 rows, N=2…27, but **81 PASS and 15 NOT_ADMITTED** | **STALE** — 96 rows, 81 compositions. `ARCHITECTURE.md:13–15` records the same correction: "It was 81" |
| "the methodology was wrong by **64×**: tier 2 costs **155 ms**, not the assumed **10 s**" | `:418–419` | none | **UNTRACEABLE** |
| "uid **103** / gid **104** to four different names" | `:438–439` | `ARCHITECTURE.md` §4 table; the four modules' manifests now carry disjoint windows (2700+), so the original numbers are no longer in any artefact | **UNTRACEABLE from artefacts** — the prevention erased the evidence. `/srv/modfs/logs/pairs-class7.csv` retains the *consequence*: 6 pairs with `identity_collision > 0` |
| "**Six of 351 pairs** are affected" | `:443` | `/srv/modfs/logs/pairs-class7.csv` — 378 pairs, `identity_collision > 0` in exactly **6** | **TRACED** |
| "one set booted, once" | `:468` | `results/boot/` — as of 2026-09-03, three PASS bundles (`m1`, `m2`×2) | **TRACED (historical)**; 6 PASS bundles exist now |

## 5. `ARCHITECTURE.md` — last changed 2026-09-20

ARCHITECTURE is canonical and is also the only document guarded by an automated
contract test (`tests/review_claims.py`, 7 assertions, passing as of
2026-09-21). It is correspondingly the most self-labelled document of the four:
nine of its historical figures carry their own generation marker.

### 5.1 §4 Conflict taxonomy

| claim (verbatim) | document and line | supporting file | verified? |
|---|---|---|---|
| "**6 of 351 ordinary pairs** rejected by class 7 — exactly the C(4,2) combinations" | `:162` | `/srv/modfs/logs/pairs-class7.csv` — `identity_collision > 0` in 6 of 378 | **TRACED** |
| "After: **0 of 666**, with all 14 accounts created across the catalogue landing in-range" | `:163–164` | `/srv/modfs/logs/pairs-v2.csv` and `t1.csv` — 666 pairs, 37 modules, `identity_collision = 0` throughout | the **0 of 666** is **TRACED**; the **14 accounts** figure has no retained audit output → **UNTRACEABLE** |
| "**Seven catalogue modules write accounts**, so **21 pairs were affected**" | `:176–177` | manifests with a non-empty `accounts.users`/`groups`: `docker`, `memcached`, `mta-msmtp`, `mysql`, `postgres`, `redis`, `tcpdump` = **7**; C(7,2) = **21** | **TRACED** |
| "the same **79 records**, none differing in content, different order, different sha256" (debconf) | `:206–208` | none | **UNTRACEABLE** |
| "Of ~5 000 files across two deltas: **28** appear in both, **17** byte-identical (391 KB duplicated), **11** differ" | `:238–239` | none | **UNTRACEABLE** |
| "**Result: 11 → 1.** Seven of the eleven are mechanical" | `:262` | `config.sh` `SQUASH_EXCLUDES` lists the 5 excluded paths; `reconcile.py` merges the 4 registries | structure **TRACED** to source, the counts inherit the UNTRACEABLE row above |
| "**7 of 37 modules** carry a debconf database that differs from base's — `docker`, `java`, `mta-msmtp`, `mta-nullmailer`, `mysql`, `postgres`, `webserver`" | `:286–288` | none | **UNTRACEABLE** — the per-module debconf diff wrote no result file |
| "so 21 pairs have two diverging copies and **231 of 666 pairs have at least one**" | `:288–289` | arithmetic on the row above: C(7,2)=21 and 666 − C(30,2)=666 − 435 = **231** | **TRACED as arithmetic**, conditional on the UNTRACEABLE "7 of 37" |
| "across all **39 artefact trees** and all **741 tree pairs** there are **zero (Name, field) disagreements** outside `Owners`" | `:289–291` | C(39,2) = 741 ✓ for base + 38 modules. `…/evidence/final-tier2.log` contains both figures | **TRACED** |
| "Of **1 479** such files: 252 handled / ~1 200 `dpkg/info` / 4 locks / 3 debconf / 1 leak / 1 `sources.list`" | `:312–321` | none | **UNTRACEABLE** — the enumeration wrote no result file. The components sum to 1 461, i.e. "~1 200" is doing the rounding |

### 5.2 §6 Evaluation methodology

| claim (verbatim) | document and line | supporting file | verified? |
|---|---|---|---|
| "jammy has ~65 000 binary packages, so pairs alone are ~2×10⁹" | `:469–470` | none | **UNTRACEABLE** — an external property of the archive, not measured here |
| tier 1 "**89 ms → 398 ms**", "152 sequential sets, before correction H1" | `:479` | none | **UNTRACEABLE (historical, labelled)** — the row's own scope column says it predates H1 |
| tier 2 "**203 ms → 1090 ms**", "round-2 table in §7" | `:480` | `/srv/modfs/results/review-fixes-2026-09-18-before/compose-sweep.csv` — N=2 mean total 203 ms, N=36 mean 1 090 ms | **TRACED (historical, labelled)** |
| tier 3 "**189–204 s**", "two N=36 runs" | `:481` | `maxsub-20260916T154758Z` 189 s and `maxsub-20260917T075714Z` 204 s | **TRACED** for the two named runs, **STALE** as a range: a third 36-module run (`probes-20260918T123806Z`) completed in **183 s** |
| "`total_ms` in the tier-2 CSV equals `mount_ms + reconcile_ms` on every row" | `:483` | `/srv/modfs/logs/compose-sweep.csv` — holds on 152/152 | **TRACED** |
| preserved CSV yields "`148.285629 + 27.200303 N`" | `:491–492` | `/srv/modfs/results/tier2/compose-sweep-2026-09-18-pre-round2.csv` — refit gives 148.286 + 27.200 | **TRACED** |
| round-2 CSV, SHA256 "`b383725ee699bde86ebeaba74ec344694e7e6e383233a772c3c17cf197fe64df`", yields "`160.696749 + 27.013002 N`" | `:492–496` | `/srv/modfs/results/review-fixes-2026-09-18-before/compose-sweep.csv` — **sha256 matches exactly**; refit gives 160.697 + 27.013 | **TRACED**, digest and fit both. This is the only claim in any document that ships its own verifiable digest |
| "Its historical sequential fit was `101 + 9.6 N` over 152 sets" | `:500` | none | **UNTRACEABLE (historical, labelled)** |
| "94.6 % admissible at N=2, 38.1 % at N=27 and 5.4 % at N=36" | `:528–530` | none | **UNTRACEABLE** — `sample_sets.py` can recompute; no run output retained |
| "`fake-cuda` is rejected against **35 of 36** siblings" | `:542` | `/srv/modfs/logs/combinations.csv` — today `fake-cuda` appears in 39 pairs and is rejected in **38**, all `module_relation` | **STALE** — correct for the 37-usable catalogue, now 38 of 39 |
| "In the 2026-09-17 run the two agreed on all **152** sets" | `:549` | `compose-sweep.csv` — `admitted = yes` on 152/152 | **TRACED** (weakly: the CSV records agreement, not the disagreement that did not occur) |
| "**40 modules — 39 usable plus the positive control**" | `:553–554` | `specs/modules.yaml` — 40 entries, one with a `snapshot:` override | **TRACED** |
| "39 usable modules is **741** ordinary pairs, **780** pairs including the control, and **9 880** triples" | `:555–556` | `combinations-gpu-full.csv` — 780 pair rows and 9 880 triple rows; C(39,2)=741 | **TRACED** |
| "It held 38 (37 usable) until 2026-09-19" | `:554–555` | `results/review-fixes-2026-09-18-*/combinations.csv` — 38 distinct modules; `pairs-v2.csv` — 37 | **TRACED** |
| "the largest admissible set is **38 of 39** and there are exactly **two** such sets" | `:562–564` | `compose-sweep.csv` — 2 samples at N=38, none higher | **TRACED** (the CSV confirms two were drawn, not that only two exist) |

### 5.3 §7 Current results

| claim (verbatim) | document and line | supporting file | verified? |
|---|---|---|---|
| "`base.sqsh` 40 MB / 113; `webserver.sqsh` 21 MB / +42; `pytools.sqsh` 25 MB / +24; stored **86 MB**" | `:581–584` | manifests give 113 / 42 / 24 packages ✓, and 41.7 / 21.0 / 25.8 MB | package counts **TRACED**; sizes **STALE** (base is 41.7 MB, stored is 88.6 MB). The block carries its own "Superseded" marker at `:588` |
| "Monolithic ≈ 252 MB (estimate …) → ~2.9×" | `:586–587` | none | **UNTRACEABLE (historical, labelled)** |
| 28-module table: base 41.7 / 28 deltas 215.0 / stored **256.7** / monolithic **1 373.9** / **5.35×** | `:599–603` | none reconstructible | **UNTRACEABLE (historical, labelled)** |
| "Median delta 1.6 MB; **11** are under 1 MB; the largest is `emacs-nox` at 37 MB" | `:605` | `emacs.sqsh` = 37.0 MB ✓ today; the median and the count of sub-1 MB deltas belong to the 28-module catalogue | `emacs` **TRACED**, the rest **UNTRACEABLE (historical)** |
| six-point calibration table: `nc-traditional` 41.6/42.0/+0.9 %, `jq` 41.9/42.3/+0.9 %, `curl` 43.0/43.4/+0.9 %, `webserver` 62.3/62.8/+0.8 %, `pytools` 67.4/67.6/+0.2 %, `emacs` 78.3/78.7/+0.5 % | `:614–621` | `thesis/evidence/storage.md` S2, recomputed from the `.sqsh` files — every figure reproduces | **TRACED**, all 24 numbers |
| "Per-module saving ranges from **53 %** (`emacs-nox`) to **over 99 %** (`nc-traditional`)" | `:626–628` | `storage.md` S3 — `emacs` 53.0 %, `nc-traditional` 99.4 % | **TRACED** |
| "naive: 137 listed / 178 real → 41 invisible; reconciled: 178/178" | `:633–635` | none | **UNTRACEABLE** |
| three reproducibility hashes: `base.sqsh` `06e105365b3c48d1`, `webserver.sqsh` `f918ba2c892ea642`, `pytools.sqsh` `eff7dbd83fe9710d` | `:653–657` | current manifests record `e4fbed70bb74f351`, `19b9a57b8ec407e0`, `c9e66c22e399732b` | **TRACED (historical, labelled)** — the block is headed "Historical reproducibility sample — 2026-08-22" and states "These are not hashes of the current artefacts". The 2026-08-22 artefacts are gone, so the hashes themselves are **UNTRACEABLE**; the *labelling* is correct |
| 38-module cohort table: 31 / 272.8 / 1 524.3 / **5.59×**; 7 / **792.8** / 1 043.1 / **1.32×**; 38 / 1 023.8 / 2 567.4 / **2.51×** | `:672–674` | `storage.md` S5 recomputes 5.59× / 1.32× / 2.51× exactly | **TRACED**, except the large-cohort stored figure, which recomputes to **792.7 MB**, not 792.8 (rounding of 792 743 936 B) |
| 40-module table: 31 / 272.8 / 1 524.3 / **5.59×**; 9 / 1 704.5 / 2 038.3 / **1.20×**; 40 / 1 935.6 / 3 562.5 / **1.84×** | `:684–686` | `storage.md` S1 — every figure reproduces | **TRACED** |
| "the two modules add **911.8 MB** to Σd and only 2·B = **83.4 MB** to the numerator" | `:691–692` | 231 550 976 + 680 222 720 = 911.8 MB ✓; 2 × 41 717 760 = 83.4 MB ✓ | **TRACED** |
| "over 99 % on `nc-traditional`, 96 % on `curl`, **15.3 %** on the driver and **5.8 %** on the CUDA runtime" | `:694–696` | `storage.md` S3 — 99.4 %, 96.2 %, 15.3 %, 5.8 % | **TRACED** |
| "a mean delta of **7.5 MB** gives 5.59×; a mean delta of **107.3 MB** gives 1.32×" | `:708–709` | computed: 231 038 976/31 = 7.45 MB; 751 026 176/7 = 107.29 MB | **TRACED** |
| "The seven large modules are **78 %** of all delta bytes" | `:710` | 751 026 176 / 982 065 152 = **76.5 %** at 38 modules; at **37** modules (Σd = 966 459 392) it is **77.7 %** | **STALE** — a 37-module figure standing in a 38-module paragraph |
| "Measured monolithic sizes come in **0.2–0.9 % below** the model across all six" | `:715–717` | `storage.md` S2 — 0.25 % to 0.95 % | **TRACED** (rounded inward at both ends) |
| "**53 packages appear in two or more** and **32 in three or more** (`gcc`+`rust` share 31, `gcc`+`llvm` 24, `llvm`+`rust` 23)" | `:726–728` | `/srv/modfs/results/fatbase/shared-packages-ge2.txt` — exactly **53** lines | the **53** is **TRACED**; 32 / 31 / 24 / 23 are **UNTRACEABLE** (not in the retained file) |
| "**378 pairs** of the 28-module catalogue, 9 s at `--jobs 8`: ACCEPT 350 / REJECT 28 / class 1 **60** / class 2 **5** / class 3 **1** / class 4 **0** (4 suppressed) / class 6 **0** / precondition **27**" | `:753–764` | `combinations-all.csv`, n=2: 350/28, benign_overlap in **60** sets, version_skew in **5**, declared_conflict in **1**, file_collision **0**, suppressed in 1 set (4 instances), base_drift **0**, not_composable in **27** | **TRACED**, every cell. The 9 s wall time is **UNTRACEABLE** |
| "**All 351 ordinary pairs were physically composed** … in **58.8 s** total (median **163 ms** each)" | `:771–772` | none — that sweep's CSV is not retained under any name | **UNTRACEABLE** |
| "tier 1 as it then stood admitted **350 and rejected 1**" | `:778` | `combinations-all.csv`: 378 pairs, 28 rejects, 27 of them control-bearing → 351 ordinary, 1 reject | **TRACED** |
| "class 7 rejects a further **6** pairs, so the same space is **344 admitted, 7 rejected**" | `:783–784` | `pairs-class7.csv`: 378 pairs, 34 rejects = 27 control + 1 MTA + 6 class-7 → 351 − 7 = 344 | **TRACED** |
| round-2 N table, 12 rows, N=2…36, `total ms` 203 → 1 090 | `:795–807` | `/srv/modfs/results/review-fixes-2026-09-18-before/compose-sweep.csv` | **TRACED (historical, labelled)** |
| "it published **42**, the true count is **10** (5 base + 1 nc-traditional + 4 rust)" | `:824–826` | `compose-sweep-2026-09-18-pre-round2.csv` sample 1 = 42; `gpu-2026-09-19/logs-before/compose-sweep.csv` sample 1 = 10; both are `base nc-traditional rust` | **TRACED**, both halves |
| "the union for `base java vim` is **46** and for `base mysql tmux` is **6**" | `:832–833` | none | **UNTRACEABLE** |
| "sample 151 … **527 package instances that collapse to 278 distinct** … **391 packages — exactly base's 113 plus those 278**" | `:857–860` | `review-fixes-2026-09-18-before/compose-sweep.csv` sample 151: n=36, `pkg_actual = 391` ✓; `…/evidence/final-smoke-clean-env.log`: "dpkg status : 391 packages" ✓; 113 + 278 = 391 ✓ | **391 and the arithmetic TRACED**; the 527/278 decomposition is **UNTRACEABLE** (not a CSV column) |
| "`total = 160.7 + 27.01 N` (R²=0.970), `mount = 18.9 + 8.03 N` (R²=0.972), `reconcile = 141.8 + 18.98 N` (R²=0.953)" | `:868–871` | refit of the preserved round-2 CSV: total 160.697 + 27.013, R²=0.970 | **TRACED** |
| "2026-09-02's 96-composition model was `115 + 18.8 N`" | `:865–866` | none | **UNTRACEABLE (historical, labelled)** |
| "`total = 175.2 + 30.55 N` (R²=0.975), `mount = 20.8 + 9.46 N` (R²=0.985), `reconcile = 154.4 + 21.09 N` (R²=0.958)" | `:882–884` | `/srv/modfs/logs/compose-sweep.csv` — refit gives 175.2 + 30.55 (0.9747), 20.8 + 9.46 (0.9845), 154.4 + 21.09 (0.9577) | **TRACED**, all six coefficients and all three R² |
| "**152 compositions, N=2→38, 152 PASS**, every V1–V8 column clean" | `:886` | same CSV | **TRACED** |
| "the two GPU modules contribute **522** and **55** paths despite being 232 MB and 680 MB" | `:897–898` | the `.files.json.zst` sidecars exist but the counts are not recorded in any retained result file | **UNTRACEABLE as published** — recomputable from the sidecars |
| "`verify = 161.3 + 41.80 N` (R²=0.961)" | `:906` | same CSV — 161.3 + 41.80, R²=0.9605 | **TRACED** |

### 5.4 §9 Tier-3 status

| claim (verbatim) | document and line | supporting file | verified? |
|---|---|---|---|
| "**Run A** — 26 modules — **did not boot.**" | `:1011` | no bundle in `/srv/modfs/results/boot/` has 26 modules | **UNTRACEABLE** — Run A left no retained bundle |
| "**Run B** — `base + webserver + apache` — is one successful UEFI/systemd boot in which … nginx started, Apache did not" | `:1018–1021` | `results/boot/m3-nginx-apache-20260903T080746Z/`: state `degraded`, `failed-unit apache2.service`, listeners `0.0.0.0:80 → nginx` | **TRACED** — and the bundle records `verdict: FAIL`, because an expected service failure is still a failed unit |
| "The GPU stack boots — 2026-09-19" | `:1073` | `results/boot/gpu-stack-20260918T231943Z/result.json` — `verdict: PASS`, state `running`, 0 failed units, 2/2 probes | **TRACED** |
| "**Nothing shows that CUDA computes: there is no GPU on this machine.**" | `STATE_OF_PLAY:§7.9` | no bundle records a GPU device **on `main`**; `experiment/noble-generation` (unmerged) retains `gpu-runtime/result.json` — GTX 1060 6 GB, compute 6.1, NVRTC 12.0, PTX 8.0, a 32-thread launch returning 7…38, three artefact library hashes traced to the manifest | **TRACED as a negative for `main`; being overtaken off-branch.** The branch is still running — hold this row until it finishes, then re-audit rather than merging the claim across on trust |

---

## 6. Two cross-cutting observations, stated as fact

1. **`tests/review_claims.py` guards `ARCHITECTURE.md` and nothing else.** All
   seven of its assertions read `ARCHITECTURE.md`; no test reads
   `EVOLUTION.md`, `README.md`, `MEETING.md`, `docs/STATE_OF_PLAY_2026-09-18.md`
   or `thesis/PLAN.md`. Every **STALE** row above outside §5 is in a document
   with no contract test. The two STALE rows inside §5 (`78 %`, `35 of 36`) are
   figures no assertion covers.

2. **One number in the corpus ships its own digest.** `ARCHITECTURE.md:494`
   quotes the SHA256 of the CSV it derives a fit from, and that digest verifies.
   No other quantitative claim in any of the four documents names a file *and* a
   digest; where a file is named at all, it is named without one.
