# 2 Background: packages and layered filesystems

## 2.1 Why package installation changes a filesystem

ModFS works with ordinary Ubuntu APT and dpkg packages rather than a new package format. APT resolves requested names against repository indices and chooses a package set. `dpkg` unpacks package-owned files, records their installed state, executes maintainer scripts, and runs triggers. These scripts can create users, register alternatives, write debconf answers, or regenerate caches. The dependency and conflict fields are declarative inputs to installation; their presence does not describe every write made during installation [@man-deb-control; @man-dpkg; @man-deb-triggers]. This distinction explains why a package set that is co-installable in metadata can still yield an incoherent composed filesystem.

ModFS builds a common base and independent siblings from one pinned archive view. Each sibling installation sees the base packages as already present, and its OverlayFS upperdir captures subsequent filesystem mutations. The archive pin stabilizes which package versions APT can resolve; it does not constrain every maintainer-script output. The project's current measured catalogue is for Ubuntu 22.04; Ubuntu 24.04 is a separate portability context (`ARCHITECTURE.md`, scope; `thesis/evidence/catalogue.md`).

## 2.2 The eight unowned system registry groups

A package's `.list` file identifies paths it owns. Many system databases are instead modified by package tools without being owned by one package. Each sibling may therefore contain a complete copy of the same path, and ordinary OverlayFS lookup shows only the uppermost copy. The resulting loss is silent: the files installed by a lower sibling can remain visible while the system database forgets them. ModFS treats the following **eight groups** as shared state (`docs/REGISTRY_FORMATS.md`). The first six are parsed and reconciled; the last two are regenerated from the merged state.

### 2.2.1 Package status: `/var/lib/dpkg/status`

This RFC-822-style database records package installation state. A record is identified by package name and architecture; version and installation status are among its fields. Taking one sibling's whole file loses the other sibling's package records. A union of records at the same version is meaningful, whereas different versions for one effective package cannot be combined into a truthful record [@man-dpkg].

### 2.2.2 Alternatives registry: `/var/lib/dpkg/alternatives/*`

Each generic name has a positional record of candidate paths, priorities, and slave links. In the catalogue, `vim` offers `/usr/bin/vim.basic` as an `editor` candidate at priority 30 and `emacs` offers `/usr/bin/emacs` at priority 0 (`docs/REGISTRY_FORMATS.md` §2). The candidate records must be united before the chosen link is computed. Taking one module's file discards a candidate. The corresponding `/etc/alternatives/*` symlinks are a *derived output* discussed below [@man-update-alternatives; @debian-policy-alternatives].

### 2.2.3 Diversions: `/var/lib/dpkg/diversions`

`dpkg-divert` records an original path, its diverted target, and the responsible package as consecutive line triples. Diversions permit a package to redirect a path legitimately used by another. Losing a lower layer's diversion leaves the merged files and dpkg's account of them inconsistent. A partial triple is malformed, not an empty record that may be ignored [@man-dpkg-divert; @debian-policy-diversions].

### 2.2.4 APT extended state: `/var/lib/apt/extended_states`

APT records whether a package was automatically installed as a dependency or deliberately requested. This matters for later `autoremove`. On a union, explicit manual intent must dominate an automatic mark: otherwise the composed system might consider a requested package disposable [@man-apt-mark].

### 2.2.5 Account databases: `/etc/passwd`, `group`, `shadow`, `gshadow`, `subuid`, `subgid`

These files map names to numeric identities, membership, password state, and subordinate ranges. An independent `postgres` build adds its account; an independent `mysql` build adds another. One top-layer `/etc/passwd` cannot represent both. The merger unions records and membership lists while preserving modes on sensitive files. Numeric UID/GID conflicts require an earlier build-time prevention policy because files are already owned by numbers when compressed. In particular, a union of names cannot change those owners [@debian-policy-users; @man-adduser-conf; @man-login-defs].

### 2.2.6 Debconf: `/var/cache/debconf/{config,templates,passwords}.dat`

Debconf's three databases contain question records identified by `Name`; `Owners` is a set of packages that asked a question. Independent installations can extend that set. The records must be merged by question and the owners united, while incompatible values are conflicts. The `passwords.dat` file follows the same record logic and requires its sensitive file mode to survive. The rough draft omitted it and called `config.dat` and `templates.dat` binary/text; the reference formats describe record-oriented text stanzas. Omitting the password database would leave a real shared-state path outside the declared rule [@man-debconf; @man-debconf-devel].

### 2.2.7 Alternative symlinks: `/etc/alternatives/*`

These links are **regenerated, not merged**. Once candidate records and priorities have been united, `update-alternatives --auto` computes the selected target. Merging old symlinks would preserve a result from one sibling's incomplete candidate set [@man-update-alternatives].

### 2.2.8 Dynamic linker cache: `/etc/ld.so.cache`

This binary index is also **regenerated, not merged**. `ldconfig` scans the libraries and configuration visible in the composed tree and writes the cache for that tree. The old cache from either sibling indexes only its own build view [@man-ldconfig]. The distinction between the six merged and two regenerated groups is semantic: records represent persistent facts to combine; these outputs are functions to recompute.

## 2.3 OverlayFS capture and the meaning of a layer

OverlayFS presents a merged view of read-only lower directories and a writable upperdir. Reading a path follows layer priority; writing a lower file first copies it up; deleting it creates a whiteout. An opaque directory stops lower-directory lookup at that path [@overlayfs-kernel]. ModFS uses this behavior twice: during a sibling build to capture package installation changes in an upperdir, and during server-side composition to present selected read-only siblings plus a top reconciliation layer. The same marker can have different meaning in those contexts. A directory marked opaque against the base during build can later hide unrelated sibling files, which motivates ModFS's explicit opaque-marker policy in Chapter 4.

SquashFS stores the captured tree as a compressed, read-only filesystem that the kernel can mount directly [@squashfs-kernel; @man-mksquashfs]. It can retain whiteouts and extended attributes, but compression and faithful storage alone do not establish that independent layers compose correctly. Package-owned path collisions, unowned registries, and runtime service resources each need a separate policy. This background leads to the related-work question: which earlier systems address namespace layering, package relations, reproducibility, or distributed storage, and which of those results apply to this specific composition problem?
