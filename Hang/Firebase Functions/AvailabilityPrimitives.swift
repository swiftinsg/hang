//
//  AvailabilityPrimitives.swift
//  Hang
//
//  The bottom layer for availability sharing. Nothing here depends on
//  Firebase, EventKit or SwiftUI.
//
//  The wire format deliberately has no place for event titles: a published day
//  is a date string and a flat list of start/end milliseconds (start, end,
//  start, end, ...). Firestore rejects arrays nested inside arrays, so the
//  [start, end] pairs used in Swift are flattened at the document boundary.
//  That is the whole payload other members ever receive.
//

import Foundation

// MARK: - Dates and intervals

extension Date {
    /// Milliseconds since 1970. The Firestore payload uses integers so it does
    /// not depend on how a Timestamp happens to be decoded on another device.
    var ms: Int {
        Int((timeIntervalSince1970 * 1000).rounded())
    }

    init(ms: Int) {
        self.init(timeIntervalSince1970: Double(ms) / 1000)
    }
}

extension DateInterval {
    /// Crops the interval to `window`, or returns nil when there is no overlap.
    func clamped(to window: DateInterval) -> DateInterval? {
        let start = max(self.start, window.start)
        let end = min(self.end, window.end)
        guard start < end else { return nil }
        return DateInterval(start: start, end: end)
    }
}

/// Interval arithmetic shared by the calculator and the publisher.
enum IntervalMath {
    /// Sorts and coalesces overlapping or touching intervals. Used before
    /// upload (one member must not look like two people) and during free-time
    /// subtraction, never on the way to the day timeline.
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
/// A day published from another phone only means something with its zone.
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
}

// MARK: - Shared availability

/// One member's busy blocks for one day. Only start and end times are ever
/// published.
struct BusyDay: Codable, Hashable {
    /// `yyyy-MM-dd` in the publishing member's time zone.
    var date: String
    /// `[startMillis, endMillis]` pairs, clamped and merged but carrying no
    /// title, location, calendar name or event identifier.
    var intervals: [[Int]]

    /// Firestore cannot store an array inside an array, so each pair is written
    /// as two consecutive numbers: `[start1, end1, start2, end2, ...]`.
    func flatIntervals() -> [Int] {
        intervals.flatMap { pair in
            pair.count == 2 ? pair : []
        }
    }

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
}

/// What the UI is allowed to claim about a member.
enum MemberAvailabilityStatus: Hashable {
    case sharing
    case stale
    case notSharing
}
