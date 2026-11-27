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
    
    // where var body is
    
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

