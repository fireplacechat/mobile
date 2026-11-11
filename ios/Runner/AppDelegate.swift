import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FireplaceNotifications") {
      NotificationsChannel.register(messenger: registrar.messenger())
    }
  }
}

/// `fireplace/notifications`: the app icon badge, clearing delivered alerts and
/// opening Fireplace's notification settings. See
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
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

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
