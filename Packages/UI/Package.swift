// swift-tools-version: 5.9
import PackageDescription

// UI — SwiftUI screens, GlassCard, RadialGauge, theme tokens (Section 2).
// Depends on Persistence for the record types views render (Account,
// Category, Transaction) but never touches DatabaseManager — data always
// arrives through view models in the app target, which keeps every view
// previewable with in-memory fixtures.
let package = Package(
    name: "UI",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "UI", targets: ["UI"])
    ],
    dependencies: [
        .package(path: "../Persistence")
    ],
    targets: [
        .target(
            name: "UI",
            dependencies: [
                .product(name: "Persistence", package: "Persistence")
            ]
        ),
        .testTarget(name: "UITests", dependencies: ["UI"])
    ]
)
