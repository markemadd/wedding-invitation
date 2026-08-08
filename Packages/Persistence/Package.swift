// swift-tools-version: 5.9
import PackageDescription

// Persistence — GRDB models, migrations, DatabaseManager (blueprint Phase 1).
//
// Dependency note: the upstream groue/GRDB.swift package does NOT ship an
// SQLCipher-enabled build via Swift Package Manager (that combination is only
// offered through CocoaPods). The DuckDuckGo-maintained fork exists precisely
// to provide GRDB + bundled SQLCipher as an SPM package, and is what the
// blueprint's "GRDB.swift (with the SQLCipher-enabled build target)" resolves
// to in an SPM-only project. Full-database encryption is the non-negotiable
// requirement here (blueprint Sections 1 and 6), so the fork is the correct
// choice over plain GRDB.
let package = Package(
    name: "Persistence",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Persistence", targets: ["Persistence"])
    ],
    dependencies: [
        // Pinned by COMMIT, deliberately, not by version. This fork inherited
        // all of upstream GRDB's historical tags (v0.x–v6.x, from 2015–2022),
        // which numerically collide with the fork's own release tags
        // (1.x–3.x). A range constraint like from: "3.0.0" therefore matches
        // ancient upstream tags (e.g. v3.7.0 = 2018-era GRDB without
        // SQLCipher, which also fails to compile on Xcode 16), and
        // exact: "3.0.0" is ambiguous because both "3.0.0" (fork release)
        // and "v3.0.0" (2018 upstream) exist. The commit below is the fork's
        // release 3.0.0 — "DuckDuckGo GRDB.swift 3.0.0 (GRDB 7.4.1,
        // SQLCipher 4.7.0)" — the SQLCipher-enabled GRDB the blueprint
        // requires. To upgrade later: pick the new release tag on
        // https://github.com/duckduckgo/GRDB.swift and replace this hash
        // with that tag's commit.
        .package(
            url: "https://github.com/duckduckgo/GRDB.swift.git",
            revision: "46098847eeabdb008f238bef5750a8e64097b6ed"
        )
    ],
    targets: [
        .target(
            name: "Persistence",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence"]
        )
    ]
)
