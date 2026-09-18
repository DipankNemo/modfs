# Independent second review — 18 September 2026

Reviewed commit: `a174110964c6230de0c7cff1ff2a3a4c8d3d4b80`.

The current catalogue composes much better than the verification claims warrant. I independently reran all **703 tier-1 pairs: 630 ACCEPT, 73 REJECT, no changed verdicts**. I physically composed **all 630 admitted pairs** from the shipped SquashFS files: every composition passed the current verifier. A separate parser comparing **all debconf fields**, including the union of Owners, found **zero discrepancies** in those 630 compositions. That is positive evidence for `merge_debconf` on this catalogue. It is not evidence that V8 verifies those fields: it does not.

The serious findings are false assurances: the sidecar binding is not enforced as documented; V8 accepts databases stripped of every answer; V7 accepts a broken Python symlink; V6 accepts a malformed, world-readable shadow database. There is also a real state-reconciliation defect without any injected corruption: a requested rsync installation becomes automatically installed when composed with mysql.

I read `CLAUDE.md` and the canonical `ARCHITECTURE.md` first, inspected the implementations and ran independent experiments, then read the final approximately 900 lines of `JOURNAL.md`. I subsequently checked selected earlier journal claims. The journal was treated as a claim inventory, not as evidence that a fix works. I did not use the author's passing test suite as a correctness oracle.

**Evidence and safety.** Scratch evidence is under `/srv/modfs/build/codex-review-20260918` (abbreviated **E** below). Original modules were mounted read-only. Modified manifests, repacked artefacts, local test packages and composition upperdirs were confined to E. No original artefact, script, spec, configuration or result bundle was changed. All seven published CSVs were copied to `E/published` before experiments and checked byte-identical to their originals afterwards. No `rm -rf` was used; scratch was retained. All review mounts were torn down. This document is the only repository file changed.

**Labels.** Every numbered finding below is **CONFIRMED** by execution. “Injected” means I deliberately damaged an isolated copy or composed upperdir; it does not mean that damage exists in the published catalogue. I distinguish these from defects observed using unmodified artefacts. Untested possibilities are listed at the end, not promoted to findings.

## High severity

### H1 — The class-4 sidecar seal is not enforced at tier 1, and is optional at the bundle gate

**CONFIRMED; isolated copies of real manifests and sidecars.** `05_check.sh:239` checks the manifest fields digest, but `load_sidecar` at approximately line 467 reads the decompressed sidecar without checking `binding.sidecar_sha256` at all. `lib.sh:244` checks that digest only **if the field exists**. The field itself is outside `binding.fields_sha256`.

Results using the real `base`, `curl` and `jq` bundles:

| Intervention | Tier 1 | `verify_bundle` |
|---|---|---|
| Original copies | ACCEPT, zero warnings | — |
| Add `/usr/bin/jq: curl` to curl's sidecar; leave the entire manifest unchanged | REJECT for a fabricated file collision; no binding mismatch | Rejects SIDECAR DIGEST MISMATCH |
| Also delete only `binding.sidecar_sha256` | Sidecar remains trusted by tier 1 | **Exit 0** |

No fields digest was recomputed for either intervention. A stale or edited sidecar can therefore alter a published tier-1 verdict. At the bundle gate, omission disables the purported protection. This is distinct from the acknowledged lack of signatures: ordinary unresealed drift is already enough. The same unchecked input can invent collisions or erase ownership/diversion evidence.

`12_verify_binding.sh` is a useful additional defence, but it does not make the statement in Architecture §5 that both seals are “verified at tier 1” true. Its re-derivation also detects a missing sidecar digest when it actually checks that module; M3 covers its separate selection problem.

**Reproduction:** run Appendix B. Evidence: `E/forgery/{original,sidecar-only-collision,bundle,bundle-no-sidecar-hash}.log`.

**Required correction:** verify the uncompressed sidecar digest wherever class 4 consumes it, require the field for bound manifests, and have the consumer enforce the required coverage/schema. Do not let optional integrity metadata select whether integrity is checked.

### H2 — V8 proves that question names survive, not that debconf records or answers survive

**CONFIRMED; injected into a real composition.** `verify_compose.py:200–215` extracts only lines beginning `Name: ` and compares name sets. `Template`, `Value`, `Owners`, template types/descriptions, duplicate records and all other fields are invisible. V7 explicitly exempts these files from its size comparison.

I composed `base curl pyyaml postgres java zstd`, reconciled it and regenerated alternatives and the linker cache. I then replaced both `config.dat` and `templates.dat` with just their original `Name:` lines separated by blank lines. Every answer, owner and template definition disappeared.

The baseline and corrupted verifier rows were **identical**, including:

```text
pkg_expected=190 pkg_actual=190 pkg_ok=1
alt_groups=40 alt_groups_bad=0 ld_ok=1 audit_ok=1
acct_expected=132 acct_ok=1 dbc_expected=148 dbc_ok=1
vis_missing=0 vis_ok=1 result=PASS
```

`debconf-communicate` subsequently emitted uninitialized-template/item warnings and `GET debconf/frontend` returned an empty value. I recollected dpkg, linker-cache and audit observations after corruption; this was not a verifier run against deliberately stale observations.

**Reproduction:** Appendix A with `CASE=debconf`. Evidence: `E/attacks/{baseline,debconf-names-only,debconf-client}.txt`.

**Required correction:** compare parsed record contents against the permitted merge, including Owners sets. If only name coverage is intended, call the column/name-coverage claim that. “Every question any layer answered survives” and “by record” currently overstate the invariant. The merge itself passed the independent 630-pair content check; this finding concerns the verifier's inability to detect a broken merge.

### H3 — V7 accepts a nonexistent symlink target, even when the link's length changes

**CONFIRMED; injected into the same real composition.** At `verify_compose.py:272`, every symlink becomes `('l', 0)`. The target is never read, and even `lstat().st_size` is discarded. Avoiding symlink traversal is correct; ignoring the link's own contents is a separate choice.

Replacing `/usr/bin/python3 -> python3.10` with `/usr/bin/python3 -> no-such-python` left the entire tier-2 row unchanged: `vis_missing=0`, `vis_ok=1`, **PASS**. Running `python3 -c 'import yaml'` inside the same chroot exited **127**, with “No such file or directory”. The real interpreter file was still present, so the path union remained complete.

This is not the previously documented padded, same-size regular-file attack. The symlink lengths differ, and comparing targets with `readlink` needs neither traversal nor hashing executable contents. The current claim of comparing “kind and size” needs this exception made explicit.

**Reproduction:** Appendix A with `CASE=symlink`. Evidence: `E/attacks/{python-symlink,python-client}.txt`.

**Required correction:** compare the link target with the appropriate layer target(s), without resolving it on the host. State separately what precedence and intentional link replacement the check permits.

### H4 — V6 does not check the claimed exact semantic union of account databases

**CONFIRMED; injected into the same real composition.** V6's parser includes only passwd, group, shadow and gshadow; it omits subuid/subgid. It checks passwd UID/GID and group GID, requires expected names to exist, and checks that expected membership is a subset of actual membership. It does not compare password hashes, shadow ageing fields, home/shell, complete record shape, extra accounts, extra memberships, permissions or ownership (`verify_compose.py:127–181`).

I replaced every shadow line with just `name:*` and changed `/etc/shadow` to mode **0644**. The original file had mode **0640**. The records were now malformed and the file world-readable. The result was still **PASS**, with `acct_ok=1`; the complete CSV row was identical to baseline. V7's reconciled-path existence check supplies no further protection.

Architecture §4 says “compared record by record, not by count”; stage 10's header explicitly lists all six account databases and calls the comparison an “exact SEMANTIC union”. Those descriptions are false. The preservation code in `merge_accounts` may work on the current catalogue, but its verifier would not detect these failures.

**Reproduction:** Appendix A with `CASE=shadow`. Evidence: `E/attacks/malformed-world-readable-shadow.txt`.

**Required correction:** define and check an explicit schema and semantic equality for all six files, including expected access mode/owner. Legitimate differences need declared rules, not unexamined fields.

## Medium severity

### M1 — Reconciliation loses an explicitly selected package's manual-install state

**CONFIRMED; unmodified real catalogue.** The `rsync` module requests `rsync` and records `packages.rsync.auto=false`. The `mysql` module installs that same package as a dependency, with `auto=true`. `merge_extended_states` unions the present stanzas; an absent automatic-install record in the requesting module cannot override the sibling's `Auto-Installed: 1` (`reconcile.py:401–412`).

For `base rsync mysql`, both tier 1 and tier 2 pass. Inside the reconciled composition:

```text
apt-mark showauto rsync       -> rsync
apt-mark showmanual rsync     -> [empty]
apt-get -s autoremove mariadb-server
                             -> Remv rsync [3.2.7-0ubuntu0.22.04.7]
```

Thus removing the database workload with autoremove also proposes removing the separately selected rsync workload. This is a dry-run observation; I did not claim to have performed that removal. `base gawk mysql` also demotes the requested gawk package to automatic in both stacking orders, although that particular autoremove simulation retained gawk. I do not claim otherwise.

**Reproduction:** Appendix A with `CASE=auto`. Evidence: `E/auto-rsync/{auto,manual,autoremove,verify}.log`; the verifier row ends `98,1,0,1,PASS`.

**Required correction:** derive manual/automatic status from complete per-layer package state and explicit requests. Merely unioning positive automatic-install records is not the semantic union of installation intent. There is currently no dedicated tier-2 check of extended_states semantics.

### M2 — Changed inherited accounts are omitted from the manifest, so class 7 misses their UID collisions

**CONFIRMED; deliberately modified artefact, freshly generated manifest.** `06_extract_metadata.sh:438–442` records users/groups only when their **names are absent from the parent**. It drops changes to inherited names.

I unpacked a copy of the real curl delta, added base's passwd file with `_apt` changed from UID 100 to UID 0, and repacked it. I then ran the unmodified extractor. It generated `accounts.users={}` and `file_uids=[0]`. There was no forged manifest:

```text
06 extraction                     exit 0, source artifact
05_check.sh curl                   ACCEPT, 0 errors, 0 warnings
12_verify_binding.sh curl          1 matched, exit 0
class 7                           “no id reused [OK]”
```

The artefact now assigns UID 0 to both root and `_apt`; class 7 reports the parent accounts as if the inherited record had not changed.

**Important containment:** I also composed this artefact. `reconcile.py` returned **2** and reported `_apt` having IDs 100 and 0. This is a confirmed tier-1/extraction gap, **not** an end-to-end admission bypass through the current stage-10 reconciler. Re-derivation cannot repair an extractor that discards the relevant difference.

**Reproduction:** Appendix C. Evidence: `E/inherited-account/{extract,tier1,binding}.log`, `E/followup/account/reconcile.log`.

**Required correction:** record and validate modified/deleted inherited identities as well as additions. Keep the reconciler's independent rejection.

### M3 — Stage 12 returns success for missing requested manifests and for names it never checks

**CONFIRMED.** `12_verify_binding.sh` counts `ABSENT`, but its exit condition checks only `BAD` and `BUNDLE_RC`. Requested names absent from the catalogue are silently filtered out by `want_this`.

```text
12_verify_binding.sh curll          exit 0; 0 matched, 0 mismatched, 0 absent
12_verify_binding.sh curl
  against an empty modules dir     exit 0; 0 matched, 0 mismatched, 1 absent
```

A successful catalogue-binding command can therefore mean no binding was verified. This is material because stage 12 is the expensive, once-per-catalogue defence on which the cheap checks rely.

**Reproduction, from the repository root:**

```sh
R=$(sudo mktemp -d /srv/modfs/build/review-missing.XXXXXX)
sudo mkdir "$R/modules"
sudo env MODFS_ROOT="$R" scripts/12_verify_binding.sh curl; echo "rc=$?"
sudo env MODFS_ROOT="$R" scripts/12_verify_binding.sh curll; echo "rc=$?"
```

Evidence: `E/absent-manifest/result.log`, `E/forgery/binding-typo.log`.

**Required correction:** reject unknown requested names, fail if any required manifest is absent, and require nonzero checked coverage. Distinguish an explicitly partial catalogue run from a verified complete catalogue.

### M4 — PostgreSQL's rewritten probe passes when the server cannot execute successfully

**CONFIRMED; injected into an isolated real `base postgres` composition.** The current probe (`specs/modules.yaml:163`) checks executable mode, account resolution and state-directory ownership. It never executes postgres.

Replacing `/usr/lib/postgresql/14/bin/postgres` with an executable shell script containing `exit 99` produced:

```text
catalogue postgres probe           exit 0
postgres --version                 exit 99
```

The earlier sibling-psql mistake is fixed, but replacing it with `test -x` still does not establish that the server loads. A server version/configuration command or disposable local database exercise is a stronger offline check. This particular short replacement would also change file size; I am reporting a **probe false assurance**, not claiming this mutation evades V7.

**Reproduction:** Appendix A with `CASE=postgres`. Evidence: `E/probes/postgres/broken-server.log`.

## Low severity and bounded false positives

### L1 — The zstd probe fails on its own successful previous output

**CONFIRMED; legitimate repeat on a real composition.** Running the exact zstd probe twice gives exit 0 then exit 1: `/tmp/z1.zst already exists; not overwritten`. It uses fixed names and no overwrite flag (`specs/modules.yaml:287`).

**Reproduction:** Appendix A with `CASE=zstd`. Evidence: `E/attacks/zstd-{1,2}.txt`.

This is a probe false positive, not a broken compressor. Fresh stage-07 compositions avoid it; a reused root or ordinary pre-existing temporary file does not. Use a uniquely owned temporary directory or make the probe deliberately repeatable.

### L2 — The new Replaces rejection is justified with an incorrect statement about dpkg

**CONFIRMED; local test packages installed with real dpkg inside the shipped base.** `05_check.sh:494–506` and the journal's “FN-3 FIXED” entry say that side-by-side installation requires Breaks/Conflicts as well as Replaces. That is not dpkg's rule for partial file takeover.

I built `review-a` and `review-b`, each owning `/usr/share/review-replaces/shared` plus a distinct file. B declares only `Replaces: review-a`. Installing A and then B with dpkg inside base succeeded: **both `install ok installed`**, B's shared-file contents visible, `dpkg --audit` empty. Freshly extracted sibling manifests were rejected by ModFS for that one collision.

Debian Policy permits file takeover through Replaces; it distinguishes that from whole-package replacement/conflicts. [Debian Policy §7.6](https://www.debian.org/doc/debian-policy/ch-relationships.html#overwriting-files-and-replacing-packages-replaces).

**Boundary:** this is a compatibility false positive if ACCEPT is meant to describe dpkg co-installability. It is **not proof that arbitrary-order OverlayFS stacking safely implements dpkg's ownership transfer**. A conservative ModFS rejection can be justified by that stronger requirement; the claim about what dpkg requires cannot. Do not “fix” this by blindly suppressing every Replaces collision. The older Architecture H3 limitation remains relevant.

**Reproduction:** Appendix A with `CASE=replaces` builds and installs the two minimal packages in a disposable base composition. The retained sibling artefacts permit the additional observed checker result to be rerun with:

```sh
sudo env MODFS_ROOT=/srv/modfs/build/codex-review-20260918/replaces \
  scripts/05_check.sh review-a review-b
```

Evidence: `E/replaces/control/{a,b}-install.log`, `E/replaces/tier1.log`. The package contents and generated sibling bundles are retained under that directory.

### L3 — Canonical claims still mix measurement generations and contradict retained evidence

**CONFIRMED by recomputation and direct file inspection.** These are documentation faults, not newly discovered composition failures:

* Architecture §6 still labels **181–808 ms** “Compose + verify”, and derives the 2× tier-1 and 230–250× tier-3 comparisons from it. The same document correctly says verification is excluded, and its new N=36 table says **1090 ms**. An explanatory caveat does not make the incompatible table/ratios valid.
* Architecture §7's total fit `148 + 27.2 N` is real, but the later split `21.5 + 6.7 N` and `126.2 + 13.2 N` sums to a slope of **19.9**, not 27.2. The “18.8 → 19.9, +6%” paragraph is also from an older measurement.
* The unconditional “reconciliation also makes composition order-independent” remains in §7 despite the narrower caveat elsewhere. On real `base gawk mysql` versus `base mysql gawk`, I obtained record-equal but **byte-different status and extended_states**. This reproduces the boundary, not a new discovery of the already documented byte-order limitation.
* “Testing [a larger base] ... has not been run” is contradicted by the retained `results/fatbase/fatbase-analysis-2026-09-17T163305Z.txt` and its per-module CSV. These files evidence that an experiment was recorded; I did not independently rebuild the fat base.
* The three displayed reproducibility hashes in §7 are not hashes of the current base/webserver/pytools artefacts. That does **not** disprove historical reproducibility, but they need a generation/date rather than appearing to identify the current artefacts.

**Reproduction:** Appendix D for fits and storage; the following for the other direct observations:

```sh
sha256sum /srv/modfs/modules/{base,webserver,pytools}.sqsh
cat /srv/modfs/results/fatbase/fatbase-analysis-2026-09-17T163305Z.txt
rg -n 'order-independent|not been run|808|6.7|13.2|19.9' ARCHITECTURE.md
# Reproduce two fresh orders with Appendix A, CASE=baseline:
# SET='base gawk mysql', then SET='base mysql gawk'.
# Compare their retained upper/var/lib/dpkg/status and
# upper/var/lib/apt/extended_states by bytes and by parsed stanza dictionaries.
```

Current hash prefixes: base `e4fbed70bb74f351`, webserver `19b9a57b8ec407e0`, pytools `c9e66c22e399732b`. Scope thesis claims to an identified evidence generation and replace stale paragraphs instead of accumulating contradictory corrections.

## Published numbers: independently recovered and not recovered

| Claim | Independent result |
|---|---|
| 5.59× small / 1.32× large / 2.51× all | **Recovered from current artefact byte sizes:** 5.588457900 / 1.315747051 / 2.507699632. These are modelled monolithic ratios, not measurements of all 38 monoliths. |
| Six monolith calibration errors below 1% | **Recovered:** curl 0.906%, jq 0.949%, nc-traditional 0.946%, webserver 0.822%, pytools 0.249%, emacs 0.512% overestimation, using `(base+delta)/measured−1`. This does not establish equivalent installed contents or calibrate the seven large modules. |
| 148 + 27.2 ms × N | **Recovered from the preserved pre-round2 CSV:** 148.285629 + 27.200303 N, 152 PASS rows. This is not the fit of the current published CSV. |
| Current compose-sweep.csv | **Recovered:** 160.696749 + 27.013002 N, R² 0.969692. Mount: 18.924173 + 8.029288 N; reconciliation: 141.772576 + 18.983714 N. All 152 rows have `total_ms = mount_ms + reconcile_ms`. |
| 630 ACCEPT / 73 REJECT of 703 | **Recovered and rerun:** fresh direct invocations of 05 for every pair, with independently collected exit codes; no differences. I did not use 09's text-classification logic as the independent oracle. |
| Tier 2 verifies each composed system against its own layers | **True for the implemented, limited predicates. False as an unrestricted correctness claim.** All 630 admitted pairs physically passed; H2–H4 demonstrate broken composed state that those predicates accept. |
| Order independence | **Recovered for record contents in the two gawk/mysql orders checked here; disproved for byte identity.** Existing postgres/mysql reverse-order boot bundles both record PASS. Existing nginx/apache reverse-order bundles both record the expected runtime failure. Neither pair proves arbitrary catalogue permutations or arbitrary future modules order-independent. |

Exact storage inputs, decimal bytes:

| Cohort | N | Base + deltas stored | Modelled sum of monoliths |
|---|---:|---:|---:|
| Small | 31 | 272,756,736 | 1,524,289,536 |
| Large | 7 | 792,743,936 | 1,043,050,496 |
| All | 38 | 1,023,782,912 | 2,567,340,032 |

Base is 41,717,760 bytes; the seven large modules are gcc, java, rust, llvm, postgres, mysql and docker. The all-catalogue accounting includes the deliberate old-snapshot control and artificial modules. It is catalogue storage accounting, not a claim that the entire set is admissible.

Evidence anchors:

```text
original combinations.csv SHA256
e74faf3298a90e402d27ca1b8c61af2f3ef5bb07f95139062888e31b203a40cf
original compose-sweep.csv SHA256
b383725ee699bde86ebeaba74ec344694e7e6e383233a772c3c17cf197fe64df
fresh tier-1 results: E/tier1/independent.json
fresh 630 compositions and independent debconf comparisons: E/pairs/results.json
```

The 630-pair run took approximately 199 seconds with read-only artefact mounts reused across pairs. **That is not a replacement latency fit**: it deliberately uses a different mounting strategy and records zero placeholders in the verifier's timing columns. It establishes coverage/correctness observations, not published stage-10 performance.

## All 38 probes, individually assessed

I executed each of the 37 usable modules' probes on a composition containing base and that module; fake-cuda also included its required fake-nvidia-driver. All passed with correct chroot plumbing. The deliberately incompatible control was reviewed but not presented as an admitted singleton test. No network service was contacted.

My first independent harness omitted `/run/lock` and a separate `/dev/pts` bind, causing apache and tmux failures. Repeating those two with the plumbing that the repository already supplies made both pass. **Those initial failures were my harness errors, not ModFS findings.** Git's deletion of an absent `/tmp/g` was replaced by a shell `rm` shim that asserts the directory does not exist, preserving the fresh-root result without performing deletion.

“No substitute demonstrated” below does not claim exhaustive provenance testing against every sibling. A successful functional test of shared identical package bytes is evidence about the composed system; it is not proof that the named module supplied those bytes.

| Module | What the current probe establishes / remaining weakness |
|---|---|
| vim | Performs and checks an actual edit, then checks editor registration. Current `&&` chain is effective; no substitute demonstrated. |
| emacs | Loads Emacs and evaluates its version expression; verifies registration. Does not exercise editing or broader Lisp/package functionality. |
| gawk | Runs gawk and checks its registration. **Confirmed PASS with gawk module absent, mysql alone present.** Already documented in spec. |
| original-awk | Runs the specifically named implementation. Does not merely resolve generic awk; no substitute demonstrated. |
| nc-openbsd | Specifically named binary and recognizable help. No socket transfer; help can pass while networking is broken. |
| nc-traditional | Specifically named binary and recognizable help. Same functional limit; sibling alternative cannot substitute by generic name. |
| webserver | Configuration syntax and expansion. Does not prove nginx binds/serves; the boot evidence already demonstrates this boundary. |
| apache | Configuration/module-loading checks. Does not prove it can bind port 80; expected negative boot case remains valid. |
| mta-msmtp | Loads msmtp and checks sendmail resolution. No queuing/delivery demonstrated. |
| mta-nullmailer | Executable presence plus dpkg ownership, explicitly documented. Does not execute the checked mail binaries. |
| pytools | Executes NumPy linear algebra and loads pip. Does not test pip installation; no passing sibling-only substitute demonstrated. |
| pyyaml | Parses YAML and checks the result. No substitute demonstrated. |
| gcc | Compiles and runs C. **Confirmed PASS with gcc module absent, rust alone present.** Does not cover all of build-essential, particularly C++ and make. |
| java | Compiles and runs Java. No substitute demonstrated. |
| rust | Compiles/runs Rust and loads Cargo. Does not exercise a Cargo build/dependency workflow. |
| llvm | Compiles an object with clang and reads symbols. No link/run test and no substitute demonstrated. |
| postgres | Presence/account/directory checks; **confirmed PASS with broken server executable**, M4. |
| mysql | Server version/account/directory ownership. Does not initialise a database, start the server or execute SQL. |
| docker | Daemon version, containerd/runc command presence and docker group. Does not start a daemon or container. |
| fake-nvidia-driver | Executes hello. Appropriate only to the explicitly artificial module-dependency experiment, not GPU functionality. |
| fake-cuda | Executable presence of sl. Does not execute sl or prove any CUDA functionality; dependency admission is tested separately. |
| pipdemo | Imports requests. Does not test a request or verify installation provenance. A concrete pytools-only substitution attempt **failed**, so I do not claim that sibling bypass. |
| control-oldsnap | Version printing only; expected to be rejected before normal composition. Not counted among usable-module probe executions. |
| curl | Real local file transfer with nonempty output. Does not exercise HTTP/TLS; no substitute demonstrated. |
| wget | Version only, explicitly weak. “No offline functional probe exists” is broader than necessary: local-server tests are possible, but were not run here. |
| git | Initialises, commits and reads a repository. No substitute demonstrated. |
| jq | Evaluates and checks a JSON expression. No substitute demonstrated. |
| rsync | Copies and compares data. **Confirmed PASS with rsync module absent, mysql alone present.** Already documented in spec. |
| tmux | Creates, lists and kills a real session, preserving failure status. The old unconditional success defect is absent. |
| htop | Version only, explicitly weak. Does not exercise its interactive process display. |
| socat | Moves and compares data using file endpoints. **Confirmed PASS with socat module absent, mysql alone present.** Does not test sockets. |
| zstd | Compression/decompression round trip. Real function tested, but repeat execution fails on existing output, L1. |
| sqlite | Creates a table, inserts and selects. No substitute demonstrated. |
| tcpdump | Version plus account existence. No capture/filter/privilege-drop path exercised. |
| dnsutils | Version and empty batch input. No DNS packet, response parsing or lookup exercised. |
| pgclient | Client version only. **Confirmed PASS with pgclient module absent, postgres alone present.** Known dependency overlap. |
| redis | Server version/account/directory ownership. Does not start a server or exercise commands/persistence. |
| memcached | Version and account existence. Does not start a server or exercise set/get. |

The five confirmed sibling-only passes are not new evidence of corrupt shared packages. They are a limit on what a high-N “all probes passed” result can attribute to individual modules. The current spec already documents these overlaps. Retain isolated-module testing alongside composed-system testing.

## Areas that were clean in this review

* **Actual debconf merging:** all fields agreed with an independently parsed expected union in every one of the 630 admitted pair compositions. No false-positive debconf conflict and no content loss were observed in that space.
* **Current bundle derivation:** stage 12 checked all 39 current manifests and artefact digests successfully. The new mounted-artefact extraction works on these inputs. H1 and M3 concern enforcement/coverage, not an observed mismatch in the originals.
* **Current numeric ownership:** no new class-7 rejection occurred in the 703-pair rerun. The earlier int/string catalogue-wide false positive did not recur. M2 is an injected inherited-account case and is caught later by reconciliation.
* **V7 on ordinary current pairs:** all 630 physically composed admitted pairs passed; there was no visibility false positive. Existing whiteout/device cases are outside this catalogue's built inputs and were not independently boot-tested here.
* **The rewritten vim/tmux/nullmailer separators:** the unconditional-success defect described in the journal is not in the current probes. Nullmailer remains explicitly a presence check.

## Reproduction appendices

Run from the reviewed repository root. These commands require passwordless root, loop/OverlayFS support and the existing host tools. They create new scratch under `/srv/modfs/build`; they never overwrite published CSVs or delete scratch. The read-only `.sqsh` files remain unchanged.

The embedded Appendix A cases and the Python commands in Appendices B–D were executed from this document before committing it. Their output is retained in `E/document-reproductions`.

### Appendix A — Reusable real-composition reproducer

Extract the marked Python block directly from this document and run one case, for example:

```sh
sed -n '/^# BEGIN REVIEW HARNESS$/,/^# END REVIEW HARNESS$/p' \
  docs/REVIEW_CODEX_2026-09-18.md | \
  sudo env PYTHONDONTWRITEBYTECODE=1 CASE=debconf python3 -
```

Cases: `baseline`, `debconf`, `symlink`, `shadow`, `postgres`, `zstd`, `auto`, `probe`, `replaces`. For a custom layer order set `SET='base mysql gawk'`. For sibling-only tests use e.g. `CASE=probe SET='base mysql' PROBE=gawk`. Each run prints and retains its scratch path. For each accepted CSV pair, `CASE=baseline SET="base <the two names>"` repeats the physical verification and independent debconf comparison; a driver can enumerate the 630 ACCEPT rows with `csv.DictReader`.

```python
# BEGIN REVIEW HARNESS
import json, os, subprocess, tempfile
from pathlib import Path
import yaml

repo = Path.cwd()
case = os.environ.get('CASE', 'baseline')
defaults = {
    'postgres': 'base postgres', 'zstd': 'base zstd',
    'auto': 'base rsync mysql', 'replaces': 'base',
}
names = os.environ.get('SET', defaults.get(
    case, 'base curl pyyaml postgres java zstd')).split()
moddir = Path(os.environ.get('ARTEFACT_DIR', '/srv/modfs/modules'))
root = Path(tempfile.mkdtemp(prefix='codex-reproduce-', dir='/srv/modfs/build'))
print('SCRATCH', root, flush=True)
mounts, layers = [], []
spec = {x['name']: x['probe'] for x in
        yaml.safe_load((repo / 'specs/modules.yaml').read_text())['modules']}

def command(args, check=True, **kwargs):
    p = subprocess.run([str(a) for a in args], text=True,
                       capture_output=True, **kwargs)
    if check and p.returncode:
        raise RuntimeError((args, p.returncode, p.stdout, p.stderr))
    return p

def mount(args, target):
    target.mkdir(parents=True, exist_ok=True)
    command(['mount', *args, target])
    mounts.append(target)

def chroot(*args, **kwargs):
    return command(['chroot', merged, *args], **kwargs)

def parse_debconf(path):
    if not path.exists():
        return {}
    records, fields, key = {}, {}, None
    for line in path.read_text().splitlines() + ['']:
        if not line:
            if fields:
                name = fields.pop('Name')
                assert name not in records, ('duplicate', name)
                if 'Owners' in fields:
                    fields['Owners'] = set(x.strip() for x in
                                          fields['Owners'].split(','))
                records[name], fields = fields, {}
        elif line[0].isspace():
            fields[key] += '\n' + line
        else:
            key, value = line.split(':', 1)
            fields[key] = value.lstrip(' ')
    return records

def independent_debconf():
    for leaf in ('config', 'templates', 'passwords'):
        rel = 'var/cache/debconf/' + leaf + '.dat'
        expected = {}
        for name in names:
            for rec, fields in parse_debconf(root / ('ro_' + name) / rel).items():
                dest = expected.setdefault(rec, {})
                for key, value in fields.items():
                    if key == 'Owners':
                        dest.setdefault(key, set()).update(value)
                    else:
                        assert key not in dest or dest[key] == value
                        dest[key] = value
        assert expected == parse_debconf(merged / rel), ('debconf differs', rel)

def verify(label):
    for filename, args in (
        ('actual.pkgs', ['dpkg-query', '-W', '-f', '${binary:Package}\t${Version}\n']),
        ('actual.ld', ['ldconfig', '-p']), ('audit.txt', ['dpkg', '--audit'])):
        p = chroot(*args)
        (root / filename).write_text(p.stdout + p.stderr)
    p = command(['python3', repo / 'scripts/verify_compose.py',
                 '--scripts', repo / 'scripts', '--merged', merged,
                 '--work', root, '--index', '1', '--n', str(len(names)-1),
                 '--admitted', 'yes', '--mount-ms', '0',
                 '--reconcile-ms', '0', '--total-ms', '0', *layers], check=False)
    (root / (label + '.log')).write_text(p.stdout + p.stderr)
    print(label, 'exit', p.returncode, p.stdout.strip(), p.stderr, flush=True)

def probe(name):
    shell = spec[name]
    if name == 'git':
        shell = 'rm() { [ "$*" = "-rf g" ] && [ ! -e g ]; }; ' + shell
    p = chroot('timeout', '45', 'sh', '-c', shell, check=False, input='')
    print('PROBE', name, p.returncode, p.stdout, p.stderr, flush=True)
    return p

try:
    for name in names:
        target = root / ('ro_' + name)
        mount(['-o', 'loop,ro', moddir / (name + '.sqsh')], target)
        layers.append(name + '=' + str(target))
    for directory in ('upper', 'work', 'merged'):
        (root / directory).mkdir()
    merged = root / 'merged'
    options = ('lowerdir=' + ':'.join(str(root / ('ro_' + n)) for n in names[::-1])
               + ',upperdir=' + str(root / 'upper')
               + ',workdir=' + str(root / 'work'))
    mount(['-t', 'overlay', 'overlay', '-o', options], merged)
    for directory in ('tmp', 'var/tmp', 'run/lock', 'proc', 'sys', 'dev'):
        (merged / directory).mkdir(parents=True, exist_ok=True)
    for directory in ('tmp', 'var/tmp', 'run/lock'):
        (merged / directory).chmod(0o1777)
    for args, directory in ((['-t', 'proc', 'proc'], 'proc'),
                            (['-t', 'sysfs', 'sysfs'], 'sys'),
                            (['--bind', '/dev'], 'dev'),
                            (['--bind', '/dev/pts'], 'dev/pts')):
        mount(args, merged / directory)
    p = command(['python3', repo / 'scripts/reconcile.py', '--merged', merged,
                 '--groups-out', root / 'groups', *layers])
    (root / 'reconcile.log').write_text(p.stdout + p.stderr)
    for group in (root / 'groups').read_text().split():
        chroot('update-alternatives', '--auto', group)
    chroot('ldconfig')
    independent_debconf()
    verify('baseline')
    if case == 'debconf':
        for leaf in ('config', 'templates'):
            p = merged / ('var/cache/debconf/' + leaf + '.dat')
            p.write_text('\n\n'.join(x for x in p.read_text().splitlines()
                                    if x.startswith('Name: ')) + '\n')
        verify('names-only')
        p = chroot('debconf-communicate', check=False, input='GET debconf/frontend\n')
        print('DEBCONF CLIENT', p.returncode, p.stdout, p.stderr)
    elif case == 'symlink':
        p = merged / 'usr/bin/python3'
        print('original target', os.readlink(p))
        p.unlink()                       # only the disposable overlay is changed
        p.symlink_to('no-such-python')
        verify('broken-symlink')
        p = chroot('python3', '-c', 'import yaml', check=False)
        print('PYTHON', p.returncode, p.stderr)
    elif case == 'shadow':
        p = merged / 'etc/shadow'
        print('original mode', oct(p.stat().st_mode & 0o7777))
        p.write_text('\n'.join(x.split(':')[0] + ':*'
                               for x in p.read_text().splitlines()) + '\n')
        p.chmod(0o644)
        verify('broken-shadow')
    elif case == 'postgres':
        p = merged / 'usr/lib/postgresql/14/bin/postgres'
        p.write_text('#!/bin/sh\nexit 99\n')
        probe('postgres')
        p = chroot('/usr/lib/postgresql/14/bin/postgres', '--version', check=False)
        print('SERVER', p.returncode)
    elif case == 'zstd':
        probe('zstd')
        probe('zstd')
    elif case == 'auto':
        for args in (['apt-mark', 'showauto', 'rsync'],
                     ['apt-mark', 'showmanual', 'rsync'],
                     ['apt-get', '-s', 'autoremove', 'mariadb-server']):
            p = chroot(*args)
            print(args, p.stdout, p.stderr)
    elif case == 'probe':
        probe(os.environ['PROBE'])
    elif case == 'replaces':
        for name in ('a', 'b'):
            package = root / ('package-' + name)
            (package / 'DEBIAN').mkdir(parents=True)
            payload = package / 'usr/share/review-replaces'
            payload.mkdir(parents=True)
            (payload / 'shared').write_text(name + '\n')
            (payload / ('keep-' + name)).write_text(name + '\n')
            (package / 'DEBIAN/control').write_text(
                'Package: review-' + name + '\nVersion: 1\nArchitecture: all\n'
                'Maintainer: Review <review@example.invalid>\nDescription: fixture\n'
                + ('Replaces: review-a\n' if name == 'b' else ''))
            deb = merged / ('tmp/' + name + '.deb')
            command(['dpkg-deb', '--build', package, deb])
            print(chroot('dpkg', '-i', '/tmp/' + name + '.deb').stdout)
        print(chroot('dpkg-query', '-W', '-f', '${Package} ${Status}\n',
                     'review-a', 'review-b').stdout)
        print('shared', (merged / 'usr/share/review-replaces/shared').read_text())
        print('audit', repr(chroot('dpkg', '--audit').stdout))
finally:
    for target in reversed(mounts):
        command(['umount', target])
# END REVIEW HARNESS
```

The harness calls the verifier directly so its `--admitted yes` is not itself an admission test. The real sets used for H2–H4/M1/M4 were separately admitted; the fabricated Replaces case deliberately compares policies. The arbitrary corruption is confined to writable composition upperdirs after a clean baseline, matching the failure-detection question being asked.

### Appendix B — Sidecar tampering without resealing

```sh
sudo python3 - <<'PY'
import json, os, shutil, subprocess, tempfile
from pathlib import Path
r = Path(tempfile.mkdtemp(prefix='review-binding-', dir='/srv/modfs/build'))
(r / 'modules').mkdir()
for name in ('base', 'curl', 'jq'):
    for suffix in ('.json', '.files.json.zst'):
        shutil.copy2('/srv/modfs/modules/' + name + suffix,
                     r / 'modules' / (name + suffix))
    (r / 'modules' / (name + '.sqsh')).symlink_to(
        '/srv/modfs/modules/' + name + '.sqsh')
env = dict(os.environ, MODFS_ROOT=str(r))
def check():
    p = subprocess.run(['scripts/05_check.sh', 'curl', 'jq'], env=env,
                       text=True, capture_output=True)
    print(p.returncode, p.stdout)
def bundle():
    p = subprocess.run(['bash', '-c',
        'source config.sh; source scripts/lib.sh; verify_bundle base curl jq'],
        env=env, text=True, capture_output=True)
    print('BUNDLE', p.returncode, p.stdout, p.stderr)
print(r)
check()
p = r / 'modules/curl.files.json.zst'
data = json.loads(subprocess.check_output(['zstd', '-dcq', str(p)]))
data['files']['/usr/bin/jq'] = 'curl'
subprocess.run(['zstd', '-q', '-f', '-o', str(p)],
               input=json.dumps(data).encode(), check=True)
check()
bundle()
p = r / 'modules/curl.json'
doc = json.loads(p.read_text())
del doc['binding']['sidecar_sha256']
p.write_text(json.dumps(doc))
bundle()
PY
```

### Appendix C — Inherited-account change with honest extraction

```sh
sudo env PYTHONDONTWRITEBYTECODE=1 python3 - <<'PY'
import os, shutil, subprocess, tempfile
from pathlib import Path
r = Path(tempfile.mkdtemp(prefix='review-account-', dir='/srv/modfs/build'))
(r / 'modules').mkdir()
for name in ('base', 'curl'):
    for suffix in ('.json', '.files.json.zst'):
        shutil.copy2('/srv/modfs/modules/' + name + suffix,
                     r / 'modules' / (name + suffix))
(r / 'modules/base.sqsh').symlink_to('/srv/modfs/modules/base.sqsh')
subprocess.run(['unsquashfs', '-no-progress', '-d', str(r / 'delta'),
                '/srv/modfs/modules/curl.sqsh'], check=True)
passwd = subprocess.check_output(['unsquashfs', '-cat',
    '/srv/modfs/modules/base.sqsh', 'etc/passwd']).decode()
out = []
for line in passwd.splitlines():
    fields = line.split(':')
    if fields[0] == '_apt':
        fields[2] = '0'
    out.append(':'.join(fields))
(r / 'delta/etc/passwd').write_text('\n'.join(out) + '\n')
subprocess.run(['mksquashfs', str(r / 'delta'), str(r / 'modules/curl.sqsh'),
               '-noappend', '-comp', 'zstd', '-no-progress', '-processors', '2'],
               check=True)
env = dict(os.environ, MODFS_ROOT=str(r))
for args in (['scripts/06_extract_metadata.sh', 'curl', '--version', '1.0'],
             ['scripts/05_check.sh', 'curl'],
             ['scripts/12_verify_binding.sh', 'curl']):
    p = subprocess.run(args, env=env)
    print(args, 'exit', p.returncode)
print('ARTEFACT_DIR=' + str(r / 'modules'))
PY
```

To confirm containment, run Appendix A with the printed `ARTEFACT_DIR`, `SET='base curl'`, `CASE=baseline`. Its checked reconcile invocation must fail with the inherited UID mismatch, before reporting a baseline verification.

### Appendix D — Recover the numeric claims

```sh
python3 - <<'PY'
import csv, statistics
from pathlib import Path
r = Path('/srv/modfs/modules')
base = (r / 'base.sqsh').stat().st_size
large = {'gcc', 'java', 'rust', 'llvm', 'postgres', 'mysql', 'docker'}
names = {p.stem for p in r.glob('*.json')} - {'base'}
for label, cohort in [('small', names-large), ('large', large), ('all', names)]:
    delta = sum((r / (n + '.sqsh')).stat().st_size for n in cohort)
    stored, model = base + delta, len(cohort)*base + delta
    print(label, len(cohort), stored, model, model/stored)
for n in ('curl', 'jq', 'nc-traditional', 'webserver', 'pytools', 'emacs'):
    measured = (r / (n + '-monolithic.sqsh')).stat().st_size
    model = base + (r / (n + '.sqsh')).stat().st_size
    print(n, 100*(model/measured - 1))
for path in (
 '/srv/modfs/results/tier2/compose-sweep-2026-09-18-pre-round2.csv',
 '/srv/modfs/logs/compose-sweep.csv'):
    rows = list(csv.DictReader(open(path)))
    assert len(rows) == 152 and all(x['result'] == 'PASS' for x in rows)
    assert all(int(x['total_ms']) == int(x['mount_ms']) + int(x['reconcile_ms'])
               for x in rows)
    for column in ('total_ms', 'mount_ms', 'reconcile_ms'):
        xs = [int(x['n']) for x in rows]
        ys = [int(x[column]) for x in rows]
        mx, my = statistics.mean(xs), statistics.mean(ys)
        slope = sum((x-mx)*(y-my) for x,y in zip(xs,ys))/sum((x-mx)**2 for x in xs)
        intercept = my-slope*mx
        r2 = 1-sum((y-intercept-slope*x)**2 for x,y in zip(xs,ys))/sum((y-my)**2 for y in ys)
        print(path, column, intercept, slope, r2)
PY
```

## What I could not verify, and why

* **Fresh tier-3 behaviour:** I did not launch a new QEMU boot. I inspected existing result/serial evidence, including the 18 September 36-probe boot, whose overall result is FAIL and whose probes all report PASS. This review concentrated execution on the new extract/check/reconcile/verify path and isolated probes. Existing boot outcomes are historical evidence, not a fresh validation of this commit under every service interaction.
* **Complete service health:** version, presence and configuration probes do not supply it. I did not exercise SQL transactions, mail delivery, container execution, TCP capture, DNS queries or all workload paths. The isolated smoke successes must not be described as that coverage.
* **Every order/permutation:** I checked two real gawk/mysql orders and inspected the documented reverse-order boot bundles. I did not enumerate permutations of high-N sets or independently prove order independence for conflicting account/debconf inputs. The broad claim remains unjustified; the reported pair-specific observations are reproducible.
* **Byte reproducibility of builds:** no independent double build or cross-host build was performed. Current hashes differ from the historical table, but that alone is not a failed reproducibility experiment.
* **Equivalent monolithic systems and fat-base conclusions:** I recovered sizes/calibration and inspected retained fat-base results, but did not compare every installed file/configuration or rebuild those baselines. In particular, the six small-module calibrations do not prove less-than-1% model error for all seven large modules.
* **Full end-to-end tier-2 latency:** the published columns exclude observations, verification, admission and teardown. I recovered the stated composition fits, not a fit for a complete verified provisioning operation. My 630-pair run deliberately amortised lower mounts and cannot fill that gap.
* **Hostile bundle authenticity/exact parent generation:** signatures are explicitly out of scope. A delta still names its parent rather than carrying an independently enforced exact parent-generation digest. I did not execute a changed-parent-generation experiment, so I report this as an unverified residual boundary, not a confirmed exploit.
* **Whiteouts, opaque replacement, trigger correctness, dynamic identities, all special node types, interrupted publication and signal failure paths:** these were not independently exercised here. Several are already explicit architecture limitations. Clean ordinary pairs do not close them.
