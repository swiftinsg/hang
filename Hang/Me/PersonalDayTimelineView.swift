//
//  PersonalDayTimelineView.swift
//  Hang
//
//  Shows the person's imported calendar events and Hang events for one day on
//  an hour-by-hour timeline, using Hang's green colour scheme.
//

import SwiftUI

struct PersonalDayTimelineView: View {
    var colors = Colors()
    let date: Date
    let personalEvents: [PersonalCalendarEvent]
    let appEvents: [GroupEvents]
    let calendar: Calendar

    private let hourHeight: CGFloat = 34
    private let gutterWidth: CGFloat = 48
    private let startHour = AvailabilityDay.startHour
    private let endHour = AvailabilityDay.endHour

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

    private var window: DateInterval {
        AvailabilityCalculator(calendar: calendar).window(for: date)
    }

    private var dayStart: Date {
        calendar.startOfDay(for: date)
    }

    private var dayPersonalEvents: [PersonalCalendarEvent] {
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return []
        }

        return personalEvents.filter { event in
            event.startDate < dayEnd && event.endDate > dayStart
        }
    }

    /// Hang events that start on the selected day, in time order.
    private var dayAppEvents: [GroupEvents] {
        appEvents
            .filter { calendar.isDate(appEventStart($0), inSameDayAs: date) }
            .sorted { $0.time < $1.time }
    }

    private var allDayPersonalEvents: [PersonalCalendarEvent] {
        dayPersonalEvents.filter { $0.isAllDay }
    }

    private var timedPersonalEvents: [PersonalCalendarEvent] {
        dayPersonalEvents.filter { event in
            !event.isAllDay && overlaps(event.startDate, event.endDate, window)
        }
    }

    private var timedAppEvents: [GroupEvents] {
        dayAppEvents.filter { event in
            overlaps(appEventStart(event), appEventEnd(event), window)
        }
    }

    private var hasEvents: Bool {
        !dayPersonalEvents.isEmpty || !dayAppEvents.isEmpty
    }

    private var eventCount: Int {
        dayPersonalEvents.count + dayAppEvents.count
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

            if hasEvents {
                Text("\(eventCount) event\(eventCount == 1 ? "" : "s")")
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
                        CalendarLegendEntry(
                            title: "Free",
                            fill: colors.green.opacity(0.2)
                        ),
                        CalendarLegendEntry(
                            title: "Your calendar",
                            fill: colors.dgreen.opacity(0.85)
                        ),
                        CalendarLegendEntry(
                            title: "Hang event",
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
                .foregroundStyle(colors.dgreen)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(colors.green.opacity(0.18), in: Capsule())
            }
        }
    }

    /// A single-column timeline of the selected day. Imported calendar events
    /// are solid green and Hang events are dashed orange outlines.
    private var timeline: some View {
        HStack(alignment: .top, spacing: 6) {
            hourGutter

            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colors.green.opacity(0.12))

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

                    ForEach(timedAppEvents) { event in
                        timelineBlock(
                            start: appEventStart(event),
                            end: appEventEnd(event),
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
        let height = max(
            14,
            CGFloat(visibleEnd.timeIntervalSince(visibleStart) / 3600) * hourHeight - 2
        )
        let blockWidth = max(width - 8, 10)
        let fillColor =
            isPersonal ? colors.dgreen.opacity(0.85) : Color.orange.opacity(0.15)
        let strokeColor = isPersonal ? colors.dgreen : Color.orange

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

            if !dayAppEvents.isEmpty {
                eventSection(title: "Hang events", icon: "person.3.fill") {
                    ForEach(dayAppEvents) { event in
                        appEventRow(event)
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
                .fill(colors.dgreen)
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

    private func appEventRow(_ event: GroupEvents) -> some View {
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

                Text(
                    "\(Self.timeFormatter.string(from: appEventStart(event))) – \(Self.timeFormatter.string(from: appEventEnd(event)))"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(colors.dgreen)

            Text("No events. You're free all day.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func appEventStart(_ event: GroupEvents) -> Date {
        Date(timeIntervalSince1970: event.time)
    }

    private func appEventEnd(_ event: GroupEvents) -> Date {
        if let endTime = event.endTime {
            return Date(timeIntervalSince1970: endTime)
        }
        // Older events only store a start time, so show them for an hour.
        return appEventStart(event).addingTimeInterval(60 * 60)
    }

    private func timeText(for event: PersonalCalendarEvent) -> String {
        if event.isAllDay {
            return "All day"
        }
        return
            "\(Self.timeFormatter.string(from: event.startDate)) – \(Self.timeFormatter.string(from: event.endDate))"
    }

    private func hourLabel(for hour: Int) -> String {
        let offset = hour - startHour
        let hourDate =
            calendar.date(byAdding: .hour, value: offset, to: window.start)
            ?? window.start
        return Self.timeFormatter.string(from: hourDate)
    }

    private func overlaps(_ start: Date, _ end: Date, _ interval: DateInterval) -> Bool {
        start < interval.end && end > interval.start
    }
}

#Preview {
    let calendar = Calendar.current
    let today = Date()
    let day = calendar.startOfDay(for: today)

    return ScrollView {
        PersonalDayTimelineView(
            date: today,
            personalEvents: [
                PersonalCalendarEvent(
                    id: "1",
                    title: "Dentist",
                    startDate: calendar.date(byAdding: .hour, value: 9, to: day) ?? today,
                    endDate: calendar.date(byAdding: .hour, value: 10, to: day) ?? today,
                    isAllDay: false,
                    calendarTitle: "Personal"
                )
            ],
            appEvents: [
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
