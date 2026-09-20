# Independent remote verification — 2026-09-20

**40/40 catalogue builds succeeded; 0/40 module archives were byte-identical
to the original machine.** The base also differed. The small remote tier-3
boot passed with explicit TCG. A CUDA kernel compiled and ran on the real GPU
using the rebuilt runtime libraries and the provider's driver. Loading the
ModFS NVIDIA 535 kernel module remains untested.

## What was actually tested

| Environment | Observed configuration |
|---|---|
| Original reference machine | Ubuntu 24.04.5; existing `/srv/modfs/modules` read only |
| Supplied remote endpoint | Vast.ai unprivileged Docker, Ubuntu 24.04.4, host kernel `6.8.0-47-generic`, RTX **3060 12 GB**, driver **550.107.02** |
| Build environment on that remote | Ubuntu 22.04.5 QEMU/TCG VM, kernel `5.15.0-191-generic`, 8 GiB RAM, 60 GiB virtual disk |
| ModFS boot-test guest | Packed kernel `5.15.0-185-generic`, base + webserver, 2 GiB RAM, explicit TCG |

The endpoint differs from the supplied Ubuntu 22.04 / 3060 Ti 8 GB brief.
Its container cannot mount OverlayFS or loop devices. A software VM provided
those privileges without changing the provider host or passing through its GPU.
All builds ran on the remote instance. Both remote source checkouts were cloned
from GitHub origin and stayed clean at
`a69111baedb576ea9d093626e883b6f7cd5bd3ce`. No dirty source tree was transferred.
Measurement helpers were separate from the measured clone.

The reference manifests were **not in the Git clone**. They were exported
read-only from the original machine and their recorded hashes independently
checked against its 41 existing archives. They are preserved here. The July
snapshot matches the reference, including the catalogue's intentional April
`control-oldsnap` exception. This is not a controlled hardware-only comparison:
the builder changed from `base.dir` to exact `base.sqsh` in `5bd645c`, jq gained
moreutils, and host tools/build dates differ. These confounds are not hidden
or removed from the reported count.

## Bootstrap portability result

Before any installation, container `00_verify.sh` reported these **six missing
tools**: **debootstrap, mksquashfs, unsquashfs, sgdisk, getfattr, qemu-img**.
Result: 14 passes, 7 failures (six tools plus mount denial). Installing exactly
its suggested apt line produced 20 passes, one mount failure.

The fresh Jammy VM separately reported **debootstrap, getfattr, qemu-img**
missing. Its preinstalled SquashFS 4.5 lacked `-xattrs-exclude`; the checker
only checked executable presence and hid the decisive mksquashfs error.
The suggested apt line left that incompatible version installed. Building
upstream SquashFS 4.6.1 made filesystem checks work, leaving **31 passes,
one failure**: the checker's obsolete expectation that the opaque marker
survives, contrary to current config.

**The suggested apt line was insufficient.** It also omitted
`qemu-system-x86` (actually reproduced as stage-11 preflight failure),
`dosfstools` for mkfs.vfat, and OVMF firmware. The container additionally needed
a privileged build environment; apt packages cannot supply missing host
capabilities. [README.md](README.md) gives the exact installs and VM setup.

## Byte comparison and mechanisms

[cross-machine-comparison.csv](cross-machine-comparison.csv) lists all 41
archive pairs, hashes, sizes and difference counts. Stage 12 independently
passed: **41 manifests bound to their artifacts, 41 stored hashes matched**.
That internal consistency does not imply cross-machine byte equality.

Every module differs at the same three retained xattrs:
`trusted.overlay.impure=y` exists only in the original at `var/cache/apt`,
`var/lib/apt`, and `var/log/apt`. `impure_fixture.sh` reproduces all three on
one remote kernel: copying up pre-existing apt entries marks their parent;
creating entries absent from the filtered lower layer does not. This matches
the documented builder change and exclusions. The kernel's
[copy-up implementation](https://github.com/torvalds/linux/blob/v5.15/fs/overlayfs/copy_up.c)
marks the parent during copy-up. The fixtures never rewrite measured archives.

| Cohort | Additional measured differences and mechanism |
|---|---|
| 28 modules | No other decompressed inode/content differences: apache, control-oldsnap, cuda-runtime, curl, dnsutils, docker, fake-cuda, fake-nvidia-driver, gawk, gcc, git, htop, nc-openbsd, nc-traditional, nvidia-driver-535, original-awk, pgclient, pytools, pyyaml, rsync, rust, socat, sqlite, tmux, vim, webserver, wget, zstd. |
| jq | Specification changed from jq alone to jq + moreutils. A separately labelled jq-only rebuild has just the common three-xattr difference; its archive still differs. It does not replace the catalogue row. |
| memcached, mta-msmtp, redis, tcpdump | Only additional differences are `/etc/shadow` and its backup: password-change days differ; all other fields agree. |
| mta-nullmailer | `hostname --fqdn` in the package config embeds `ketchup` versus `modfs-verification` in `/etc/mailname` and debconf state. |
| llvm | Older debootstrap creates base `/lib32` as a symlink. Nineteen unchanged inode records therefore move from `lib32/` to `usr/lib32/`; the loader cache changes accordingly. |
| emacs | Only line ordering differs in `usr/share/info/dir{,.old}`. Package update script scans with unsorted `find`. Reversing input order in `info_order_fixture.sh` exactly reproduces the two saved `dir.old` hashes; C versus C.UTF-8 does not change the fixture result. |
| java | JKS contains the same 120 public certificates but different creation timestamps. The postinst runs `java -Xshare:dump`, generating a process-dependent CDS archive. Two diagnostic dumps on the same remote VM also differ; see `java-cds-fixture.log`. |
| mysql | Shadow dates plus 166 initialized MariaDB state files differ. The postinst explicitly runs mysql_install_db. A sampled view differs only in its creation timestamp. Aria's control UUID encodes different build times and node IDs; the remote node matches its NIC `52:54:00:12:34:56`. |
| postgres | Shadow dates, a newly generated snakeoil certificate/key and certificate-name link, and initialized pg_control/WAL differ. Public certificate subject/date/serial and cluster system identifiers differ. No private key material is published. |
| pipdemo | Unpinned PyPI resolves idna 3.19 versus 3.20. Of 82 changed pyc files, 77 have identical marshalled payloads and changed timestamp headers; five track changed idna code. Five Python source files also differ. |

The base contains the same 113 package records. Older debootstrap creates four
additional multilib paths and doubles the exported component list, causing
`var/lib/dpkg/available` to be literally concatenated twice. Shadow dates
also differ. `component-duplication-*.log` executes the installed bootstrap
functions on the same synthetic Release input and reproduces the duplication.

All these differences are observed in read-only inventories, selected content
probes, retained package scripts, or isolated fixtures. Exact contributions
from host libzstd 1.4.8 versus 1.5.5 to compressed sizes were not isolated.
The CDS archive's individual varying memory fields and every database byte
were not decoded. The findings identify byte-affecting mechanisms, not a
complete attribution of every changed byte. No normalization was used.

The [MariaDB control-file implementation](https://github.com/MariaDB/server/blob/10.6/storage/maria/ma_control_file.c)
places the generated UUID at offset 4, matching `mysql-uuid-diagnosis.json`.
The [OpenJDK archive layout](https://github.com/openjdk/jdk11u/blob/master/src/hotspot/share/memory/filemap.hpp)
includes memory addresses and heap settings; the two same-VM CDS dumps prove
variation without requiring another machine. They are diagnostic outputs,
not replacements for the archived java module.

## GPU and boot results

`cuda_runtime_probe.py` used the remote module's NVRTC 11.5 and libcudart,
compiled for compute_86, launched 32 threads, and read back exactly 7–38.
`gpu-runtime-result.json` records PASS and actual mapped libraries;
`gpu-library-binding.json` verifies all three compiler/runtime library hashes
against the remote artifact inventory. Driver library: provider 550.107.02.

The 535 artifact's nvidia.ko reports vermagic `5.15.0-185-generic`; the provider
host is `6.8.0-47-generic`. Stage 11 successfully obtained the pinned 185.195
kernel packages, establishing snapshot availability. Installing that kernel
inside a container cannot change its shared host kernel. The provider forbids
host kernel/driver changes and required capabilities are absent. An owned
bootable host/VM and approval before kernel installation/reboot are needed
for the remaining **535-driver-on-real-GPU** test. No insmod, provider reboot,
kernel replacement or passthrough was attempted.

The original unmodified stage-11 invocation packed the image but selected KVM
inside the software VM and returned BROKEN with empty serial output. Its
QEMU exit was 0; the exact KVM failure mechanism is not established.
`run_tcg_retry.sh` copied that packed image and its OVMF firmware to the outer
container and reran the launcher explicitly with TCG, using the **unchanged
stage-11 verdict parser and guest harness**. It passed in 21 seconds:
nginx active, audit PASS, webserver PASS, zero failed units, clean poweroff.
Both complete run bundles are retained. This is a small-set tier-3 result,
not a claim that the original stage-11 invocation passed or all 40 modules boot.

## Reproduce and audit

[README.md](README.md) contains remote setup and commands. Run
`python3 verify_evidence.py` here to independently recompute the 41-row
comparison from retained manifests/inventories and validate GPU library
binding and the boot parser. `content_probe.py`, `impure_fixture.sh`,
`info_order_fixture.sh`, and `cds_fixture.sh` reproduce the diagnoses.

Base built in 846.31 seconds; the complete module sequence ran about 84 minutes.
Scratch was cleared between base/catalogue/boot phases and after each successful
module. Every build had a recorded space check; the smallest per-module starting
free space was over 56 GB. No deletion occurred outside `/srv/modfs/build`.
The original local artifacts were never rebuilt or modified. Findings are
committed locally on `experiment/remote-verification`.
