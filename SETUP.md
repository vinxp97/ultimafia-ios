# Setup

How to build and run Ultimafia from source. For an overview of the app, see [README.md](README.md).

## Requirements

- A Mac with **Xcode 27** or later (last built with Xcode 27.1).
- Deployment target **26.5** (iOS 26.5, iPadOS 26.5 and macOS 26.5).
- An Apple ID or Apple Developer team, to sign builds for a physical device.
- No third-party packages are needed.

## Project layout

| Path | Contents |
| --- | --- |
| `Ultimafia.xcodeproj` | The Xcode project. This is the source of truth for all platforms. |
| `Ultimafia/` | The app: one SwiftUI target for iPhone, iPad and native macOS (not Mac Catalyst). |
| `UltimafiaWidgets/` | The Live Activity widget extension (iPhone and iPad only). |
| `Package.swift`, `xtool.yml` | An optional SwiftPM/xtool manifest for building the iOS app without Xcode (see below). |
| `Tests/` | Standalone regression checks and fixtures. |

The app bundle ID is `VCCCLLC.Ultimafia` and the widget bundle ID is `VCCCLLC.Ultimafia.Widgets`.

## Clone and open

```sh
git clone https://github.com/vinxp97/ultimafia-mobile.git
cd ultimafia-mobile
open Ultimafia.xcodeproj
```

## Signing with your own team

The project uses automatic signing. To build for a device:

1. Select the **Ultimafia** target, open **Signing & Capabilities**, and choose your own **Team**.
2. Do the same for the **UltimafiaWidgets** target.
3. If Xcode reports that the bundle ID is taken, change it to an identifier you own, such as `com.yourname.ultimafia`. Change the widget to match, such as `com.yourname.ultimafia.Widgets`.

The iOS build uses the Associated Domains (`webcredentials:ultimafia.com`), iCloud Key-Value Store and Declared Age Range capabilities. Under a different bundle ID, those features may need their own configuration or may not work, but the app still builds and runs.

The macOS build is sandboxed and is signed ad hoc for local runs (`CODE_SIGN_IDENTITY = -`), so you don't need a team. It is set up to run locally, not to be distributed.

## Firebase web key

Sign-in uses ultimafia.com's Firebase **web client** API key, in `Ultimafia/App/Secrets.swift`. That key is a public client identifier, not a credential, and the file is committed, so no setup is needed. `Secrets.swift.template` is a placeholder reference only. Never put real credentials in it or in any doc.

## Running

In Xcode, choose the **Ultimafia** scheme and a run destination:

- **iPhone or iPad Simulator:** pick a simulator (for example iPhone 17 or iPad Pro 13-inch) and press ⌘R.
- **Physical iPhone or iPad:** connect the device, enable Developer Mode on it, select it as the destination and press ⌘R. Signing must be set up as above.
- **Mac:** pick **My Mac** and press ⌘R.

From the command line:

```sh
# iPhone simulator
xcodebuild -project Ultimafia.xcodeproj -scheme Ultimafia \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# iPad simulator
xcodebuild -project Ultimafia.xcodeproj -scheme Ultimafia \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build

# Native macOS
xcodebuild -project Ultimafia.xcodeproj -scheme Ultimafia \
  -destination 'platform=macOS,arch=arm64' build
```

## Debug launch arguments

DEBUG builds accept these launch arguments. Add them under **Product › Scheme › Edit Scheme › Run › Arguments**, or pass them with `xcrun simctl launch`. They are useful for screenshots and for testing without an account:

| Argument | Effect |
| --- | --- |
| `-UMNoSession` | Stay signed out. Never resume a saved session or reconnect to a game. |
| `-UMNoKeychain` | Never touch the keychain, so no access prompts. |
| `-UMDiagReplay` | Open a synthetic game with no network and no account, and play it through Day 1, Night 1 and Day 2. |
| `-UMDiagHistory` | Use with `-UMDiagReplay` to deliver the backlog as one history event, like joining a running game. |
| `-UMDiagWidth <pt> [compact\|regular]` | Approximate a Split View or Slide Over width on iPad. |
| `-UMDiagMessages public\|dms\|thread\|new\|settings` | Show the Messages screens with sample data. |
| `-UMDiagLongChat` | Load a long sample transcript, to check that chat scrolls to the newest line. |
| `-UMDiagShell play\|messages\|game\|you` | Mac only. Show the full Mac window with demo data. |
| `-UMMacSnapshot <path.png> [seconds]` | Mac only. Save the main window to a PNG inside the app's sandbox container. |

## Optional: build the iOS app with xtool (Linux/WSL)

[xtool](https://github.com/xtool-org/xtool) can build the iOS app without Xcode, using `Package.swift` and `xtool.yml`. Tested with xtool 1.21.0 on Ubuntu in WSL.

```sh
xtool setup                                  # one-time Apple sign-in and SDK setup
xtool dev build --configuration release --ipa
xtool dev run                                # build and install to a connected iPhone
```

Notes:

- The xtool build uses the bundle ID `com.ue2020.ultimafia.dev` from `xtool.yml`. It installs as a separate app under your team.
- The Xcode entitlements are not applied, so Associated Domains, iCloud Key-Value Store and Declared Age Range are unavailable in this build.
- The `Assets.xcassets` catalog is excluded, because xtool 1.21.0 can't build asset catalogs under WSL. As a result, the catalog icons, the logos and the trophy art are missing.
- xtool sets the app icon from `AppIcon-1024.png` instead.
- `Sounds`, `Fonts`, `RoleIcons`, the privacy manifest and `UMTerminology.json` are still bundled.
- Under WSL, USB device forwarding may need the usbmuxd setup described in [xtool issue #19](https://github.com/xtool-org/xtool/issues/19).
