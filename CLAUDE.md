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


## Privilege boundary
You cannot run builds — they need root (overlay, chroot) and network (apt).
Test logic on fixtures under `unshare -r` or synthetic trees, then hand me the
exact commands to run. I'll paste the output back. This stays true: anything
that writes, builds, mounts or deletes goes through me, so I stay in the loop.

For READ-ONLY inspection of root-owned artefacts, use:

    sudo /usr/local/sbin/modfs-read {xattr|du|ls|cat|head|tail|stat} <path>

Use it freely without asking — it cannot change anything. It exists because
artefacts are root-owned and the things that matter for diagnosis are exactly
the things unprivileged reads fail on: overlay xattrs (is a directory opaque?),
directory sizes, root-mode logs.

It is confined to `/srv/modfs`, canonicalises every path with `readlink -f`
BEFORE checking it (so a symlink pointing at `/etc` is refused, not followed),
offers no shell and no `-exec`, and has no operation that writes.

Source is `tools/modfs-read`. The INSTALLED copy at /usr/local/sbin must be
root-owned and not writable by me — if sudo pointed at the repo copy, anyone who
can edit this repo could rewrite the script and escalate to full root. Do not
ask for broader sudo; if you need something this cannot do, hand me the command.