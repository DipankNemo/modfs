# Sampling and the boot pipeline

**Chapter: Implementation (methodology)**

Two mechanisms that neither `REGISTRY_FORMATS.md` nor `DATA_MODEL.md` covers:
how tier 2 decides *which* module sets to compose, and how a composed tree
becomes a machine that boots.

---

# Part 1 — Choosing what to compose

## The problem

Tier 1 is a **census**: it checks every pair and every triple. C(40,2) = 780 and
C(40,3) = 9,880, so "all of them" is 10,660 checks and entirely affordable,
because tier 1 reads manifests and mounts nothing.

Tier 2 cannot do that. It mounts every layer, reconciles, verifies and tears
down. Composing every set of size 10 from 40 modules would be 847 million
compositions. So tier 2 **samples**: it composes a chosen subset and the choice
has to be defensible.

## Why a uniform random draw is the wrong tool

Most random sets are not admissible. The sampler's own measurements:

```
N=2    94.6 % of uniform draws admissible
N=27   38.1 %
```

At high N, nearly two in three draws are sets tier 1 rejects — so the sweep
spends its time building nothing. Worse, the failures are not random: they
cluster on whichever modules carry constraints, so the sets that *do* get built
are systematically the ones with least to say.

`sample_sets.py` therefore makes the draw **constraint-aware**. It models what is
admissible and proposes only sets it believes will pass.

## The model proposes, tier 1 still decides

This separation is the important design point. The sampler is a heuristic for
*choosing*; it is never the authority on *admissibility*. Every proposed set
still goes through `05_check.sh`, and a set the model believed admissible that
tier 1 rejects is recorded as a refusal rather than quietly dropped — because
that disagreement is itself a finding about the model.

## Exclusions are measured, not declared

The sampler can read a real tier-1 pair sweep (`--pairs`). Exclusions then come
from **what the sweep observed**, not from what anyone wrote in `modules.yaml`.
A conflict nobody declared is still learned. Without `--pairs` the model knows
only the declared relations, which for this catalogue misses the
mail-transport-agent pair entirely.

## Why a rejection is not an exclusion edge

The subtle part. A tier-1 rejection of `{a, b}` can mean two different things:

1. **a and b genuinely cannot coexist** — a real pairwise conflict.
2. **a has an unsatisfied module-level requirement** that b does not supply — a
   property of `a` alone, which happens to surface when it is paired with b.

Treating every rejection as a symmetric exclusion edge conflates them, and the
consequence is concrete: `fake-cuda` is rejected against 38 of 39 siblings, yet
it **belongs in the largest admitted set**. Treated as an exclusion edge it would
be banished from every high-N sample — removing exactly the module most worth
including. So module-level relations are resolved structurally and used to
*explain* rejections; only the unexplained residue becomes an exclusion.

## Two sampling modes, and why the output says which

The method changes what a sample *means*, so it is reported per plan point:

| Mode | When | What it gives |
|---|---|---|
| `exact` | the admissible space, or its complement, is small enough to enumerate (≤ 200,000 combinations) | sets drawn **uniformly from all admissible sets**; the count is exact |
| `sampled` | the space is too large to enumerate | a seeded, closure-aware greedy draw — **reproducible but not uniform** over admissible sets |

`exact` covers the top of the range, where the complement is tiny: at N=36 of 37
there are exactly **2** admissible sets, and a plan asking for 5 must say so
rather than spin forever looking for a third.

Stating `sampled` is not uniform, rather than glossing it, is the honest choice:
a reader can then judge what the resulting distribution supports.

## The census that rotted into a sample

The best methodology lesson in the project, and it is a one-line bug.

The tier-2 plan said **`27:1`** — draw one set of size 27. When it was written the
catalogue held exactly **27 usable modules**, so "one set of 27" meant *all of
them*: a complete enumeration, deterministic and repeatable.

The catalogue then grew to 37. The plan string never moved. The same constant now
means "one arbitrary draw from C(37,27) possibilities", of which only **38%** are
admissible.

**A constant that encoded a fact about the population silently changed meaning
when the population changed**, and nothing detected it because the constant was
still perfectly valid syntax producing perfectly plausible output. The published
claim had quietly degraded from "we composed every usable module" to "we composed
one arbitrary subset", with no line of code edited.

---

# Part 2 — From composed tree to booting machine

`11_boot_test.sh` is tier 3. Six stages.

## 0. Admission first, always

`verify_bundle` checks every artefact digest against its manifest, then tier 1
runs. A set that tier 1 rejects is **not composed**, unless it was explicitly
declared a known negative.

This ordering was learned: an early run composed a tier-1-rejected set anyway and
died inside APT, producing a failure that looked like a system defect and was a
harness defect. A deliberate negative must say so with `--known-negative` and is
never labelled "admitted".

## 1. Compose

Mount each `.sqsh` read-only, stack them as OverlayFS lowerdirs, reconcile the
registries, regenerate the derived state. This is the same composition tier 2
verifies — tier 3 adds nothing to it, which is the point: the thing being booted
is the thing that was verified.

## 2. Kernel — into the image only, never into a module

**No module contains a kernel.** The kernel is boot scaffolding, installed into
the disk image at pack time.

That separation is deliberate and load-bearing. A module is a *delta of
userspace*; making one carry a kernel would tie it to one ABI and break the claim
that modules compose freely. The resolved ABI is recorded in every run bundle's
`result.json` — package name, version, and the `vmlinuz` digest — so the boot is
reproducible even though the kernel is not part of any artefact.

The apt scratch left by installing the kernel is then dropped: 709 MB was
shipping into every image before anyone noticed.

## 3. In-guest harness

A small service is written into the image. Once systemd settles it reports
`MODFS`-prefixed lines on the serial console: systemd state, remaining jobs,
failed units, `dpkg --audit`, every per-module probe, and listening sockets.

Two failures worth recording:

- **The observer was the job.** The harness waited for `systemctl is-system-running
  --wait`, a steady state its own queued job prevented from ever arriving. It
  could not have succeeded at any timeout. It now counts *foreign* jobs, excluding
  itself.
- **A passing probe could not speak.** Probe output was captured and printed only
  on failure, so a probe could report nothing it merely *observed*. Lines prefixed
  `MODFS-` now pass through regardless of verdict.

## 4. Pack a UEFI disk

`sgdisk` writes a GPT with a 128 MB ESP (`ef00`) and an ext4 root labelled
`modfsroot`; `losetup -P` exposes the partitions; the composed tree is rsynced in;
runtime mountpoints the artefacts deliberately exclude are recreated.

Three things that had to be learned:

- **Partition nodes appear asynchronously.** `[ -e ${LOOPDEV}p1 ]` can succeed a
  moment before the kernel will let anything open it. With three squashfs loop
  mounts held and 36 snap loop devices on the host, the window is wide enough to
  hit. The script waits for partitions to be *usable*, not merely present.
- **The image was a fixed 3072 MB.** That fitted every set until the 24.04 GPU
  stack, where rsync died with ENOSPC while the host had 38 GB free. The image is
  now sized from the content it must hold.
- **`/etc/fstab` must name the root.** Without it systemd waits 90 seconds for a
  filesystem entry that does not exist.

## 5. Boot and judge

QEMU with OVMF firmware, KVM where available, serial to a log. The run is judged
from that log, and the whole bundle — `result.json`, `serial.log`, `kernel.json`,
probe output — is written to `results/boot/<run>/` and **never overwritten**.

Bundles are immutable because the boot history includes runs where the harness
was the failure, and deleting those would leave a record showing only the
occasions the instrument happened to work.

A bundle also records whether the artefacts it describes still exist unchanged.
Rebuild a module and every bundle mentioning it is marked **superseded**: retained
as history, not offered as current evidence.
