#if PREVIEW_DIAGNOSTICS
import Darwin
import Foundation

/// Numeric local test data only. This entire writer is absent from normal
/// Release builds. An outcome of zero means the run did not record completion.
enum PreviewDiagnostics {
  static func peakBytes() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return 0 }
    return measuredPeak(info: info, count: count)
  }

  static func measuredPeak(info: task_vm_info_data_t, count: mach_msg_type_number_t) -> UInt64 {
    let end = (MemoryLayout<task_vm_info_data_t>.offset(of: \.ledger_phys_footprint_peak) ?? Int.max - 8) + 8
    // A current footprint cannot establish the peak. Older API revisions must
    // show "unavailable" instead of suggesting the memory budget was met.
    guard Int(count) * MemoryLayout<integer_t>.size >= end else { return 0 }
    return max(info.phys_footprint, UInt64(max(0, info.ledger_phys_footprint_peak)))
  }

  static func record(root: URL, run: UInt64, started: UInt64, outcome: Int) {
    let file = root.appendingPathComponent("preview-diagnostics-v1.json")
    do {
      var records: [[String: NSNumber]] = []
      if let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
         ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 32 * 1024,
         let bytes = try? Data(contentsOf: file),
         let saved = try? JSONSerialization.jsonObject(with: bytes) as? [[String: NSNumber]] {
        records = Array(saved.suffix(20)).filter { Set($0.keys) == ["run", "at", "ms", "peak", "outcome"] }
      }
      records.removeAll { $0["run"]?.uint64Value == run }
      records.append([
        "run": NSNumber(value: run), "at": NSNumber(value: Int64(Date().timeIntervalSince1970 * 1000)),
        "ms": NSNumber(value: (DispatchTime.now().uptimeNanoseconds - started) / 1_000_000),
        "peak": NSNumber(value: peakBytes()), "outcome": NSNumber(value: outcome)
      ])
      let bytes = try JSONSerialization.data(withJSONObject: Array(records.suffix(20)))
      try bytes.write(to: file, options: [.atomic])
      try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
    } catch { /* Diagnostics never prevent the push's original fallback. */ }
  }
}
#endif
