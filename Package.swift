// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Therm2",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Therm2", targets: ["Therm2"])],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", revision: "a480ce66166c9d23798580c1d4d845434b97d24a", traits: [])
    ],
    targets: [
        .executableTarget(name: "Therm2", dependencies: ["SwiftTerm"]),
        .testTarget(name: "Therm2Tests", dependencies: ["Therm2"])
    ]
)
