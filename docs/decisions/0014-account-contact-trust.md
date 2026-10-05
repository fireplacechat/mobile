# Account contact trust

Contact pins, verification and known-device history are local, account-scoped secure-store records. Each KeyService belongs to one local account. Verification records bind both the local identity and the pinned contact identity; replacing either identity requires a fresh comparison.

Legacy unscoped records are not imported, because their originating account cannot be established. Existing contacts use first-use pinning again and require explicit verification. Account keys and cryptographic wire formats are unchanged. No server fields are added.
