// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "CutTools", platforms: [.macOS(.v14)], products: [.executable(name: "CutTools", targets: ["CutTools"])], targets: [.executableTarget(name: "CutTools"), .testTarget(name: "CutToolsTests", dependencies: ["CutTools"])])
