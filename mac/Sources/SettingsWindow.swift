import AppKit

/// Settings window (port of SettingsForm.cs), laid out in two columns.
final class SettingsController: BaseWindowController {
    var saved: (() -> Void)?
    private let s: Settings

    private let cmbLang = NSPopUpButton()
    private let dtStart: NSDatePicker, dtEnd: NSDatePicker, dtLunchS: NSDatePicker, dtLunchE: NSDatePicker
    private var days: [NSButton] = []
    private let chkLunch, chkStrict, chkSounds, chkStartup, chkBlink, chkVoice, chkDefer, chkHandsOff, chkCheckIn: NSButton
    private let nMicroI, nMicroD, nLongI, nLongD, nWarn, nPostMax, nPostMin, nIdle, nBlink: NumField

    init(_ settings: Settings) {
        s = settings
        dtStart = timePicker(s.shiftStartMin); dtEnd = timePicker(s.shiftEndMin)
        dtLunchS = timePicker(s.lunchStartMin); dtLunchE = timePicker(s.lunchEndMin)
        func chk(_ title: String, _ on: Bool) -> NSButton {
            let b = NSButton(checkboxWithTitle: title, target: nil, action: nil)
            b.state = on ? .on : .off
            return b
        }
        chkLunch = chk(L.t("Pause reminders during lunch", "I-pause ang paalala tuwing tanghalian"), s.lunchEnabled)
        chkVoice = chk(L.t("Voice guidance (so your eyes can leave the screen)",
                           "Gabay na boses, sa English (para makaalis ang mata sa screen)"), s.voiceGuide)
        chkDefer = chk(L.t("Hold breaks during calls and full-screen apps",
                           "I-hold ang break habang may tawag o full-screen app"), s.deferDuringMeetings)
        chkHandsOff = chk(L.t("Pause the break timer while I keep typing or using the mouse",
                              "I-pause ang timer ng break kapag nagta-type o gumagamit pa ako ng mouse"), s.handsOffCheck)
        chkCheckIn = chk(L.t("End-of-shift check-in (eye blur and energy)",
                             "Check-in sa dulo ng shift (labo ng mata at lakas)"), s.dailyCheckIn)
        chkStrict = chk(L.t("Strict mode: breaks can't be skipped or postponed",
                            "Strict mode: hindi puwedeng laktawan o ipagpaliban ang break"), s.strictMode)
        chkSounds = chk(L.t("Play sounds", "Magpatunog"), s.sounds)
        chkBlink = chk(L.t("Gentle \"blink\" notifications between breaks",
                           "Mahinahong paalalang \"kumurap\" sa pagitan ng breaks"), s.blinkNudges)
        chkStartup = chk(L.t("Open ScreenRest when I log in to my Mac", "Buksan ang ScreenRest pag-log in ko sa Mac"),
                         Settings.startupEnabled)
        nMicroI = NumField(5, 120, s.microIntervalMin); nMicroD = NumField(10, 120, s.microDurationSec)
        nLongI = NumField(15, 180, s.longIntervalMin); nLongD = NumField(1, 20, s.longDurationMin)
        nWarn = NumField(0, 120, s.warningSec); nPostMin = NumField(1, 30, s.postponeMin)
        nPostMax = NumField(0, 10, s.maxPostpones); nIdle = NumField(1, 60, s.idleResetMin)
        nBlink = NumField(5, 60, s.blinkEveryMin)
        super.init(title: L.t("ScreenRest Settings", "ScreenRest Settings"))
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        cmbLang.addItems(withTitles: ["English", "Tagalog"])
        cmbLang.selectItem(at: s.language == "tl" ? 1 : 0)
        for i in 0..<7 {
            let b = NSButton(checkboxWithTitle: L.day(i), target: nil, action: nil)
            b.state = s.workDays[i] ? .on : .off
            days.append(b)
        }

        // Left column: language, shift, break lengths
        let left = Form()
        left.section(L.t("Language", "Wika"))
        left.row(L.t("Language / Wika", "Wika / Language"), cmbLang)
        left.section(L.t("Work shift", "Shift sa trabaho"))
        left.row(L.t("Shift starts", "Simula ng shift"), dtStart)
        left.row(L.t("Shift ends", "Tapos ng shift"), dtEnd)
        left.row(L.t("Work days", "Araw ng trabaho"), hstack(days, spacing: 6))
        left.full(chkLunch)
        left.row(L.t("Lunch", "Tanghalian"), hstack([dtLunchS, label(L.t("to", "hanggang")), dtLunchE]))
        left.section(L.t("Eye break (20-20-20 rule)", "Eye break (20-20-20 rule)"))
        left.row(L.t("Every (minutes)", "Tuwing (minuto)"), nMicroI)
        left.row(L.t("Lasts (seconds)", "Tagal (segundo)"), nMicroD)
        left.section(L.t("Stand-up and stretch break", "Tayo at stretch break"))
        left.row(L.t("Every (minutes)", "Tuwing (minuto)"), nLongI)
        left.row(L.t("Lasts (minutes)", "Tagal (minuto)"), nLongD)

        // Right column: guidance and behaviour
        let right = Form()
        right.section(L.t("Guidance and smart breaks", "Gabay at matalinong breaks"))
        right.full(chkVoice)
        right.full(chkDefer)
        right.full(chkHandsOff)
        right.full(chkCheckIn)
        right.section(L.t("Behaviour", "Kilos ng app"))
        right.row(L.t("Heads-up before stretch break (s)", "Paalala bago ang stretch break (s)"), nWarn)
        right.row(L.t("Postpone by (minutes)", "Ipagpaliban nang (minuto)"), nPostMin)
        right.row(L.t("Max postpones in a row", "Pinakamaraming sunod na pagpapaliban"), nPostMax)
        right.row(L.t("Away this long counts as a break (min)", "Ganito katagal na wala = break na (min)"), nIdle)
        right.full(chkStrict)
        right.full(chkSounds)
        right.full(chkBlink)
        right.row(L.t("Blink reminder every (min)", "Paalalang kumurap tuwing (min)"), nBlink)
        if Settings.canManageStartup { right.full(chkStartup) }

        let columns = hstack([left.grid, right.grid], spacing: 36)
        columns.alignment = .top

        let reset = ActionButton(L.t("Reset to defaults", "Ibalik sa default")) { [weak self] in self?.apply(Settings()) }
        let cancel = ActionButton(L.t("Cancel", "Kanselahin")) { [weak self] in self?.close() }
        cancel.keyEquivalent = "\u{1b}"
        let save = ActionButton(L.t("Save", "I-save"), primary: true) { [weak self] in self?.onSave() }
        let buttons = hstack([reset, spacer(), cancel, save], spacing: 10)

        let body = vstack([columns, buttons], spacing: 20)
        buttons.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        setContent(padded(body, NSEdgeInsets(top: 18, left: 22, bottom: 18, right: 22)))
    }

    private func apply(_ d: Settings) {
        // Language is a personal choice, so "Reset to defaults" leaves it alone.
        setMinutes(dtStart, d.shiftStartMin); setMinutes(dtEnd, d.shiftEndMin)
        for i in 0..<7 { days[i].state = d.workDays[i] ? .on : .off }
        chkLunch.state = d.lunchEnabled ? .on : .off
        setMinutes(dtLunchS, d.lunchStartMin); setMinutes(dtLunchE, d.lunchEndMin)
        nMicroI.value = d.microIntervalMin; nMicroD.value = d.microDurationSec
        nLongI.value = d.longIntervalMin; nLongD.value = d.longDurationMin
        nWarn.value = d.warningSec; nPostMin.value = d.postponeMin; nPostMax.value = d.maxPostpones
        nIdle.value = d.idleResetMin
        chkStrict.state = d.strictMode ? .on : .off; chkSounds.state = d.sounds ? .on : .off
        chkBlink.state = d.blinkNudges ? .on : .off; nBlink.value = d.blinkEveryMin
        chkVoice.state = d.voiceGuide ? .on : .off
        chkDefer.state = d.deferDuringMeetings ? .on : .off
        chkHandsOff.state = d.handsOffCheck ? .on : .off; chkCheckIn.state = d.dailyCheckIn ? .on : .off
    }

    private func warn(_ text: String) {
        let a = NSAlert()
        a.messageText = "ScreenRest"
        a.informativeText = text
        a.alertStyle = .warning
        if let w = window { a.beginSheetModal(for: w) } else { a.runModal() }
    }

    private func onSave() {
        window?.makeFirstResponder(nil) // commit a number that is still being typed
        if minutes(dtEnd) <= minutes(dtStart) {
            warn(L.t("The shift has to end after it starts.", "Dapat matapos ang shift pagkatapos nitong magsimula."))
            return
        }
        if chkLunch.state == .on && minutes(dtLunchE) <= minutes(dtLunchS) {
            warn(L.t("Lunch has to end after it starts.", "Dapat matapos ang tanghalian pagkatapos nitong magsimula."))
            return
        }
        s.language = cmbLang.indexOfSelectedItem == 1 ? "tl" : "en"
        s.shiftStartMin = minutes(dtStart); s.shiftEndMin = minutes(dtEnd)
        for i in 0..<7 { s.workDays[i] = days[i].state == .on }
        s.lunchEnabled = chkLunch.state == .on; s.lunchStartMin = minutes(dtLunchS); s.lunchEndMin = minutes(dtLunchE)
        s.microIntervalMin = nMicroI.value; s.microDurationSec = nMicroD.value
        s.longIntervalMin = nLongI.value; s.longDurationMin = nLongD.value
        s.warningSec = nWarn.value; s.postponeMin = nPostMin.value; s.maxPostpones = nPostMax.value
        s.idleResetMin = nIdle.value; s.strictMode = chkStrict.state == .on; s.sounds = chkSounds.state == .on
        s.blinkNudges = chkBlink.state == .on; s.blinkEveryMin = nBlink.value
        s.voiceGuide = chkVoice.state == .on; s.deferDuringMeetings = chkDefer.state == .on
        s.handsOffCheck = chkHandsOff.state == .on; s.dailyCheckIn = chkCheckIn.state == .on
        do {
            try s.save()
        } catch {
            warn(L.t("Couldn't save settings: ", "Hindi na-save ang settings: ") + error.localizedDescription)
            return
        }
        let wantStartup = chkStartup.state == .on
        if Settings.canManageStartup && wantStartup != Settings.startupEnabled {
            do { try Settings.setStartup(wantStartup) } catch {
                Notifier.shared.post("ScreenRest", L.t("Couldn't change the login item: ", "Hindi nabago ang login item: ") +
                                     error.localizedDescription)
            }
        }
        saved?()
        close()
    }
}

/// Two-column label / control grid with section headings.
final class Form {
    let grid = NSGridView()
    init() {
        grid.columnSpacing = 14
        grid.rowSpacing = 7
        grid.rowAlignment = .firstBaseline
    }
    func section(_ title: String) {
        let l = label(title, size: 13, weight: .semibold, color: Brand.teal)
        let r = grid.addRow(with: [l, NSGridCell.emptyContentView])
        r.mergeCells(in: NSRange(location: 0, length: 2))
        if grid.numberOfRows > 1 { r.topPadding = 12 }
    }
    func row(_ text: String, _ control: NSView) {
        grid.addRow(with: [label(text), control])
    }
    func full(_ control: NSView) {
        let r = grid.addRow(with: [control, NSGridCell.emptyContentView])
        r.mergeCells(in: NSRange(location: 0, length: 2))
    }
}
