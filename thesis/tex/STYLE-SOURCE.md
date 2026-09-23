# How the chapters should read

Both first drafts were written like a project log. This is the contract that
replaces that. It also records two things neither draft knew: the deliverable is
**LaTeX**, and the institute expects **five chapters**, not eight.

---

## 1. The one test

> **Would this sentence make sense to a reader who has never seen this
> repository?**

An examiner has the thesis and the bibliography. They do not have `JOURNAL.md`,
they cannot look up commit `d01eb4e`, and "R4-1" is not a name of anything to
them. If a sentence only works for someone with the repo open, it is not thesis
prose.

Applied to the first drafts: 29 explicit dates, 9 internal finding identifiers,
4 commit hashes and 12 citations to internal documents, all in the body.

## 2. Three categories, three destinations

**Findings — keep, this is the thesis.** What is true about the system and how
it was established. *"Comparing directory entry names rather than file content
meant a symlink replacing a 1 MB file with a five-byte target was reported as
present."*

**Method — keep, but as method, not as chronology.** That verification was
developed adversarially is a legitimate methodological statement. *"Four
independent adversarial review passes were conducted against the checkers"* is
method. *"On 22 September, round 4 found R4-1"* is a diary entry.

**Provenance — move to an appendix. Do not delete it.** Which file a figure came
from, which digest it carried, when it was generated. This is good practice and
it is exactly what makes the work auditable — but it is an appendix, not a
chapter. One table: figure, source file, SHA-256, date. The body then cites the
appendix once.

## 3. Transformations

**Dates.** A date belongs in the body only when the date itself is the fact. The
pinned snapshot `20260701T000000Z` is a fact about the system and stays. "The
evidence directory was last regenerated on 2026-09-22 at 23:05:49 UTC" is
provenance and moves.

> ✗ The evidence directory was last regenerated on 2026-09-22 at 23:05:49 UTC, at
> commit `58e926b`, against a catalogue of 40 modules.
>
> ✓ All measurements reported here were taken on a single catalogue of 40
> modules; Appendix B lists each figure's source file and digest.

**Review rounds.** Number the *finding classes*, never the sessions.

> ✗ 17 Sep — the tier-1 and tier-2 checkers — 7 findings (JOURNAL, 2026-09-17).
> 22 Sep — the merger — 9 findings (R4-1 to R4-9).
>
> ✓ Four adversarial passes were conducted, each targeting a different component:
> the admission checker, the fixes made in response to the first pass, the
> pipeline as a whole by an independent implementation, and the registry merger.
> They produced 40 confirmed defects, which fall into three classes (§4.3).

**Internal documents as citations.** Never cite `JOURNAL.md` or `STATE_OF_PLAY`.
State the finding; if provenance is needed, cite the appendix.

**Two chronologies that legitimately stay**, because the sequence *is* the
argument: that classes 8 and 9 were discovered by running the system rather than
by reasoning about it, and that each registry was found by a composition
behaving wrongly. Report these as *how the knowledge was obtained*, without dates.

## 4. Chapter structure

The institute's template (`thesis/thesis guidelines/thesis.zip`) is five
chapters. The eight-chapter drafts map onto it:

| Template chapter | File | Takes from the drafts |
|---|---|---|
| 1 Introduction | `cha/01-introduction.tex` | Introduction |
| 2 Fundamentals | `cha/02-fundamentals.tex` | Background **and** Related Work |
| 3 Architecture | `cha/03-architecture.tex` | Design **and** Implementation |
| 4 Analysis | `cha/04-analysis.tex` | Evaluation **and** Discussion |
| 5 Conclusion | `cha/05-conclusion.tex` | Conclusion and future work |

Sections carry the detail. Chapter 3 is the largest: the taxonomy, the eight
registries, the data model, the verification tiers.

### What each chapter must do

**1 Introduction.** The problem (BMaaS stores whole-disk images; ten
configurations sharing one base means ten copies). What is proposed. The research
questions. Contributions as a numbered list. A one-paragraph roadmap. No results.

**2 Fundamentals.** What a reader needs before Chapter 3: dpkg and maintainer
scripts, OverlayFS semantics including whiteouts and opaque markers, SquashFS,
and the registries that no package owns. Then Related Work, positioned — union
filesystems, package co-installability, functional deployment, distributed
filesystems — each ending in what it does *not* address that this work does.

**3 Architecture.** The design and its realisation. Pinned sibling deltas. The
conflict taxonomy. The eight registries and their merge rules. The data model —
manifest, sidecar, seals. The three verification tiers. Argue *why*, not just
*what*: why regenerate `ld.so.cache` rather than merge it, why partition UID
ranges rather than detect collisions.

**4 Analysis.** Results and what they mean, together. Admission over the full
combination space, composition and verification at increasing N, storage against
a monolithic baseline, boot. Then threats to validity and limitations — in the
chapter, not exiled to the end.

**5 Conclusion.** What was shown, what was not, what follows. No new evidence.

## 5. Numbers

- Every number traces to `thesis/evidence/`, and the appendix says where.
- Label the catalogue: figures moved as it grew from 27 to 38 to 40 modules.
- Never difference fits from different generations. The tier-2 slope reproduces
  across generations to 0.1 %; the intercept moved 47 %. Only the slope carries
  an argument.
- Use `\num` and `\SI`, per the template.

## 6. Voice

Past tense for what was done, present for what is true. *"The checker compared
entry names"*; *"OverlayFS resolves a path by taking the topmost layer's copy."*

Prefer the concrete: *"vim registers `/usr/bin/vim.basic` at priority 30 and
emacs registers `/usr/bin/emacs` at priority 0"* beats *"modules may register
competing alternatives."*

First person plural for choices actually made (*"we chose to regenerate"*), never
for the system's behaviour.

Do not oversell. The storage saving is **server-side**, modest and
cohort-dependent. The strongest contributions are the taxonomy, the
reconciliation mechanism, and what the verification work revealed.

## 7. Format

The deliverable is **LaTeX**, not Markdown. `vssthesis.cls`, chapters under
`cha/`. From the template: `\cref` for cross-references, `\SI`/`\num` for units
and numbers, `listings` for code, `biblatex` against `thesis/refs/refs.bib`,
and acronyms declared in `glossary.tex`.

Every figure and table needs a caption that stands alone, and must be referenced
from the text before it appears.
