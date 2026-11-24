import AppKit

/// `--snapshot <dir> [en|tl]`: renders every window to PNG without showing it (for docs and layout checks,
/// and for machines where screen recording isn't allowed). Uses demo stats so your real history isn't touched.
enum Snapshot {
    static func run(_ dir: URL, lang: String) {
        DayStats.demoMode = true
        L.set(lang)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let s = Settings.load()
        s.language = lang
        let today = DayStats.loadToday()

        func save(_ view: NSView, _ name: String, bg: NSColor) {
            view.layoutSubtreeIfNeeded()
            let b = view.bounds
            guard b.width > 0, b.height > 0, let rep = view.bitmapImageRepForCachingDisplay(in: b) else { return }
            view.cacheDisplay(in: b, to: rep)
            let out = NSImage(size: b.size)
            out.lockFocus()
            bg.setFill()
            NSRect(origin: .zero, size: b.size).fill()
            NSImage(cgImage: rep.cgImage!, size: b.size).draw(in: NSRect(origin: .zero, size: b.size))
            out.unlockFocus()
            if let tiff = out.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("\(name)-\(lang).png"))
            }
        }
        func win(_ c: BaseWindowController, _ name: String, bg: NSColor = .windowBackgroundColor) {
            guard let v = c.window?.contentView else { return }
            (c.window?.appearance ?? NSApp.effectiveAppearance).performAsCurrentDrawingAppearance {
                save(v, name, bg: bg)
            }
        }

        win(WelcomeController(s), "welcome", bg: Brand.bg)
        win(AboutController(), "about", bg: Brand.bg)
        win(CheckInController(today), "checkin")

        // SwiftUI windows need a real (invisible) window and a moment to lay out.
        func live(_ w: NSWindow, _ name: String) {
            for (mode, look) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                w.appearance = NSAppearance(named: look)
                w.alphaValue = 0
                w.orderFrontRegardless()
                RunLoop.main.run(until: Date().addingTimeInterval(1.0))
                guard let frame = w.contentView?.superview else { continue }
                NSAppearance(named: look)!.performAsCurrentDrawingAppearance {
                    save(frame, "\(name)-\(mode)", bg: look == .aqua ? .white : NSColor(white: 0.12, alpha: 1))
                }
            }
            w.orderOut(nil)
        }
        let settings = SettingsWindowController(s)
        if let tabs = settings.window?.contentViewController as? NSTabViewController {
            for (i, pane) in ["general", "schedule", "breaks", "smart"].enumerated() {
                tabs.selectedTabViewItemIndex = i
                settings.updateLabels()
                live(settings.window!, "settings-" + pane)
            }
        }
        for (r, name) in [(1, "today"), (7, "week"), (30, "month")] {
            let d = DashboardWindowController(range: r, today: { today }, checkInEnabled: { true }, onCheckIn: {})
            live(d.window!, "dashboard-" + name)
        }

        let screen = NSScreen.main ?? NSScreen.screens[0]
        var opt = BreakOptions()
        opt.voice = false
        opt.sounds = false
        let eye = BreakController(kind: .eye, steps: Exercises.eyeBreak(20), screen: screen, options: opt)
        eye.prepareForSnapshot()
        save(eye.window.contentView!, "break-eye", bg: Brand.bg)
        let st = BreakController(kind: .stretch, steps: Exercises.stretchRoutine(300), screen: screen, options: opt)
        st.prepareForSnapshot()
        save(st.window.contentView!, "break-stretch", bg: Brand.bg)
        opt.allowSkip = false
        opt.allowPostpone = false
        let strict = BreakController(kind: .eye, steps: Exercises.eyeBreak(20), screen: screen, options: opt)
        strict.prepareForSnapshot()
        save(strict.window.contentView!, "break-strict", bg: Brand.bg)
    }
}
