import AudioToolbox
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    Sounds.installNotificationSound()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FireplaceNotifications") {
      NotificationsChannel.register(messenger: registrar.messenger())
    }
  }
}

/// `fireplace/notifications`: the app icon badge, clearing delivered alerts,
/// opening Fireplace's notification settings and the send sound. See
/// lib/src/model/notifications/system_notifications.dart.
private enum NotificationsChannel {
  static var channel: FlutterMethodChannel?

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "fireplace/notifications", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "setBadge":
        setBadge(max(0, (call.arguments as? Int) ?? 0), result: result)
      case "clearDelivered":
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        result(nil)
      case "openSettings":
        openSettings()
        result(nil)
      case "playSendSound":
        Sounds.playSend()
        result(nil)
      #if DEBUG || PREVIEW_DIAGNOSTICS
      case "previewDiagnostics":
        result(diagnosticRecords())
      #endif
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  #if DEBUG || PREVIEW_DIAGNOSTICS
  private static func diagnosticRecords() -> [[String: NSNumber]] {
    guard let appGroup = Bundle.main.object(forInfoDictionaryKey: "FPAppGroup") as? String,
          let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return [] }
    let file = root.appendingPathComponent("preview-diagnostics-v1.json")
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
          ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 32 * 1024,
          let data = try? Data(contentsOf: file),
          let records = try? JSONSerialization.jsonObject(with: data) as? [[String: NSNumber]] else { return [] }
    return Array(records.suffix(20)).filter {
      Set($0.keys) == ["run", "at", "ms", "peak", "outcome"]
    }.map { row in
      row.filter { $0.key != "run" }
    }
  }
  #endif

  private static func setBadge(_ count: Int, result: @escaping FlutterResult) {
    if #available(iOS 16.0, *) {
      UNUserNotificationCenter.current().setBadgeCount(count) { error in
        DispatchQueue.main.async {
          result(error == nil ? nil : FlutterError(code: "badge", message: nil, details: nil))
        }
      }
    } else {
      UIApplication.shared.applicationIconBadgeNumber = count
      result(nil)
    }
  }

  private static func openSettings() {
    let target: String
    if #available(iOS 16.0, *) {
      target = UIApplication.openNotificationSettingsURLString
    } else {
      target = UIApplication.openSettingsURLString
    }
    if let url = URL(string: target) {
      UIApplication.shared.open(url)
    }
  }
}

/// The two pops ship as Flutter assets (assets/sounds/).
private enum Sounds {
  /// Named by the push sender in `aps.sound`; keep the two in step.
  static let notificationFile = "notification_pop.wav"
  private static var sendSound: SystemSoundID?

  private static func assetPath(_ name: String) -> String? {
    let key = FlutterDartProject.lookupKey(forAsset: "assets/sounds/\(name)")
    return Bundle.main.path(forResource: key, ofType: nil)
  }

  /// APNs plays alert sounds from the main bundle or Library/Sounds. Copy the
  /// asset there on every launch, so an app update also updates the sound.
  /// If this fails, alerts fall back to the default sound.
  static func installNotificationSound() {
    guard let source = assetPath(notificationFile) else { return }
    let files = FileManager.default
    guard let library = files.urls(for: .libraryDirectory, in: .userDomainMask).first else {
      return
    }
    let folder = library.appendingPathComponent("Sounds", isDirectory: true)
    let target = folder.appendingPathComponent(notificationFile)
    do {
      try files.createDirectory(at: folder, withIntermediateDirectories: true)
      if files.fileExists(atPath: target.path) {
        try files.removeItem(at: target)
      }
      try files.copyItem(at: URL(fileURLWithPath: source), to: target)
    } catch {
      // The default alert sound plays instead.
    }
  }

  /// A system sound: short, mixes with other audio, and is silent when the
  /// ringer switch is set to silent.
  static func playSend() {
    if sendSound == nil, let path = assetPath("send_pop.wav") {
      var id: SystemSoundID = 0
      if AudioServicesCreateSystemSoundID(URL(fileURLWithPath: path) as CFURL, &id) == noErr {
        sendSound = id
      }
    }
    if let id = sendSound {
      AudioServicesPlaySystemSound(id)
    }
  }
}
