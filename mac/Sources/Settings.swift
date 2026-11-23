import Foundation
import ServiceManagement

/// All user settings, persisted to ~/Library/Application Support/ScreenRest/settings.ini
/// (same keys and format as the Windows app's %APPDATA%\ScreenRest\settings.ini).
final class Settings {
    // Shift (minutes after midnight)
    var shiftStartMin = 8 * 60
    var shiftEndMin = 17 * 60
    var workDays = [false, true, true, true, true, true, false] // Sun..Sat
    var lunchEnabled = true
    var lunchStartMin = 12 * 60
    var lunchEndMin = 13 * 60

    // Eye break (20-20-20 rule)
    var microIntervalMin = 20
    var microDurationSec = 20

    // Stretch / stand-up break
    var longIntervalMin = 60
    var longDurationMin = 5

    // Behaviour
    var warningSec = 30
    var strictMode = false
    var maxPostpones = 2
    var postponeMin = 5
    var sounds = true
    var idleResetMin = 5
    var blinkNudges = false
    var blinkEveryMin = 10

    // Guidance and smart behaviour
    var voiceGuide = true          // play media/<slug>.wav for each step
    var videoIntroSec = 8          // Windows only: the Mac app always shows the demo clip (kept so settings.ini stays compatible)
    var deferDuringMeetings = true // hold breaks while camera/mic is in use or a full-screen app is up
    var handsOffCheck = true       // break timer pauses while you keep typing / using the mouse
    var dailyCheckIn = true        // ask eye-blur and energy ratings at the end of each shift

    /// Interface language: "en" (English) or "tl" (Tagalog). Voice-overs stay in English.
    var language = "en"

    static var dir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ScreenRest", isDirectory: true)
    }
    private static var fileURL: URL { dir.appendingPathComponent("settings.ini") }
    static var exists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    // ---- schedule helpers ----
    static func minuteOfDay(_ t: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: t)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
    /// 0 = Sunday ... 6 = Saturday (matches .NET DayOfWeek).
    static func weekdayIndex(_ t: Date) -> Int { Calendar.current.component(.weekday, from: t) - 1 }

    func isWorkDay(_ t: Date) -> Bool { workDays[Settings.weekdayIndex(t)] }
    func inShiftHours(_ t: Date) -> Bool {
        let m = Settings.minuteOfDay(t)
        return isWorkDay(t) && m >= shiftStartMin && m < shiftEndMin
    }
    func inLunch(_ t: Date) -> Bool {
        let m = Settings.minuteOfDay(t)
        return lunchEnabled && m >= lunchStartMin && m < lunchEndMin
    }
    func isActiveTime(_ t: Date) -> Bool { inShiftHours(t) && !inLunch(t) }

    static func hm(_ minutes: Int) -> String { String(format: "%d:%02d", minutes / 60, minutes % 60) }

    // ---- persistence ----
    static func load() -> Settings {
        let s = Settings()
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return s }
        var d: [String: String] = [:]
        for raw in text.components(separatedBy: .newlines) {
            guard let eq = raw.firstIndex(of: "="), eq != raw.startIndex else { continue }
            let k = raw[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            d[k] = raw[raw.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        }
        func int(_ k: String, _ def: Int) -> Int { d[k.lowercased()].flatMap { Int($0) } ?? def }
        func bool(_ k: String, _ def: Bool) -> Bool {
            switch d[k.lowercased()]?.lowercased() { case "true": return true; case "false": return false; default: return def }
        }
        s.shiftStartMin = int("ShiftStartMin", s.shiftStartMin)
        s.shiftEndMin = int("ShiftEndMin", s.shiftEndMin)
        s.lunchEnabled = bool("LunchEnabled", s.lunchEnabled)
        s.lunchStartMin = int("LunchStartMin", s.lunchStartMin)
        s.lunchEndMin = int("LunchEndMin", s.lunchEndMin)
        s.microIntervalMin = int("MicroIntervalMin", s.microIntervalMin)
        s.microDurationSec = int("MicroDurationSec", s.microDurationSec)
        s.longIntervalMin = int("LongIntervalMin", s.longIntervalMin)
        s.longDurationMin = int("LongDurationMin", s.longDurationMin)
        s.warningSec = int("WarningSec", s.warningSec)
        s.strictMode = bool("StrictMode", s.strictMode)
        s.maxPostpones = int("MaxPostpones", s.maxPostpones)
        s.postponeMin = int("PostponeMin", s.postponeMin)
        s.sounds = bool("Sounds", s.sounds)
        s.idleResetMin = int("IdleResetMin", s.idleResetMin)
        s.blinkNudges = bool("BlinkNudges", s.blinkNudges)
        s.blinkEveryMin = int("BlinkEveryMin", s.blinkEveryMin)
        s.voiceGuide = bool("VoiceGuide", s.voiceGuide)
        s.videoIntroSec = int("VideoIntroSec", s.videoIntroSec)
        s.deferDuringMeetings = bool("DeferDuringMeetings", s.deferDuringMeetings)
        s.handsOffCheck = bool("HandsOffCheck", s.handsOffCheck)
        s.dailyCheckIn = bool("DailyCheckIn", s.dailyCheckIn)
        if let lang = d["language"], lang == "en" || lang == "tl" { s.language = lang }
        if let wd = d["workdays"], wd.count == 7 {
            s.workDays = wd.map { $0 == "1" }
        }
        return s
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Settings.dir, withIntermediateDirectories: true)
        func b(_ v: Bool) -> String { v ? "True" : "False" } // same spelling as the Windows build
        let wd = workDays.map { $0 ? "1" : "0" }.joined()
        let lines = [
            "# ScreenRest settings (times are minutes after midnight)",
            "ShiftStartMin=\(shiftStartMin)", "ShiftEndMin=\(shiftEndMin)", "WorkDays=\(wd)",
            "LunchEnabled=\(b(lunchEnabled))", "LunchStartMin=\(lunchStartMin)", "LunchEndMin=\(lunchEndMin)",
            "MicroIntervalMin=\(microIntervalMin)", "MicroDurationSec=\(microDurationSec)",
            "LongIntervalMin=\(longIntervalMin)", "LongDurationMin=\(longDurationMin)",
            "WarningSec=\(warningSec)", "StrictMode=\(b(strictMode))", "MaxPostpones=\(maxPostpones)",
            "PostponeMin=\(postponeMin)", "Sounds=\(b(sounds))", "IdleResetMin=\(idleResetMin)",
            "BlinkNudges=\(b(blinkNudges))", "BlinkEveryMin=\(blinkEveryMin)",
            "VoiceGuide=\(b(voiceGuide))", "VideoIntroSec=\(videoIntroSec)",
            "DeferDuringMeetings=\(b(deferDuringMeetings))", "HandsOffCheck=\(b(handsOffCheck))",
            "DailyCheckIn=\(b(dailyCheckIn))", "Language=\(language)",
        ]
        try (lines.joined(separator: "\n") + "\n").write(to: Settings.fileURL, atomically: true, encoding: .utf8)
    }

    // ---- Open at login (Login Items, macOS 13+) ----

    /// Only a real ScreenRest.app bundle can register itself as a login item.
    static var canManageStartup: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    static var startupEnabled: Bool {
        guard canManageStartup else { return false }
        let st = SMAppService.mainApp.status
        return st == .enabled || st == .requiresApproval
    }

    static func setStartup(_ on: Bool) throws {
        guard canManageStartup else { return }
        if on { try SMAppService.mainApp.register() }
        else if SMAppService.mainApp.status != .notRegistered { try SMAppService.mainApp.unregister() }
    }
}
