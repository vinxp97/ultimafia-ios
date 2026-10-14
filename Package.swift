// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Ultimafia",
    platforms: [
        .iOS("26.5"),
    ],
    products: [
        .library(
            name: "Ultimafia",
            targets: ["Ultimafia"]
        ),
    ],
    targets: [
        .target(
            name: "Ultimafia",
            path: "Ultimafia",
            exclude: [
                "Assets.xcassets",
                "PrivacyInfo.xcprivacy",
                "UMTerminology.json",
                "Sounds",
                "Fonts",
                "RoleIcons",
                "Ultimafia.entitlements",
                "Ultimafia-iOS.entitlements",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                // Match SWIFT_DEFAULT_ACTOR_ISOLATION from the Xcode target.
                .unsafeFlags(["-default-isolation", "MainActor"]),
            ]
        ),
    ]
)
