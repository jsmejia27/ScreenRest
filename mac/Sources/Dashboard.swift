import AppKit
import Charts
import Combine
import SwiftUI

// Dashboard: today / 7 days / 30 days at a glance, with summary cards, two charts and short insights
// worked out from your own stats.csv. Replaces the plain-text stats, weekly summary and trend windows.

// MARK: - Numbers

/// Totals for a run of days.
struct PeriodTotals {
    var days = 0, active = 0, eyeT = 0, eyeAll = 0, strT = 0, strAll = 0, postponed = 0
    var blurSum = 0, blurN = 0, energySum = 0, energyN = 0

    init(_ list: [DayStats]) {
        for d in list {
            if d.activeSec > 0 || d.breaksDue > 0 { days += 1 }
            active += d.activeSec
            eyeT += d.eyeTaken; eyeAll += d.eyeTaken + d.eyeSkipped
            strT += d.stretchTaken; strAll += d.stretchTaken + d.stretchSkipped
            postponed += d.postponed
            if d.eyeBlur > 0 { blurSum += d.eyeBlur; blurN += 1 }
            if d.energy > 0 { energySum += d.energy; energyN += 1 }
        }
    }
    var due: Int { eyeAll + strAll }
    /// Share of breaks taken, or nil when no break was due.
    var score: Int? { due == 0 ? nil : Int((100.0 * Double(eyeT + strT) / Double(due)).rounded()) }
    var activePerDay: Int { days == 0 ? 0 : active / days }
    var avgBlur: Double? { blurN == 0 ? nil : Double(blurSum) / Double(blurN) }
    var avgEnergy: Double? { energyN == 0 ? nil : Double(energySum) / Double(energyN) }
}

struct Insight: Identifiable {
    enum Tone { case good, note, watch }
    let id = UUID()
    let tone: Tone
    let symbol: String
    let text: String
}

struct BarPoint: Identifiable {
    let id = UUID()
    let date: Date
    let kind: String
    let count: Int
}

struct HourPoint: Identifiable {
    let id = UUID()
    let hour: Int
    let kind: String
    let count: Int
}

struct RatingPoint: Identifiable {
    let id = UUID()
    let date: Date
    let series: String
    let value: Int
}

final class DashboardModel: ObservableObject {
    /// 1 = today, 7 or 30 days.
    @Published var range = 7 { didSet { recompute() } }
    @Published private(set) var current = PeriodTotals([])
    @Published private(set) var previous = PeriodTotals([])
    @Published private(set) var bars: [BarPoint] = []
    @Published private(set) var ratings: [RatingPoint] = []
    @Published private(set) var insights: [Insight] = []
    @Published private(set) var hours: [HourPoint] = []
    private var entries: [BreakEntry] = []
    @Published private(set) var chartStart = Date()
    @Published private(set) var chartEnd = Date()

    private let liveToday: () -> DayStats
    private var history: [DayStats] = []
    let checkInEnabled: () -> Bool

    init(range: Int, today: @escaping () -> DayStats, checkInEnabled: @escaping () -> Bool) {
        self.range = range
        liveToday = today
        self.checkInEnabled = checkInEnabled
        reload()
    }

    func reload() {
        history = DayStats.history(liveToday())
        recompute()
    }

    // Labels shared by the charts and their colour scales.
    static var eyeLabel: String { L.t("Eye breaks", "Eye breaks") }
    static var stretchLabel: String { L.t("Stretch breaks", "Stretch breaks") }
    static var skippedLabel: String { L.t("Skipped", "Nilaktawan") }
    static var takenLabel: String { L.t("Taken", "Ginawa") }
    static var blurLabel: String { L.t("Eye blur", "Labo ng mata") }
    static var energyLabel: String { L.t("Energy", "Lakas") }

    private func days(back n: Int, offset: Int = 0) -> [DayStats] {
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: -offset, to: DayStats.today)!
        let start = cal.date(byAdding: .day, value: -(n - 1), to: end)!
        return history.filter { $0.date >= start && $0.date <= end }
    }

    private func recompute() {
        let cal = Calendar.current
        current = PeriodTotals(days(back: range))
        previous = PeriodTotals(days(back: range, offset: range))

        // Charts always show at least a week, so "Today" still has some context.
        let span = max(7, range)
        chartEnd = DayStats.today
        chartStart = cal.date(byAdding: .day, value: -(span - 1), to: chartEnd)!
        let shown = days(back: span)
        bars = shown.flatMap { d -> [BarPoint] in
            [BarPoint(date: d.date, kind: Self.eyeLabel, count: d.eyeTaken),
             BarPoint(date: d.date, kind: Self.stretchLabel, count: d.stretchTaken),
             BarPoint(date: d.date, kind: Self.skippedLabel, count: d.eyeSkipped + d.stretchSkipped)]
        }
        ratings = shown.flatMap { d -> [RatingPoint] in
            var r: [RatingPoint] = []
            if d.eyeBlur > 0 { r.append(RatingPoint(date: d.date, series: Self.blurLabel, value: d.eyeBlur)) }
            if d.energy > 0 { r.append(RatingPoint(date: d.date, series: Self.energyLabel, value: d.energy)) }
            return r
        }
        let since = cal.date(byAdding: .day, value: -(range - 1), to: DayStats.today)!
        entries = BreakLog.load(since: since).filter { $0.result != .postponed }
        hours = Dictionary(grouping: entries, by: \.hour).sorted { $0.key < $1.key }.flatMap { h, list -> [HourPoint] in
            [HourPoint(hour: h, kind: Self.takenLabel, count: list.filter { $0.result == .completed }.count),
             HourPoint(hour: h, kind: Self.skippedLabel, count: list.filter { $0.result == .skipped }.count)]
        }
        insights = makeInsights()
    }

    var periodName: String {
        switch range {
        case 1: return L.t("yesterday", "kahapon")
        case 7: return L.t("the previous 7 days", "nakaraang 7 araw")
        default: return L.t("the previous 30 days", "nakaraang 30 araw")
        }
    }

    // MARK: Insights

    private func makeInsights() -> [Insight] {
        var out: [Insight] = []
        let cur = current, prev = previous

        // 1. Break score against the previous period
        if let s = cur.score, let p = prev.score {
            let d = s - p
            if d >= 5 {
                out.append(Insight(tone: .good, symbol: "arrow.up.right.circle.fill",
                                   text: String(format: L.t("You took more of your breaks: %d%%, up %d points on %@.",
                                                            "Mas marami kang breaks na ginawa: %d%%, tumaas nang %d puntos kumpara sa %@."), s, d, periodName)))
            } else if d <= -5 {
                out.append(Insight(tone: .watch, symbol: "arrow.down.right.circle.fill",
                                   text: String(format: L.t("Your break score slipped to %d%%, down %d points on %@. Strict mode can help.",
                                                            "Bumaba ang break score sa %d%%, %d puntos mula sa %@. Makakatulong ang strict mode."), s, -d, periodName)))
            } else {
                out.append(Insight(tone: .note, symbol: "equal.circle.fill",
                                   text: String(format: L.t("Steady: you took %d%% of your breaks, about the same as %@.",
                                                            "Tuloy-tuloy: %d%% ng breaks ang ginawa mo, halos kapareho ng %@."), s, periodName)))
            }
        }

        // 2. Streak of good days (only days with breaks due count; weekends don't break it)
        var streak = 0
        for d in history.reversed() where d.breaksDue > 0 {
            if d.score >= 80 { streak += 1 } else { break }
        }
        if streak >= 2 {
            out.append(Insight(tone: .good, symbol: "flame.fill",
                               text: String(format: L.t("%d workdays in a row with at least 80%% of breaks taken.",
                                                        "%d sunod-sunod na araw ng trabaho na hindi bababa sa 80%% ng breaks ang ginawa."), streak)))
        }

        // 3. Energy on good-break days vs other days (last 30 days of check-ins)
        let rated = days(back: 30).filter { $0.energy > 0 && $0.breaksDue > 0 }
        let hi = rated.filter { $0.score >= 80 }, lo = rated.filter { $0.score < 80 }
        if hi.count >= 2 && lo.count >= 2 {
            let eh = Double(hi.map(\.energy).reduce(0, +)) / Double(hi.count)
            let el = Double(lo.map(\.energy).reduce(0, +)) / Double(lo.count)
            if eh - el >= 0.3 {
                out.append(Insight(tone: .good, symbol: "bolt.heart.fill",
                                   text: String(format: L.t("On days you take most of your breaks, your energy averages %.1f, against %.1f on other days.",
                                                            "Sa mga araw na ginagawa mo ang karamihan ng breaks, %.1f ang karaniwang lakas mo, kumpara sa %.1f sa ibang araw."), eh, el)))
            }
        }

        // 4. Eye blur moving (first half vs second half of the period's ratings)
        let blurs = days(back: max(7, range)).filter { $0.eyeBlur > 0 }.map(\.eyeBlur)
        if blurs.count >= 4 {
            let half = blurs.count / 2
            let a = Double(blurs.prefix(half).reduce(0, +)) / Double(half)
            let b = Double(blurs.suffix(blurs.count - half).reduce(0, +)) / Double(blurs.count - half)
            if b - a >= 0.5 {
                out.append(Insight(tone: .watch, symbol: "eye.trianglebadge.exclamationmark",
                                   text: L.t("Eye blur has been creeping up. If it stays that way, book an eye exam.",
                                             "Unti-unting lumalabo ang mata. Kung magpatuloy, magpa-eye exam ka.")))
            } else if a - b >= 0.5 {
                out.append(Insight(tone: .good, symbol: "eye.fill",
                                   text: L.t("Eye blur is easing off lately. Keep resting those eyes.",
                                             "Bumubuti ang labo ng mata nitong huli. Ituloy ang pagpapahinga ng mata.")))
            }
        }

        // 5. Which kind of break gets skipped
        if cur.eyeAll >= 5 && cur.strAll >= 3 {
            let eyeSkip = 100 * (cur.eyeAll - cur.eyeT) / cur.eyeAll
            let strSkip = 100 * (cur.strAll - cur.strT) / cur.strAll
            if strSkip >= 25 && strSkip - eyeSkip >= 10 {
                out.append(Insight(tone: .watch, symbol: "figure.walk",
                                   text: String(format: L.t("You skip stretch breaks more than eye breaks (%d%% vs %d%%). A shorter stretch break might be easier to keep.",
                                                            "Mas madalas mong laktawan ang stretch break kaysa eye break (%d%% vs %d%%). Baka mas madaling sundin ang mas maikling stretch break."), strSkip, eyeSkip)))
            } else if eyeSkip >= 25 && eyeSkip - strSkip >= 10 {
                out.append(Insight(tone: .watch, symbol: "eye.slash",
                                   text: String(format: L.t("Eye breaks get skipped most (%d%%). They only take 20 seconds: try looking out of a window.",
                                                            "Eye break ang pinakamadalas laktawan (%d%%). 20 segundo lang ito: subukang tumingin sa bintana."), eyeSkip)))
            }
        }

        // 6. Time of day with the most skipped breaks (from breaks.csv)
        if entries.count >= 12 {
            let overall = Double(entries.filter { $0.result == .skipped }.count) / Double(entries.count)
            let worst = Dictionary(grouping: entries, by: \.hour)
                .filter { $0.value.count >= 4 }
                .map { (hour: $0.key, rate: Double($0.value.filter { $0.result == .skipped }.count) / Double($0.value.count)) }
                .max { $0.rate < $1.rate }
            if let w = worst, w.rate >= 0.3, w.rate - overall >= 0.15 {
                out.append(Insight(tone: .watch, symbol: "clock.badge.exclamationmark",
                                   text: String(format: L.t("Breaks around %d:00 get skipped most (%d%%). A heads-up a little earlier may help then.",
                                                            "Pinakamadalas laktawan ang break bandang %d:00 (%d%%). Makakatulong ang mas maagang paalala sa oras na iyon."),
                                                w.hour, Int((w.rate * 100).rounded()))))
            }
        }

        // 7. Postponing habit
        if cur.days > 0 && Double(cur.postponed) / Double(cur.days) >= 2 {
            out.append(Insight(tone: .note, symbol: "clock.arrow.circlepath",
                               text: String(format: L.t("You postpone about %d breaks a day. A longer heads-up in Settings gives you time to wrap up first.",
                                                        "Mga %d break bawat araw ang ipinagpapaliban mo. Bigyan ang sarili ng mas mahabang paalala sa Settings."),
                                            Int((Double(cur.postponed) / Double(cur.days)).rounded()))))
        }

        // 8. Long screen days
        if range > 1 && cur.days >= 2 && cur.activePerDay >= 7 * 3600 {
            out.append(Insight(tone: .note, symbol: "display",
                               text: String(format: L.t("You average %@ of active screen time a day. Breaks matter most on days like these.",
                                                        "Karaniwang %@ ang aktibong oras mo sa screen bawat araw. Pinakamahalaga ang breaks sa ganitong mga araw."),
                                            DayStats.duration(cur.activePerDay))))
        }

        // 9. Nudge to do the check-in
        if checkInEnabled() && cur.blurN == 0 && cur.energyN == 0 && cur.days > 0 {
            out.append(Insight(tone: .note, symbol: "checklist",
                               text: L.t("Do the end-of-shift check-in to see how breaks affect your eyes and energy.",
                                         "Gawin ang check-in sa dulo ng shift para makita kung paano nakakaapekto ang breaks sa mata at lakas mo.")))
        }

        if out.isEmpty {
            out.append(Insight(tone: .note, symbol: "sparkles",
                               text: L.t("Insights appear here after a day or two of breaks.",
                                         "Lalabas dito ang mga obserbasyon pagkatapos ng isa o dalawang araw ng breaks.")))
        }
        // Keep it short: at most four, warnings first so they aren't missed.
        let order: [Insight.Tone: Int] = [.watch: 0, .good: 1, .note: 2]
        return Array(out.enumerated().sorted { (order[$0.element.tone]!, $0.offset) < (order[$1.element.tone]!, $1.offset) }
                        .map(\.element).prefix(4))
    }
}

// MARK: - Window

final class DashboardWindowController: NSWindowController, NSWindowDelegate {
    var closed: (() -> Void)?
    let model: DashboardModel

    init(range: Int, today: @escaping () -> DayStats, checkInEnabled: @escaping () -> Bool, onCheckIn: @escaping () -> Void) {
        model = DashboardModel(range: range, today: today, checkInEnabled: checkInEnabled)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 760),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.minSize = NSSize(width: 820, height: 600)
        super.init(window: w)
        w.delegate = self
        let host = NSHostingController(rootView: DashboardView(model: model, onCheckIn: onCheckIn,
                                                               onExport: { ReportPDF.exportWithPanel(today: today) }))
        w.contentViewController = host
        w.setContentSize(NSSize(width: 940, height: 760))
        w.title = L.t("ScreenRest Dashboard", "ScreenRest Dashboard")
    }
    required init?(coder: NSCoder) { fatalError() }

    func present(range: Int? = nil) {
        if let r = range { model.range = r }
        model.reload()
        activateApp()
        if window?.isVisible != true { window?.center() }
        window?.makeKeyAndOrderFront(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) { model.reload() }

    func windowWillClose(_ notification: Notification) {
        let c = closed
        closed = nil
        c?()
    }
}

// MARK: - Views

private let teal = Color(nsColor: Brand.teal)

private struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let t = title { Text(t).font(.headline) }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(nsColor: .separatorColor).opacity(0.6)))
    }
}

/// Small coloured change badge: "▲ 6 pts vs …".
private struct Delta: View {
    let value: Int?
    let unit: String
    var higherIsBetter = true
    var note: String? = nil
    var body: some View {
        if let n = note {
            Text(n).font(.caption).foregroundStyle(.tertiary)
        } else if let v = value {
            let good = higherIsBetter ? v > 0 : v < 0
            let color: Color = v == 0 ? .secondary : (good ? .green : .orange)
            Label("\(v > 0 ? "+" : "")\(v) \(unit)", systemImage: v > 0 ? "arrow.up" : v < 0 ? "arrow.down" : "equal")
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .labelStyle(.titleAndIcon)
        } else {
            Text(L.t("No earlier data", "Wala pang naunang data")).font(.caption).foregroundStyle(.tertiary)
        }
    }
}

private struct ScoreRing: View {
    let score: Int?
    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 9)
            Circle()
                .trim(from: 0, to: CGFloat(score ?? 0) / 100)
                .stroke(teal, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(score.map { "\($0)%" } ?? "–").font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit()
        }
        .frame(width: 66, height: 66)
    }
}

private struct Metric: View {
    let title: String
    let value: String
    let detail: String
    let delta: Delta
    let symbol: String
    var body: some View {
        Card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(title, systemImage: symbol).font(.subheadline).foregroundStyle(.secondary)
                    Text(value).font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                    delta
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct DashboardView: View {
    @ObservedObject var model: DashboardModel
    let onCheckIn: () -> Void
    let onExport: () -> Void
    private let refresh = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private func pct(_ a: Int, _ b: Int) -> String { b == 0 ? "–" : "\(Int((100.0 * Double(a) / Double(b)).rounded()))%" }
    private func pctValue(_ a: Int, _ b: Int) -> Int? { b == 0 ? nil : Int((100.0 * Double(a) / Double(b)).rounded()) }
    private func diff(_ a: Int?, _ b: Int?) -> Int? { (a != nil && b != nil) ? a! - b! : nil }

    var body: some View {
        let c = model.current, p = model.previous
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                // Summary cards
                HStack(alignment: .top, spacing: 14) {
                    Card {
                        HStack(spacing: 14) {
                            ScoreRing(score: c.score)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L.t("Break score", "Break score")).font(.subheadline).foregroundStyle(.secondary)
                                Text(L.t("of breaks taken", "ng breaks ang ginawa")).font(.caption).foregroundStyle(.secondary)
                                Delta(value: diff(c.score, p.score), unit: L.t("pts", "puntos"))
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    Metric(title: L.t("Screen time", "Oras sa screen"),
                           value: DayStats.duration(model.range == 1 ? c.active : c.activePerDay),
                           detail: model.range == 1 ? L.t("active so far today", "aktibo hanggang ngayon") : L.t("per workday, on average", "bawat araw ng trabaho, karaniwan"),
                           delta: Delta(value: p.days == 0 ? nil : (c.activePerDay - p.activePerDay) / 60, unit: "min", higherIsBetter: false,
                                        note: model.range == 1 ? L.t("Day still in progress", "Hindi pa tapos ang araw") : nil),
                           symbol: "display")
                    Metric(title: L.t("Eye breaks", "Eye breaks"), value: "\(c.eyeT)/\(c.eyeAll)",
                           detail: pct(c.eyeT, c.eyeAll) + L.t(" taken", " ginawa"),
                           delta: Delta(value: diff(pctValue(c.eyeT, c.eyeAll), pctValue(p.eyeT, p.eyeAll)), unit: L.t("pts", "puntos")),
                           symbol: "eye")
                    Metric(title: L.t("Stretch breaks", "Stretch breaks"), value: "\(c.strT)/\(c.strAll)",
                           detail: pct(c.strT, c.strAll) + L.t(" taken", " ginawa"),
                           delta: Delta(value: diff(pctValue(c.strT, c.strAll), pctValue(p.strT, p.strAll)), unit: L.t("pts", "puntos")),
                           symbol: "figure.walk")
                }

                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 14) {
                        breaksChart
                        feelingsChart
                        hoursChart
                    }
                    .frame(maxWidth: .infinity)
                    insightsCard.frame(width: 290)
                }

                footer
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(teal)
        .onReceive(refresh) { _ in model.reload() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L.t("Dashboard", "Dashboard")).font(.largeTitle.weight(.bold))
                Text(L.date(Date(), "EEEE d MMMM") + (DayStats.demoMode ? L.t(" · demo stats", " · demo stats") : ""))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $model.range) {
                Text(L.t("Today", "Ngayon")).tag(1)
                Text(L.t("7 days", "7 araw")).tag(7)
                Text(L.t("30 days", "30 araw")).tag(30)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
        }
    }

    private var breaksChart: some View {
        Card(title: L.t("Breaks per day", "Breaks bawat araw")) {
            if model.bars.allSatisfy({ $0.count == 0 }) {
                empty(L.t("No breaks yet in this period.", "Wala pang breaks sa panahong ito."))
            } else {
                Chart(model.bars) { b in
                    BarMark(x: .value("Day", b.date, unit: .day), y: .value("Breaks", b.count))
                        .foregroundStyle(by: .value("Kind", b.kind))
                        .cornerRadius(3)
                }
                .chartForegroundStyleScale([DashboardModel.eyeLabel: teal,
                                            DashboardModel.stretchLabel: Color.blue,
                                            DashboardModel.skippedLabel: Color.gray.opacity(0.35)])
                .chartXScale(domain: model.chartStart...Calendar.current.date(byAdding: .day, value: 1, to: model.chartEnd)!)
                .chartXAxis { dayAxis }
                .chartLegend(position: .top, alignment: .leading)
                .frame(height: 190)
            }
        }
    }

    private var feelingsChart: some View {
        Card(title: L.t("How you felt (1–5)", "Ang pakiramdam mo (1–5)")) {
            if model.ratings.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    empty(L.t("No check-ins in this period. Rate your eye blur and energy at the end of a shift to see a trend here.",
                              "Walang check-in sa panahong ito. I-rate ang labo ng mata at lakas sa dulo ng shift para makita ang takbo rito."))
                    Button(L.t("Do today's check-in…", "Gawin ang check-in ngayon…"), action: onCheckIn)
                }
            } else {
                Chart(model.ratings) { r in
                    LineMark(x: .value("Day", r.date, unit: .day), y: .value("Rating", r.value))
                        .foregroundStyle(by: .value("Series", r.series))
                    PointMark(x: .value("Day", r.date, unit: .day), y: .value("Rating", r.value))
                        .foregroundStyle(by: .value("Series", r.series))
                        .symbolSize(30)
                }
                .chartForegroundStyleScale([DashboardModel.blurLabel: Color.orange, DashboardModel.energyLabel: Color.green])
                .chartYScale(domain: 1...5)
                .chartXScale(domain: model.chartStart...Calendar.current.date(byAdding: .day, value: 1, to: model.chartEnd)!)
                .chartXAxis { dayAxis }
                .chartYAxis { AxisMarks(values: [1, 2, 3, 4, 5]) }
                .chartLegend(position: .top, alignment: .leading)
                .frame(height: 150)
                Text(L.t("Eye blur: lower is better. Energy: higher is better.",
                         "Labo ng mata: mas mababa, mas mabuti. Lakas: mas mataas, mas mabuti."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Day labels in the app's language (Charts would otherwise use the system language).
    private var dayAxis: some AxisContent {
        AxisMarks(values: .stride(by: .day, count: model.range == 30 ? 5 : 1)) { v in
            AxisGridLine()
            AxisValueLabel(centered: true) {
                if let d = v.as(Date.self) { Text(L.date(d, model.range == 30 ? "d MMM" : "EEE")) }
            }
        }
    }

    private var hoursChart: some View {
        Card(title: L.t("Time of day", "Oras ng araw")) {
            if model.hours.isEmpty {
                empty(L.t("Shows when you take or skip breaks, once a few breaks are logged with this version.",
                          "Ipinapakita kung kailan mo ginagawa o nilalaktawan ang breaks, kapag may ilang break nang naitala sa bersyong ito."))
            } else {
                Chart(model.hours) { h in
                    BarMark(x: .value("Hour", "\(h.hour):00"), y: .value("Breaks", h.count))
                        .foregroundStyle(by: .value("Kind", h.kind))
                        .cornerRadius(3)
                }
                .chartForegroundStyleScale([DashboardModel.takenLabel: teal, DashboardModel.skippedLabel: Color.gray.opacity(0.35)])
                .chartLegend(position: .top, alignment: .leading)
                .frame(height: 150)
            }
        }
    }

    private var insightsCard: some View {
        Card(title: L.t("Insights", "Mga obserbasyon")) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(model.insights) { i in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: i.symbol)
                            .font(.system(size: 17))
                            .foregroundStyle(i.tone == .good ? Color.green : i.tone == .watch ? Color.orange : teal)
                            .frame(width: 22)
                        Text(i.text).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider()
                Text(L.t("Worked out on this Mac from your own history. A wellness guide, not medical advice.",
                         "Kinuwenta sa Mac na ito mula sa sarili mong history. Gabay sa kalusugan, hindi payong medikal."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(String(format: L.t("Compared with %@.", "Kumpara sa %@."), model.periodName))
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button(L.t("Daily check-in…", "Check-in…"), action: onCheckIn)
            Button(L.t("Open data folder", "Buksan ang data folder")) { openDataFolder() }
            Button {
                onExport()
            } label: {
                Label(L.t("Export PDF for my doctor…", "I-export ang PDF para sa doktor…"), systemImage: "doc.richtext")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
    }
}
