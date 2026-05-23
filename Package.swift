// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AppExperienceKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "AppExperienceKit",
            targets: ["AppExperienceKit"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/optimizely/swift-sdk.git", from: "5.1.1")
    ],
    targets: [
        .target(
            name: "AppExperienceKit",
            dependencies: [
                .product(name: "Optimizely", package: "swift-sdk")
            ]
        ),
        .testTarget(
            name: "AppExperienceKitTests",
            dependencies: ["AppExperienceKit"]
        )
    ]
)
