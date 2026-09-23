# 1 Introduction

## 1.1 Context and motivation

Bare Metal as a Service automates the provisioning and management of physical machines. Platforms such as BAAS, Ironic, and MAAS provide the surrounding machinery for preparing and deploying operating systems [@baas; @ironic; @maas]. This thesis concerns one part of that workflow: constructing and retaining the operating-system roots needed by different workloads. A web server, a database node, and a development machine can share a base distribution while requiring different packages and configuration.

Storing a complete root for each workload repeats that common base. A module-oriented repository could retain the base once and store each workload's additions separately, constructing the selected root when provisioning requires it. The benefit depends on the workload: a small service may add little to its base, while a large toolchain or GPU runtime can dominate the image. The thesis therefore measures storage by cohort and distinguishes a repository with many variants from one deployed node.

ModFS explores this design using ordinary Ubuntu APT/dpkg packages, OverlayFS to capture installation changes, and SquashFS to store immutable deltas. Its deployed node receives a flattened bootable image. Modularity belongs to the server's construction and storage process; a separate node-side update protocol is not implemented. The title's “updatable” refers to rebuilding sibling modules within a compatible generation and constructing new complete images, subject to the lifecycle limits developed below.

## 1.2 Problem statement

Reusing filesystem content is insufficient to compose independently installed software. Package installation includes dependency resolution, file unpacking, and maintainer scripts that update global state. If two modules are installed independently against the same base, each can contain a different complete `/var/lib/dpkg/status`. OverlayFS exposes the highest layer's file; it does not union its package records with those below. Lower-layer executables can remain visible while dpkg no longer knows that their packages are installed.

The same problem affects account databases, alternatives, debconf, diversions, and APT installation marks. Numeric identities create another dependency: two independent scripts can assign the same available UID to different services, and later merging their names cannot repair ownership numbers already stored on disk. Filesystem markers also depend on context. An opaque directory created against the base can hide a sibling's files when reused in a composition containing layers absent from the original build.

Package relations capture only part of this state. A common archive pin reduces version drift, but incompatible requests, path ownership, and generated registries still need explicit rules. Finally, a structurally coherent root can contain services that compete for the same runtime resource. Nginx and Apache seeking the same listening port provide the project's concrete example. These mechanisms require a taxonomy that distinguishes what can be prevented, rejected, reconciled, and observed only during execution.

## 1.3 Approach and central claim

ModFS first builds and upgrades a common base against a fixed archive snapshot. Each module is installed independently over the exact read-only base using OverlayFS, and only its upperdir is compressed. Artefacts carry manifests and ownership sidecars, while generation identity binds compatible siblings to their snapshot, platform, and exact base. Static admission checks the selected package and module relations, path ownership, identities, and composability metadata (`ARCHITECTURE.md` §§2–5).

During physical assembly, a writable reconciliation layer combines the supported shared registries and native tools regenerate derived state. Structural assertions then inspect the composed tree. Packing adds the boot inputs and creates a conventional image; a QEMU/UEFI tier observes guest state, service failures, probes, and listeners (`docs/RUNBOOK.md`; `docs/SAMPLING_AND_BOOT.md`). These tiers deliberately test different properties.

The central claim is that a pinned common parent makes independent package installations a tractable engineering unit **when combined with explicit compatibility policies and semantic reconciliation**. Pinning constrains package resolution; it does not reduce all physical and runtime conflicts to package metadata. Nor does it ensure byte-reproducible builds. The thesis supports its claim by tracing the policies to specific failure mechanisms and by examining counterexamples to its own verification assertions.

## 1.4 Research questions and evidence

The investigation follows three research questions:

1. **RQ1 — Conflict handling.** How can state conflicts among independently built filesystem deltas be classified, prevented, rejected, or reconciled?
2. **RQ2 — Storage.** What server-side repository storage reduction does one shared base plus deltas provide relative to monolithic equivalents, and how does the result depend on the workload cohort?
3. **RQ3 — Verification and boot behavior.** How far do static admission and structural verification support expectations of a bootable, functioning system, and which failures remain outside their observation?

RQ1 is addressed through the taxonomy, implemented policies, and adversarial tests. RQ2 uses compressed artefact sizes and an explicit monolithic comparison model. RQ3 compares the predicates and outcomes of admission, physical composition, and selected boots. The evidence does not supply a calibrated probability that static acceptance predicts successful boot; answering RQ3 therefore includes explaining the limits of that prediction.

The retained evaluation snapshot covers an adversarial catalogue of 40 modules, with exhaustive pair and triple admission and a current storage inventory (`thesis/evidence/catalogue.md`; `tier1.md`; `storage.md`). The overall storage ratio is 1.84×, using modelled monolithic sizes calibrated against six actual whole-root builds (`storage.md`, S1–S2). The physical sweep predates rebuilt artefacts, and most boot bundles are superseded (`tier2.md`; `tier3.md`; `provenance.md`). The thesis reports those results as historical observations rather than silently extending them to the latest inputs.

The verification review is central to interpreting the results. Directed counterexamples exposed checks that passed while modelling too little, harnesses that distorted observations, and synthetic merger defects absent from the published catalogue outcomes. A clean sweep is therefore evidence for its stated predicates, not an unrestricted correctness guarantee. Chapter 7 develops this finding and the still-open equal-size file-substitution case.

## 1.5 Scope and contributions

The primary measured generation uses Ubuntu 22.04 on x86-64 with APT/dpkg. Separate Ubuntu 24.04 work investigates portability; it is not the source of the current Jammy evaluation totals. Modules are direct siblings of one exact base. Moving the archive pin requires a new base and siblings, and the design rejects incompatible generation mixing. The current implementation lacks a transactional remote publisher, a node-side module-update client, and a demonstrated bare-metal rollback service (`ARCHITECTURE.md` §13).

Within that scope, the thesis makes three contributions:

- **A conflict taxonomy tied to policy.** Nine classes distinguish benign duplication, package and path incompatibilities, rewritten shared state, identity allocation, opaque-directory effects, and runtime resources.
- **A concrete reconciliation mechanism.** Six registry groups are parsed and combined and two derived groups are regenerated, preserving the ordinary Ubuntu filesystem layout. The treatment states both implemented behavior and remaining gaps.
- **An evidence-bounded verification study.** Admission, sampled physical compositions, storage, and boot results retain their population and freshness labels. Adversarial regressions show where successful checks failed to establish the property claimed about them.

These contributions build on existing union filesystems, package analysis, and immutable deployment techniques. The storage result is cohort-dependent; userspace GPU execution is distinct from validating the packaged driver on hardware; and server repository savings are distinct from node-transfer performance. Those boundaries define the claim being evaluated.

## 1.6 Organization

Chapter 2 introduces package installation and the eight shared registry groups. Chapter 3 positions ModFS against union filesystems, package co-installability, functional deployment, reproducible builds, and distributed storage. Chapter 4 gives the design and conflict taxonomy. Chapter 5 explains the builder, bundle schema, reconciliation, sampling, and boot implementation. Chapter 6 evaluates admission, physical composition, storage, and boot with explicit evidence labels. Chapter 7 examines verifier findings, reproducibility, updates, base sizing, and validity limits. Chapter 8 answers the research questions and identifies the experiments needed to extend the result.
