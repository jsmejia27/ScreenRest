# ScreenRest for macOS

A native port of ScreenRest (Swift + AppKit) for macOS 13 Ventura and later, on Apple silicon and Intel. It lives in the menu bar and has the same features as the Windows app: eye and stretch breaks with video and voice, shift schedule and lunch, idle detection, holding breaks during calls, the hands-off check, strict mode, daily check-in, English and Tagalog.

The Mac version also has its own native touches: a System Settings-style **Settings** window (toolbar panes, changes apply as you make them, live summaries such as how many breaks a shift gives you) and a **Dashboard** (menu bar → Dashboard…, ⌘D) with today / 7 / 30-day summary cards, charts of breaks and check-in ratings, and short insights worked out from your own history. Both follow light and dark mode.

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
| `Sources/AppWindows.swift` | Welcome and About windows |
| `Sources/Notifier.swift` | Notifications with toast fallback |
| `Sources/Settings.swift`, `Stats.swift`, `Exercises.swift`, `Lang.swift` | Same models as the Windows app |
| `Sources/IconFactory.swift` | Draws the menu bar icon and app icon in code |
| `Sources/UI.swift`, `Snapshot.swift` | AppKit helpers; offscreen rendering |
| `Info.plist`, `build.sh` | Bundle metadata and build script |
