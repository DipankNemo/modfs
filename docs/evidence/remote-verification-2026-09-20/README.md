# Independent remote verification evidence

See [REPORT.md](REPORT.md) for final results and limits, and the dated JOURNAL.md
entries for the record as work progressed. The project revision used for the
initial checks is `a69111baedb576ea9d093626e883b6f7cd5bd3ce`.

## Container bootstrap

Connect using `ssh -p 17288 root@91.150.160.38`. Read the instance guide at
`/etc/vast-agents-guide.md`. On a fresh equivalent instance:

```sh
git clone https://github.com/DipankNemo/modfs.git /root/modfs
cd /root/modfs
git checkout --detach a69111baedb576ea9d093626e883b6f7cd5bd3ce
./scripts/00_verify.sh
# Record this output BEFORE installation.
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y debootstrap squashfs-tools rsync gdisk attr qemu-utils util-linux curl python3-yaml zstd
./scripts/00_verify.sh
./scripts/11_boot_test.sh --name remote-preflight base jq
```

`initial-verify.log`, `suggested-install.log` and `post-install-verify.log`
record these steps. `remote-environment.log` records `uname`, OS, disk,
capabilities, device absence and namespace/loop failures. Repeat its decisive
checks with:

```sh
uname -r
systemd-detect-virt
capsh --print
unshare --mount --propagation private true
unshare --user --map-root-user true
losetup -f
ls -l /dev/kvm /dev/loop-control /dev/loop0 /dev/fuse
nvidia-smi --query-gpu=name,memory.total,compute_cap,driver_version --format=csv
```

## Local reference, read-only

The original Git tree has no tracked manifests. `local-reference.csv` was
derived directly from `/srv/modfs/modules`, without changing any artefact or
manifest. To reproduce it into a NEW output file:

```python
import csv, hashlib, json, pathlib
root = pathlib.Path('/srv/modfs/modules')
with open('local-reference-repeated.csv', 'x') as out:
    w = csv.writer(out)
    w.writerow(['name', 'snapshot', 'manifest_sha256',
                'manifest_artifact_sha256', 'actual_artifact_sha256',
                'manifest_bytes', 'actual_bytes', 'digest_matches'])
    for p in sorted(root.glob('*.json')):
        raw = p.read_bytes()
        d = json.loads(raw)
        a = d['artifact']
        sq = p.with_suffix('.sqsh')
        h = hashlib.sha256()
        with sq.open('rb') as source:
            for chunk in iter(lambda: source.read(8 * 1024 * 1024), b''):
                h.update(chunk)
        actual = h.hexdigest()
        size = sq.stat().st_size
        w.writerow([p.stem, d['snapshot'], hashlib.sha256(raw).hexdigest(),
                    a['sha256'], actual, a['bytes'], size,
                    actual == a['sha256'] and size == a['bytes']])
```

The 41 matching rows establish local reference integrity only.

## Software VM on the remote container

This uses QEMU TCG, no KVM and no GPU passthrough. It does not modify the
provider's kernel or reboot the instance. All VM scratch is below
`/srv/modfs/build/verification-vm`. The guest is a separate build environment;
its results must not be described as native execution in the container.

Installed `qemu-system-x86 cloud-image-utils` on the remote. Downloaded
[Canonical's dated Jammy image](https://cloud-images.ubuntu.com/jammy/20260918/)
and SHA256SUMS over HTTPS. The image hash is
`48c7e1ab2005bff1c5450bd6c74d0f38482f0d750e14f320367e3e1c795035f9`.
The first checksum command matched a space-prefixed filename, but Canonical
uses `*filename`; it selected no lines. The corrected check below passed.

Run in a fresh directory, with at least 60 billion free bytes:

```sh
mkdir -p /srv/modfs/build/verification-vm
cd /srv/modfs/build/verification-vm
curl -fL --retry 3 -o jammy-server-cloudimg-amd64.img https://cloud-images.ubuntu.com/jammy/20260918/jammy-server-cloudimg-amd64.img
curl -fL --retry 3 -o SHA256SUMS https://cloud-images.ubuntu.com/jammy/20260918/SHA256SUMS
grep ' \*jammy-server-cloudimg-amd64.img$' SHA256SUMS | sha256sum -c -
qemu-img create -f qcow2 -F qcow2 -b "$PWD/jammy-server-cloudimg-amd64.img" guest.qcow2 60G
ssh-keygen -q -t ed25519 -N '' -f guest-key
python3 - <<'PY'
from pathlib import Path
import yaml
key = Path('guest-key.pub').read_text().strip()
data = {
    'disable_root': False, 'ssh_pwauth': False,
    'users': [{'name': 'root', 'lock_passwd': True,
               'ssh_authorized_keys': [key]}],
    'write_files': [{'path': '/etc/ssh/sshd_config.d/99-modfs-verification.conf',
                     'content': 'PermitRootLogin prohibit-password\n'}],
}
Path('user-data').write_text('#cloud-config\n' + yaml.safe_dump(data))
Path('meta-data').write_text('instance-id: modfs-independent-verification-20260920\nlocal-hostname: modfs-verification\n')
PY
cloud-localds seed.img user-data meta-data
qemu-system-x86_64 -accel tcg,thread=multi -machine q35 -cpu max -smp 4 -m 8192 \
  -drive file=guest.qcow2,format=qcow2,if=virtio,discard=unmap \
  -drive file=seed.img,format=raw,if=virtio \
  -netdev user,id=n0,hostfwd=tcp:127.0.0.1:2222-:22 \
  -device virtio-net-pci,netdev=n0 -display none -serial file:serial.log \
  -monitor unix:monitor.sock,server,nowait -pidfile qemu.pid -daemonize
```

After cloud-init finishes, access it FROM THE REMOTE CONTAINER with:

```sh
ssh -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new \
  -o UserKnownHostsFile=/srv/modfs/build/verification-vm/known_hosts \
  -i /srv/modfs/build/verification-vm/guest-key -p 2222 root@127.0.0.1
```

The private key remains on the remote and is never committed. The guest also
clones from GitHub origin; no source tree is copied into it. Its first clone
and pre-install verifier output are in `guest-initial-verify-retry.log` (the
earlier log is an SSH connection attempt before boot completed).

## Guest tool bootstrap and inventories

The guest ran the same initial verifier and suggested apt line before any
extra tool installation. `guest-suggested-install.log` records the 4.5 option
failure. The follow-up command sequence (`guest-extra-tools.log`) was:

```sh
export DEBIAN_FRONTEND=noninteractive
apt-get install -y build-essential libzstd-dev liblz4-dev liblzo2-dev liblzma-dev libattr1-dev zlib1g-dev pkg-config qemu-system-x86 dosfstools ovmf
mkdir -p /srv/modfs/build/toolchain
cd /srv/modfs/build/toolchain
git clone --branch 4.6.1 --depth 1 https://github.com/plougher/squashfs-tools.git
cd squashfs-tools
git rev-parse HEAD
make -C squashfs-tools -j4 ZSTD_SUPPORT=1 XZ_SUPPORT=1 LZO_SUPPORT=1 LZ4_SUPPORT=1
install -m 755 squashfs-tools/mksquashfs squashfs-tools/unsquashfs /usr/local/bin/
mksquashfs -version
dpkg-query -W debootstrap libzstd1 squashfs-tools
cd /root/modfs
./scripts/00_verify.sh
```

The upstream revision was `d8cb82d9840330f9344ec37b992595b5d7b44184`.
The `/usr/local/bin` tools supersede the distro's 4.5 executable on PATH;
dpkg still correctly reports the distro package as 4.5. With compatible tools,
the verifier reports 31 passes and the obsolete opaque-directory expectation
fails. Do not describe that as a completely passing verifier.

`squash_inventory.py` is a read-only measurement helper. It consumes
`unsquashfs -pf -` and hashes the embedded file data without extracting it.
It retains inode metadata, links and xattrs; regular-file pseudo-stream data
offsets are replaced by per-file hashes. It neither rewrites an archive nor
changes the cross-machine archive-hash comparison. Example:

```sh
python3 squash_inventory.py /srv/modfs/modules/base.sqsh > new-base-inventory.json
```

`local-inventories.jsonl.gz` contains one JSON document for each of the 41
reference artefacts, produced by that helper and gzip-compressed for storage.
Every archive hash/size was checked against `local-reference.csv` afterwards.
The plain base and jq inventories are also retained for convenient inspection.
Validation: all 41 archives parse; 65,674 total per-archive nodes; four base
file digests independently match `unsquashfs -cat` (`etc/adduser.conf`,
`usr/bin/bash`, `var/lib/dpkg/status`, `etc/machine-id`). Python syntax check
passed. This is diagnostic coverage, not a general-purpose SquashFS parser.

The base build runs in the guest with the unchanged `a69111b` checkout:

```sh
cd /root/modfs
export MODFS_ROOT=/srv/modfs/build/verification
export MODFS_SNAPSHOT_ID=20260701T000000Z
export PYTHONDONTWRITEBYTECODE=1
df -B1 /srv/modfs/build  # require >40 billion free bytes before starting
/usr/bin/time -p unshare --mount --propagation private ./scripts/01_build_base.sh --version 1.0
```

`remote-base-build.log` records the actual result and elapsed time. Logs are
also preserved in the guest under `/srv/modfs/results/remote-verification-2026-09-20/`.

## Catalogue and independent comparison

After base, copy the committed measurement helper `run_catalogue.sh` into
guest `/srv/modfs/build/run_catalogue.sh` (not into the clean source clone),
then run inside that guest:

```sh
nohup bash /srv/modfs/build/run_catalogue.sh /root/modfs \
  > /srv/modfs/results/remote-verification-2026-09-20/catalogue.log 2>&1 < /dev/null &
```

The helper records space before each build, stops on shortage, saves bundles
and logs, and removes successful upperdirs/build scratch before proceeding.
It refuses to overwrite a prior catalogue status CSV. Its final status is
40 builds with exit 0. `catalogue-results-bundle.tar` contains the status/logs,
manifests, and sidecars, but no large SquashFS payloads. The latter remain
in the guest's results/payloads directory.

Run `squash_inventory.py` against each of the 41 new archives as for the
originals, retaining one JSON document per line in `remote-inventories.jsonl.gz`.
To recompute the comparison from the committed records:

```sh
python3 verify_evidence.py
```

This checks both sets of manifest hashes against independent archive
inventories, package maps, snapshot identity, every CSV field, actual GPU
library bindings, and the unchanged boot verdict parser. Its saved output is
`evidence-validation.json`. It audits recorded measurements; it does not claim
to rehash a remote file while offline.

For the supplemental jq-only build, a separate root
`/srv/modfs/build/matched-jq` received copies of the new base bundle. Then:

```sh
cd /root/modfs
MODFS_ROOT=/srv/modfs/build/matched-jq MODFS_SNAPSHOT_ID=20260701T000000Z \
  PYTHONDONTWRITEBYTECODE=1 /usr/bin/time -p \
  unshare --mount --propagation private ./scripts/02_build_delta.sh --version 1.0 jq jq
```

Its inventory is `matched-jq-inventory.json`; the original jq reference is
`local-jq-inventory.json`. This separate result does not change the main count.

## Content diagnoses

`content_probe.py` reads selected files through unsquashfs. It reports shadow
date fields and digests of the other fields, public JKS certificate entries,
Python bytecode headers/payload hashes, the PostgreSQL public certificate and
cluster identifier, and package scripts. It never emits password values or
private keys. Execute on each machine with its own artifact directory:

```sh
python3 content_probe.py /srv/modfs/modules cross-machine-differences.json.gz
# In the remote guest:
python3 /srv/modfs/build/content_probe.py /srv/modfs/build/verification/modules \
  /srv/modfs/build/cross-machine-differences.json.gz
```

Outputs are `content-{local,remote}.json`; their comparison is in
`content-diagnosis.json`. Compare equal accounts' `other_fields_sha256`, match
JKS entries by alias and certificate SHA256, compare pyc payload hashes, and
diff the text records. `llvm-layout-diagnosis.json` compares the 19 added LLVM
paths to the old records after removing the leading `usr/` in the lookup key.
Neither operation changes any artifact.

Run the isolated fixtures **only in the remote guest**, using the scripts here
as stdin or copying them under `/srv/modfs/build` first:

```sh
unshare --mount --propagation private bash /srv/modfs/build/impure_fixture.sh
bash /srv/modfs/build/info_order_fixture.sh
unshare --mount --propagation private bash /srv/modfs/build/cds_fixture.sh
```

They respectively demonstrate lower-entry copy-up attributes, order-dependent
Info-index generation (including exact old/new dir.old hashes), and differing
successive JVM CDS dumps on one VM. All fixture output stays below
`/srv/modfs/build`; measured archives remain read only.

For the MySQL samples, read `var/lib/mysql/sys/version.frm` and
`var/lib/mysql/aria_log_control` with `unsquashfs -cat MODULE FILE` on each
machine. The retained `mysql-state-*.json` stores the view as text and the
52-byte control file as hex. `uuid.UUID(bytes=control_bytes[4:20])` reproduces
the UUID version, timestamp and node in `mysql-uuid-diagnosis.json`.

## Binding and boot

The actual original invocation, inside the guest, was:

```sh
cd /root/modfs
export MODFS_ROOT=/srv/modfs/build/verification MODFS_SNAPSHOT_ID=20260701T000000Z
export PYTHONDONTWRITEBYTECODE=1
unshare --mount --propagation private ./scripts/12_verify_binding.sh
# Clear BUILD_DIR using lib.sh reset_workdir after confirming no mounts.
df -B1 /srv/modfs/build  # required >15 GB before packing
unshare --mount --propagation private ./scripts/11_boot_test.sh \
  --name remote-webserver --timeout 3600 base webserver
```

Binding passed, the initial boot failed. The original packed image is at
`/srv/modfs/build/verification/build/boot-remote-webserver-20260920T190147Z/disk.img`.
Copy `run_tcg_retry.sh` to the **outer remote container** below its build root
and execute there. It copies that image using a sparse tar stream, copies the
guest's OVMF firmware, runs QEMU explicitly with TCG, and extracts and runs the
original script's exact Python verdict parser. It does not repack the image.
The script records input hashes, QEMU and verdict exit codes, serial output and
timestamps. Its result is retained in `tcg-boot-results.tar`; the original run
and binding logs are in `first-boot-results.tar`.

## Real GPU runtime probe

In the build guest, extract only the required libraries from the new artifact:

```sh
unsquashfs -no-progress -d /srv/modfs/build/gpu-libraries \
  /srv/modfs/build/verification/modules/cuda-runtime.sqsh \
  'usr/lib/x86_64-linux-gnu/libcudart*' 'usr/lib/x86_64-linux-gnu/libnvrtc*'
```

Copy that relative `usr` subtree by tar over the **inner SSH connection** to
outer `/srv/modfs/build/gpu-built`. This is transfer of built libraries, not
source. Create `gpu-built/cache` and `gpu-built/tmp`. On the outer container:

```sh
uname -r
nvidia-smi
LD_LIBRARY_PATH=/srv/modfs/build/gpu-built/usr/lib/x86_64-linux-gnu \
  CUDA_CACHE_PATH=/srv/modfs/build/gpu-built/cache \
  TMPDIR=/srv/modfs/build/gpu-built/tmp PYTHONDONTWRITEBYTECODE=1 \
  python3 /srv/modfs/build/cuda_runtime_probe.py \
  /srv/modfs/build/gpu-built/usr/lib/x86_64-linux-gnu
```

The helper can equivalently be supplied over stdin as `python3 - LIBDIR`, as
in the measured run. It uses the existing provider driver and never insmods
or modifies a kernel module. The implementation follows NVIDIA's
[NVRTC 11.5 API](https://docs.nvidia.com/cuda/archive/11.5.0/nvrtc/index.html).
The two interrupted attempts to transfer the original full CUDA artifact
were never used; their logs are retained separately.
