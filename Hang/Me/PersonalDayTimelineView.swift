//
//  PersonalDayTimelineView.swift
//  Hang
//
//  The personal calendar uses the same availability timeline as the shared
//  calendar, with a single "You" column. Personal events stay editable here.
//
//  Below the timeline it lists every event happening on the selected day so
//  each event's colour is visible next to its title as well as in the bar.
//

import SwiftUI

struct PersonalDayTimelineView: View {
    let date: Date
    let importedEvents: [PersonalCalendarEvent]
    let personalEvents: [GroupEvents]
    let groupEvents: [GroupEvents]
    let calendar: Calendar

    /// Owned by `PersonalCalendarView`'s AppStorage, so colour changes update
    /// both the timeline and the month grid. Never written to Firestore.
    @Binding var storedColors: [String: String]
    /// Fallback colour for group events loaded without a saved group colour.
    var groupColor: Color = .blue

    /// Called when a personal event is tapped. Group events stay read only on
    /// this screen because they belong to the We calendar.
    var onEditPersonalEvent: ((GroupEvents) -> Void)? = nil

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("hma")
        return formatter
    }()

    private var dayStart: Date {
        calendar.startOfDay(for: date)
    }

    private var dayEnd: Date {
        calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
    }

    /// Events that overlap the selected day, including ones that began earlier
    /// or run into the next day.
    private var dayImportedEvents: [PersonalCalendarEvent] {
        importedEvents
            .filter { $0.startDate < dayEnd && $0.endDate > dayStart }
            .sorted { $0.startDate < $1.startDate }
    }

    private var dayPersonalEvents: [GroupEvents] {
        personalEvents
            .filter { $0.startDate < dayEnd && $0.endDate > dayStart }
            .sorted { $0.startDate < $1.startDate }
    }

    private var dayGroupEvents: [GroupEvents] {
        groupEvents
            .filter { $0.startDate < dayEnd && $0.endDate > dayStart }
            .sorted { $0.startDate < $1.startDate }
    }

    private var eventCount: Int {
        dayImportedEvents.count + dayPersonalEvents.count + dayGroupEvents.count
    }

    private var hasEvents: Bool {
        eventCount > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DayAvailabilityView(
                date: date,
                members: [Person.currentUser],
                calendar: calendar,
                groupEvents: groupEvents,
                personalEvents: personalEvents,
                importedEvents: importedEvents,
                storedColors: $storedColors,
                groupColor: groupColor,
                onEditPersonalEvent: onEditPersonalEvent
            )

            if hasEvents {
                eventInformation
            } else {
                emptyState
            }
        }
    }

    // MARK: - Day event information

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(
                    .green.adjusted(saturation: 0.75, brightness: -0.25)
                )
            Text("No events. You're free all day.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var eventInformation: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Events")
                    .font(.subheadline.bold())
                Text("\(eventCount) event\(eventCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            if !dayImportedEvents.isEmpty {
                eventSection(title: "Imported events", icon: "calendar") {
                    ForEach(dayImportedEvents) { event in
                        importedEventRow(event)
                    }
                }
            }

            if !dayPersonalEvents.isEmpty {
                eventSection(title: "Personal events", icon: "calendar.badge.plus") {
                    ForEach(dayPersonalEvents) { event in
                        personalEventRow(event)
                    }
                }
            }

            if !dayGroupEvents.isEmpty {
                eventSection(title: "Group events", icon: "person.3.fill") {
                    ForEach(dayGroupEvents) { event in
                        groupEventRow(event)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func eventSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func importedEventRow(_ event: PersonalCalendarEvent) -> some View {
        let key = PersonalEventColorKey.imported(event.id)
        let color = PersonalEventColors.color(
            in: storedColors,
            for: key,
            default: .gray
        )

        return HStack(alignment: .top, spacing: 8) {
            colorBar(color: color)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)

                HStack(spacing: 5) {
                    Text(timeText(for: event))
                    Text("•")
                    Text(event.calendarTitle)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
            colorMenu(key: key, defaultColor: .gray)
        }
    }

    private func personalEventRow(_ event: GroupEvents) -> some View {
        let key = PersonalEventColorKey.personal(event.id)
        let color = PersonalEventColors.color(
            in: storedColors,
            for: key,
            default: .gray
        )

        return HStack(alignment: .top, spacing: 8) {
            Group {
                if let onEditPersonalEvent {
                    Button {
                        onEditPersonalEvent(event)
                    } label: {
                        personalEventRowContent(event, color: color)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .accessibilityHint("Edit or delete this event")
                } else {
                    personalEventRowContent(event, color: color)
                }
            }

            Spacer(minLength: 0)
            colorMenu(key: key, defaultColor: .gray)
        }
    }

    private func personalEventRowContent(
        _ event: GroupEvents,
        color: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            colorBar(color: color)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)

                if !event.desc.isEmpty {
                    Text(event.desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if !event.location.isEmpty {
                    Text(event.location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text(timeText(for: event))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func groupEventRow(_ event: GroupEvents) -> some View {
        // Group events all use the colour set for their group in More Info.
        HStack(alignment: .top, spacing: 8) {
            colorBar(color: event.groupColor ?? groupColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)

                if !event.desc.isEmpty {
                    Text(event.desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if !event.location.isEmpty {
                    Text(event.location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text(timeText(for: event))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func colorBar(color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 3)
    }

    /// Writes only to this device's AppStorage, keyed by the event's ID.
    private func colorMenu(key: String, defaultColor: Color) -> some View {
        EventOutlineColorMenu(
            selection: Binding(
                get: { PersonalEventColors.choice(in: storedColors, for: key) },
                set: { PersonalEventColors.setChoice($0, in: &storedColors, for: key) }
            ),
            displayColor: PersonalEventColors.color(
                in: storedColors,
                for: key,
                default: defaultColor
            )
        )
    }

    // MARK: - Helpers

    private func timeText(for event: PersonalCalendarEvent) -> String {
        if event.isAllDay {
            return "All day"
        }
        return
            "\(Self.timeFormatter.string(from: event.startDate)) – \(Self.timeFormatter.string(from: event.endDate))"
    }

    private func timeText(for event: GroupEvents) -> String {
        "\(Self.timeFormatter.string(from: event.startDate)) – \(Self.timeFormatter.string(from: event.endDate))"
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
                        .timeIntervalSince1970,
                    groupColor: .blue
                )
            ],
            calendar: calendar,
            storedColors: .constant([:])
        )
        .padding()
    }
}
