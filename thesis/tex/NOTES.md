# Restructuring and review notes

## Delivered scope

The existing eight-chapter Markdown draft has been restructured into the institute's five-chapter LaTeX format under `thesis/tex/`. Work stayed on `thesis/chapters`; no branch switch, new branch, merge, other worktree, or subagent was used. Existing Markdown chapters, source code, bibliography, and the branch's original `thesis/evidence/` files remain unchanged. No ModFS builds, physical sweeps, or boot experiments were run during this restructure.

`thesis/STYLE.md` was absent from the checked-out branch. Its version on `main` was read and preserved as `STYLE-SOURCE.md`, with the source revision recorded in `evidence/origin.json`. The refreshed 23 September numerical evidence was also available on `main`; the checked-out branch still held the superseded 22 September snapshot. Frozen, byte-identical exports under `evidence/current/` make the new thesis self-contained with respect to its numerical inputs without silently replacing the original branch evidence.

The supplied class, cover style, and three logos are byte-identical to the template zip. `thesis.tex` uses the template structure. Local preamble adjustments supply dataref, PGFPlots, bibliography URL wrapping, a correctly sized title metadata table, positive equation spacing, the submission date, and the institute's AI-inclusive declaration. The class's negative display spacing otherwise caused equations with sums to overlap preceding text; this was found and fixed by inspecting the rendered PDF.

The author details are Dipanker Dubey, student ID 10026801, submission **28 September 2026**, as supplied in the conversation. This overrides the older repository date. Start date, examiners, and supervisors remain visibly pending; birth information is omitted using the template's privacy option.

## Structure and balance

| Part | Material retained and organized | Nonblank body pages |
|---|---|---:|
| Abstract / Kurzfassung | Equivalent English and German motivation, problem, approach, results, conclusion | About half a page of text each |
| Introduction | Context, problem, strategy, three questions, numbered contributions, roadmap; no numerical results | 2 |
| Fundamentals | Package installation and shared state lead into layering, then related work positioned against the composition problem | 9 |
| Architecture | Exact-parent model, taxonomy, capture, bundle contracts, registry semantics and discovery, verification and lifecycle | 9 |
| Analysis | Current results and interpretation together; historical boot and reproducibility observations retain their scope | 10 |
| Conclusion | Answers to the questions, limits, brief future work; no new evidence | 1 |

The main chapters differ by 11.1% in rendered page length. PDF text extraction gives approximately 4,144 / 4,011 / 3,915 words for Fundamentals / Architecture / Analysis, including captions, tables, and headers; these are approximate comparison counts, not linguistic word counts. The completed PDF has 65 pages including covers, blank verso pages, appendices, lists, bibliography, and the TODO list.

The original command block and Mermaid source do not appear as program code in the thesis. A native TikZ architecture schematic replaces the diagram source. Numerical figures are vector PGFPlots figures. Full per-module storage detail moves to the supplementary inventory. The body contains no internal audit identifiers, dated project-log citations, or repository-document citations. One reference leads to the provenance appendix; separate AI-use notes satisfy the supplied institute guidance.

## What was adopted from the other draft

The other draft was read directly from `thesis/chapters-b`, pinned at `7d673825b895a31b70f96cd247eacecda333c184`; no checkout was needed. Its background, related work, design, implementation, evaluation, discussion, and notes were compared with the existing draft.

- **Registry discovery as method.** Its account connects lost package state, surveys of shared upperdir files, linker behavior, account audits, and shared unowned configuration files. Architecture now explains this progression and the candidate-selection method: intersect shared upperdir paths and subtract package-owned paths. It explicitly avoids claiming that the survey proves complete registry coverage.
- **Baseline freshness versus equivalence.** Its monolithic-baseline caveat prompted inspection of `02_build_delta.sh --compare`. Independent debootstrap monoliths do not reproduce the base builder's full upgrade and machine-ID normalization. Analysis now explains why fresh comparators can still differ in inputs. The separate flattened-root comparison path in `15_measure_monolith.sh` is not conflated with these independent builds.
- **Verification findings grouped by mechanism.** The distinction among insufficient predicates, observer/harness effects, and evidence-reporting errors provides a clearer argument than review chronology. Concrete merger defects remain explicit; neither documentation corrections nor a green test summary is used as a defect count.
- **Boot population and tier costs.** The boot verdict distribution and separation of compose from verify were retained and checked against the refreshed permitted exports. Blank verdicts are counted as unfinished results, not omitted. The costs and derived factors were recalculated rather than copied from the other draft's older fit.

Ideas retained from the existing draft include the detailed integrity commitments, UID prevention rationale, implicit manual APT marks, semantic-versus-byte order independence, bounded whiteout policy, historical fat-base model, and the distinction between repository storage and flattened node delivery. Related-work positioning continues to credit union-filesystem semantics and EDOS/Mancoosi physical file-conflict analysis rather than claiming them as new inventions.

## Numerical review and qualifications

- The current physical evidence contains **152 compositions and 152 PASS**, covering 39 non-control deltas of the 40-module catalogue. It is no longer labelled as the stale physical sweep. Each V1–V8 column is clean; the text specifies what each predicate actually observes.
- Current fits are compose **92.0 + 30.53 N ms** and verify **96.1 + 39.08 N ms**. Their sum is **188.1 + 69.61 N ms**; no combined R² is invented. The timing table, figure, and prose use the same declarations.
- The composition slope differs from the previous fit by about **0.07%**, while the intercept decreases **47.5%**. These descriptive comparisons are not presented as a controlled causal proof that slope belongs only to the method and intercept only to the machine. Verification's slope also changed. Implementation scripts are unchanged between the pinned writing revision and the refreshed-evidence revision; changed artefact/workload/environment context still prevents causal attribution.
- The requested historical **62–686×** boot/physical range used the old combined physical fit. With the refreshed fit, retained two-module boot durations imply approximately **584–1008×**, and historical 36-module boots imply **68–76×**. These are labelled unmatched descriptive comparisons, not same-input speedups. No Tier-1-to-Tier-2 cost ratio is stated.
- Admission remains 667/780 accepted pairs and 7,807/9,880 accepted triples. Overlapping rejection causes are not stacked or treated as a partition. Accepted triples containing rejected pairs reflect missing-provider completion, not repair of an existing hard conflict.
- Storage ratios remain **5.43× / 1.20× / 1.84×**. Every headline monolithic value is modelled as base plus delta. Six independent builds calibrate the model; measured values are not substituted into its headline numerator. The calibration does not validate large-workload error bounds or input equivalence.
- The historical fat-base experiment remains explicitly a 38-module model, separate from the current inventory. Fleet equations are models of repeated layer payloads, not measured node-transfer results.
- All historical boot categories are retained: 6 PASS, 5 FAIL, 2 BROKEN, 4 ABORTED, and 3 without results. The current GPU pair does not demonstrate operation of the packaged driver on GPU hardware. Passing command probes do not erase failed service units or convert `starting` into `running`.

`prepare_data.py` produces 513 central declarations plus linked tables and plot coordinates. The base-size source is the artefact inventory; historical fat-base quantities are checked against the permitted claims index. `prepare_provenance.py` generates one table mapping figures, tables, and qualitative findings to source files, full SHA-256 digests, and dates. Document hashes are not misrepresented as newly computed remote artefact hashes.

## Claims not adopted or not quantitatively sourced

- The STYLE example's “40 confirmed defects” is not an audited result. The other draft's defect summaries and the documentation inconsistency count are not interchangeable. Analysis uses concrete qualitative findings.
- The cross-machine “0 of 40” archive-match result exists in a remote report outside the permitted numerical directory. Its mechanisms are discussed qualitatively; the rate is not imported as a thesis measurement.
- The approximately 2% removable-complexity claim lacks an auditable result in the permitted evidence and is omitted.
- A report of packaged-driver loading or initialization is not treated as proof of hardware operation. The thesis retains the narrower guest-boot and userspace-versus-driver distinction.
- Missing timing dispersion and controlled repetitions prevent uncertainty bands or a causal performance claim. A new physical sweep does not refresh historical boots.
- Existing bibliography keys all resolve. Inherited metadata still need attention: versioned kernel URLs, Debian Policy/manual version-URL pairing, and Pendry's missing page range. The misleading unused `debian-policy-diversions` entry is not cited; the existing `man-dpkg-divert` key is used instead. The unused UEFI placeholder is not cited either.

## Figures and missing visual evidence

Delivered: architecture schematic, current composition/verification means and fits, and storage comparison by cohort. Admission is reported in booktabs census/cause tables; a second graph would duplicate those small tables. Every figure and table is introduced and interpreted in prose.

A per-composition scatterplot or uncertainty band needs row-level/dispersion evidence; a quantitative cross-machine figure needs an authorized numerical export; a current end-to-end boot matrix needs new matched boots. These are unavailable evidence extensions, not blank figure placeholders. No body figure is left unimplemented.

## Actual build and verification

A real pdfLaTeX/latexmk/BibTeX build completed using TeX Live 2023. The system lacked German Babel data. `texlive-lang-german_2023.20240207-1_all.deb` was downloaded and extracted under `/tmp/modfs-tex-deps`, without installing system packages. An isolated pdfLaTeX format with the supplied German hyphenation loaders was built under `/tmp/modfs-tex-format`; this also removed the initial missing-hyphenation warning.

The exact successful local command, from the repository root, was:

```sh
TEXINPUTS=/tmp/modfs-tex-deps/usr/share/texlive/texmf-dist/tex//: \
TEXFORMATS=/tmp/modfs-tex-format: \
latexmk -pdf -pdflatex='pdflatex -fmt=modfs-pdflatex %O %S' \
  -interaction=nonstopmode -halt-on-error -cd thesis/tex/thesis.tex
```

These `/tmp` paths describe this environment only; a complete TeX installation with German support builds with the ordinary `make` command. No temporary dependency paths are embedded in the thesis source.

Validation confirmed:

- All 31 frozen evidence files are byte-identical to their pinned repository sources.
- The supplied class, style, and three logos are unchanged.
- All 39 cited bibliography keys, 25 cross-reference targets, 331 referenced data keys, and 17 used acronym keys resolve.
- Exactly five numbered body chapters, with clean source-to-chapter mapping and no body provenance leakage.
- No undefined references, missing dataref keys, or overfull boxes in the final build; no `??` markers in extracted PDF text.
- Rendered cover date, numerical plots, and corrected equation spacing inspected visually.
- Preparation scripts regenerate their outputs deterministically; source-only changes do not require rerunning ModFS tests or experiments.

Remaining build warnings are compatibility messages inherited from the unchanged template: the BibLaTeX fallback BibTeX backend, siunitx's removed `binary-units` option, and a small sans-serif font-size substitution. They do not prevent compilation or lose content. The TODO list is intentional. The PDF and intermediate files are ignored by Git; the built PDF is available locally as `thesis/tex/thesis.pdf`.

## Every remaining TODO

The first four are optional evidence extensions required only for stronger claims; the existing text already states the narrower supported conclusions. The last four concern source metadata or author completion before submission.

- `cha/06-provenance.tex:22` — Export a quantitative independent-rebuild summary into the permitted thesis evidence if the thesis is to report a cross-machine reproduction rate. The current body reports mechanisms qualitatively.

- `cha/06-provenance.tex:23` — Complete matched large-workload monolithic calibration if a measured whole-catalogue saving is required. The present headline remains explicitly modelled.

- `cha/06-provenance.tex:24` — Collect dispersion and controlled timing repetitions before adding uncertainty bands or a causal cross-machine performance claim. The current figure shows descriptive means and fits.

- `cha/06-provenance.tex:25` — Boot representative sets from the refreshed physical-sweep artefacts before claiming current end-to-end verification of that sweep. Historical boot observations remain separately labelled.

- `cha/06-provenance.tex:27` — Review inherited bibliography metadata: versioned kernel documentation URLs, Debian Policy and manual-page version/URL consistency, and the missing page range in the Pendry union-mount reference. Citation keys resolve; these metadata qualifications remain.

- `cha/07-aids.tex:21` — Confirm the complete AI tool and model history, including assistance with the implementation and experiments before this writing session; add any missing tools, purposes, and affected sections.

- `cha/07-aids.tex:22` — Review and approve the scientific argument, all AI-assisted prose and figures, and the German translation before submission. This draft does not assert that author review has already occurred.

- `cha/07-aids.tex:23` — Confirm the official start date, examiner, second examiner, and supervisor(s); replace the title-page pending fields. The author has supplied Dipanker Dubey, student ID 10026801, and submission date 28 September 2026.

## Chapter commits

- `d5b3c3a` — template foundation and bilingual abstract.
- `9a0509c` — Introduction.
- `87daa33` — Fundamentals.
- `04df0c9` — Architecture.
- `34a5d51` — Analysis.
- `4edf51a` — Conclusion.

The provenance/disclosure appendices and these review notes are committed separately after the chapter commits.
