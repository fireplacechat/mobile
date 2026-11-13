import Darwin
import Foundation

/// Read an existing lock file only. Never create it or change its contents.
/// Match Dart's POSIX record lock; flock() would not coordinate with it.
final class PreviewReadLock {
  private static let processGate = NSLock()
  private var descriptor: Int32 = -1
  private var ownsGate = false
  init(file: URL, deadline: UInt64) throws {
    while !Self.processGate.try() {
      if DispatchTime.now().uptimeNanoseconds >= deadline { throw PreviewFailure.deadline }
      usleep(5000)
    }
    var opened: Int32 = -1
    var transferred = false
    defer {
      if !transferred {
        if opened >= 0 { close(opened) }
        Self.processGate.unlock()
      }
    }
    opened = open(file.path, O_RDONLY | O_NOFOLLOW)
    guard opened >= 0 else { throw PreviewFailure.unavailable }
    var record = flock(l_start: 0, l_len: 0, l_pid: 0, l_type: Int16(F_RDLCK), l_whence: Int16(SEEK_SET))
    while fcntl(opened, F_SETLK, &record) != 0 {
      if errno != EACCES && errno != EAGAIN {
        throw PreviewFailure.unavailable
      }
      if DispatchTime.now().uptimeNanoseconds >= deadline {
        throw PreviewFailure.deadline
      }
      usleep(5000)
    }
    descriptor = opened
    ownsGate = true
    transferred = true
  }
  deinit {
    if descriptor >= 0 { close(descriptor) }
    if ownsGate { Self.processGate.unlock() }
  }
}

/// One in-flight preview per extension process bounds aggregate memory even
/// if iOS delivers overlapping requests. A busy process immediately falls back.
final class PreviewAdmission {
  static let process = PreviewAdmission()
  private let state = NSLock()
  private var active = false
  func acquire() -> Lease? {
    state.lock()
    defer { state.unlock() }
    if active { return nil }
    active = true
    return Lease(owner: self)
  }
  private func release() {
    state.lock()
    active = false
    state.unlock()
  }
  final class Lease {
    private let owner: PreviewAdmission
    fileprivate init(owner: PreviewAdmission) { self.owner = owner }
    deinit { owner.release() }
  }
}
