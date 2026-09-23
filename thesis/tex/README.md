# ModFS thesis in the institute template

Entry point: `thesis.tex`. The bibliography is `../refs/refs.bib`, so retain this directory inside the repository.

## Build

A TeX Live installation with pdfLaTeX, latexmk, BibTeX, German Babel/hyphenation, and the packages required by the supplied `vssthesis.cls` is needed. In particular, the class uses MathDesign/Charter, acro, cleveref, siunitx, TikZ, and BibLaTeX; the thesis additionally uses dataref and PGFPlots. The class selects the BibTeX backend for BibLaTeX.

From this directory:

```sh
make
```

The output is `thesis.pdf`. Intermediate files and the PDF are ignored by Git. `make clean` removes intermediate files. A real PDF build was completed; see `NOTES.md` for the local environment and remaining compatibility warnings.

## Evidence and figures

```sh
make data
make
```

`prepare_data.py` regenerates the central `data.tex`, tables, and vector plot sources from the frozen evidence. `prepare_provenance.py` regenerates the source-digest table and verifies qualitative source files against the pinned repository revision. Python 3 and Git suffice; neither script executes ModFS or creates new measurements.

`evidence/current/` is the permitted `thesis/evidence/` export at the revision in `evidence/origin.json`. `evidence/previous/` retains the superseded fit and its provenance for the labelled historical comparison. Do not edit declarations in `data.tex` independently of their evidence. Updating evidence requires reviewing identities and qualifications in the text, not just replacing numbers.

## Outstanding author input

The title uses Dipanker Dubey, student ID 10026801, and submission on 28 September 2026. Start date, examiners, and supervisors remain visibly pending. The appendices and generated TODO list record these and the remaining evidence, bibliography, and AI-disclosure qualifications. `NOTES.md` lists every TODO and distinguishes submission details from optional additional experiments.
