#!/usr/bin/env python3
"""Compile and execute a small CUDA kernel using an extracted runtime module.

Run on the GPU container, not the build VM. Uses the provider's existing
libcuda/kernel driver. This does NOT test loading ModFS's NVIDIA 535 module.
API reference: https://docs.nvidia.com/cuda/archive/11.5.0/nvrtc/index.html
"""
import ctypes as C
import hashlib
import json
from pathlib import Path
import re
import sys

P = C.c_void_p
I = C.c_int
U = C.c_uint
Z = C.c_size_t
CP = C.c_char_p
PP = C.POINTER(P)


def bind(lib, name, args):
    fn = getattr(lib, name)
    fn.argtypes = args
    fn.restype = I
    return fn


def check(fn, *args):
    rc = fn(*args)
    if rc:
        raise RuntimeError(f'{fn.__name__} returned {rc}')


libdir = Path(sys.argv[1]).resolve()
nvrtc_path = (libdir / 'libnvrtc.so.11.2').resolve(strict=True)
cudart_path = (libdir / 'libcudart.so.11.0').resolve(strict=True)
assert libdir in nvrtc_path.parents and libdir in cudart_path.parents
nvrtc = C.CDLL(str(nvrtc_path))
cudart = C.CDLL(str(cudart_path))
driver = C.CDLL('libcuda.so.1')

version = bind(nvrtc, 'nvrtcVersion', [C.POINTER(I), C.POINTER(I)])
create = bind(nvrtc, 'nvrtcCreateProgram', [PP, CP, CP, I, C.POINTER(CP), C.POINTER(CP)])
compile_program = bind(nvrtc, 'nvrtcCompileProgram', [P, I, C.POINTER(CP)])
log_size = bind(nvrtc, 'nvrtcGetProgramLogSize', [P, C.POINTER(Z)])
get_log = bind(nvrtc, 'nvrtcGetProgramLog', [P, P])
ptx_size = bind(nvrtc, 'nvrtcGetPTXSize', [P, C.POINTER(Z)])
get_ptx = bind(nvrtc, 'nvrtcGetPTX', [P, P])
destroy = bind(nvrtc, 'nvrtcDestroyProgram', [PP])
runtime_version = bind(cudart, 'cudaRuntimeGetVersion', [C.POINTER(I)])
set_device = bind(cudart, 'cudaSetDevice', [I])
malloc = bind(cudart, 'cudaMalloc', [PP, Z])
free = bind(cudart, 'cudaFree', [P])
sync = bind(cudart, 'cudaDeviceSynchronize', [])
copy = bind(cudart, 'cudaMemcpy', [P, P, Z, I])
init = bind(driver, 'cuInit', [U])
driver_version = bind(driver, 'cuDriverGetVersion', [C.POINTER(I)])
get_device = bind(driver, 'cuDeviceGet', [C.POINTER(I), I])
device_name = bind(driver, 'cuDeviceGetName', [P, I, I])
attribute = bind(driver, 'cuDeviceGetAttribute', [C.POINTER(I), I, I])
load_module = bind(driver, 'cuModuleLoadData', [PP, P])
get_function = bind(driver, 'cuModuleGetFunction', [PP, P, CP])
launch = bind(driver, 'cuLaunchKernel', [P] + [U] * 7 + [P, PP, PP])
unload = bind(driver, 'cuModuleUnload', [P])

major, minor, runtime, drv, device, cc_major, cc_minor = (I() for _ in range(7))
check(version, C.byref(major), C.byref(minor))
check(runtime_version, C.byref(runtime))
check(init, 0)
check(driver_version, C.byref(drv))
check(get_device, C.byref(device), 0)
name = C.create_string_buffer(256)
check(device_name, name, len(name), device)
check(attribute, C.byref(cc_major), 75, device)
check(attribute, C.byref(cc_minor), 76, device)
assert (major.value, minor.value) == (11, 5)
assert runtime.value == 11050
assert (cc_major.value, cc_minor.value) == (8, 6)

source = b'extern "C" __global__ void modfs_add(int *out) { out[threadIdx.x] = (int)threadIdx.x + 7; }'
program = P()
check(create, C.byref(program), source, b'modfs_probe.cu', 0, None, None)
try:
    options = (CP * 1)(b'--gpu-architecture=compute_86')
    compile_rc = compile_program(program, 1, options)
    length = Z()
    check(log_size, program, C.byref(length))
    log = C.create_string_buffer(length.value)
    check(get_log, program, log)
    if compile_rc:
        raise RuntimeError(f'NVRTC compile returned {compile_rc}: {log.value.decode()}')
    check(ptx_size, program, C.byref(length))
    ptx = C.create_string_buffer(length.value)
    check(get_ptx, program, ptx)
finally:
    check(destroy, C.byref(program))

check(set_device, 0)
check(free, None)  # Initialise cudart's primary context before driver API use.
module, function, allocation = P(), P(), P()
check(load_module, C.byref(module), ptx)
try:
    check(get_function, C.byref(function), module, b'modfs_add')
    result = (I * 32)()
    check(malloc, C.byref(allocation), C.sizeof(result))
    try:
        params = (P * 1)(C.cast(C.byref(allocation), P))
        check(launch, function, 1, 1, 1, 32, 1, 1, 0, None, params, None)
        check(sync)
        check(copy, result, allocation, C.sizeof(result), 2)  # Device to host.
        assert list(result) == list(range(7, 39)), list(result)
    finally:
        check(free, allocation)
finally:
    check(unload, module)

mapped = sorted({line.split()[-1] for line in Path('/proc/self/maps').read_text().splitlines()
                 if any(token in line for token in ('libcuda.', 'libcudart.', 'libnvrtc'))})
hashes = {path: hashlib.sha256(Path(path).read_bytes()).hexdigest() for path in mapped}
print(json.dumps({
    'result': 'PASS', 'scope': 'Remotely built ModFS runtime with provider driver; no ModFS 535 kernel module load',
    'device': name.value.decode(), 'compute_capability': [cc_major.value, cc_minor.value],
    'nvrtc_version': [major.value, minor.value], 'runtime_version': runtime.value,
    'driver_api_version': drv.value, 'kernel_source': source.decode(),
    'ptx_version': re.search(rb'\.version\s+(\S+)', ptx.value).group(1).decode(),
    'ptx_sha256': hashlib.sha256(ptx.value).hexdigest(),
    'compiler_log': log.value.decode(), 'output': list(result),
    'mapped_library_sha256': hashes,
}, indent=2))
