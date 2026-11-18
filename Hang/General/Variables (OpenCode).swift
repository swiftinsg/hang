//  Checkpoint A — shared primitives for real availability sharing.
//
//  Nothing in this file depends on Firebase, EventKit or SwiftUI; it is the
//  bottom of the dependency graph, so every later layer can build on it.
//  Everything here is internal to the Hang module on purpose.
//

import Foundation

// MARK: - Dates and intervals

extension Date {
    /// Milliseconds since 1970, used for the Firestore payload so the wire
    /// format never depends on how a Timestamp happens to be decoded.
    var ms: Int {
        Int((timeIntervalSince1970 * 1000).rounded())
    }

    init(ms: Int) {
        self.init(timeIntervalSince1970: Double(ms) / 1000)
    }
}

extension DateInterval {
    /// Crops the interval to `window`, or returns nil when the two do not
    /// overlap at all. Replaces the private `clampedInterval` that used to
    /// live inside `AvailabilityCalculator`.
    func clamped(to window: DateInterval) -> DateInterval? {
        let start = max(self.start, window.start)
        let end = min(self.end, window.end)
        guard start < end else { return nil }
        return DateInterval(start: start, end: end)
    }
}

/// Interval arithmetic shared by the calculator and the publisher.
///
/// Merging is used for *arithmetic only* — free-time subtraction — where
/// overlapping input is invisible. It is never applied to intervals on their
/// way to the UI: the day timeline stacks translucent bars so that two people
/// busy at 3pm reads darker than one, and that only works if the overlaps
/// survive.
enum IntervalMath {
    /// Sorts and coalesces overlapping or touching intervals.
    static func merge(_ intervals: [DateInterval]) -> [DateInterval] {
        var result: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = result.last, interval.start <= last.end {
                result[result.count - 1] = DateInterval(
                    start: last.start,
                    end: max(last.end, interval.end)
                )
            } else {
                result.append(interval)
            }
        }
        return result
    }

    /// Everything in `window` that is not covered by `busy`.
    static func subtract(
        _ busy: [DateInterval],
        from window: DateInterval
    ) -> [DateInterval] {
        var free = [window]

        for block in merge(busy) {
            free = free.flatMap { slot in
                guard slot.intersects(block) else { return [slot] }

                var remaining: [DateInterval] = []
                if slot.start < block.start {
                    remaining.append(
                        DateInterval(
                            start: slot.start,
                            end: min(block.start, slot.end)
                        )
                    )
                }
                if block.end < slot.end {
                    remaining.append(
                        DateInterval(
                            start: max(block.end, slot.start),
                            end: slot.end
                        )
                    )
                }
                return remaining
            }
        }

        return free
    }
}

// MARK: - Day keys

/// Stable `yyyy-MM-dd` strings, always resolved in an explicit time zone.
///
/// Availability is published from another person's phone, so "the 18th" only
/// means something alongside the zone it was written in.
enum DayKey {
    static func key(for date: Date, in timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0
        )
    }

    static func date(from key: String, in timeZone: TimeZone) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(
            from: DateComponents(
                year: parts[0],
                month: parts[1],
                day: parts[2]
            )
        )
    }
}

// MARK: - The compared part of the day

/// The hours availability is compared over, e.g. 8am to 10pm.
///
/// Was a pair of statics on `AvailabilityDay`; now a value so it can differ
/// per member later without every call site changing.
struct DayWindow: Hashable {
    var startHour: Int
    var endHour: Int

    static let standard = DayWindow(startHour: 8, endHour: 22)

    /// The concrete window on a given day. `AvailabilityCalculator.window(for:)`
    /// forwards to this so the maths exists in exactly one place.
    func window(for date: Date, calendar: Calendar) -> DateInterval {
        let dayStart = calendar.startOfDay(for: date)
        let start = calendar.date(
            byAdding: .hour,
            value: startHour,
            to: dayStart
        ) ?? dayStart
        let end = calendar.date(
            byAdding: .hour,
            value: endHour,
            to: dayStart
        ) ?? dayStart
        return DateInterval(start: start, end: end)
    }
}

// MARK: - Shared availability

/// One member's busy blocks for one day, in the shape written to Firestore.
///
/// Only start and end times are ever published; event titles stay on the
/// device that owns the calendar.
struct BusyDay: Codable, Hashable {
    /// `yyyy-MM-dd` in the publishing member's time zone.
    var date: String
    /// Flat `[startMillis, endMillis]` pairs, clamped and windowed but not
    /// coalesced, so the receiving device can still draw each block.
    var intervals: [[Int]]

    func dateIntervals() -> [DateInterval] {
        intervals.compactMap { pair in
            guard pair.count == 2 else { return nil }

            let start = Date(ms: pair[0])
            let end = Date(ms: pair[1])
            guard start < end else { return nil }

            return DateInterval(start: start, end: end)
        }
    }
}

/// A member's availability as read back from Firestore.
struct MemberAvailability: Hashable {
    var intervals: [DateInterval]
    var updatedAt: Date?
    var timezone: TimeZone

    /// How long a shared snapshot stays trustworthy before the UI calls it stale.
    static let staleAfter: TimeInterval = 48 * 60 * 60

    /// Free/busy is still usable when stale, it just cannot be presented as
    /// current. Callers decide how loud to be about that.
    func isStale(now: Date = Date()) -> Bool {
        guard let updatedAt else { return true }
        return now.timeIntervalSince(updatedAt) > Self.staleAfter
    }
}

/// What the UI is allowed to claim about a member.
///
/// `.mock` only exists for previews and never reaches a release build, because
/// the only producer of mock data is compiled out with `#if DEBUG`.
enum MemberAvailabilityStatus: Hashable {
    /// This member publishes their own busy times.
    case sharing
    /// Published, but older than `MemberAvailability.staleAfter`.
    case stale
    /// Joined the group, has not shared anything.
    case notSharing
    /// Debug/preview fixtures only.
    case mock
}
