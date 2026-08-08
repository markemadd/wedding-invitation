// swift-tools-version: 5.9
import PackageDescription

// Budgeting — SalaryAllocationService and category logic (Phase 3).
let package = Package(
    name: "Budgeting",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Budgeting", targets: ["Budgeting"])
    ],
    dependencies: [
        .package(path: "../Persistence")
    ],
    targets: [
        .target(
            name: "Budgeting",
            dependencies: [
                .product(name: "Persistence", package: "Persistence")
            ]
        ),
        .testTarget(name: "BudgetingTests", dependencies: ["Budgeting"])
    ]
)
