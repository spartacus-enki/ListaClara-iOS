// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ListaClaraCore", platforms: [.iOS(.v16), .macOS(.v13)], products: [.library(name: "ListaClaraCore", targets: ["ListaClaraCore"])], targets: [
    .target(name: "ListaClaraCore", path: "Sources/Core"),
    .testTarget(name: "ListaClaraCoreTests", dependencies: ["ListaClaraCore"], path: "Tests")
])
