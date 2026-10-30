// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TokenCoach",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "TokenCoachCore"),
        .executableTarget(name: "spike", dependencies: ["TokenCoachCore"]),
        .executableTarget(name: "TokenCoach", dependencies: ["TokenCoachCore"]),
    ]
)
