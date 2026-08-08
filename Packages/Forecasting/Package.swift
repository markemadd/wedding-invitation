// swift-tools-version: 5.9
import PackageDescription

// Forecasting — Monte Carlo engine (Phase 5).
// Depends on SavingsAndGoals for historical monthly savings figures; the
// engine adds simulation on top, it never recomputes savings itself.
let package = Package(
    name: "Forecasting",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Forecasting", targets: ["Forecasting"])
    ],
    dependencies: [
        .package(path: "../SavingsAndGoals"),
        .package(path: "../Persistence")
    ],
    targets: [
        .target(
            name: "Forecasting",
            dependencies: [
                .product(name: "SavingsAndGoals", package: "SavingsAndGoals"),
                .product(name: "Persistence", package: "Persistence")
            ]
        ),
        .testTarget(name: "ForecastingTests", dependencies: ["Forecasting"])
    ]
)
