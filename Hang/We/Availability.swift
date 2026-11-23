//
//  Availability.swift
//  Hang
//
//  Free/busy is derived only from data the app actually has:
//
//    • your personal events from Firestore (users/<uid>/calendar),
//    • events imported from your device calendar (EventKit),
//    • group events, which block everyone,
//    • the anonymous busy intervals other members publish to the group.
//
//  There is no generated, seeded, or random busy time. Members who have not
//  shared anything are left out of the score instead of being assumed free.
//

import FirebaseAuth
import FirebaseCore
import SwiftUI

extension Person {
    /// The signed-in person. The group calendar shows their personal calendar
    /// as an extra, read-only member column.
    static var currentUser: Person {
        let uid: String
        if FirebaseApp.app() != nil {
            uid = Auth.auth().currentUser?.uid ?? "current-user"
        } else {
            uid = "current-user"
        }
        return Person(
            uid: uid,
            name: "You",
            status: "Your personal calendar"
        )
    }

    /// True only for the signed-in account. Previews without a Firebase app
    /// use the local fallback uid above.
    var isCurrentUser: Bool {
        guard FirebaseApp.app() != nil else { return uid == "current-user" }
        return uid == Auth.auth().currentUser?.uid
    }

    /// Stable per-member colour used for avatars and busy blocks. Derived from
    /// the uid so it stays the same across launches, devices and views (the
    /// Profile preview uses this too). FNV-1a spreads different uids across the
    /// palette better than a simple character sum while staying deterministic.
    var tint: Color {
        let palette: [Color] = [
            .teal, .indigo, .orange, .pink, .purple, .blue, .mint,
        ]
        let seedSource = uid.isEmpty ? name : uid
        var hash: UInt32 = 2166136261
        for byte in seedSource.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16777619
        }
        return palette[Int(hash % UInt32(palette.count))]
    }
}

/// The part of the day that availability is compared over.
enum AvailabilityDay {
    static let startHour = 1
    static let endHour = 23
}

struct AvailabilityCalculator {
    var calendar: Calendar = .current

    /// Events created in Hang on the signed-in user's personal calendar.
    var personalEvents: [GroupEvents] = []

    /// Events imported from the signed-in user's device calendar.
    var importedEvents: [PersonalCalendarEvent] = []

    /// Shared events, which block every member of the group.
    var groupEvents: [GroupEvents] = []

    /// Busy blocks published by each member, keyed by Firebase uid.
    var sharedBusy: [String: [DateInterval]] = [:]

    /// When each published snapshot was last written, for staleness.
    var sharedUpdatedAt: [String: Date] = [:]

    /// The comparable hours for a given day, e.g. 8:00 to 22:00.
    func window(for date: Date) -> DateInterval {
        let dayStart = calendar.startOfDay(for: date)
        let start =
            calendar.date(
                byAdding: .hour,
                value: AvailabilityDay.startHour,
                to: dayStart
            ) ?? dayStart
        let end =
            calendar.date(
                byAdding: .hour,
                value: AvailabilityDay.endHour,
                to: dayStart
            ) ?? dayStart
        return DateInterval(start: start, end: end)
    }

    /// Real busy time we have for one member, before shared group events.
    ///
    /// Your own calendars are readable directly. Other members use the
    /// anonymous intervals they published, never an invented schedule.
    func memberBusyIntervals(for member: Person, on date: Date) -> [DateInterval] {
        let window = window(for: date)

        let raw: [DateInterval]
        if member.isCurrentUser {
            let ownEvents = personalEvents.map {
                DateInterval(start: $0.startDate, end: $0.endDate)
            }
            let deviceEvents = importedEvents.map {
                DateInterval(start: $0.startDate, end: $0.endDate)
            }
            raw = ownEvents + deviceEvents
        } else {
            raw = sharedBusy[member.uid] ?? []
        }

        return raw.compactMap { $0.clamped(to: window) }
            .sorted { $0.start < $1.start }
    }

    /// Group events that overlap the day. These block everybody.
    func groupEventIntervals(on date: Date) -> [DateInterval] {
        let window = window(for: date)
        return groupEvents.map {
            DateInterval(start: $0.startDate, end: $0.endDate)
        }
        .compactMap { $0.clamped(to: window) }
        .sorted { $0.start < $1.start }
    }

    /// All busy time for one member inside the availability window.
    func busyIntervals(for member: Person, on date: Date) -> [DateInterval] {
        (memberBusyIntervals(for: member, on: date)
            + groupEventIntervals(on: date))
            .sorted { $0.start < $1.start }
    }

    /// The gaps between a member's busy intervals within the availability window.
    func freeIntervals(for member: Person, on date: Date) -> [DateInterval] {
        IntervalMath.subtract(
            busyIntervals(for: member, on: date),
            from: window(for: date)
        )
        .filter { $0.duration > 30 * 60 }
    }

    /// How free the group is on a day: 0 = no known free time, 1 = all members
    /// whose availability is known are free all day.
    func freeFraction(on date: Date, members: [Person]) -> Double {
        let scored = members.filter { member in
            member.isCurrentUser || sharedBusy[member.uid] != nil
        }
        guard !scored.isEmpty else { return 0 }

        let dayLength = window(for: date).duration
        guard dayLength > 0 else { return 0 }

        let freeDuration = scored.reduce(0.0) { total, member in
            total
                + freeIntervals(for: member, on: date).reduce(0.0) {
                    $0 + $1.duration
                }
        }

        return min(
            1,
            max(0, freeDuration / (dayLength * Double(scored.count)))
        )
    }

    /// One pass over a month instead of one pass per visible cell.
    func dailyFractions(for days: [Date], members: [Person]) -> [Date: Double] {
        var result: [Date: Double] = [:]
        for day in days {
            result[calendar.startOfDay(for: day)] =
                freeFraction(on: day, members: members)
        }
        return result
    }

    /// The one definition of "sharing / stale / not sharing" used by the day
    /// columns and the heatmap.
    static func sharedStatus(
        shared: Bool,
        updatedAt: Date?,
        now: Date = Date()
    ) -> MemberAvailabilityStatus {
        guard shared else { return .notSharing }
        guard let updatedAt else { return .sharing }

        return now.timeIntervalSince(updatedAt) > MemberAvailability.staleAfter
            ? .stale
            : .sharing
    }

    func status(for member: Person) -> MemberAvailabilityStatus {
        if member.isCurrentUser { return .sharing }
        guard sharedBusy[member.uid] != nil else { return .notSharing }

        return Self.sharedStatus(
            shared: true,
            updatedAt: sharedUpdatedAt[member.uid]
        )
    }
}
