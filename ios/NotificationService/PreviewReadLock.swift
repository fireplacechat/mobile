import Darwin
import Foundation

/// Read an existing lock file only. Never create it or change its contents.
/// Match Dart's POSIX record lock; flock() would not coordinate with it.
final class PreviewReadLock {
  private var descriptor: Int32 = -1
  init(file: URL, deadline: UInt64) throws {
    let opened = open(file.path, O_RDONLY | O_NOFOLLOW)
    guard opened >= 0 else { throw PreviewFailure.unavailable }
    var record = flock(l_start: 0, l_len: 0, l_pid: 0, l_type: Int16(F_RDLCK), l_whence: Int16(SEEK_SET))
    while fcntl(opened, F_SETLK, &record) != 0 {
      if errno != EACCES && errno != EAGAIN {
        close(opened)
        throw PreviewFailure.unavailable
      }
      if DispatchTime.now().uptimeNanoseconds >= deadline {
        close(opened)
        throw PreviewFailure.deadline
      }
      usleep(5000)
    }
    descriptor = opened
  }
  deinit { if descriptor >= 0 { close(descriptor) } }
}
