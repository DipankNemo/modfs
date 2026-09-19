# Thesis plan — chapter map to evidence

Every claim below is traceable to something measured and committed. Where a
chapter needs input that does not exist yet, it says so.

| Ch | Title | Primary sources | Ready? |
|---|---|---|---|
| 1 | Introduction | ARCHITECTURE §1, EVOLUTION.md | needs framing decisions |
| 2 | Background | — | **needs reference papers** |
| 3 | Related Work | — | **needs reference papers** |
| 4 | Design | ARCHITECTURE §1–5, §11 | ready |
| 5 | Implementation | ARCHITECTURE §3–5, JOURNAL, scripts/ | ready |
| 6 | Evaluation | JOURNAL, /srv/modfs/logs/*.csv, results/ | **ready, most evidence-dense** |
| 7 | Discussion & Limitations | STATE_OF_PLAY §7, DECISION_kernel_pinning | ready |
| 8 | Conclusion & Future Work | EVOLUTION.md, STATE_OF_PLAY | ready |

## What chapter 6 (Evaluation) will contain — all measured

- conflict taxonomy: 9 classes, 2 discovered by running the system
- tier 1: 703 pairs, ACCEPT 630 / REJECT 73, matching an independent
  combinatorial model; 10,660 combinations at higher N
- tier 2: 152 compositions, N=2→38, V1–V8 clean
- tier 3: boots, 0 failed units, per-unit causal matrix
- storage: 5.59× / 1.20× / 1.84× (40 modules), with the monolithic baseline
  rebuilt like-for-like and the model validated against 6 measured monoliths
- cost: compose 148 + 27.2 ms × N; verify 161.3 + 41.8 ms × N
- base fattening: server-side −24.1%, and why no single-module node can win
- GPU: a 680 MB module composes at the same per-layer cost and saves 5.8%
- the verification findings: 20+ defects across three independent review passes

## What is NOT claimed, and must be stated

- class 8 (runtime resource conflict) is undetectable below tier 3
- V7 cannot see same-size content substitution
- nothing binds a manifest to the base generation it was built against
- the saving is server-side storage and assembly, not node-side
- no GPU hardware, so CUDA is shown to compose, not to compute

## Needed from Dipanker

1. `thesis/template/` — the university's .cls/.sty and any sample main.tex
2. `docs/refs/` — the reference papers, plus one line each: what claim it supports
