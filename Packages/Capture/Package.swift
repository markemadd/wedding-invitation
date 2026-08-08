// swift-tools-version: 5.9
import PackageDescription

// Capture — manual entry, receipt OCR, Apple Pay App Intent, voice (Phase 2).
// Depends on Persistence because every capture path writes Transaction rows
// through the shared TransactionWriter / DatabaseManager, never raw SQLite.
//
// WhisperKit is deliberately NOT a dependency yet: blueprint Phase 0 says to
// add it only if SFSpeechRecognizer proves insufficient for Egyptian Arabic
// during Phase 2 testing — pulling it in early costs build time and app size.
let package = Package(
    name: "Capture",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Capture", targets: ["Capture"])
    ],
    dependencies: [
        .package(path: "../Persistence")
    ],
    targets: [
        .target(
            name: "Capture",
            dependencies: [
                .product(name: "Persistence", package: "Persistence")
            ]
        ),
        .testTarget(
            name: "CaptureTests",
            dependencies: ["Capture"],
            resources: [
                // Real-receipt OCR dumps (geometry + text) produced by
                // Tools/ReceiptProbe.swift — the ground truth the OCR
                // heuristics are tuned and regression-tested against.
                .copy("Fixtures")
            ]
        )
    ]
)
