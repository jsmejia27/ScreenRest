import AppKit
import ServiceManagement
import UserNotifications

/// `--selftest <dir>`: drives the real windows on screen (breaks, Settings, Dashboard) through the same
/// code paths as a click or key press, reads the live system checks, and writes report.txt plus a PNG of
/// each window to <dir>. Uses demo stats. Settings.ini may be written by the Settings check, so back it up.
final class SelfTest: NSObject, NSApplicationDelegate {
    private let out: URL
    private var lines: [String] = []
    private var failures = 0

    init(out: URL) { self.out = out }

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        DayStats.demoMode = true
        L.set("en")
        // Start from a run-loop timer, not the main queue, so the buttons' queued actions can run while we wait.
        perform(#selector(runTest), with: nil, afterDelay: 0.2)
    }

    // MARK: helpers

    private func wait(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

    private func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        if !ok { failures += 1 }
        lines.append("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  (\(detail))")")
    }

    private func info(_ name: String, _ value: String) { lines.append("INFO  \(name): \(value)") }

    private func capture(_ w: NSWindow, _ name: String) {
        guard let v = w.contentView?.superview ?? w.contentView else { return }
        let b = v.bounds
        guard let rep = v.bitmapImageRepForCachingDisplay(in: b) else { return }
        v.cacheDisplay(in: b, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent(name + ".png"))
    }

    private func buttons(in v: NSView) -> [NSButton] {
        v.subviews.flatMap { ($0 as? NSButton).map { [$0] } ?? [] } + v.subviews.flatMap { buttons(in: $0) }
    }

    private func key(_ w: NSWindow, code: UInt16, chars: String) {
        guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: w.windowNumber, context: nil, characters: chars,
                                       charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code) else { return }
        w.sendEvent(e)
    }

    final class Box { var result: BreakResult? }

    /// Shows a break, lets it run `seconds`, then ends it with `action`. The box receives the result it reports.
    private func runBreak(_ name: String, kind: BreakKind, steps: [Exercise], opt: BreakOptions,
                          seconds: Double, action: (BreakController) -> Void) -> (Box, BreakController) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let c = BreakController(kind: kind, steps: steps, screen: screen, options: opt)
        let box = Box()
        c.onFinish = { box.result = $0 }
        c.show()
        wait(seconds)
        check("\(name): window on screen above other apps", c.window.isVisible && c.window.level == .screenSaver)
        check("\(name): covers the whole screen", c.window.frame == screen.frame, "\(c.window.frame.size) vs \(screen.frame.size)")
        capture(c.window, "break-\(name)")
        action(c)
        wait(0.6)
        return (box, c)
    }

    // MARK: the test

    @objc private func runTest() {
        lines.append("ScreenRest self-test, \(Date())")
        lines.append("macOS \(ProcessInfo.processInfo.operatingSystemVersionString), screens: \(NSScreen.screens.count)")
        lines.append("")

        // Live system checks
        let idle = Native.idleSeconds()
        check("Idle time readable", idle >= 0, String(format: "%.1f s since last input", idle))
        info("Camera in use", "\(Native.cameraInUse())")
        info("Microphone in use (another app)", "\(Native.microphoneInUse())")
        info("Full-screen app in front", "\(Native.foregroundIsFullScreen())")
        info("Busy reason", Native.isBusy() ?? "none")
        check("Exercise media bundled", Exercise.media("calf_raises.gif") != nil && Exercise.media("calf_raises.wav") != nil)
        if Settings.canManageStartup {
            let st = SMAppService.mainApp.status
            info("Login item status", ["notRegistered", "enabled", "requiresApproval", "notFound"][min(Int(st.rawValue), 3)])
        } else {
            info("Login item", "not available (not running from a .app bundle)")
        }
        let sem = DispatchSemaphore(value: 0)
        var auth = "unknown"
        UNUserNotificationCenter.current().getNotificationSettings { s in
            auth = ["notDetermined", "denied", "authorized", "provisional", "ephemeral"][min(s.authorizationStatus.rawValue, 4)]
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 3)
        info("Notification permission", auth)
        lines.append("")

        // 1. Eye break with voice, ended with Esc (a real key event through the window)
        var opt = BreakOptions()
        opt.sounds = false
        opt.handsOff = false
        let eye = Exercises.eye[0].with(8)
        var (r, c) = runBreak("eye-esc", kind: .eye, steps: [eye], opt: opt, seconds: 2.5) { c in
            check("eye-esc: voice-over playing", c.isVoicePlaying)
            key(c.window, code: 53, chars: "\u{1b}")
        }
        check("eye-esc: Esc skips the break", r.result == .skipped, "result \(String(describing: r.result))")
        check("eye-esc: window closed", !c.window.isVisible)

        // 2. Stretch break, Done button
        (r, c) = runBreak("stretch-done", kind: .stretch, steps: Exercises.stretchRoutine(60), opt: opt, seconds: 2.5) { c in
            let done = buttons(in: c.window.contentView!).first { $0.title == "Done" }
            check("stretch-done: Done button present", done != nil)
            done?.performClick(nil)
        }
        check("stretch-done: Done counts as taken", r.result == .completed, "result \(String(describing: r.result))")

        // 3. Postpone button
        (r, c) = runBreak("postpone", kind: .eye, steps: [eye], opt: opt, seconds: 1.5) { c in
            buttons(in: c.window.contentView!).first { $0.title.hasPrefix("Postpone") }?.performClick(nil)
        }
        check("postpone: Postpone reported", r.result == .postponed, "result \(String(describing: r.result))")

        // 4. Strict mode: no buttons, Esc ignored, the break runs to the end
        var strict = opt
        strict.allowSkip = false
        strict.allowPostpone = false
        (r, c) = runBreak("strict", kind: .eye, steps: [Exercises.eye[1].with(3)], opt: strict, seconds: 1.0) { c in
            check("strict: no Done/Skip/Postpone buttons", buttons(in: c.window.contentView!).isEmpty)
            key(c.window, code: 53, chars: "\u{1b}")
            check("strict: Esc ignored", !c.isFinished)
        }
        wait(3.5)
        check("strict: break completes on its own", r.result == .completed, "result \(String(describing: r.result))")

        // 5. Countdown runs and finishes by itself (non-strict, short)
        (r, c) = runBreak("countdown", kind: .eye, steps: [Exercises.eye[2].with(3)], opt: opt, seconds: 0.5) { _ in }
        wait(3.5)
        check("countdown: completes on its own after 3 s", r.result == .completed, "result \(String(describing: r.result))")
        lines.append("")

        // 6. Settings window: real panes, live change applies to the model
        let s = Settings.load()
        let settings = SettingsWindowController(s)
        settings.present()
        wait(1.0)
        check("Settings: window on screen", settings.window?.isVisible == true)
        check("Settings: no minimize/zoom (HIG)", settings.window?.styleMask.contains(.miniaturizable) == false)
        if let tabs = settings.window?.contentViewController as? NSTabViewController {
            check("Settings: four toolbar panes", tabs.tabViewItems.count == 4)
            for (i, n) in ["general", "schedule", "breaks", "smart"].enumerated() {
                tabs.selectedTabViewItemIndex = i
                wait(0.8)
                capture(settings.window!, "settings-\(n)")
            }
        }
        let before = s.microIntervalMin
        settings.model.b(\.microIntervalMin).wrappedValue = before + 5
        check("Settings: change applies immediately", s.microIntervalMin == before + 5)
        settings.model.b(\.microIntervalMin).wrappedValue = before
        settings.window?.close()

        // 7. Dashboard window
        let dash = DashboardWindowController(range: 7, today: { DayStats.loadToday() }, checkInEnabled: { true }, onCheckIn: {})
        dash.present()
        wait(1.5)
        check("Dashboard: window on screen", dash.window?.isVisible == true)
        check("Dashboard: has insights", !dash.model.insights.isEmpty, "\(dash.model.insights.count)")
        capture(dash.window!, "dashboard")
        dash.window?.close()

        lines.append("")
        lines.append(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECK(S) FAILED")
        try? (lines.joined(separator: "\n") + "\n").write(to: out.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }
}
