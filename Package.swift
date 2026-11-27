// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "keychain-touchid",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "keytap", targets: ["keychain_touchid"])
    ],
    targets: [
        .executableTarget(
            name: "keychain_touchid",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency")
            ],
        ),
        .testTarget(
            name: "keychain_touchidTests",
            dependencies: ["keychain_touchid"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency")
            ],
        ),
    ]
)
