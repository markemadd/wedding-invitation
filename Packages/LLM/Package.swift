// swift-tools-version: 5.9
import PackageDescription

// LLM — MLX wrapper and prompt templates (Phase 5).
//
// MLX Swift is deliberately NOT a dependency yet. Blueprint Phase 0's
// watch-out is explicit: add MLX exactly when the phase that needs it
// arrives (Phase 5), because it adds real build time and app size. The
// module shell exists now so the dependency graph and folder structure are
// final; the mlx-swift package lands here in Phase 5.
let package = Package(
    name: "LLM",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "LLM", targets: ["LLM"])
    ],
    targets: [
        .target(name: "LLM"),
        .testTarget(name: "LLMTests", dependencies: ["LLM"])
    ]
)
