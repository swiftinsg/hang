//
//  PreviewData.swift
//  Hang
//
//  Debug-only fixtures for SwiftUI previews.
//
//  Nothing here is used by a shipping path. The availability entries are
//  hand-written start/end pairs — the same shape the publisher writes — so the
//  preview never needs a Firebase app or access to the device calendar.
//

#if DEBUG

import Foundation

enum PreviewData {
    static let groupID = "preview"

    static var members: [Person] { SampleData.members }

    static var group: TestGroup {
        var group = TestGroup(
            code: "ABC123",
            name: "Preview Group",
            desc: "A group for trying out the calendar.",
            ownerUid: SampleData.currentUid,
            memberUids: members.map(\.uid)
        )
        group.id = groupID
        return group
    }

    static var events: [GroupEvents] {
        [
            event(id: "preview-event-1", name: "Dinner", at: 0, startHour: 18, endHour: 19),
            event(id: "preview-event-2", name: "Study session", at: 1, startHour: 13, endHour: 15),
        ]
    }

    /// Availability as it would arrive from Firestore: one entry per member,
    /// with the final member deliberately absent so the "not shared" hatch is
    /// visible in previews. The second member is stale on purpose.
    static func availability(for members: [Person]) -> [String: MemberAvailability] {
        var result: [String: MemberAvailability] = [:]

        for (index, member) in members.enumerated() {
            // The last member never published: they demonstrate `notSharing`.
            guard index < members.count - 1 else { continue }

            let intervals: [DateInterval]
            switch index {
            case 0:
                // Overlapping blocks: the timeline stacks them and the overlap
                // reads darker, which is the display rule we want to check.
                intervals = [
                    interval(dayOffset: 0, startHour: 9, endHour: 11),
                    interval(dayOffset: 0, startHour: 10, endHour: 12),
                    interval(dayOffset: 0, startHour: 16, endHour: 18),
                ]
            case 1:
                intervals = [
                    interval(dayOffset: 0, startHour: 13, endHour: 15),
                    interval(dayOffset: 0, startHour: 19, endHour: 20),
                ]
            default:
                intervals = [
                    interval(dayOffset: 0, startHour: 8, endHour: 10),
                    interval(dayOffset: 0, startHour: 14, endHour: 17),
                ]
            }

            let updatedAt = index == 1
                ? Date().addingTimeInterval(-3 * 24 * 60 * 60)
                : Date()

            result[member.uid] = MemberAvailability(
                intervals: intervals,
                updatedAt: updatedAt,
                timezone: .current
            )
        }

        return result
    }

    // MARK: - Helpers

    private static func interval(dayOffset: Int, startHour: Int, endHour: Int) -> DateInterval {
        let calendar = Calendar.current
        let day = calendar.date(
            byAdding: .day,
            value: dayOffset,
            to: calendar.startOfDay(for: Date())
        ) ?? Date()

        let start = calendar.date(byAdding: .hour, value: startHour, to: day) ?? day
        let end = calendar.date(byAdding: .hour, value: endHour, to: day) ?? day
        return DateInterval(start: start, end: end)
    }

    private static func event(
        id: String,
        name: String,
        at dayOffset: Int,
        startHour: Int,
        endHour: Int
    ) -> GroupEvents {
        let calendar = Calendar.current
        let day = calendar.date(
            byAdding: .day,
            value: dayOffset,
            to: calendar.startOfDay(for: Date())
        ) ?? Date()
        let start = calendar.date(byAdding: .hour, value: startHour, to: day) ?? day
        let end = calendar.date(byAdding: .hour, value: endHour, to: day) ?? day

        var event = GroupEvents(
            name: name,
            desc: "A preview event.",
            startTime: start,
            endTime: end,
            createdBy: SampleData.currentUid
        )
        event.id = id
        return event
    }
}

#endif
