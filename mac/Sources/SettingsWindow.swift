import AppKit
import SwiftUI

// Settings window in the macOS style: a fixed toolbar of panes (General, Schedule, Breaks, Smart),
// each a grouped form like System Settings. Changes apply as you make them; there is no Save button.

/// Shares the app's live Settings object with the SwiftUI panes and saves changes to disk.
final class SettingsModel: ObservableObject {
    let s: Settings
    /// Called after every applied change (the app refreshes its menu and status).
    var changed: (() -> Void)?
    private var saveWork: DispatchWorkItem?
    @Published var startupError: String?

    init(_ s: Settings) { self.s = s }

    /// Two-way binding to one setting. Setting it applies the change straight away.
    func b<T>(_ kp: ReferenceWritableKeyPath<Settings, T>) -> Binding<T> {
        Binding(get: { self.s[keyPath: kp] },
                set: { v in
                    self.objectWillChange.send()
                    self.s[keyPath: kp] = v
                    self.applied()
                })
    }

    /// Binding for a "minutes after midnight" setting, shown in a time picker.
    func time(_ kp: ReferenceWritableKeyPath<Settings, Int>) -> Binding<Date> {
        Binding(get: { Calendar.current.date(byAdding: .minute, value: self.s[keyPath: kp],
                                             to: Calendar.current.startOfDay(for: Date()))! },
                set: { d in
                    self.objectWillChange.send()
                    self.s[keyPath: kp] = Settings.minuteOfDay(d)
                    self.applied()
                })
    }

    func day(_ i: Int) -> Binding<Bool> {
        Binding(get: { self.s.workDays[i] },
                set: { v in
                    self.objectWillChange.send()
                    self.s.workDays[i] = v
                    self.applied()
                })
    }

    var startup: Binding<Bool> {
        Binding(get: { Settings.startupEnabled },
                set: { v in
                    self.objectWillChange.send()
                    do { try Settings.setStartup(v); self.startupError = nil }
                    catch { self.startupError = error.localizedDescription }
                })
    }

    var shiftValid: Bool { s.shiftEndMin > s.shiftStartMin }
    var lunchValid: Bool { !s.lunchEnabled || s.lunchEndMin > s.lunchStartMin }

    /// Everything except the language goes back to the defaults.
    func restoreDefaults() {
        let d = Settings(), lang = s.language
        objectWillChange.send()
        s.shiftStartMin = d.shiftStartMin; s.shiftEndMin = d.shiftEndMin; s.workDays = d.workDays
        s.lunchEnabled = d.lunchEnabled; s.lunchStartMin = d.lunchStartMin; s.lunchEndMin = d.lunchEndMin
        s.microIntervalMin = d.microIntervalMin; s.microDurationSec = d.microDurationSec
        s.longIntervalMin = d.longIntervalMin; s.longDurationMin = d.longDurationMin
        s.warningSec = d.warningSec; s.strictMode = d.strictMode; s.maxPostpones = d.maxPostpones
        s.postponeMin = d.postponeMin; s.sounds = d.sounds; s.idleResetMin = d.idleResetMin
        s.blinkNudges = d.blinkNudges; s.blinkEveryMin = d.blinkEveryMin; s.voiceGuide = d.voiceGuide
        s.deferDuringMeetings = d.deferDuringMeetings; s.handsOffCheck = d.handsOffCheck; s.dailyCheckIn = d.dailyCheckIn
        s.language = lang
        applied()
    }

    private func applied() {
        changed?()
        // Save shortly after the last change, and only a schedule that makes sense.
        saveWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self = self, self.shiftValid, self.lunchValid else { return }
            try? self.s.save()
        }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
    }

    /// How a full workday plays out with the current settings (same timer rules as the app).
    var plannedBreaks: (eye: Int, stretch: Int, activeMin: Int) {
        var segments: [Int] = []
        if s.lunchEnabled && s.lunchStartMin > s.shiftStartMin && s.lunchEndMin < s.shiftEndMin && s.lunchEndMin > s.lunchStartMin {
            segments = [s.lunchStartMin - s.shiftStartMin, s.shiftEndMin - s.lunchEndMin]
        } else {
            segments = [max(0, s.shiftEndMin - s.shiftStartMin)]
        }
        let eyeSec = s.microIntervalMin * 60, strSec = s.longIntervalMin * 60
        var eye = 0, stretch = 0
        for seg in segments {
            var sinceEye = 0, sinceStr = 0
            for _ in 0..<(seg * 60) {
                sinceEye += 1; sinceStr += 1
                if strSec - sinceStr <= 0 { stretch += 1; sinceStr = 0; sinceEye = 0 }
                else if eyeSec - sinceEye <= 0 {
                    if strSec - sinceStr > 120 { eye += 1 } // an eye break right before a stretch is skipped
                    sinceEye = 0
                }
            }
        }
        return (eye, stretch, segments.reduce(0, +))
    }
}

// MARK: - Window

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var closed: (() -> Void)?
    let model: SettingsModel
    private let tabs = PaneTabs()
    private var languageShown: String

    init(_ settings: Settings) {
        model = SettingsModel(settings)
        languageShown = settings.language
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false) // no minimize/zoom (HIG)
        w.isReleasedWhenClosed = false
        w.toolbarStyle = .preference
        super.init(window: w)
        w.delegate = self

        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.crossfade, .allowUserInteraction]
        let panes: [(AnyView, String)] = [
            (AnyView(GeneralPane(m: model)), "gearshape"),
            (AnyView(SchedulePane(m: model)), "calendar"),
            (AnyView(BreaksPane(m: model)), "timer"),
            (AnyView(SmartPane(m: model)), "sparkles"),
        ]
        for (view, symbol) in panes {
            let host = NSHostingController(rootView: view)
            host.sizingOptions = [.preferredContentSize]
            let item = NSTabViewItem(viewController: host)
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            tabs.addTabViewItem(item)
        }
        w.contentViewController = tabs
        updateLabels()
        tabs.fitWindow(animate: false)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Tab names follow the interface language (the panes re-render themselves).
    func updateLabels() {
        let names = [L.t("General", "Pangkalahatan"), L.t("Schedule", "Iskedyul"), L.t("Breaks", "Breaks"), L.t("Smart", "Matalino")]
        for (i, item) in tabs.tabViewItems.enumerated() { item.label = names[i] }
        window?.title = names[max(0, tabs.selectedTabViewItemIndex)]
    }

    /// Called by the app after each change.
    func settingsChanged() {
        if model.s.language != languageShown { languageShown = model.s.language; updateLabels() }
    }

    func present() {
        activateApp()
        if window?.isVisible != true { window?.center() }
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        let c = closed
        closed = nil
        c?()
    }
}

/// Resizes the window to each pane's height, keeping the top edge in place (like System Settings).
final class PaneTabs: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        fitWindow(animate: view.window?.isVisible == true)
    }

    /// A pane grew or shrank (for example a warning appeared under a section).
    override func preferredContentSizeDidChange(for viewController: NSViewController) {
        super.preferredContentSizeDidChange(for: viewController)
        if viewController === tabViewItems[safe: selectedTabViewItemIndex]?.viewController {
            fitWindow(animate: view.window?.isVisible == true)
        }
    }

    func fitWindow(animate: Bool) {
        guard let w = view.window, let vc = tabViewItems[safe: selectedTabViewItemIndex]?.viewController else { return }
        var size = vc.preferredContentSize
        if size.width <= 0 || size.height <= 0, let host = vc as? NSHostingController<AnyView> {
            size = host.sizeThatFits(in: NSSize(width: 520, height: 10_000))
        }
        guard size.width > 0, size.height > 0 else { return }
        var f = w.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        f.origin = NSPoint(x: w.frame.minX, y: w.frame.maxY - f.height)
        w.setFrame(f, display: true, animate: animate)
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: - Shared rows

/// "Every  20 min  [-|+]" row.
struct NumberRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    let unit: String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text("\(value) \(unit)").monospacedDigit().foregroundStyle(.secondary)
                Stepper(title, value: $value, in: range, step: step).labelsHidden()
            }
        }
    }
}

private struct Footnote: View {
    let text: String
    var warning = false
    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: warning ? "exclamationmark.triangle.fill" : "info.circle")
                .foregroundStyle(warning ? Color.orange : Color.secondary)
        }
        .font(.callout)
        .foregroundStyle(warning ? Color.primary : Color.secondary)
    }
}

private extension View {
    /// Fixed-width grouped form, as tall as its content, so each pane sizes the window.
    func paneStyle() -> some View {
        formStyle(.grouped)
            .scrollDisabled(true)
            .frame(width: 520)
            .fixedSize(horizontal: false, vertical: true)
            .tint(Color(nsColor: Brand.teal))
    }
}

/// Work-day button: filled with the brand colour when on, so the choice reads clearly in any window state.
private struct DayChip: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            configuration.label
                .font(.callout.weight(configuration.isOn ? .semibold : .regular))
                .frame(minWidth: 36)
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
                .foregroundStyle(configuration.isOn ? Color.white : Color.primary)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isOn ? Color(nsColor: Brand.teal) : Color.secondary.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

private func hoursText(_ minutes: Int) -> String {
    minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
}

// MARK: - Panes

struct GeneralPane: View {
    @ObservedObject var m: SettingsModel

    var body: some View {
        Form {
            Section {
                Picker(L.t("Language", "Wika"), selection: m.b(\.language)) {
                    Text("English").tag("en")
                    Text("Tagalog").tag("tl")
                }
            } header: {
                Text(L.t("Language", "Wika"))
            } footer: {
                if L.tl { Footnote(text: "Ang gabay na boses ay nasa English pa.") }
            }

            Section(L.t("Sound and voice", "Tunog at boses")) {
                Toggle(L.t("Voice guidance during breaks", "Gabay na boses habang naka-break"), isOn: m.b(\.voiceGuide))
                Toggle(L.t("Play sounds", "Magpatunog"), isOn: m.b(\.sounds))
            }

            Section {
                if Settings.canManageStartup {
                    Toggle(L.t("Open ScreenRest when I log in", "Buksan ang ScreenRest pag-log in ko"), isOn: m.startup)
                } else {
                    LabeledContent(L.t("Open at login", "Buksan pag-log in"),
                                   value: L.t("Move ScreenRest to Applications first", "Ilipat muna ang ScreenRest sa Applications"))
                }
            } header: {
                Text(L.t("Startup", "Pagbukas"))
            } footer: {
                if let e = m.startupError { Footnote(text: e, warning: true) }
                else { Footnote(text: L.t("ScreenRest then covers every shift without you opening it.",
                                          "Sa ganoon, sakop ng ScreenRest ang bawat shift nang hindi mo binubuksan.")) }
            }

            Section {
                LabeledContent(L.t("Settings and history files", "Files ng settings at history")) {
                    Button(L.t("Show in Finder", "Ipakita sa Finder")) { openDataFolder() }
                }
                LabeledContent(L.t("Reset settings", "I-reset ang settings")) {
                    Button(L.t("Restore Defaults", "Ibalik sa Default")) { m.restoreDefaults() }
                }
            } footer: {
                Footnote(text: L.t("Restore Defaults keeps your language. Your history is never changed.",
                                   "Hindi binabago ng Ibalik sa Default ang wika at ang iyong history."))
            }
        }
        .paneStyle()
    }
}

struct SchedulePane: View {
    @ObservedObject var m: SettingsModel

    var body: some View {
        let p = m.plannedBreaks
        let days = m.s.workDays.filter { $0 }.count
        Form {
            Section {
                DatePicker(L.t("Starts", "Simula"), selection: m.time(\.shiftStartMin), displayedComponents: .hourAndMinute)
                DatePicker(L.t("Ends", "Tapos"), selection: m.time(\.shiftEndMin), displayedComponents: .hourAndMinute)
                LabeledContent(L.t("Work days", "Araw ng trabaho")) {
                    HStack(spacing: 4) {
                        ForEach([1, 2, 3, 4, 5, 6, 0], id: \.self) { i in
                            Toggle(L.day(i), isOn: m.day(i)).toggleStyle(DayChip())
                        }
                    }
                }
            } header: {
                Text(L.t("Work shift", "Shift sa trabaho"))
            } footer: {
                if !m.shiftValid {
                    Footnote(text: L.t("The shift has to end after it starts. Changes are saved once it does.",
                                       "Dapat matapos ang shift pagkatapos nitong magsimula. Mase-save ito kapag naayos na."), warning: true)
                } else {
                    Footnote(text: String(format: L.t("Reminders run %@ a day, %d days a week. Outside these hours ScreenRest stays quiet.",
                                                      "Tumatakbo ang paalala nang %@ bawat araw, %d araw bawat linggo. Tahimik ang ScreenRest sa labas ng oras na ito."),
                                          hoursText(p.activeMin), days))
                }
            }

            Section {
                Toggle(L.t("Pause reminders during lunch", "I-pause ang paalala tuwing tanghalian"), isOn: m.b(\.lunchEnabled))
                DatePicker(L.t("From", "Mula"), selection: m.time(\.lunchStartMin), displayedComponents: .hourAndMinute)
                    .disabled(!m.s.lunchEnabled)
                DatePicker(L.t("To", "Hanggang"), selection: m.time(\.lunchEndMin), displayedComponents: .hourAndMinute)
                    .disabled(!m.s.lunchEnabled)
            } header: {
                Text(L.t("Lunch", "Tanghalian"))
            } footer: {
                if !m.lunchValid {
                    Footnote(text: L.t("Lunch has to end after it starts.", "Dapat matapos ang tanghalian pagkatapos nitong magsimula."), warning: true)
                }
            }
        }
        .environment(\.locale, Locale(identifier: "en_GB")) // 24-hour clock
        .paneStyle()
    }
}

struct BreaksPane: View {
    @ObservedObject var m: SettingsModel

    var body: some View {
        let p = m.plannedBreaks
        Form {
            Section {
                NumberRow(title: L.t("Every", "Tuwing"), value: m.b(\.microIntervalMin), range: 5...120, step: 5, unit: "min")
                NumberRow(title: L.t("Lasts", "Tagal"), value: m.b(\.microDurationSec), range: 10...120, step: 5, unit: "s")
            } header: {
                Text(L.t("Eye break · 20-20-20 rule", "Eye break · 20-20-20 rule"))
            }

            Section {
                NumberRow(title: L.t("Every", "Tuwing"), value: m.b(\.longIntervalMin), range: 15...180, step: 5, unit: "min")
                NumberRow(title: L.t("Lasts", "Tagal"), value: m.b(\.longDurationMin), range: 1...20, unit: "min")
            } header: {
                Text(L.t("Stand-up and stretch break", "Tayo at stretch break"))
            } footer: {
                if m.shiftValid {
                    Footnote(text: String(format: L.t("A full shift gives you about %d eye breaks and %d stretch breaks, %d minutes on your feet.",
                                                      "Sa isang buong shift, mga %d eye break at %d stretch break, %d minutong nakatayo."),
                                          p.eye, p.stretch, p.stretch * m.s.longDurationMin))
                }
            }

            Section {
                NumberRow(title: L.t("Heads-up before a stretch break", "Paalala bago ang stretch break"), value: m.b(\.warningSec), range: 0...120, step: 5, unit: "s")
                NumberRow(title: L.t("Postpone by", "Ipagpaliban nang"), value: m.b(\.postponeMin), range: 1...30, unit: "min")
                NumberRow(title: L.t("Postpones in a row", "Sunod-sunod na pagpapaliban"), value: m.b(\.maxPostpones), range: 0...10, unit: "×")
                Toggle(L.t("Strict mode", "Strict mode"), isOn: m.b(\.strictMode))
            } header: {
                Text(L.t("When a break is due", "Kapag oras na ng break"))
            } footer: {
                Footnote(text: m.s.strictMode
                         ? L.t("Breaks can't be skipped or postponed, and Cmd-Tab is blocked until they finish.",
                               "Hindi puwedeng laktawan o ipagpaliban ang break, at naka-block ang Cmd-Tab hanggang matapos.")
                         : L.t("You can still finish early with Done, skip with Esc, or postpone.",
                               "Puwede pa ring tapusin nang maaga gamit ang Tapos na, laktawan gamit ang Esc, o ipagpaliban."))
            }
        }
        .paneStyle()
    }
}

struct SmartPane: View {
    @ObservedObject var m: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle(L.t("Hold breaks during calls and full-screen apps", "I-hold ang break habang may tawag o full-screen app"),
                       isOn: m.b(\.deferDuringMeetings))
                Toggle(L.t("Pause the countdown while I keep typing", "I-pause ang countdown habang nagta-type pa ako"),
                       isOn: m.b(\.handsOffCheck))
                NumberRow(title: L.t("Time away that counts as a break", "Tagal ng pag-alis na bilang break"),
                          value: m.b(\.idleResetMin), range: 1...60, unit: "min")
            } header: {
                Text(L.t("Fit around my work", "Iayon sa trabaho ko"))
            } footer: {
                Footnote(text: L.t("Calls are noticed when the camera or microphone is in use. ScreenRest never turns them on or listens.",
                                   "Napapansin ang tawag kapag ginagamit ang camera o mikropono. Hindi kailanman binubuksan o pinakikinggan ng ScreenRest ang mga ito."))
            }

            Section {
                Toggle(L.t("Gentle blink reminders between breaks", "Mahinahong paalalang kumurap sa pagitan ng breaks"), isOn: m.b(\.blinkNudges))
                NumberRow(title: L.t("Remind me every", "Paalalahanan ako tuwing"), value: m.b(\.blinkEveryMin), range: 5...60, step: 5, unit: "min")
                    .disabled(!m.s.blinkNudges)
                Toggle(L.t("End-of-shift check-in", "Check-in sa dulo ng shift"), isOn: m.b(\.dailyCheckIn))
            } header: {
                Text(L.t("Reminders and check-in", "Paalala at check-in"))
            } footer: {
                Footnote(text: L.t("The check-in asks two quick questions about eye blur and energy. The Dashboard uses them to show whether breaks help.",
                                   "Dalawang mabilis na tanong ang check-in tungkol sa labo ng mata at lakas. Ginagamit ito ng Dashboard para ipakita kung nakakatulong ang breaks."))
            }
        }
        .paneStyle()
    }
}
