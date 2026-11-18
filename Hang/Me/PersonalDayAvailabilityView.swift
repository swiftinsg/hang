//
//  PersonalDayAvailabilityView.swift
//  Hang
//
//  Shows the person's imported calendar events for one day, plus any group
//  events planned in the app. This is the only timeline that displays titles
//  for imported events, because it never leaves the device that owns them.
//

import SwiftUI

struct PersonalDayAvailabilityView: View {
    let date: Date
    let personalEvents: [PersonalCalendarEvent]
    let groupEvents: [GroupEvents]
    let calendar: Calendar

    private let hourHeight: CGFloat = 34
    private let gutterWidth: CGFloat = 48
    private let startHour = DayWindow.standard.startHour
    private let endHour = DayWindow.standard.endHour

    @State private var isShowingLegend = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("hma")
        return formatter
    }()

    // MARK: - Day data

    private var dayStart: Date {
        calendar.startOfDay(for: date)
    }

    private var window: DateInterval {
        AvailabilityCalculator(calendar: calendar).window(for: date)
    }

    private var dayPersonalEvents: [PersonalCalendarEvent] {
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return []
        }

        return personalEvents.filter { event in
            event.startDate < dayEnd && event.endDate > dayStart
        }
    }

    private var dayGroupEvents: [GroupEvents] {
        groupEvents.filter {
            calendar.isDate($0.startTime, inSameDayAs: date)
        }
    }

    private var allDayPersonalEvents: [PersonalCalendarEvent] {
        dayPersonalEvents.filter { $0.isAllDay }
    }

    private var timedPersonalEvents: [PersonalCalendarEvent] {
        dayPersonalEvents.filter { event in
            !event.isAllDay && overlaps(event.startDate, event.endDate, window)
        }
    }

    private var timedGroupEvents: [GroupEvents] {
        dayGroupEvents.filter { event in
            overlaps(event.startTime, event.endTime, window)
        }
    }

    private var hasEvents: Bool {
        !dayPersonalEvents.isEmpty || !dayGroupEvents.isEmpty
    }

    private var timelineHeight: CGFloat {
        CGFloat(endHour - startHour) * hourHeight
    }

    private var hours: [Int] {
        Array(startHour..<endHour)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if hasEvents {
                if !allDayPersonalEvents.isEmpty {
                    allDayEvents
                }

                timeline
                eventList
            } else {
                emptyState
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Your day")
                .font(.subheadline.bold())

            Text(Self.dateFormatter.string(from: date))
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if !dayPersonalEvents.isEmpty {
                Text("\(dayPersonalEvents.count) calendar event\(dayPersonalEvents.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                isShowingLegend = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Your day legend")
            .popover(isPresented: $isShowingLegend) {
                CalendarLegendView(
                    title: "Your Day Legend",
                    entries: [
                        CalendarLegendEntry(title: "Free", fill: .purple.opacity(0.2)),
                        CalendarLegendEntry(title: "Your calendar event", fill: .purple.opacity(0.85)),
                        CalendarLegendEntry(
                            title: "Group event",
                            fill: .orange.opacity(0.15),
                            stroke: .orange,
                            dashed: true
                        ),
                    ]
                )
                .presentationCompactAdaptation(.popover)
            }
        }
    }

    private var allDayEvents: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(allDayPersonalEvents) { event in
                HStack(spacing: 5) {
                    Image(systemName: "sun.max.fill")
                        .font(.caption2)
                    Text(event.title)
                        .font(.caption)
                        .lineLimit(1)
                    Text("All day")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.purple)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.purple.opacity(0.12), in: Capsule())
            }
        }
    }

    /// A single-column timeline of the person's day. Personal events are solid
    /// purple and group events are dashed orange outlines.
    private var timeline: some View {
        HStack(alignment: .top, spacing: 6) {
            hourGutter

            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.purple.opacity(0.12))

                    hourLines

                    ForEach(timedPersonalEvents) { event in
                        timelineBlock(
                            start: event.startDate,
                            end: event.endDate,
                            title: event.title,
                            isPersonal: true,
                            width: proxy.size.width
                        )
                    }

                    ForEach(timedGroupEvents) { event in
                        timelineBlock(
                            start: event.startTime,
                            end: event.endTime,
                            title: event.name,
                            isPersonal: false,
                            width: proxy.size.width
                        )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .frame(height: timelineHeight)
        }
    }

    private var hourGutter: some View {
        VStack(spacing: 0) {
            ForEach(hours, id: \.self) { hour in
                Text(hourLabel(for: hour))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(
                        width: gutterWidth - 4,
                        height: hourHeight,
                        alignment: .topTrailing
                    )
                    .padding(.trailing, 4)
                    .offset(y: -5)
            }
        }
        .frame(width: gutterWidth)
        .allowsHitTesting(false)
    }

    private var hourLines: some View {
        Canvas { context, size in
            for index in 0...hours.count {
                let y = CGFloat(index) * hourHeight
                var path = SwiftUI.Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(
                    path,
                    with: .color(Color.primary.opacity(index == 0 ? 0.18 : 0.10)),
                    lineWidth: 0.6
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func timelineBlock(
        start: Date,
        end: Date,
        title: String,
        isPersonal: Bool,
        width: CGFloat
    ) -> some View {
        let visibleStart = max(start, window.start)
        let visibleEnd = min(end, window.end)
        let y = CGFloat(visibleStart.timeIntervalSince(window.start) / 3600) * hourHeight
        let height = max(14, CGFloat(visibleEnd.timeIntervalSince(visibleStart) / 3600) * hourHeight - 2)
        let blockWidth = max(width - 8, 10)
        let fillColor = isPersonal ? Color.purple.opacity(0.85) : Color.orange.opacity(0.15)
        let strokeColor = isPersonal ? Color.purple : Color.orange

        return RoundedRectangle(cornerRadius: 6)
            .fill(fillColor)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        strokeColor,
                        style: StrokeStyle(
                            lineWidth: 1.5,
                            dash: isPersonal ? [] : [3, 2]
                        )
                    )
            }
            .overlay(alignment: .topLeading) {
                if height > 20 {
                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isPersonal ? .white : .orange)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                }
            }
            .frame(width: blockWidth, height: height)
            .offset(x: 4, y: y)
    }

    private var eventList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !dayPersonalEvents.isEmpty {
                eventSection(title: "Your calendar", icon: "calendar") {
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
    }

    private func personalEventRow(_ event: PersonalCalendarEvent) -> some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.purple)
                .frame(width: 3)

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
        }
    }

    private func groupEventRow(_ event: GroupEvents) -> some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.orange)
                .frame(width: 3)

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

                Text(timeText(for: event))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.purple)
            Text("No events. You're free all day.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func hourLabel(for hour: Int) -> String {
        let offset = hour - startHour
        let hourDate = calendar.date(byAdding: .hour, value: offset, to: window.start) ?? window.start
        return Self.timeFormatter.string(from: hourDate)
    }

    private func timeText(for event: PersonalCalendarEvent) -> String {
        if event.isAllDay {
            return "All day"
        }
        return rangeText(start: event.startDate, end: event.endDate)
    }

    private func timeText(for event: GroupEvents) -> String {
        rangeText(start: event.startTime, end: event.endTime)
    }

    private func rangeText(start: Date, end: Date) -> String {
        "\(Self.timeFormatter.string(from: start)) – \(Self.timeFormatter.string(from: end))"
    }

    private func overlaps(_ start: Date, _ end: Date, _ interval: DateInterval) -> Bool {
        start < interval.end && end > interval.start
    }
}

#if DEBUG
#Preview {
    let calendar = Calendar.current
    let today = Date()
    let day = calendar.startOfDay(for: today)

    return ScrollView {
        PersonalDayAvailabilityView(
            date: today,
            personalEvents: [
                PersonalCalendarEvent(
                    id: "1",
                    title: "Dentist",
                    startDate: calendar.date(byAdding: .hour, value: 9, to: day) ?? today,
                    endDate: calendar.date(byAdding: .hour, value: 10, to: day) ?? today,
                    isAllDay: false,
                    calendarTitle: "Personal"
                ),
                PersonalCalendarEvent(
                    id: "2",
                    title: "Team standup",
                    startDate: calendar.date(byAdding: .hour, value: 14, to: day) ?? today,
                    endDate: calendar.date(byAdding: .hour, value: 15, to: day) ?? today,
                    isAllDay: false,
                    calendarTitle: "Work"
                ),
            ],
            groupEvents: PreviewData.events,
            calendar: calendar
        )
        .padding()
    }
}
#endif
