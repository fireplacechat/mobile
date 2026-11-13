import Flutter
import Foundation
import FireplaceCryptoExports

public class FireplaceNativePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    fireplace_crypto_ensure_linked()
  }
}
