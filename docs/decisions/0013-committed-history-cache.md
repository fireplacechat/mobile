# 0013: Publish local history only after disk commit

An encrypted-history mutation creates a candidate map. Only after encrypted temporary-file
write, flush and atomic rename succeed is that map published to the cache and stream. A failed
write leaves readers seeing the last persisted state. Removal follows the same rule; chat deletion
clears its cache only after file deletion succeeds.

Receive-journal replay relies on `LocalMessageStore.has` meaning durable presence. Keeping the
previous cache on failure makes the existing replay write the message again before consuming its
journal or ratchet state. No wire-format or ratchet change is necessary.

Tests reproduce failed disk writes and receive replay using the real encrypted file store and
ChatService, then reopen the store to verify history survived. Implementation assisted by Codex.
