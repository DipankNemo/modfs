# Source and completion notes

These notes record limits found while revising `thesis/rough/firstedit.txt`. Only chapter files and this note were changed. Numerical claims in the chapters use `thesis/evidence/` or arithmetic from its generated tables; mechanism descriptions use `ARCHITECTURE.md` and the reference documents.

## Measurements that cannot currently carry a headline

- **Tier 2 freshness.** `thesis/evidence/tier2.md` deliberately emits no current table: `compose-sweep.csv` predates rebuilt module artefacts. Its retained 152-row fit and V1–V8 outcomes can be presented only as historical, for the earlier 39-module generation. A new `scripts/10_compose_sweep.sh` run followed by evidence regeneration is required for current composition cost, pass rates, and a current Figure 6.2. I did not rerun it because the brief forbids changing `thesis/evidence/` or anything outside `thesis/chapters/`.
- **Tier 3 freshness.** `thesis/evidence/tier3.md` says only two of its 20 bundles still describe unchanged artefacts. One is aborted and the other is a successful GPU-stack guest boot. The web-server and high-layer Class 8 demonstrations are retained history. A current high-layer boot and a current order-reversal matrix require fresh bundles. No current-catalogue boot success percentage is defensible.
- **Tier gaps.** The brief gives tier-to-tier factors, but the generated evidence has no retained current Tier-1 timing table (`thesis/evidence/claims.md` marks its timing claim untraceable). I omitted numerical tier-gap factors instead of comparing incompatible generations or timed scopes.
- **Cross-machine reproducibility.** `docs/evidence/remote-verification-2026-09-20/REPORT.md` contains the independent rebuild comparison and diagnosis. `thesis/evidence/` does not publish its cross-machine digest table. The discussion states the qualitative finding and its confounds; a numerical byte-match fraction belongs in the generated evidence before publication as a thesis number.
- **Review and complexity counts.** `JOURNAL.md` and the labelled regression tests support the pattern of repeated checker and harness defects. `thesis/evidence/` does not give a generated count of distinct defects across review passes or the whole-repository cuttable-lines audit. The requested “20+” and “about 2%” are therefore not quantified in the chapters. The 29 closed `inconsistencies.md` entries count documentation findings and must not be substituted for the implementation-defect count.
- **GPU scope.** The current generated boot table proves a guest boot without GPU access. The remote-verification report documents a real-GPU userspace computation with a provider driver, and `JOURNAL.md` describes a distinct GTX 1060 userspace experiment on an in-progress branch. Neither is a generated thesis GPU measurement for the packaged NVIDIA driver on real hardware. The driver load/link/init result stops at hardware enumeration. A passed-through or owned matching-kernel GPU test is still required.

## Disagreements corrected in the chapters

- The rough draft's §2.2 says seven registries and omits debconf `passwords.dat`. `docs/REGISTRY_FORMATS.md` identifies eight groups: six record-merged and two regenerated (`/etc/alternatives/*`, `/etc/ld.so.cache`). Background and Implementation follow that account.
- The draft and `thesis/PLAN.md` report 5.59× for the small cohort; the current 40-module `thesis/evidence/storage.md` S1 reports 5.43× after `jq` was rebuilt from its `jq, moreutils` spec. The current server storage totals in Chapter 6 are 282.6, 1,704.5, and 1,945.4 decimal MB by cohort. The plan's “rebuilt like-for-like” monolithic baseline wording is also too broad: only six were built, with 34 modelled as $B+d$.
- The plan and older draft mix catalogue generations in the admission counts and storage figures. Chapter 6 labels the 40-module catalogue and uses `tier1.md` and `storage.md`; older figures remain historical only. `storage.md` S5 records the published storage values and the catalogues to which they belonged.
- The draft's Tier-2 `total_ms` is composition alone. The same-sweep fitted compose and verify costs are separate in `tier2-fit.csv`; summing them gives the combined historical cost. The superseded `148 + 27.2N` fit belongs to an earlier CSV. No two generations were differenced.
- The plan's “zero failed units” headline conflicts with the historical nginx/Apache and high-layer bundles in `tier3.md`: probes can pass while `apache2.service` fails. Those bundles are now superseded and are labelled accordingly.
- The draft's unconditional order-independence claim exceeds the tested property. The recorded reversals are equal as sets of semantic registry records, while their bytes differ (`thesis/evidence/inconsistencies.md` I-03; `ARCHITECTURE.md` §4).
- The rough draft describes the CUDA module as simply bootable and at points implies computation was not tested. Subsequent project history and the remote report demonstrate userspace execution on real GPUs, while the ModFS kernel driver remains unproven on GPU hardware. Chapter 7 keeps those claims separate.

## Figures and analyses still needing data

- Figure 6.1 can be drawn from `thesis/evidence/tier1-classes.csv`; the class columns overlap and cannot form a stacked partition of rejections.
- Figure 6.2 can show the **historical** sweep using `tier2-by-n.csv` and `tier2-fit.csv`. A current-generation plot needs a new sweep; the existing file must not silently be relabelled.
- Figures 6.3 and 6.4 can be drawn from `storage-per-module.csv` and `storage-sensitivity.csv` for the current catalogue.
- The draft's proposed Tier-3 workflow diagram is a process diagram supported by `docs/SAMPLING_AND_BOOT.md`, not a measured performance plot. A current verdict-by-module figure needs new, non-superseded boot bundles, including both web-server orders and a high-layer set.
- A per-node transfer or rollback plot needs retained delivery traces or a deployment experiment. Server repository bytes in `storage.md` cannot supply it.

## Draft statements deliberately removed

The draft claims a sub-millisecond Tier-1 check, broad deterministic builds, strong boot prediction, generic order-independent composition, and whole-image network savings. The first has no retained timing CSV (`claims.md`); the others exceed the measurements or describe a different delivery path. Its SquashFS compression percentage and illustrative account-ID example also lack generated evidence. The draft's claim of a complete monolithic baseline overstates the six measured calibrators. These claims were not carried forward as assertions.

Bibliography keys used in Chapters 1–3 all occur in `thesis/refs/refs.bib`. That file itself flags entries for final bibliographic verification; no bibliography metadata was edited under this task's scope.
