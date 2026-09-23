# 3 Related work

ModFS draws on research in namespace composition, package co-installability, functional deployment, reproducible builds, and distributed storage. These comparisons answer different questions. Some supply mechanisms used directly by ModFS; others establish properties that it does not implement. The chapter therefore compares the unit of composition, the consistency rule, and the point at which a conflict is detected. It makes no cross-system performance ranking: the evaluation contains no common benchmark against these systems.

## 3.1 Union mounts and namespace composition

### 3.1.1 Priority, whiteouts, and opaque directories

Pendry and McKusick's 4.4BSD union mounts combine directory trees while giving one layer precedence over another [@pendry1995union]. Their treatment includes copy-on-write behavior, whiteouts for deletion, and opaque directories. An opaque directory is necessary when deleting and recreating a directory should not make its old lower contents reappear. The paper also explains that changing layer order changes the effect of stored deletion markers. Neither the marker nor the general hazard of interpreting it under a different stack originates with ModFS.

The ModFS-specific failure is the separation between the build stack and the composition stack. A package installation creates its upperdir against the base alone. At composition time the same layer is placed over independent siblings that were absent during that installation. A directory marker can then hide another sibling's files without a conventional file-ownership collision. Class 9 applies established union semantics to this mismatch and gives it an explicit build policy; it should be presented as a discovered failure of this construction, not a new filesystem primitive.

Wright and colleagues' Unionfs provides a broader treatment of namespace unification and Unix semantics [@wright2006namespace]. It includes branch priority, copy-up, duplicate-name handling, and dynamic branch management. The paper explicitly distinguishes a merged directory namespace from the single data stream, permissions, and owner that an application sees at a regular-file path. Selecting one visible `/etc/passwd` is therefore normal union behavior. ModFS's additional task is to identify that file as structured system state and compute a record-level result before it is used.

### 3.1.2 Per-process namespaces and image layers

Plan 9 lets processes construct namespaces from services using binding and mounting operations; its union directories make several sources accessible through a chosen naming environment [@pike1993namespaces; @pike1995plan9]. This offers useful conceptual separation between where a resource resides and how a program names it. ModFS also assembles separately maintained content into one namespace, but targets a conventional Ubuntu root with shared package and account databases. It does not provide Plan 9's per-process service namespace or replace Linux interfaces with its file protocol.

OCI image layers serialize filesystem changes as ordered changesets, including additions, modifications, and whiteout-encoded removals [@oci-image-spec]. This is relevant prior art for distributing layered filesystem content. OCI's changeset semantics describe how a layer is applied to its predecessors; the format does not establish that independently installed dpkg registries can be combined by arbitrary layer selection. ModFS adds sibling-generation constraints, admission, and reconciliation for that use case. Conversely, ModFS's use of SquashFS does not implement OCI image interoperability or establish an advantage over its distribution tools.

The common lesson is that namespace composition answers which object is visible. Whether that object truthfully describes the selected installed system requires application-specific semantics. ModFS keeps union lookup as the underlying mechanism and adds policies around its inputs and outputs.

## 3.2 Package co-installability and physical installation

### 3.2.1 What the formal models establish

Mancinelli and colleagues model package repositories through packages, dependencies, and conflicts and show how satisfiability methods support distribution-wide analysis [@mancinelli2006managing]. Treinen and Zacchiroli describe the progression from EDOS to Mancoosi, including installability checking and the broader upgrade problem [@treinen2008solving]. Vouillon and Di Cosmo develop transformations that preserve co-installability while reducing the repository to a simpler representation; the paper's proofs are machine checked [@vouillon2013coinstallability]. These works provide the appropriate foundation for declared dependency and conflict reasoning.

General installability asks whether a repository contains a suitable installation satisfying a request. ModFS's admission task is narrower: selected modules already contain installed package sets, so the checker evaluates that proposed union and its module requirements. Pinning reduces version variation but does not prove that every combination is valid or turn general package solving into a trivial problem. Likewise, an empirical approximately linear physical-composition fit says nothing about the worst-case complexity of repository solving.

A further distinction concerns adding modules to a selected set. A pair may fail because it lacks a required provider; a third module can supply it. A genuine incompatibility between two packages already present is different. The admitted triples containing rejected pairs in Chapter 6 illustrate this distinction (`thesis/evidence/tier1.md`, T1.4). A sampler cannot turn every pair rejection into an unconditional exclusion edge. Nor does checking all pairs and triples constitute a general completeness proof for larger sets.

### 3.2.2 File-conflict analysis is also prior art

It would be incorrect to describe earlier package research as uniformly blind to physical files. Treinen and Zacchiroli's §2.2.5 constructs candidate file conflicts from Debian's path-ownership index, filters them using co-installability, and discusses `Replaces` and diversions. Because diversion behavior depends on executed maintainer scripts, the remaining pairs are actually installed in a chroot and their logs inspected [@treinen2008solving, §2.2.5]. The combination of a metadata filter and a physical experiment thus has a direct predecessor.

ModFS applies that pattern to prebuilt module artefacts rather than fresh package-pair installations. It uses extracted file sidecars, constrained replacement/diversion policy, and a reconciled tree assembled from independent installation results. In particular, its registry problem arises because several successful installations each wrote their own complete view of shared state. Co-installability remains necessary for its package policy, but cannot prove that the composed status database contains the expected records or that numeric file ownership agrees with the merged account database.

The contribution is therefore not ownership intersection, version-conflict detection, or tiering alone. It is their integration with a sibling-delta construction and explicit registry, identity, marker, and runtime boundaries. The cited formal proofs concern their stated repository models; they cannot be inherited as a correctness proof for ModFS's additional parsers or verifiers.

## 3.3 Functional deployment and reproducibility

### 3.3.1 Nix and NixOS

Nix uses hashes of build inputs to give component instances distinct store paths and records dependency relationships so that multiple variants can coexist [@dolstra2004nix]. These input-derived names should not be described as simply hashes of the resulting file bytes. The deployment model supports retaining earlier components and assembling environments without overwriting one global package location.

NixOS extends this approach to the static parts of system configuration, constructing packages, configuration files, and startup information from a functional specification [@dolstra2008nixos]. Its activation process and running services still manage mutable state. It would overstate the comparison to say that NixOS makes every system file immutable or eliminates the need to handle account and application state.

ModFS makes a different compatibility choice: it executes ordinary Ubuntu package installations at their conventional paths, captures their effects, and reconciles selected global registries. A digest identifies the resulting artefact, while a generation binds it to an exact parent. This does not provide Nix's model of explicitly identified build inputs, dependency closures, or system generations. ModFS's missing transactional publisher and deployment client are substantive lifecycle gaps, not features supplied automatically by immutable SquashFS storage.

The NixOS paper also reports independent builds with residual differences caused largely by timestamps and other impurities [@dolstra2008nixos, §6.2]. This anticipates the shape of ModFS's negative byte-reproducibility result. Describing a build functionally or selecting the same package versions is a design intention that must still be tested against the actual build environment.

### 3.3.2 Reproducible builds and measurement reproducibility

Lamb and Zacchiroli distinguish source review from confidence in the executable artefact and explain the role of independently obtaining identical build outputs [@lamb2022reproducible]. Timestamp normalization, stable ordering, and controlled build inputs are established techniques in this work. `SOURCE_DATE_EPOCH` supplies a standard timestamp interface to cooperating tools; setting it does not force arbitrary maintainer scripts or database initialization to become deterministic [@source-date-epoch].

ModFS's pin fixes an APT archive view, while its hashes verify existing outputs. The rebuild observations in Chapter 7 show why neither property entails byte identity across machines. A digest also cannot by itself authenticate the party that supplied it. The thesis consequently separates package resolution, archive identity, and independent reproduction rather than using “deterministic” for all three.

Performance reproducibility is a further question. Uta and colleagues investigate variability in cloud networks and its effect on big-data experiments [@uta2020reproducible]. Their workload does not predict ModFS composition times. It does support the methodological need to report environment, repetitions, and variability rather than treating a fitted mean as a portable performance guarantee. Chapter 6's retained timing summary lacks the controlled repetitions needed for that stronger claim.

### 3.3.3 Filesystem-tree deployment

OSTree versions filesystem trees in a content-addressed repository and supports deployment of coherent operating-system snapshots [@ostree]. It is therefore relevant to the lifecycle surrounding ModFS, not only to storage format. ModFS's specific experiment concerns constructing a root from selected independent APT-installation deltas. Transactional deployment and retaining older trees address what happens after such a root has been constructed. A comparison would need to account for both stages; the current thesis does not implement or measure an OSTree-backed ModFS deployment.

## 3.4 Distributed filesystems and release consistency

AFS uses client caching and server coordination to support shared files at scale [@howard1988afs; @howard1988scale]. Kazar's account explains the synchronization and caching issues, including callbacks used to maintain cache validity [@kazar1988synchronization]. The relevant property is the consistency of changing shared data across clients. ModFS's current node has no corresponding cache-coherence protocol: its selected immutable modules are assembled into an image before provisioning.

AFS also uses read-only volume clones for software releases and administrative operations [@howard1988afs]. Thus retaining a coherent release and returning to an older release are established deployment ideas. ModFS's use of compressed installation deltas changes the construction unit, but does not originate the general idea of snapshot-based release management. In the present implementation, retaining an older packed image permits redeployment; it does not supply an operational rollback service.

Coda extends the AFS lineage with optimistic replication and disconnected operation [@satyanarayanan1990coda]. Kistler and Satyanarayanan explain the transition between hoarding useful cached data, emulating service while disconnected, and reintegrating logged changes after reconnection [@kistler1992disconnected]. Conflicts arise from independently evolving mutable state. ModFS instead combines independent installation results before a node runs, under a common-parent restriction. Its reconciliation is not a replay protocol for edits made by provisioned machines.

These comparisons locate the consistency work. AFS and Coda coordinate or reconcile clients over time; ModFS moves package and filesystem checks into image construction, leaving runtime resources to boot observation. There is no measured common workload from which to claim lower latency, bandwidth, or operational complexity than either distributed filesystem.

## 3.5 Positioning the contribution

| Prior line of work | Established mechanism or question | ModFS's specific scope |
|---|---|---|
| Union mounts and namespace systems [@pendry1995union; @wright2006namespace; @pike1993namespaces] | Branch precedence, deletion semantics, and construction of a naming environment. | Independently built siblings and the system-state semantics of their merged root. |
| Package co-installability and conflict analysis [@mancinelli2006managing; @treinen2008solving; @vouillon2013coinstallability] | Declared relations, path-conflict filtering, and physical installation tests. | Admission of prebuilt modules plus reconciliation of their installed registries and identities. |
| Nix and NixOS [@dolstra2004nix; @dolstra2008nixos] | Isolated component instances and functional construction of static system configuration. | Preserving ordinary APT package layouts and handling their shared mutable installation state. |
| Reproducible builds [@lamb2022reproducible] | Independent reproduction of artefact bytes and control of impurity. | Separating pinned resolution, bound output identity, and unachieved byte reproducibility. |
| OCI and OSTree [@oci-image-spec; @ostree] | Ordered filesystem changesets and coherent tree deployment, respectively. | Selecting sibling installation deltas; publication and remote lifecycle remain incomplete. |
| AFS and Coda [@howard1988afs; @satyanarayanan1990coda] | Cached shared files, release snapshots, and disconnected reintegration. | Server-side image construction without a node cache or mutation-replay protocol. |

Table 3.1: Conceptual positioning. The rows compare mechanisms and scope, not measured rankings.

The supplied literature establishes much of the foundation and several directly related techniques. ModFS's contribution is the concrete combination of a pinned sibling construction, a conflict taxonomy, registry-specific reconciliation, and an empirical account of what its verification pipeline observes and misses. Absence of an identical implementation from this selected reading set is not evidence of exhaustive novelty. The thesis supports its contribution through the implemented policies and retained counterexamples rather than a claim that layering, package checking, or immutable release management began here.
