//
//  Availability.swift
//  Hang
//
//  The one place free/busy is calculated. Three inputs feed it:
//
//    • the signed-in person's imported calendar (EventKit),
//    • group events, which block everybody,
//    • every other member's published busy blocks, read from Firestore.
//
//  Everything in the UI — the month heatmap, the busiest days, the day
//  timeline — goes through this type, so wiring real data in one place makes
//  every screen real at once.
//
//  Overlaps are deliberately *not* merged on the display path: the timeline
//  stacks translucent bars so two people busy at 3pm reads darker than one.
//  Merging is only used inside the free-time arithmetic, where it is invisible.
//

import Foundation

struct AvailabilityCalculator {
    var calendar: Calendar = .current
    var windowHours: DayWindow = .standard

    /// Events imported from the person's own calendars. These only block the
    /// current user's time.
    var personalEvents: [PersonalCalendarEvent] = []

    /// Events created inside the app for the group. These block everyone.
    var groupEvents: [GroupEvents] = []

    /// Busy blocks published by each member, keyed by uid.
    var sharedBusy: [String: [DateInterval]] = [:]

    /// When each published snapshot was last written, for staleness.
    var sharedUpdatedAt: [String: Date] = [:]

    /// Debug-only escape hatch. Previews set this so the timeline has something
    /// to draw; the mock generator itself is compiled out of release builds, so
    /// in release the flag can be set but has no effect.
    var useMockFallback = false

    // MARK: - Window

    /// The comparable hours for a given day, e.g. 8:00 to 22:00.
    func window(for date: Date) -> DateInterval {
        windowHours.window(for: date, calendar: calendar)
    }

    // MARK: - Busy

    /// Busy intervals for one member only.
    ///
    /// Imported events belong to the current user; other members use whatever
    /// they published. Intervals are clamped and sorted but **not merged**, so
    /// overlapping busy time stays visible as separate bars.
    func memberBusyIntervals(for member: Person, on date: Date) -> [DateInterval] {
        let window = window(for: date)
        var raw: [DateInterval]

        if member.isCurrentUser {
            raw = personalEvents
                // Events Hang itself wrote back are represented by the group
                // event, so counting them here would double the person up.
                .filter { $0.linkedEventID == nil }
                .map { DateInterval(start: $0.startDate, end: $0.endDate) }
        } else if let shared = sharedBusy[member.uid] {
            raw = shared
        } else {
            raw = fallbackBusyIntervals(for: member, on: date)
        }

        return raw
            .compactMap { $0.clamped(to: window) }
            .sorted { $0.start < $1.start }
    }

    /// Group events as separate bands. Keeping them separate from member busy
    /// blocks stops a long busy block being recoloured by an event that only
    /// overlaps part of it — and lets the timeline draw them distinctly.
    func groupEventIntervals(on date: Date) -> [(title: String, interval: DateInterval)] {
        let window = window(for: date)

        return groupEvents.compactMap { event in
            event.interval.clamped(to: window).map { (event.name, $0) }
        }
    }

    /// All busy time for one member: their own blocks plus group events.
    ///
    /// Concatenated, never merged, so a call site can still tell a personal
    /// block from a group band.
    func busyIntervals(for member: Person, on date: Date) -> [DateInterval] {
        (memberBusyIntervals(for: member, on: date)
            + groupEventIntervals(on: date).map(\.interval))
            .sorted { $0.start < $1.start }
    }

    // MARK: - Free

    /// The gaps between a member's busy intervals within the availability window.
    func freeIntervals(for member: Person, on date: Date) -> [DateInterval] {
        IntervalMath.subtract(
            busyIntervals(for: member, on: date),
            from: window(for: date)
        )
        .filter { $0.duration > 30 * 60 }
    }

    /// How free the whole group is on a day: 0 = nobody free, 1 = everyone free all day.
    func freeFraction(on date: Date, members: [Person]) -> Double {
        guard !members.isEmpty else { return 0 }

        let dayLength = window(for: date).duration
        guard dayLength > 0 else { return 0 }

        let freeDuration = members.reduce(0.0) { total, member in
            total + freeIntervals(for: member, on: date).reduce(0.0) { $0 + $1.duration }
        }

        return min(1, max(0, freeDuration / (dayLength * Double(members.count))))
    }

    // MARK: - Month summaries

    /// One pass over a month instead of one pass per visible cell.
    func dailyFractions(for days: [Date], members: [Person]) -> [Date: Double] {
        var result: [Date: Double] = [:]
        for day in days {
            result[calendar.startOfDay(for: day)] = freeFraction(on: day, members: members)
        }
        return result
    }

    // MARK: - What the UI may claim

    /// The one definition of "sharing / stale / not sharing" used by both the
    /// day columns and the member roster.
    ///
    /// `shared` is whether an availability document exists at all; a member
    /// who has never published is not secretly free, they are simply not
    /// sharing. A document written without a timestamp is still live data.
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
        // The current user knows their own calendar directly; there is no
        // round-trip to wait for, and their column is never hatched.
        if member.isCurrentUser { return .sharing }

        guard sharedBusy[member.uid] != nil else {
            return fallbackStatus()
        }

        return Self.sharedStatus(
            shared: true,
            updatedAt: sharedUpdatedAt[member.uid]
        )
    }

    // MARK: - Debug rows

    private func fallbackBusyIntervals(for member: Person, on date: Date) -> [DateInterval] {
        #if DEBUG
        return useMockFallback ? member.mockBusyIntervals(on: date, calendar: calendar) : []
        #else
        return []
        #endif
    }

    private func fallbackStatus() -> MemberAvailabilityStatus {
        #if DEBUG
        return useMockFallback ? .mock : .notSharing
        #else
        return .notSharing
        #endif
    }
}

// MARK: - Sample data (previews only)

#if DEBUG
private extension Person {
    /// Deterministic fake calendar data so the same day always looks the same.
    ///
    /// This is the only fabricated availability in the app, and it is compiled
    /// out of release builds. Nothing in shipping code calls it unless a
    /// preview sets `useMockFallback`.
    func mockBusyIntervals(on date: Date, calendar: Calendar) -> [DateInterval] {
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let isWeekend = calendar.isDateInWeekend(date)
        let patternCount = isWeekend ? 4 : 8
        let pattern = (dayOfYear + scheduleSeed * 3) % patternCount

        let dayStart = calendar.startOfDay(for: date)
        func slot(_ startHour: Int, _ endHour: Int) -> DateInterval {
            let start = calendar.date(byAdding: .hour, value: startHour, to: dayStart) ?? dayStart
            let end = calendar.date(byAdding: .hour, value: endHour, to: dayStart) ?? dayStart
            return DateInterval(start: start, end: end)
        }

        switch pattern {
        case 0: return []
        case 1: return [slot(9, 11)]
        case 2: return [slot(13, 15)]
        case 3: return [slot(9, 12), slot(18, 20)]
        case 4: return [slot(16, 22)]
        case 5: return [slot(8, 10), slot(12, 13), slot(15, 17)]
        case 6: return [slot(8, 22)]
        default: return [slot(11, 13), slot(19, 21)]
        }
    }
}
#endif
