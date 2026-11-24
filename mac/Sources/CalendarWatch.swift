import EventKit
import Foundation

/// Optional calendar awareness (Settings → Smart → Use my calendar). Reads only event times and whether
/// you're busy; nothing is stored or sent anywhere. Used to hold breaks during meetings and to move a
/// stretch break forward when a meeting would otherwise interrupt it.
final class CalendarWatch {
    static let shared = CalendarWatch()
    private let store = EKEventStore()
    private var cache: [EKEvent] = []
    private var cachedAt = Date.distantPast

    var authorized: Bool {
        let st = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) { return st == .fullAccess }
        return st.rawValue == 3 // .authorized before macOS 14
    }

    var denied: Bool {
        let st = EKEventStore.authorizationStatus(for: .event)
        return st == .denied || st == .restricted
    }

    func requestAccess(_ done: @escaping (Bool) -> Void) {
        let finish: (Bool, Error?) -> Void = { ok, _ in DispatchQueue.main.async { done(ok) } }
        if #available(macOS 14.0, *) { store.requestFullAccessToEvents(completion: finish) }
        else { store.requestAccess(to: .event, completion: finish) }
    }

    /// Timed events you're busy for, from an hour ago to two hours ahead (refreshed at most once a minute).
    private func events(_ now: Date) -> [EKEvent] {
        guard authorized else { return [] }
        if now.timeIntervalSince(cachedAt) > 60 {
            let pred = store.predicateForEvents(withStart: now.addingTimeInterval(-3600), end: now.addingTimeInterval(7200), calendars: nil)
            cache = store.events(matching: pred).filter { e in
                guard !e.isAllDay, e.availability != .free, e.status != .canceled else { return false }
                // Skip meetings you declined
                if let me = e.attendees?.first(where: { $0.isCurrentUser }), me.participantStatus == .declined { return false }
                return true
            }
            cachedAt = now
        }
        return cache
    }

    /// The meeting happening right now, if any.
    func meetingNow(_ now: Date = Date()) -> EKEvent? {
        events(now).first { $0.startDate <= now && $0.endDate > now }
    }

    /// The next meeting starting within `seconds`.
    func meetingStarting(within seconds: TimeInterval, _ now: Date = Date()) -> EKEvent? {
        events(now).filter { $0.startDate > now && $0.startDate.timeIntervalSince(now) <= seconds }.min { $0.startDate < $1.startDate }
    }
}
