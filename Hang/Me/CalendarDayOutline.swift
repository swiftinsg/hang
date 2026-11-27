//
//  CalendarDayOutline.swift
//  Hang
//
//  Month cells need one outline colour even when several events cover the
//  day. The colour comes from the event that occupies the most time on that
//  day, clipped to the day so an event that started yesterday doesn't win
//  just because it is long overall.
//

import SwiftUI

/// One event's contribution to a single month cell.
struct CalendarDayEvent: Identifiable {
    let id: String
    /// Full start time, used to lay out the mini timeline inside the cell.
    let start: Double
    /// Full duration, also used by the mini timeline.
    let duration: Double
    /// Portion of the event that actually falls on the day; decides the outline.
    let overlap: Double
    /// Colour the event is drawn with everywhere on this device.
    let color: Color
    /// Set only for shared group events, which also get a hangout image.
    let hangColor: HangColors?

    private static func make(
        id: String,
        start: Date,
        end: Date,
        dayStart: Date,
        dayEnd: Date,
        color: Color,
        hangColor: HangColors?
    ) -> CalendarDayEvent? {
        let visibleStart = max(start, dayStart)
        let visibleEnd = min(end, dayEnd)
        let overlap = visibleEnd.timeIntervalSince(visibleStart)
        guard overlap > 0 else { return nil }

        return CalendarDayEvent(
            id: id,
            start: start.timeIntervalSince1970,
            duration: max(end.timeIntervalSince(start), overlap),
            overlap: overlap,
            color: color,
            hangColor: hangColor
        )
    }

    /// A shared event keeps the colour chosen for its group in More Info.
    static func group(
        _ event: GroupEvents,
        dayStart: Date,
        dayEnd: Date
    ) -> CalendarDayEvent? {
        make(
            id: event.id.uuidString,
            start: event.startDate,
            end: event.endDate,
            dayStart: dayStart,
            dayEnd: dayEnd,
            color: event.groupColor.col,
            hangColor: event.groupColor
        )
    }

    /// Personal events created in Hang use this device's local colour choice.
    static func personal(
        _ event: GroupEvents,
        storedColors: [String: String],
        dayStart: Date,
        dayEnd: Date
    ) -> CalendarDayEvent? {
        make(
            id: PersonalEventColorKey.personal(event.id),
            start: event.startDate,
            end: event.endDate,
            dayStart: dayStart,
            dayEnd: dayEnd,
            color: PersonalEventColors.color(
                in: storedColors,
                for: PersonalEventColorKey.personal(event.id),
                default: .gray
            ),
            hangColor: nil
        )
    }

    /// Events imported from the device calendar follow the same local choice.
    static func imported(
        _ event: PersonalCalendarEvent,
        storedColors: [String: String],
        dayStart: Date,
        dayEnd: Date
    ) -> CalendarDayEvent? {
        make(
            id: PersonalEventColorKey.imported(event.id),
            start: event.startDate,
            end: event.endDate,
            dayStart: dayStart,
            dayEnd: dayEnd,
            color: PersonalEventColors.color(
                in: storedColors,
                for: PersonalEventColorKey.imported(event.id),
                default: .gray
            ),
            hangColor: nil
        )
    }
}

enum CalendarDayOutline {
    /// The event with the longest presence on the day owns the cell outline.
    /// A group event wins a tie so shared hangouts stay recognisable, then the
    /// earlier event wins so the result is stable across refreshes.
    private static func longest(
        _ events: [CalendarDayEvent]
    ) -> CalendarDayEvent? {
        events.max { lhs, rhs in
            if lhs.overlap != rhs.overlap {
                return lhs.overlap < rhs.overlap
            }
            if (lhs.hangColor == nil) != (rhs.hangColor == nil) {
                return rhs.hangColor != nil
            }
            return lhs.start > rhs.start
        }
    }

    static func color(for events: [CalendarDayEvent]) -> Color? {
        longest(events)?.color
    }

    /// Image matching the longest group event on the day, if there is one.
    static func groupColor(for events: [CalendarDayEvent]) -> HangColors? {
        longest(events.filter { $0.hangColor != nil })?.hangColor
    }
}
