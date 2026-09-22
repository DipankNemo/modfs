# The eight reconciled registries — record formats and merge rules

**Chapter: Implementation**

`ARCHITECTURE.md` §4 says these files need a "semantic union — you must parse the
file to merge it". It never says what a record looks like, so it never says what
*parsing* them means or what a conflict actually is. This document closes that:
per registry, the real record format, what identifies a record, what OverlayFS
does to it, the merge rule, and the case that cannot be merged.

Every example below is a real record extracted from the catalogue with
`unsquashfs -cat`, not an invented one.

## Why these files are a class of their own

A registry is a file that **no package owns** and that **every package rewrites**.
That combination is what makes them conflict class 5, distinct from every other
class:

- `dpkg` does not list them in any package's `.list`, so **conflict class 4
  (file collision) cannot see them** — no two packages "own the same path",
  because no package owns them at all.
- OverlayFS resolves a path by taking the **topmost layer's copy, entire**. For
  ordinary files that is correct. For a registry it means the top module's view
  of the world silently replaces every lower module's.

So stacking two modules that each installed packages gives a system where `dpkg`
knows only about the top module's packages, while the lower module's files are
all still present. The system is running software it does not know it has.

---

## 1. `/var/lib/dpkg/status` — the package database

**Format.** RFC-822 stanzas separated by a blank line. One stanza per package.

```
Package: adduser
Status: install ok installed
Priority: important
Section: admin
Installed-Size: 608
Architecture: all
Version: 3.118ubuntu5
Depends: passwd, debconf (>= 0.5) | debconf-2.0
Conffiles:
 /etc/adduser.conf 1e4d1d4a9d4b0e1f...
```

**Key.** `Package` plus `Architecture` — the same name can be installed for
`amd64` and `i386` as separate records.

**What goes wrong.** Two modules, two complete status files. The top one wins and
every package the lower module installed becomes invisible: `apt` would reinstall
them, `autoremove` would delete files another module depends on.

**Merge rule.** Union by key. Where both layers carry the same package at the same
version, either copy will do; the later layer wins, which matters only for fields
like `Installed-Size` that both agree on anyway.

**What cannot be merged.** The same package at **different versions** — one set of
files is on disk and the record must describe those files, so there is no correct
union. That is conflict class 2, rejected at tier 1.

---

## 2. `/var/lib/dpkg/alternatives/<name>` — the alternatives registry

**Format.** A flat line-oriented file with no delimiters, read positionally:

```
auto                                  <- the mode
/usr/bin/editor                       <- the generic name (the "link")
editor.1.gz                           <- slave link name
/usr/share/man/man1/editor.1.gz       <- slave link path
...                                   <- more slave pairs
                                      <- BLANK LINE ends the slave list
/usr/bin/vim.basic                    <- candidate 1: its path
30                                    <- candidate 1: its PRIORITY
/usr/share/man/man1/vim.1.gz          <- candidate 1's slave targets
...
                                      <- blank line ends this candidate
```

**Key.** The file name is the generic name; within it, each candidate is keyed by
its path.

**What goes wrong, with the real numbers.** `vim` registers `/usr/bin/vim.basic`
at **priority 30**. `emacs` registers `/usr/bin/emacs` at **priority 0**. Under
`auto` mode the highest priority wins, so on the merged system `/usr/bin/editor`
must resolve to vim. Take the top layer's file entire and whichever module was
stacked last is the only candidate that exists.

**Merge rule.** Union of candidates, keeping each one's priority. `/etc/alternatives/*`
— the actual symlinks — are then **regenerated** by `update-alternatives --auto`
rather than merged, because they are a *function* of this registry rather than
content of their own.

**What cannot be merged.** Two layers offering the **same candidate path at
different priorities**. Until 17 September the later layer simply won, so a module
owning *zero files* could silently change which binary `/usr/bin/editor` resolves
to. It is now reported as a conflict and the higher priority is kept.

---

## 3. `/var/lib/dpkg/diversions` — the diversion registry

**Format.** Line triples, with **no separator between records**:

```
/usr/share/man/man1/sh.1.gz           <- original path
/usr/share/man/man1/sh.distrib.1.gz   <- where the original was moved to
dash                                  <- the package that owns the diversion
/bin/sh                               <- next record begins immediately
/bin/sh.distrib
dash
```

**Key.** The original path.

**What goes wrong.** A diversion is how two packages legitimately ship the same
path — `dash` diverts `/bin/sh` so `bash` can provide it. Lose the diversion and
`dpkg` no longer knows why the file it expects is somewhere else.

**Merge rule.** Union by original path.

**What cannot be merged.** A file whose line count is **not a multiple of three**.
Because records have no separator, a parser that reads complete triples and stops
will silently discard a trailing partial record and report success. Found in round
4 as R4-3 and again as R4-8 in the sidecar writer — the same defect twice, because
the merger and the extractor parsed the file independently. Both now reject it.

---

## 4. `/var/lib/apt/extended_states` — the auto-installed flags

**Format.** RFC-822 stanzas again, but a different schema from `status`:

```
Package: libip4tc2
Architecture: amd64
Auto-Installed: 1
```

**Key.** `Package` plus `Architecture`.

**What goes wrong.** `Auto-Installed: 1` means "apt pulled this in as a dependency
and may remove it when nothing needs it". If a module requested a package
*explicitly* and the merged file says it was automatic, `apt autoremove` on the
deployed node will delete it.

**Merge rule.** Union by key, and **manual wins over automatic**: if any layer
requested the package explicitly, the merged system must not treat it as
disposable. This is the one registry where the rule is not "later layer wins" —
it is a deliberate asymmetry, because the two states are not symmetric in
consequence.

---

## 5. `/etc/passwd`, `group`, `shadow`, `gshadow`, `subuid`, `subgid` — the account databases

**Format.** Colon-separated, one record per line, a different field count each:

```
passwd   (7)  postgres:x:5200:5201:PostgreSQL administrator,,,:/var/lib/postgresql:/bin/bash
group    (4)  ssl-cert:x:5200:postgres
shadow   (9)  postgres:!:20353:0:99999:7:::
gshadow  (4)  ssl-cert:!::postgres
subuid   (3)  root:100000:65536
```

Field counts live in `scripts/account_schema.py` so the merger, the verifier and
the extractor cannot drift apart.

**Key.** The name, in field 0 — except `subuid`/`subgid`, where one name may hold
several ranges and the whole line is the key.

**What goes wrong, with the real numbers.** `postgres` adds
`postgres:x:5200:5201`; `mysql` adds `mysql:x:5300:5300`. Take the top layer's
`/etc/passwd` and one of the two accounts vanishes while its files remain on disk,
owned by a numeric UID with no name behind it.

**Merge rule.** Union by name, **and member lists are unioned rather than
overwritten**. The real case: `postgres` adds itself to `ssl-cert`'s member list,
giving `ssl-cert:x:5200:postgres`. Another module adding a different member to the
same group must not erase that one, so field 3 of `group` and fields 2 and 3 of
`gshadow` merge as sets.

**What cannot be merged.** The same name with a **different numeric identity** —
one set of files on disk is owned by one number. That is conflict class 7, and it
is prevented up front by partitioning UID ranges per module (`specs/uid-ranges.yaml`,
100-wide windows from 2000, append-only) rather than detected afterwards. Note
`postgres` at 5200 and `mysql` at 5300: different windows, by construction.

A subtler case: the same name and UID but a **different primary GID**. Found in
round 4 as R4-1 — the comparison read field 2 and never field 3, so a user could
keep its UID while silently changing group.

---

## 6. `/var/cache/debconf/{config,templates,passwords}.dat` — the answer database

**Format.** RFC-822 stanzas, with a field that is semantically a **set**:

```
Name: adduser/homedir-permission
Template: adduser/homedir-permission
Value: false
Owners: adduser
```

**Key.** `Name`.

**What goes wrong.** `Owners` lists every package that asked this question. Two
modules install packages that share a question and each writes its own owner list.
Last-writer-wins drops the other module's owners, and a later `dpkg-reconfigure`
believes a package no longer owns a question it answered.

**Merge rule.** Union by `Name`, with `Owners` merged **as a set**, not
concatenated. `passwords.dat` merges identically but keeps its file mode, because
it holds secrets.

**What cannot be merged.** Two layers giving the same `Name` a **different
`Value`** — the answer configures software already installed, so neither answer
can be discarded silently. Found 18 September; before that the whole debconf group
was not merged at all.

---

## 7. `/etc/alternatives/*` and 8. `/etc/ld.so.cache` — regenerated, not merged

These two are **functions of the merged state rather than content in their own
right**, so merging them would be merging a cache:

- `/etc/alternatives/*` is the set of symlinks implied by registry 2. Regenerated
  with `update-alternatives --auto`.
- `/etc/ld.so.cache` is a binary index of every shared library on the system.
  Regenerated with `ldconfig`.

Deriving them again from the merged inputs is both simpler and more obviously
correct than parsing a binary cache and unioning it. The cost is that the compose
step must run two external tools, and a failure in either is a composition
failure — `10_compose_sweep.sh` treats a regeneration failure as exactly that
rather than swallowing it.

---

## What the merge rules have in common

Four distinct shapes, and which one applies is a property of the record's meaning
rather than of its syntax:

| Shape | Registries | Why |
|---|---|---|
| Union by key, later layer wins | dpkg status, diversions | records are independent; a duplicate key at the same version is genuinely identical |
| Union by key, **fields merged as sets** | account member lists, debconf `Owners` | the field is a set that several modules legitimately contribute to |
| Union by key, **asymmetric precedence** | extended_states | manual beats automatic because the consequences are not symmetric |
| **Regenerate** | `/etc/alternatives`, `ld.so.cache` | derived state, not content |

The verification that these merges are correct is V1–V8 in
`scripts/verify_compose.py`, checked on every composition: V2 covers registry 1,
V3 registry 2, V4 registry 8, V6 registry 5 and V8 registry 6.
