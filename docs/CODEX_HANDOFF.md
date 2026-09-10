# Codex collaboration handoff

This file is the durable exchange point between Codex in ChatGPT and Codex
running locally. Read `AGENTS.md` before using it.

Keep this document concise. Add a new entry at the top of **Handoff log** when
work completes or pauses. Code, commits, and retained evidence remain the
authority; this file tells the next agent where to look.

## Coordination state

| Field | Value |
|---|---|
| Integration branch | `codex/collaboration` |
| Initial upstream base | `main@31c99aac93ea60966fef12478f68f48c103cf22b` |
| Active implementation task | None |
| Current priority | Independently confirm and then close or explicitly scope the account-database composition gap |
| Repository deadline | Submission 29 September 2026; scope is frozen unless the user explicitly reopens it |

## Branch ownership

| Branch pattern | Intended owner | Purpose |
|---|---|---|
| `main` | User / Claude workflow | Existing primary development |
| `codex/collaboration` | Shared, reviewed integration | Instructions, handoffs, accepted Codex work |
| `codex/local-*` | Local Codex | Local implementation and privileged-test preparation |
| `codex/chat-*` | ChatGPT Codex | GitHub-side analysis or implementation |

The integration branch is not a simultaneous editing surface. Agents work on
task branches and integrate after review.

## Current verified understanding

- ModFS is a strong BSc thesis prototype, but it must not claim arbitrary safe
  composition.
- The current catalogue reports zero duplicate numeric UID/GID allocations
  after applying disjoint ranges.
- Numeric uniqueness is not account-database composition. OverlayFS exposes
  one complete top-layer copy of `passwd`, `group`, `shadow`, and
  `gshadow`; sibling records are not automatically unioned.
- The 10 September reassessment identifies at least 21 accepted pairs of
  account-writing modules for which the checker model can differ from the
  actual composed files.
- Additional high-priority evidence gaps include positive dependency closure,
  actual Tier-2 identity checks, evidence/source binding, and a final rerun
  whose schema matches the exact source commit.
- Large new feature work is out of scope unless the user explicitly decides
  otherwise.

These are working conclusions, not substitutes for reproducing the relevant
checks at the current commit.

## Next proposed task

Perform an independent, read-only audit of the Class-7 path at the current
integration commit:

1. Trace account creation from module build through metadata extraction,
   Tier-1 admission, composition, reconciliation, Tier-2 verification, and
   Tier-3 boot.
2. State the required invariants for account names, numeric IDs, primary and
   supplementary groups, shadow/gshadow records, and inode ownership.
3. Design the smallest deterministic reconciliation and verification change.
4. Define fixture-level tests and the two-order `base + postgres + mysql`
   experiment before implementation.
5. Record any disagreement with `docs/REASSESSMENT_2026-09-10.md`.

No implementation has been authorized or started for this task yet.

## Handoff log

### 2026-09-10 — ChatGPT Codex — collaboration branch initialized

- Branch: `codex/collaboration`
- Upstream base: `main@31c99aac93ea60966fef12478f68f48c103cf22b`
- Goal: establish a safe communication protocol between ChatGPT Codex and
  local Codex without sharing an implementation branch.
- Changed files:
  - `AGENTS.md`
  - `docs/CODEX_HANDOFF.md`
- Tests: documentation-only change; no implementation tests run.
- Evidence: Git history on `codex/collaboration`.
- Unsupported claims: no new technical claim was added.
- Status: ready for the user and local Codex to review.
- Next action: pull `codex/collaboration`, read both files, and create a
  short-lived task branch only after agreeing on the first task.

## Handoff entry template

Copy this section, place the completed entry above older log entries, and
delete fields that truly do not apply.

```markdown
### YYYY-MM-DD — <actor> — <short task>

- Branch:
- Full commit SHA:
- Based on:
- Goal:
- Scope/files:
- Changes:
- Tests actually run:
- Test results and exit codes:
- Evidence paths or bundle IDs:
- Observations:
- Inferences:
- Unsupported/unverified claims:
- Blockers:
- Status: ready for review | ready for local testing | ready to merge | paused
- Exact next action:
```
