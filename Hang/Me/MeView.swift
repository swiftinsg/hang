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
                    // Every group the user belongs to, not just the first one.
                    // Each event carries its group's display colour.
                    groupEvents: groupStore.groups.flatMap(\.events)
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

    /// Per-event outline colours are local to this device, never online.
    @AppStorage(PersonalEventColors.storageKey) private var colorsJSON: String = PersonalEventColors.emptyJSON
    private var storedColors: Binding<[String: String]> {
        PersonalEventColors.binding($colorsJSON)
    }

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
    
    /// The personal calendar behaves like a normal calendar: any date can be selected, including past dates, so they can be viewed and edited.
    private var effectiveSelectedDate: Date {
        selectedDate ?? Date()
    }
    
    private func changeMonth(by value: Int) {
        displayedMonth =
        calendar.date(byAdding: .month, value: value, to: displayedMonth)
        ?? displayedMonth
    }
    
    private func weekdayCell(at index: Int) -> some View {
        
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
                    calendar: calendar, storedColors: storedColors,
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
        .refreshable {
            await AppReloader.reloadAll()
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
                    .foregroundStyle(.black)
                    .background(
                        .accent.opacity(0.15),
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
    
    private func dayCell(for date: Date) -> some View {
        var cellSize: CGSize = .zero
        let isCurrentMonth = calendar.isDate(
            date,
            equalTo: displayedMonth,
            toGranularity: .month
        )
        let isSelected = selectedDate.map {
            calendar.isDate($0, inSameDayAs: date)
        } ?? false
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd =
        calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        
        // Highlight every day an event covers, including the days in between its start and end, so selecting a middle day still shows the event.
        
        var groupEventsToday = groupEvents.filter { event in
            event.startDate < dayEnd && event.endDate > dayStart
        }
        var savedEventsToday: Array<PersonalCalendarEvent> = calendarStore.events(on: date, calendar: calendar)
        var personalEventsToday = personalEvents.filter { event in
            event.startDate < dayEnd && event.endDate > dayStart
        }
        var hasCalendarEvents =
        !personalEventsToday.isEmpty || !savedEventsToday.isEmpty
        var hasGroupEvents = !groupEventsToday.isEmpty
        var eventsToday = {
            var groupEventTimes: [EventTime] = {
                groupEventsToday.compactMap { EventTime(start: $0.time, dur: $0.endDate.timeIntervalSince($0.startDate), color: $0.color) }
            }()
            groupEventTimes +=  {
                personalEventsToday.compactMap { EventTime(start: $0.time, dur: $0.endDate.timeIntervalSince($0.startDate), color: $0.color) }
            }()
            let personalEventTimes: [EventTime] = {
                savedEventsToday.compactMap { EventTime(start: $0.startDate.timeIntervalSince1970, dur: $0.endDate.timeIntervalSince($0.startDate), color: $0.color) }
            }()
            let sortedTimes = groupEventTimes + personalEventTimes.sorted {
                if $0.start == $1.start { return $0.dur > $1.dur }
                return $0.start < $1.start
            }
            let firstTime = sortedTimes.first?.start
            let lastTime = sortedTimes.map { $0.start + $0.dur }.max()
            return (sortedTimes, (lastTime ?? 86400.0)-(firstTime ?? 0), (firstTime ?? 0), ((lastTime ?? 86400.0)))
        }()
        var capsWidth: Double = {
            if hasGroupEvents {
                return 0.6
            } else {
                return 0.65
            }
        }()
        return Button {
            selectedDate = date
        } label: {
            VStack(spacing: 0) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.subheadline)
                    .foregroundStyle(isCurrentMonth ? Color.primary : Color.secondary)
                if hasGroupEvents || hasCalendarEvents {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .frame(width: cellSize.width*capsWidth, height: cellSize.height*0.1)
                            .hidden()
                        ForEach(0..<eventsToday.0.count, id: \.self) { x in
                            let offsetX = CGFloat((eventsToday.0[x].start - eventsToday.2) / eventsToday.1)*cellSize.width*capsWidth
                            let eventWidth = max(CGFloat(eventsToday.0[x].dur / eventsToday.1)*cellSize.width*capsWidth, 2)
                            Capsule()
                                .foregroundStyle(eventsToday.0[x].color)
                                .frame(width: eventWidth, height: cellSize.height*0.1)
                                .offset(x: offsetX)
                            
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 45)
            .overlay {
                ZStack {
                    if hasGroupEvents {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(storedColors.green.col, lineWidth: 2)
                            .padding(2)
                    } else if hasCalendarEvents {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.orange, lineWidth: 2)
                            .padding(2)
                    }
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.accentColor, lineWidth: 2.5)
                    }
                }
            }
            .onChange(of: personalEvents) {
                groupEventsToday = groupEvents.filter { event in
                    event.startDate < dayEnd && event.endDate > dayStart
                }
                savedEventsToday = calendarStore.events(on: date, calendar: calendar)
                personalEventsToday = personalEvents.filter { event in
                    event.startDate < dayEnd && event.endDate > dayStart
                }
                hasCalendarEvents =
                !personalEventsToday.isEmpty || !savedEventsToday.isEmpty
                hasGroupEvents = !groupEventsToday.isEmpty
                eventsToday = {
                    var groupEventTimes: [EventTime] = {
                        groupEventsToday.compactMap { EventTime(start: $0.time, dur: $0.endDate.timeIntervalSince($0.startDate), color: $0.color) }
                    }()
                    groupEventTimes +=  {
                        personalEventsToday.compactMap { EventTime(start: $0.time, dur: $0.endDate.timeIntervalSince($0.startDate), color: $0.color) }
                    }()
                    let personalEventTimes: [EventTime] = {
                        savedEventsToday.compactMap { EventTime(start: $0.startDate.timeIntervalSince1970, dur: $0.endDate.timeIntervalSince($0.startDate), color: $0.color) }
                    }()
                    let sortedTimes = groupEventTimes + personalEventTimes.sorted {
                        if $0.start == $1.start { return $0.dur > $1.dur }
                        return $0.start < $1.start
                    }
                    let firstTime = sortedTimes.first?.start
                    let lastTime = sortedTimes.map { $0.start + $0.dur }.max()
                    return (sortedTimes, (lastTime ?? 86400.0)-(firstTime ?? 0), (firstTime ?? 0), ((lastTime ?? 86400.0)))
                }()
                capsWidth = {
                    if hasGroupEvents {
                        return 0.6
                    } else {
                        return 0.65
                    }
                }()
            }
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newSize in
                cellSize = newSize
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(calendar.component(.day, from: date))")
    }
    // Floating action button, pinned to the bottom of the screen so it stays
    // reachable while the calendar page is scrolled.
    private var createEventButton: some View {
        Button {
            activeSheet = .create
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .padding(5)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .tint(.accent)
        .padding(.horizontal, 32)
        .buttonBorderShape(.circle)
    }
}

struct EventTime: Identifiable, Hashable {
    var id = UUID()
    let start: Double
    let dur: Double
    let color: Color = Color.black.opacity(0.25)
}
