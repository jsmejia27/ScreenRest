import AppKit
import Charts
import SwiftUI

/// One-page A4 PDF of the last 30 days, written to show an optometrist or doctor:
/// break habits, average screen time, and the eye-blur and energy check-ins, with how they're scored.
@MainActor
enum ReportPDF {
    static let pageSize = CGSize(width: 595, height: 842) // A4 in points

    /// Renders the report for the last 30 days to `url`. Returns false if it couldn't be written.
    @discardableResult
    static func write(to url: URL, today: @escaping () -> DayStats) -> Bool {
        let model = DashboardModel(range: 30, today: today, checkInEnabled: { false })
        let view = ReportPage(model: model)
            .frame(width: pageSize.width, height: pageSize.height)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(pageSize)
        var ok = false
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: pageSize)
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, [kCGPDFContextTitle as String: "ScreenRest health report",
                                                                    kCGPDFContextCreator as String: "ScreenRest"] as CFDictionary) else { return }
            pdf.beginPDFPage(nil)
            draw(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            ok = true
        }
        return ok
    }

    /// The same page as a PNG at `scale` (for screenshots on the website).
    static func png(to url: URL, scale: CGFloat, today: @escaping () -> DayStats) {
        let model = DashboardModel(range: 30, today: today, checkInEnabled: { false })
        let renderer = ImageRenderer(content: ReportPage(model: model)
            .frame(width: pageSize.width, height: pageSize.height)
            .environment(\.colorScheme, .light))
        renderer.scale = scale
        if let img = renderer.nsImage, let tiff = img.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }

    /// Asks where to save, writes the PDF and shows it in Finder.
    static func exportWithPanel(today: @escaping () -> DayStats) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "ScreenRest report \(f.string(from: Date())).pdf"
        panel.message = L.t("A one-page summary of the last 30 days, for your optometrist or doctor.",
                            "Isang pahinang buod ng huling 30 araw, para sa optometrist o doktor mo.")
        activateApp()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if write(to: url, today: today) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            let a = NSAlert()
            a.messageText = L.t("Couldn't save the report.", "Hindi na-save ang report.")
            a.runModal()
        }
    }
}

private struct ReportPage: View {
    @ObservedObject var model: DashboardModel
    private let teal = Color(nsColor: Brand.teal)

    private func fmt(_ v: Double?) -> String { v.map { String(format: "%.1f", $0) } ?? "–" }
    private func pct(_ a: Int, _ b: Int) -> String { b == 0 ? "–" : "\(Int((100.0 * Double(a) / Double(b)).rounded()))%" }

    var body: some View {
        let c = model.current
        let start = Calendar.current.date(byAdding: .day, value: -29, to: DayStats.today)!
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(alignment: .center, spacing: 12) {
                Image(nsImage: IconFactory.appIcon(44)).resizable().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.t("Screen break and eye-comfort report", "Report sa screen break at ginhawa ng mata")).font(.system(size: 18, weight: .bold))
                    Text(L.date(start, "d MMM yyyy") + " – " + L.date(DayStats.today, "d MMM yyyy") +
                         L.t("  ·  last 30 days  ·  made with ScreenRest", "  ·  huling 30 araw  ·  gawa ng ScreenRest"))
                        .font(.system(size: 9.5)).foregroundStyle(.secondary)
                }
            }
            Divider()

            // Summary table
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                row(L.t("Days tracked", "Araw na naitala"), "\(c.days)",
                    L.t("Average active screen time", "Karaniwang aktibong oras sa screen"), DayStats.duration(c.activePerDay) + L.t(" / day", " / araw"))
                row(L.t("Breaks taken (score)", "Breaks na ginawa (score)"), c.score.map { "\($0)%" } ?? "–",
                    L.t("Breaks postponed", "Ipinagpaliban"), "\(c.postponed)")
                row(L.t("Eye breaks (20-20-20)", "Eye breaks (20-20-20)"), "\(c.eyeT) / \(c.eyeAll)  (\(pct(c.eyeT, c.eyeAll)))",
                    L.t("Stretch breaks", "Stretch breaks"), "\(c.strT) / \(c.strAll)  (\(pct(c.strT, c.strAll)))")
                row(L.t("Average right-eye blur", "Karaniwang labo ng kanang mata"), fmt(c.avgBlur) + " / 5  (n=\(c.blurN))",
                    L.t("Average energy", "Karaniwang lakas"), fmt(c.avgEnergy) + " / 5  (n=\(c.energyN))")
            }
            .font(.system(size: 10.5))

            // Ratings chart
            section(L.t("Daily check-in: right-eye blur and energy", "Araw-araw na check-in: labo ng kanang mata at lakas"))
            if model.ratings.isEmpty {
                Text(L.t("No check-ins in this period.", "Walang check-in sa panahong ito.")).font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                Chart(model.ratings) { r in
                    LineMark(x: .value("Day", r.date, unit: .day), y: .value("Rating", r.value))
                        .foregroundStyle(by: .value("Series", r.series))
                    PointMark(x: .value("Day", r.date, unit: .day), y: .value("Rating", r.value))
                        .foregroundStyle(by: .value("Series", r.series)).symbolSize(18)
                }
                .chartForegroundStyleScale([DashboardModel.blurLabel: Color.orange, DashboardModel.energyLabel: Color.green])
                .chartYScale(domain: 1...5)
                .chartYAxis { AxisMarks(values: [1, 2, 3, 4, 5]) }
                .chartXScale(domain: model.chartStart...Calendar.current.date(byAdding: .day, value: 1, to: model.chartEnd)!)
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: 5)) { v in
                    AxisGridLine()
                    AxisValueLabel { if let d = v.as(Date.self) { Text(L.date(d, "d MMM")) } }
                } }
                .chartLegend(position: .top, alignment: .leading)
                .font(.system(size: 9))
                .frame(height: 170)
            }

            // Breaks chart
            section(L.t("Breaks per day", "Breaks bawat araw"))
            Chart(model.bars) { b in
                BarMark(x: .value("Day", b.date, unit: .day), y: .value("Breaks", b.count))
                    .foregroundStyle(by: .value("Kind", b.kind))
            }
            .chartForegroundStyleScale([DashboardModel.eyeLabel: teal, DashboardModel.stretchLabel: Color.blue,
                                        DashboardModel.skippedLabel: Color.gray.opacity(0.35)])
            .chartXScale(domain: model.chartStart...Calendar.current.date(byAdding: .day, value: 1, to: model.chartEnd)!)
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 5)) { v in
                AxisGridLine()
                AxisValueLabel { if let d = v.as(Date.self) { Text(L.date(d, "d MMM")) } }
            } }
            .chartLegend(position: .top, alignment: .leading)
            .font(.system(size: 9))
            .frame(height: 140)

            // Observations
            section(L.t("Observations", "Mga obserbasyon"))
            VStack(alignment: .leading, spacing: 4) {
                ForEach(model.insights) { i in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                        Text(i.text).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.system(size: 10))

            Spacer(minLength: 0)
            Divider()
            Text(L.t("How to read this: the person rates their right eye's blurriness at the end of each workday from 1 (clear) to 5 (very blurry), and their energy from 1 (exhausted) to 5 (great). Breaks follow the 20-20-20 rule (a 20-second look into the distance every 20 minutes) plus a stand-up stretch break about every hour. Ratings are self-reported. ScreenRest is a wellness reminder, not a medical device.",
                     "Paano basahin: sa dulo ng bawat araw ng trabaho, nire-rate ng tao ang labo ng kanang mata mula 1 (malinaw) hanggang 5 (napakalabo), at ang lakas mula 1 (pagod na pagod) hanggang 5 (napakasigla). Sumusunod ang breaks sa 20-20-20 rule (20 segundong pagtingin sa malayo tuwing 20 minuto) at stretch break nang nakatayo halos bawat oras. Sariling rating ito ng tao. Paalala sa kalusugan ang ScreenRest, hindi medical device."))
                .font(.system(size: 8.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(36)
        .background(Color.white)
    }

    private func section(_ t: String) -> some View {
        Text(t).font(.system(size: 12, weight: .semibold)).padding(.top, 4)
    }

    private func row(_ a: String, _ av: String, _ b: String, _ bv: String) -> some View {
        GridRow {
            Text(a).foregroundStyle(.secondary)
            Text(av).fontWeight(.semibold)
            Text(b).foregroundStyle(.secondary)
            Text(bv).fontWeight(.semibold)
        }
    }
}
