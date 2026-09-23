# Thesis plan — chapter map to evidence

Every claim below is traceable to something measured and committed. Where a
chapter needs input that does not exist yet, it says so.

| Ch | Title | Primary sources | Ready? |
|---|---|---|---|
| 1 | Introduction | ARCHITECTURE §1, EVOLUTION.md | needs framing decisions |
| 2 | Background | `docs/REGISTRY_FORMATS.md`, `docs/DATA_MODEL.md` | ready |
| 3 | Related Work | `thesis/refs/` (15 papers, `refs.bib`) | ready |
| 4 | Design | ARCHITECTURE §1–5, §11 | ready |
| 5 | Implementation | ARCHITECTURE §3–5, JOURNAL, scripts/ | ready |
| 6 | Evaluation | JOURNAL, /srv/modfs/logs/*.csv, results/ | **ready, most evidence-dense** |
| 7 | Discussion & Limitations | STATE_OF_PLAY §7, DECISION_kernel_pinning | ready |
| 8 | Conclusion & Future Work | EVOLUTION.md, STATE_OF_PLAY | ready |

## What chapter 6 (Evaluation) will contain — all measured

- conflict taxonomy: 9 classes, 2 discovered by running the system
- tier 1: **780 pairs (667 ACCEPT / 113 REJECT) and 9,880 triples (7,807 / 2,073)** at 40 modules, matching an independent combinatorial model. The older 703 pairs / 630 / 73 is the 38-module catalogue
- tier 2: 152 compositions, N=2→38, V1–V8 clean
- tier 3: the high-N runs reach `multi-user` with 36/36 probes passing and exactly ONE failed unit, `apache2.service` -- which is class 8, a real conflict rather than a defect, and must not be reported as zero
- storage: **5.43× / 1.20× / 1.84×** (40 modules). 6 of 40 monoliths are rebuilt for real and 34 modelled as B + d; all six were rebuilt AFTER their deltas on 22 September, so the calibration is genuine like-for-like at last, and they show the model OVERSTATES the saving by **0.25-1.34 %**
- cost: compose **92.0 + 30.53 ms × N** (R²=0.981); verify **96.1 + 39.08 ms × N** (R²=0.965) — the CURRENT sweep, 152 rows, re-measured 23 September, `thesis/evidence/tier2-fit.csv`. Earlier `175.2 + 30.55` and `148 + 27.2` are superseded sweeps. **The slope reproduces across generations to 0.1 %; the intercept does not** — only the slope should carry an argument
- base fattening: server-side −24.1%, and why no single-module node can win
- GPU: a 680 MB module composes at the same per-layer cost and saves 5.8%
- the verification findings across **four** independent review passes. State it as STATE_OF_PLAY §9 does — tier 2 never rejected a genuine defect that a checker was not first taught to see — and NOT as "no composition ever failed": round 4 fixed real defects in `reconcile.py` itself

## What is NOT claimed, and must be stated

- class 8 (runtime resource conflict) is undetectable below tier 3
- V7 cannot see same-size content substitution
- ~~nothing binds a manifest to the base generation~~ — **closed.** `generation` is sha256({snapshot, suite, arch, base_sha256}) and is checked as a composability precondition
- the saving is server-side storage and assembly, not node-side
- CUDA userspace **does** compute on a real GTX 1060, and the kernel module loads and initialises in its target kernel — both on the unmerged `experiment/noble-generation`, and neither shows the module DRIVING a GPU

## Needed from Dipanker

1. `thesis/template/` — the university's .cls/.sty and any sample main.tex
2. `thesis/refs/` — the 17 papers (`txt/` extractions, `pdf/` originals, `refs.bib`), with per-paper digests in `thesis/refs/NOTES.md`
