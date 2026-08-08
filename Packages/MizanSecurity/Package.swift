// swift-tools-version: 5.9
import PackageDescription

// MizanSecurity — Keychain wrapper, LAContext gate, backup/export (Phase 1).
//
// Naming note: the blueprint's folder structure calls this module "Security",
// but a Swift module named Security would shadow Apple's Security.framework —
// the very framework the Keychain code inside it must `import Security` from.
// Prefixing the module name avoids that collision; everything else about the
// blueprint's structure is unchanged.
let package = Package(
    name: "MizanSecurity",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "MizanSecurity", targets: ["MizanSecurity"])
    ],
    dependencies: [
        // For DatabaseKeyProviding conformance and session invalidation —
        // security conforms to what persistence needs, never the reverse.
        .package(path: "../Persistence")
    ],
    targets: [
        .target(
            name: "MizanSecurity",
            dependencies: [
                .product(name: "Persistence", package: "Persistence")
            ]
        ),
        .testTarget(name: "MizanSecurityTests", dependencies: ["MizanSecurity"])
    ]
)
