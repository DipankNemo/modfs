#!/usr/bin/env bash
#
# Negative controls for the two GPU-module probes.
#
#   sudo ./tests/gpu_probe_attacks.sh
#
# WHY THIS EXISTS. A probe that has only ever passed proves nothing about the
# module; it proves the probe ran. STATE_OF_PLAY section 5a lists eight checks
# in this project that passed while measuring the wrong thing, and the GPU
# probes are the ones most exposed to that failure, because nothing here can
# execute a CUDA kernel and say "it worked". So each probe is required to FAIL
# on a composed system that has been broken in a specific, named way.
#
# Method: compose base + the GPU modules exactly as 07_smoke_test.sh does, run
# the probe on the pristine merge (CONTROL, must pass), then mutate the
# writable upper layer and re-run (ATTACK, must fail). The overlay upper is
# discarded afterwards, so no artefact is touched -- this is the same technique
# ARCHITECTURE section 3 records for the V7 content attack on curl.
#
# Exit: 0 every case behaved, 1 a case did not, 2 the harness broke.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${HERE}/config.sh"
source "${HERE}/scripts/lib.sh"

die2() { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 2; }
[ "$(id -u)" -eq 0 ] || die2 "must run as root (mounts + chroot)"

DRIVER=nvidia-driver-535
CUDA=cuda-runtime
ABI=5.15.0-185-generic
KDIR="/usr/lib/modules/${ABI}/kernel/nvidia-535"
LIBDIR="/usr/lib/x86_64-linux-gnu"

for m in base "$DRIVER" "$CUDA"; do
    [ -f "${MOD_DIR}/${m}.sqsh" ] || die2 "missing artefact ${MOD_DIR}/${m}.sqsh"
done

# Probes come from the catalogue, never copied here: a test that carries its own
# copy of the thing under test stops testing it the first time one is edited.
read_probe() {            # read_probe <module>
    python3 - "${SPEC_DIR}/modules.yaml" "$1" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1], encoding='utf-8')) or {}
for m in (doc.get('modules') or []):
    if m.get('name') == sys.argv[2]:
        sys.stdout.write(str(m.get('probe') or '')); break
else:
    sys.exit(1)
PY
}
DRIVER_PROBE="$(read_probe "$DRIVER")" || die2 "no probe for ${DRIVER}"
CUDA_PROBE="$(read_probe "$CUDA")"     || die2 "no probe for ${CUDA}"

C="${BUILD_DIR}/gpu-probe-attacks"
reset_workdir "$C"
mkdir -p "$C"/{upper,work,merged}
trap 'unmount_all; cleanup' EXIT
trap 'unmount_all; trap - INT;  kill -s INT  $$' INT
trap 'unmount_all; trap - TERM; kill -s TERM $$' TERM

LOWERS=()
for m in base "$DRIVER" "$CUDA"; do
    mp="${C}/ro_${m}"; mkdir -p "$mp"
    do_mount -o loop,ro "${MOD_DIR}/${m}.sqsh" "$mp"
    LOWERS=("$mp" "${LOWERS[@]}")
done
LOWERDIR=$(IFS=:; echo "${LOWERS[*]}")
do_mount -t overlay overlay \
    -o "lowerdir=${LOWERDIR},upperdir=${C}/upper,workdir=${C}/work" "${C}/merged"
M="${C}/merged"
mount_chroot_fs "$M"
mkdir -p "$M/tmp"; chmod 1777 "$M/tmp"
write_chroot_policy "$M"
# The probes read /etc/ld.so.cache, which is a per-layer file the composed
# system must regenerate -- ARCHITECTURE section 4. Without this the cache is
# the top module's and the CONTROL cases fail for a reason that has nothing to
# do with what is being tested.
in_chroot "$M" ldconfig >/dev/null 2>&1 || die2 "ldconfig failed in the merge"

PASS=0; BAD=0
# case <label> <module> <expect pass|fail> <mutation...>
case_run() {
    local label="$1" mod="$2" expect="$3"; shift 3
    local probe out rc verdict
    case "$mod" in "$DRIVER") probe="$DRIVER_PROBE" ;; *) probe="$CUDA_PROBE" ;; esac
    if [ $# -gt 0 ]; then "$@" || { printf '  %-34s HARNESS: mutation failed\n' "$label"; BAD=$((BAD+1)); return 0; }; fi
    out=$(in_chroot "$M" sh -c "$probe" 2>&1 </dev/null); rc=$?
    [ "$rc" -eq 0 ] && verdict=pass || verdict=fail
    if [ "$verdict" = "$expect" ]; then
        printf '  %-34s probe %-4s (expected %-4s) ok\n' "$label" "$verdict" "$expect"
        PASS=$((PASS+1))
    else
        printf '  %-34s probe %-4s (expected %-4s) *** WRONG ***\n' "$label" "$verdict" "$expect"
        [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/        /' | head -4
        BAD=$((BAD+1))
    fi
}

# Mutations write into the overlay upper, so the previous case is undone by
# restoring from the read-only layer underneath rather than by remounting.
restore() { rm -rf "${M:?}/$1"; cp -a "${C}/ro_$2/$1" "${M}/$1"; }

echo
echo "========================================================================"
echo " GPU PROBE NEGATIVE CONTROLS  (${DRIVER}, ${CUDA})"
echo "========================================================================"
echo "  ${DRIVER}"
case_run "D0 CONTROL pristine"        "$DRIVER" pass
case_run "D1 .ko truncated to 0 bytes" "$DRIVER" fail \
    sh -c ": > '${M}${KDIR}/nvidia.ko'"
case_run "D0b restored"               "$DRIVER" pass \
    sh -c "cp -a '${C}/ro_${DRIVER}${KDIR}/nvidia.ko' '${M}${KDIR}/nvidia.ko'"
case_run "D2 .ko removed"             "$DRIVER" fail \
    sh -c "rm -f '${M}${KDIR}/nvidia-uvm.ko'"
case_run "D0c restored"               "$DRIVER" pass \
    sh -c "cp -a '${C}/ro_${DRIVER}${KDIR}/nvidia-uvm.ko' '${M}${KDIR}/nvidia-uvm.ko'"
# The V7 blind spot, on the files where it would matter most: same size,
# different bytes. (kind, size) cannot see this; a content digest can.
case_run "D3 .ko same-size substitution" "$DRIVER" fail \
    sh -c "sz=\$(stat -c %s '${M}${KDIR}/nvidia-peermem.ko'); head -c \"\$sz\" /dev/zero > '${M}${KDIR}/nvidia-peermem.ko'"
case_run "D0d restored"               "$DRIVER" pass \
    sh -c "cp -a '${C}/ro_${DRIVER}${KDIR}/nvidia-peermem.ko' '${M}${KDIR}/nvidia-peermem.ko'"
case_run "D4 nvidia-smi removed"      "$DRIVER" fail \
    sh -c "rm -f '${M}/usr/bin/nvidia-smi'"
case_run "D0e restored"               "$DRIVER" pass \
    sh -c "cp -a '${C}/ro_${DRIVER}/usr/bin/nvidia-smi' '${M}/usr/bin/nvidia-smi'"
case_run "D5 libcuda.so.1 removed"    "$DRIVER" fail \
    sh -c "rm -f '${M}${LIBDIR}/libcuda.so.1'"
case_run "D0f restored"               "$DRIVER" pass \
    sh -c "cp -a '${C}/ro_${DRIVER}${LIBDIR}/libcuda.so.1' '${M}${LIBDIR}/libcuda.so.1'"
# The layout failure the brief warns about and round2_attacks.py reproduces:
# a REAL lib/ directory outranks base's lib -> usr/lib symlink.
case_run "D6 /lib is a real directory" "$DRIVER" fail \
    sh -c "rm -f '${M}/lib' && mkdir -p '${M}/lib/modules/${ABI}'"
case_run "D0g restored"               "$DRIVER" pass \
    sh -c "rm -rf '${M}/lib' && ln -s usr/lib '${M}/lib'"

echo "  ${CUDA}"
case_run "C0 CONTROL pristine"        "$CUDA" pass
case_run "C1 soname target removed"   "$CUDA" fail \
    sh -c "rm -f '${M}${LIBDIR}/libcublasLt.so.11.7.4.6'"
case_run "C0b restored"               "$CUDA" pass \
    sh -c "cp -a '${C}/ro_${CUDA}${LIBDIR}/libcublasLt.so.11.7.4.6' '${M}${LIBDIR}/'"
case_run "C2 libcudart is a wrong CUDA" "$CUDA" fail \
    sh -c "rm -f '${M}${LIBDIR}/libcudart.so.11.0' && : > '${M}${LIBDIR}/libcudart.so.11.4.999' && ln -s libcudart.so.11.4.999 '${M}${LIBDIR}/libcudart.so.11.0'"
case_run "C0c restored"               "$CUDA" pass \
    sh -c "rm -f '${M}${LIBDIR}/libcudart.so.11.0' '${M}${LIBDIR}/libcudart.so.11.4.999' && ln -s libcudart.so.11.5.117 '${M}${LIBDIR}/libcudart.so.11.0'"
case_run "C3 libnvToolsExt removed"   "$CUDA" fail \
    sh -c "rm -f '${M}${LIBDIR}/libnvToolsExt.so.1'"
case_run "C0d restored"               "$CUDA" pass \
    sh -c "cp -a '${C}/ro_${CUDA}${LIBDIR}/libnvToolsExt.so.1' '${M}${LIBDIR}/'"

echo "========================================================================"
echo " ${PASS} case(s) behaved, ${BAD} did not"
echo "========================================================================"
[ "$BAD" -eq 0 ] || exit 1
exit 0
