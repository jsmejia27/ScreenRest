import AppKit

enum AppInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.0" }
    static var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "© 2026 Jilbert Mejia. MIT License."
    }
}

/// Shared look for the branded windows (welcome, about): dark panel matching the break screen.
class BrandController: BaseWindowController {
    let body = vstack([], spacing: 0)

    override init(title: String, resizable: Bool = false) {
        super.init(title: title, resizable: resizable)
        window?.appearance = NSAppearance(named: .darkAqua)
        window?.backgroundColor = Brand.bg
        window?.titlebarAppearsTransparent = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func clear() { body.arrangedSubviews.forEach { body.removeArrangedSubview($0); $0.removeFromSuperview() } }

    func add(_ v: NSView, after spacing: CGFloat) {
        body.addArrangedSubview(v)
        body.setCustomSpacing(spacing, after: v)
    }

    func header(_ title: String, _ subtitle: String) -> NSView {
        let logo = NSImageView(image: IconFactory.appIcon(64))
        logo.widthAnchor.constraint(equalToConstant: 64).isActive = true
        logo.heightAnchor.constraint(equalToConstant: 64).isActive = true
        let text = vstack([label(title, size: 24, weight: .semibold, color: .white), label(subtitle, size: 13.5, color: Brand.accent)], spacing: 2)
        return hstack([logo, text], spacing: 14)
    }

    func para(_ text: String, _ color: NSColor) -> NSTextField { label(text, size: 13.5, color: color, wrap: 520) }

    /// Right-aligned row of buttons, spanning the window.
    func buttonRow(_ buttons: [NSView]) -> NSView {
        let row = hstack([spacer()] + buttons, spacing: 10)
        return row
    }

    func finishLayout(_ row: NSView) {
        row.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        if window?.contentView == nil || window?.contentView?.subviews.first !== body {
            setContent(padded(body, NSEdgeInsets(top: 30, left: 30, bottom: 24, right: 30)))
        } else if let v = window?.contentView {
            v.layoutSubtreeIfNeeded()
            window?.setContentSize(v.fittingSize)
        }
    }
}

/// First run: language choice, where the menu bar icon is, the schedule, open at login and a sample break.
final class WelcomeController: BrandController {
    var tryBreak = false, openSettings = false
    var done: ((WelcomeController) -> Void)?
    private let s: Settings
    private var startupChecked = true

    init(_ settings: Settings) {
        s = settings
        super.init(title: "ScreenRest")
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func windowWillClose(_ notification: Notification) {
        if Settings.canManageStartup { try? Settings.setStartup(startupChecked) }
        done?(self)
        super.windowWillClose(notification)
    }

    /// Lays out the whole window in the current language; called again when the language changes.
    private func build() {
        clear()
        window?.title = L.t("Welcome to ScreenRest", "Maligayang pagdating sa ScreenRest")

        // Language picker first, so a Tagalog speaker can switch before reading anything else.
        let lang = hstack([label("Language / Wika:", color: Brand.dim), langButton("English", "en"), langButton("Tagalog", "tl")])
        add(lang, after: 16)
        add(header(L.t("Welcome to ScreenRest", "Maligayang pagdating!"),
                   L.t("Rest your eyes. Move your body. Every workday.", "Ipahinga ang mata. Igalaw ang katawan. Araw-araw sa trabaho.")), after: 18)
        add(para(L.t("ScreenRest runs quietly in the menu bar: look for the green eye icon at the top right of your screen. " +
                     "Click it any time for breaks, stats and settings.",
                     "Tahimik na tumatakbo ang ScreenRest sa menu bar: hanapin ang berdeng icon na mata sa kanang itaas ng screen. " +
                     "I-click ito anumang oras para sa breaks, stats at settings."), Brand.soft), after: 16)

        let plan = NSGridView()
        plan.columnSpacing = 18
        plan.rowSpacing = 8
        func addPlan(_ when: String, _ what: String) {
            plan.addRow(with: [label(when, size: 13.5, weight: .semibold, color: Brand.accent), label(what, size: 13.5, color: Brand.soft, wrap: 360)])
        }
        addPlan(L.t("Your shift", "Iyong shift"),
                String(format: L.t("%@ to %@, %@", "%@ hanggang %@, %@"), Settings.hm(s.shiftStartMin), Settings.hm(s.shiftEndMin), days()))
        addPlan(L.t("Every \(s.microIntervalMin) min", "Tuwing \(s.microIntervalMin) min"),
                L.t("\(s.microDurationSec)-second eye break: look far away (the 20-20-20 rule)",
                    "\(s.microDurationSec) segundong eye break: tumingin sa malayo (ang 20-20-20 rule)"))
        addPlan(L.t("Every \(s.longIntervalMin) min", "Tuwing \(s.longIntervalMin) min"),
                L.t("\(s.longDurationMin)-minute stretch break on your feet, with video and voice",
                    "\(s.longDurationMin) minutong stretch break nang nakatayo, may video at boses"))
        if s.lunchEnabled {
            addPlan(L.t("Lunch", "Tanghalian"),
                    Settings.hm(s.lunchStartMin) + L.t(" to ", " hanggang ") + Settings.hm(s.lunchEndMin) + L.t(": no reminders", ": walang paalala"))
        }
        let planBox = padded(plan, NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16))
        planBox.wantsLayer = true
        planBox.layer?.backgroundColor = Brand.panel.cgColor
        planBox.layer?.cornerRadius = 8
        add(planBox, after: 16)

        add(para(L.t("Breaks wait while you're on a call or in a full-screen app. Everything stays on this Mac.",
                     "Naghihintay ang break habang nasa tawag ka o may full-screen app. Lahat ay nananatili sa Mac na ito."), Brand.dim), after: 10)
        if L.tl { add(para("Paalala: ang gabay na boses ay nasa English pa.", Brand.dim), after: 10) }

        if Settings.canManageStartup {
            let startup = NSButton(checkboxWithTitle: L.t("Open ScreenRest when I log in to my Mac", "Buksan ang ScreenRest pag-log in ko sa Mac"),
                                   target: self, action: #selector(toggleStartup(_:)))
            startup.state = startupChecked ? .on : .off
            add(startup, after: 20)
        }

        let change = ActionButton(L.t("Change my schedule...", "Baguhin ang iskedyul...")) { [weak self] in
            self?.openSettings = true; self?.close()
        }
        let tryIt = ActionButton(L.t("Try a 20-second break", "Subukan ang 20-segundong break")) { [weak self] in
            self?.tryBreak = true; self?.close()
        }
        let go = ActionButton(L.t("Get started", "Simulan na"), primary: true) { [weak self] in self?.close() }
        let row = buttonRow([change, tryIt, go])
        add(row, after: 0)
        finishLayout(row)
    }

    @objc private func toggleStartup(_ sender: NSButton) { startupChecked = sender.state == .on }

    private func langButton(_ text: String, _ code: String) -> NSButton {
        let b = ActionButton(text) { [weak self] in
            guard let self = self, self.s.language != code else { return }
            self.s.language = code
            L.set(code)
            self.build()
        }
        b.controlSize = .regular
        if s.language == code { b.bezelColor = Brand.teal }
        return b
    }

    private func days() -> String {
        let cur = s.workDays.map { $0 ? "1" : "0" }.joined()
        if cur == "0111110" { return L.t("Monday to Friday", "Lunes hanggang Biyernes") }
        return (0..<7).filter { s.workDays[$0] }.map { L.day($0) }.joined(separator: ", ")
    }
}

/// About box: version, copyright, privacy note, data folder.
final class AboutController: BrandController {
    init() {
        super.init(title: L.t("About ScreenRest", "Tungkol sa ScreenRest"))
        add(header("ScreenRest", L.t("Version ", "Bersyon ") + AppInfo.version + " · macOS"), after: 18)
        add(para(L.t("A break coach for people who spend the day at a screen. Eye breaks follow the " +
                     "20-20-20 rule; stretch breaks get you standing, moving and drinking water, guided by video and voice.",
                     "Isang break coach para sa mga buong araw nakaharap sa screen. Ang eye breaks ay sumusunod sa " +
                     "20-20-20 rule; ang stretch breaks ay nagpapatayo, nagpapagalaw at nagpapainom sa iyo ng tubig, may gabay na video at boses."),
                 Brand.soft), after: 12)
        add(para(L.t("Private by design: no account, no ads, no internet connection. Your settings and stats are plain files in ",
                     "Pribado: walang account, walang ads, walang internet. Ang iyong settings at stats ay simpleng files sa ") +
                 DayStats.dataFolder.path, Brand.dim), after: 12)
        add(para(L.t("ScreenRest is a wellness reminder, not medical advice. If your vision stays blurry, see an optometrist.",
                     "Ang ScreenRest ay paalala para sa kalusugan, hindi payong medikal. Kung patuloy na malabo ang paningin mo, magpatingin sa optometrist."),
                 Brand.dim), after: 12)
        add(para(AppInfo.copyright, Brand.soft), after: 4)
        add(para(L.t("Free and open source. Code: github.com/jsmejia27/ScreenRest",
                     "Libre at open source. Code: github.com/jsmejia27/ScreenRest"), Brand.dim), after: 20)
        let data = ActionButton(L.t("Open data folder", "Buksan ang data folder")) { openDataFolder() }
        let ok = ActionButton(L.t("Close", "Isara"), primary: true) { [weak self] in self?.close() }
        let row = buttonRow([data, ok])
        add(row, after: 0)
        finishLayout(row)
    }
    required init?(coder: NSCoder) { fatalError() }
}
