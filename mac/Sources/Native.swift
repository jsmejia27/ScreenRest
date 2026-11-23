import AppKit
import CoreAudio
import CoreGraphics
import CoreMediaIO

/// macOS queries: idle time, and "am I on a call / presenting / in a full-screen app?"
/// None of these need a permission prompt: they read device and window state, never camera, mic or screen content.
enum Native {
    // ---------------------------------------------------------------- idle time

    /// Seconds since the last keyboard, mouse or trackpad input (any app).
    static func idleSeconds() -> Double {
        guard let any = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
    }

    // ---------------------------------------------------------------- busy detection

    /// True when a break would be rude: camera or microphone in use (video call), or a full-screen
    /// app (slideshow, video, game) is in front. `reason` says which, in the interface language.
    static func isBusy() -> String? {
        if cameraInUse() { return L.t("your camera is on", "nakabukas ang camera mo") }
        if microphoneInUse() { return L.t("you're on a call", "nasa tawag ka") }
        if foregroundIsFullScreen() { return L.t("a full-screen app is open", "may bukas na full-screen app") }
        return nil
    }

    // ---- camera: CoreMediaIO "device is running somewhere" ----
    static func cameraInUse() -> Bool {
        var addr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == 0, size > 0 else { return false }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &addr, 0, nil, size, &used, &ids) == 0 else { return false }
        for id in ids {
            var a = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            var running: UInt32 = 0
            var got: UInt32 = 0
            if CMIOObjectGetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &got, &running) == 0, running != 0 {
                return true
            }
        }
        return false
    }

    // ---- microphone: CoreAudio ----
    private static func audioIDs(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector,
                                 _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var a = AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(obj, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func audioUInt32(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> UInt32? {
        var a = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &v) == noErr ? v : nil
    }

    static func microphoneInUse() -> Bool {
        let system = AudioObjectID(kAudioObjectSystemObject)
        if #available(macOS 14.2, *) {
            // Per-process: is any other app recording audio right now? (Exact, and ignores music playback.)
            let me = getpid()
            for p in audioIDs(system, kAudioHardwarePropertyProcessObjectList) {
                guard audioUInt32(p, kAudioProcessPropertyIsRunningInput) == 1 else { continue }
                var a = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID, mScope: kAudioObjectPropertyScopeGlobal,
                                                   mElement: kAudioObjectPropertyElementMain)
                var pid: pid_t = 0
                var size = UInt32(MemoryLayout<pid_t>.size)
                if AudioObjectGetPropertyData(p, &a, 0, nil, &size, &pid) == noErr, pid == me { continue }
                return true
            }
            return false
        }
        // Older macOS: an input-only device (built-in mic, USB mic) that is running means something is recording.
        for dev in audioIDs(system, kAudioHardwarePropertyDevices) {
            let inputs = audioIDs(dev, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
            let outputs = audioIDs(dev, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput)
            if !inputs.isEmpty && outputs.isEmpty && audioUInt32(dev, kAudioDevicePropertyDeviceIsRunningSomewhere) == 1 {
                return true
            }
        }
        return false
    }

    // ---- full-screen app in front (Keynote / PowerPoint slideshow, video, game) ----
    static func foregroundIsFullScreen() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() else { return false }
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }

        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)
        let screens = displays.map { CGDisplayBounds($0) }

        for w in info {
            guard (w[kCGWindowOwnerPID as String] as? Int).map({ pid_t($0) }) == front.processIdentifier,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: b) else { continue }
            // A window that covers a whole display, menu bar included. (Zoomed windows stop below the menu bar.)
            for d in screens where r.minX <= d.minX && r.minY <= d.minY && r.maxX >= d.maxX && r.maxY >= d.maxY {
                return true
            }
        }
        return false
    }
}
