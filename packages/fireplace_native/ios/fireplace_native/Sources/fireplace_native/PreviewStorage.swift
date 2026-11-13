import Darwin
import Flutter
import Foundation

enum IOSPreviewStorage {
  private static let queue = DispatchQueue(label: "fireplace.preview.storage")
  private static var prepared: [String: String]?

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "fireplace/preview_storage", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "prepare" || call.method == "protectHistory" else {
        result(FlutterMethodNotImplemented)
        return
      }
      queue.async {
        do {
          let configuration = try prepare()
          if call.method == "protectHistory" {
            guard let args = call.arguments as? [String: String], let uid = args["uid"],
                  !uid.isEmpty, !uid.contains("/"), uid != ".", uid != ".." else {
              throw PreviewStorageError.configuration
            }
            let directory = URL(fileURLWithPath: configuration["directory"]!)
              .appendingPathComponent("messages_\(uid)", isDirectory: true)
            try protectHistory(directory)
          }
          DispatchQueue.main.async { result(call.method == "prepare" ? configuration : nil) }
        } catch {
          // Do not expose keychain accounts, values or tokens through errors.
          DispatchQueue.main.async {
            result(FlutterError(code: "shared_storage", message: "Could not open secure storage.", details: nil))
          }
        }
      }
    }
  }

  private static func setting(_ key: String) throws -> String {
    guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
          !value.isEmpty, !value.contains("$(") else { throw PreviewStorageError.configuration }
    return value
  }

  private static func protectHistory(_ directory: URL) throws {
    let files = FileManager.default
    let protection: [FileAttributeKey: Any] = [
      .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
    ]
    try files.setAttributes(protection, ofItemAtPath: directory.path)
    var resource = directory
    var values = URLResourceValues()
    values.isExcludedFromBackup = true // The history key is device-only.
    try resource.setResourceValues(values)
    var failure: Error?
    guard let entries = files.enumerator(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey],
      errorHandler: { _, error in failure = error; return false }) else {
      throw PreviewStorageError.configuration
    }
    for case let entry as URL in entries {
      guard try entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
        throw PreviewStorageError.configuration
      }
      try files.setAttributes(protection, ofItemAtPath: entry.path)
    }
    if let failure = failure { throw failure }
  }

  private static func prepare() throws -> [String: String] {
    if let prepared = prepared { return prepared }
    let group = try setting("FPSharedKeychainGroup")
    let legacy = try setting("FPLegacyKeychainGroup")
    let appGroup = try setting("FPAppGroup")
    guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
      throw PreviewStorageError.configuration
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
    // This is a separate file from each account's lock. POSIX closing rules
    // forbid opening and closing a second descriptor of an account lock.
    let descriptor = open(root.appendingPathComponent("migration.lock").path, O_CREAT | O_RDWR, mode_t(S_IRUSR | S_IWUSR))
    guard descriptor >= 0 else { throw PreviewStorageError.fileLock }
    defer { close(descriptor) }
    var lock = flock(l_start: 0, l_len: 0, l_pid: 0, l_type: Int16(F_WRLCK), l_whence: Int16(SEEK_SET))
    guard fcntl(descriptor, F_SETLKW, &lock) == 0 else { throw PreviewStorageError.fileLock }
    try PreviewKeychainMigration.run(SystemPreviewKeychain(legacyGroup: legacy, sharedGroup: group))
    let configuration = ["keychainGroup": group, "directory": root.path]
    prepared = configuration
    return configuration
  }
}
