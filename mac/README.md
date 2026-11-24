# ScreenRest for macOS

A native port of ScreenRest (Swift + AppKit) for macOS 13 Ventura and later, on Apple silicon and Intel. It lives in the menu bar and has the same features as the Windows app: eye and stretch breaks with video and voice, shift schedule and lunch, idle detection, holding breaks during calls, the hands-off check, strict mode, daily check-in, English and Tagalog.

The Mac version also has its own native touches: a System Settings-style **Settings** window (toolbar panes, changes apply as you make them, live summaries such as how many breaks a shift gives you) and a **Dashboard** (menu bar → Dashboard…, ⌘D) with today / 7 / 30-day summary cards, charts of breaks and check-in ratings, and short insights worked out from your own history, including the time of day you skip breaks most. From the Dashboard you can export a one-page **PDF for your eye doctor**. Optional extras: **Use my calendar** (breaks wait during meetings, and a stretch break due during one moves to just before it) and a **countdown to the next break** in the menu bar. All of it follows light and dark mode.

Focus modes aren't detected yet: macOS only shares Focus status with apps that have Apple's Communication Notifications entitlement, which needs a Developer ID build. A desktop widget likewise needs a WidgetKit extension built and signed in Xcode.

## Build

Only the Xcode Command Line Tools are needed (`xcode-select --install`), no Xcode project.

```bash
./mac/build.sh
```

This writes `mac/build/ScreenRest.app`, a universal binary with the exercise videos and voice-overs from `media/` bundled inside. Drag it to `/Applications` and open it.

```bash
./mac/build.sh --package
```

This also writes `dist/ScreenRest-<version>-mac.zip` and `.dmg` and prints their SHA-256 checksums. For a quicker one-architecture build while developing, set `ARCHS=arm64`.

The app is signed ad hoc, not notarized. A copy downloaded from the internet is blocked by Gatekeeper the first time it opens ("can't be opened" or "Apple could not verify..."). Click **Done**, then go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. You only do this once. On macOS 13 and 14, Control-click the app and choose **Open** also works; macOS 15 and later removed that shortcut.

Ready-made downloads are on the [Releases page](https://github.com/jsmejia27/ScreenRest/releases/latest) (`ScreenRest-x.y.z-mac.dmg` and `.zip`).

## Signing and notarizing

Notarized builds open without Gatekeeper's warning. This needs a paid Apple Developer account ($99 a year) and its **Developer ID Application** certificate.

**On your Mac**, once:

```bash
xcrun notarytool store-credentials screenrest --apple-id you@example.com --team-id TEAMID
```

(It asks for an app-specific password, made at account.apple.com → Sign-In and Security.) Then each release:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=screenrest VERSION=1.2.0 ./mac/build.sh --package
```

This signs with the hardened runtime and `ScreenRest.entitlements` (calendar access only), notarizes the disk image, and staples the ticket to the dmg and the app. `SIGN_IDENTITY=-` signs ad hoc with the hardened runtime, handy for checking that everything still works before you have a certificate.

**On GitHub**, add these repository secrets and the Mac job in `.github/workflows/build.yml` signs every build and notarizes release tags:

| Secret | What it is |
|---|---|
| `MACOS_CERT_P12` | The Developer ID Application certificate and key exported from Keychain Access as .p12, then base64-encoded (`base64 -i cert.p12 \| pbcopy`) |
| `MACOS_CERT_PASSWORD` | The password you chose when exporting the .p12 |
| `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` | Your Apple ID, team ID and an app-specific password |

Pushing a tag such as `v1.2.0` then builds Windows and Mac, notarizes the Mac files, and publishes one release with a shared `SHA256SUMS.txt`.

## Live self-test

```bash
mac/build/ScreenRest.app/Contents/MacOS/ScreenRest --selftest /tmp/screenrest-selftest
```

Drives the real windows on screen (eye, stretch, postpone and strict-mode breaks, Settings, Dashboard) through the same code paths as clicks and key presses, reads the live system checks (idle time, camera, microphone, full screen, notification permission, login item), and writes `report.txt` plus a PNG of each window. It uses demo stats; back up `settings.ini` first, since the Settings check saves it.

## Try it

```bash
open mac/build/ScreenRest.app --args --demo
```

Demo mode gives an eye break every 30 s and a stretch break every 90 s, ignores shift hours, and keeps its own `stats-demo.csv`.

`ScreenRest --snapshot <dir> [en|tl]` (the binary inside `Contents/MacOS`) renders every window to PNG without showing anything on screen. It's useful for screenshots and layout checks.

## How the Windows features map to macOS

| Windows | macOS |
|---|---|
| System-tray icon, balloon tips | Menu bar icon (teal / grey / orange) and notifications. If notifications are off for ScreenRest, a small toast shows under the menu bar instead. |
| `GetLastInputInfo` idle time | `CGEventSource` seconds since last input. No permission needed. |
| Camera/mic in use (registry ConsentStore) | CoreMediaIO "device running somewhere" for the camera. CoreAudio per-process input for the mic (macOS 14.2+), or input-only devices on older versions. No camera or mic access is requested. |
| Presentation / full-screen app | The frontmost app has a window that covers a whole display (slideshows, full-screen video and games). |
| Full-screen break on every monitor | Borderless windows above everything, the menu bar and full-screen Spaces included. Strict mode also blocks Cmd-Tab during the break. |
| Start with Windows (Run key) | Open at login (`SMAppService`, listed in System Settings > General > Login Items) |
| `%APPDATA%\ScreenRest\` | `~/Library/Application Support/ScreenRest/`, same `settings.ini` and `stats.csv` format, so files can be copied between the two |
| Uninstaller | Drag the app to the Trash. Delete the folder above to remove your data. |

## Source files

| File | Purpose |
|---|---|
| `Sources/main.swift` | Entry point, single instance, `--demo` / `--make-iconset` / `--snapshot` |
| `Sources/StatusApp.swift` | Menu bar item, menu, shift schedule, timers, idle detection (port of `TrayApp.cs`) |
| `Sources/BreakWindow.swift` | Full-screen guided break: video, voice, hands-off check, dim overlay for other screens |
| `Sources/Native.swift` | Idle time; camera, mic and full-screen detection |
| `Sources/SettingsWindow.swift` | Settings: toolbar panes (General, Schedule, Breaks, Smart) with grouped SwiftUI forms; changes apply immediately |
| `Sources/Dashboard.swift` | Dashboard: today / 7 / 30 days, summary cards, Swift Charts, insights from your own history |
| `Sources/HealthWindows.swift` | Daily check-in |
| `Sources/BreakLog.swift` | `breaks.csv`: time, type and result of every break (Mac only; feeds the time-of-day chart and insight) |
| `Sources/CalendarWatch.swift` | Optional calendar awareness: hold breaks during meetings, move a stretch break before one |
| `Sources/ReportPDF.swift` | One-page A4 PDF of the last 30 days for an optometrist (Dashboard → Export PDF) |
| `Sources/SelfTest.swift` | `--selftest`: drives the real windows on screen and reads the live system checks |
| `ScreenRest.entitlements` | Hardened-runtime entitlements for Developer ID signing (calendar access only) |
| `Sources/AppWindows.swift` | Welcome and About windows |
| `Sources/Notifier.swift` | Notifications with toast fallback |
| `Sources/Settings.swift`, `Stats.swift`, `Exercises.swift`, `Lang.swift` | Same models as the Windows app |
| `Sources/IconFactory.swift` | Draws the menu bar icon and app icon in code |
| `Sources/UI.swift`, `Snapshot.swift` | AppKit helpers; offscreen rendering |
| `Info.plist`, `build.sh` | Bundle metadata and build script |
