// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "AudioRouter", platforms: [.macOS("14.2")], targets: [
    .target(name: "AudioBridge", publicHeadersPath: "include", linkerSettings: [.linkedFramework("CoreAudio")]),
    .executableTarget(name: "AudioRouter", dependencies: ["AudioBridge"], linkerSettings: [.linkedFramework("CoreAudio"), .linkedFramework("AppKit")])
], swiftLanguageModes: [.v5])
