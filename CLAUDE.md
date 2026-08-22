# Working agreement

Read `ARCHITECTURE.md` first — it is canonical. If code and ARCHITECTURE.md
disagree, the code is wrong. Append findings to `JOURNAL.md` as we go; it
becomes the Implementation and Evaluation chapters.

## Deadlines
- Submission: **29 September 2026**
- Code freeze: **2 September 2026** — refuse new features after this date.

## How to work with me
- Explain the concept before implementing. I want the "why", with analogies.
- Numbered steps, explicit reasoning behind design decisions.
- Don't dump multiple files at once without explaining what each does.

## Code rules
- Bash and Python 3 only. No new dependencies without asking first.
- Every script sources `config.sh` and `lib.sh`. Never hardcode paths.
- Every script must tear down its mounts on **any** exit path (trap EXIT).
- Syntax-check before presenting (`bash -n`, `python3 -m py_compile`).
- Never present untested code.
- Scripts are numbered by pipeline stage: `NN_verb_noun.sh`.

## Environment
- Ubuntu 22.04 (jammy), APT/dpkg, x86-64 only.
- Code lives in `~/modfs` (git). Artefacts live in `/srv/modfs` (not git).
- Everything must be reproducible by re-running scripts from `~/modfs`.
