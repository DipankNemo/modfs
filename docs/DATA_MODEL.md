# The data model — what a module records, and how it is trusted

**Chapter: Implementation**

`docs/REGISTRY_FORMATS.md` covers what composition *merges*. This covers what the
system *records*: the three files a module is, the two hand-written spec files
that are the source of truth, and the digests that bind them together. Every
figure below is read from the real catalogue.

## A module is three files, not one

```
/srv/modfs/modules/postgres.sqsh            the delta artefact -- the bytes
/srv/modfs/modules/postgres.json            the manifest -- what tier 1 reads
/srv/modfs/modules/postgres.files.json.zst  the class-4 sidecar -- path ownership
```

The split exists because the three are read at different costs. Tier 1 admits or
rejects a set by reading **only the manifest**: no mount, no root, 89 ms at N=2.
The sidecar is read only when a check needs per-file ownership. The artefact is
touched only when something actually composes.

That is the whole reason a tiered model is possible. If admission needed the
artefact, tier 1 would cost what tier 2 costs.

## The manifest — `<name>.json`, schema 1

Twenty-one top-level keys, in four groups.

**Identity and provenance.** `schema`, `module`, `version`, `parent`, `snapshot`,
`suite`, `arch`, `built`, `generation`.

**What the module asked for and got.** `requested` is what the operator wrote in
the spec (`["postgresql"]`); `packages` is what APT actually resolved — 29 entries
for postgres, name to version. The distinction matters: `requested` is intent,
`packages` is fact, and conflict class 6 is precisely the case where the fact
includes an upgrade of something inherited from the parent.

**Module-level relations.** `requires`, `conflicts`, `provides`, `removed`.
These are *between modules*, a layer above Debian's own `Depends`/`Conflicts`
between packages.

**What the module did to the system.** `uid_range` (`start`/`end`), `accounts`
(`users`, `groups`, `shadow`, `gshadow`, `file_uids`, `file_gids`),
`identity_audit`, `units`, `artifact` (`file`, `bytes`, `sha256`).

`accounts.file_uids` and `file_gids` deserve a note: they are the numeric owners
found on *files in the delta*, not the accounts the module declared. A module can
ship a file owned by uid 2500 without ever declaring that account, which is how it
would silently inherit another module's identity. Comparing declared records alone
missed that for most of the project.

## The sidecar — `<name>.files.json.zst`

Its full name is the **class-4 file-ownership sidecar**: it answers "which package
owns this path", which is exactly what conflict class 4 needs and what `dpkg`
would otherwise have to be asked inside a mounted tree.

```json
{"schema": 1, "module": "postgres",
 "files": {"/etc/ethertypes": "netbase", ...},
 "diversions": [{"path": "/usr/bin/pg_config", "to": "/usr/bin/pg_config.libpq-dev", ...}]}
```

postgres maps **5,904 paths**. Uncompressed that is 380 KB; zstd brings it to
**28.6 KB**, a 13x reduction, which is why it is stored compressed and read on
demand rather than folded into the manifest.

It exists as a separate file for a blunt reason recorded in the build script: the
build tree is deleted after the artefact is made, so path ownership has to be
captured at build time or it is gone. Re-deriving it later would mean mounting the
artefact and running `dpkg` inside it — tier-2 cost for a tier-1 question.

## The three seals, and the one that cannot cover itself

```
binding.artifact_sha256   digest of the .sqsh
binding.sidecar_sha256    digest of the .files.json.zst
binding.fields_sha256     digest over 17 named manifest fields
binding.fields            the list of those 17 field names
binding.source            "artifact" -- the manifest was derived FROM the bytes
```

`fields_sha256` covers a **named list** of fields rather than the whole document.
That is deliberate: it means the seal states exactly what it protects, and a
consumer can refuse a manifest whose `fields` list is shorter than the one it
requires. Sealing "the whole file" would have been simpler and weaker — anything
could be dropped and resealed, and the seal would still verify.

The asymmetry worth writing about: **`sidecar_sha256` lives inside `binding`, so it
cannot be inside its own digest.** Deleting that one field used to leave a manifest
that still verified perfectly while no longer committing to any sidecar, so a
tampered sidecar could invent collisions or erase evidence. The fix was not
cryptographic — it was to move the requirement from the document to the consumer:
`manifest_binding.validate_manifest()` now *rejects* a manifest whose
`sidecar_sha256` is missing or malformed, and `load_sidecar()` refuses to parse
ownership data until the digest matches. **A document cannot opt out of being
checked.**

## The generation identifier

`generation` is `sha256({snapshot, suite, arch, base_sha256})` plus those four
fields in clear. One generation is one archive view and one exact base artefact.

Module specs are deliberately *not* in it: a module may be rebuilt within a
generation. It is an integrity identifier, not a signature.

This is what makes "composable" checkable rather than assumed. Two modules are
siblings only if they share a parent, a snapshot, a suite, an arch **and** a
generation — and the positive control `control-oldsnap`, built from snapshot
`20250401T000000Z`, fails both `snapshot` and `generation` against a base built
from `20260701T000000Z`. Those two failures on the same 39 pairs are why the
`not_composable` counter reads 78 and not 39.

## The two spec files — the actual source of truth

Everything above is *derived*. These two are written by hand and are the inputs.

### `specs/modules.yaml`

Per module: `name`, `packages` (what APT is asked for), `probe` (a shell command
run inside the composed chroot that must exit 0), `provokes` (which conflict class
this module exists to exercise), `requires`/`conflicts`/`provides`, `version`, and
for the positive control a `snapshot` override.

`provokes` is the unusual field and the honest one: **this catalogue is
adversarial, not representative.** Modules are here to provoke conflict classes,
not to model real deployments. `vim` and `emacs` exist because both register
`/usr/bin/editor`; the two `nc` variants exist because they look like a file
collision and are not.

The drift risk is real and has bitten: `jq`'s spec asked for `jq moreutils` while
the built artefact carried `jq` alone, 0.6 MB against 10.4 MB, and the published
storage ratio was computed from a module that did not match its own definition.
Nothing had compared the two.

### `specs/uid-ranges.yaml`

`width: 100`, `first: 2000`, then a name-to-start map — `vim: 2000`, `emacs: 2100`,
`postgres: 5200`, `mysql: 5300`. Append-only.

This is **prevention rather than detection**, and the reason is in the file's own
header: four modules in the original catalogue independently allocated uid 103 to
four different names, because Debian's dynamic system range (100-999) is the same
for every build. OverlayFS cannot union conflicting numbers. Partitioning the space
means the collision cannot be constructed, so class 7 becomes a check that should
never fire rather than a conflict to resolve.

## What was hard, and what was not

Worth saying plainly in the thesis, because "we merged some files" hides the
distribution of difficulty.

**Genuinely simple.** `dpkg/status` and `diversions`: union by key, and both are
plain text with an obvious record boundary. `extended_states` likewise once the
manual-over-automatic asymmetry was noticed.

**Simple mechanism, hard to notice.** The account files are four lines of parsing
each — but there are six of them, they have four different field counts, and
`shadow` holds secrets so its mode matters. The difficulty was never the merge; it
was knowing the file needed merging at all. Each was found by a composition
behaving wrongly, not by reading documentation.

**Hard, and solved by not doing it.** `/etc/ld.so.cache` is a binary index and
`/etc/alternatives/*` is a symlink farm. Both could be parsed and merged. Both are
*functions of the merged state*, so regenerating them with `ldconfig` and
`update-alternatives --auto` is simpler and more obviously correct than any merge.
Recognising which state is derived is the reusable lesson.

**OS and toolchain specifics that cost real time.**

- **dpkg stores numeric ids as strings** in its metadata while `os.lstat` returns
  ints. Comparing them directly made the class-7 ownership check reject the entire
  catalogue: the sweep planned zero compositions.
- **SquashFS carries xattrs through a round trip**, including
  `trusted.overlay.opaque`. A marker written when the only lower layer was the
  base — where it hid nothing — erased a sibling module's files at compose time,
  when "below" had become that sibling. Measured across 38 modules: 869 markers,
  456 directories, 178 claimed by two or more. Fixed by stripping `opaque` at
  squash time; whiteouts are kept, so file-level deletion still works.
- **The kernel caps mount data at 4096 bytes.** OverlayFS packs every lower layer
  into one option string, so a 37-layer set succeeded or failed depending on how
  long its scratch directory name was. Relative lowerdirs took 4319 bytes to 419.
- **Ubuntu 24.04 needs two packages 22.04 did not.** `adduser`, because noble's
  minbase no longer retains `/etc/adduser.conf` and the builder needs it to
  establish UID ranges before APT runs; and `systemd-boot-efi`, because noble split
  the EFI binary out. Both found by the build failing with a precise error, not by
  reading release notes.
- **Package names move between releases.** Six CUDA 11 library names do not exist
  in 24.04, and `linux-objects-nvidia-535-5.15.0-*` has no 24.04 counterpart. Four
  of 40 modules needed noble-specific edits; **36 did not**, which is the more
  interesting number.
