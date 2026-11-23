import Foundation

extension String {
    /// Left-aligned in a field of n characters (like .NET {0,-n}).
    func padR(_ n: Int) -> String { count >= n ? self : self + String(repeating: " ", count: n - count) }
    /// Right-aligned in a field of n characters (like .NET {0,n}).
    func padL(_ n: Int) -> String { count >= n ? self : String(repeating: " ", count: n - count) + self }
}

/// One row per day in ~/Library/Application Support/ScreenRest/stats.csv (stats-demo.csv in --demo mode).
/// Same columns as the Windows app, so the file can be moved between machines.
final class DayStats {
    var date: Date // start of the day
    var eyeTaken = 0, eyeSkipped = 0, stretchTaken = 0, stretchSkipped = 0, postponed = 0, activeSec = 0
    var eyeBlur = 0 // daily check-in, 1 (clear) .. 5 (very blurry); 0 = not answered
    var energy = 0  // daily check-in, 1 (exhausted) .. 5 (great); 0 = not answered

    /// Set by --demo so test runs never touch your real history.
    static var demoMode = false

    private static var fileURL: URL { Settings.dir.appendingPathComponent(demoMode ? "stats-demo.csv" : "stats.csv") }
    private static let header = "date,eye_taken,eye_skipped,stretch_taken,stretch_skipped,postponed,active_sec,eye_blur,energy"

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static var today: Date { Calendar.current.startOfDay(for: Date()) }

    init(date: Date) { self.date = Calendar.current.startOfDay(for: date) }

    var score: Int {
        let total = eyeTaken + eyeSkipped + stretchTaken + stretchSkipped
        return total == 0 ? 100 : Int((100.0 * Double(eyeTaken + stretchTaken) / Double(total)).rounded())
    }
    var checkedIn: Bool { eyeBlur > 0 || energy > 0 }
    var breaksDue: Int { eyeTaken + eyeSkipped + stretchTaken + stretchSkipped }

    func toCsv() -> String {
        [DayStats.dayFormat.string(from: date), "\(eyeTaken)", "\(eyeSkipped)", "\(stretchTaken)", "\(stretchSkipped)",
         "\(postponed)", "\(activeSec)", "\(eyeBlur)", "\(energy)"].joined(separator: ",")
    }

    private static func parse(_ line: String) -> DayStats? {
        let p = line.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: ",")
        guard p.count >= 7, let d = dayFormat.date(from: p[0]) else { return nil }
        let s = DayStats(date: d)
        func n(_ i: Int) -> Int { Int(p[i]) ?? 0 }
        s.eyeTaken = n(1); s.eyeSkipped = n(2); s.stretchTaken = n(3); s.stretchSkipped = n(4)
        s.postponed = n(5); s.activeSec = n(6)
        if p.count >= 9 { s.eyeBlur = n(7); s.energy = n(8) } // older files lack these
        return s
    }

    static func loadAll() -> [DayStats] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return text.components(separatedBy: .newlines).compactMap(parse).sorted { $0.date < $1.date }
    }

    static func loadToday() -> DayStats {
        let t = today
        return loadAll().first { $0.date == t } ?? DayStats(date: t)
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: Settings.dir, withIntermediateDirectories: true)
            var lines = [DayStats.header]
            var written = false
            for s in DayStats.loadAll() {
                if s.date == date { lines.append(toCsv()); written = true } else { lines.append(s.toCsv()) }
            }
            if !written { lines.append(toCsv()) }
            try (lines.joined(separator: "\n") + "\n").write(to: DayStats.fileURL, atomically: true, encoding: .utf8)
        } catch { }
    }

    static var dataFolder: URL { Settings.dir }

    static func duration(_ sec: Int) -> String { String(format: "%dh %02dm", sec / 3600, (sec % 3600) / 60) }

    /// History with today's live numbers swapped in.
    static func history(_ today: DayStats) -> [DayStats] {
        var all = loadAll()
        if let i = all.firstIndex(where: { $0.date == today.date }) { all[i] = today } else { all.append(today) }
        return all
    }

    private static func rating(_ v: Int) -> String { v == 0 ? " -" : " \(v)" }

    static func report(_ today: DayStats) -> String {
        var out: [String] = []
        func line(_ label: String, _ value: String) { out.append((label + ":").padR(21) + value) }
        if demoMode { out.append(L.t("(demo mode: separate test stats)", "(demo mode: hiwalay na test stats)")); out.append("") }
        out.append(L.t("TODAY", "NGAYONG ARAW") + "  (" + L.date(today.date, "EEE d MMM") + ")")
        let taken = L.t(" taken, ", " ginawa, "), skipped = L.t(" skipped", " nilaktawan")
        line(L.t("Active screen time", "Oras sa screen"), duration(today.activeSec))
        line("Eye breaks", "\(today.eyeTaken)\(taken)\(today.eyeSkipped)\(skipped)")
        line("Stretch breaks", "\(today.stretchTaken)\(taken)\(today.stretchSkipped)\(skipped)")
        line(L.t("Postponed", "Ipinagpaliban"), "\(today.postponed)")
        line("Break score", "\(today.score)%")
        line("Check-in", today.checkedIn
             ? String(format: L.t("eye blur %d/5, energy %d/5", "labo ng mata %d/5, lakas %d/5"), today.eyeBlur, today.energy)
             : L.t("not done yet", "hindi pa nagagawa"))
        out.append("")
        out.append(L.t("LAST 14 DAYS                               blur energy",
                       "HULING 14 ARAW                             labo lakas"))
        for row in history(today).reversed().prefix(14) {
            out.append(L.date(row.date, "EEE d MMM").padR(11) + " " + duration(row.activeSec) +
                "  eye " + "\(row.eyeTaken)".padL(2) + "/" + "\(row.eyeTaken + row.eyeSkipped)".padR(2) +
                " str " + "\(row.stretchTaken)".padL(2) + "/" + "\(row.stretchTaken + row.stretchSkipped)".padR(2) +
                " " + "\(row.score)".padL(3) + "%  " + rating(row.eyeBlur) + "   " + rating(row.energy))
        }
        return out.joined(separator: "\n")
    }

    // ------------------------------------------------------------------ weekly summary
    private static func weekStart(_ d: Date) -> Date {
        let diff = (Settings.weekdayIndex(d) + 6) % 7 // Monday = 0
        return Calendar.current.date(byAdding: .day, value: -diff, to: Calendar.current.startOfDay(for: d))!
    }

    private struct WeekTotals {
        var days = 0, active = 0, eyeT = 0, eyeAll = 0, strT = 0, strAll = 0, blurSum = 0, blurN = 0, energySum = 0, energyN = 0
        var best: DayStats?
        var score: Int { let all = eyeAll + strAll; return all == 0 ? 0 : Int((100.0 * Double(eyeT + strT) / Double(all)).rounded()) }
        var avgBlur: String { blurN == 0 ? "-" : String(format: "%.1f", Double(blurSum) / Double(blurN)) }
        var avgEnergy: String { energyN == 0 ? "-" : String(format: "%.1f", Double(energySum) / Double(energyN)) }
    }

    private static func totals(_ all: [DayStats], _ start: Date) -> WeekTotals {
        var w = WeekTotals()
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start)!
        for d in all where d.date >= start && d.date < end {
            if d.activeSec > 0 { w.days += 1 }
            w.active += d.activeSec
            w.eyeT += d.eyeTaken; w.eyeAll += d.eyeTaken + d.eyeSkipped
            w.strT += d.stretchTaken; w.strAll += d.stretchTaken + d.stretchSkipped
            if d.eyeBlur > 0 { w.blurSum += d.eyeBlur; w.blurN += 1 }
            if d.energy > 0 { w.energySum += d.energy; w.energyN += 1 }
            if d.activeSec > 0 && (w.best == nil || d.score > w.best!.score) { w.best = d }
        }
        return w
    }

    static func weeklyReport(_ today: DayStats) -> String {
        let all = history(today)
        let thisStart = weekStart(today.date)
        let t = totals(all, thisStart)
        let l = totals(all, Calendar.current.date(byAdding: .day, value: -7, to: thisStart)!)
        var out: [String] = []
        func row(_ a: String, _ b: String, _ c: String) { out.append(a.padR(25) + b.padL(9) + "   " + c.padL(9)) }
        row(L.t("WEEK OF ", "LINGGO NG ") + L.date(thisStart, "d MMM"), L.t("this week", "ngayon"), L.t("last week", "nakaraan"))
        row(L.t("Days tracked", "Araw na naitala"), "\(t.days)", "\(l.days)")
        row(L.t("Active screen time", "Oras sa screen"), duration(t.active), duration(l.active))
        row(L.t("Eye breaks taken", "Eye breaks na ginawa"), "\(t.eyeT)/\(t.eyeAll)", "\(l.eyeT)/\(l.eyeAll)")
        row(L.t("Stretch breaks taken", "Stretch breaks na ginawa"), "\(t.strT)/\(t.strAll)", "\(l.strT)/\(l.strAll)")
        row("Break score", "\(t.score)%", "\(l.score)%")
        row(L.t("Avg right-eye blur (1-5)", "Labo ng kanang mata (1-5)"), t.avgBlur, l.avgBlur)
        row(L.t("Avg energy (1-5)", "Karaniwang lakas (1-5)"), t.avgEnergy, l.avgEnergy)
        out.append("")
        if let b = t.best {
            out.append(String(format: L.t("Best day: %@ (%d%% of breaks taken)", "Pinakamagandang araw: %@ (%d%% ng breaks ang ginawa)"),
                              L.date(b.date, "EEEE"), b.score))
        }
        if l.days > 0 && t.score > l.score {
            out.append(L.t("You took more of your breaks than last week. Nice!",
                           "Mas marami kang breaks na ginawa kaysa noong nakaraang linggo. Galing!"))
        } else if l.days > 0 && t.score < l.score {
            out.append(L.t("Fewer breaks than last week. Try strict mode next week?",
                           "Mas kaunti ang breaks kaysa noong nakaraang linggo. Subukan ang strict mode sa susunod na linggo?"))
        }
        if t.blurN > 0 && l.blurN > 0 {
            let tb = Double(t.blurSum) / Double(t.blurN), lb = Double(l.blurSum) / Double(l.blurN)
            if tb > lb + 0.4 {
                out.append(L.t("Eye blur is up on last week. Please book that eye exam.",
                               "Lumabo ang mata kumpara noong nakaraang linggo. Magpa-eye exam ka na."))
            } else if tb < lb - 0.4 {
                out.append(L.t("Eye blur is down on last week. Keep resting those eyes.",
                               "Bumuti ang labo ng mata kumpara noong nakaraang linggo. Ituloy ang pagpapahinga ng mata."))
            }
        }
        return out.joined(separator: "\n")
    }
}
