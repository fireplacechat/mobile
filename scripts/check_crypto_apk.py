"""Verify the packaged Rust libraries, architecture, page alignment and exports."""
import argparse
from pathlib import Path
import struct
import subprocess
import zipfile

TARGETS = {'arm64-v8a': (2, 183), 'armeabi-v7a': (1, 40), 'x86_64': (2, 62)}
REQUIRED = {'fp_free', 'fp_session_load', 'fp_session_save', 'fp_session_destroy',
            'fp_session_encrypt_handle', 'fp_session_decrypt_handle'}
FORBIDDEN = {'fp_set_test_rng', 'fp_clear_test_rng'}


def check_library(data, abi, symbols):
    elf_class, machine = TARGETS[abi]
    if len(data) < 64 or data[:4] != b'\x7fELF' or data[4:6] != bytes([elf_class, 1]):
        raise ValueError(f'{abi}: invalid ELF class or byte order')
    if struct.unpack_from('<H', data, 18)[0] != machine:
        raise ValueError(f'{abi}: wrong ELF architecture')
    wide = elf_class == 2
    offset = struct.unpack_from('<Q' if wide else '<I', data, 32 if wide else 28)[0]
    size, count = struct.unpack_from('<HH', data, 54 if wide else 42)
    if size < (56 if wide else 32) or count == 0 or offset + size * count > len(data):
        raise ValueError(f'{abi}: invalid ELF program headers')
    loads = 0
    for index in range(count):
        header = offset + index * size
        if struct.unpack_from('<I', data, header)[0] == 1:
            loads += 1
            alignment = struct.unpack_from('<Q' if wide else '<I', data,
                                           header + (48 if wide else 28))[0]
            if alignment < 16384:
                raise ValueError(f'{abi}: library is not aligned for 16 KB pages')
    if not loads or not REQUIRED <= symbols or FORBIDDEN & symbols:
        raise ValueError(f'{abi}: missing live-session ABI or exported test RNG')


def check_apk(apk, nm):
    with zipfile.ZipFile(apk) as archive:
        for abi in TARGETS:
            name = f'lib/{abi}/libfireplace_crypto.so'
            if name not in archive.namelist():
                raise ValueError(f'{abi}: crypto library is missing from APK')
            data = archive.read(name)
            result = subprocess.run([str(nm), '-D', '--defined-only', '-'], input=data,
                                    capture_output=True, check=True)
            symbols = {line.split()[-1] for line in result.stdout.decode().splitlines() if line.split()}
            check_library(data, abi, symbols)
            print(f'{abi}: crypto ABI present, no test RNG, 16 KB aligned')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--nm', required=True, type=Path, help='NDK llvm-nm executable')
    options = parser.parse_args()
    check_apk(options.apk, options.nm)
