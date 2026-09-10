# ModFS Reassessment — 10 September 2026

This is a point-in-time, read-only reassessment of the repository and the
locally retained evidence after commits `4ed2c6a` and `b7f4942`. It supplements
rather than rewrites `docs/ASSESSMENT.md`, which remains the audit record of
the 3 September state.

No implementation file was changed for this reassessment. The only repository
change is this report.

## 1. Executive verdict

ModFS is unequivocally substantial enough for a bachelor thesis. It contains a
real systems artifact, a clear motivating problem, multiple non-obvious failure
modes, quantitative evaluation, negative controls, a three-tier validation
strategy, and a traceable engineering history. Its strongest contribution is
not simply “small SquashFS deltas save space.” It is the demonstrated boundary
between four different notions of composability:

1. provenance compatibility;
2. package-metadata consistency;
3. filesystem and global-state consistency; and
4. runtime/hardware coexistence.

The project is not production-ready, and it should not claim arbitrary safe
composition yet. The newest UID/GID work is valuable and experimentally
successful at preventing duplicate numeric allocations, but it leaves the
more fundamental whole-file account-database problem unresolved. In its
current form, the checker can admit a composition in which required service
accounts disappear.

That negative finding does not weaken the thesis. Properly reported, it makes
the thesis stronger: it shows that preventing identifier collisions and
constructing a coherent final identity database are separate problems.

The most objective summary is:

| Dimension | Assessment |
|---|---|
| Problem significance | strong |
| Implementation depth | strong |
| Experimental method | strong for one host and one distribution |
| Negative controls and failure analysis | unusually strong |
| Internal validity | medium; important oracles still omit account state and positive dependency closure |
| External validity | limited; Ubuntu 22.04, amd64, one artifact lineage, one host |
| Reproducibility evidence | good within-host artifact evidence; incomplete run provenance and no current cross-host proof |
| Production readiness | low |
| Bachelor-thesis worthiness | high |

Complexity alone does not make a thesis. ModFS is thesis-worthy because the
complexity has produced testable hypotheses, measured results, falsified
predictions, and a defensible account of where the abstraction fails.

## 2. What was inspected

The pass covered all current repository source, scripts, specifications and
Markdown files; the Git history since the previous audit; every current module
manifest; the retained pair/tier-2 CSVs; the maximal-subset output; catalogue
logs; and the tier-3 evidence bundles under `/srv/modfs/results/boot`.

Read-only host checks also inspected the current execution identity, available
storage, QEMU/tool availability, and NVIDIA device state. No build, mount,
chroot, package installation, image construction or boot was initiated.

Snapshot at inspection time:

| Item | Observed state |
|---|---|
| Git HEAD | `b7f49429f6209d951fc3c09c312a07d093ada710` |
| Tracked worktree before this report | clean |
| Project text | 8,767 lines across the inventoried source/docs/spec/test files |
| Catalogue declarations | 38 delta modules |
| Built catalogue entries | 37; `pipdemo` is missing |
| Manifests on disk | base plus 37 deltas |
| Artifact/manifest size or SHA-256 mismatches | 0 in the current local store |
| Current pair evidence | 666 pairs over 37 built modules |
| Current tier-2 pair evidence | 630 ordinary pairs: 595 `PASS`, 35 `NOT_ADMITTED` |
| Rootless syntax checks | all Bash files parsed; both Python helpers compiled |

## 3. Genuine progress since the first assessment

### 3.1 The destructive traversal described in C1 is closed for boot run names

Run names and module names now pass a strict identifier allowlist. Boot result
bundles are timestamped, live outside disposable build scratch, and are not
silently overwritten. Numeric boot parameters have bounds. The original
`--name ../../modules` path is no longer representable.

This is a real fix. It should be described narrowly, because the broader stale
mount/deletion hardening is not complete (section 6.1).

### 3.2 Admission is now enforced in stages 10 and 11

The intended order is now implemented in the two principal evaluation paths:

```text
artifact digest check -> tier-1 admission -> compose -> reconcile -> verify
```

Rejected sets are not composed by default. A deliberate bypass is labelled
`KNOWN_NEGATIVE`, which repairs the earlier semantic error where the MTA pair
could be tier-1 rejected and tier-2 “PASS” at the same time.

### 3.3 Tier-3 evidence is substantially better

The causal boot matrix now contains admitted single-service and dual-service
runs, per-unit state, journals and listener ownership. The two dual-service
runs reproduce Apache's port-80 bind failure with nginx holding the sockets,
in both layer orders. This directly supports the conclusion that OverlayFS
file priority does not determine which independent service wins a runtime
resource race.

This is one of the strongest thesis experiments in the repository because it
separates configuration validity from runtime health: both configuration
probes pass while a service fails after boot.

### 3.4 Numeric UID/GID collisions were prevented in the rebuilt catalogue

`specs/uid-ranges.yaml` assigns a disjoint 100-ID window to each module.
Before package installation, stage 02 configures both `adduser` and `useradd`
allocation ranges. This is the correct place to influence package maintainer
scripts: before they create accounts and files.

The retained manifests show 14 new user/group records across seven modules,
all within the assigned windows. The original four modules no longer all use
UID 103/GID 104. The current pair CSV records zero numeric identity
collisions, down from six affected pairs.

That result is valid as stated: **duplicate numeric allocation in the tested
builds fell from six affected pairs to zero**.

### 3.5 Module-level requirements are no longer inert metadata

Stage 05 now checks module `requires`, `conflicts` and `provides`. The fake CUDA
pair demonstrates a versioned capability requirement: `fake-cuda` needs an
`nvidia-driver >= 550` provider.

This is useful architecture work, particularly for GPU software where the
userspace toolkit, framework, kernel driver and hardware are distinct
compatibility layers.

### 3.6 The catalogue now contains realistic scale

GCC, Java, Rust, LLVM, PostgreSQL, MariaDB and Docker give the evaluation a
far better size and dependency range than the original small adversarial set.
Several predictions of conflict were falsified: the large toolchains share
many packages at identical versions. That is stronger support for the pinned
snapshot hypothesis than agreement among small utilities.

## 4. Critical new finding: Class 7 is not yet prevented

### 4.1 Numeric uniqueness and database composition are different invariants

The range policy fixes the numbers, but every account-creating delta still
contains a complete changed copy of `/etc/passwd`, `/etc/group`, `/etc/shadow`
and `/etc/gshadow`. OverlayFS selects the highest complete file; it does not
merge records from sibling files.

Stage 06 records only accounts added relative to base
(`scripts/06_extract_metadata.sh:359-364`). Stage 05 then constructs
`merged_users` and `merged_groups` by unioning those manifest fragments
(`scripts/05_check.sh:492-503`). That union does not exist in the composed
filesystem. `scripts/reconcile.py` does not handle any account database.

Direct artifact inspection demonstrates the problem:

```text
postgres.sqsh /etc/passwd -> base accounts + postgres
mysql.sqsh    /etc/passwd -> base accounts + mysql

base + postgres + mysql, with mysql highest
actual visible file        -> base accounts + mysql
checker model              -> base accounts + postgres + mysql
```

Therefore `User=postgres` is unresolved in that ordering even though stage 05
says it resolves. Reversing the order loses `mysql` instead.

Seven ordinary modules contribute a user or group database change:

```text
docker memcached mta-msmtp mysql postgres redis tcpdump
```

All 21 pairwise combinations among these seven are recorded as `ACCEPT` in
`pairs-v2.csv`. Every one necessarily loses at least one contributed account
or group record because one complete file wins.

The proposed 34-module “maximal” high-N set is more revealing. In its recorded
stacking order, `tcpdump` is the highest account-writing layer. Its visible
account files lose:

```text
users:  memcache, msmtp, mysql, postgres, redis
groups: docker, memcache, msmtp, mysql, postgres, redis, ssl-cert
```

A high-N boot of that set is therefore expected to fail multiple identity
dependent services unless some later image-construction side effect happens to
recreate the records. Such recreation would itself need to be specified and
tested, not treated as success by accident.

### 4.2 What should be claimed now

Do claim:

> Disjoint pre-install allocation windows eliminated the six observed
> cross-module numeric UID/GID collisions in the rebuilt catalogue.

Do not yet claim:

> Class 7 is prevented, service identities compose, or the 34-module set is
> boot-ready.

### 4.3 Required closure

Now that numeric IDs are disjoint, semantic record union is possible. The
composition/image stage needs one authoritative account-database operation
covering at least:

- passwd and shadow user records;
- group and gshadow records;
- supplementary memberships;
- `/etc/subuid` and `/etc/subgid` if relevant;
- duplicate-name/different-ID and duplicate-ID/different-name rejection;
- preservation of base records and password/lock semantics;
- every unit identity and relevant numeric inode owner;
- order-reversal equivalence.

An alternative is to create all identities only during final image
construction and remap every affected inode. That is more invasive. For this
thesis, strict account-database reconciliation followed by exact verification
is the smaller credible path because the numeric windows are already disjoint.

Tier 2 must then compare the actual composed account databases against the
expected semantic union. Tier 3 should boot `postgres + mysql` in both orders
and the high-N set, checking `getent`, unit state and numeric ownership.

## 5. Further UID/GID policy risks

### 5.1 The chosen range overlaps normal user IDs

The module windows span 2000–5799, while the built base's `login.defs` assigns
ordinary users from 1000–60000. Debian Policy likewise classifies 1000–59999
as dynamically allocated user accounts and 100–999 as dynamically allocated
system accounts. See the official [Debian UID/GID classes](https://www.debian.org/doc/debian-policy/ch-opersys.html#uid-and-gid-classes).

The build temporarily moves system allocation into ordinary-user space, then
restores the base policy. The final node has no rule reserving 2000–5799 from
future local users. A sufficiently used image can therefore assign a human
account a number already baked into module-owned files.

This needs an explicit namespace design. Options include reserving a suitable
range in the final image's local allocation policy, using a much denser
centrally assigned service-ID registry, or moving identity creation/remapping
to final image construction. Simply retaining the current ranges without
reserving them at runtime is unsafe.

### 5.2 Module range stability is not account stability

An append-only module window guarantees that two modules use different
windows. It does not guarantee that a particular account keeps the same ID
across versions of one module. If a new dependency creates an account first,
later allocations within the window can shift. PostgreSQL already shows why
order matters: `ssl-cert` consumes one group ID before the `postgres` group.

For updateability, the required invariant is name-to-ID stability across
module generations, or an explicit ownership migration. A deterministic
name-to-ID mapping or a committed per-account registry is stronger than a
per-module range alone.

### 5.3 The range file is policy text, not yet a validated allocation database

`uid_range_for` reads one start and adds the configured width. It does not
validate that all starts are unique, aligned, non-overlapping, in an approved
namespace, or large enough. The present file happens to be complete and
non-overlapping; the mechanism does not enforce that property before builds.

Add a rootless specification validator and make stage 08 run it before the
first build. Its output should be retained as evidence.

### 5.4 Account creation outside adduser/useradd remains possible

Hard-coded `--uid`, direct file edits, `systemd-sysusers`, first-boot account
creation, LDAP/NSS identities and `DynamicUser=` are separate paths. The
post-build audit catches some build-time escapes but not identities created
only at boot. The manifest and boot oracle should explicitly cover these
cases or state them out of scope.

## 6. Safety and correctness issues still present

### 6.1 Nested-mount detection is implemented incorrectly

`require_no_mounts` promises to detect a mount below a deletion target, but it
parses `$2` from `/proc/self/mountinfo` (`scripts/lib.sh:58-66`). The mountpoint
is field 5, not field 2. The fallback `mountpoint -q "$p"` checks only the
target itself, not child mounts.

Stage 11 consequently can miss stale mounts under its scratch directory and
then execute `rm -rf`. Several other stages still call `rm -rf` directly,
including stages 01, 02, 04, 07, 09 and 10. The original boot-name traversal
is fixed; the broader claim that safe recursive deletion was applied
everywhere is not supported by the code.

Do not run privileged destructive-path tests until this is corrected and
covered by an isolated canary/mount-namespace test.

### 6.2 Signal traps can still clean up and continue

`trap cleanup EXIT INT TERM` and the combined stage-11 trap return from the
signal handler rather than terminating with the signal status. The previously
reported H10 therefore remains open.

### 6.3 Artifact integrity is only partly bound

Stages 10 and 11 now verify each SquashFS hash against its adjacent manifest,
which is meaningful progress. Remaining gaps include:

- no exact parent-generation binding;
- no sidecar hash in the manifest;
- no check that a loaded manifest's internal `module` matches its filename;
- no binding of module spec, UID policy and builder revision to the artifact;
- stages 04 and 07 do not perform the same bundle check;
- a successful `integrity.txt` is empty, so the boot bundle does not retain
  the hashes it actually verified.

### 6.4 Positive package dependency closure remains unimplemented

The newly enforced module relations close former finding M5. They do not close
original finding C4. Stage 05 still does not verify every installed package's
`Depends` and `Pre-Depends` against the fixed final package set.

These are two different layers:

```text
module relation: cuda-toolkit requires nvidia-driver >= 550
package relation: package A depends on package/libc/virtual provider B
```

Both are necessary. Fixed-set dependency verification is not a full solver.

### 6.5 Multiple providers are documented as rejected but are not checked

`ARCHITECTURE.md:216` says that no capability may have two providers. Stage 05
builds a list of providers but only uses it to satisfy requirements and match
conflicts (`scripts/05_check.sh:555-603`). It never rejects duplicate
providers. Either define capabilities as non-exclusive and correct the
documentation, or add an explicit `exclusive_capability` concept. Generic
capabilities often legitimately have multiple providers, so unconditional
uniqueness would be too broad.

### 6.6 The maximal-subset algorithm is invalid for positive requirements

Stage 10 treats every rejected pair as an undirected conflict edge. Positive
dependencies are not monotone in that model:

```text
fake-cuda + unrelated-module                  -> reject (driver absent)
fake-cuda + fake-nvidia-driver + unrelated    -> admit
```

The recorded 34-module set already contains `fake-nvidia-driver` but excludes
`fake-cuda`. Adding `fake-cuda` satisfies its only module requirement, so the
statement “no further module can be added” is false under the current checker.
The n-ary confirmation proves that the chosen 34 are admitted; it does not
prove maximality.

Compute candidates using n-ary admission, or model requirements and conflicts
as a directed constraint problem. Also keep “maximal” (locally unextendable)
distinct from “maximum” (largest possible).

### 6.7 Tier 2 still does not test the newly important invariant

The current tier-2 oracle checks package-name sets, alternatives candidates,
linker SONAME inclusion and textual `dpkg --audit` output. It does not check
account databases, unit identities, filesystem ownership meaning, package
dependency closure, configuration validity or functional probes. Thus 595
`PASS` rows are structural passes under a deliberately incomplete oracle, not
595 proven-working systems.

At minimum, rename the result in thesis tables to `STRUCTURAL_PASS` until the
oracle covers the claimed invariant.

## 7. Pip, TensorFlow and CUDA

### 7.1 Current state: support is not demonstrated

`pipdemo` is declared but has no SquashFS artifact or manifest. Its retained
catalogue log records the earlier TSV-column bug before any successful build.
The parser fix was committed, but the module was not rebuilt. Therefore the
project currently has:

- a generic raw `post_install` hook;
- one failed pip demonstration;
- no measured pip file-collision blind spot from a completed artifact;
- fake CUDA dependency metadata;
- no real CUDA or TensorFlow module.

The present pip command is also neither version-locked nor hash-locked:

```text
pip3 install --no-cache-dir ... requests
```

It asks the live index for whatever `requests` resolves to at build time. That
breaks the repository's central snapshot/provenance premise.

### 7.2 CUDA is not simply a pip dependency

NVIDIA documents several installation mechanisms: native DEB/RPM packages,
a runfile, Conda and Python-focused pip wheels. It also separates toolkit
requirements from the driver and hardware requirements. See NVIDIA's official
[CUDA Installation Guide for Linux](https://docs.nvidia.com/cuda/cuda-installation-guide-linux/).

For ModFS, model at least three components:

```text
nvidia-driver/kernel module
        -> requires exact kernel ABI, hardware support, possibly DKMS/initramfs/Secure Boot

cuda-toolkit/userspace
        -> requires a compatible driver capability and compiler/runtime ABI

tensorflow environment
        -> requires Python ABI and selected CUDA/cuDNN/runtime capabilities
```

The driver's kernel coupling means a real GPU test cannot be validated by the
current kernel-less module build or ordinary QEMU boot without GPU passthrough.

### 7.3 Lack of a public repository snapshot is not the same as impossibility

The current documentation says real CUDA is unusable because NVIDIA's
repository has no snapshot service. A better conclusion is that the existing
*online APT snapshot backend* cannot represent it.

NVIDIA supports a local repository package for Ubuntu. A ModFS source-lock
step can download exact DEBs/repository metadata once, verify hashes and
signatures, store them in an immutable local input bundle, and then build
offline. That is conceptually the same provenance invariant as the Ubuntu
snapshot, implemented by materialization rather than a public timestamped URL.

### 7.4 TensorFlow should use an isolated, locked Python environment

TensorFlow's official Linux instructions use pip, including
`tensorflow[and-cuda]` for GPU support, and verify GPU discovery from Python.
See the official [TensorFlow pip installation guide](https://www.tensorflow.org/install/pip).

Do not make `--break-system-packages` the architecture. Build an isolated venv
under a stable path such as `/opt/modfs/venvs/tensorflow`, using a committed
lock file and a local wheelhouse. Pip documents `--require-hashes`, exact
pinning and `--no-index`/local artifacts as repeatable-install mechanisms; see
[Repeatable installs](https://pip.pypa.io/en/stable/topics/repeatable-installs/)
and [Secure installs](https://pip.pypa.io/en/stable/topics/secure-installs/).

Required metadata for a non-dpkg module should include:

- lock-file digest and every wheel filename/SHA-256;
- Python implementation, version, ABI and platform tags;
- installed distribution names/versions (`pip inspect` or equivalent);
- `pip check` result;
- an inventory of every path contributed by the module, independent of dpkg;
- ELF dependencies, SONAMEs and relevant GPU library constraints;
- source/index identity and signature policy;
- functional probes for CPU import/computation and, separately, GPU discovery
  and a small GPU operation.

The general solution is not “teach the checker about pip” only. It is to make
filesystem ownership inventory backend-neutral. Dpkg, pip, a vendor runfile or
a locally unpacked archive should all emit the same artifact contribution
schema. This is a strong possible thesis extension because it exposes which
parts of the current design are package-manager-specific.

### 7.5 Scope recommendation for the remaining thesis period

With the recorded 29 September deadline, full CUDA/driver/TensorFlow support is
too large to make a prerequisite for the thesis. A defensible staged result is:

1. rebuild and validate the small locked `pipdemo`;
2. add backend-neutral path inventory and prove it sees pip files;
3. build one version/hash-locked TensorFlow CPU environment and run it in a
   composed chroot or boot;
4. retain fake CUDA modules for exhaustive dependency tests;
5. if time and disk permit, materialize one exact CUDA userspace input bundle;
6. treat kernel-driver installation and real-GPU validation as a targeted
   hardware experiment or explicit future work.

The host does have a GTX 1060 and a working NVIDIA driver, so a real hardware
experiment is technically possible. `nvidia-smi` reports driver 580.173.02 and
driver API compatibility up to CUDA 13.0. That does not prove the CUDA toolkit
is installed; `nvcc` was not present during this inspection.

## 8. Current quantitative results, stated accurately

### 8.1 Pair and tier-2 results

The retained current tables show:

| Experiment | Result |
|---|---|
| Tier 1, 37 built modules | 666 pairs: 595 accept, 71 reject |
| Rejection composition | 36 control snapshot, 34 unsatisfied fake-CUDA pairs, 1 MTA conflict |
| Numeric Class-7 findings | 0 |
| Tier 2, 36 ordinary built modules | 630 pairs: 595 structural pass, 35 not admitted |
| Account-database correctness | not checked; at least the 21 accepted account-writer pairs violate union |

The current `pairs-v2.csv` predates the final stage-09 output-schema commit: it
does not contain the now-defined `module_relation` column. The current source
therefore cannot be claimed as the exact source that emitted that CSV without
additional provenance evidence.

### 8.2 Storage result after adding large modules

Current local artifact sizes are:

| Quantity | Bytes | Approximate |
|---|---:|---:|
| Base | 41,717,760 | 39.8 MiB |
| 37 built deltas | 966,459,392 | 921.7 MiB |
| Shared modular store | 1,008,177,152 | 961.5 MiB |
| Per-module monolithic estimate, calibrated as before | 2,492,446,396 | 2.32 GiB |
| Estimated ratio | | 2.47× |

This is about a 59.5% storage reduction relative to the calibrated monolithic
estimate. It remains a good result, but it is materially below the earlier
5.35× ratio. Seven deltas exceed 50 MiB and the largest, Rust, is about
167 MiB.

The correct conclusion is:

> Sharing the base always removes repeated base storage, but the aggregate
> ratio depends on the distribution of delta sizes. Adding large, mostly
> module-specific payloads can reduce the ratio even while increasing realism.

The statement that the ratio necessarily grows with module count should be
removed. This new result is more credible than a monotonic-growth claim and
provides a useful sensitivity analysis for the thesis.

## 9. Documentation status

`ARCHITECTURE.md` was updated for UID ranges and module relations, but not as a
coherent current-state document. Examples of material drift include:

- the header still says code freeze was 2 September despite 10 September
  implementation commits;
- section 6 still describes 27 modules and the old sample plan;
- section 7 still reports the 28-module, 256.7 MB, 5.35× catalogue;
- lines 412–415 still describe the pre-rebuild six Class-7 pair rejections;
- Future Work lines 580–582 say deterministic allocation is deferred and
  stage 05 only detects/rejects, contradicting the preceding implementation;
- “reconciliation makes composition order-independent” is too broad while
  account files, debconf, triggers and runtime resource races remain
  order-sensitive or unreconciled;
- `EVOLUTION.md` stops before the current prevention work;
- `README.md` is far behind the actual pipeline.

Keep `JOURNAL.md` append-only as the chronological lab record. Make
`ARCHITECTURE.md` the single current truth and label old tables explicitly as
historical experiments. Do not silently rewrite the old assessment; cite this
addendum as its follow-up.

## 10. Evidence and testing improvements

### 10.1 Preserve tier-1 and tier-2 runs like tier 3

The current tier-1/tier-2 CSVs live in mutable log paths and have no adjacent
source manifest. The source files were changed after the latest CSVs were
generated. Give every sweep an immutable result bundle containing:

```text
run.json               command, expectation, seed/plan, start/end, exit
source.txt             commit, dirty diff hash, script/spec/policy hashes
artifacts.txt          artifact + manifest + sidecar hashes
input-plan.csv
result.csv
stdout.log / stderr.log
summary.json
COMPLETE
```

### 10.2 Add committed, repeatable tests

Many important validations exist only as prose in the journal or as one-off
shell experiments. Add rootless fixture tests for:

- every package conflict class and malformed relation input;
- virtual version semantics;
- duplicate/exclusive capability policy;
- positive dependency closure;
- UID-range specification validation;
- account merge, membership merge and order reversal;
- manifest/filename/sidecar/generation binding;
- maximal-subset behavior with positive dependencies;
- checker exit 0/1/2 and worker-loss accounting.

Add isolated privileged integration tests for stale mounts, cleanup on each
signal, whiteouts/opaque directories, composition order, and interrupted
publication. These tests should run in a private mount namespace or disposable
VM, never directly against the only artifact store.

### 10.3 Strengthen the experiment design

For every headline result, record:

- hypothesis before the run;
- independent and dependent variables;
- exact oracle and what it does not observe;
- positive and negative controls;
- repetitions and variance where timing/races are involved;
- source/artifact identity;
- result and any retraction.

The project already does much of this informally. Turning it into a consistent
table will make the evaluation chapter unusually strong.

## 11. Prioritized work

### P0 — before a high-N boot or strong Class-7 claim

1. Reconcile or construct final account databases and verify the actual files.
2. Resolve the 2000–5799 collision with the normal-user namespace.
3. Define account-ID stability across module versions.
4. Correct nested-mount detection and route recursive deletion through one
   tested helper.
5. Replace the false maximal-subset claim; verify candidate additions n-arily.
6. Update `ARCHITECTURE.md` to the current evidence and terminology.

### P1 — before freezing thesis measurements

1. Add positive package-dependency closure.
2. Add account/ownership checks to tier 2.
3. Bind sidecar, parent generation, source policy and manifest identity.
4. Preserve immutable tier-1/tier-2 evidence bundles.
5. Re-run the current HEAD so result schemas and source hashes match.
6. Recompute storage tables for both the small adversarial and large realistic
   cohorts rather than mixing them into one headline.

### P2 — bounded ecosystem extension

1. Rebuild a locked, offline `pipdemo`.
2. Generalize file inventory beyond dpkg ownership lists.
3. Add one locked TensorFlow environment and CPU-level runtime probe.
4. Keep real CUDA userspace/hardware validation as a separate targeted lane.

### P3 — future work or production hardening

- debconf and dpkg-trigger reconciliation;
- whiteout/removal and opaque-directory semantics;
- atomic multi-file publication and locking;
- full multiarch handling;
- secure boot, DKMS, kernel/driver update coupling;
- real BMaaS integration and rollback/generation retention;
- cross-host and clean-room reproduction;
- broader runtime resource modelling.

## 12. Recommended thesis claim and research questions

A defensible central claim is:

> For Ubuntu package sets built as sibling deltas from one pinned and aligned
> base, shared-base storage substantially reduces duplication and makes many
> package-level incompatibilities cheap to verify. Safe composition still
> requires explicit reconciliation of global mutable state, while runtime and
> hardware compatibility require stronger validation tiers.

Useful research questions are:

1. How much storage does pinned sibling-delta modularization save, and how does
   the saving change with module size distribution?
2. Which incompatibilities can be decided from package/module metadata, which
   require filesystem/state reconciliation, and which appear only at runtime?
3. Can deterministic pre-allocation eliminate cross-module numeric identity
   collisions, and what additional mechanism is needed to compose the final
   account namespace?
4. What evidence is required before a structurally composed filesystem can be
   called a working machine image?

The third question is particularly valuable because the present result is not
a clean success or failure: the allocation policy succeeds at its exact goal,
then exposes the next missing invariant. That is excellent thesis material.

## 13. Final objective assessment

The project has progressed materially since the first audit. The safety of the
specific boot-run path, admission semantics, boot evidence, catalogue realism,
numeric identity allocation and module relationships are all better.

The next best move is not to maximize feature count. It is to close the
identity-database gap, correct the measurement/documentation record, and make
the current evidence self-identifying. One tightly scoped, reproducible pip or
TensorFlow extension would add value; attempting full CUDA, driver, Secure
Boot, TensorFlow and general external-repository support before the thesis
deadline would dilute the strongest contribution.

As a bachelor thesis prototype, this is already strong. As a claim of safe,
arbitrary, production composition, it is not yet defensible. The difference
between those two statements should remain explicit throughout the thesis.
