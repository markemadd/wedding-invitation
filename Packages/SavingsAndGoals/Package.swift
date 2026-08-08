// swift-tools-version: 5.9
import PackageDescription

// SavingsAndGoals — goal planner, wishlist, debt, sinking funds (Phase 4).
// Depends on Budgeting because savings math is defined as income minus the
// SalaryAllocationService monthly summary — it never recomputes spending
// aggregates itself.
let package = Package(
    name: "SavingsAndGoals",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "SavingsAndGoals", targets: ["SavingsAndGoals"])
    ],
    dependencies: [
        .package(path: "../Persistence"),
        .package(path: "../Budgeting")
    ],
    targets: [
        .target(
            name: "SavingsAndGoals",
            dependencies: [
                .product(name: "Persistence", package: "Persistence"),
                .product(name: "Budgeting", package: "Budgeting")
            ]
        ),
        .testTarget(name: "SavingsAndGoalsTests", dependencies: ["SavingsAndGoals"])
    ]
)
