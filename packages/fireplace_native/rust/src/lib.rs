//! Re-export the pinned C ABI for the feature-enabled host comparison library.
//! Normal host and mobile builds select fireplace-crypto directly.

pub use fireplace_crypto::ffi::*;
