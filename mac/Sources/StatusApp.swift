import AppKit

/// Menu bar app: tracks active screen time during the shift and triggers breaks (port of TrayApp.cs).
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let demo: Bool
    private var s: Settings
    private var stats: DayStats
    private var statusItem: NSStatusItem!
    private var tick: Timer?
    private let icoActive = IconFactory.menuBarIcon(IconFactory.brand)
    private let icoPaused = IconFactory.menuBarIcon(IconFactory.paused)
    private let icoDue = IconFactory.menuBarIcon(IconFactory.due)
    private var statusMenuItem: NSMenuItem!
    private var resumeItem: NSMenuItem!

    private var sinceEye = 0, sinceStretch = 0, sinceBlink = 0, saveCounter = 0
    private var eyeWarned = false, stretchWarned = false
    private var eyePostpones = 0, stretchPostpones = 0
    private var pausedUntil = Date.distantPast
    private var wasActive = false, inBreak = false
    private var deferring = false, deferReason = "", freeTicks = 0 // break held while in a call / full-screen app
    private var greetedDate: Date?, summaryDate: Date?

    private var breakCtl: BreakController?
    private var dims: [NSWindow] = []
    private var windows: [BaseWindowController] = []
    private var settingsWC: SettingsWindowController?
    private var dashboardWC: DashboardWindowController?
    private var menuLanguage = ""
    private weak var checkInCtl: CheckInController?

    // ---- intervals (seconds); demo mode shrinks them so you can try it in 2 minutes ----
    private var eyeEvery: Int { demo ? 30 : s.microIntervalMin * 60 }
    private var eyeLength: Int { demo ? 8 : s.microDurationSec }
    private var stretchEvery: Int { demo ? 90 : s.longIntervalMin * 60 }
    private var stretchLength: Int { demo ? 40 : s.longDurationMin * 60 }
    private var stretchWarn: Int { demo ? 10 : s.warningSec }
    private var eyeWarn: Int { min(10, eyeEvery / 3) }

    init(demo: Bool) {
        self.demo = demo
        DayStats.demoMode = demo // demo runs keep their own stats file
        s = Settings.load()
        L.set(s.language)
        stats = DayStats.loadToday()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        Notifier.shared.setup()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = icoActive
        statusItem.button?.toolTip = "ScreenRest"
        buildMenu()

        let t = Timer(timeInterval: 1, target: self, selector: #selector(onTick), userInfo: nil, repeats: true)
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        tick = t

        let mode = demo
            ? L.t("DEMO MODE: eye break every 30 s, stretch every 90 s.", "DEMO MODE: eye break tuwing 30 s, stretch tuwing 90 s.")
            : String(format: L.t("Active %@–%@. Eye break every %d min, stretch break every %d min.",
                                 "Aktibo %@–%@. Eye break tuwing %d min, stretch break tuwing %d min."),
                     Settings.hm(s.shiftStartMin), Settings.hm(s.shiftEndMin), s.microIntervalMin, s.longIntervalMin)
        if !demo && !Settings.exists {
            showWelcome()
        } else {
            balloon(L.t("ScreenRest is running", "Tumatakbo na ang ScreenRest"),
                    mode + L.t(" Click the eye icon in the menu bar for options.", " I-click ang icon na mata sa menu bar para sa mga opsyon."))
        }
        refresh()
    }

    /// Opening the app again (Finder, Spotlight, Launchpad) while it runs: show the menu instead of a second copy.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag && !inBreak { statusItem.button?.performClick(nil) }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) { stats.save() }

    /// A hidden main menu so Cmd-C / Cmd-V / Cmd-W work in the settings and report windows.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appItem.submenu = appMenu
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }

    /// (Re)builds the menu bar menu in the current language.
    private func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusMenuItem = NSMenuItem(title: "ScreenRest", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(L.t("Take an eye break now", "Mag-eye break ngayon")) { [weak self] in self?.startBreak(.eye) })
        menu.addItem(ActionMenuItem(L.t("Take a stretch break now", "Mag-stretch break ngayon")) { [weak self] in self?.startBreak(.stretch) })

        let pause = NSMenuItem(title: L.t("Pause reminders", "I-pause ang mga paalala"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.addItem(ActionMenuItem(L.t("30 minutes (meeting)", "30 minuto (meeting)")) { [weak self] in self?.pauseFor(30 * 60) })
        sub.addItem(ActionMenuItem(L.t("1 hour", "1 oras")) { [weak self] in self?.pauseFor(3600) })
        sub.addItem(ActionMenuItem(L.t("2 hours", "2 oras")) { [weak self] in self?.pauseFor(7200) })
        sub.addItem(ActionMenuItem(L.t("Rest of today", "Buong araw ngayon")) { [weak self] in
            self?.pausedUntil = Calendar.current.date(byAdding: .day, value: 1, to: DayStats.today)!
            self?.refresh()
        })
        pause.submenu = sub
        menu.addItem(pause)
        resumeItem = ActionMenuItem(L.t("Resume reminders", "Ituloy ang mga paalala")) { [weak self] in
            self?.pausedUntil = .distantPast
            self?.refresh()
        }
        menu.addItem(resumeItem)
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(L.t("Dashboard...", "Dashboard..."), key: "d") { [weak self] in self?.showDashboard(range: 1) })
        menu.addItem(ActionMenuItem(L.t("Daily check-in...", "Pang-araw-araw na check-in...")) { [weak self] in self?.showCheckIn(false) })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(L.t("Settings...", "Settings..."), key: ",") { [weak self] in self?.showSettings() })
        menu.addItem(ActionMenuItem(L.t("About ScreenRest", "Tungkol sa ScreenRest")) { [weak self] in self?.present(AboutController()) })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(L.t("Quit ScreenRest", "Isara ang ScreenRest"), key: "q") { [weak self] in self?.exitApp() })
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        statusMenuItem.title = statusText()
        resumeItem.isHidden = !(Date() < pausedUntil)
    }

    /// First run only: introduce the menu bar icon and schedule, then save defaults so it isn't shown again.
    private func showWelcome() {
        let w = WelcomeController(s)
        w.done = { [weak self] w in
            guard let self = self else { return }
            try? self.s.save()
            L.set(self.s.language)
            self.buildMenu()
            DispatchQueue.main.async {
                if w.openSettings { self.showSettings() }
                else if w.tryBreak { self.startBreak(.eye) }
                else {
                    self.balloon(L.t("ScreenRest is running", "Tumatakbo na ang ScreenRest"),
                                 L.t("Click the eye icon in the menu bar for breaks, stats and settings.",
                                     "I-click ang icon na mata sa menu bar para sa breaks, stats at settings."))
                }
                self.refresh()
            }
        }
        present(w)
    }

    // ------------------------------------------------------------------ main loop
    @objc private func onTick() {
        let now = Date()
        if stats.date != DayStats.today { stats.save(); stats = DayStats.loadToday() }

        let active = demo || s.isActiveTime(now)
        if active && !wasActive { onShiftEnter(now) }
        if !active && wasActive && !demo && s.isWorkDay(now) && Settings.minuteOfDay(now) >= s.shiftEndMin { onShiftEnd() }
        wasActive = active

        if inBreak || !active || now < pausedUntil { refresh(); return }

        // Natural break: if you've been away from the keyboard/mouse long enough, that counts.
        let idle = Int(Native.idleSeconds())
        let idleReset = demo ? 20 : s.idleResetMin * 60
        if idle >= idleReset {
            resetEye()
            if idle >= max(idleReset, stretchLength) { resetStretch() }
            refresh()
            return
        }

        sinceEye += 1; sinceStretch += 1; sinceBlink += 1
        stats.activeSec += 1
        saveCounter += 1
        if saveCounter >= 60 { saveCounter = 0; stats.save() }

        let toStretch = stretchEvery - sinceStretch
        let toEye = eyeEvery - sinceEye

        var due: BreakKind?
        if toStretch <= 0 { due = .stretch }
        else if toEye <= 0 {
            // A stretch break is coming soon anyway, so skip this eye break.
            if toStretch <= 120 && !demo { resetEye() } else { due = .eye }
        }
        if let due = due {
            // Never pop up in the middle of a video call, presentation or full-screen video.
            if s.deferDuringMeetings, let why = Native.isBusy() {
                if !deferring {
                    deferring = true
                    deferReason = why
                    let st = due == .stretch
                    balloon(L.t("Break on hold", "Naka-hold ang break"),
                            L.t("It looks like \(why). Your \(st ? "stretch" : "eye") break will start once you're free.",
                                "Mukhang \(why). Magsisimula ang iyong \(st ? "stretch" : "eye") break kapag libre ka na."))
                }
                freeTicks = 0
                refresh()
                return
            }
            if deferring {
                freeTicks += 1
                if freeTicks < 10 { refresh(); return } // 10 s grace after the call ends
            }
            deferring = false; freeTicks = 0
            startBreak(due)
            return
        }

        if !stretchWarned && stretchWarn > 0 && toStretch <= stretchWarn {
            stretchWarned = true
            balloon(L.t("Stretch break in \(toStretch) seconds", "Stretch break sa loob ng \(toStretch) segundo"),
                    L.t("Finish your thought. Time to stand up and move soon.",
                        "Tapusin na ang ginagawa. Malapit na ang oras para tumayo at gumalaw."))
        } else if !eyeWarned && toEye <= eyeWarn && toStretch > toEye + 5 {
            eyeWarned = true
            balloon(L.t("Eye break in \(toEye) seconds", "Eye break sa loob ng \(toEye) segundo"),
                    L.t("Get ready to look away from the screen.", "Humanda nang tumingin palayo sa screen."))
        } else if s.blinkNudges && !demo && sinceBlink >= s.blinkEveryMin * 60 && toEye > 60 && toStretch > 60 {
            sinceBlink = 0
            balloon(L.t("Blink", "Kumurap"),
                    L.t("Blink slowly a few times, and relax your shoulders.",
                        "Kumurap nang dahan-dahan nang ilang beses, at i-relax ang mga balikat."))
        }
        refresh()
    }

    private func onShiftEnter(_ now: Date) {
        resetEye(); resetStretch()
        if demo { return }
        if greetedDate != DayStats.today {
            greetedDate = DayStats.today
            balloon(L.t("Good morning! Your shift has started", "Magandang umaga! Nagsimula na ang shift mo"),
                    L.t("ScreenRest will remind you to rest your eyes and stand up until \(Settings.hm(s.shiftEndMin)).",
                        "Paaalalahanan ka ng ScreenRest na ipahinga ang mata at tumayo hanggang \(Settings.hm(s.shiftEndMin))."))
        } else {
            balloon(L.t("Welcome back", "Maligayang pagbabalik"), L.t("Reminders are on again.", "Bukas na ulit ang mga paalala."))
        }
    }

    private func onShiftEnd() {
        if summaryDate == DayStats.today { return }
        summaryDate = DayStats.today
        stats.save()
        balloon(L.t("Shift done. Time to log off!", "Tapos na ang shift. Oras nang mag-log off!"),
                String(format: L.t("Eye breaks %d/%d · Stretch %d/%d · Score %d%%. Now go outside and look far away.",
                                   "Eye breaks %d/%d · Stretch %d/%d · Score %d%%. Lumabas ka at tumanaw sa malayo."),
                       stats.eyeTaken, stats.eyeTaken + stats.eyeSkipped, stats.stretchTaken,
                       stats.stretchTaken + stats.stretchSkipped, stats.score))
        let lastDay = isLastWorkDayOfWeek(Date())
        if s.dailyCheckIn { showCheckIn(lastDay) } else if lastDay { showWeekly() }
    }

    /// Last ticked work day in a Monday-to-Sunday week (Friday by default).
    private func isLastWorkDayOfWeek(_ d: Date) -> Bool {
        var last = -1
        for i in [1, 2, 3, 4, 5, 6, 0] where s.workDays[i] { last = i }
        return last == Settings.weekdayIndex(d)
    }

    private func showCheckIn(_ thenWeekly: Bool) {
        if let c = checkInCtl { c.present(); return }
        let c = CheckInController(stats)
        checkInCtl = c
        present(c) { [weak self] in if thenWeekly { self?.showWeekly() } }
    }

    /// End of the week: the dashboard opens on the last 7 days.
    private func showWeekly() { showDashboard(range: 7) }

    private func resetEye() { sinceEye = 0; eyeWarned = false; sinceBlink = 0 }
    private func resetStretch() { sinceStretch = 0; stretchWarned = false }

    // ------------------------------------------------------------------ breaks
    private func startBreak(_ kind: BreakKind) {
        if inBreak { return }
        inBreak = true
        statusItem.button?.image = icoDue

        let steps = kind == .eye ? Exercises.eyeBreak(eyeLength) : Exercises.stretchRoutine(stretchLength)
        let postpones = kind == .eye ? eyePostpones : stretchPostpones
        var opt = BreakOptions()
        opt.allowSkip = !s.strictMode
        opt.allowPostpone = !s.strictMode && postpones < s.maxPostpones
        opt.postponeMin = demo ? 1 : s.postponeMin
        opt.sounds = s.sounds
        opt.voice = s.voiceGuide
        opt.handsOff = s.handsOffCheck

        let mouse = NSEvent.mouseLocation
        let target = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        for scr in NSScreen.screens where scr != target {
            let d = makeDimWindow(scr)
            dims.append(d)
            d.orderFrontRegardless()
        }
        let ctl = BreakController(kind: kind, steps: steps, screen: target, options: opt)
        ctl.onFinish = { [weak self] r in self?.endBreak(kind, r) }
        breakCtl = ctl
        ctl.show()
        if s.strictMode {
            // Strict: no Cmd-Tab out of the break. (Dock and menu bar must be hidden for that option.)
            NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching, .disableHideApplication]
        }
    }

    private func endBreak(_ kind: BreakKind, _ r: BreakResult) {
        guard inBreak else { return }
        inBreak = false
        NSApp.presentationOptions = []
        for d in dims { d.orderOut(nil); d.close() }
        dims.removeAll()
        breakCtl = nil

        let postponeSec = (demo ? 1 : s.postponeMin) * 60
        if kind == .eye {
            if r == .postponed {
                sinceEye = max(0, eyeEvery - postponeSec); eyeWarned = false; eyePostpones += 1; stats.postponed += 1
            } else {
                if r == .completed { stats.eyeTaken += 1 } else { stats.eyeSkipped += 1 }
                resetEye(); eyePostpones = 0
            }
        } else {
            if r == .postponed {
                sinceStretch = max(0, stretchEvery - postponeSec); stretchWarned = false; stretchPostpones += 1; stats.postponed += 1
            } else {
                if r == .completed { stats.stretchTaken += 1 } else { stats.stretchSkipped += 1 }
                resetStretch(); resetEye(); stretchPostpones = 0
            }
        }
        stats.save()
        if r == .completed {
            balloon(kind == .eye ? L.t("Eyes rested", "Napahinga ang mata") : L.t("Nice work, you moved!", "Galing, gumalaw ka!"),
                    L.t("Break score today: \(stats.score)%. Keep it up.", "Break score ngayong araw: \(stats.score)%. Ituloy mo lang."))
        }
        refresh()
    }

    // ------------------------------------------------------------------ UI helpers
    private func pauseFor(_ seconds: TimeInterval) { pausedUntil = Date().addingTimeInterval(seconds); refresh() }

    private func statusText() -> String {
        let now = Date()
        if inBreak { return L.t("On a break", "Naka-break") }
        if deferring { return L.t("Break on hold: ", "Naka-hold ang break: ") + deferReason }
        if now < pausedUntil {
            if pausedUntil >= Calendar.current.date(byAdding: .day, value: 1, to: DayStats.today)! {
                return L.t("Paused for the rest of today", "Naka-pause buong araw ngayon")
            }
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return L.t("Paused until ", "Naka-pause hanggang ") + f.string(from: pausedUntil)
        }
        if !demo {
            if !s.isWorkDay(now) { return L.t("Day off, no reminders", "Day off, walang paalala") }
            if s.inShiftHours(now) && s.inLunch(now) { return L.t("Lunch break, enjoy it", "Lunch break, mag-enjoy ka") }
            if !s.inShiftHours(now) {
                return String(format: L.t("Off shift (active %@–%@)", "Wala sa shift (aktibo %@–%@)"),
                              Settings.hm(s.shiftStartMin), Settings.hm(s.shiftEndMin))
            }
        }
        return String(format: L.t("Eye break in %@ · stretch in %@", "Eye break sa %@ · stretch sa %@"),
                      left(eyeEvery - sinceEye), left(stretchEvery - sinceStretch))
    }

    private func left(_ sec: Int) -> String {
        let s = max(0, sec)
        return s >= 60 ? "\(s / 60)m" : "\(s)s"
    }

    private func refresh() {
        guard let button = statusItem?.button else { return }
        button.toolTip = "ScreenRest: " + statusText()
        let now = Date()
        let idleState = now < pausedUntil || (!demo && !s.isActiveTime(now))
        button.image = inBreak ? icoDue : idleState ? icoPaused : icoActive
    }

    private func balloon(_ title: String, _ text: String) { Notifier.shared.post(title, text) }

    private func showDashboard(range: Int) {
        stats.save()
        if let d = dashboardWC { d.present(range: range); return }
        let d = DashboardWindowController(range: range,
                                          today: { [weak self] in self?.stats ?? DayStats.loadToday() },
                                          checkInEnabled: { [weak self] in self?.s.dailyCheckIn ?? true },
                                          onCheckIn: { [weak self] in self?.showCheckIn(false) })
        d.closed = { [weak self] in self?.dashboardWC = nil }
        dashboardWC = d
        d.present()
    }

    /// Settings apply as they change (macOS style), straight into the live Settings object.
    private func showSettings() {
        if let c = settingsWC { c.present(); return }
        let c = SettingsWindowController(s)
        menuLanguage = s.language
        c.model.changed = { [weak self, weak c] in
            guard let self = self else { return }
            if self.s.language != self.menuLanguage {
                self.menuLanguage = self.s.language
                L.set(self.s.language)
                self.buildMenu()
                self.dashboardWC?.model.reload()
            }
            c?.settingsChanged()
            self.refresh()
        }
        c.closed = { [weak self] in self?.settingsWC = nil; self?.refresh() }
        settingsWC = c
        c.present()
    }

    /// Shows a window and keeps it alive until it closes.
    private func present(_ c: BaseWindowController, onClose: (() -> Void)? = nil) {
        windows.append(c)
        c.closed = { [weak self, unowned c] in
            self?.windows.removeAll { $0 === c }
            onClose?()
        }
        c.present()
    }

    private func exitApp() {
        tick?.invalidate()
        stats.save()
        NSApp.terminate(nil)
    }
}
