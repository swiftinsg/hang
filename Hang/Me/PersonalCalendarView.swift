//
//  PersonalCalendarView.swift
//  Hang
//
//  The signed-in person's own month calendar. It shows imported device
//  calendars and group events that fall on the same days.
//
//  Nothing on this screen is shared: the busy blocks published to groups are
//  anonymous intervals produced elsewhere, and event titles stay here.
//

import EventKit
import SwiftUI

struct PersonalCalendarView: View {
    let groupEvents: [GroupEvents]

    private let calendar: Calendar = {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }()

    @State private var displayedMonth: Date = Date()
    @State private var selectedDate: Date? = Date()
    @State private var isShowingLegend = false
    @State private var calendarStore = PersonalCalendarStore.shared

    // MARK: - Month grid

    private func generateMonthGrid() -> [Date] {
        guard
            let monthInterval = calendar.dateInterval(
                of: .month,
                for: displayedMonth
            ),
            let firstWeek = calendar.dateInterval(
                of: .weekOfMonth,
                for: monthInterval.start
            ),
            let lastWeek = calendar.dateInterval(
                of: .weekOfMonth,
                for: monthInterval.end.addingTimeInterval(-1)
            )
        else {
            return []
        }

        var dates: [Date] = []
        var currentDate = firstWeek.start

        while currentDate < lastWeek.end {
            dates.append(currentDate)

            guard
                let nextDate = calendar.date(
                    byAdding: .day,
                    value: 1,
                    to: currentDate
                )
            else {
                break
            }

            currentDate = nextDate
        }

        return dates
    }

    private var weekdays: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        return Array(symbols[1...6] + [symbols[0]])
    }

    private var todayWeekdayIndex: Int {
        let originalIndex = calendar.component(.weekday, from: Date()) - 1
        return (originalIndex + 6) % 7
    }

    private func changeMonth(by value: Int) {
        displayedMonth =
            calendar.date(byAdding: .month, value: value, to: displayedMonth)
            ?? displayedMonth
    }

    private func weekdayCell(at index: Int) -> some View {
        let isToday = index == todayWeekdayIndex

        let textColor: Color = isToday ? .primary : .gray

        let backgroundColor: Color =
            isToday
            ? .secondary.opacity(0.4)
            : .secondary.opacity(0.2)

        return Text(weekdays[index])
            .font(.subheadline)
            .frame(maxWidth: .infinity)
            .foregroundStyle(textColor)
            .padding(.vertical, 3)
            .background(
                backgroundColor,
                in: RoundedRectangle(cornerRadius: 8)
            )
    }

    // MARK: - Body

    var body: some View {
        // The whole calendar scrolls as one page, so the day view below the
        // month grid stays fully visible without its own scroller.
        ScrollView {
            VStack(spacing: 2) {
                monthHeader

                if !calendarStore.hasFullAccess {
                    calendarAccessBanner
                        .padding(.top, 8)
                }

                monthGrid
                    .padding(.top, 4)

                Divider()
                    .padding(.vertical, 8)

                PersonalDayAvailabilityView(
                    date: selectedDate ?? Date(),
                    personalEvents: personalEvents,
                    groupEvents: groupEvents,
                    calendar: calendar
                )
            }
            .padding(15)
        }
        .task {
            await calendarStore.requestAccessIfNeeded()
        }
    }

    /// Imported events with the Hang-written marker removed: those are group
    /// events and are already drawn as such, so showing them twice would make
    /// the day look busier than it is.
    private var personalEvents: [PersonalCalendarEvent] {
        calendarStore.events.filter { $0.linkedEventID == nil }
    }

    // MARK: - Calendar access

    @ViewBuilder
    private var calendarAccessBanner: some View {
        if calendarStore.authorizationStatus == .notDetermined
            || calendarStore.authorizationStatus == .writeOnly {
            Button {
                Task { await calendarStore.requestAccessIfNeeded() }
            } label: {
                Label("Import your calendar", systemImage: "calendar.badge.plus")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(.orange)
                    .background(
                        Color.orange.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
            }
            .buttonStyle(.plain)
        } else if calendarStore.authorizationStatus == .denied
                    || calendarStore.authorizationStatus == .restricted {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .foregroundStyle(.orange)
                Text("Calendar access is off. Enable it in Settings to see your events here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(
                Color.orange.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
    }

    private var monthHeader: some View {
        VStack(spacing: 24) {
            HStack {
                Button {
                    changeMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }

                Spacer()
                Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                Spacer()
                Button {
                    changeMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }

                Button {
                    isShowingLegend = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("Personal calendar legend")
                .popover(isPresented: $isShowingLegend) {
                    CalendarLegendView(
                        title: "Personal Calendar Legend",
                        entries: [
                            CalendarLegendEntry(title: "Free", fill: .purple.opacity(0.45)),
                            CalendarLegendEntry(title: "Your calendar busy", fill: .gray.opacity(0.3), stroke: .orange),
                            CalendarLegendEntry(title: "Event", fill: .clear, stroke: .orange),
                        ]
                    )
                    .presentationCompactAdaptation(.popover)
                }
            }
            .tint(.primary)
            .padding(.horizontal)

            HStack(spacing: 2) {
                ForEach(weekdays.indices, id: \.self) { index in
                    weekdayCell(at: index)
                }
            }
        }
    }

    private var monthGrid: some View {
        let days = generateMonthGrid()

        return LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 2),
                count: 7
            ),
            spacing: 2
        ) {
            ForEach(days, id: \.self) { date in
                dayCell(for: date)
            }
        }
    }

    // A single day in the month grid, including its shading, outlines, and
    // event marker.
    private func dayCell(for date: Date) -> some View {
        let isCurrentMonth = calendar.isDate(
            date,
            equalTo: displayedMonth,
            toGranularity: .month
        )

        let isSelected =
            selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false

        let hasPersonalEvents = !calendarStore
            .events(on: date, calendar: calendar)
            .filter { $0.linkedEventID == nil }
            .isEmpty

        let hasGroupEvents = groupEvents.contains {
            calendar.isDate($0.startTime, inSameDayAs: date)
        }
        let hasEvents = hasPersonalEvents || hasGroupEvents

        return Button {
            selectedDate = date
        } label: {
            Text("\(calendar.component(.day, from: date))")
                .font(.subheadline)
                .frame(maxWidth: .infinity, minHeight: 45)
                .overlay(alignment: .bottom) {
                    if hasEvents {
                        HStack(spacing: 2) {
                            if hasPersonalEvents {
                                Image(systemName: "calendar")
                            }
                            if hasGroupEvents {
                                Image(systemName: "person.3")
                            }
                        }
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.orange)
                        .padding(.bottom, 4)
                    }
                }
                .foregroundStyle(isCurrentMonth ? .primary : .secondary)
                .background(
                    // Imported calendar events gray the day out; free days stay
                    // the personal-calendar purple.
                    hasPersonalEvents
                        ? Color.gray.opacity(isCurrentMonth ? 0.32 : 0.12)
                        : Color.purple.opacity(isCurrentMonth ? 0.5 : 0.2),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay {
                    // Days that already have an event.
                    if hasEvents {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.orange, lineWidth: 2)
                            .padding(2)
                    }
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.purple, lineWidth: 2.5)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview {
    PersonalCalendarView(groupEvents: PreviewData.events)
}
#endif
