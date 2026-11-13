import Darwin
import XCTest
@testable import PreviewDiagnostics

final class PreviewMemoryTests: XCTestCase {
  func testUnavailablePeakNeverReportsTheCurrentFootprintAsAPeak() {
    var info = task_vm_info_data_t()
    info.phys_footprint = 6 * 1024 * 1024
    info.ledger_phys_footprint_peak = 18 * 1024 * 1024
    let fieldEnd = MemoryLayout<task_vm_info_data_t>.offset(of: \.ledger_phys_footprint_peak)! + 8
    let firstSupportedCount = mach_msg_type_number_t(fieldEnd / MemoryLayout<integer_t>.size)
    XCTAssertEqual(PreviewDiagnostics.measuredPeak(info: info, count: firstSupportedCount - 1), 0)
    XCTAssertEqual(PreviewDiagnostics.measuredPeak(info: info, count: firstSupportedCount), 18 * 1024 * 1024)
    info.phys_footprint = 20 * 1024 * 1024
    XCTAssertEqual(PreviewDiagnostics.measuredPeak(info: info, count: firstSupportedCount), 20 * 1024 * 1024)
  }
}
