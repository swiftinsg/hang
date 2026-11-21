import EventKit
import SwiftUI

private enum PersonalCalendarSheet: Identifiable {
    case create
    case edit(GroupEvents)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let event):
            return "edit-\(event.id.uuidString)"
        }
    }
}

struct MeView: View {
    // Personal events are owned here. Group events are read from the shared
    // We store, so anything added in We appears here (one-way sync).
    @State private var groupStore = GroupStore.shared
    @State private var personalStore = PersonalEventsStore.shared

    var body: some View {
        @Bindable var personalStore = personalStore

        NavigationStack {
            VStack {
                PersonalCalendarView(
                    personalEvents: $personalStore.events,
                    groupEvents: groupStore.groups.first?.events ?? []
                )
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
    @Binding var personalEvents: [GroupEvents]
    let groupEvents: [GroupEvents]

    private let calendar: Calendar = {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }()

    @State private var displayedMonth: Date = Date()
    @State private var selectedDate: Date? = Date()
    @State private var activeSheet: PersonalCalendarSheet?
    @State private var calendarStore = PersonalCalendarStore.shared
    @State private var personalStore = PersonalEventsStore.shared
    @State private var cellSize: CGSize = .zero

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

    private func isPastDate(_ date: Date) -> Bool {
        date < calendar.startOfDay(for: Date())
    }

    /// Past days can't be selected, so never pass one to the timeline or a
    /// create sheet (e.g. if the app stays open past midnight).
    private var effectiveSelectedDate: Date {
        let selected = selectedDate ?? Date()
        return isPastDate(selected) ? Date() : selected
    }

    private func changeMonth(by value: Int) {
        displayedMonth =
            calendar.date(byAdding: .month, value: value, to: displayedMonth)
            ?? displayedMonth
    }

    private func weekdayCell(at index: Int) -> some View {
        let isToday = index == todayWeekdayIndex

        return Text(weekdays[index])
            .font(.subheadline)
            .frame(maxWidth: .infinity)
            .bold()
            .foregroundStyle(.secondary)
            .padding(.vertical, 3)
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
                    date: effectiveSelectedDate,
                    importedEvents: calendarStore.events,
                    personalEvents: personalEvents,
                    groupEvents: groupEvents,
                    calendar: calendar,
                    onEditPersonalEvent: { event in
                        activeSheet = .edit(event)
                    }
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
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .create:
                CreatePersonalEventView(
                    events: $personalEvents,
                    initialDate: effectiveSelectedDate,
                    onSave: { newEvents in
                        personalStore.add(newEvents)
                    }
                )
                .presentationDetents([.large])
            case .edit(let event):
                EditEventView(
                    events: $personalEvents,
                    eventID: event.id,
                    onSave: { updatedEvent in
                        personalStore.update(updatedEvent)
                    },
                    onDelete: { eventID in
                        personalStore.delete(eventID)
                    }
                )
                .presentationDetents([.medium, .large])
            }
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
//            .tint(.primary)
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

    // A single day in the month grid, including event markers and outlines.
    // Days before today are disabled and shown as plain gray cells.
    private func dayCell(for date: Date) -> some View {
        let isCurrentMonth = calendar.isDate(
            date,
            equalTo: displayedMonth,
            toGranularity: .month
        )
        let isPastDate = isPastDate(date)

        let isSelected = !isPastDate
            && (selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false)

        let dayStart = calendar.startOfDay(for: date)
        let dayEnd =
            calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        // Highlight every day an event covers, including the days in between
        // its start and end, so selecting a middle day still shows the event.
        // Past days never get markers or outlines.
        let hasCalendarEvents = !isPastDate && (
            !calendarStore.events(on: date, calendar: calendar).isEmpty
                || personalEvents.contains { event in
                    event.startDate < dayEnd && event.endDate > dayStart
                }
        )
        let hasGroupEvents = !isPastDate && groupEvents.contains { event in
            event.startDate < dayEnd && event.endDate > dayStart
        }
        let hasEvents = hasCalendarEvents || hasGroupEvents
        return Button {
            selectedDate = date
        } label: {
            Text("\(calendar.component(.day, from: date))")
                .font(.subheadline)
                .frame(maxWidth: .infinity, minHeight: 45)
                .foregroundStyle(
                    isPastDate
                        ? Color.secondary.opacity(0.45)
                        : (isCurrentMonth ? Color.primary : Color.secondary)
                )
                .background {
                    if isPastDate {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray5))
                    }
                }
                .overlay(alignment: .bottom) {
                    if hasEvents {
                        HStack(spacing: 2) {
                            if hasCalendarEvents {
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
                .overlay(alignment: .bottom) {
                    if hasEvents {
                        HStack(spacing: 2) {
                            if hasGroupEvents {
                                Image("flatHang")
                                    .resizable()
                                    .scaledToFit()
                                    .scaleEffect(0.7)
                                    .offset(y: cellSize.height*0.16)
                            } else if hasCalendarEvents {
                                Image(systemName: "calendar")
                            }
                        }
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.orange)
                        .padding(.bottom, 4)
                    }
                }

                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { newSize in
                    cellSize = newSize
                }
        }
        
        .buttonStyle(.plain)
        .disabled(isPastDate)
        .accessibilityLabel(
            isPastDate
                ? "\(calendar.component(.day, from: date)), unavailable past date"
                : "\(calendar.component(.day, from: date))"
        )
    }

    // Floating action button, pinned to the bottom of the screen so it stays
    // reachable while the calendar page is scrolled.
    private var createEventButton: some View {
        Button {
            activeSheet = .create
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
