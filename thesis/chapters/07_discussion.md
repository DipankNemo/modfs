# 7 Discussion and limitations

## 7.1 Verification as an experimental finding

The strongest finding concerns the distance between a successful check and the property it is supposed to establish. The retained physical sweep is clean under its recorded predicates, yet subsequent review repeatedly found ways to violate a claimed invariant without changing that verdict. This is evidence about the verification instrument as well as the system. A catalogue can exercise many package combinations while never exercising an omitted condition in a checker.

The review history needs a precise reading. The September 21 review reports defects in checks, sampling, and evidence handling without a newly observed composition failure. The later September 22 registry review also demonstrates defects in the merger itself: accepting a repeated account with a different primary GID, retaining duplicate group members, and silently discarding an incomplete diversion record. These synthetic inputs are not demonstrated failures of the published catalogue compositions (`JOURNAL.md`, round-three and round-four entries; `tests/round4_attacks.py`). Nevertheless, they preclude the broader claim that every discovered defect was outside composition. The defensible conclusion is that the published clean sweep did not reveal these failures; directed fixtures and newly specified assertions did.

### 7.1.1 What the counterexamples establish

| Reviewed behavior | Why an earlier success was insufficient | Required distinction |
|---|---|---|
| Package-status comparison | Equal name sets can conceal differing package versions. | Check the intended name/version union. |
| Registry visibility exemption | Exempting a rewritten database from path checks does not prove its records survived. | Supply a semantic assertion for the exemption. |
| Regular-file visibility | A different file of equal size can satisfy a kind/size test. | Visibility and content identity are different properties. |
| Account reconciliation | An equal UID can conceal a changed primary GID. | Check both identity fields and reject incompatible records. |
| Diversion parsing | Ignoring a partial record can make malformed input appear successfully merged. | Distinguish absent input from invalid input. |
| Guest probes | A command can work while a required service unit has failed. | Observe probes, service state, and listeners separately. |
| Timing and evidence selection | A recent file may omit sets, and a composition timer may exclude verification. | Retain the measured scope and test completeness and freshness. |

Table 7.1: Mechanisms exposed by adversarial review. Sources: `thesis/evidence/inconsistencies.md`, `tests/round2_attacks.py`, `tests/round3_evidence.py`, `tests/round4_attacks.py`, and the corresponding dated `JOURNAL.md` entries. This is a qualitative classification, not an independently enumerated defect count.

The regression labels require interpretation. `FIXED` means a reproduced defect now has an assertion for the intended behavior: that may be rejection of invalid input or a correct merge of valid input. `CONTROL` protects a valid case against an overbroad repair. A passing `KNOWN OPEN` case confirms that a documented blind spot still reproduces; it does not certify that the blind spot has been closed. Thus an all-green test summary cannot be read without its expected outcomes.

The documentation audit reinforces the same methodological concern. Its 29 closed entries concern claims and their evidence (`thesis/evidence/inconsistencies.md`, index). They are not a substitute for a deduplicated implementation-defect inventory. Neither the number of reviews nor the total number of tests proves completeness. Each acceptance claim needs a counterexample that would falsify it and a retained result showing that the checker responds as intended. Shared parsing code reduces inconsistency between producer and consumer, but can also make both agree on the same incorrect interpretation; independently constructed fixtures remain necessary.

### 7.1.2 Consequences for the tiered result

Passing V1–V8 means the recorded predicates passed for the historical compositions in Chapter 6. It does not establish arbitrary filesystem equivalence, service coexistence, or correctness on subsequently rebuilt artefacts. A stronger verifier changes the meaning and potentially the cost of verification. Its new timing must be measured; an old duration cannot be attached to an expanded set of assertions.

There is a separate reproducibility problem in the measurement pipeline. The September 22 journal audit found retained Jammy manifests that still matched their artefact hashes but lacked the generation field required by the newer validator. A published accepted set could consequently be rejected when checked with the newer code. A scratch adoption procedure restored compatibility. This is a historical example of schema drift, not a claim that the later refreshed catalogue still lacks the field (`JOURNAL.md`, “thorough check of experiment/noble-generation”). A result therefore needs the checker revision and metadata schema as well as the module names. “Current” in Chapter 6 identifies the retained evidence snapshot; it does not claim that this thesis revision reran the live system.

## 7.2 Conflict boundaries and order dependence

Class 8 is a system-level limit of the present static and structural checks. Nginx and Apache may satisfy package relations and produce a coherent root while both attempt to bind port 80. The retained reversed-order boots show nginx owning the socket and `apache2.service` failing (`thesis/evidence/tier3.md`, T3.1). Most of those bundles are now superseded. They establish the existence of the conflict, not a universal startup winner or a current full-catalogue boot guarantee.

The runtime outcome depends on configuration, ordering, and resource availability. Changing OverlayFS order is not equivalent to controlling service scheduling. Explicit port declarations could reject some known conflicts before boot, so it would be too strong to say that all resource conflicts are statically unknowable. What the present lower tiers cannot establish is successful coexistence of arbitrary services in the eventual running environment. Conversely, reaching systemd with one failed service is not proof that registry reconciliation failed.

V7 has a directly demonstrated blind spot: a regular file replaced with different bytes but identical size passes its kind/size comparison. `tests/round2_attacks.py` preserves this as `KNOWN OPEN`. Hashing contested paths against their intended winning layer would strengthen that assertion without requiring every byte of every layer to be checked again. It would still need an explicit policy for legitimate replacements, generated registries, links, modes, and ownership. A hash comparison cannot decide which layer ought to win unless the design first defines that answer.

Order independence is also bounded. The account and debconf reversals recorded in the project are equal as semantic record sets while their serialized bytes differ (`ARCHITECTURE.md` §4; `thesis/evidence/inconsistencies.md`, I-03). That property does not prove that every field is order-insensitive. Highest-layer choices for non-identity fields and ordinary conflicting paths can remain order-dependent. A declared stacking priority and tested semantic unions are defensible; a universal byte-identical root under arbitrary permutation is not.

Registry coverage is not identical to registry correctness. Chapter 5 describes intended formats and identifies implementation gaps for multiarch package status and differing diversion triples at one original path. It also distinguishes dedicated assertions from weaker indirect checks such as `dpkg --audit`. The taxonomy organizes policies for the known mechanisms; it is not a proof that all maintainer-script state belongs to one of the implemented registry groups.

## 7.3 Build reproducibility

Snapshot pinning fixes the APT archive view. With the same base, architecture, sources, preferences, and package request, it constrains package resolution. It does not make installation a pure function of package names. Maintainer scripts can read the clock or hostname, initialize a database, generate keys, and invoke tools whose output depends on traversal order or their version. An unpinned external package source is outside the APT pin entirely.

The independent rebuild report documents differing archives and investigates several mechanisms (`docs/evidence/remote-verification-2026-09-20/REPORT.md`). OverlayFS copy-up left `trusted.overlay.impure` attributes in one build context. Account files carried generated password-change dates; mail configuration captured host identity; Emacs index generation depended on input order. Java generated certificate and shared-archive state, while database packages initialized identifiers and internal data. The pip demonstration also admitted changing external package input. These examples explain why fixing the archive timestamp or stripping logs cannot alone establish byte reproducibility.

This was not a controlled experiment changing only the physical host. The report also records builder, specification, debootstrap, and host-tool differences. For example, changing the build parent from a directory to the exact mounted `base.sqsh` addresses a real provenance problem but changes the compared procedure. The report supplies diagnostic mechanisms, not a complete causal decomposition of every differing byte. Its quantitative cross-machine comparison is outside the permitted `thesis/evidence/` tables and is recorded as an evidence gap in `NOTES.md`.

The distinction among three properties is essential: equal resolved package metadata, equal installed filesystem state, and equal compressed archive bytes. Matching one does not imply the next. A digest identifies and checks an existing artefact; it does not ensure that another build will reproduce it. Nor does an unsigned digest authenticate the publisher. The generation identifier deliberately binds siblings to an exact parent, so independently rebuilt, byte-different bases cannot be silently treated as interchangeable.

Normalization also has semantic limits. Resetting machine identity for first boot may be appropriate; replacing all generated database state or cryptographic material merely to obtain a stable hash can change application behavior or duplicate identities. Future reproducibility work should classify generated paths, specify which state belongs at first boot, and test that transformation. The current pipeline does not establish that all runtime identity state has been isolated and regenerated.

## 7.4 Updates and the deployment lifecycle

An intra-generation specification change can rebuild one sibling against the same exact base. Its new artefact, manifest, sidecar, and admission results must be published coherently, and affected selected sets require verification again. The independence of sibling builds reduces rebuilding scope; it does not make an updated sibling automatically compatible with every old composition.

Changing the archive pin or base creates a new generation. The architecture requires rebuilding the base and siblings and prevents mixing their parent identities (`ARCHITECTURE.md` §13). That is a compatibility rule, not an implemented transaction protocol. The current pipeline has no transactional catalogue publisher, node update client, or measured atomic fleet migration. Publication should eventually expose complete generations, preserve the old generation until migration succeeds, and bind each deployed image to its selected modules, kernel, and configuration.

Server repository storage and node transfer remain different costs. Retaining a shared base and replacing one delta may save server-side storage or transfer between catalogue replicas that already hold the base. The implemented provisioning path flattens the selected root into a whole bootable image. It has no measured delta-transfer protocol to nodes. A percentage reduction in node-update traffic therefore cannot be derived from average module sizes.

Rollback likewise has several parts. Retaining an older verified image permits an operator to redeploy that image. It does not roll back persistent application data, prove backward compatibility of a database format, or supply a safe orchestration procedure. These require a deployment experiment rather than extrapolation from repository sizes.

## 7.5 Base sizing and fleet costs

Choosing between a thin and a fat base needs separate models for a repository and a node. Let the thin base have compressed size $B$, and module $m$ have delta size $d_m$. If a fat base adds $\Delta B$ and reduces that module's delta by $s_m$, the change in stored layer bytes for a repository containing module set $M$ is

$$
\Delta S_{\mathrm{repository}}=\Delta B-\sum_{m\in M}s_m.
$$

The base is counted once. Thus spreading a common dependency across many deltas can make base fattening attractive at repository scale, even when few individual workloads benefit. Chapter 6 reports a historical comparison traced in `thesis/evidence/claims.md` to the 38-module fat-base experiment: 1,023.8 MB became 777.2 MB, a derived reduction of approximately 24.1%. These are not the current 40-module storage totals.

For a single selected set $A$, an additive layer-size model instead gives

$$
\Delta S_A=\Delta B-\sum_{m\in A}s_m.
$$

The same historical audit records a base increment of 113.5 MB and a maximum individual delta saving of 69.6 MB, for `gcc` (`claims.md`, base-fattening rows). Since no single module saves enough to offset the increment, no single-module selection wins **under that experiment's layer-size model**. This is not a theorem for every future catalogue, and multi-module selections have a different break-even condition.

For a fleet, let node $k$ select $A_k$. Summing that model over $K$ nodes yields

$$
\Delta F=K\Delta B-\sum_{k=1}^{K}\sum_{m\in A_k}s_m.
$$

This is a model of repeated layer payloads, not a measurement of ModFS's flattened node images or network traffic. Flattening removes overwritten paths and changes compression; shared caches, repeated deployment, and transport protocols change transfer costs further. A homogeneous development fleet and a heterogeneous service fleet may therefore favor different bases, but their actual crossover requires their selection distribution and measured packed images.

Estimating a fat base by adding independently compressed module sizes can double-count shared dependencies and ignores compression changes. Nearly empty residual deltas cannot be assumed without rebuilding them. The retained fat-base experiment is the appropriate historical source. It supports an engineering trade-off: a minimal base limits compulsory payload for specialized nodes, while a larger base can reduce a server catalogue's duplicated dependencies. It does not guarantee that a minimal base contains no unused software or establish a measured security benefit.

## 7.6 GPU and platform boundaries

The GPU evidence separates guest boot, userspace computation, and operation of the packaged kernel driver. The still-current GPU-stack bundle establishes a successful guest boot and probes without GPU access (`thesis/evidence/tier3.md`, T3.1). The remote report describes CUDA userspace running on a real GPU using the provider's already installed driver and traces the userspace libraries to the rebuilt artefact. The GTX 1060 experiment belongs to the separate Ubuntu 24.04 branch, reviewed in the September 22 journal; it must not be substituted for the remote machine or the Jammy catalogue result.

The packaged NVIDIA module was reported to load, link, and initialize in its target kernel, stopping at hardware enumeration. It has not been demonstrated driving a GPU. A userspace workload using a host's existing driver does not close that gap. The next driver experiment needs accessible matching hardware, the intended kernel ABI, and the deployment's module-signing policy (`ARCHITECTURE.md`, GPU discussion). Packaging kernel objects is also different from supplying the bootable kernel image, which belongs to image construction.

The Ubuntu 24.04 branch provides a portability investigation with its own manifests, artefacts, and results. Its later audit records a completed replacement for an interrupted composition sweep, while the branch remained unmerged (`JOURNAL.md`, September 22). It is therefore inaccurate to call all its work unfinished, but equally inaccurate to import its measurements into the generated Jammy evaluation. Extending the mechanism to another package manager would require new registry semantics and package-relation handling, not merely a different image filename.

## 7.7 Threats to validity and next experiments

**Construct validity.** Kind/size visibility is weaker than content preservation; a probe is weaker than service health; a digest is weaker than reproducibility or authenticity. Registry-specific tests leave other mutable package state outside their observation. The conclusions must name the predicate actually tested.

**Internal validity.** Changes in artefacts, manifest schemas, checker revisions, and harness behavior prevent treating all retained results as repetitions of one experiment. The physical timing summaries lack controlled cache-state repetitions and uncertainty estimates. Their high fit quality is descriptive, not evidence that only layer count causes cost. QEMU timings include virtualization and harness effects; the thesis has no paired bare-metal experiment from which to infer a speedup.

**External validity.** The catalogue deliberately exercises conflicts and contains synthetic entries, a negative control, and large payload outliers. Its current server storage ratios, 5.43× for the small cohort, 1.20× for the large cohort, and 1.84× overall, are cohort properties as well as properties of base sharing (`thesis/evidence/storage.md`, S1 and S4). Every headline monolithic value uses the $B+d$ model; six built monoliths calibrate it on smaller deltas. They do not directly validate the largest payloads. Nor do sampled higher-order compositions establish long-lived node behavior or arbitrary package support.

The next experiments should first restore comparable evidence: confirm bundle and generation validity, rerun physical compositions with the current verifier, and boot representative sets from those exact artefacts. Then test content substitution on contested paths, cross-machine builds under controlled inputs, the packaged driver on hardware, and complete publication and rollback. Each addresses a distinct unsupported claim. The methodological contribution is to make those boundaries explicit: the usefulness of a clean verdict depends on whether its instrument could have seen the relevant failure.
