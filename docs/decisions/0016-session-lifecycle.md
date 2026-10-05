# Session lifecycle

Session cancellation is registered before initialization awaits. Each completed resource is registered for cleanup, initialization checks cancellation after awaits, and partial initialization is closed on failure. Disposal during an awaited start waits for that start to settle before cleaning its resources.

Chat shutdown cancels sync subscriptions and retry timers and drains in-flight receive work before local storage closes. Shutdown is idempotent. No wire or server-storage changes are involved.
