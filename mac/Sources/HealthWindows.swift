import AppKit

/// End-of-shift check-in: two 1-5 ratings, saved into today's stats row.
final class CheckInController: BaseWindowController {
    private let day: DayStats
    private let blur = NSSegmentedControl(labels: ["1", "2", "3", "4", "5"], trackingMode: .selectOne, target: nil, action: nil)
    private let energy = NSSegmentedControl(labels: ["1", "2", "3", "4", "5"], trackingMode: .selectOne, target: nil, action: nil)

    init(_ day: DayStats) {
        self.day = day
        super.init(title: L.t("ScreenRest: daily check-in", "ScreenRest: pang-araw-araw na check-in"))
        blur.selectedSegment = day.eyeBlur - 1
        energy.selectedSegment = day.energy - 1
        for s in [blur, energy] { for i in 0..<5 { s.setWidth(40, forSegment: i) } }

        let intro = label(L.t("How were you today? It takes 5 seconds, and over time it shows whether breaks help.",
                              "Kumusta ka ngayong araw? 5 segundo lang ito, at sa paglipas ng panahon makikita kung nakakatulong ang breaks."),
                          wrap: 460)
        func row(_ title: String, _ lo: String, _ hi: String, _ seg: NSSegmentedControl) -> NSView {
            let t = label(title, weight: .semibold)
            let line = hstack([label(lo, size: 12, color: .secondaryLabelColor), seg, label(hi, size: 12, color: .secondaryLabelColor)], spacing: 10)
            return vstack([t, line], spacing: 6)
        }
        let later = ActionButton(L.t("Not today", "Hindi ngayon")) { [weak self] in self?.close() }
        later.keyEquivalent = "\u{1b}"
        let save = ActionButton(L.t("Save", "I-save"), primary: true) { [weak self] in
            guard let self = self else { return }
            self.day.eyeBlur = self.blur.selectedSegment + 1 // -1 (none) becomes 0 = not answered
            self.day.energy = self.energy.selectedSegment + 1
            self.day.save()
            self.close()
        }
        let buttons = hstack([spacer(), later, save], spacing: 10)
        let body = vstack([intro,
                           row(L.t("Right eye blur", "Labo ng kanang mata"), L.t("1 = clear", "1 = malinaw"), L.t("5 = very blurry", "5 = napakalabo"), blur),
                           row(L.t("Energy", "Lakas"), L.t("1 = exhausted", "1 = pagod na pagod"), L.t("5 = great", "5 = napakasigla"), energy),
                           buttons], spacing: 16)
        buttons.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        setContent(padded(body, NSEdgeInsets(top: 20, left: 22, bottom: 18, right: 22)))
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Plain monospace report window (today's stats, weekly summary).
final class ReportController: BaseWindowController {
    init(title: String, text: String) {
        super.init(title: title)
        let l = NSTextField(labelWithString: text)
        l.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        l.isSelectable = true
        setContent(padded(l, NSEdgeInsets(top: 20, left: 22, bottom: 20, right: 22)))
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// 30-day chart of eye blur, energy and break score: something to show your optometrist.
final class TrendController: BaseWindowController {
    init(_ today: DayStats) {
        super.init(title: L.t("ScreenRest: health trend (last 30 days)", "ScreenRest: takbo ng kalusugan (huling 30 araw)"), resizable: true)
        let chart = TrendView(today)
        let open = ActionButton(L.t("Open data folder (CSV)", "Buksan ang data folder (CSV)")) {
            openDataFolder()
        }
        let bottom = hstack([spacer(), open])
        let root = NSView()
        for v in [chart, bottom] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        NSLayoutConstraint.activate([
            chart.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            chart.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            chart.topAnchor.constraint(equalTo: root.topAnchor),
            bottom.topAnchor.constraint(equalTo: chart.bottomAnchor, constant: 4),
            bottom.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            bottom.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            bottom.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            root.widthAnchor.constraint(greaterThanOrEqualToConstant: 600),
            root.heightAnchor.constraint(greaterThanOrEqualToConstant: 380),
        ])
        window?.contentView = root
        window?.setContentSize(NSSize(width: 900, height: 520))
        window?.appearance = NSAppearance(named: .aqua) // the chart is drawn on white
    }
    required init?(coder: NSCoder) { fatalError() }
}

func openDataFolder() {
    try? FileManager.default.createDirectory(at: DayStats.dataFolder, withIntermediateDirectories: true)
    NSWorkspace.shared.open(DayStats.dataFolder)
}

final class TrendView: NSView {
    private let days: [DayStats]
    private let blurColor = rgb(232, 120, 40)
    private let energyColor = rgb(30, 158, 138)
    private let scoreColor = rgb(215, 225, 232)
    private let font = NSFont.systemFont(ofSize: 12)

    init(_ today: DayStats) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: DayStats.today)!
        days = DayStats.history(today).filter { $0.date > cutoff }
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    private func text(_ s: String, _ x: CGFloat, _ y: CGFloat, color: NSColor = .gray, font f: NSFont? = nil) {
        (s as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: f ?? font, .foregroundColor: color])
    }

    private func dayOffset(_ start: Date, _ d: Date) -> CGFloat {
        CGFloat(Calendar.current.dateComponents([.day], from: start, to: d).day ?? 0)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        let area = NSRect(x: 60, y: 50, width: bounds.width - 110, height: bounds.height - 100)
        text(L.t("Right-eye blur and energy (1-5), with daily break score",
                 "Labo ng kanang mata at lakas (1-5), kasama ang araw-araw na break score"),
             56, 14, color: .black, font: .systemFont(ofSize: 15, weight: .semibold))
        legend(area.maxX - 330, 40)

        guard !days.isEmpty, area.width >= 50, area.height >= 50 else {
            text(L.t("No data yet. Do the daily check-in at the end of each shift.",
                     "Wala pang data. Gawin ang check-in sa dulo ng bawat shift."), area.minX, area.minY + 20)
            return
        }

        func ratingY(_ v: Int) -> CGFloat { area.maxY - area.height * (CGFloat(v) - 0.5) / 5 }

        // Grid lines for ratings 1..5
        for v in 1...5 {
            let y = ratingY(v)
            rgb(230, 234, 238).setStroke() // set every time: drawing the label text resets it
            let p = NSBezierPath()
            p.move(to: NSPoint(x: area.minX, y: y)); p.line(to: NSPoint(x: area.maxX, y: y))
            p.stroke()
            text("\(v)", area.minX - 22, y - 8)
        }

        let start = Calendar.current.date(byAdding: .day, value: -29, to: DayStats.today)!
        let step = area.width / 30
        // Break score as light bars: 0% at the bottom, 100% level with the "5" line (right-hand axis).
        let top = ratingY(5)
        text("100%", area.maxX + 4, top - 8)
        text("0%", area.maxX + 4, area.maxY - 14)
        scoreColor.setFill()
        for d in days where d.breaksDue > 0 {
            let x = area.minX + dayOffset(start, d.date) * step
            let h = (area.maxY - top) * CGFloat(d.score) / 100
            NSRect(x: x + step * 0.2, y: area.maxY - h, width: step * 0.6, height: h).fill()
        }
        line(area, start, step, blurColor) { $0.eyeBlur }
        line(area, start, step, energyColor) { $0.energy }

        // Date labels every 5 days
        for i in stride(from: 0, to: 30, by: 5) {
            let d = Calendar.current.date(byAdding: .day, value: i, to: start)!
            text(L.date(d, "d MMM"), area.minX + CGFloat(i) * step, area.maxY + 6)
        }
    }

    private func line(_ area: NSRect, _ start: Date, _ step: CGFloat, _ c: NSColor, _ value: (DayStats) -> Int) {
        func ratingY(_ v: Int) -> CGFloat { area.maxY - area.height * (CGFloat(v) - 0.5) / 5 }
        let pts = days.compactMap { d -> NSPoint? in
            let v = value(d)
            return v > 0 ? NSPoint(x: area.minX + dayOffset(start, d.date) * step + step / 2, y: ratingY(v)) : nil
        }
        c.setStroke(); c.setFill()
        if pts.count > 1 {
            let p = NSBezierPath()
            p.lineWidth = 2.5
            p.lineJoinStyle = .round
            p.move(to: pts[0])
            for q in pts.dropFirst() { p.line(to: q) }
            p.stroke()
        }
        for q in pts { NSBezierPath(ovalIn: NSRect(x: q.x - 4, y: q.y - 4, width: 8, height: 8)).fill() }
    }

    private func legend(_ x: CGFloat, _ y: CGFloat) {
        swatch(x, y, blurColor, L.t("Eye blur", "Labo ng mata"))
        swatch(x + 110, y, energyColor, L.t("Energy", "Lakas"))
        swatch(x + 190, y, scoreColor, "Break score")
    }

    private func swatch(_ x: CGFloat, _ y: CGFloat, _ c: NSColor, _ s: String) {
        c.setFill()
        NSRect(x: x, y: y + 3, width: 14, height: 10).fill()
        text(s, x + 18, y, color: .darkGray)
    }
}
