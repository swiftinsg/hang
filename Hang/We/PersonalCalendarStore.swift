//
//  PersonalCalendarStore.swift
//  Hang
//
//  Imports the person's own calendar through EventKit so their busy time can
//  be shown alongside group availability, and so events created in the app can
//  be written back to the device calendar.
//
//  Only the signed-in person's own events ever live here. Other members' busy
//  time arrives through Firestore as start/end pairs, never as event titles.
//

import EventKit
import Foundation
import Observation

/// A calendar event imported from the person's device calendars.
struct PersonalCalendarEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarTitle: String
    /// Set when this device event was written by Hang for a group event.
    ///
    /// Without it the same event is imported twice — once as personal busy
    /// time and once as a group event — so the timeline draws two bars for one
    /// commitment and the day looks busier than it is.
    var linkedEventID: String? = nil
}

/// Owns the EventKit event store and the imported events for the app.
///
/// The store is a shared singleton so the personal calendar, the group
/// calendar, and the day timelines all read the same imported data.
@Observable
final class PersonalCalendarStore {
    static let shared = PersonalCalendarStore()

    private(set) var events: [PersonalCalendarEvent] = []
    private(set) var authorizationStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let eventStore = EKEventStore()
    @ObservationIgnored private var changeObserver: NSObjectProtocol?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?

    private init() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleReload()
        }
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
        reloadTask?.cancel()
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

    /// Coalesces the burst of change notifications Calendar.app emits while a
    /// single event is edited. Without this a reload — and, from Checkpoint D,
    /// an availability upload — fires on every keystroke.
    func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.loadEventsIfAuthorized()
        }
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

    /// Writes an event created in the app to the person's default calendar so
    /// it also appears in the Calendar app. Returns an error message when the
    /// save fails, or `nil` on success.
    ///
    /// `linkedEventID` is written into the event notes as a marker so the next
    /// import can tell "Hang put this here" from "a real calendar event".
    func saveEventToCalendar(
        title: String,
        notes: String,
        startDate: Date,
        endDate: Date,
        linkedEventID: String? = nil
    ) async -> String? {
        // Writing needs at least write-only access. If the person has never
        // been asked, prompt once so the event can actually be saved.
        var status = EKEventStore.authorizationStatus(for: .event)
        if status == .notDetermined {
            do {
                _ = try await eventStore.requestFullAccessToEvents()
            } catch {
                return error.localizedDescription
            }
            status = EKEventStore.authorizationStatus(for: .event)
        }

        authorizationStatus = status

        guard status == .fullAccess || status == .writeOnly else {
            return "Calendar access is off, so the event was only added to the group calendar."
        }

        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            return "No default calendar is available to save this event."
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = title

        var payload = notes
        if let linkedEventID {
            payload += "\n\n\(Self.marker(for: linkedEventID))"
        }
        event.notes = payload.isEmpty ? nil : payload

        event.startDate = startDate
        event.endDate = endDate
        event.calendar = calendar

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
        } catch {
            return error.localizedDescription
        }

        // Refresh imported events so the new event shows up immediately.
        loadEventsIfAuthorized()
        return nil
    }

    // MARK: - Hang event markers

    private static let markerPrefix = "[[hang:"

    /// Written into `EKEvent.notes`. Round-trips the group event's id.
    static func marker(for eventID: String) -> String {
        "\(markerPrefix)\(eventID)]]"
    }

    /// Reads the marker back out of imported event notes.
    static func linkedEventID(in notes: String?) -> String? {
        guard let notes, let start = notes.range(of: markerPrefix) else { return nil }
        let rest = notes[start.upperBound...]
        guard let end = rest.firstIndex(of: "]") else { return nil }
        return String(rest[..<end])
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
                calendarTitle: event.calendar?.title ?? "Calendar",
                linkedEventID: Self.linkedEventID(in: event.notes)
            )
        }

        events = imported.sorted { $0.startDate < $1.startDate }
        errorMessage = nil
    }
}
