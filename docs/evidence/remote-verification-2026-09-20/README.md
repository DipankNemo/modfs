# Independent remote verification evidence

See the dated JOURNAL.md entries for conclusions. Logs are observations, not
claims that all requested phases completed. The project revision used for the
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
