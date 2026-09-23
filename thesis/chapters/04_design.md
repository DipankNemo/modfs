# 4 Design

## 4.1 Requirements and boundaries

Bare Metal as a Service image repositories commonly retain a separate whole-root image for each workload. When those images share an operating system, each image repeats the same base bytes. ModFS aims to retain one compressed base and separately updateable package deltas, while still producing a conventional bootable filesystem for each selected machine (`ARCHITECTURE.md` §§1–2). Composition occurs on the server; a provisioned node receives a flattened image. The design does not require OverlayFS support on the node and does not provide live module switching there.

The working system is built around Ubuntu 22.04, APT/dpkg, OverlayFS, and SquashFS (`ARCHITECTURE.md`, scope). Ubuntu 24.04 exercises portability of the build and boot procedure, but the current evidence catalogue and storage result are for the 22.04 generation (`thesis/evidence/catalogue.md`; `provenance.md`). This distinction prevents a portability experiment from being treated as another measured production catalogue. The other constraints are deliberate: every module is a *direct sibling* of one base, all siblings resolve packages against the same archive snapshot, and a pin change creates a new generation rather than allowing old and new siblings to mix (`ARCHITECTURE.md` §§2, 13).

This flat topology gives admission a tractable reference state. Every sibling was installed against the same parent, so a manifest can describe only the package and filesystem contribution relative to that parent. The exact base is part of a generation identifier derived from the archive snapshot, suite, architecture, and base artefact digest. Changing a module specification can keep that generation; changing the base bytes cannot (`docs/DATA_MODEL.md`, “The generation identifier”). A digest is an integrity check on origin and consistency, not a signature proving who produced a bundle.

## 4.2 Conflict taxonomy as design method

The draft's conflict taxonomy is the central design tool. It distinguishes cases that should be accepted, rejected, prevented before building, repaired during composition, and observed only at boot. Table 4.1 follows `ARCHITECTURE.md` §4; class numbers identify mechanisms rather than severity.

| Class | Failure mechanism | Design response |
|---|---|---|
| 1. Benign overlap | Siblings carry the same package version or harmless shared paths. | Accept and measure duplication. |
| 2. Version skew | Different versions, parents, snapshots, or generations describe one composed state. | Reject before mounting. |
| 3. Declared package conflict | Debian `Conflicts` or `Breaks`, including virtual names, excludes co-installation. | Reject through package-relation checking. |
| 4. File collision | Different packages claim one path without a valid replacement or diversion. | Intersect ownership sidecars and reject unsanctioned overlap. |
| 5. Shared-state divergence | Package scripts rewrite whole, unowned registries independently. | Parse and reconcile records, or regenerate derived state. |
| 6. Implicit base upgrade | A delta upgrades an inherited base package through dependency resolution. | Upgrade the base at the pin before sibling builds and detect recurrence. |
| 7. Numeric identity collision | Separate builds assign one UID or GID to different accounts. | Partition allocation windows before installation and check records and file owners. |
| 8. Runtime resource conflict | Independently valid services compete for a port or other resource. | Observe at boot; metadata and filesystem tiers cannot infer the startup race. |
| 9. Opaque directory erasure | A captured OverlayFS marker hides paths from a later sibling. | Remove the marker under checked build preconditions and verify path visibility. |

The distinction between classes 4 and 5 is decisive. `dpkg` can identify package-owned files, so intersecting their path maps makes class 4 visible without composition. Files such as `/var/lib/dpkg/status` are rewritten by package tools but owned by no individual package. Their absence from a package ownership collision report is expected, not evidence that the files safely compose. OverlayFS selects the highest layer's whole copy, discarding lower records. That is why class 5 has a record-level reconciler rather than a path-level exception (`docs/REGISTRY_FORMATS.md`, “Why these files are a class of their own”).

Classes 6 and 7 are best handled before the conflicting bytes exist. APT builds should see a base already upgraded against the pinned repository pockets; otherwise a module can carry a newer base library while another assumes the older one. For identities, Debian's default dynamic range can assign the same number independently in multiple build roots. Once files are stored with that numeric owner, a later text-file merge cannot repair ownership. Disjoint, permanent allocation windows make the collision structurally unavailable to normal builds; checks remain necessary for malformed or externally supplied artefacts (`ARCHITECTURE.md` §4).

Class 9 shows why the build context matters. `trusted.overlay.opaque` means “hide lower entries in this directory.” During a sibling build, the only lower tree is the base; at composition another sibling may occupy the same directory. Retaining the marker faithfully can then erase that sibling's unrelated files without a same-path collision. The builder removes these markers under its asserted preconditions, retains file whiteouts, and the physical tier checks visibility. This is a case in which correct preservation of a filesystem feature produced the wrong *composition* semantics (`ARCHITECTURE.md` §§3–4).

Class 8 sets a natural boundary. The `webserver` (nginx) and `apache` packages have compatible metadata and files, yet both services seek port 80. The winning daemon depends on startup order. Neither a package relation checker nor an offline filesystem assertion observes that race; boot execution can. A future port declaration policy could warn about known conflicts, but it would still need to model the resources actually used at runtime. Chapter 6 treats the retained boot runs with their artefact-generation limits.

## 4.3 Why verification is tiered

The design places inexpensive, complete metadata checks before expensive, sampled physical and boot checks. Tier 1 can enumerate every pair and triple in the current catalogue. Tier 2 pays for mounts and semantic reconciliation, so its higher-order sets are selected under constraints and then rechecked by Tier 1 (`docs/SAMPLING_AND_BOOT.md`, Part 1). Tier 3 pays for packing and starting a whole machine. Each tier observes a different failure domain; passing a higher tier for one set says more about that set, while an exhaustive lower-tier census says more about the set space. Neither substitutes for the other.

Verification is itself a design object. A check of package-name sets cannot establish version agreement; a check of path names and sizes cannot establish byte identity; a service probe returning success cannot establish that systemd has no failed units. The verifier therefore uses explicit predicates and preserves negative controls. The tests under `tests/` exercise cases where a check used to pass an unmodelled defect. This is why the thesis reports the scope of each assertion rather than describing the tiers as a general proof of correctness.

## 4.4 Updates and delivery

An intra-generation specification change rebuilds and republishes the affected module bundle, then repeats binding and admission checks against its unchanged siblings. A repository-snapshot move requires a new base and all siblings in an isolated generation; a mixture is invalid even if individual package names still match. Generation publication is an architectural requirement, while an atomic remote catalogue publisher and transfer client are not implemented (`ARCHITECTURE.md` §13). A reused byte-identical artefact could avoid a transfer, but a changed hash requires the entire new artefact in the current system; file-level incremental distribution is not part of the design.

At delivery, the selected layers are reconciled and flattened into an ordinary image. A server-side base-and-deltas saving therefore does not imply smaller bytes flashed to an individual node. Rollback is redeployment of a retained complete image, with its selected set and boot inputs, not a reversal of live on-node module changes. These boundaries also determine the evaluation denominator: repository storage can be compared with multiple monolithic roots, while node transfer and rollback require separate measurements (`ARCHITECTURE.md` §13).
