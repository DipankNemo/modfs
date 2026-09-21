# Reference digest — per-paper factual notes

Source texts: `/home/kaptan/modfs/thesis/refs/txt/*.txt` (plain-text extractions,
named by BibTeX key). Bibliography: `/home/kaptan/modfs/thesis/refs/refs.bib`
— note the path is `refs/refs.bib`, **not** `refs/pdf/refs.bib`; the file in
`refs/pdf/NOTES.md` is zero bytes.

Scope of this file: factual comparison only. Each entry states (1) the paper's
own claim in its authors' terms, (2) the mechanism it shares with ModFS if any,
(3) the concrete difference in treatment, (4) which specific ModFS claim it
supports, contextualises or challenges. No Related Work argument is made here
and the entries are ordered alphabetically by key, not narratively. Where the
extracted text does not support a comparison this is stated rather than filled in.

Matched against: `ARCHITECTURE.md` §3 (assumption B and its 2026-09-16
revision), §4 (taxonomy, "Class 7", "Numeric uniqueness is not database
composition", "Class 5 — measured, not assumed"), §8 (reproducibility),
§13 (update strategy); `docs/STATE_OF_PLAY_2026-09-18.md` §2 (nine classes,
class 8, class 9) and §3 (the registry table).

---

## Prior-art flags

Items where a cited paper appears to already cover something ModFS presents as
discovered or novel. Each is specific and quoted. An examiner who has read
these papers will expect them cited at the point of the corresponding claim.

### F1 — The opaque-directory marker is prior art (`pendry1995union`), including its rationale

STATE_OF_PLAY §2 introduces class 9 around `trusted.overlay.opaque` as a
mechanism discovered by running the system. The *mechanism and its motivating
example* are in Pendry and McKusick 1995, §5, in the same form:

> "Whenever a whiteout is replaced by a directory, the directory inode is
> automatically tagged with the opaque attribute. During a lookup in a union
> stack, the union filesystem does not continue to the lower layer object if the
> upper layer object is marked opaque. To understand this requirement, consider
> the sequence of operations: `rm -rf tree` / `mkdir tree` … Without the opaque
> attribute, the normal union semantics would make the lower layer `tree`
> visible once more."

They also provide the manual escape hatch ModFS achieves by stripping the xattr:
"the opaque attribute can be turned off manually using the `chflags(1)` command."

What is **not** in Pendry: the specific ModFS failure. 4.4BSD sets opaque *only*
where a whiteout was replaced by a directory, so an opaque flag there always
encodes a real deletion. ModFS measured the opposite condition — 869 markers,
456 distinct directories, **zero** of which exist in base and **zero** modules
carrying a whiteout — i.e. markers that encode no deletion at all. The closest
Pendry gets to class 9's root cause is about *whiteouts*, not opaque, and about
*reordering*, not layer substitution (§7, Union stack management):

> "The expectation is that the logical ordering of the union stack will be
> unchanged for the lifetime of the usage of the filesystems. Changing the
> ordering of the layers will have the greatest effect on whiteouts. Since the
> whiteouts themselves are created within the filesystems, if the filesystems
> are re-ordered, the effect of the whiteouts will vary."

**Action implied:** cite `pendry1995union` for the opaque attribute itself and
for the general "markers are relative to the stack that made them" hazard.
Class 9's claimed novelty must narrow to: *a marker created against a build-time
stack (base only) being reinterpreted at compose time against sibling layers
that did not exist when it was written, producing erasure with no file
collision* — plus the measurement (869/456/178) and the squash-time fix.

### F2 — Class 4's detection method is prior art (`treinen2008solving` §2.2.5)

ARCHITECTURE §4 lists class 4 detection as "Intersect per-module
`<name>.files.json.zst` sidecars; honour `Replaces:` and diversions".
Treinen and Zacchiroli 2008 §2.2.5 "Application: Finding File Conflicts in
Debian" describes the same pipeline on the distribution's `Contents` index:
pairs sharing at least one file, then filtered by exactly the two suppression
rules ModFS uses, plus non-co-installability:

> "1. The two packages are not co-installable by the package relationships
> declared in their distribution … 2. One of the packages, say A, declares that
> it has the right to replace files owned by B, by having in its control file a
> stanza `Replaces: B`. 3. One of the packages, say B, diverts the file F …"

They report the funnel: 200,000,000 theoretical pairs → 867 sharing a file →
102 co-installable → 27 real file overwrites. They also state the reason ModFS
must use a static sidecar rather than reading the live diversion database:
diversions are registered by `postinst`, which "is written in a Turing complete
language … which means that exact semantic properties are undecidable."

**Action implied:** cite this at class 4 rather than presenting file-collision
detection by ownership intersection as new. The genuinely ModFS-specific parts
are the unit (a *module* = a delta artefact, not a distribution package), the
tightened suppression rule (STATE_OF_PLAY §5a: bare `Replaces` was accepted and
flipped a verdict REJECT→ACCEPT with unchanged artefact bytes; ModFS now
requires `Replaces` **plus** `Breaks`/`Conflicts`), and the fact that Treinen
resolves the diversion undecidability by *actually installing each pair in a
chroot*, which is ModFS tier 2/3 work, not tier 1.

### F3 — Classes 2 and 3 are already formalised (`mancinelli2006managing`, `vouillon2013coinstallability`, `treinen2008solving`)

- **Class 2 (version skew: same package, different versions).** Formalised as an
  axiom of the repository model. Mancinelli et al. 2006, Definition 2: "Two
  packages with the same unit but different versions conflict, that is, if
  π1 = (u, v1) and π2 = (u, v2) with v1 ≠ v2, then (π1, π2) ∈ C." Treinen and
  Zacchiroli 2008 give the identical condition in their Definition 2 and note it
  "is specific to Debian (RPM does note [sic] have this a priori restriction)."
  Mancinelli's footnote 5 says RPM allows several versions of a unit "at least
  in principle (if, for example, they do not install files in the same
  location)" — i.e. the version/file-collision interaction is noticed in 2006.
- **Class 3 (declared conflict, including virtual names).** The conflict relation
  C *is* `Conflicts:`, and virtual names are handled by an explicit expansion
  step. Treinen §2.1: "Expansion also introduces explicitly the virtual package
  which depends on all packages that provide it. Special care has to be taken
  with conflicts on virtual packages as a package may at the same time provide a
  virtual package and conflict with it. Section 7.4 of the Debian policy states
  that in this case the package conflicts with each package providing that
  virtual package, with the exception that the package doesn't conflict with
  itself." Vouillon and Di Cosmo 2013 §2: "Extra properties like `provides` …,
  or versioned constraints … can be easily preprocessed out [Mancinelli et al.
  2006]".
- **`Breaks:` is explicitly outside these models.** Treinen §2.1: "The `Replaces`
  relation concerns only the installer (not the meta-installer), and the same
  seems to be true for the `Breaks` relation (which wasn't included in policy
  anyway at the time of the EDOS project)." ModFS's class 3 does cover `Breaks:`
  and its class 4 does use `Replaces:`, so those two specific inclusions are
  outside the cited formalisations and can be claimed as extensions.

### F4 — Class 4 is **not** in the co-installability model (`vouillon2013coinstallability`)

Co-installability as Vouillon and Di Cosmo define it is a metadata-level
property only. Their repository is a tuple (P, D, C) over package names; the
paper's own statement of the research programme is: "it is only assumed that
each component carries with itself a small amount of metadata describing what
the component provides and what it requires to be deployed and run". Files,
paths and file ownership do not appear anywhere in the model, and the words
"file conflict" / "overwrite" do not appear in the extracted text. Their
co-installability is therefore *necessary but not sufficient* for ModFS
composability — which is exactly the relation Treinen §2.2.5 uses it in (stage 1
of two). This is a supporting, not challenging, result for ModFS's claim that a
file-level check is needed in addition to metadata, and it should be stated
that way rather than left implicit.

### F5 — Class 5's underlying mechanism, but not its handling, is in `wright2006namespace`

Wright et al. state the cause of class 5 as the first of four "key problems" of
namespace unification: "just because two files may have the same name, it does
not mean they have the same data or attributes. Unix files have only one data
stream, one set of permissions, and one owner; but in a unified view, two files
with the same name could have different data, permissions, or even owners. Even
with duplicate name elimination, the question still remains which attributes
should be used. The solution to this problem often involves defining a priority
ordering". And the design consequence: "For regular files, devices, and symlinks,
Unionfs performs operations only on the leftmost object. This is because
applications expect only a single stream of data when accessing a file."

That is precisely the OverlayFS behaviour ARCHITECTURE §4 describes as "OverlayFS
takes the top layer's copy *entire* — it cannot union text records". So the
*mechanism* of class 5 is catalogued prior art; ModFS should not present
"top-layer-wins on regular files" as a finding.

What is **not** in Wright: any notion of shared mutable state files, package
registries, or content-level merging. There is no discussion of `/var/lib/dpkg/*`,
`/etc/passwd`, debconf, alternatives or diversions; no proposal that a union
filesystem should ever parse and merge file contents; and the word "opaque" does
not occur in the paper at all. The specific ModFS contribution therefore stands:
the *enumeration* of which files behave this way in a Debian system (the
STATE_OF_PLAY §3 table), the reconciliation layer, and the computable definition
of "registry" as *non-package-owned files shared by two or more modules*.

### F6 — Class 9's problem shape (not its marker) also appears in `wright2006namespace`

Unionfs meets the same semantic requirement the opaque flag exists for, and
solves it differently: "if `mkdir` succeeds, the newly-created directory merges
with any directories to the right which were hidden by the removed whiteout.
This would break Unix semantics, as a newly-created directory is not empty. When
a new directory is created after removing a whiteout, Unionfs creates whiteouts
in the newly-created directory for all the files and subdirectories to the
right." This is an *enumerated* set of whiteouts computed against the branches
present at creation time, rather than a single flag that is re-evaluated against
whatever is below at mount time. Both designs bind the marker to the stack that
created it; ModFS's contribution is the observation that a build/compose split
makes those two stacks different sets of layers, which Unionfs does not consider
(its dynamic-branch section, §3.7, is about cache revalidation and generation
numbers, not about the semantics of stale markers).

### F7 — The cross-host build-diff experiment is anticipated by `dolstra2008nixos` §6.2

ARCHITECTURE §8 reports a cross-host base rebuild differing in bytes with all 113
package-version records agreeing, and attributes residual differences to
timestamps/date fields, host toolchain and layout. NixOS 2008 ran the same shape
of experiment and reported the same shape of result: two builds of 485
derivations on two machines, 165,927 files and directories, one differing file
*name*, "differences in 5059 files, or 3.4% of all regular files … almost all
were caused by timestamps being encoded in files … Filtering out these … we were
left with 644 files, or 0.4% … only 42 (or 0.03%) had different file sizes."
ModFS's negative result is therefore consistent with a published 2008
measurement, not a surprise; the honest framing is "reproduces a known result on
a different artefact type (SquashFS deltas rather than store paths)".

### F8 — Byte-reproducibility technique is a standard, not a finding (`lamb2022reproducible`)

ARCHITECTURE §8's hygiene list (`-mkfs-time`/`-all-time` pinned to
`SOURCE_EPOCH`, log exclusion, `aux-cache` exclusion, archive-metadata
normalisation) implements measures Lamb and Zacchiroli catalogue: the
`SOURCE_DATE_EPOCH` variable ("the Reproducible Builds project proposed the
`SOURCE_DATE_EPOCH` environment variable as a way to communicate an acceptable
timestamp to build systems"), archive metadata normalisation ("instructing tools
to ignore on-disk values in favour of metadata chosen by the build system"), and
non-deterministic directory ordering. Their Definition 1 is also the strict form
of the claim ModFS must be careful with: "The build process of a software
product is reproducible if, after designating a specific version of its source
code and all of its build dependencies, every build produces bit-for-bit
identical artifacts, no matter the environment in which the build is performed."
By that definition ModFS is *not* reproducible (ARCHITECTURE §8, remote
counterexample), which the thesis already states; the flag is only that the
mitigations must be cited as implementing an existing specification.

### F9 — Content-addressed component identity is prior art (`dolstra2004nix`)

ARCHITECTURE §13 relies on "an identical artefact can be reused from an existing
content-addressed cache". Nix 2004 is the canonical citation for that idea, and
its version is stronger: store paths are "computed by hashing all inputs
involved in building the component", so "a given store path uniquely determines
the store object". ModFS pins one archive snapshot ID and hashes *outputs*
(`artifact.sha256`, `binding.fields_sha256`); it does not hash the build inputs,
which is why host toolchain drift is invisible to its identity scheme. This is
an accurate and citable difference, but content addressing itself must be cited.

### F10 — Shipping only the changed part of a read-only release is prior art (`howard1988afs`, `howard1988scale`)

AFS volume movement already ships deltas from copy-on-write snapshots: "The
actual movement is accomplished by creating a frozen copy-on-write snapshot of
the volume called a Clone … If the volume does change, the procedure is repeated
with an incremental clone by shipping only those files that have changed." And
read-only clones already provide the atomic-release-with-rollback property
ARCHITECTURE §13 describes: "Read-only volumes are valuable in system
administration since they form the basis of an orderly release process for
system software. It is easy to back out a new release in the event of an
unanticipated problem with it." ModFS's deltas are produced by a different
mechanism (OverlayFS upperdir at *package-install* granularity, squashed
separately and composed on the server) and its rollback is redeployment of a
retained flattened image, but the "ship the delta, roll back by reverting to a
retained read-only release" pattern is 1988 prior art.

### Not covered by any of the 17 papers

On the extracted texts, no paper covers: (a) the reconciliation of Debian
registry files as a *set* — the STATE_OF_PLAY §3 table and `reconcile.py`;
(b) class 7 numeric identity collision across independently built layers and its
prevention by disjoint pre-install UID/GID windows; (c) class 8 runtime resource
conflict as a stated limit of static analysis; (d) the build-time-versus-
compose-time marker mismatch that produces class 9. Items (a)–(d) remain the
places where the thesis is not duplicating a cited result.

---

## dolstra2004nix

Eelco Dolstra, Merijn de Jonge and Eelco Visser, "Nix: A Safe and Policy-Free
System for Software Deployment", 18th Large Installation System Administration
Conference (LISA '04), USENIX, pp. 79–92, 2004.

The authors claim that existing deployment systems are neither safe nor
policy-free, and that both problems follow from one technique: "using
cryptographic hashes to compute unique paths for component instances", giving
concurrent installation of multiple versions, atomic upgrade and rollback, safe
(complete) dependency closures and safe garbage collection. The shared mechanism
is content addressing for identity and reuse: Nix names each component by a hash
of all its build inputs, so "a given store path uniquely determines the store
object", and deploys *closures* under the depends-on relation. The concrete
difference is what is hashed and what composition means. Nix hashes **inputs**
and composes by building a user environment as "a single directory" of symlinks
to store paths, with precedence resolved by the environment's build script; ModFS
hashes **outputs** (`artifact.sha256` over the `.sqsh`, `binding.fields_sha256`
over manifest fields) and composes by stacking read-only OverlayFS lowerdirs plus
a computed reconciliation layer, then flattening to ext4 — so ModFS gets a
conventional FHS root and Nix does not, and ModFS's identity scheme cannot see
build-input drift (the host debootstrap/libzstd difference in ARCHITECTURE §8)
whereas Nix's would change the store path. Nix also states its own boundary in
terms that bear directly on ModFS class 5: describing a complete Apache/Subversion
server configuration, "The only thing not under Nix control here is state –
things that are modified by the server, e.g., the actual Subversion repositories
and user account databases." This supports ModFS's claim that shared mutable
registries are a separate problem from package composition, and contextualises
the pinning claim (ARCHITECTURE §2, "Central claim"): Nix reduces the same
conflict problem by per-component isolation and hashing, ModFS by a single
archive pin plus sibling-only composition, and the two are alternative reductions
of the same problem, not the same reduction. *Extraction quality: two-column
PDF, columns interleaved line-by-line; sentences read correctly only when the
left and right halves of each line are separated by eye. Figures and the store
diagram are lost. No OCR garbling of words.*

## dolstra2008nixos

Eelco Dolstra and Andres Löh, "NixOS: A Purely Functional Linux Distribution",
13th ACM SIGPLAN International Conference on Functional Programming (ICFP '08),
pp. 367–378, 2008.

The authors claim that system configuration management should be purely
functional: "all static parts of a system (such as software packages,
configuration files and system startup scripts) are built by pure functions and
are immutable", from which deterministic reproduction, side-by-side versions,
atomic upgrade and trivial rollback follow. Two mechanisms are shared with ModFS:
content-addressed immutable artefacts built from a declarative specification, and
an explicit treatment of what cannot be made declarative. The concrete difference
is the treatment of `/etc` and `/var`. NixOS builds cross-cutting `/etc` files
purely and then "the activation script … copies these symlinks into `/etc`", but
draws a hard line at mutable state: "Some constitute mutable state that aren't
dealt with in the functional model at all, such as the system password file
`/etc/passwd` or the DNS configuration file `/etc/resolv.conf`, which must be
modified at runtime", and "NixOS does not have any mechanism to deal directly
with mutable state, such as the contents of `/var`." ModFS takes the opposite
decision for exactly those files: ARCHITECTURE §4 reconciles `/etc/passwd`,
`group`, `shadow`, `gshadow`, `subuid`, `subgid` by record union and merges
`/var/lib/dpkg/status`, `alternatives/*`, `diversions`, `/var/lib/apt/
extended_states` and the debconf `*.dat` databases, verifying the result with
V2/V3/V6/V8. This challenges nothing in NixOS but it does mean the class-5
reconciliation is a positive claim in territory a cited system explicitly
declines to enter, and should be argued as such. §6.2 also supports ModFS's
reproducibility position (see flag F7) and gives the same honest caveat ModFS
gives: "two builds of an identical derivation should produce the same result in
the Nix store. However, in contemporary operating systems, there is no way to
actually enforce that model." *Extraction quality: two-column PDF interleaved
line-by-line, as for `dolstra2004nix`; Figures 9 and 11 survive only as indented
path listings. Text itself is clean.*

## howard1988afs

John H. Howard, "An Overview of the Andrew File System", technical report
CMU-ITC-88-062, Carnegie Mellon University, Information Technology Center, 1988.

The author's claim is descriptive: AFS is a distributed file system intended to
scale "up to at least 7000 workstations" while giving users, programs and
administrators the amenities of a shared file system, organised around logical
volumes, whole-file caching and location transparency. The shared mechanism is
the read-only, cheaply-cloned release unit: "An important file system operation
from an operator's point of view is the creation of a read-only snapshot, or
'clone', of any logical volume. This is implemented in such a way that it is
quick and inexpensive to make clones … new software releases are typically made
by cloning the system binaries. Read-only clones can be replicated on multiple
[servers]." The concrete difference is granularity and composition: an AFS clone
is a snapshot of a whole named subtree that is *replicated*, not *composed* —
there is no union of two clones at one path, no precedence rule, no whiteout and
no merge of shared state, because each volume is attached at its own mount point
and cross-volume renames are illegal. ModFS's modules are deltas that are stacked
at the same paths and must therefore resolve collisions that AFS's design makes
impossible by construction. This contextualises ARCHITECTURE §1's problem
statement — per-use-case read-only release units with cheap snapshots are a 1988
idea — and it is the source for flag F10. It neither supports nor challenges any
class in the taxonomy, since no AFS mechanism merges two sources at one path.
*Extraction quality: good; occasional OCR damage to short words ("servcrs",
"u_rs"), no loss of structure.*

## howard1988scale

John H. Howard, Michael L. Kazar, Sherri G. Menees, David A. Nichols,
M. Satyanarayanan, Robert N. Sidebotham and Michael J. West, "Scale and
Performance in a Distributed File System", ACM Transactions on Computer Systems
6(1):51–81, February 1988.

The authors claim that a prototype AFS was re-engineered in four areas — cache
validation, server process structure, name translation and low-level storage
representation — and that the result "scales gracefully", demonstrated by
comparison against Sun NFS, with whole-file transfer and caching established as
the decisive design choice and volumes credited with improving operability. Two
mechanisms are shared with ModFS: the copy-on-write snapshot as the unit of
shipping, and incremental transfer of only what changed. §6.2: "The actual
movement is accomplished by creating a frozen copy-on-write snapshot of the
volume called a Clone, constructing a machine-independent representation of the
clone, shipping it to the new site … If the volume does change, the procedure is
repeated with an incremental clone by shipping only those files that have
changed." The concrete difference is that AFS's delta is computed *between two
points in time of one volume*, while ModFS's delta is captured *between a parent
rootfs and a child install* by the filesystem itself ("The filesystem captures
the diff; we never compute it", ARCHITECTURE §2.3), and AFS never composes two
deltas from different provenances. §6.4's read-only replication also states the
release/rollback property ModFS claims in §13, and states the same eventual-
consistency caveat: "there may be some period of time during which certain
replication sites have an old copy of the volume while others have the new copy"
— which is the same class of hazard as ModFS's ARCHITECTURE §13/H2 note that
atomic publication "remains H2, not a claimed feature". This is a supporting and
contextualising reference for the update-strategy and storage-saving claims, not
for any conflict class. *Extraction quality: good for prose; tables survive with
column alignment but some digits and check marks are unreliable; recurrent OCR
substitution of "tile" for "file".*

## kazar1988synchronization

Michael Leon Kazar, "Synchronization and Caching Issues in the Andrew File
System", technical report CMU-ITC-88-063, Carnegie Mellon University,
Information Technology Center, 1988.

The author claims that distributed file systems need not choose between strict
single-machine consistency semantics at high cost and weak guarantees at low
cost, and that AFS achieves "a good compromise" — useful consistency guarantees
with good performance — chiefly through callbacks, where a server promises to
notify a client before another party modifies a cached file. On the extracted
text there is **no mechanism shared with ModFS**: the paper is about cache
coherence between a server and many concurrently reading/writing clients over
time, whereas ModFS composes immutable read-only artefacts once, server-side,
with no cache, no callback, no concurrent writer and no consistency window. The
paper does not discuss unioning, whiteouts, copy-up, layer precedence, package
metadata or build reproducibility. Consequently it does not support, contextualise
or challenge any specific ModFS claim, and no comparison can be drawn from its
text. (The bibliography entry already records that this report was downloaded
under the wrong title and notes "drop it if the chapter does not use it"; the
present reading gives no reason to keep it.) *Extraction quality: good; minor OCR
substitutions ("Ritkin" for "Rifkin", "tile" for "file").*

## kistler1992disconnected

James J. Kistler and M. Satyanarayanan, "Disconnected Operation in the Coda File
System", ACM Transactions on Computer Systems 10(1):3–25, 1992.

The authors claim that "caching of data, now widely used for performance, can
also be exploited to improve availability", and that disconnected operation —
hoarding, server emulation while disconnected, and reintegration on reconnection
— "is feasible, efficient and usable". The shared mechanism is the reintegration
of divergent copies of the same object with an explicit, typed decision about
what can be merged automatically. The concrete difference is where the type
information comes from and what happens when it is absent. Coda merges only
*directories*, because their semantics are known, and refuses to merge file
contents: during replay "In the case of a store of a file, the entire
reintegration is aborted. But for directories, a conflict is declared only if a
newly created name collides with an existing name, if an object updated at the
client or the server has been deleted by the other, or if directory attributes
have been modified at the server and the client." ModFS makes the same
type-driven split but draws the line differently: it supplies parsers so that
*specific named files* (dpkg `status`, alternatives, diversions,
`extended_states`, the six account databases, the debconf `*.dat` files) become
mergeable records, while all other regular files keep the unmergeable
top-layer-wins behaviour, and two files (`/etc/alternatives/*`, `/etc/ld.so.cache`)
are regenerated by their owning tool rather than merged at all. Coda's
name/name conflict — "new objects with identical names are created in partitioned
replicas of a directory" — is the closest analogue in this paper to ModFS class 4
and class 7, but it is a *detected and escalated* conflict, not a prevented one;
ModFS prevents class 7 by disjoint pre-install UID windows and rejects class 4 at
tier 1. This supports ARCHITECTURE §4's core class-5 position that mergeability
requires knowing the record structure ("only the last needs to understand what it
is merging"), and challenges nothing. *Extraction quality: readable but degraded
— inter-word spacing is expanded and broken ("inst ante" for "instance", "syst
em"), so quoting requires care; section structure and pseudocode survive.*

## L04_P9

**No BibTeX entry exists for this key in `refs.bib`.** The document's own title
page reads: Dave Eckhardt, "P9 / 9P", lecture slides for 15-412, 9 September 2011
(Carnegie Mellon University). It is a teaching deck, not a peer-reviewed paper,
and should either be given a `@misc` entry with those details or dropped.

The deck's content claim is pedagogical: Plan 9 aims to "Build a UNIX out of
little systems … not 'a system out of little Unixes'", keeping the tree-structured
file system and "everything is a file" and discarding ttys and signals, with
personal namespaces and the 9P protocol as the organising ideas. The mechanism it
shares with ModFS is namespace construction by per-process binding, but the deck
treats it at an introductory level and its outline explicitly skips detail
("Skipping the unimportant parts: VM, Scheduling, Name spaces"). It contains no
treatment of union-directory search order, no whiteouts, no copy-up and no
content merging, so it adds nothing to `pike1993namespaces` or `pike1995plan9`
and supports no specific ModFS claim beyond what those two already support. It
should not be used as a citation for any technical statement. *Extraction
quality: clean for slide text, but it is slides — bullet fragments without
connective prose, and speaker notes absent.*

## lamb2022reproducible

Chris Lamb and Stefano Zacchiroli, "Reproducible Builds: Increasing the Integrity
of Software Supply Chains", IEEE Software 39(2):62–70, 2022.

The authors claim that reproducible builds — "when every build generates
bit-for-bit identical results" — let users determine whether a distributed binary
corresponds to its claimed source, and that in Debian this is both achievable at
scale ("over 95% of the 30 000+ packages in Debian's development branch can now
be built reproducibly") and valuable for quality assurance independently of
security. The shared mechanism is the deliberate elimination of environment- and
order-dependence from build outputs, and the specific techniques ModFS uses come
from this programme: `SOURCE_DATE_EPOCH`, archive metadata normalisation, and
imposing deterministic ordering on directory iteration. The concrete difference
is the strength of the property claimed and the object it applies to. Lamb and
Zacchiroli's Definition 1 requires identity "no matter the environment in which
the build is performed", and Debian's CI tests it adversarially — a second build
with the clock set 18 months ahead and hostname, language and kernel varied,
"30+" variations — whereas ModFS's positive reproducibility evidence is
same-host repeat builds (ARCHITECTURE §7, three modules, 2026-08-22) and its one
cross-host attempt produced different bytes with identical package records
(§8). This **challenges** the strong form of any ModFS reproducibility claim and
supports the weaker one ModFS actually makes ("These measures remove specific
sources of variation; they do not make artefact bytes independent of the wall
clock or the host toolchain"). It also supplies the vocabulary for ModFS's
residual causes: the remote diff's changed password-change dates and Java
certificate timestamps are "uncontrolled build inputs", and the unsorted Info-index
input is their "non-deterministic filesystem ordering". One further parallel: the
`GBrowse` case, where a secret generated at build time was shipped identically to
all users and "the fix was to generate the secret at installation time", is the
same reasoning ARCHITECTURE §8 gives for emptying `/etc/machine-id`.
*Extraction quality: poor layout fidelity — the two IEEE columns are interleaved
line-by-line throughout, so most sentences are split across unrelated adjacent
lines; listings and Figure 2 are lost. Word-level OCR is accurate, so quotations
are reliable once reassembled.*

## mancinelli2006managing

Fabio Mancinelli, Jaap Boender, Roberto Di Cosmo, Jérôme Vouillon, Berke Durak,
Xavier Leroy and Ralf Treinen, "Managing the Complexity of Large Free and Open
Source Package-Based Software Distributions", 21st IEEE/ACM International
Conference on Automated Software Engineering (ASE'06), IEEE Computer Society,
pp. 199–208, 2006.

The authors claim that distribution *editors* — not users — lack tools, and
present a formal model of a package repository plus a toolchain (Ceve, EGraph,
edos-debcheck/rpmcheck, SAT and CP solvers) that automatically finds packages
that cannot be installed in any configuration, applied to Debian and Mandriva:
"for 123 packages there are no possible way to install them … 111 of them are not
installable because of a missing dependency … The other 12 … are not installable
because the specified dependency relationships induce an unavoidable conflict."
The shared mechanism is dependency-and-conflict metadata reasoning, and the model
is the one ModFS's tier 1 implements informally: a repository (P, D, C), an
installation as a subset of P, and healthiness as *abundance* plus *peace*. The
concrete difference is that Mancinelli et al. answer "is this package installable
in this repository at all", a per-package question over the whole archive, while
ModFS answers "can these already-built module artefacts be stacked", a
per-*pair*/per-*set* question over 38 pre-built deltas at a fixed archive pin —
and ModFS then has to check things the model excludes by construction. Two
specific points bear on the taxonomy: Definition 2's axiom "Two packages with the
same unit but different versions conflict" is class 2 as an axiom rather than a
discovered class (flag F3), and the paper explicitly notes the file-level case
without modelling it — "Also, packages that install different files in the same
location conflict with each other, but this is not explicitly declared; Ceve can
explicitly add these conflicts to the output" — which is class 4 acknowledged as
an *add-on to* the metadata model, matching ModFS's separation of tier-1 metadata
checks from the class-4 sidecar intersection. Note for the bibliography: the
`refs.bib` comment says "the NP-completeness argument currently has no citation";
the NP-completeness *statement* is **not** in this paper's extracted text — it is
Theorem 1 of `treinen2008solving`, which is the correct citation, although
Vouillon and Di Cosmo attribute the result to this paper.
*Extraction quality: two-column PDF interleaved line-by-line; formulae and
Figures 4–6 are unusable, but the definitions and experimental numbers are
legible. Quote with care across line boundaries.*

## pendry1995union

Jan-Simon Pendry and Marshall Kirk McKusick, "Union Mounts in 4.4BSD-Lite",
USENIX 1995 Technical Conference, USENIX, 1995. (Page range still missing from
`refs.bib`.)

The authors claim that a union mount, "unlike a traditional mount that hides the
contents of the directory on which it is placed … presents a view of a merger of
the two directories", and that although only the top of the union stack is
writable, "the union filesystem gives the appearance of allowing anything to be
deleted or modified" via whiteouts and automatic copy-up. This is the same
mechanism ModFS uses, one kernel generation earlier, and the paper is the origin
of both markers ModFS depends on. Precise semantics, as extracted: **whiteouts**
are directory entries of a new type `DT_WHT` with no inode allocated ("A whiteout
is created simply by adding a new directory entry with the required name, but
with `DT_WHT` as the type … whiteouts are assigned the file number `WINO`"), they
are created automatically on `unlink`, `rmdir` and `rename` but only when
something would otherwise show through ("no whiteout would be created if the file
'w' was removed since there is no visible object with the same name in any of the
lower layers"), they can be removed deliberately with `rm -W` to undelete, and
they are suppressed from `readdir` in userspace by `opendir(3)`/`__opendir2`
rather than in the kernel. **Copy-up** happens on any content or attribute change
("Whenever file contents or attributes are changed the target file is copied to
the upper layer and changes are made there"), and the copy is owned by the
*mounter*, not the writer, with the mounter's umask; it is explicitly per-name and
link-unaware: "Copyup operates on only one name at a time. Other links to the same
file are not copied and so the link count in the upper layer will be incorrect."
**Opaque**: yes, there is a direct equivalent, set automatically and only when a
whiteout is replaced by a directory (quoted in full under flag F1). **A file
present in several layers**: "A name lookup will locate the logically topmost
object with that name", duplicates suppressed in `opendir`; there is no merging
of contents and no concept that two layers' copies of one file might both be
wanted. **Shared mutable state files**: not discussed at all — the applications
section covers patchable CD-ROMs, private source trees and architecture-specific
build trees, none of which involve a file that several layers each rewrite
wholesale. The concrete differences from ModFS's use are therefore: BSD sets
opaque only where a real deletion occurred, ModFS measured 869 markers where none
had (ARCHITECTURE §3, revised 2026-09-16); BSD's stack is built by the
administrator at mount time and expected to be stable, ModFS's lower layers are
chosen per composition from artefacts built against a different stack; and BSD
copy-up ownership semantics are irrelevant to ModFS because its lowers are
squashed read-only and the upper is a computed reconciliation layer. This paper
supports ARCHITECTURE §3's assumption B (the markers are real, documented
mechanisms with defined semantics), and it partially pre-empts class 9 (flag F1).
*Extraction quality: two-column USENIX proceedings, interleaved line-by-line, and
figures are reduced to scattered fragments ("root union vnode", "nil vnode").
Prose and the footnote defining the opaque attribute survive intact; section 5's
two columns must be read separately.*

## pike1993namespaces

Rob Pike, Dave Presotto, Ken Thompson, Howard Trickey and Phil Winterbottom,
"The Use of Name Spaces in Plan 9", ACM SIGOPS Operating Systems Review
27(2):72–76, 1993.

The authors claim that a per-process, locally constructed name space over
file-like services is a sufficient and general structuring principle: resources
are files, access is uniform via 9P whether local or remote, and "although there
is no global name space, for a process to function sensibly the local name spaces
must adhere to global conventions." The shared mechanism is union directories:
`mount` and `bind` take flags specifying "how the tree is to be attached to old:
replacing the current contents or appearing before or after the current contents
of the directory. A directory with several services mounted is called a union
directory and is searched in the specified order." The concrete differences are
substantial and all in ModFS's direction of more machinery: Plan 9 has no
whiteout, no copy-up, and (per the feature comparison in `wright2006namespace`)
unions only the top level rather than recursively, so it never has to answer what
happens when two layers hold the same path deeper in the tree. Its `REPLACE`
flag — "causes the directory of include files to be overlaid with its contents
from the dump on March first" — is the coarsest possible analogue of an opaque
marker: it applies to the whole bind point, is stated explicitly by the caller,
and is not persisted in any filesystem. The example use, unioning `/$cputype/bin`
with a private bin directory to replace `$PATH`, is the same use case
`wright2006namespace` lists first and the same one ModFS generalises. This
contextualises ModFS's composition model (stacking with leftmost-highest
precedence is a long-standing idea) and, by absence, supports the claim that
whiteout and opaque semantics are what make OverlayFS composition hazardous in a
way Plan 9's is not. *Extraction quality: **poor**. Heavy OCR damage throughout —
inter-character spacing inserted into most words, and systematic letter
substitutions (`/proo` for `/proc`, `bAnd` for `bind`, `heXix` for `helix`, `fde`
for `file`). Quotations must be reconstructed and should be verified against the
PDF or the canonical text at 9p.io before being used in the thesis.*

## pike1995plan9

Rob Pike, Dave Presotto, Sean Dorward, Bob Flandrena, Ken Thompson, Howard
Trickey and Phil Winterbottom, "Plan 9 from Bell Labs", Computing Systems
8(3):221–254, 1995.

The authors claim Plan 9 is "an attempt to have it both ways" — the central
administration and resource amortisation of timesharing with the economics of
cheap personal machines — realised by separating terminals, CPU servers and file
servers and binding them together with per-process name spaces and one protocol.
The shared mechanism is again the union directory, described here in more
implementation detail than in `pike1993namespaces`: "this is a union directory
and behaves like the concatenation of the constituent directories. A flag
argument to bind and mount specifies the position of a new directory in the
union, permitting new elements to be added either at the front or rear of the
union or to replace it entirely … each component of the union is searched in turn
and the first match taken; likewise, when a union directory is read, the contents
of each of the component directories is read in turn." The concrete difference,
beyond the absence of whiteouts and copy-up, is the *creation* rule, which is the
one place Plan 9 confronts a question ModFS also has to answer — which layer
receives a new object: "By default, directories in unions do not accept new files
… When a directory is added to the union, a flag to bind or mount enables create
permission … When a file is being created with a new name in a union, it is
created in the first directory of the union with create permission; if that
creation fails, the entire create fails." ModFS answers the same question by
construction rather than by policy: all lowers are read-only SquashFS and every
write lands in the single computed upper. Note also that Plan 9's union *reads*
concatenate without duplicate elimination (confirmed by `wright2006namespace`
feature 2), which is the opposite of OverlayFS and of ModFS's V7 expectation that
each path appears once in the merged view. This contextualises the composition
design; it does not bear on any conflict class, because Plan 9 unions namespaces,
never file contents or package state. *Extraction quality: good — single-column
reflowed text with hyphenation artefacts (`direc­tories`) from soft hyphens;
code blocks and `ls` output survive.*

## satyanarayanan1990coda

Mahadev Satyanarayanan, James J. Kistler, Puneet Kumar, Maria E. Okasaki,
Ellen H. Siegel and David C. Steere, "Coda: A Highly Available File System for a
Distributed Workstation Environment", IEEE Transactions on Computers
39(4):447–459, 1990.

The authors claim that Coda, a descendant of AFS, provides "resiliency to server
and network failures through the use of two distinct but complementary
mechanisms", server replication and disconnected operation, and that it does so
under an *optimistic* replication strategy that "allows writes everywhere and
resolves conflicting updates after they occur", with version vectors used "to
detect write-write conflicts on individual files". The shared mechanism is
conflict detection and automated resolution over divergent copies of the same
object, with a typed distinction governing what can be merged. Section V is the
part that maps onto ModFS class 5: "Since Unix files are untyped byte streams
there is, in general, no information to automate their resolution. Directories, on
the other hand, are objects whose semantics are completely known. Consequently,
their resolution can sometimes be automated. If automated resolution is not
possible, Coda marks all accessible replicas of the object inconsistent." The
concrete difference is that Coda's typing is built into the filesystem (directory
versus byte stream) and its unresolvable cases are escalated to a human repair
tool, whereas ModFS adds *application-level* typing for a fixed, enumerated list
of eight registry kinds and treats an unresolvable case as a build-time REJECT
rather than a runtime inconsistency — there is no repair tool and no human in the
compose loop. Coda's three unresolvable directory classes (update/update,
remove/update, name/name) are also a useful comparison for ModFS's own residual
cases: class 7 numeric identity collision is exactly a name/name conflict where
the colliding name is a number, and ARCHITECTURE §4 reaches the same verdict Coda
does — "This is **not repairable by a record union**: the numbers themselves
disagree". This supports ARCHITECTURE §4's structure (merge what you can parse,
reject what you cannot) and contextualises it as an instance of optimistic
replication practice rather than a novel principle. *Extraction quality: moderate
— two-column IEEE layout interleaved, plus OCR noise in formulae and citations
("Abstmct" for "Abstract", "[lo]" for "[10]", "AFS-l" for "AFS-1"). Section V's
prose is legible; the formal currency-guarantee equations are not reliable.*

## treinen2008solving

Ralf Treinen and Stefano Zacchiroli, "Solving Package Dependencies: From EDOS to
Mancoosi", arXiv:0811.3620, 2008.

The authors present results of the EDOS project — a formal model of inter-package
relations, its complexity, and the tools and distribution-wide quality-assurance
applications built on it — and set out the successor Mancoosi project's focus on
the "upgrade problem" faced by system administrators, decomposed into dependency
resolution and upgrade deployment. Three mechanisms are shared with ModFS.
First, the dependency/conflict model that tier 1 implements, including the
axiom "Two packages with the same name but different versions conflict" and the
virtual-package expansion rule quoted under flag F3. Second, the complexity
result ModFS's "intractable file-level problem reduced to a small declarative
package-level one" framing needs a citation for — Theorem 1: "The problem whether
a given package is installable in a repository is NP-complete", with the
practical qualification the thesis should quote alongside it: "In practice it
means as little as that it is a challenging problem since in practice one does not
encounter randomly chosen repositories." Third, and most directly, the class-4
detection pipeline of §2.2.5 (flag F2). The concrete differences: Treinen's file
check runs over a whole distribution's `Contents` index and over *package* pairs,
ModFS's over 38 module sidecars and *module* pairs; Treinen resolves diversions by
empirically installing each surviving pair in a chroot because maintainer scripts
are undecidable, whereas ModFS's tier 1 is static and its empirical equivalent is
tier 2/3; and Treinen's model deliberately excludes `Replaces` and `Breaks`
whereas ModFS's classes 3 and 4 use both. The paper also names two ModFS
limitations in advance: `Breaks` being outside the meta-installer model, and the
Mancoosi rollback goal's remark that "we are looking for solutions beyond mere
file system snapshots", which is a direct contrast with ModFS's §13 rollback by
redeploying a retained flattened image. *Extraction quality: good for prose,
definitions and the file-conflict statistics; the sideways-rotated Figures 3 and 4
(per-architecture uninstallability tables) are garbled and should not be cited
for numbers.*

## uta2020reproducible

Alexandru Uta, Alexandru Custura, Dmitry Duplyakin, Ivo Jimenez, Jan Rellermeyer,
Carlos Maltzahn, Robert Ricci and Alexandru Iosup, "Is Big Data Performance
Reproducible in Modern Cloud Networks?", 17th USENIX Symposium on Networked
Systems Design and Implementation (NSDI '20), USENIX, pp. 513–527, 2020.

The authors claim that cloud network performance is highly variable even where
providers enforce quality of service, that "the systems community centered around
cloud computing and big data disregards performance variability when performing
empirical evaluations in the cloud" — over 60% of surveyed articles under-specify
repetitions or statistics, and 76% of properly specified studies use no more than
15 repetitions — and that this invalidates conclusions, for which they give
experiment-design protocols. Note that "reproducible" here means *performance*
reproducibility, a different property from the build reproducibility of
`lamb2022reproducible` and ARCHITECTURE §8; the two must not be conflated in the
thesis. The shared concern is experimental method for the timing claims in
ARCHITECTURE §6/§7: the tier-1 and tier-2 cost figures (89 ms at N=2 → 398 ms at
N=36; 148 + 27.2 ms × N, R² = 0.970) and the build wall times in §13. The concrete
difference is the environment: ModFS measures a single fixed host with no
multi-tenancy, so the particular cause Uta et al. characterise — provider QoS,
token buckets, co-tenant contention — does not apply, and their strongest finding
("Network performance on clouds is largely a function of provider implementation
and policies, which can change at any time") is out of scope. What does transfer
is their methodological guidance, which ModFS's own §13 already partially
acknowledges ("These runs shared the host with verification, so they are measured
build costs rather than an isolated benchmark"): report repetition counts, report
variability not just medians, "'rest' the infrastructure and randomize experiment
order", and establish baselines before comparing across time. This **challenges**
the presentation of ModFS's single-run timings if they are reported without
repetition counts or dispersion, and supports the existing caveat where they are.
It bears on no conflict class and no filesystem mechanism. *Extraction quality:
moderate — two-column USENIX layout interleaved line-by-line; figures and their
captions are separated from the text that discusses them, and the survey
percentages appear in running prose rather than in the figure they annotate.*

## vouillon2013coinstallability

Jérôme Vouillon and Roberto Di Cosmo, "On Software Component Co-Installability",
ACM Transactions on Software Engineering and Methodology 22(4), Article 34, 2013.

The authors claim a novel theoretical framework of "formally certified semantic
preserving graph-theoretic transformations" that maps any concrete component
repository to a much smaller *strongly flat* repository with equivalent
co-installability properties, machine-checked in Coq, enabling both a compact
visualisation of all metadata-derived incompatibilities and efficient computation
of strong conflicts. The shared mechanism is co-installability itself: "A set of
packages Π are co-installable in a repository if they are all included in some
healthy installation I of the repository", healthiness being *abundance* plus
*peace* — which is the property ModFS tier 1 decides for each candidate module
set. The decisive concrete difference is the level of the model: theirs is
metadata-only. Versions and virtual packages are eliminated before the analysis
begins ("Extra properties like provides …, or versioned constraints … can be
easily preprocessed out [Mancinelli et al. 2006], so that one can focus on a core
dependency system that contains a binary symmetric conflict relation, and a
dependency function"), and the paper's own positioning is that this research area
assumes "only … that each component carries with itself a small amount of metadata
describing what the component provides and what it requires to be deployed and
run". Files, paths and file ownership are absent from the model; so are
maintainer scripts, UIDs, and any notion of shared state. Against the three
classes asked about: **class 2 and class 3 are formalised** by this line of work,
though in this paper they are inherited from the cited encoding rather than
restated (see `mancinelli2006managing` Definition 2 and `treinen2008solving` §2.1
for the explicit statements — flag F3); **class 4 is out of the model entirely**
(flag F4). This therefore supports ModFS's central claim in ARCHITECTURE §2 in one
direction — the package-level problem genuinely is declarative and tractable in
practice, and there is a published apparatus for it — while its own scope
boundary is the strongest available external support for ModFS's position that
the file-level checks (class 4, class 9, V7) are additional and necessary rather
than redundant. It challenges nothing in the taxonomy, but it does challenge any
implicit claim that the metadata-level classes were discovered here. *Extraction
quality: good — single-column-equivalent flow, definitions and proofs legible;
some set-theoretic symbols and subscripts are dropped or mangled in displayed
formulae, and Figures 16–18 (the Ubuntu 10.10 conflict graphs) are absent, so the
Ubuntu findings can be cited only from the prose of §13.*

## wright2006namespace

Charles P. Wright, Jay Dave, Puja Gupta, Harikesavan Krishnan, David P. Quigley,
Erez Zadok and Mohammad Nayyer Zubair, "Versatility and Unix Semantics in
Namespace Unification", ACM Transactions on Storage 2(1):74–105, 2006.

The authors claim that previous unification systems "compromised on the set of
features provided or Unix compatibility", and that Unionfs is the first n-way
stackable fan-out unification file system that is simultaneously versatile and
Unix-semantics-preserving: dynamic insertion and removal of any branch at any
precedence, mixed read-only and read-write branches, in-kernel duplicate
elimination, NFS interoperability, unique and persistent inode numbers, and
atomic multi-branch operations. This is the paper that catalogues the semantic
problems of namespace unification, and the catalogue is its §2 list of "four key
problems": duplicate names with possibly differing data, permissions and owners,
resolved by branch precedence; deletion that must not re-expose lower instances,
resolved by whiteouts; mixing read-only and read-write branches, resolved by
copyup, with the observation that "Over time, the highest-priority directory
becomes a de facto merged copy of the remaining directories' contents, defeating
the physical separation goal"; and name-cache coherency under dynamic branch
changes. Against the two classes asked about: **class 5's mechanism is in the
catalogue, its handling is not** (flag F5) — the paper states that only the
leftmost regular file is used and that this is deliberate ("applications expect
only a single stream of data when accessing a file"), but it never contemplates
merging file contents, never mentions package databases, `/etc/passwd`,
alternatives, diversions or debconf, and offers no equivalent of ModFS's
enumeration of registries or of `reconcile.py`; **class 9 has no equivalent
marker** — the word "opaque" does not occur in the paper, and Unionfs meets the
same requirement by writing an enumerated set of whiteouts into a newly created
directory for every entry to its right (flag F6), which is stack-dependent in the
same way but is visible as ordinary whiteout entries rather than as a single
directory-level flag. Two further concrete differences matter for the thesis.
First, Unionfs supports "dynamic insertion and removal of a branch anywhere in
the union" and handles it with generation numbers and revalidation (§3.7) — it
treats stack change as a *cache-coherence* problem, never as a problem of markers
authored against a previous stack, which is precisely ModFS's class 9. Second,
its Table I feature comparison is the authoritative cross-system summary of which
predecessors have whiteouts and copy-up ("Plan 9 does not support whiteouts …
BSD union mounts, TFS, and Unionfs create whiteouts transparently"; "Plan 9 union
directories do not support copyup"), and is the right citation for positioning
OverlayFS's ancestry. This paper supports ARCHITECTURE §3's account of overlay
semantics and constrains the novelty claims for classes 5 and 9 as described in
flags F5 and F6. *Extraction quality: good for prose. **One important defect:** in
Table I (Feature Comparison) the check marks are lost, so the table's cells are
blank in the extraction; the per-feature support claims above are taken from the
numbered prose items (1)–(18) of §5, which restate the table in words. Verify any
table-derived statement against the PDF.*
