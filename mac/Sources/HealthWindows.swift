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

func openDataFolder() {
    try? FileManager.default.createDirectory(at: DayStats.dataFolder, withIntermediateDirectories: true)
    NSWorkspace.shared.open(DayStats.dataFolder)
}
