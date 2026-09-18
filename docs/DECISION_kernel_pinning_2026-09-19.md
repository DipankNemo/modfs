# Decision requested: should a kernel be pinned into base?

**19 September 2026. Recommendation: NO — and there is a cheaper way to get the
thing pinning was wanted for.** Deadline is 29 September; this is your call
because it changes every artefact.

---

## 1. What pinning was supposed to buy

A driver module is **ABI-pinned**. `nvidia-driver-535` installs
`linux-objects-nvidia-535-5.15.0-185-generic` — the kernel ABI is *in the
package name* — and the five `.ko` files it links carry
`vermagic=5.15.0-185-generic`. It is valid against exactly one kernel.

That kernel is not a module: `11_boot_test.sh` installs it at pack time, into
the image only. So the constraint is real and load-bearing, and **neither layer
of the dependency model can state it**. Package relations can't (apt only ever
sees one module's build). Module-level `requires` can't (it resolves against
modules in the set, and the kernel is never one).

Pinning a kernel into base would make the ABI a property of `base.json`, and
then `05_check.sh` could reject a driver/kernel mismatch statically, at tier 1,
on every composition — instead of it surfacing at boot, or not at all.

That is a genuine benefit. It is the only one.

## 2. What it costs — measured, not estimated

### 2a. Storage depends entirely on *which* kernel you pin, and the two answers differ by 12×

Resolved against the pinned snapshot `20260701T000000Z`:

| Option | What you install | Packages | Installed | Stored (est. at base's 2.9×) |
|---|---|---:|---:|---:|
| **A** | `linux-image-generic` + `initramfs-tools` — what stage 11 installs today | 20 | **1 582.5 MB** | ~550 MB |
| **B** | `linux-image-5.15.0-185-generic` + `linux-modules-…` directly, skipping the meta | 13 | **135.5 MB** | ~47 MB |

The brief's figure of "~45 MB stored" is accurate — **for option B only**.
Option A is twelve times that, because `linux-image-generic` hard-depends on
`linux-firmware` (1 089.8 MB on its own), `linux-modules-extra` (336.4 MB) and
both microcode packages. `--no-install-recommends` cannot avoid them; the
JOURNAL entry of 16 September already recorded this and it still holds.

Option B also is not free of consequences: dropping `linux-firmware` means the
image has no device firmware, which is fine under QEMU (virtio needs none) and
is a real narrowing on physical hardware.

### 2b. The rebuild invalidates the evidence, not just the artefacts

Base plus 40 siblings, **plus the six monolithic `--compare` baselines** — and
those are not optional. The 18 September entry records exactly this trap:
`08 --force` does *not* rebuild the monoliths, so a storage comparison would
measure a fresh base against stale ones. Roughly 1–2 hours of build time, and
then:

- every artefact hash in ARCHITECTURE §7 and JOURNAL is superseded
- all three cohort ratios must be re-measured
- the tier-1 counts (10 660 combinations) must be re-run
- the tier-2 fit must be re-fitted, as a **fourth** measurement generation
- every boot bundle in `results/boot/` describes a base that no longer exists

Ten days out, with an evidence set that is currently coherent and cross-checked.

### 2c. It changes what base means

Base is currently flavour-neutral. Pinning a kernel commits every sibling in
the catalogue to one ABI, and adds class-6 surface: a kernel in base is a
package modules inherit and could implicitly upgrade.

### 2d. The headline ratio would *improve*, and that is a reason for suspicion

With B = 41.7 → ~88.7 MB, the whole-catalogue ratio goes **1.84× → ~2.74×**,
because the monolithic column is `N·B + Σd` and every one of the 40 hypothetical
images now carries a kernel.

Do not take that number. Today the kernel is fetched from the mirror at pack
time and stored **zero** times in either column, so the omission is neutral.
Pinning moves it to "stored once in base" — a relocation, not a saving — while
inflating the baseline 40×. It would make the ratio look better by changing
what is being compared. (The related question of whether the monolithic
baseline is equivalent at all is audit finding **H9**, and it is still open.)

## 3. Why it is not necessary

**The ABI is a deterministic function of the pinned snapshot**, so recording it
does not require installing it. That is now demonstrated end to end rather than
argued:

```
snapshot index predicts   linux-image-generic  5.15.0.185.166  (meta)
                       →  ABI                  5.15.0-185-generic
                       →  ABI package          5.15.0-185.195
pack step resolved        5.15.0-185-generic / 5.15.0-185.195
booted guest reported     Ubuntu 5.15.0-185.195-generic
.ko vermagic              5.15.0-185-generic
```

Four independent points, one answer. Pinning would buy determinism the pin
already provides.

## 4. Recommendation

**Do not pin.** Instead, two cheap changes that buy the same check for ~0 MB and
no rebuild. **Both are new features, not fixes — I have not built either:**

1. **Record the resolved ABI in `base.json` as a derived field.**
   `06_extract_metadata.sh` can compute it from the snapshot indices without
   installing anything. Cost: regenerate 41 manifests (`08 --refresh-metadata`,
   about a minute), not a rebuild. If it should be *sealed*, it goes into
   `BIND_FIELDS`, which invalidates existing manifests until regenerated — same
   minute, but say so out loud.

2. **Let `05_check.sh` compare a module's declared ABI against it**, so a
   driver/kernel mismatch is a tier-1 REJECT with a reason, rather than a
   surprise at boot or a silent pass.

If you want either, say so and I will build them. If you would rather spend the
remaining days on writing, the current state is defensible as it stands: the
ABI is recorded in every run bundle, the match is verified in the one boot that
matters, and the limitation is documented in ARCHITECTURE §5.

## 5. If you decide to pin anyway

Pin **option B** (`linux-image-<abi>` + `linux-modules-<abi>` directly), not the
meta package. Budget 2 h of building plus a full re-measurement pass, rebuild
the six monolithic baselines in the same generation, and report the resulting
ratio as a **new baseline definition** rather than as an improvement on 1.84×.
