import Foundation
import UserNotifications

final class NotificationService: UNNotificationServiceExtension, @unchecked Sendable {
  private let state = NSLock()
  private var callback: ((UNNotificationContent) -> Void)?
  private var original: UNNotificationContent?
  private var work: Task<Void, Never>?
  private var timer: DispatchWorkItem?
  private var root: URL?
  private var started: UInt64 = 0

  override func didReceive(_ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
    state.lock()
    let previous = started
    state.unlock()
    finish(nil, outcome: 3, run: previous)
    let run = DispatchTime.now().uptimeNanoseconds
    state.lock()
    callback = contentHandler
    original = request.content
    started = run
    let timeout = DispatchWorkItem { [weak self] in self?.finish(nil, outcome: 3, run: run) }
    timer = timeout
    state.unlock()
    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 4.5, execute: timeout)
    let task = Task { [weak self] in
      guard let self = self else { return }
      do {
        let deadline = PreviewDeadline()
        guard let appGroup = Bundle.main.object(forInfoDictionaryKey: "FPAppGroup") as? String,
              let group = Bundle.main.object(forInfoDictionaryKey: "FPSharedKeychainGroup") as? String,
              !group.contains("$("),
              let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup),
              request.content.userInfo["fp"] as? String == "1",
              let key = request.content.userInfo["k"] as? String else { throw PreviewFailure.unavailable }
        try deadline.check()
        guard self.begin(root: root, run: run) else { throw PreviewFailure.deadline }
        let store = PreviewKeychain(group: group)
        guard let auth = try store.object("ios-preview-auth", cap: 32 * 1024) else { throw PreviewFailure.unavailable }
        let credentials = try PreviewCredentials(auth)
        let preview = try await PreviewRunner(store: store, root: root, deadline: deadline).run(key: key, credentials: credentials)
        try deadline.check()
        // Signing out or disabling previews while the fetch was under way must
        // not post its plaintext. Each keychain value is an atomic record.
        guard let current = try store.object("ios-preview-auth", cap: 32 * 1024), current["uid"] as? String == credentials.uid,
              try store.read("pushoff:\(credentials.uid)") == nil,
              try store.read("pushnopreview:\(credentials.uid)") == nil else { throw PreviewFailure.unavailable }
        guard let preview = preview, let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
          self.finish(nil, outcome: 2, run: run)
          return
        }
        content.body = preview.body
        if try store.read("pushhidename:\(credentials.uid)") != nil { content.title = "Fireplace" }
        if try store.read("pushsilent:\(credentials.uid)") != nil { content.sound = nil }
        content.threadIdentifier = key
        content.userInfo["fp_message_id"] = preview.message
        self.finish(content, outcome: 1, run: run)
      } catch {
        self.finish(nil, outcome: 2, run: run)
      }
    }
    state.lock()
    if callback != nil && started == run { work = task }
    else { task.cancel() }
    state.unlock()
  }

  private func begin(root: URL, run: UInt64) -> Bool {
    state.lock()
    defer { state.unlock() }
    guard callback != nil && started == run else { return false }
    self.root = root
    #if PREVIEW_DIAGNOSTICS
    PreviewDiagnostics.record(root: root, run: run, started: run, outcome: 0)
    #endif
    return true
  }

  private func finish(_ content: UNNotificationContent?, outcome: Int, run: UInt64) {
    state.lock()
    guard started == run else { state.unlock(); return }
    let callback = self.callback, fallback = original
    self.callback = nil
    let work = self.work, timer = self.timer
    let root = self.root
    self.root = nil
    self.work = nil; self.timer = nil
    state.unlock()
    guard let callback = callback, let fallback = fallback else { return }
    timer?.cancel()
    work?.cancel()
    #if PREVIEW_DIAGNOSTICS
    if let root = root { PreviewDiagnostics.record(root: root, run: run, started: run, outcome: outcome) }
    #endif
    callback(content ?? fallback)
  }

  override func serviceExtensionTimeWillExpire() {
    state.lock()
    let run = started
    state.unlock()
    finish(nil, outcome: 3, run: run)
  }
}
