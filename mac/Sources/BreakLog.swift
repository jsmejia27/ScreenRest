import Foundation

/// One row per break in breaks.csv (breaks-demo.csv in --demo mode), next to stats.csv.
/// stats.csv keeps the daily totals in the Windows format; this file adds the time of each break,
/// so the Dashboard can show the time of day you take or skip breaks.
///
///   time,kind,result,planned_sec,taken_sec,paused_sec
///   2026-11-24T14:00:12,stretch,completed,300,300,4
struct BreakEntry {
    let time: Date
    let kind: BreakKind
    let result: BreakResult
    let plannedSec: Int
    let takenSec: Int
    let pausedSec: Int

    var hour: Int { Calendar.current.component(.hour, from: time) }
}

enum BreakLog {
    private static var fileURL: URL { Settings.dir.appendingPathComponent(DayStats.demoMode ? "breaks-demo.csv" : "breaks.csv") }
    private static let header = "time,kind,result,planned_sec,taken_sec,paused_sec"

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss" // local time, like the dates in stats.csv
        return f
    }()

    private static func name(_ k: BreakKind) -> String { k == .eye ? "eye" : "stretch" }
    private static func name(_ r: BreakResult) -> String {
        switch r { case .completed: return "completed"; case .skipped: return "skipped"; case .postponed: return "postponed" }
    }

    static func append(_ e: BreakEntry) {
        do {
            try FileManager.default.createDirectory(at: Settings.dir, withIntermediateDirectories: true)
            let line = [timeFormat.string(from: e.time), name(e.kind), name(e.result),
                        "\(e.plannedSec)", "\(e.takenSec)", "\(e.pausedSec)"].joined(separator: ",") + "\n"
            if let h = try? FileHandle(forWritingTo: fileURL) {
                defer { try? h.close() }
                try h.seekToEnd()
                try h.write(contentsOf: Data(line.utf8))
            } else {
                try (header + "\n" + line).write(to: fileURL, atomically: true, encoding: .utf8)
            }
        } catch { }
    }

    /// Entries from `since` (inclusive) onwards.
    static func load(since: Date) -> [BreakEntry] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line -> BreakEntry? in
            let p = line.split(separator: ",").map(String.init)
            guard p.count >= 6, let t = timeFormat.date(from: p[0]), t >= since else { return nil }
            let kind: BreakKind = p[1] == "eye" ? .eye : .stretch
            let result: BreakResult
            switch p[2] { case "completed": result = .completed; case "skipped": result = .skipped; case "postponed": result = .postponed; default: return nil }
            return BreakEntry(time: t, kind: kind, result: result,
                              plannedSec: Int(p[3]) ?? 0, takenSec: Int(p[4]) ?? 0, pausedSec: Int(p[5]) ?? 0)
        }
    }
}
