//
//  AvailabilityPublisher.swift
//  Hang
//
//  Uploads *only when* the signed-in person is busy.
//
//  PRIVACY CONTRACT — read before changing anything in this file.
//
//  A member's calendar never leaves their phone. What is published is a list
//  of anonymous start/end pairs, in milliseconds, for the next few weeks. No
//  titles, no notes, no locations, no calendar names, no attendee lists, no
//  event identifiers. `PersonalCalendarEvent` is reduced to `DateInterval`
//  before any document is built, and the document builder only ever sees
//  intervals, so a title cannot leak by accident.
//
//  Other people can therefore answer "when are they busy?" and nothing else.
//  There is no code path anywhere that sends an event name.
//
//  Intervals are merged *within one member* before upload. That is a privacy
//  measure as much as a correctness one: two overlapping blocks describe a
//  sharper picture of the day than one, and a single member must not read as
//  two people in the stacked timeline. Merging never happens across members.
//

import FirebaseFirestore
import Foundation
import Observation

@Observable
final class AvailabilityPublisher {
    static let shared = AvailabilityPublisher()

    private let store = PersonalCalendarStore.shared
    /// Resolved lazily so referencing the publisher cannot trap in a preview
    /// before `FirebaseApp.configure()` has run.
    private var db: Firestore { Firestore.firestore() }
    private let calendar = Calendar.current
    private let window = DayWindow.standard

    /// How far ahead busy time is published. Long enough to plan, short enough
    /// that the document stays small and stale data ages out quickly.
    var horizonDays = 30

    /// Don't re-upload more often than this when responding to calendar edits.
    var minimumInterval: TimeInterval = 15 * 60

    @ObservationIgnored private var lastPublish: [String: Date] = [:]
    /// Groups with an upload in progress. Keyed by group so that refreshing
    /// several groups does not make the second publish bail out — only a
    /// duplicate upload *of the same group* is suppressed.
    @ObservationIgnored private var inFlight: Set<String> = []

    // MARK: - Payload

    /// The signed-in person's busy blocks, reduced to anonymous intervals.
    ///
    /// Events Hang itself wrote back are skipped: those are group events, they
    /// are already shared as group events, and re-publishing them would make
    /// the same commitment count twice.
    func busyDays() -> [BusyDay] {
        let timeZone = TimeZone.current
        let today = calendar.startOfDay(for: Date())
        var days: [BusyDay] = []

        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else {
                continue
            }
            let dayWindow = window.window(for: day, calendar: calendar)

            let intervals = store.events
                .filter { $0.linkedEventID == nil }
                .map { DateInterval(start: $0.startDate, end: $0.endDate) }
                .compactMap { $0.clamped(to: dayWindow) }

            let busy = IntervalMath.merge(intervals)
            guard !busy.isEmpty else { continue }

            days.append(
                BusyDay(
                    date: DayKey.key(for: day, in: timeZone),
                    intervals: busy.map { [$0.start.ms, $0.end.ms] }
                )
            )
        }

        return days
    }

    // MARK: - Writing

    /// Replaces this member's published availability for one group.
    ///
    /// The document deliberately has exactly three fields; see the rules in
    /// `firestore.rules`, which reject anything else.
    func publish(to groupID: String, uid: String) async throws {
        guard !inFlight.contains(groupID) else { return }
        inFlight.insert(groupID)
        defer { inFlight.remove(groupID) }

        let days = busyDays()

        try await db
            .collection(Path.Firestore.groups)
            .document(groupID)
            .collection(Path.Firestore.availability)
            .document(uid)
            .setData([
                "timezoneIdentifier": TimeZone.current.identifier,
                "updatedAt": FieldValue.serverTimestamp(),
                "days": days.map { ["date": $0.date, "intervals": $0.intervals] },
            ])

        lastPublish[groupID] = Date()
    }

    /// Stops sharing with one group. Used when a member turns sharing off or
    /// leaves; the document is deleted rather than emptied so there is nothing
    /// left to read.
    func unpublish(from groupID: String, uid: String) async {
        try? await db
            .collection(Path.Firestore.groups)
            .document(groupID)
            .collection(Path.Firestore.availability)
            .document(uid)
            .delete()
        lastPublish[groupID] = nil
    }

    /// Publishes to every group that is due for a refresh.
    ///
    /// Called on sign-in, on foreground, when the calendar changes, and when a
    /// group is joined. Pass `force` after an explicit calendar edit.
    func refresh(groups: [String], uid: String, force: Bool = false) async {
        for groupID in groups {
            if !force,
               let last = lastPublish[groupID],
               Date().timeIntervalSince(last) < minimumInterval {
                continue
            }
            try? await publish(to: groupID, uid: uid)
        }
    }
}
