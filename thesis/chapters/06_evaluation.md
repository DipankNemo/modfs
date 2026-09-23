# 6 Evaluation

## 6.1 Research questions and experimental method

The evaluation follows the system from package metadata to a running machine. RQ1 asks which conflicts can be identified or reconciled, RQ2 asks what server repository storage is saved, and RQ3 asks how much the verification tiers establish about the delivered system. These questions require different experiments: a census of selected package combinations, a sample of physical compositions, a storage inventory with monolithic calibration, and a causal boot matrix. A result from one experiment is not a substitute for the others.

All measurements below are taken from the retained `thesis/evidence/` snapshot documented in `provenance.md`, generated on 22 September 2026. Here, **N counts sibling deltas, excluding the shared base**. The current catalogue has 40 entries: 36 real workloads, three synthetic modules, and one deliberately incompatible control (`catalogue.md`). The control is counted in admission and storage; it is excluded from ordinary physical composition. The large storage cohort comprises `cuda-runtime`, `nvidia-driver-535`, `rust`, `java`, `llvm`, `gcc`, `docker`, `postgres`, and `mysql`. The other 31 entries form the small adversarial cohort (`catalogue.md` C2; `storage.md` S1). “Large realistic” describes the declared workload types, not statistical representativeness. The catalogue was assembled to exercise conflict mechanisms.

### 6.1.1 Measurement identity and freshness

| Evidence family | Population and identity | Interpretation |
|---|---|---|
| Static admission | Current 40-module catalogue; `tier1.md` and `tier1-*.csv` | Exhaustive pairs and triples at the retained evidence snapshot. |
| Physical composition | Retained 152-row sweep; 39 distinct deltas covered; `tier2-*.csv` | Historical measurements, superseded by later artefact rebuilds. |
| Storage | Current 40-module artefact inventory; `storage.md` and `storage-*.csv` | Compressed repository sizes and a calibrated model of monoliths. |
| Boot | 20 retained bundles; `tier3.md` and `tier3.csv` | A history of selected sets, with per-bundle freshness and verdicts. |

Table 6.1: Evidence populations. Sources: `thesis/evidence/provenance.md`, `tier1.md`, `tier2-fit.csv`, and `tier3.md`.

The number 39 in the tier-2 provenance row counts distinct deltas appearing in the CSV. It is compatible with coverage of the 40-module catalogue after excluding `control-oldsnap`; it does **not** identify a separate 39-module catalogue or an exact parent generation. The evidence generator derives this count from module names and explicitly treats the control's exclusion as intentional (`scripts/16_build_evidence.sh`, `build_tier2`). The reason this sweep is historical is different: its recorded timestamp precedes rebuilt artefacts. Accordingly, `tier2.md` withholds a current table while the companion CSV summaries retain the older results. They are used below with that qualification.

The generated summaries do not provide a complete timing environment, repetitions under controlled host load, or residual distributions. The regression results therefore describe this retained sweep, not a hardware-independent performance guarantee. They also predate later verifier changes. The boot table reports machine observations separately from harness failures and missing observations.

## 6.2 Tier 1: exhaustive static admission

### 6.2.1 Verdicts and overlapping causes

The sweep evaluates every pair and triple of the 40-module catalogue. Its cardinalities follow directly from $\binom{40}{2}=780$ and $\binom{40}{3}=9,880$.

| N | Sets | ACCEPT | REJECT |
| --- | --- | --- | --- |
| 2 | 780 | 667 | 113 |
| 3 | 9880 | 7807 | 2073 |

Table 6.2: Tier-1 census for the 40-module catalogue. Source: `thesis/evidence/tier1-totals.csv`.

| N | Version skew | Declared conflict | File collision | Identity collision | Module relation | Base upgrade | Not composable |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 2 | 7 | 1 | 0 | 0 | 75 | 0 | 39 |
| 3 | 245 | 38 | 0 | 0 | 1370 | 0 | 741 |

Table 6.3: Rejection conditions observed in the same census. Source: `thesis/evidence/tier1-classes.csv`. Columns overlap: a set can violate several conditions.

The module-relation column includes unsatisfied requirements as well as declared module incompatibilities. It is broader than conflicts between virtual-package providers. In particular, an unsatisfied CUDA-to-driver requirement is not the same condition as mutually incompatible mail providers. Version-skew and composability counters also describe different checks, even when a set triggers both. The lack of file-collision, identity-collision, or base-upgrade rejections is evidence about this built catalogue and these predicates. It does not establish that arbitrary package installations cannot construct those failures.

### 6.2.2 Positive control and non-monotonic admission

`control-oldsnap` uses a different archive snapshot and must be refused with every ordinary sibling. There are $\binom{39}{1}=39$ pairs and $\binom{39}{2}=741$ triples containing it; all are flagged not composable (`tier1-control.csv`). These counts are sets with a positive flag, not the sum of diagnostics within a set. The control rules out an all-accept implementation but does not exercise every rejection predicate.

The cross-check in `tier1-crosscheck.csv` finds 2,145 triples containing a rejecting pair. Of these, 2,073 are rejected and 72 admitted; no rejected triple is unexplained by an inner rejecting pair. The accepted exceptions all concern module relations (`tier1-nonmonotone.csv`). If a pair lacks a required driver module, adding that driver can complete the requirement. This does not mean that adding a provider repairs a genuine declared incompatibility between two already present packages. It means that “this selected set lacks something” is not a monotone exclusion rule.

The cross-check compares outputs within the admission experiment. It is a useful consistency test, but it is not an independent filesystem oracle or a proof of the checker's completeness. The physically sampled sets must still pass the authoritative admission checker rather than relying on exclusions inferred from pair counts.

### 6.2.3 Benign overlap and collision suppression

| N | Sets with benign overlap | Overlap instances | Sets with suppression | Suppressed instances |
| --- | --- | --- | --- | --- |
| 2 | 168 | 667 | 1 | 4 |
| 3 | 4585 | 25346 | 38 | 152 |

Table 6.4: Non-rejecting overlap conditions in the 40-module census. Source: `thesis/evidence/tier1-measured.csv`.

The counts show how often benign overlap or a sanctioned replacement/diversion occurs. They are not a count of wholly accepted sets: a set with harmless overlap can still be rejected for a different reason. Nor do path-instance counts directly quantify duplicated storage bytes. They establish that the checker distinguishes permitted overlap from a rejection condition.

Figure 6.1: Admission totals and overlapping rejection conditions for the 40-module pair and triple census. Source: `thesis/evidence/tier1-totals.csv` and `thesis/evidence/tier1-classes.csv`. Use separate panels for verdict totals and rejection conditions; the latter must not be stacked into an apparent partition.

## 6.3 Tier 2: physical compositions and their cost

### 6.3.1 Sample and structural observations

The retained sweep contains 152 compositions across 39 covered deltas, excluding the control. Table 6.5 gives the breakdown by layer count. Higher-order compositions are sampled rather than exhaustively enumerated: the sampler respects known constraints, resolves requirements, and submits every proposal to Tier 1 (`docs/SAMPLING_AND_BOOT.md`). At small enumerable spaces its draw is uniform over admissible sets; its larger-space seeded heuristic is not uniform. The aggregate tables do not preserve enough sampling detail to estimate population-wide failure probabilities.

| N | Samples | Installed packages | Mount ms | Reconcile ms | Compose ms | Verify ms |
| --- | --- | --- | --- | --- | --- | --- |
| 2 | 30 | 117–178 | 39 | 192 | 231 | 245 |
| 3 | 30 | 120–187 | 50 | 206 | 256 | 277 |
| 5 | 20 | 131–216 | 68 | 258 | 325 | 381 |
| 10 | 10 | 174–271 | 122 | 389 | 512 | 550 |
| 15 | 10 | 224–300 | 161 | 496 | 658 | 783 |
| 20 | 10 | 225–346 | 204 | 599 | 803 | 1034 |
| 25 | 10 | 302–371 | 253 | 711 | 964 | 1243 |
| 27 | 10 | 325–378 | 277 | 744 | 1021 | 1349 |
| 30 | 10 | 334–376 | 296 | 767 | 1063 | 1372 |
| 33 | 6 | 362–390 | 334 | 806 | 1139 | 1482 |
| 35 | 4 | 383–403 | 362 | 844 | 1207 | 1601 |
| 38 | 2 | 401–408 | 408 | 952 | 1360 | 1730 |

Table 6.5: Historical composition sample and mean durations. Source: `thesis/evidence/tier2-by-n.csv`. N excludes base; durations are milliseconds. The 39 covered deltas do not include the intentionally incompatible control. Individual columns are rounded independently, so displayed component means need not sum exactly.

The package ranges are an additional measure of composition size: the number of deltas alone does not determine how many packages, paths, or registry records must be checked. At the upper end, only two samples contribute to the N=38 mean. The table supports a descriptive scaling model within the observed range, not a uniform estimate of cost for every module set of that size.

| Check | Observed predicate | Historical passing rows |
|---|---|---:|
| V1 | A reconciliation duration was recorded. | 152/152 |
| V2 | Installed package names and versions match the expected union. | 152/152 |
| V3 | Alternatives groups retain offered candidates. | 152/152 |
| V4 | The regenerated cache contains the expected union of layer SONAMEs. | 152/152 |
| V5 | `dpkg --audit` reports no inconsistency. | 152/152 |
| V6 | Account records and membership satisfy the semantic merge check. | 152/152 |
| V7 | Expected paths remain visible with the checked kind, size, and link properties. | 152/152 |
| V8 | Debconf records satisfy the semantic merge check. | 152/152 |

Table 6.6: Recorded structural outcomes. Source: `thesis/evidence/tier2-checks.csv`. V1 is weaker evidence than a separately captured exit status: the evidence generator infers it from a positive `reconcile_ms`. Later regression tests must not be retrospectively counted as having run in these rows.

These clean rows show that the then-implemented predicates accepted the sampled compositions. They cannot establish properties the predicates did not observe. V7's regular-file comparison is `(kind, size)` rather than a content hash, for example; equal-size substitution remains a known blind spot. This distinction becomes the central verification finding in Chapter 7.

### 6.3.2 Regression and the full tier cost

| Phase | a, ms | b, ms/module | R² | Rows |
| --- | --- | --- | --- | --- |
| mount | 20.8 | 9.46 | 0.9845 | 152 |
| reconcile | 154.4 | 21.09 | 0.9577 | 152 |
| total (compose only) | 175.2 | 30.55 | 0.9747 | 152 |
| verify | 161.3 | 41.80 | 0.9605 | 152 |

Table 6.7: Ordinary least-squares fits over the retained 152-row sweep. Source: `thesis/evidence/tier2-fit.csv`. Each row fits $t(N)=a+bN$ in milliseconds; these are historical results for the same sweep.

`total_ms` equals `mount_ms + reconcile_ms` on all 152 rows, while verification is recorded separately (`thesis/evidence/inconsistencies.md` I-11). Thus the relevant fitted costs are

$$
t_{compose}(N)=175.2+30.55N\ \mathrm{ms},\qquad
t_{verify}(N)=161.3+41.80N\ \mathrm{ms}.
$$

Adding coefficients from the same sample gives

$$
t_{compose+verify}(N)=336.5+72.35N\ \mathrm{ms}.
$$

This sum is the fitted duration of the measured composition and verification phases. It does not automatically include sampler planning, process setup, or teardown outside their timing scopes. No $R^2$ for the combined duration is provided; it cannot be obtained by adding the individual $R^2$ values. At N=38 the observed mean is 1,360 ms for composition plus 1,730 ms for verification, giving approximately 3,090 ms for these phases, derived from Table 6.5. The often quoted 1.36 seconds accounts for composition only.

The historical fits are approximately linear in the tested range. That does not prove that compressed payload size has no effect on composition, nor that GPU modules have a measured zero marginal cost: those claims require matched sets and a controlled comparison. Differences from a superseded sweep also mix catalogue and checker changes and cannot isolate a causal effect. Current Tier-1 timing and directly comparable cross-tier latency data are absent from the permitted evidence; no current tier-gap factor is inferred.

Figure 6.2: Historical mean composition and verification time against N, with the fits from the same sweep. Source: `thesis/evidence/tier2-by-n.csv` and `thesis/evidence/tier2-fit.csv`. Show means and sample counts, and identify the 39 covered ordinary deltas of the 40-module catalogue. Per-composition scatter and uncertainty bands require row-level or dispersion data beyond these summary CSVs; a current-generation plot additionally requires a new sweep.

## 6.4 Server-side storage and sensitivity

### 6.4.1 Comparison model

Let B denote the compressed base and $d_i$ each compressed sibling delta. A repository storing each single-module variant independently is modelled as

$$
S_{mono}=NB+\sum_i d_i,\qquad S_{ModFS}=B+\sum_i d_i,\qquad
R=\frac{S_{mono}}{S_{ModFS}}.
$$

The base is 41.7 decimal MB; the evidence uses decimal MB throughout (`storage.md` S1). The numerator and denominator both concern compressed root-filesystem artefacts, not bootable disk envelopes with a kernel and EFI partition. This comparison models a library of single-module variants. It does not quantify storage for every possible combination, a deduplicating image store, or the bytes sent to one node.

| Cohort | N | Stored MB | Modelled monolithic MB | Ratio | Mean delta MB |
| --- | --- | --- | --- | --- | --- |
| small adversarial | 31 | 282.6 | 1534.2 | 5.43× | 7.8 |
| large realistic | 9 | 1704.5 | 2038.3 | 1.20× | 184.8 |
| whole catalogue | 40 | 1945.4 | 3572.4 | 1.84× | 47.6 |

Table 6.8: Current 40-module repository comparison. Source: `thesis/evidence/storage-cohorts.csv`. The monolithic column uses the $B+d$ model for every entry; independently measured monoliths calibrate it below.

The current small-cohort ratio is 5.43×, not the older 5.59×. The rebuilt `jq` artefact now contains both requested packages, `jq` and `moreutils`, making its delta 10.4 MB (`catalogue.md`; `storage.md` S3, S5). This is a changed artefact definition as well as an illustration of catalogue sensitivity. An unchanged catalogue count is insufficient to identify the same storage experiment.

### 6.4.2 Individual modules and the shared-base assumption

| Module | Kind | Delta MB | Modelled monolith MB | Marginal saving % |
| --- | --- | --- | --- | --- |
| cuda-runtime | real | 680.2 | 721.9 | 5.8 |
| nvidia-driver-535 | real | 231.6 | 273.3 | 15.3 |
| rust | real | 175.5 | 217.2 | 19.2 |
| java | real | 141.6 | 183.3 | 22.8 |
| llvm | real | 128.2 | 169.9 | 24.6 |
| gcc | real | 84.0 | 125.7 | 33.2 |
| docker | real | 83.1 | 124.8 | 33.4 |
| postgres | real | 82.1 | 123.9 | 33.7 |
| mysql | real | 56.6 | 98.3 | 42.4 |
| emacs | real | 37.0 | 78.7 | 53.0 |
| apache | real | 28.1 | 69.8 | 59.7 |
| pytools | real | 25.8 | 67.6 | 61.7 |
| webserver | real | 21.0 | 62.8 | 66.5 |
| vim | real | 18.1 | 59.8 | 69.7 |
| git | real | 17.1 | 58.9 | 70.9 |
| dnsutils | real | 16.0 | 57.7 | 72.3 |
| pipdemo | synthetic | 15.5 | 57.2 | 72.9 |
| pgclient | real | 12.1 | 53.8 | 77.6 |
| jq | real | 10.4 | 52.2 | 80.0 |
| memcached | real | 10.3 | 52.0 | 80.3 |
| pyyaml | real | 10.1 | 51.9 | 80.4 |
| gawk | real | 3.1 | 44.8 | 93.1 |
| mta-msmtp | real | 2.6 | 44.3 | 94.2 |
| sqlite | real | 1.9 | 43.6 | 95.6 |
| redis | real | 1.7 | 43.4 | 96.2 |
| control-oldsnap | control | 1.6 | 43.4 | 96.2 |
| curl | real | 1.6 | 43.4 | 96.2 |
| tcpdump | real | 1.1 | 42.8 | 97.5 |
| zstd | real | 0.9 | 42.6 | 98.0 |
| tmux | real | 0.7 | 42.5 | 98.2 |
| rsync | real | 0.7 | 42.4 | 98.4 |
| socat | real | 0.6 | 42.3 | 98.5 |
| wget | real | 0.6 | 42.3 | 98.6 |
| mta-nullmailer | real | 0.5 | 42.2 | 98.9 |
| htop | real | 0.4 | 42.1 | 99.1 |
| nc-openbsd | real | 0.3 | 42.0 | 99.3 |
| original-awk | real | 0.3 | 42.0 | 99.3 |
| nc-traditional | real | 0.3 | 42.0 | 99.4 |
| fake-nvidia-driver | synthetic | 0.2 | 41.9 | 99.5 |
| fake-cuda | synthetic | 0.2 | 41.9 | 99.5 |

Table 6.9: Current per-module compressed sizes and marginal saving, $100[1-d/(B+d)]$. Source: `thesis/evidence/storage-per-module.csv`; catalogue: 40 modules. “Marginal” means that the server already holds the shared base. For an isolated one-module repository, base plus delta costs $B+d$, so this column is not its total saving.

The per-module spread explains why the aggregate result is modest. CUDA's 680.2 MB delta yields only 5.8% marginal saving, whereas thin utilities benefit much more from not duplicating the base. The whole catalogue retains the incompatible control and synthetic modules for experimental purposes. Their presence must be visible when relating the headline result to a deployable workload library.

### 6.4.3 Cohort sensitivity and calibration

| Population | N | Stored MB | Modelled monolithic MB | Ratio |
| --- | --- | --- | --- | --- |
| all 40 modules (headline) | 40 | 1945.4 | 3572.4 | 1.84× |
| minus large realistic (31 left) | 31 | 282.6 | 1534.2 | 5.43× |
| minus control + synthetic (36 left) | 36 | 1927.8 | 3388.0 | 1.76× |
| minus cuda-runtime alone (39 left) | 39 | 1265.2 | 2850.5 | 2.25× |
| minus nvidia-driver-535 alone (39 left) | 39 | 1713.9 | 3299.1 | 1.92× |
| minus rust alone (39 left) | 39 | 1770.0 | 3355.2 | 1.90× |

Table 6.10: Exclusions from the current 40-module catalogue, recalculated with the same model. Source: `thesis/evidence/storage-sensitivity.csv`.

Removing only CUDA changes the ratio to 2.25×; removing the control and synthetic cases gives 1.76× for the 36 real workloads. The differences quantify a limitation of external validity: the ratio belongs to this catalogue as well as to the storage method.

| Module | Measured MB | Modelled MB | Model error % |
| --- | --- | --- | --- |
| curl | 43.0 | 43.4 | +0.91 |
| emacs | 78.3 | 78.7 | +0.51 |
| jq | 51.5 | 52.2 | +1.34 |
| nc-traditional | 41.6 | 42.0 | +0.95 |
| pytools | 67.4 | 67.6 | +0.25 |
| webserver | 62.3 | 62.8 | +0.82 |

Table 6.11: Real monolithic builds used to calibrate the model. Source: `thesis/evidence/storage-model-check.csv`; current 40-module catalogue.

Only six modules have a measured monolithic comparator; 34 have no such build. The headline monolithic total nevertheless remains the formula applied to **all 40**, rather than substituting the six measurements into an otherwise modelled sum. `storage.md` S2 contains both the explicit formula statement and an ambiguous “34 modelled and 6 measured” sentence; the formula, CSV totals, and calibration role resolve that ambiguity.

Across the six comparisons, modelled monolithic size is 0.25–1.34% above measured size. This biases the apparent storage benefit upward, but it is a baseline-size error, not the same percentage-point error in every saving ratio. Nor is it a confidence interval for unbuilt large monoliths. The largest calibrated delta is `emacs` at 37.0 MB; the large cohort begins with `mysql` at 56.6 MB and includes CUDA at 680.2 MB (`storage-per-module.csv`). Extending calibration to this tail remains necessary.

### 6.4.4 The historical fat-base experiment

The claim audit traces a separate 38-module fat-base experiment: repository storage moved from 1,023.8 MB with the thin base to 777.2 MB with the fat base (`thesis/evidence/claims.md`, STATE_OF_PLAY base-fattening row, tracing `fatbase-analysis-2026-09-17T163305Z.txt`). The derived reduction is $(1-777.2/1023.8)\times100\approx24.1\%$. This historical result answers a different question from Table 6.8: whether moving common dependencies into one shared base reduces duplication among sibling deltas. It is not a current 40-module remeasurement and must not be subtracted from the present catalogue total. Chapter 7 develops the corresponding fleet trade-off without treating compressed layer sums as measured node-image sizes.

Figure 6.3: Current per-module delta sizes and marginal savings, ordered by delta size. Source: `thesis/evidence/storage-per-module.csv`. Identify synthetic and control entries and state the already-held-base assumption.

Figure 6.4: Current repository storage for the small, large, and whole cohorts, with a sensitivity panel for exclusions. Source: `thesis/evidence/storage-cohorts.csv` and `thesis/evidence/storage-sensitivity.csv`. Show decimal MB and the modelled nature of the monolithic column.

## 6.5 Tier 3: boot results and runtime conflicts

The complete local evidence snapshot contains six PASS, five FAIL, two BROKEN, four ABORTED, and three unfinished bundles without `result.json` (`tier3.md` T3.0). These are not interchangeable trial outcomes: a missing serial marker is not an observed operating-system failure, and a failed unit is not necessarily failed filesystem composition. Only two bundles are unmarked as superseded; both concern the GPU stack, and one of them aborted. Table 6.12 gives the selected causal matrix and high-layer sequence.

| Run | N | Verdict | systemd | Failed unit | Probes | Seconds |
| --- | --- | --- | --- | --- | --- | --- |
| m1-nginx-20260903T080001Z | 1 | PASS | running | none | 1/1 | 232 |
| m2-apache-20260903T081752Z | 1 | PASS | running | none | 1/1 | 284 |
| m3-nginx-apache-20260903T080746Z | 2 | FAIL | degraded | apache2.service | 2/2 | 191 |
| m4-apache-nginx-20260903T081112Z | 2 | FAIL | degraded | apache2.service | 2/2 | 194 |
| acct-mp-20260916T142443Z | 2 | PASS | starting | none | 2/2 | 330 |
| acct-pm-20260916T141529Z | 2 | PASS | starting | none | 2/2 | 316 |
| maxsub-20260916T154758Z | 36 | FAIL | starting | apache2.service | 34/36 | 189 |
| maxsub-20260917T075714Z | 36 | FAIL | starting | apache2.service | 35/36 | 204 |
| probes-20260918T123806Z | 36 | FAIL | starting | apache2.service | 36/36 | 183 |
| gpu-stack-20260918T231943Z | 2 | PASS | running | none | 2/2 | 198 |

Table 6.12: Selected completed boot observations. Source: `thesis/evidence/tier3.csv`. N excludes base. All selected runs except the GPU-stack PASS are superseded relative to the current 40-module inventory. Full identifiers are retained to distinguish repeated runs.

The individual web-server runs establish that each service can start alone in its historical image. In both composed orders, nginx owns port 80 and `apache2.service` fails, despite passing package audit and module probes. The controlled change is the selected service set and order; the observation supports Class 8, a runtime resource conflict. Reversing the filesystem order does not prove that a scheduler will always choose the same winner. The conflict is a startup race, and the probes' limited conditions do not establish mutual service health.

The high-layer probe sequence records 34/36, then 35/36, then 36/36 passing probes while the Apache failed unit persists. These are runs of evolving artefacts and harnesses, not repeated trials of one fixed system, so the progression is not an estimated reliability improvement. The last run records systemd state `starting`; the generated table alone must not be paraphrased as a fully settled `running` system. It does show the relevant package tools, probes, and several network listeners available alongside a runtime conflict.

The non-superseded GPU-stack PASS reports `running`, two passing probes, and no failed units, but the guest had no GPU. Its driver/kernel and userspace checks do not establish hardware operation. Separately recorded userspace GPU computation and the driver boundary are discussed in Chapter 7, without treating them as extra rows in this boot census.

Figure 6.5: Historical boot matrix linking selected modules, probe outcomes, failed units, and port ownership. Source: `thesis/evidence/tier3.csv`. Label superseded bundles and retain the unobserved/aborted categories in any full-history panel. A current high-layer matrix needs fresh boot bundles.

## 6.6 Answers to the research questions

**RQ1:** The taxonomy gives distinct policies for package relations, ownership, shared registries, numeric identities, opaque-directory semantics, and runtime resources. The current pair/triple census exercises admission exhaustively at those set sizes, while the historical physical sample supports the then-implemented reconciliation predicates. Neither establishes completeness for arbitrary package sets.

**RQ2:** The current repository ratios are 5.43×, 1.20×, and 1.84× for the small, large, and whole 40-module catalogue populations. Sensitivity analysis and measured monolithic calibration bound their interpretation. Savings concern server storage of variants under the stated model, not a smaller flattened image per node.

**RQ3:** Each tier establishes properties in its observation domain. Historical boot tests expose a service conflict that metadata and structural checks did not model, and adversarial reviews expose analogous blind spots inside the checkers themselves. The physical sweep must be refreshed after the artefact rebuilds before its predicates can be claimed for the current inventory. This does not erase the historical mechanism findings; it limits which exact bytes have received which tests.
