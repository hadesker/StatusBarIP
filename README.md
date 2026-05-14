# Status Bar IP

Status Bar IP is a small macOS menu bar utility that displays the current public IP address and local adapter addresses. It is built with SwiftUI for the UI layer and AppKit for precise menu bar behavior.

## Screenshots

### Popover

![Status Bar IP popover](assets/screenshot_popover.png)

### Settings: General

![Status Bar IP general settings](assets/screenshot_general.png)

### Settings: Adapter Display

![Status Bar IP adapter display settings](assets/screenshot_adapter.png)

### Settings: About

![Status Bar IP about settings](assets/screenshot_about.png)

## Features

- Shows the selected IP address in the macOS status bar.
- Optional status bar adapter icon.
- Fetches public IP data from `https://ip.faster.asia/?json=true`.
- Enumerates local network interfaces with `getifaddrs`.
- Classifies adapters as Public IP, Tailscale, LAN, VPN/Tunnel, or Other.
- Left click opens a SwiftUI popover with visible IP addresses.
- Clicking an IP copies it to the clipboard.
- Right click opens a native menu with Settings and Close.
- Settings window includes:
  - General settings for public IP refresh interval, Dock icon visibility, launch at login, and status bar icon visibility.
  - Adapter display settings for ordering and hiding adapters.
  - About page with app metadata and project links.

## Requirements

- macOS 14.0+
- Xcode 16+ or newer
- Swift 6 project settings

## Project Structure

```text
StatusBarIP/
  AppDelegate.swift              AppKit lifecycle, status item, popover, settings window
  StatusBarIPApp.swift           SwiftUI app entry point
  Info.plist                     Bundle metadata and LSUIElement config
  Models/
    IPModels.swift               IP models and adapter classification
  Services/
    AppSettings.swift            UserDefaults-backed settings
    IPStore.swift                Observable app state and refresh orchestration
    LocalIPService.swift         Local adapter enumeration via getifaddrs
    PublicIPService.swift        Public IP fetcher via URLSession
  Views/
    PopoverView.swift            Status item popover UI
    SettingsView.swift           Settings sidebar and panes
  Assets.xcassets/               App icon catalog

StatusBarIPTests/
  StatusBarIPTests.swift         JSON decoding, classification, ordering fallback tests
```

## Build

From the repository root:

```sh
xcodebuild \
  -project StatusBarIP.xcodeproj \
  -scheme StatusBarIP \
  -configuration Debug \
  -derivedDataPath ./DerivedData \
  build
```

The debug app bundle is created at:

```text
DerivedData/Build/Products/Debug/Status Bar IP.app
```

## Binary Release

The release script builds a universal macOS app, signs the app with a Developer ID certificate, notarizes it with Apple, staples the notarization ticket, signs the DMG, notarizes the DMG, and writes checksums.

### 1. Install the Developer ID certificate

In Xcode:

```text
Xcode > Settings > Accounts > Apple ID > Team > Manage Certificates...
```

Create or download:

```text
Developer ID Application
```

Then verify Terminal can see the signing identity:

```sh
security find-identity -v -p codesigning
```

You should see a line like:

```text
Developer ID Application: Hien Nguyen (4Y76Q8W243)
```

The script defaults to `SIGNING_IDENTITY=auto`, which selects the first `Developer ID Application` identity and uses its SHA-1 fingerprint. This avoids ambiguity when the same certificate name exists in both the login and system keychains.

### 2. Configure notarization

Create an app-specific password at:

```text
https://account.apple.com/account/manage
```

Copy [.env.example](.env.example) to `.env` and fill in your local values:

```sh
cp .env.example .env
```

Example `.env`:

```sh
APP_SPECIFIC_PASSWORD=<get https://account.apple.com/account/manage>
APPLE_ID=<your apple id email address>
NOTARY_PROFILE=<your notary profile name>
REQUIRE_NOTARIZATION=1
```

`APPPLE_ID` is also accepted for compatibility if you already used that spelling. `.env` is ignored by git; do not commit app-specific passwords, `.p12`, `.p8`, or provisioning profiles.

When `APP_SPECIFIC_PASSWORD`, `APPLE_ID` or `APPPLE_ID`, and `NOTARY_PROFILE` are present, the script runs:

```sh
xcrun notarytool store-credentials "$NOTARY_PROFILE" \
  --apple-id "$APPLE_ID" \
  --team-id "$DEVELOPMENT_TEAM" \
  --password "$APP_SPECIFIC_PASSWORD" \
  --validate
```

This stores the notary credentials securely in Keychain. After the profile is saved, you can remove `APP_SPECIFIC_PASSWORD` from `.env` if you prefer; future builds can use only `NOTARY_PROFILE`.

### 3. Build the release

From the repository root:

```sh
./scripts/build-release.sh
```

The script builds the `Release` app bundle and creates:

```text
releases/StatusBarIP-<version>-<build>-macOS.zip
releases/StatusBarIP-<version>-<build>-macOS.dmg
releases/StatusBarIP-<version>-<build>-macOS-SHA256SUMS.txt
```

For one-off builds without `.env`, pass values inline:

```sh
APPLE_ID="you@example.com" \
APP_SPECIFIC_PASSWORD="app-specific-password" \
NOTARY_PROFILE="statusbarip-notary" \
REQUIRE_NOTARIZATION=1 \
./scripts/build-release.sh
```

If `NOTARY_PROFILE` is omitted, the script can still create local ad-hoc-signed artifacts, but macOS Gatekeeper will warn users after download.

### 4. Verify the release

Verify the app bundle:

```sh
spctl --assess --type execute -vv \
  "build/release/DerivedData/Build/Products/Release/Status Bar IP.app"
```

Expected result:

```text
accepted
source=Notarized Developer ID
origin=Developer ID Application: Hien Nguyen (4Y76Q8W243)
```

Verify the DMG:

```sh
spctl --assess --type open --context context:primary-signature -vv \
  "releases/StatusBarIP-<version>-<build>-macOS.dmg"
```

Expected result:

```text
accepted
source=Notarized Developer ID
origin=Developer ID Application: Hien Nguyen (4Y76Q8W243)
```

Upload the generated `.dmg`, `.zip`, and checksum file to the GitHub release.

## Test

```sh
xcodebuild \
  -project StatusBarIP.xcodeproj \
  -scheme StatusBarIP \
  -configuration Debug \
  -derivedDataPath ./DerivedData \
  test
```

In sandboxed environments, `xcodebuild test` may fail when Xcode cannot communicate with `testmanagerd`. Run the command from a normal terminal or grant the required permission if your automation environment restricts that service.

## Architecture Notes

`IPStore` is the central observable state object. It owns current entries, public IP response metadata, settings, clipboard copy state, timer refresh, Dock visibility, and Launch at Login state.

`StatusItemController` uses `NSStatusItem` instead of SwiftUI `MenuBarExtra` so left click and right click can be handled differently:

- Left click toggles the SwiftUI `NSPopover`.
- Right click temporarily assigns an `NSMenu` with Settings and Close.

Public IP fetching is implemented with `URLSession`, not shelling out to `curl`. Local adapter enumeration is implemented with `getifaddrs`, with IPv4 prioritized by the service and IPv6 kept when available.

Settings are persisted with `UserDefaults` through `UserDefaultsSettingsStore`:

- `fetchInterval`
- `orderedIDs`
- `hiddenIDs`
- `showDockIcon`
- `showStatusBarIcon`

Launch at Login is managed through `SMAppService.mainApp`.

## Adapter Classification

Adapter classification lives in `AdapterClassifier`:

- Tailscale: interface name contains `tailscale`, is `tailscale0`, or IPv4 is in `100.64.0.0/10`.
- VPN/Tunnel: `utun`, `tun`, `tap`, `ppp`, or names containing `vpn`.
- LAN: private IPv4 ranges or link-local IPv6.
- Other: fallback for unclassified interfaces.

## App Metadata

- Bundle ID: `net.hadesker.statusbarip`
- Product name: `Status Bar IP`
- Minimum macOS version: `14.0`
- App category: Utilities
- Default mode: menu bar app via `LSUIElement`

## Development Tips

- Keep generated files out of git. `DerivedData/`, Xcode user data, `.xcresult`, and build outputs are ignored.
- If the Dock icon or app name looks stale, quit any old running copy and launch the app bundle from the latest `DerivedData` build.
- If adding new settings, update `AppSettings`, `UserDefaultsSettingsStore`, and tests that construct `AppSettings` directly.
- If adding new adapter kinds, update `AdapterKind.defaultOrder`, `AdapterKind.symbolName`, `AdapterKind.tint`, and classification tests.

## Links

- App Store: https://apps.apple.com/us/app/status-bar-ip/id6768105320
- GitHub: https://github.com/hadesker/StatusBarIP
- Author: Hadesker
- Website: https://hadesker.net
