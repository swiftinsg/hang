//
//  ReminderScheduler.swift
//  Hang
//
//  Account-wide reminders. The user picks one global offset in ProfileView and
//  Hang schedules a local notification for every upcoming event (personal,
//  group, and imported from the device calendar) on this device.
//
//  Nothing is sent to a server: notifications are generated locally from the
//  events the app already has, so they work without APNs or Firebase Messaging.
//

import Foundation
import UserNotifications

extension Notification.Name {
    /// Posted when notification permission is granted so the active views can
    /// schedule reminders for events that were already loaded.
    static let hangRemindersShouldResync = Notification.Name("hang.reminders.resync")
}

/// The account-wide reminder choice stored at `users/<uid>.reminderPreference`.
enum ReminderPreference: String, Codable, CaseIterable, Identifiable {
    case none = "none"
    case oneDayBefore = "1day"
    case twoHoursBefore = "2hours"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "No reminder"
        case .oneDayBefore: return "1 day before"
        case .twoHoursBefore: return "2 hours before"
        }
    }
}

enum ReminderPermission {
    case granted
    case notDetermined
    case denied
}

/// One event to schedule a reminder for, normalised across the app's three
/// event sources.
struct ReminderEvent: Equatable {
    enum Source: String, Equatable {
        case personal, group, device
    }

    let id: String
    let source: Source
    let title: String
    let startDate: Date
    let location: String
}

@MainActor
final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderScheduler()

    private static let identifierPrefix = "hang.reminder."
    /// iOS keeps only the soonest 64 pending requests per app, so stay under it.
    private static let maximumScheduledReminders = 60

    private let center = UNUserNotificationCenter.current()
    /// Guards against overlapping syncs leaving a stale set of requests behind.
    private var syncGeneration = 0

    private override init() {
        super.init()
        center.delegate = self
    }

    /// Safe to call from app startup; the singleton also sets itself as the
    /// delegate when it is first created.
    func configure() {
        center.delegate = self
    }

    // MARK: - Permission

    func permissionStatus() async -> ReminderPermission {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .granted
        case .notDetermined:
            return .notDetermined
        default:
            return .denied
        }
    }

    /// Call from a user action (the preference picker) so iOS shows its prompt.
    @discardableResult
    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            if granted {
                NotificationCenter.default.post(
                    name: .hangRemindersShouldResync,
                    object: nil
                )
            }
            return granted
        } catch {
            print("Error requesting notification permission: \(error)")
            return false
        }
    }

    // MARK: - Scheduling

    /// Replaces every reminder Hang has scheduled with one per upcoming event.
    /// Called whenever events or the preference change, so edits, deletions and
    /// switching the preference never leave stale notifications behind.
    func sync(events: [ReminderEvent], preference: ReminderPreference) async {
        syncGeneration += 1
        let generation = syncGeneration

        let existingIDs = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) }

        guard generation == syncGeneration else { return }
        center.removePendingNotificationRequests(withIdentifiers: existingIDs)

        guard preference != .none else { return }
        guard await permissionStatus() == .granted else { return }
        guard generation == syncGeneration else { return }

        let now = Date()
        let candidates: [(event: ReminderEvent, fireDate: Date)] = events.compactMap { event in
            guard let fireDate = fireDate(for: event, preference: preference),
                  fireDate > now else { return nil }
            return (event, fireDate)
        }
        .sorted { $0.fireDate < $1.fireDate }

        for candidate in candidates.prefix(Self.maximumScheduledReminders) {
            guard generation == syncGeneration else { return }

            let content = UNMutableNotificationContent()
            content.title = candidate.event.title
            content.body = reminderBody(for: preference)
            content.sound = .default
            content.userInfo = [
                "eventID": candidate.event.id,
                "source": candidate.event.source.rawValue
            ]

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, candidate.fireDate.timeIntervalSince(now)),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: identifier(for: candidate.event),
                content: content,
                trigger: trigger
            )
            do {
                try await center.add(request)
            } catch {
                print("Error scheduling reminder: \(error)")
            }
        }
    }

    /// Drops all Hang reminders, e.g. when the user signs out.
    func cancelAll() async {
        syncGeneration += 1
        let ids = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Foreground presentation

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    // MARK: - Helpers

    private func identifier(for event: ReminderEvent) -> String {
        Self.identifierPrefix + event.source.rawValue + "." + event.id
    }

    private func fireDate(for event: ReminderEvent, preference: ReminderPreference) -> Date? {
        switch preference {
        case .none:
            return nil
        case .oneDayBefore:
            // Calendar arithmetic keeps the reminder at the same wall-clock
            // time even when daylight saving changes before the event.
            return Calendar.current.date(byAdding: .day, value: -1, to: event.startDate)
        case .twoHoursBefore:
            return event.startDate.addingTimeInterval(-2 * 60 * 60)
        }
    }

    /// Body: "happening in 1 day" / "happening in 2 hours". The title is the
    /// event name, set in `sync(events:preference:)`.
    private func reminderBody(for preference: ReminderPreference) -> String {
        switch preference {
        case .none:
            return ""
        case .oneDayBefore:
            return "happening in 1 day"
        case .twoHoursBefore:
            return "happening in 2 hours"
        }
    }
}
