// swift-tools-version: 5.9
// Apple platforms are declared below. Linux is supported too: URLSession lives in
// FoundationNetworking there, imported with `#if canImport(FoundationNetworking)`.

import PackageDescription

let package = Package(
    name: "CoworkingView",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6),
    ],
    products: [
        .library(name: "CoworkingView", targets: ["CoworkingView"]),
    ],
    targets: [
        .target(name: "CoworkingView"),
        .testTarget(
            name: "CoworkingViewTests",
            dependencies: ["CoworkingView"],
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
