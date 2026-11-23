import Foundation

/// Tiny two-language switch (English / Tagalog). Every user-facing string is written as
/// L.t("English", "Tagalog") so both versions sit side by side in the code (same as the Windows app).
enum L {
    /// True when the interface is in Tagalog (Settings.language == "tl").
    static var tl = false

    static func set(_ code: String) { tl = code.lowercased() == "tl" }
    static var code: String { tl ? "tl" : "en" }

    static func t(_ en: String, _ tl: String) -> String { L.tl ? tl : en }

    /// Date in the interface language, e.g. "Mon 3 Nov" / "Lun 3 Nob". Uses Unicode date patterns (EEE d MMM).
    static func date(_ d: Date, _ format: String) -> String {
        let f = DateFormatter()
        f.locale = tl ? Locale(identifier: "fil_PH") : Locale.current
        f.dateFormat = format
        return f.string(from: d)
    }

    private static let daysEn = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static let daysTl = ["Lin", "Lun", "Mar", "Miy", "Huw", "Biy", "Sab"]
    static func day(_ i: Int) -> String { tl ? daysTl[i] : daysEn[i] }
}
