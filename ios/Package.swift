// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "FireplacePreviewTests",
  platforms: [.macOS(.v12)],
  targets: [
    .target(name: "PreviewCore", path: "NotificationService/Core"),
    .target(name: "PreviewNetworking", path: "NotificationService/Network"),
    .target(name: "PreviewDiagnostics", path: "NotificationService",
      exclude: ["Core", "Network", "Memory", "Info.plist", "NotificationService.entitlements",
        "NotificationService.swift", "PreviewCoreBridge.swift", "PreviewKeychain.swift",
        "PreviewReadLock.swift", "PreviewREST.swift", "PreviewRunner.swift"],
      sources: ["PreviewDiagnostics.swift"], swiftSettings: [.define("PREVIEW_DIAGNOSTICS")]),
    .testTarget(name: "PreviewCoreTests", dependencies: ["PreviewCore", "PreviewNetworking", "PreviewDiagnostics"], path: "PreviewTests",
      resources: [.copy("fixtures")])
  ]
)
