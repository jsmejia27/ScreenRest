import AppKit
import AVFoundation

enum BreakKind { case eye, stretch }
enum BreakResult { case completed, skipped, postponed }

/// How a break behaves (built from Settings by the app).
struct BreakOptions {
    var allowSkip = true, allowPostpone = true, sounds = true
    var postponeMin = 5
    var voice = true      // play media/<slug>.wav
    var handsOff = true   // pause the countdown while keyboard/mouse are in use
}

/// Borderless window above everything (full-screen apps and the menu bar included), on one screen.
final class OverlayWindow: NSWindow {
    var onKey: ((NSEvent) -> Bool)?

    init(screen: NSScreen, alpha: CGFloat) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        hasShadow = false
        backgroundColor = Brand.bg
        alphaValue = alpha
        setFrame(screen.frame, display: false)
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }
    override func cancelOperation(_ sender: Any?) {
        // Esc, when it comes through the responder chain instead of keyDown
        if let e = NSApp.currentEvent, onKey?(e) == true { return }
    }
}

/// Plain dim overlay for the other screens, so you can't keep working there.
func makeDimWindow(_ screen: NSScreen) -> OverlayWindow {
    let w = OverlayWindow(screen: screen, alpha: 0.92)
    let l = label(L.t("Break time: look away from the screen", "Oras ng break: tumingin palayo sa screen"), size: 22, color: Brand.dim)
    l.translatesAutoresizingMaskIntoConstraints = false
    let v = NSView()
    v.addSubview(l)
    NSLayoutConstraint.activate([l.centerXAnchor.constraint(equalTo: v.centerXAnchor), l.centerYAnchor.constraint(equalTo: v.centerYAnchor)])
    w.contentView = v
    return w
}

/// Simple flat progress bar.
final class BarView: NSView {
    var fraction: CGFloat = 0 { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        rgb(40, 55, 64).setFill()
        bounds.fill()
        Brand.accent.setFill()
        NSRect(x: 0, y: 0, width: bounds.width * max(0, min(1, fraction)), height: bounds.height).fill()
    }
}

/// Full-screen dimmed overlay that guides the user through a break (port of BreakForm.cs).
final class BreakController: NSObject {
    var onFinish: ((BreakResult) -> Void)?
    private(set) var pausedSeconds = 0 // time the countdown was held because you kept working

    private let kind: BreakKind
    private let steps: [Exercise]
    private let opt: BreakOptions
    private let totalSec: Int
    private var elapsed = 0, stepIdx = 0, stepElapsed = 0, shownSec = 0
    private var finished = false, holding = false, voicePlaying = false

    let window: OverlayWindow
    private let lblHeader, lblTitle, lblBody, lblTimer, lblNudge, lblNext: NSTextField
    private let bar = BarView()
    private let demoBox = NSView()
    private let demoView = NSImageView()
    private var demoImage: NSImage?
    private var voice: AVAudioPlayer?
    private var timer: Timer?
    private let timerBig = NSFont.monospacedDigitSystemFont(ofSize: 76, weight: .ultraLight)
    private let timerSmall = NSFont.monospacedDigitSystemFont(ofSize: 54, weight: .ultraLight)

    init(kind: BreakKind, steps: [Exercise], screen: NSScreen, options: BreakOptions) {
        self.kind = kind
        self.steps = steps
        opt = options
        totalSec = steps.reduce(0) { $0 + $1.seconds }
        window = OverlayWindow(screen: screen, alpha: 0.96)

        let textW = min(980, screen.frame.width - 120)
        func make(_ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor) -> NSTextField {
            let l = label("", size: size, weight: weight, color: color, wrap: textW)
            l.alignment = .center
            l.widthAnchor.constraint(equalToConstant: textW).isActive = true
            return l
        }
        lblHeader = make(16, .bold, Brand.accent)
        lblTitle = make(44, .bold, .white)
        lblBody = make(21, .regular, Brand.soft)
        lblTimer = make(76, .ultraLight, .white)
        lblNudge = make(17, .bold, Brand.warn)
        lblNext = make(16, .regular, Brand.dim)
        super.init()
        build(screen: screen, textW: textW)
    }

    private func build(screen: NSScreen, textW: CGFloat) {
        lblTimer.font = timerBig
        lblNudge.stringValue = " " // keeps its line height so the layout doesn't jump

        // Looping exercise demo (animated GIF), about a third of the screen height.
        let demoH = max(180, min(460, screen.frame.height * 9 / 25))
        let demoW = min(textW, demoH * 16 / 9)
        demoBox.wantsLayer = true
        demoBox.layer?.backgroundColor = Brand.panel.cgColor
        demoBox.layer?.cornerRadius = 10
        demoBox.layer?.masksToBounds = true
        demoBox.translatesAutoresizingMaskIntoConstraints = false
        demoBox.widthAnchor.constraint(equalToConstant: demoW).isActive = true
        demoBox.heightAnchor.constraint(equalToConstant: demoH).isActive = true
        demoView.imageScaling = .scaleProportionallyUpOrDown
        demoView.animates = true
        demoView.translatesAutoresizingMaskIntoConstraints = false
        demoBox.addSubview(demoView)
        NSLayoutConstraint.activate([
            demoView.leadingAnchor.constraint(equalTo: demoBox.leadingAnchor),
            demoView.trailingAnchor.constraint(equalTo: demoBox.trailingAnchor),
            demoView.topAnchor.constraint(equalTo: demoBox.topAnchor),
            demoView.bottomAnchor.constraint(equalTo: demoBox.bottomAnchor),
        ])
        demoBox.isHidden = true

        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.widthAnchor.constraint(equalToConstant: textW).isActive = true
        bar.heightAnchor.constraint(equalToConstant: 8).isActive = true

        // "Done" ends the break early and counts it as taken (you did the exercise). Strict mode keeps you in.
        var buttons: [NSView] = []
        func button(_ title: String, primary: Bool, _ r: BreakResult) -> NSButton {
            let b = ActionButton(title, primary: false) { [weak self] in
                DispatchQueue.main.async { self?.finish(r) }
            }
            b.font = .systemFont(ofSize: 15, weight: primary ? .semibold : .regular)
            if primary { b.bezelColor = Brand.teal }
            b.refusesFirstResponder = true
            return b
        }
        if opt.allowSkip { buttons.append(button(L.t("Done", "Tapos na"), primary: true, .completed)) }
        if opt.allowPostpone {
            buttons.append(button(L.t("Postpone \(opt.postponeMin) min", "Ipagpaliban nang \(opt.postponeMin) min"), primary: false, .postponed))
        }
        if opt.allowSkip { buttons.append(button(L.t("Skip  (Esc)", "Laktawan  (Esc)"), primary: false, .skipped)) }
        if !opt.allowSkip && !opt.allowPostpone {
            let strict = label(L.t("Strict mode is on. This break can't be skipped. Your body will thank you.",
                                   "Naka-on ang strict mode. Hindi puwedeng laktawan ang break na ito. Magpapasalamat ang katawan mo."),
                               size: 14, color: Brand.dim)
            strict.font = NSFontManager.shared.convert(.systemFont(ofSize: 14), toHaveTrait: .italicFontMask)
            buttons.append(strict)
        }
        let row = hstack(buttons, spacing: 16)

        let stack = vstack([lblHeader, lblTitle, demoBox, lblBody, lblTimer, lblNudge, bar, lblNext, row], spacing: 0, alignment: .centerX)
        stack.setCustomSpacing(8, after: lblHeader)
        stack.setCustomSpacing(18, after: lblTitle)
        stack.setCustomSpacing(20, after: demoBox)
        stack.setCustomSpacing(24, after: lblBody)
        stack.setCustomSpacing(4, after: lblNudge)
        stack.setCustomSpacing(22, after: bar)
        stack.setCustomSpacing(28, after: lblNext)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor, constant: -20),
        ])
        window.contentView = content
        window.appearance = NSAppearance(named: .darkAqua)

        window.onKey = { [weak self] e in
            guard let self = self else { return false }
            if e.keyCode == 53 { // Esc
                if self.opt.allowSkip { self.finish(.skipped) }
                return true
            }
            return true // swallow other keys: nothing to type into during a break
        }
    }

    func show() {
        activateApp()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        showStep()
        let t = Timer(timeInterval: 1, target: self, selector: #selector(onTick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Fills in the first step without showing the window or starting the timer (used by --snapshot).
    func prepareForSnapshot() { showStep() }

    // ------------------------------------------------------------------ steps
    private func showStep() {
        let ex = steps[stepIdx]
        if kind == .eye {
            lblHeader.stringValue = L.t("EYE BREAK  ·  LOOK AWAY FROM THE SCREEN", "EYE BREAK  ·  TUMINGIN PALAYO SA SCREEN")
            lblNext.stringValue = L.t("Your eyes focus up close all day. Looking far away lets the focusing muscles relax.",
                                      "Buong araw nakatutok sa malapit ang mata mo. Ang pagtingin sa malayo ay nagpapahinga sa mga kalamnan nito.")
        } else {
            lblHeader.stringValue = String(format: L.t("STRETCH BREAK  ·  STEP %d OF %d", "STRETCH BREAK  ·  HAKBANG %d SA %d"),
                                           stepIdx + 1, steps.count)
        }
        lblTitle.stringValue = ex.title
        lblBody.stringValue = ex.steps

        voicePlaying = playVoice(opt.voice ? ex.audioURL : nil)
        if !voicePlaying && opt.sounds { NSSound(named: "Tink")?.play() } // chime only when there's no voice

        loadDemo(ex.mediaURL)

        lblTimer.font = demoBox.isHidden ? timerBig : timerSmall
        updateTimer()
    }

    private func playVoice(_ url: URL?) -> Bool {
        stopVoice()
        guard let url = url, let p = try? AVAudioPlayer(contentsOf: url) else { return false }
        voice = p
        return p.play()
    }

    private func stopVoice() {
        voice?.stop()
        voice = nil
    }

    private func loadDemo(_ url: URL?) {
        demoImage = url.flatMap { NSImage(contentsOf: $0) }
        demoView.image = demoImage
        demoBox.isHidden = demoImage == nil
    }

    private func updateTimer() {
        let stepLeft = steps[stepIdx].seconds - stepElapsed
        lblTimer.stringValue = BreakController.clock(stepLeft)
        bar.fraction = totalSec == 0 ? 1 : CGFloat(elapsed) / CGFloat(totalSec)
        if kind == .stretch {
            let next = stepIdx + 1 < steps.count ? L.t("Next: ", "Susunod: ") + steps[stepIdx + 1].title
                                                 : L.t("Last one, almost done!", "Huli na ito, malapit nang matapos!")
            let left = BreakController.clock(totalSec - elapsed)
            lblNext.stringValue = next + "        ·        " + L.t(left + " left in break", left + " natitira sa break")
        }
    }

    static func clock(_ sec: Int) -> String {
        let s = max(0, sec)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    @objc private func onTick() {
        shownSec += 1

        // Hands-off check: if you're still typing or using the mouse, the break isn't happening.
        // (A short grace period at the start, since you were mid-sentence when it appeared.)
        if opt.handsOff && shownSec > 3 && Native.idleSeconds() < 1.5 {
            holding = true
            pausedSeconds += 1
            lblNudge.stringValue = kind == .stretch
                ? L.t("Paused: hands off the keyboard and mouse, and stand up", "Naka-pause: bitawan ang keyboard at mouse, at tumayo")
                : L.t("Paused: hands off the keyboard and mouse, and look away", "Naka-pause: bitawan ang keyboard at mouse, at tumingin palayo")
            return
        }
        if holding { holding = false; lblNudge.stringValue = " " }

        elapsed += 1
        stepElapsed += 1

        if stepElapsed >= steps[stepIdx].seconds {
            stepIdx += 1
            stepElapsed = 0
            if stepIdx >= steps.count { finish(.completed); return }
            showStep()
            return
        }
        updateTimer()
    }

    func finish(_ r: BreakResult) {
        guard !finished else { return }
        finished = true
        timer?.invalidate()
        timer = nil
        stopVoice()
        demoView.image = nil
        if r == .completed && opt.sounds { NSSound(named: "Glass")?.play() }
        window.orderOut(nil)
        window.close()
        onFinish?(r)
    }
}
