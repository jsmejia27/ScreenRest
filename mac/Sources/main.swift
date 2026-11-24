import AppKit

// ScreenRest for macOS: entry point.
//   --demo                 eye break every 30 s, stretch every 90 s, ignores shift hours (separate stats file)
//   --make-iconset <dir>   writes the app icon PNGs (used by build.sh)

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--make-iconset"), i + 1 < args.count {
    IconFactory.writeIconset(to: URL(fileURLWithPath: args[i + 1]))
    exit(0)
}

let demo = args.contains("--demo")
L.set(Settings.load().language)

let app = NSApplication.shared

if let i = args.firstIndex(of: "--selftest"), i + 1 < args.count {
    app.setActivationPolicy(.accessory)
    let t = SelfTest(out: URL(fileURLWithPath: args[i + 1]))
    app.delegate = t
    app.run()
    exit(0)
}

if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
    app.setActivationPolicy(.accessory) // may become active (invisibly) so controls render in active colours
    MainActor.assumeIsolated { // top-level code runs on the main thread
        Snapshot.run(URL(fileURLWithPath: args[i + 1]), lang: i + 2 < args.count ? args[i + 2] : "en")
    }
    exit(0)
}

// Single instance (a second copy started with `open -n` or from the terminal).
if let id = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != getpid() }) {
    let a = NSAlert()
    a.messageText = "ScreenRest"
    a.informativeText = L.t("ScreenRest is already running. Look for the eye icon in the menu bar at the top of the screen.",
                            "Tumatakbo na ang ScreenRest. Hanapin ang icon na mata sa menu bar sa itaas ng screen.")
    activateApp()
    a.runModal()
    exit(0)
}

app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
let delegate = AppDelegate(demo: demo)
app.delegate = delegate
app.run()
