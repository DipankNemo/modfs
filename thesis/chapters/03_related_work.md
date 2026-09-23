# 3 Related work

## 3.1 Union mounts and namespace composition

The draft correctly places ModFS in a lineage of union and stackable filesystems. Pendry and McKusick's 4.4BSD union mounts describe a merged directory view with priority, whiteouts, and opaque directories [@pendry1995union]. Wright and colleagues examine namespace unification and its Unix-semantic and performance costs when multiple branches are presented as one [@wright2006namespace]. Plan 9 shows a different, per-process way to construct names from multiple services [@pike1993namespaces; @pike1995plan9]. These works explain how names are resolved. They do not, by namespace lookup alone, reconcile an APT installation database or service accounts that separate package installations have each rewritten.

ModFS uses OverlayFS as the capture and assembly mechanism rather than claiming to invent union lookup. Its contribution is the rule for *which* sibling deltas may be assembled and how the shared state of an installed Ubuntu system is made coherent before the root is flattened. The opaque-directory failure in Chapter 4 also cautions against equating a union filesystem's faithful interpretation of a marker with the intended semantics of independently built siblings. A marker generated against one lower tree can mean something else when the lower tree changes.

OCI images offer a familiar layer distribution model [@oci-image-spec]. Their layer ordering and whiteout semantics are useful points of comparison, but an OCI layer is not a proof that two independently installed dpkg states form one maintainable host root. ModFS's sibling constraint, package admission, and registry reconciliation answer that narrower system-image question. Conversely, OCI's distribution ecosystem addresses transport and publication functions ModFS has not implemented.

## 3.2 Package co-installability

Research on package-based distributions formalizes dependencies and conflicts over a repository and studies the difficulty of deciding installability at scale [@mancinelli2006managing; @treinen2008solving]. Vouillon and Di Cosmo investigate co-installability through a formal model and sound transformations that make repository analysis more efficient [@vouillon2013coinstallability]. These results are directly relevant to ModFS's metadata admission: one selected set must admit a consistent package universe, including virtual providers and disjunctive dependencies. A pair rejected for an unsatisfied module requirement can become acceptable when a third module supplies the provider, so admission cannot be reduced to an undirected graph of rejecting pairs (`thesis/evidence/tier1.md` T1.4).

The physical composition problem adds predicates beyond package relations. Two packages may be metadata-compatible while different package-owned paths collide; unowned registries can contain only the upper sibling's records; numerically owned files can refer to the wrong service account; and services can compete for a socket after boot. ModFS does not replace a package solver with a filesystem heuristic. It layers path and identity policy, semantic registry reconciliation, and boot observation on top of package metadata. It also does not claim a formal completeness proof for those extra predicates: the verifier review in Chapter 7 shows why that would overstate the current implementation.

## 3.3 Functional deployment and reproducible builds

Nix separates packages into store paths that encode dependencies and permit several variants to coexist; NixOS applies functional configuration ideas to a whole Linux system [@dolstra2004nix; @dolstra2008nixos]. This attacks hidden mutable global state by changing the deployment model. ModFS instead accepts mainstream Ubuntu packages and filesystem paths, then limits their independent builds to one pinned base generation and reconciles the global state their scripts produce. That compatibility choice also retains sources of impurity Nix tries to eliminate: maintainer scripts can consult time, host identity, filesystem traversal order, or outside repositories.

Reproducible-build research defines a stronger target than deterministic package selection: independently performing the same build should yield identical output bytes [@lamb2022reproducible]. `SOURCE_DATE_EPOCH` addresses one class of embedded timestamps but cannot, by itself, control every post-install action [@source-date-epoch]. The ModFS snapshot fixes the APT candidate universe. The independent rebuild described in Chapter 7 found byte differences despite that pin. The distinction matters for its hashes: a digest can identify and verify an existing `.sqsh`, but identical resolution and a valid digest do not imply that another machine will generate the same digest. The design's generation identifier specifies compatibility with an exact base; it is not a claim that rebuilding the base later is bit-for-bit reproducible.

OSTree is a closer image-management comparison because it versions filesystem trees and deploys them as coherent snapshots [@ostree]. ModFS's emphasis differs: it captures ordinary APT installations as sibling deltas and decides whether a selected set can be assembled into one root. OSTree's transactional deployment model points to a gap in ModFS's current lifecycle: generation publication and node rollback are specified, but a transactional publisher and remote update client are outside the implementation (`ARCHITECTURE.md` §13).

## 3.4 Distributed filesystems and the location of consistency work

The Andrew File System uses client caching and server coordination to make shared files usable at scale [@howard1988afs; @howard1988scale; @kazar1988synchronization]. Coda extends that line with disconnected operation and reintegration of client changes [@satyanarayanan1990coda; @kistler1992disconnected]. Their central consistency problem concerns changing files across clients over time. ModFS's measured task is different: immutable server-side module artefacts are selected, verified, reconciled, and flattened before a node boots. There is no ModFS client cache protocol or disconnected mutation replay to compare empirically with AFS or Coda.

These distributed-storage works remain useful in framing *where* consistency is enforced. They show that deferring conflicts until data is consumed or reintegrated has operational consequences. ModFS moves its package and filesystem checks before provisioning, while explicitly retaining runtime-only checks for services. This is a scope distinction, not a performance comparison; the thesis has no common workload with AFS or Coda.

## 3.5 Positioning

| Prior line of work | Property it primarily models | ModFS's additional question |
|---|---|---|
| Union and namespace filesystems [@pendry1995union; @wright2006namespace] | Which branch supplies a path? | Is the selected installed-system state coherent? |
| Package co-installability [@mancinelli2006managing; @vouillon2013coinstallability] | Can package relations be satisfied? | Do files, identities, and rewritten registries compose? |
| Functional deployment [@dolstra2004nix; @dolstra2008nixos] | How can deployment avoid mutable global state? | How far can ordinary APT packages be modularized while retaining their paths? |
| Reproducible builds [@lamb2022reproducible] | Can independent builds yield identical bytes? | Which package resolution and artefact properties are actually reproducible here? |
| AFS and Coda [@howard1988afs; @satyanarayanan1990coda] | How is mutable shared data kept available across clients? | Which checks can run on the server before a root is flashed? |

Table 3.1 positions research questions, not measured speed or storage rankings. ModFS draws on existing layering, package, and deployment techniques. Its specific contribution is the taxonomy and reconciliation policy for *independent, pinned sibling installs*, together with a tiered verification experiment that exposes the limits of its own assertions.
