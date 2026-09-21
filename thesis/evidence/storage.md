# Storage — the delta model against a monolithic baseline

**Chapter: Evaluation**

## S1 Cohort ratios, computed from the artefacts on disk

_Unit: **decimal MB (10⁶)**, which is what every published figure uses; `mksquashfs` and `lib.sh`'s `human()` print binary MiB under the same label, a 4.9 % difference._

_ratio = (N·B + Σd) / (B + Σd), B = 41.7 MB. It tends to N as deltas shrink and to 1 as they grow._

_**Catalogue: 40 modules** · measured 2026-09-18 22:58:43Z · source `/srv/modfs/modules`_

| cohort | N | stored MB | monolithic MB | ratio | mean delta MB |
|---|---:|---:|---:|---:|---:|
| small adversarial | 31 | 272.8 | 1524.3 | 5.59× | 7.5 |
| large realistic | 9 | 1704.5 | 2038.3 | 1.20× | 184.8 |
| whole catalogue | 40 | 1935.6 | 3562.5 | 1.84× | 47.3 |

## S2 Is the `B + d` monolithic model honest?

_The monolithic column above is MODELLED as `B + d` for every module. Only 6 of 40 have a real monolithic build to check it against. Across those 6 the model comes in 0.25–0.95 % HIGH, because squashfs compresses one whole tree slightly better than a base and a delta compressed separately — so the model mildly OVERSTATES the saving._

| module | measured MB | modelled MB | model error | built |
|---|---:|---:|---:|---|
| curl | 43.0 | 43.4 | +0.91 % | 2026-09-16 15:10:06Z |
| emacs | 78.3 | 78.7 | +0.51 % | 2026-09-16 15:33:05Z |
| jq | 41.9 | 42.3 | +0.95 % | 2026-09-16 15:19:27Z |
| nc-traditional | 41.6 | 42.0 | +0.95 % | 2026-09-16 15:22:59Z |
| pytools | 67.4 | 67.6 | +0.25 % | 2026-09-16 15:30:17Z |
| webserver | 62.3 | 62.8 | +0.82 % | 2026-09-16 15:26:28Z |

**The whole-catalogue monolithic column is therefore 34 modelled figures and 6 measured ones, not 40 rebuilt baselines.** Any sentence calling the whole-catalogue baseline "rebuilt like-for-like" is wrong; the SIX are rebuilt like-for-like and they calibrate the rest.

## S3 Per-module saving against its own monolithic image

_`1 − d/(B+d)`. The thinner the module, the more the delta model wins; a module much larger than the base shares nothing to amortise._

_**Catalogue: 40 modules** · measured 2026-09-18 22:58:43Z · source `/srv/modfs/modules`_

| module | kind | delta MB | monolithic MB | saving |
|---|---|---:|---:|---:|
| cuda-runtime | real | 680.2 | 721.9 | 5.8 % |
| nvidia-driver-535 | real | 231.6 | 273.3 | 15.3 % |
| rust | real | 175.5 | 217.2 | 19.2 % |
| java | real | 141.6 | 183.3 | 22.8 % |
| llvm | real | 128.2 | 169.9 | 24.6 % |
| gcc | real | 84.0 | 125.7 | 33.2 % |
| docker | real | 83.1 | 124.8 | 33.4 % |
| postgres | real | 82.1 | 123.9 | 33.7 % |
| mysql | real | 56.6 | 98.3 | 42.4 % |
| emacs | real | 37.0 | 78.7 | 53.0 % |
| apache | real | 28.1 | 69.8 | 59.7 % |
| pytools | real | 25.8 | 67.6 | 61.7 % |
| webserver | real | 21.0 | 62.8 | 66.5 % |
| vim | real | 18.1 | 59.8 | 69.7 % |
| git | real | 17.1 | 58.9 | 70.9 % |
| dnsutils | real | 16.0 | 57.7 | 72.3 % |
| pipdemo | synthetic | 15.5 | 57.2 | 72.9 % |
| pgclient | real | 12.1 | 53.8 | 77.6 % |
| memcached | real | 10.3 | 52.0 | 80.3 % |
| pyyaml | real | 10.1 | 51.9 | 80.4 % |
| gawk | real | 3.1 | 44.8 | 93.1 % |
| mta-msmtp | real | 2.6 | 44.3 | 94.2 % |
| sqlite | real | 1.9 | 43.6 | 95.6 % |
| redis | real | 1.7 | 43.4 | 96.2 % |
| control-oldsnap | control | 1.6 | 43.4 | 96.2 % |
| curl | real | 1.6 | 43.4 | 96.2 % |
| tcpdump | real | 1.1 | 42.8 | 97.5 % |
| zstd | real | 0.9 | 42.6 | 98.0 % |
| tmux | real | 0.7 | 42.5 | 98.2 % |
| rsync | real | 0.7 | 42.4 | 98.4 % |
| socat | real | 0.6 | 42.3 | 98.5 % |
| wget | real | 0.6 | 42.3 | 98.6 % |
| jq | real | 0.6 | 42.3 | 98.7 % |
| mta-nullmailer | real | 0.5 | 42.2 | 98.9 % |
| htop | real | 0.4 | 42.1 | 99.1 % |
| nc-openbsd | real | 0.3 | 42.0 | 99.3 % |
| original-awk | real | 0.3 | 42.0 | 99.3 % |
| nc-traditional | real | 0.3 | 42.0 | 99.4 % |
| fake-nvidia-driver | synthetic | 0.2 | 41.9 | 99.5 % |
| fake-cuda | synthetic | 0.2 | 41.9 | 99.5 % |

## S4 Sensitivity — the headline ratio is a property of the catalogue, not only of the method

_Each row removes one cohort from the whole-catalogue figure and recomputes. The spread between these rows is the answer to "why does the published ratio keep changing"._

| catalogue | N | stored MB | monolithic MB | ratio | mean delta MB |
|---|---:|---:|---:|---:|---:|
| all 40 modules (headline) | 40 | 1935.6 | 3562.5 | 1.84× | 47.3 |
| minus large realistic (31 left) | 31 | 272.8 | 1524.3 | 5.59× | 7.5 |
| minus control + synthetic (36 left) | 36 | 1918.0 | 3378.1 | 1.76× | 52.1 |
| minus cuda-runtime alone (39 left) | 39 | 1255.3 | 2840.6 | 2.26× | 31.1 |
| minus nvidia-driver-535 alone (39 left) | 39 | 1704.0 | 3289.3 | 1.93× | 42.6 |
| minus rust alone (39 left) | 39 | 1760.1 | 3345.4 | 1.90× | 44.1 |

## S5 Every published storage figure, recomputed from the artefacts on disk today

_Same formula in every row: `(N.B + Sd) / (B + Sd)`, decimal MB. The only things that differ between the published figures are WHICH modules were in the catalogue and whether the x0.993 monolithic calibration was applied. A row that reproduces shows the published number was right FOR ITS CATALOGUE: the catalogue moved, not the method._

| document | section | catalogue as described | as published | N today | recomputed today | verdict |
|---|---|---|---|---|---|---|
| docs/STATE_OF_PLAY_2026-09-18.md | 6 | 38 modules, 2026-09-16 | 5.59x / 1.32x / 2.51x | 38 | 5.59x / 1.32x / 2.51x | reproduces |
| ARCHITECTURE.md | 7 "Storage depends on the catalogue" | 38 modules, 2026-09-16 | 5.59x / 1.32x / 2.51x | 38 | 5.59x / 1.32x / 2.51x | reproduces |
| ARCHITECTURE.md | 7 re-measure block | 40 modules, 2026-09-19 | 5.59x / 1.20x / 1.84x | 40 | 5.59x / 1.20x / 1.84x | reproduces |
| thesis/PLAN.md | ch. 6 list | 40 modules | 5.59x / 1.20x / 1.84x | 40 | 5.59x / 1.20x / 1.84x | reproduces |
| docs/REASSESSMENT_2026-09-10.md | 8.2 | 37 modules, 2026-09-10 | 2.47x whole | - | - | NOT REPRODUCIBLE: that generation was overwritten by the 2026-09-16 full rebuild |
