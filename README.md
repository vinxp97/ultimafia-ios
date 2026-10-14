# Ultimafia (native SwiftUI client)

Multiplatform SwiftUI app (iOS / macOS / visionOS) for ultimafia.com.
Bundle ID `VCCCLLC.Ultimafia`. Xcode 27, deployment target 26.5. No third-party packages.

The xtool development target uses `com.ue2020.ultimafia.dev` from `xtool.yml`; the Xcode project keeps the original bundle ID. This installs as a separate app under your Apple team. Services tied to the original bundle ID (such as OAuth, push notifications, or associated domains) may need separate configuration.

The xtool development target does not apply the Xcode iOS entitlements. Associated Domains, iCloud Key-Value Store, and the declared-age-range capability are unavailable in this development build. The Xcode project retains those entitlements for its normal signed build.

## Build with xtool on Linux/WSL

The Xcode project remains the source of truth for macOS and visionOS. For iOS, the SwiftPM manifest and xtool configuration also expose the app to xtool:

```sh
xtool setup                 # one-time Apple authentication / SDK setup
```

Before building, ensure `Ultimafia/App/Secrets.swift` exists with your own local Firebase web API key. If it is missing, create it from the reference template and fill in your own value:

```sh
cp Secrets.swift.template Ultimafia/App/Secrets.swift
```

Treat your configured `Ultimafia/App/Secrets.swift` as local configuration; do not commit or publish it. The current repository tracks this file, so take care not to stage local credential edits. Preserve an existing configured file instead of overwriting it. The template contains only a placeholder; never copy a real key into the template or README.

After the SDK and Secrets setup, build:

```sh
xtool dev build --configuration release --ipa
```

Tested with xtool **1.21.0** on Ubuntu in WSL.

To build and install directly to a connected iPhone, use `xtool dev run`. USB device forwarding from Windows into WSL may need the Apple Devices/usbmuxd port-forwarding setup described in [xtool issue #19](https://github.com/xtool-org/xtool/issues/19).

The xtool target intentionally excludes the entire `Ultimafia/Assets.xcassets` catalog because xtool 1.21.0 fails to build asset catalogs under WSL. This excludes `AccentColor`, the catalog `AppIcon` (all catalog icon sizes), `AppLogo`, every `Logo-*` seasonal image set (default, halloween, july, pride, thanksgiving, valentines, and winter), and all `Trophy-*` image sets. The Xcode project still includes the full catalog. xtool separately reads `AppIcon-1024.png` through `iconPath` to set the development app icon; it does not bundle the catalog icon set, AppLogo, seasonal logos, trophy art, or AccentColor. The app privacy manifest and `UMTerminology.json` are included as xtool resources. `Sounds`, `Fonts`, and `RoleIcons` are copied into the app bundle; font and role-art lookups check those subdirectories as well as the bundle root.

## Setup on a new Mac

1. `git clone https://github.com/vinxp97/ultimafia-ios.git && cd ultimafia-ios`
2. `open Ultimafia.xcodeproj`
3. Target Ultimafia → Signing & Capabilities → pick your Team (Automatic signing).
4. Build & run.
