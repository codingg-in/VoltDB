// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoltDB",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/mysql-nio.git", from: "1.7.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "VoltDB",
            dependencies: [
                .product(name: "MySQLNIO", package: "mysql-nio"),
                .product(name: "Collections", package: "swift-collections"),
            ],
            path: "Sources/VoltDB",
            resources: [
                .process("Resources")
            ]
        ),
    ]
)
