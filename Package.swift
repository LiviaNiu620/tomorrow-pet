// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TomorrowPet",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TomorrowPet", targets: ["TomorrowPet"])
    ],
    targets: [
        .executableTarget(
            name: "TomorrowPet",
            path: "Sources/TomorrowPet"
        ),
        .testTarget(
            name: "TomorrowPetTests",
            dependencies: ["TomorrowPet"],
            path: "Tests/TomorrowPetTests"
        )
    ]
)
