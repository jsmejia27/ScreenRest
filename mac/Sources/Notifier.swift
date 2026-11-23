import AppKit
import UserNotifications

/// The Windows balloon tips. Uses macOS notifications when allowed, otherwise a small toast
/// under the menu bar, so reminders still show if notifications are off for ScreenRest.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    private var systemAllowed = false
    private var toast: NSPanel?
    private var toastTimer: Timer?

    func setup() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return } // a bare binary can't use UNUserNotificationCenter
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        c.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { Notifier.shared.systemAllowed = granted }
        }
    }

    func post(_ title: String, _ body: String) {
        guard systemAllowed else { showToast(title, body); return }
        UNUserNotificationCenter.current().getNotificationSettings { st in
            let ok = st.authorizationStatus == .authorized || st.authorizationStatus == .provisional
            DispatchQueue.main.async {
                guard ok else { Notifier.shared.systemAllowed = false; Notifier.shared.showToast(title, body); return }
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                let req = UNNotificationRequest(identifier: "screenrest", content: content, trigger: nil) // replaces the previous one
                UNUserNotificationCenter.current().add(req) { err in
                    if err != nil { DispatchQueue.main.async { Notifier.shared.showToast(title, body) } }
                }
            }
        }
    }

    // Show banners even while one of our windows is in front.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    // ---------------------------------------------------------------- fallback toast
    private func showToast(_ title: String, _ body: String) {
        toastTimer?.invalidate()
        toast?.orderOut(nil)

        let width: CGFloat = 340
        let t = label(title, size: 13, weight: .semibold, color: .white, wrap: width - 32)
        let b = label(body, size: 12, color: Brand.soft, wrap: width - 32)
        let stack = vstack([t, b], spacing: 4)
        let content = padded(stack, NSEdgeInsets(top: 12, left: 16, bottom: 14, right: 16))
        content.wantsLayer = true
        content.layer?.backgroundColor = Brand.bg.withAlphaComponent(0.97).cgColor
        content.layer?.cornerRadius = 12
        content.layer?.borderColor = Brand.teal.cgColor
        content.layer?.borderWidth = 1
        content.widthAnchor.constraint(equalToConstant: width).isActive = true

        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: 80),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isReleasedWhenClosed = false
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        p.contentView = content
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        let vf = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        p.setFrame(NSRect(x: vf.maxX - size.width - 12, y: vf.maxY - size.height - 10, width: size.width, height: size.height), display: true)
        let click = NSClickGestureRecognizer(target: self, action: #selector(dismissToast))
        content.addGestureRecognizer(click)
        p.orderFrontRegardless()
        toast = p
        let timer = Timer(timeInterval: 6, target: self, selector: #selector(dismissToast), userInfo: nil, repeats: false)
        RunLoop.main.add(timer, forMode: .common)
        toastTimer = timer
    }

    @objc private func dismissToast() {
        toastTimer?.invalidate()
        toast?.orderOut(nil)
        toast = nil
    }
}
