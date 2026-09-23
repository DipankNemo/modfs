# 1 Introduction

## 1.1 Motivation

Bare Metal as a Service provisions physical machines from prepared operating-system images [@baas; @ironic; @maas]. A repository with several workload variants may store a full root for each variant even when they share the same Ubuntu base. A whole-image update also gives the operator a coarse unit of change. ModFS asks whether independent package installations can be kept as compressed sibling deltas and assembled into a conventional image only when a particular machine is provisioned. This is a server-side image-construction question: the deployed machine receives a flattened root, not a live stack of ModFS modules.

Reusing bytes alone is insufficient. APT and dpkg packages install files and run scripts that change global operating-system state. If two installations are performed separately against one base, their compressed upperdirs can both contain `/var/lib/dpkg/status`, `/etc/passwd`, or an alternatives registry. OverlayFS exposes one whole file at each path; it does not combine package stanzas, user records, or alternative candidates. The two deltas may also have different package versions, claim the same path, allocate the same numeric UID to different accounts, or carry a directory marker that hides a sibling's files. Even a coherent merged root may start services that compete for the same port. These mechanisms motivate an explicit conflict taxonomy instead of a blanket assertion that layers compose.

## 1.2 Approach and claim

ModFS builds an Ubuntu base from a fixed archive snapshot and fully upgrades it against that archive view. Each module is installed independently over the read-only base using OverlayFS; only its writable upperdir is compressed with SquashFS. Modules name the exact base generation to which they belong. Before assembly, static admission checks package and module relations, file ownership, and identities. During assembly, a reconciliation layer combines unowned system registries and regenerates derived caches. Structural verification inspects the actual merged tree. A separate QEMU/UEFI boot tier observes service behavior (`ARCHITECTURE.md` §§2–6; `docs/RUNBOOK.md`).

The draft's proposed central claim was that snapshot pinning reduces the conflict problem to a small declarative package problem. The completed work supports a more precise claim: pinning **constrains package resolution and defines compatible sibling generations**, but package metadata alone cannot establish physical or runtime composability. The research contribution is the classification of those remaining conflicts, the targeted reconciliation policy, and a verification pipeline whose review exposed its own blind spots. The system retains ordinary Ubuntu package paths and produces a normal bootable image, while its evidence is limited to the artefacts and generations actually tested.

## 1.3 Research questions

The thesis keeps the draft's three research questions, with “effective” interpreted against explicit measurements and limitations:

1. **RQ1 — Conflict handling.** How can state conflicts among independently built filesystem deltas be classified, prevented, rejected, or reconciled?
2. **RQ2 — Storage.** What server-side repository storage reduction does one shared base plus deltas provide relative to monolithic equivalents, and how does the result depend on the workload cohort?
3. **RQ3 — Verification.** Which properties do static admission, physical structural verification, and boot tests actually establish, and which failures remain outside each tier's observation?

The current evidence covers an adversarial catalogue of 40 modules, with exhaustive pair and triple admission and a current storage inventory (`thesis/evidence/tier1.md`; `storage.md`; `catalogue.md`). The present tier-2 sweep predates rebuilt artefacts and most boot bundles are superseded (`tier2.md`; `tier3.md`; `provenance.md`). Those limitations are part of the answer to RQ3, rather than inconvenient exceptions to be dropped from the result.

## 1.4 Scope and contributions

The primary measured generation uses Ubuntu 22.04 on x86-64 with APT/dpkg, OverlayFS, and SquashFS (`ARCHITECTURE.md`, scope; `thesis/evidence/catalogue.md`). Ubuntu 24.04 work probes portability of the build and boot procedure, but it does not supply the current 40-module evaluation figures. Modules are direct siblings of a single exact base. A snapshot move creates a new generation and requires rebuilding the base and siblings. The current implementation assembles and verifies images on the server; it has no transactional remote publisher, node-side module update mechanism, or demonstrated bare-metal rollback service (`ARCHITECTURE.md` §13).

The thesis makes three concrete contributions. First, a nine-class taxonomy separates harmless duplication, preventable build conflicts, metadata rejections, shared-state reconciliation, and runtime conflicts. Second, the implemented composer parses six registry groups and regenerates two derived groups, preserving ordinary dpkg, account, alternatives, debconf, and linker behavior in the merged view (`docs/REGISTRY_FORMATS.md`). Third, the evaluation traces each published number to retained artefacts, distinguishes current from superseded runs, and uses adversarial regression cases to show where a passing verifier failed to model the claimed property. The whole-catalogue storage ratio is 1.84× for the measured server repository; it is modest for the large cohort and uses a mostly modelled monolithic comparison (`thesis/evidence/storage.md` S1–S4).

## 1.5 Organization

Chapter 2 introduces package installation and the eight shared registry groups. Chapter 3 positions ModFS against union filesystems, package co-installability, functional deployment, reproducible builds, and distributed storage. Chapter 4 gives the design and conflict taxonomy; Chapter 5 explains the builder, data model, reconciliation, sampling, and boot implementation. Chapter 6 evaluates admission, composition evidence, storage, and boot with explicit generation labels. Chapter 7 discusses verifier findings, reproducibility, and validity limits. Chapter 8 states the bounded conclusions and the measurements still needed.
