//
//  PersonalCalendarStore.swift
//  Hang
//
//  Imports the person's own calendar through EventKit so their busy time can
//  be shown alongside the events in Hang.
//

import EventKit
import Foundation
import Observation

/// A calendar event imported from the person's device calendars.
struct PersonalCalendarEvent: Identifiable, Hashable {
    let id: String
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var calendarTitle: String
}

/// Owns the EventKit event store and the imported events for the app.
///
/// The store is a shared singleton so the personal calendar and the day
/// timeline read the same imported data.
@Observable
final class PersonalCalendarStore {
    static let shared = PersonalCalendarStore()

    private(set) var events: [PersonalCalendarEvent] = []
    private(set) var authorizationStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let eventStore = EKEventStore()
    @ObservationIgnored private var changeObserver: NSObjectProtocol?

    private init() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.loadEvents()
            }
        }
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

    var hasFullAccess: Bool {
        authorizationStatus == .fullAccess
    }

    /// Asks for calendar access the first time, then imports events.
    func requestAccessIfNeeded() async {
        let status = EKEventStore.authorizationStatus(for: .event)
        authorizationStatus = status

        if status == .fullAccess {
            loadEvents()
            return
        }

        // Read access requires full access. If the app only has write-only
        // access, ask to upgrade it as well.
        guard status == .notDetermined || status == .writeOnly else { return }

        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            if granted {
                loadEvents()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Refreshes imported events without prompting for permission.
    func loadEventsIfAuthorized() {
        let status = EKEventStore.authorizationStatus(for: .event)
        authorizationStatus = status
        guard status == .fullAccess else { return }
        loadEvents()
    }

    /// Events that overlap the day containing `date`.
    func events(on date: Date, calendar: Calendar = .current) -> [PersonalCalendarEvent] {
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return []
        }

        return events.filter { event in
            event.startDate < dayEnd && event.endDate > dayStart
        }
    }

    /// Fetches a two-year window of events around today.
    private func loadEvents() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        guard
            let start = calendar.date(byAdding: .year, value: -1, to: today),
            let end = calendar.date(byAdding: .year, value: 2, to: today)
        else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let imported = eventStore.events(matching: predicate).compactMap { event -> PersonalCalendarEvent? in
            guard let startDate = event.startDate, let endDate = event.endDate else {
                return nil
            }

            return PersonalCalendarEvent(
                id: "\(event.eventIdentifier ?? UUID().uuidString)-\(startDate.timeIntervalSince1970)",
                title: event.title ?? "Untitled event",
                startDate: startDate,
                endDate: endDate,
                isAllDay: event.isAllDay,
                calendarTitle: event.calendar?.title ?? "Calendar"
            )
        }

        events = imported.sorted { $0.startDate < $1.startDate }
        errorMessage = nil
    }
}
