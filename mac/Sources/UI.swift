import AppKit

// Small AppKit helpers shared by all windows.

func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular,
           color: NSColor = .labelColor, wrap: CGFloat? = nil) -> NSTextField {
    let f = wrap != nil ? NSTextField(wrappingLabelWithString: text) : NSTextField(labelWithString: text)
    f.font = .systemFont(ofSize: size, weight: weight)
    f.textColor = color
    f.isSelectable = false
    if let w = wrap {
        f.preferredMaxLayoutWidth = w
        f.widthAnchor.constraint(lessThanOrEqualToConstant: w).isActive = true
    }
    return f
}

func vstack(_ views: [NSView], spacing: CGFloat = 8, alignment: NSLayoutConstraint.Attribute = .leading) -> NSStackView {
    let s = NSStackView(views: views)
    s.orientation = .vertical
    s.alignment = alignment
    s.spacing = spacing
    return s
}

func hstack(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
    let s = NSStackView(views: views)
    s.orientation = .horizontal
    s.alignment = .centerY
    s.spacing = spacing
    return s
}

/// A view that holds `content` with padding around it.
func padded(_ content: NSView, _ i: NSEdgeInsets) -> NSView {
    let box = NSView()
    content.translatesAutoresizingMaskIntoConstraints = false
    box.addSubview(content)
    NSLayoutConstraint.activate([
        content.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: i.left),
        content.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -i.right),
        content.topAnchor.constraint(equalTo: box.topAnchor, constant: i.top),
        content.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -i.bottom),
    ])
    return box
}

/// Flexible empty view that pushes the following views to the right in a horizontal stack.
func spacer() -> NSView {
    let v = NSView()
    v.setContentHuggingPriority(.init(1), for: .horizontal)
    v.setContentCompressionResistancePriority(.init(1), for: .horizontal)
    return v
}

/// NSButton that runs a closure.
final class ActionButton: NSButton {
    private var handler: () -> Void = {}
    convenience init(_ title: String, primary: Bool = false, _ handler: @escaping () -> Void) {
        self.init(frame: .zero)
        self.title = title
        bezelStyle = .rounded
        controlSize = .large
        if primary { bezelColor = Brand.teal; keyEquivalent = "\r" }
        self.handler = handler
        target = self
        action = #selector(fire)
    }
    @objc private func fire() { handler() }
}

/// NSMenuItem that runs a closure.
final class ActionMenuItem: NSMenuItem {
    private var handler: () -> Void = {}
    convenience init(_ title: String, key: String = "", _ handler: @escaping () -> Void) {
        self.init(title: title, action: #selector(fire), keyEquivalent: key)
        self.handler = handler
        target = self
    }
    @objc private func fire() { handler() }
}

func activateApp() {
    if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
}

/// Window controller that tells the app when its window closes, so the app can drop its reference.
class BaseWindowController: NSWindowController, NSWindowDelegate {
    var closed: (() -> Void)?

    init(title: String, resizable: Bool = false) {
        var mask: NSWindow.StyleMask = [.titled, .closable]
        if resizable { mask.formUnion([.resizable, .miniaturizable]) }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 300), styleMask: mask, backing: .buffered, defer: false)
        w.title = title
        w.isReleasedWhenClosed = false
        super.init(window: w)
        w.delegate = self
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Sets the content and sizes the window to fit it.
    func setContent(_ v: NSView) {
        guard let w = window else { return }
        w.contentView = v
        v.layoutSubtreeIfNeeded()
        w.setContentSize(v.fittingSize)
    }

    func present() {
        guard let w = window else { return }
        activateApp()
        w.center()
        w.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        let c = closed
        closed = nil
        c?()
    }
}
