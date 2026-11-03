// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Therm2",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Therm2", targets: ["Therm2"])],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.99.2", traits: [])
    ],
    targets: [
        .executableTarget(name: "Therm2", dependencies: ["SwiftTerm"]),
        .testTarget(name: "Therm2Tests", dependencies: ["Therm2"])
    ]
)
