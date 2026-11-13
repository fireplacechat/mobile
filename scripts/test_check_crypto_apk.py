"""Regression checks for rejecting unsafe or mismatched packaged libraries."""
import struct
import unittest

from check_crypto_apk import REQUIRED, check_library


def arm64_library():
    # Minimal ELF64 header and one PT_LOAD entry; bytes follow the ELF format,
    # independently of any Rust build layout or symbol ordering.
    data = bytearray(120)
    data[:6] = b'\x7fELF\x02\x01'
    struct.pack_into('<H', data, 18, 183)
    struct.pack_into('<Q', data, 32, 64)
    struct.pack_into('<HH', data, 54, 56, 1)
    struct.pack_into('<I', data, 64, 1)
    struct.pack_into('<Q', data, 112, 16384)
    return data


class LibraryChecks(unittest.TestCase):
    def test_valid_header_and_exports(self):
        check_library(arm64_library(), 'arm64-v8a', REQUIRED)

    def test_wrong_architecture_is_rejected(self):
        with self.assertRaises(ValueError):
            check_library(arm64_library(), 'x86_64', REQUIRED)

    def test_four_kilobyte_alignment_is_rejected(self):
        data = arm64_library()
        struct.pack_into('<Q', data, 112, 4096)
        with self.assertRaises(ValueError):
            check_library(data, 'arm64-v8a', REQUIRED)

    def test_truncated_headers_are_rejected(self):
        with self.assertRaises(ValueError):
            check_library(arm64_library()[:100], 'arm64-v8a', REQUIRED)

    def test_test_rng_export_is_rejected(self):
        with self.assertRaises(ValueError):
            check_library(arm64_library(), 'arm64-v8a', REQUIRED | {'fp_set_test_rng'})

    def test_missing_session_api_is_rejected(self):
        with self.assertRaises(ValueError):
            check_library(arm64_library(), 'arm64-v8a', REQUIRED - {'fp_session_load'})


if __name__ == '__main__':
    unittest.main()
