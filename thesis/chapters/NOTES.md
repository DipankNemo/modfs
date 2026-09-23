# Review, source, and completion notes

## Scope and overall assessment

This comprehensive review revises the first chapter pass against `thesis/rough/firstedit.txt`, the chapter plan, canonical architecture, reference documents, relevant implementation, dated journal, supplied papers, and the retained evidence. The earlier pass was too compressed: it omitted useful evaluation tables and the base-sizing model, and several qualifications were inaccurate. All eight chapters have now been deepened, with Introduction written last and one review commit per chapter.

Only `thesis/chapters/` was changed. Code, source documents, bibliography, and `thesis/evidence/` were left untouched. No catalogue rebuild, physical sweep, boot, or evidence regeneration was performed. Existing tests using temporary fixtures were run to corroborate specific mechanism claims, not to create new thesis evaluation results.

The evidence is a retained snapshot generated on 22 September 2026. “Current” in the chapters means current within that snapshot's inventory and freshness checks. It does not mean that every result was repeated during this writing review. Dates, package versions, script identifiers, record field values, and configuration constants are distinguished from experimental measurements.

## Major corrections to the earlier chapter pass

| Finding | Correction and source |
|---|---|
| Tier 2 was described as a separate “39-module generation.” | The 39 are distinct covered deltas, excluding the incompatible control from the 40-module catalogue. The sweep is historical because later artefacts were rebuilt. `scripts/16_build_evidence.sh`, `build_tier2`; `thesis/evidence/provenance.md`; September 21 round-three journal. |
| Evaluation had become a summary of results. | Restored the admission census and causes, overlap conditions, sample sizes and timings, V predicates, fits, cohorts, all per-module sizes, sensitivity, measured calibration, and selected boot matrix. Each table cites its evidence file. |
| The headline comparison could be read as six measured baselines plus 34 modelled ones. | Every headline monolithic value is computed as $B+d$. Six actual monoliths calibrate the model; their measured values are not substituted into the total. `storage.md` S1–S2 and its CSVs. |
| Calibration error was described as the same percentage error in savings. | The reported 0.25–1.34% is monolithic baseline-size overestimation. Its effect on a saving fraction differs and cannot be extrapolated as a confidence interval to the large payloads. |
| Benign-overlap counts could be read as accepted-set counts. | They count sets with a non-rejecting condition, even when another condition rejects the set. Rejection-class columns also overlap. `tier1-measured.csv`; `tier1-classes.csv`. |
| Module relations were conflated with virtual-provider conflicts. | Missing module requirements and declared module incompatibilities are distinct from package-level virtual-provider conflicts. The admitted non-monotone triples illustrate missing-provider completion. `tier1-nonmonotone.csv`. |
| A clean V1–V8 result was too broadly characterized. | V1 in the evidence is inferred from positive reconciliation time. V4 checks inclusion of expected layer SONAMEs. V7 does not compare regular-file content. Historical results cannot inherit later verifier repairs. |
| All review defects were characterized as checker/harness defects. | September 22 round-four fixtures also demonstrate merger defects, including primary-GID conflict and discarded partial diversion records. These are not demonstrated failures of the published catalogue compositions. The central finding is the limited observation of the clean sweep, not absence of merger bugs. |
| Every `FIXED` fixture was said to require rejection. | Some fixes require successful normalization or merging; others require rejection. Passing `KNOWN OPEN` fixtures confirm the limitation remains. `tests/round4_attacks.py`; `tests/round2_attacks.py`. |
| The historical base-fattening result was omitted. | `claims.md` does trace it: 38-module repository storage 1,023.8 → 777.2 MB, approximately 24.1% reduction. Discussion restores the repository, selected-set, and fleet equations with explicit additive-model limits. |
| Literature was cited generically. | Related Work now recognizes opaque-marker semantics as union-filesystem prior art and physical file-conflict analysis as an EDOS/Mancoosi precedent. Nix input-derived identity is distinguished from output hashing; NixOS's mutable-state and impurity boundaries are acknowledged. |

The earlier NOTES also incorrectly attributed already-corrected “rebuilt like-for-like” and “zero failed units” wording to the present `thesis/PLAN.md`. Those statements appear in the historical claims audit, but the present plan already qualifies them. Its remaining stale statements are listed below.

## Measurement limits and missing evidence

### Physical composition and boot

`thesis/evidence/tier2.md` deliberately emits **NO TABLE** because the retained sweep predates rebuilt artefacts. Its companion CSV summaries remain available and are used only as historical observations. Their presence does not mean the generator freshly recomputed them after withholding the Markdown table. A new composition sweep followed by evidence regeneration is required to make current physical pass-rate and cost claims.

Tier 2's `total_ms` measures mount plus reconciliation, not verification. The corrected source locator is `inconsistencies.md` **I-11**. The historical same-sweep fits sum to $336.5+72.35N$ ms for compose plus verify; no combined $R^2$ is supplied. Planning, teardown, and other untimed work cannot be assumed included. The requested numerical tier-gap factors are not published: `claims.md` marks the retained Tier-1 timing claim untraceable, and there is no compatible current Tier-1 timing CSV from which to derive them.

The boot snapshot contains 20 bundles but only two not marked superseded, both GPU-stack runs: one aborted and one passed. Historical web-server and high-layer runs support the Class-8 mechanism, not a present full-catalogue reliability percentage. `starting` must not be silently rewritten as `running`, and passing probes must not erase an Apache failed unit. Harness changes and rebuilt inputs also prevent treating the high-layer sequence as repeated trials of one fixed system.

The September 22 Noble-branch audit records a historical mismatch between retained Jammy manifests and a newly required generation field. This must not be carried forward as an assertion that the later refreshed catalogue still lacks it. The base and curl manifests accessible during this review contain `generation`; this limited inspection is not a replacement for full bundle validation. The relevant thesis lesson is to retain checker revision and schema identity with measurements.

### Reproducibility, review counts, and GPU scope

The requested **0 of 40 matching archives** comparison exists in `docs/evidence/remote-verification-2026-09-20/REPORT.md`, outside the authorized numerical source directory. It is not a nonexistent experiment. Its cross-machine comparison table needs incorporation into `thesis/evidence/` before use as a numerical thesis result under the brief's rule. Discussion describes its mechanisms qualitatively and states the confounds: builder, specification, host-tool, and bootstrap differences accompanied the machine change. “Every difference is diagnosed” is too strong if read as a complete causal explanation of every byte; the report leaves some generated-state details unresolved.

`claims.md` repeats “20+” review defects across an earlier three-pass account as a trace to narrative documents. It is not a deduplicated result inventory for the brief's four-pass claim. The later merger findings also change the classification of those defects. The chapters retain the qualitative finding and concrete counterexamples; they do not substitute the 29 documentation inconsistencies for implementation defects. The requested whole-repository complexity audit, approximately 215 cuttable lines out of 10,699, has no retained supporting audit in the permitted evidence. A low proposed deletion fraction would in any event require the audit's criteria before supporting a general claim that complexity is justified.

GPU experiments have distinct identities. The local generated boot table establishes a guest boot without GPU access. The independent remote report describes real userspace computation using a provider driver. The GTX 1060 work belongs to `experiment/noble-generation`, with its own userspace artefact and existing host driver. The later September 22 audit records a completed replacement for its interrupted sweep, although the branch remained unmerged; the earlier “still running” narrative is not its final status. The packaged ModFS kernel driver has not been demonstrated driving a GPU. Its load/link/initialization report stops at hardware enumeration. These findings are kept separate rather than combined into one hardware-validation claim.

### Storage and deployment

The current small-cohort ratio is 5.43× following the spec-faithful `jq` rebuild. The brief and older `claims.md` status text say all historical storage ratios reproduce exactly, but the current `storage-published-reconciliation.csv` contains **differs** rows. Later artefact changes mean even selecting an old catalogue's module names does not reconstruct its exact old bytes. Historical figures remain historical where their original trace survives.

The fat-base audit supplies a historical base increment of 113.5 MB and greatest individual delta saving of 69.6 MB. These justify the single-module break-even conclusion only for that experiment's additive layer-size model. The rough draft's hypothetical fat-base sum double-counted potentially shared dependencies and assumed residual sizes without rebuilding. Its transfer equation `1 - 7.5/49.2 = 0.7987` is also arithmetically wrong: that expression is about 0.8476. More fundamentally, neither an old average nor corrected arithmetic measures the implemented whole-image node transfer. No numerical node-transfer saving is retained.

A transactional publisher, remote update client, measured fleet migration, rollback rehearsal, and application-data compatibility test remain absent. The chapters describe those as future work. A server-side storage ratio cannot establish them.

## Source and implementation disagreements left outside the edit scope

| Location | Disagreement or gap | Chapter treatment |
|---|---|---|
| `ARCHITECTURE.md` §2 central claim | Reducing the whole conflict problem to package metadata overstates the architecture's own registry, identity, marker, and runtime mechanisms. | Introduction states a conditional engineering claim rather than a complexity theorem. |
| `docs/DATA_MODEL.md`, digest table | Calls `binding.sidecar_sha256` a digest of `.files.json.zst`; canonical architecture and code hash decompressed JSON bytes. | Implementation names the actual byte boundary. |
| `docs/DATA_MODEL.md`, digest rationale | Explains the sidecar requirement as if hashing a digest were inherently impossible. | The issue is required schema coverage and excluding `binding` from the selected field payload. |
| `docs/RUNBOOK.md`, base construction | Says retained `base.dir` supplies each lowerdir. Canonical architecture requires the exact mounted `base.sqsh`. | Implementation uses the canonical exact-parent requirement. |
| `docs/REGISTRY_FORMATS.md`, status key; `reconcile.py::merge_status` | Required format identity is package plus architecture; code indexes status by package name. | Multiarch support is not claimed. This is an implementation gap relative to the reference model. |
| `docs/REGISTRY_FORMATS.md`, diversion key; `reconcile.py::merge_diversions` | Reference key is original path; code deduplicates complete triples without separately arbitrating different triples at one original path. | Malformed-record rejection is distinguished from complete conflict handling. |
| `docs/REGISTRY_FORMATS.md`, alternatives conflict | Higher priority can be retained after detecting contradictory priorities. | That is scratch output with a nonzero result, not an accepted resolution. |
| Registry and account descriptions | Manual APT marks can be implicit; nested missing owner metadata can produce warnings rather than rejection. | Explain inherited state and distinguish fully checked acceptance from `ACCEPT WITH WARNINGS`. |
| Whiteout representation versus builder policy | SquashFS can preserve deletion markers; the current opaque-stripping builder rejects whiteout-bearing upperdirs. | No arbitrary-removal guarantee is inferred from representation support. |
| `docs/SAMPLING_AND_BOOT.md` and boot narrative | Reusing reconciliation does not make packing an unchanged tree: kernel and harness inputs are added. | Separate composition, packing, and observed guest behavior. |
| `storage.md` S2 | Its “34 modelled and 6 measured” sentence is ambiguous beside its explicit all-module formula. | Headline model and independent calibrators are reported separately. |
| `thesis/PLAN.md` | Still carries 5.59× and older calibration errors, an unbound-manifest limitation, a broad no-GPU-compute statement, an unsupported equal-per-layer GPU cost claim, and “current” physical results now stale. | Evidence and later canonical mechanism/history govern the chapters. |

The code/reference disagreements above are not resolved by treating code as the design authority. The chapters state the intended contract and the narrower implementation separately, as required by the brief. Corrections outside the chapter directory remain follow-up work.

## Figures and document completion

| Figure | Available source or remaining work |
|---|---|
| 4.1 architecture | Mermaid schematic from canonical architecture; no measurement implied. |
| 6.1 admission | `tier1-totals.csv` plus `tier1-classes.csv`; totals and overlapping causes need separate panels. |
| 6.2 physical cost | Historical `tier2-by-n.csv` and `tier2-fit.csv`. Raw-point scatter or uncertainty bands need retained row/dispersion data; a current plot needs a new sweep. |
| 6.3 module storage | `storage-per-module.csv`; state that marginal saving assumes the base is already held. |
| 6.4 cohorts and sensitivity | `storage-cohorts.csv` and `storage-sensitivity.csv`; monolith column is modelled. |
| 6.5 boot matrix | `tier3.csv`; label freshness and retain missing/aborted categories for a full-history view. A current causal matrix needs new boots. |

The data figures are captioned drawing specifications, as requested, rather than fabricated plots. The former draft's appendix promises, institution-specific disclosure, signed declaration, and final typesetting are not created by these chapter files. No unsupported institutional requirement is inferred from the draft alone.

## Bibliography and primary-source checks

All citation keys used in the chapters exist in `thesis/refs/refs.bib`. Related Work was checked against supplied primary-paper extracts, with `thesis/refs/NOTES.md` used as a guide rather than a substitute for the load-bearing passages. No long quotations or unsourced cross-system performance numbers were retained.

Several bibliography details still need correction outside this task's allowed files:

- `debian-policy-diversions` labels §3.9 of the binary-packages chapter “Diversions.” The relevant official text is the [diversions appendix](https://www.debian.org/doc/debian-policy/ap-pkg-diversions.html). Background instead cites the existing `man-dpkg-divert` key.
- Kernel entries label Linux 5.15 but link to `latest`. This review checked the versioned [OverlayFS](https://www.kernel.org/doc/html/v5.15/filesystems/overlayfs.html) and [SquashFS](https://www.kernel.org/doc/html/v5.15/filesystems/squashfs.html) documentation. Their stable URLs should be reflected in the bibliography.
- The OCI entry mixes a consultation year and version label without a versioned URL. The layer comparison was checked against [OCI image-spec v1.1.0](https://raw.githubusercontent.com/opencontainers/image-spec/v1.1.0/layer.md).
- Debian Policy's live page no longer represents the bibliography's pinned version. Generic relation semantics were checked, but the version/URL pairing needs archival verification. Manual-page package versions also retain the bibliography's own verification warning.
- Pendry's page range remains missing, and the unused UEFI entry still has a version placeholder. These were not silently filled in.

Project comparisons were additionally checked against official [OSTree](https://ostreedev.github.io/ostree/introduction/), [SOURCE_DATE_EPOCH](https://reproducible-builds.org/specs/source-date-epoch/), [BAAS](https://github.com/baas-project/baas), [Ironic](https://docs.openstack.org/ironic/latest/), and [MAAS](https://canonical.com/maas/docs/stable/) sources. The thesis retains the existing bibliography keys for these claims.

## Validation performed during this review

- Mechanically compared the numerical rows of Evaluation tables 6.2–6.5 and 6.8–6.12 with their CSVs; checked table 6.7 against the fit CSV and table 6.6 against its recorded outcomes and implementation predicates.
- Checked citation-key existence, explicit source-path existence, table column counts, heading structure, code/equation fence balance, and `git diff --check`.
- Ran `tests/round4_attacks.py`: 16 tests passed; `tests/round4_class7.py`: five tests passed; `tests/round2_attacks.py`: 11 expected cases passed, including the still-open equal-size substitution and sparse-file cases. These are review validation results, not new catalogue measurements.
- Checked that review changes are confined to `thesis/chapters/`, with separate chapter commits. No evidence was regenerated.

A typeset PDF was not built: Pandoc is unavailable in this environment, and the requested deliverable is Markdown chapters. Citation rendering and final university-template layout therefore remain untested.
