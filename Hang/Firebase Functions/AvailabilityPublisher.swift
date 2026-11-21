//
//  AvailabilityPublisher.swift
//  Hang
//
//  Uploads only when the signed-in person is busy.
//
//  PRIVACY CONTRACT — read before changing anything in this file.
//
//  A member's calendar never leaves their phone. What is published is a list of
//  anonymous start/end pairs, in milliseconds, for the next few weeks. No
//  titles, no notes, no locations, no calendar names, no attendee lists, no
//  event identifiers. Both event types are reduced to `DateInterval` before a
//  document is built, and the document builder only ever sees intervals, so a
//  title cannot leak by accident.
//
//  Other people can therefore answer "when are they busy?" and nothing else.
//  There is no code path anywhere that sends an event name.
//

import FirebaseFirestore
import Foundation
import Observation

@Observable
final class AvailabilityPublisher {
    static let shared = AvailabilityPublisher()

    private let deviceCalendar = PersonalCalendarStore.shared
    private let hangCalendar = PersonalEventsStore.shared

    /// Resolved lazily so previews can reference the publisher before
    /// `FirebaseApp.configure()` has run.
    private var db: Firestore { Firestore.firestore() }

    private let calendar = Calendar.current

    /// How far ahead busy time is published. Long enough to plan, short enough
    /// that the document stays small and stale data ages out quickly.
    var horizonDays = 30

    /// Don't re-upload more often than this when responding to calendar edits.
    var minimumInterval: TimeInterval = 15 * 60

    private(set) var errorMessage: String?

    @ObservationIgnored private var lastPublish: [String: Date] = [:]
    @ObservationIgnored private var inFlight: Set<String> = []
    @ObservationIgnored private var isPaused = false
    @ObservationIgnored private var pendingAfterResume: Set<String> = []

    // MARK: - Payload

    /// The signed-in person's busy blocks, reduced to anonymous intervals.
    ///
    /// Both the Firestore personal calendar and the device calendar are
    /// included. Overlaps are merged within this one member so a single person
    /// never reads as two people in the timeline.
    func busyDays() -> [BusyDay] {
        let timeZone = TimeZone.current
        let today = calendar.startOfDay(for: Date())

        let ownEvents = hangCalendar.events.map {
            DateInterval(start: $0.startDate, end: $0.endDate)
        }
        let deviceEvents = deviceCalendar.events.map {
            DateInterval(start: $0.startDate, end: $0.endDate)
        }
        let busy = IntervalMath.merge(ownEvents + deviceEvents)

        var days: [BusyDay] = []
        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today)
            else { continue }

            let dayStart =
                calendar.date(
                    byAdding: .hour,
                    value: AvailabilityDay.startHour,
                    to: day
                ) ?? day
            let dayEnd =
                calendar.date(
                    byAdding: .hour,
                    value: AvailabilityDay.endHour,
                    to: day
                ) ?? day
            let dayWindow = DateInterval(start: dayStart, end: dayEnd)

            let intervals = busy
                .compactMap { $0.clamped(to: dayWindow) }
                .map { [$0.start.ms, $0.end.ms] }

            guard !intervals.isEmpty else { continue }

            days.append(
                BusyDay(
                    date: DayKey.key(for: day, in: timeZone),
                    intervals: intervals
                )
            )
        }

        return days
    }

    // MARK: - Writing

    /// Replaces this member's published availability for one group.
    ///
    /// The document has exactly three fields. The rules reject anything else,
    /// and none of the three can carry an event title.
    func publish(to groupID: String, uid: String) async throws {
        guard !groupID.isEmpty else { return }
        if isPaused {
            pendingAfterResume.insert(groupID)
            return
        }
        guard !inFlight.contains(groupID) else { return }
        inFlight.insert(groupID)
        defer { inFlight.remove(groupID) }

        let days = busyDays()

        try await db
            .collection(Path.Firestore.Groups)
            .document(groupID)
            .collection(Path.Firestore.Availability)
            .document(uid)
            .setData([
                "timezoneIdentifier": TimeZone.current.identifier,
                "updatedAt": FieldValue.serverTimestamp(),
                // Firestore rejects nested arrays, so each [start, end] pair
                // goes over the wire as two consecutive numbers.
                "days": days.map { ["date": $0.date, "intervals": $0.flatIntervals()] },
            ])

        lastPublish[groupID] = Date()
        await MainActor.run {
            self.errorMessage = nil
        }
    }

    /// Stops sharing with one group. The document is deleted rather than
    /// emptied so there is nothing left to read.
    func unpublish(from groupID: String, uid: String) async {
        guard !groupID.isEmpty else { return }
        try? await db
            .collection(Path.Firestore.Groups)
            .document(groupID)
            .collection(Path.Firestore.Availability)
            .document(uid)
            .delete()
        lastPublish[groupID] = nil
    }

    /// Prevents availability writes while account deletion removes them.
    func pausePublishing() {
        isPaused = true
    }

    /// Resumes writes and returns groups that changed while paused. The caller
    /// can refresh those after a cancelled/failed deletion, or discard them
    /// after the account has been deleted.
    @discardableResult
    func resumePublishing() -> [String] {
        isPaused = false
        defer { pendingAfterResume.removeAll() }
        return pendingAfterResume.sorted()
    }

    /// Waits for uploads that were already running when publishing was paused.
    func waitForPendingPublishes() async {
        while !inFlight.isEmpty {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Publishes to every group that is due for a refresh.
    func refresh(groups: [String], uid: String, force: Bool = false) async {
        if isPaused {
            pendingAfterResume.formUnion(groups)
            return
        }

        for groupID in groups {
            if !force,
               let last = lastPublish[groupID],
               Date().timeIntervalSince(last) < minimumInterval {
                continue
            }
            do {
                try await publish(to: groupID, uid: uid)
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
