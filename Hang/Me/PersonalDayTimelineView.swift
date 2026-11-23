//
//  PersonalDayTimelineView.swift
//  Hang
//
//  The personal calendar uses the same availability timeline as the shared
//  calendar, with a single "You" column. Personal events stay editable here.
//

import SwiftUI

struct PersonalDayTimelineView: View {
    let date: Date
    let importedEvents: [PersonalCalendarEvent]
    let personalEvents: [GroupEvents]
    let groupEvents: [GroupEvents]
    let calendar: Calendar

    /// Called when a personal event is tapped. Group events stay read only on
    /// this screen because they belong to the We calendar.
    var onEditPersonalEvent: ((GroupEvents) -> Void)? = nil

    var body: some View {
        DayAvailabilityView(
            date: date,
            members: [Person.currentUser],
            calendar: calendar,
            groupEvents: groupEvents,
            personalEvents: personalEvents,
            importedEvents: importedEvents,
            onEditPersonalEvent: onEditPersonalEvent
        )
    }
}

#Preview {
    let calendar = Calendar.current
    let today = Date()
    let day = calendar.startOfDay(for: today)

    return ScrollView {
        PersonalDayTimelineView(
            date: today,
            importedEvents: [
                PersonalCalendarEvent(
                    id: "1",
                    title: "Dentist",
                    startDate: calendar.date(byAdding: .hour, value: 9, to: day) ?? today,
                    endDate: calendar.date(byAdding: .hour, value: 10, to: day) ?? today,
                    isAllDay: false,
                    calendarTitle: "Personal"
                )
            ],
            personalEvents: [
                GroupEvents(
                    name: "Gym",
                    time: (calendar.date(byAdding: .hour, value: 12, to: day) ?? today)
                        .timeIntervalSince1970,
                    endTime: (calendar.date(byAdding: .hour, value: 13, to: day) ?? today)
                        .timeIntervalSince1970
                )
            ],
            groupEvents: [
                GroupEvents(
                    name: "Dinner",
                    desc: "Group dinner",
                    time: (calendar.date(byAdding: .hour, value: 18, to: day) ?? today)
                        .timeIntervalSince1970,
                    endTime: (calendar.date(byAdding: .hour, value: 20, to: day) ?? today)
                        .timeIntervalSince1970
                )
            ],
            calendar: calendar
        )
        .padding()
    }
}
