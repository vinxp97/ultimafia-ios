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
            path: ".",
            exclude: [
                "Ultimafia/Assets.xcassets",
                "Ultimafia/PrivacyInfo.xcprivacy",
                "Ultimafia/UMTerminology.json",
                "Ultimafia/Sounds",
                "Ultimafia/Fonts",
                "Ultimafia/RoleIcons",
                "Ultimafia/Ultimafia.entitlements",
                "Ultimafia/Ultimafia-iOS.entitlements",
            ],
            // Shared/ holds types the app and the widget extension both compile (Live Activity attributes).
            sources: ["Ultimafia", "Shared"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                // Match SWIFT_DEFAULT_ACTOR_ISOLATION from the Xcode target.
                .unsafeFlags(["-default-isolation", "MainActor"]),
            ]
        ),
    ]
)
