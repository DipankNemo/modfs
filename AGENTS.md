# AGENTS.md

## Purpose

This repository contains the ModFS BSc thesis prototype: a modular, updatable
filesystem for Bare Metal as a Service using Ubuntu 22.04, APT/dpkg,
OverlayFS, and SquashFS.

These instructions apply to Codex running locally and to Codex working through
GitHub. They establish a shared workflow; they do not replace technical
evidence or human review.

## Canonical context

Read these files before planning or changing implementation code:

1. `ARCHITECTURE.md` — intended design and supported scope.
2. `docs/REASSESSMENT_2026-09-10.md` — newest independent problem list.
3. `docs/CODEX_HANDOFF.md` — current task, decisions, and agent handoff.
4. `JOURNAL.md` and `EVOLUTION.md` — experimental history and rationale.
5. `CLAUDE.md` — existing working agreement and deadline constraints.

When code, documentation, and retained evidence disagree, do not silently
choose one. Report the discrepancy in `docs/CODEX_HANDOFF.md`, identify the
exact commit and evidence involved, and narrow the claim until it is resolved.

## Deadline and scope

- Submission: 29 September 2026.
- The repository is past its nominal 2 September code freeze.
- Prefer correctness, evidence provenance, and thesis-ready documentation over
  new features.
- Do not add broad CUDA, TensorFlow, external-repository, API, or production
  deployment work unless the user explicitly reopens scope.
- Current highest-priority technical issue: account-database composition and
  verification for `/etc/passwd`, `/etc/shadow`, `/etc/group`, and
  `/etc/gshadow`.
- Do not claim that Class 7 is fully prevented merely because numeric UID/GID
  collisions fell to zero. The final composed account databases must also be
  verified.

## Branch model

- `main` is not a Codex working branch. Claude may continue using it.
- `codex/collaboration` is the Codex integration and communication branch.
- Every implementation task uses a short-lived branch created from the latest
  `origin/codex/collaboration`.
- Recommended names:
  - `codex/local-<short-task>` for local Codex work.
  - `codex/chat-<short-task>` for work initiated through ChatGPT.
- Never let two agents edit the same files on the same branch concurrently.
- Do not commit implementation directly to `main`.
- Do not force-push shared branches.
- Integrate through a reviewed pull request or an explicitly reviewed
  fast-forward. Preserve the originating commit SHA in the handoff.

## Required startup sequence

Before each task, run read-only checks first:

```bash
git status --short
git fetch origin
git branch --show-current
git rev-parse HEAD
git rev-parse origin/codex/collaboration
```

Then:

1. Stop if the worktree is dirty unless the user explains the changes and
   confirms how to preserve them.
2. Switch to `codex/collaboration` and run
   `git pull --ff-only origin codex/collaboration`.
3. Read the canonical context listed above.
4. Check `docs/CODEX_HANDOFF.md` for active or overlapping work.
5. Create or switch to a task branch from the pulled integration branch.
6. State the intended files, tests, and supported claim before editing.

Do not automatically merge a changed `main` during an active task. Fetch it,
compare it with the integration branch, record the relevant changes, and merge
only after checking for semantic conflicts.

## Handoff protocol

GitHub is the durable communication channel between ChatGPT Codex and local
Codex. Chat messages are not the canonical record.

Every completed or paused task must update `docs/CODEX_HANDOFF.md` with:

- actor and date;
- task branch and full commit SHA;
- goal and scope;
- files changed;
- commands/tests actually run and their exit status;
- evidence paths or uploaded bundle identifiers;
- unsupported or unverified claims;
- blockers and exact next action;
- whether changes are ready for review, testing, or merge.

Update the handoff in the same task branch as the code. Do not record a test as
passing unless it actually ran. If a test requires root, mounts, chroot, QEMU,
or host-specific facilities, provide the exact command and ask the user to run
it locally.

## Implementation rules

- Explain the intended invariant before changing the implementation.
- Keep changes bounded and reviewable.
- Preserve user changes and unrelated work.
- Use fail-closed behavior for admission, integrity, and cleanup checks.
- Treat artifact content, manifests, sidecars, source policy, and evidence as
  separate objects unless they are cryptographically bound.
- Do not use broad or unresolved paths in recursive deletion.
- Do not weaken a check merely to make an experiment pass.
- A negative result is valid thesis evidence when the setup, oracle, and
  limitation are explicit.
- Update architecture and journal material only after the corresponding
  behavior has been demonstrated.

## Test and evidence standard

For every experimental result, retain:

- full source commit SHA;
- exact command line and configuration;
- OS, architecture, kernel, and relevant tool versions;
- module/artifact hashes;
- start/end timestamps and exit codes;
- raw logs and machine-readable output;
- a short interpretation that distinguishes observation from inference.

Use immutable, timestamped result directories. Never overwrite the only copy
of a previous run. A source file or CSV without a matching commit SHA is not
sufficient evidence for a final thesis claim.

## Thesis and AI-use constraints

Scientific integrity has priority over implementation convenience:

- Do not invent data, citations, test results, or source behavior.
- Prefer primary sources for technical claims.
- Record material AI assistance for the thesis appendix
  (`Verwendete Hilfsmittel`), including tool/version, purpose, remarks, and
  affected sections.
- AI-generated or materially AI-modified code and text must remain reviewable
  by the student, who is responsible for the final content.
