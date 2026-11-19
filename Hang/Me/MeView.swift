import EventKit
import SwiftUI

struct MeView: View {
    // Keep the group in state so events added from this screen actually stay
    // in the calendar instead of being written to a throwaway value.
    @State private var tg = TestGroup(
        code: "HELLO1", name: "CODZEE",
        events: [
            GroupEvents(name: "event1", time: 1_720_708_600),
            GroupEvents(name: "event2", time: 1_790_403_500),
        ]
    )

    var body: some View {
        NavigationStack {
            VStack {
                PersonalCalendarView(tg: $tg)
            }
            .navigationTitle("My Calendar")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: ProfileView()) {
                        Label("Profile", systemImage: "person.fill")
                    }
                }
            }
        }
    }
}

#Preview {
    MeView()
}

struct PersonalCalendarView: View {
    var sizing = Sizing()
    var colors = Colors()
    @Binding var tg: TestGroup

    private let calendar: Calendar = {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }()

    @State private var displayedMonth: Date = Date()
    @State private var selectedDate: Date? = Date()
    @State private var isShowingCreateEvent = false
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

    var body: some View {
        // The whole calendar scrolls as one page, so the day timeline below
        // the month grid stays fully visible without its own scroller.
        ScrollView {
            VStack(spacing: 2) {
                monthHeader

                if !calendarStore.hasFullAccess {
                    calendarAccessBanner
                        .padding(.top, 8)
                }

                monthGrid

                Divider()
                    .padding(.vertical, 8)

                PersonalDayTimelineView(
                    date: selectedDate ?? Date(),
                    personalEvents: calendarStore.events,
                    appEvents: tg.events,
                    calendar: calendar
                )
            }
            .padding(15)
            // Leave room so the floating add button never covers the last row.
            .padding(.bottom, 60)
        }
        .task {
            await calendarStore.requestAccessIfNeeded()
        }
        .onAppear {
            calendarStore.loadEventsIfAuthorized()
        }
        .overlay(alignment: .bottomTrailing) {
            createEventButton
        }
        .sheet(isPresented: $isShowingCreateEvent) {
            CreateEventView(
                tg: $tg,
                initialDate: selectedDate ?? Date()
            )
            .presentationDetents([.medium, .large])
        }
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
                    .foregroundStyle(colors.dgreen)
                    .background(
                        colors.green.opacity(0.15),
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
            .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
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

    // A single day in the month grid, including its availability shading,
    // outlines, and event marker.
    private func dayCell(for date: Date) -> some View {
        let isCurrentMonth = calendar.isDate(
            date,
            equalTo: displayedMonth,
            toGranularity: .month
        )

        let isSelected =
            selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false

        let personalEventsToday = calendarStore.events(on: date, calendar: calendar)
        let hasPersonalEvents = !personalEventsToday.isEmpty
        let hasAppEvents = tg.events.contains {
            calendar.isDate(
                Date(timeIntervalSince1970: $0.time),
                inSameDayAs: date
            )
        }
        let hasEvents = hasPersonalEvents || hasAppEvents

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
                            
                        }
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.orange)
                        .padding(.bottom, 4)
                    }
                }
                .foregroundStyle(isCurrentMonth ? .primary : .secondary)
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
                            .strokeBorder(colors.dgreen, lineWidth: 2.5)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // Floating action button, pinned to the bottom of the screen so it stays
    // reachable while the calendar page is scrolled.
    private var createEventButton: some View {
        Button {
            isShowingCreateEvent = true
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(colors.dgreen, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
        }
        .padding(20)
        .accessibilityLabel("New event")
    }
}
