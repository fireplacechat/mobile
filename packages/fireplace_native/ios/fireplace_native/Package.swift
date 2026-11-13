// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "fireplace_native",
  platforms: [.iOS("15.0")],
  products: [.library(name: "fireplace-native", targets: ["fireplace_native"])],
  dependencies: [.package(name: "FlutterFramework", path: "../FlutterFramework")],
  targets: [
    .binaryTarget(name: "FireplaceCrypto", path: "Frameworks/FireplaceCrypto.xcframework"),
    .target(
      name: "FireplaceCryptoExports", dependencies: ["FireplaceCrypto"],
      publicHeadersPath: "include"
    ),
    .target(
      name: "fireplace_native",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework"),
        "FireplaceCryptoExports"
      ]
    )
  ]
)
