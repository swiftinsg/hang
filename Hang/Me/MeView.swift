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
                    calendar: calendar,
                    storedColors: storedColors,
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
                    colorKey: PersonalEventColorKey.personal(event.id),
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
    
    /// One event's visible portion of a day, measured in seconds from midnight.
    /// Clipping to the day is what keeps multi-day events from stretching the
    /// mini bar beyond the cell.
    private struct DayEventSlice: Identifiable {
        let id: String
        let color: Color
        let start: Double
        let duration: Double
    }

    /// A capsule's final gap and width after the whole bar has been fitted to
    /// the cell. Keeping these together means overlapping events stay in time
    /// order while every one of them is still drawn.
    private struct LaidOutSlice: Identifiable {
        let id: String
        let color: Color
        let gap: CGFloat
        let width: CGFloat
    }

    /// Every event covering this day, reduced to a coloured time slice. Group
    /// events use their group's Firestore colour; personal and imported events
    /// use the device-local choice, defaulting to gray.
    private func eventSlices(for date: Date) -> [DayEventSlice] {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let stored = storedColors.wrappedValue

        var slices: [DayEventSlice] = []

        func add(id: String, color: Color, start: Date, end: Date) {
            let visibleStart = max(start, dayStart)
            let visibleEnd = min(end, dayEnd)
            guard visibleEnd > visibleStart else { return }
            slices.append(
                DayEventSlice(
                    id: id,
                    color: color,
                    start: visibleStart.timeIntervalSince(dayStart),
                    duration: visibleEnd.timeIntervalSince(visibleStart)
                )
            )
        }

        for event in calendarStore.events(on: date, calendar: calendar) {
            let key = PersonalEventColorKey.imported(event.id)
            add(
                id: key,
                color: PersonalEventColors.color(
                    in: stored, for: key, default: .gray
                ),
                start: event.startDate,
                end: event.endDate
            )
        }

        for event in personalEvents
        where event.startDate < dayEnd && event.endDate > dayStart {
            let key = PersonalEventColorKey.personal(event.id)
            add(
                id: key,
                color: PersonalEventColors.color(
                    in: stored, for: key, default: .gray
                ),
                start: event.startDate,
                end: event.endDate
            )
        }

        for event in groupEvents
        where event.startDate < dayEnd && event.endDate > dayStart {
            add(
                id: PersonalEventColorKey.group(event.id),
                color: event.groupColor ?? .blue,
                start: event.startDate,
                end: event.endDate
            )
        }

        return slices.sorted { $0.start < $1.start }
    }

    /// The time-positioned capsules are laid out in an HStack, not stacked on
    /// top of each other, so overlapping events no longer hide one another.
    /// The whole line is scaled to the available width, then padded on all
    /// sides so it never touches the cell's edges.
    private func miniBar(for slices: [DayEventSlice]) -> some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let windowStart = slices.map(\.start).min() ?? 0
            let windowEnd = slices.map { $0.start + $0.duration }.max() ?? 86_400
            let span = max(windowEnd - windowStart, 1)

            let laidOut = slices.map { slice -> LaidOutSlice in
                LaidOutSlice(
                    id: slice.id,
                    color: slice.color,
                    gap: max(CGFloat((slice.start - windowStart) / span) * width, 0),
                    width: max(CGFloat(slice.duration / span) * width, 2)
                )
            }
            let total = laidOut.reduce(0) { $0 + $1.gap + $1.width }
            let scale = total > width ? width / total : 1

            HStack(spacing: 0) {
                ForEach(laidOut) { item in
                    if item.gap * scale > 0 {
                        Color.clear.frame(width: item.gap * scale)
                    }
                    Capsule()
                        .fill(item.color)
                        .frame(width: item.width * scale, height: 4)
                }
            }
        }
        .frame(height: 4)
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
    }

    private func dayCell(for date: Date) -> some View {
        let isCurrentMonth = calendar.isDate(
            date,
            equalTo: displayedMonth,
            toGranularity: .month
        )
        let isSelected = selectedDate.map {
            calendar.isDate($0, inSameDayAs: date)
        } ?? false
        let slices = eventSlices(for: date)
        // The longest event owns the outline, so the ring matches the bar.
        let outlineColor = slices.max { $0.duration < $1.duration }?.color

        return Button {
            selectedDate = date
        } label: {
            VStack(spacing: 0) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.subheadline)
                    .foregroundStyle(
                        isCurrentMonth ? Color.primary : Color.secondary
                    )
                    .padding(.top, slices.isEmpty ? 0 : 4)

                if !slices.isEmpty {
                    Spacer(minLength: 0)
                    miniBar(for: slices)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 45)
            .overlay {
                if let outlineColor {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(outlineColor, lineWidth: 2)
                        .padding(2)
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: 2.5)
                }
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

