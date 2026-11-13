// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "FireplacePreviewTests",
  platforms: [.macOS(.v12)],
  targets: [
    .target(name: "PreviewCore", path: "NotificationService/Core"),
    .target(name: "PreviewNetworking", path: "NotificationService/Network"),
    .testTarget(name: "PreviewCoreTests", dependencies: ["PreviewCore", "PreviewNetworking"], path: "PreviewTests",
      resources: [.copy("fixtures")])
  ]
)
