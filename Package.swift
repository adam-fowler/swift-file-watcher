// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-file-watcher",
    platforms: [.macOS(.v15)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(name: "FileWatching", targets: ["FileWatching"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-system.git", from: "1.0.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "FileWatching",
            dependencies: [
                .product(name: "SystemPackage", package: "swift-system"),
                .target(name: "CInotify", condition: .when(platforms: [.linux])),
            ]
        ),
        .systemLibrary(name: "CInotify"),
        .testTarget(
            name: "FileWatchingTests",
            dependencies: ["FileWatching"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
