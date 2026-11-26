import FirebaseAuth
import SwiftUI

private enum GroupCalendarSheet: Identifiable {
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

public enum GroupTab: String, CaseIterable, Identifiable {
    case cal = "Calendar"
    case events = "Events"
    case info = "Group Info"

    public var id: Self { self }
}

struct GroupView: View {
    var sizing = Sizing()
    // rip Colors() struct
    @Binding var tg: TestGroup
    @State private var selectedGroupTab: GroupTab = .events
    @State private var availabilityStore = AvailabilityStore.shared
    @State var screenSize: CGSize = .zero
    var body: some View {
        NavigationStack {
            ZStack {
                VStack {
                    Text(tg.name)
                        .font(.largeTitle.bold())
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    Picker("Picker", selection: $selectedGroupTab) {
                        ForEach(GroupTab.allCases) { gtab in
                            Text(gtab.rawValue)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                    .pickerStyle(.segmented)

                    switch selectedGroupTab {
                    case .cal:
                        CalendarView(tg: $tg)
                    case .events:
                        EventView(tg: $tg, size: screenSize)
                    case .info:
                        MoreInfoView(tg: $tg)
                    }
                }
                //                .navigationTitle(tg.name)
            }
            .onAppear {
                // Keep this group's shared hangouts live so new ones appear
                // for every member without reopening the app.
                GroupStore.shared.startListeningToEvents(for: tg)

                // Opening a group is also the most reliable time to sync
                // availability: make sure we are listening for other members
                // and publish this member's busy times even if the app-wide
                // group-ID change handler hasn't fired yet.
                let groupID = tg.documentID
                guard !groupID.isEmpty else { return }
                availabilityStore.listen(groupID: groupID)
                if let uid = Auth.auth().currentUser?.uid {
                    Task {
                        await AvailabilityPublisher.shared.refresh(
                            groups: [groupID],
                            uid: uid,
                            force: true
                        )
                    }
                }
            }
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            screenSize = newSize
        }
    }
}

#Preview {
    GroupView(
        tg: .constant(
            TestGroup(
                code: "HELLO1",
                name: "CODZEE",
                members: [
                    Person(name: "seren", status: "i am skibidi")
                ],
                events: [
                    //                    GroupEvents(name: "event1", time: 1_720_708_600),
                    //                    GroupEvents(name: "event2", time: 1_790_403_500),
                ]

            )
        )
    )
}

struct CalendarView: View {
    var sizing = Sizing()
    // rip Colors() struct
    @Binding var tg: TestGroup

    private let calendar: Calendar = {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }()
    @State private var cellSize: CGSize = .zero
    @State private var displayedMonth: Date = Date()
    @State private var selectedDate: Date? = Date()
    @State private var activeSheet: GroupCalendarSheet?
    @State private var calendarStore = PersonalCalendarStore.shared
    @State private var personalStore = PersonalEventsStore.shared
    @State private var availabilityStore = AvailabilityStore.shared
    @State private var availabilityPublisher = AvailabilityPublisher.shared
    /// Personal event colours stay on this device, including in the shared
    /// calendar's "You" column.
    @AppStorage(PersonalEventColors.storageKey) private var colorsJSON: String = PersonalEventColors.emptyJSON

    private var members: [Person] { tg.members }

    private var storedColors: Binding<[String: String]> {
        PersonalEventColors.binding($colorsJSON)
    }

    private var availability: AvailabilityCalculator {
        AvailabilityCalculator(
            calendar: calendar,
            personalEvents: personalStore.events,
            importedEvents: calendarStore.events,
            groupEvents: tg.events,
            sharedBusy: availabilityStore.busyIntervals(
                inGroup: tg.documentID
            ),
            sharedUpdatedAt: availabilityStore.updatedAt(
                inGroup: tg.documentID
            )
        )
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
        return Text(weekdays[index])
            .font(.subheadline)
            .bold()
            .frame(maxWidth: .infinity)
            .foregroundStyle(.gray)
            .padding(.vertical, 3)
    }

    var body: some View {
        // The whole calendar scrolls as one page, so the availability timeline
        // below the month grid stays fully visible without its own scroller.
        ScrollView {
            VStack(spacing: 2) {
                monthHeader
                monthGrid

                if let message = availabilityStore.errorMessage
                    ?? availabilityPublisher.errorMessage
                {
                    Text("Availability sync: \(message)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }

                Divider()
                    .padding(.vertical, 8)

                DayAvailabilityView(
                    date: effectiveSelectedDate,
                    groupID: tg.documentID,
                    members: members,
                    calendar: calendar,
                    groupEvents: tg.events,
                    personalEvents: personalStore.events,
                    importedEvents: calendarStore.events,
                    storedColors: storedColors,
                    groupColor: tg.eventColor.color ?? .blue,
                    onEditGroupEvent: { event in
                        activeSheet = .edit(event)
                    }
                )
            }
            .padding(15)
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
                CreateEventView(
                    tg: $tg,
                    initialDate: effectiveSelectedDate
                )
                .presentationDetents([.medium, .large])
            case .edit(let event):
                EditEventView(
                    events: $tg.events,
                    eventID: event.id,
                    onSave: { updatedEvent in
                        GroupStore.shared.updateEvent(updatedEvent, to: tg)
                    },
                    onDelete: { eventID in
                        GroupStore.shared.deleteEvent(eventID, from: tg)
                    }
                )
                .presentationDetents([.medium, .large])
            }
        }
        .task {
            calendarStore.loadEventsIfAuthorized()
        }
    }

    private var monthHeader: some View {
        VStack(spacing: 24) {
            HStack {
                Button {
                    changeMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(.accent)
                }

                Spacer()
                Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                Spacer()
                Button {
                    changeMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.accent)
                }
            }
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
        // Past days are never scored or eligible for the best-days outline.
        let upcomingDays = days.filter { !isPastDate($0) }
        let fractions = availability.dailyFractions(
            for: upcomingDays,
            members: members
        )
        let topDays = topAvailableDays(
            among: upcomingDays,
            fractions: fractions
        )

        return LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 2),
                count: 7
            ),
            spacing: 2
        ) {
            ForEach(days, id: \.self) { date in
                dayCell(
                    for: date,
                    topAvailableDays: topDays,
                    fractions: fractions
                )
            }
        }
    }

    // A single day in the month grid, including its availability shading,
    // outlines, and event marker. Days before today are disabled and shown as
    // plain gray cells with no shading, markers, or outlines.
    private func dayCell(
        for date: Date,
        topAvailableDays: Set<Date>,
        fractions: [Date: Double]
    ) -> some View {
        let isCurrentMonth = calendar.isDate(
            date,
            equalTo: displayedMonth,
            toGranularity: .month
        )
        let isPastDate = isPastDate(date)

        let isSelected =
            !isPastDate
            && (selectedDate.map { calendar.isDate($0, inSameDayAs: date) }
                ?? false)

        let dayStart = calendar.startOfDay(for: date)
        let dayEnd =
            calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        let hasGroupEvents =
            !isPastDate
            && tg.events.contains { event in
                event.startDate < dayEnd && event.endDate > dayStart
            }

        let isTopAvailable =
            !isPastDate
            && topAvailableDays.contains(calendar.startOfDay(for: date))

        let freeFraction =
            fractions[calendar.startOfDay(for: date)] ?? 0

        // Darker green means more of the group is free that day.
        let shading = 0.05 + 0.5 * freeFraction

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
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                .green.adjusted(
                                    saturation: 0.5,
                                    brightness: -0.07
                                ).opacity(
                                    isCurrentMonth ? shading : shading * 0.4
                                )
                            )
                    }
                }
                .overlay(alignment: .bottom) {
                    HStack(spacing: 2) {
                        if hasGroupEvents {
                            Image("flatTripleHang")
                                .resizable()
                                .scaledToFit()
                                .scaleEffect(0.9)
                                .offset(y: cellSize.height * 0.18)
                        }
                    }
                }
                .overlay {
                    // Most available days of the month.
                    if isTopAvailable {
                        Image("topAvailableHang")
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(0.5)
                            .offset(y: cellSize.height * 0.3)
                            .offset(x: cellSize.height * 4)

                    }
                }
                .overlay {
                    if isTopAvailable {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                Color.blue,
                                style: StrokeStyle(
                                    lineWidth: 1.5,
                                    dash: [3, 2]
                                )
                            )
                    }
                }

                .overlay {
                    // Days that already have an event.
                    if hasGroupEvents {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.blue, lineWidth: 2)
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
        .disabled(isPastDate)
        .accessibilityLabel(
            isPastDate
                ? "\(calendar.component(.day, from: date)), unavailable past date"
                : "\(calendar.component(.day, from: date))"
        )
    }

    // The three upcoming days of the displayed month where the group is most
    // free. Past days are never eligible.
    private func topAvailableDays(
        among days: [Date],
        fractions: [Date: Double]
    ) -> Set<Date> {
        let monthDays = days.filter {
            !isPastDate($0)
                && calendar.isDate(
                    $0,
                    equalTo: displayedMonth,
                    toGranularity: .month
                )
        }

        let best =
            monthDays
            .map { ($0, fractions[calendar.startOfDay(for: $0)] ?? 0) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(3)

        return Set(best.map { calendar.startOfDay(for: $0.0) })
    }

    // Floating action button, pinned to the bottom of the screen so it stays
    // reachable while the calendar page is scrolled.
    private var createEventButton: some View {
        NewGroupEventButton {
            activeSheet = .create
        }
    }
}

// Shared floating "New event" button used by both the Calendar and Events tabs.
struct NewGroupEventButton: View {
    // rip Colors() struct
    var action: () -> Void

    var body: some View {
        Button("", systemImage: "plus", action: action)
            .font(.title2.weight(.semibold))
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(Color.accentColor)
            .padding(.horizontal, 32)
            .buttonBorderShape(.circle)
    }
}

struct EventView: View {
    @Binding var tg: TestGroup
    var size: CGSize
    var sizing = Sizing()
    // rip Colors() struct
    @State private var showAddView = false
    @State private var activeSheet: GroupCalendarSheet?

    var body: some View {
        Group {
            if $tg.events.isEmpty {
                ContentUnavailableView("No Events", systemImage: "tray", description: Text("Go arrange a hangout with your friends!"))
            } else {
                List {
                    ForEach($tg.events) { $event in
                        Button {
                            activeSheet = .edit(event)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(event.name)
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .lineLimit(1)

                                HStack {
                                    Text(
                                        Date(timeIntervalSince1970: event.time)
                                            .formatted(
                                                date: .abbreviated,
                                                time: .omitted
                                            )
                                    )
                                    Divider()
                                    Text(
                                        event.endTime == nil
                                            ? Date(
                                                timeIntervalSince1970: event
                                                    .time
                                            )
                                            .formatted(
                                                date: .omitted,
                                                time: .shortened
                                            )
                                            : Date(
                                                timeIntervalSince1970: event
                                                    .time
                                            )
                                            .formatted(
                                                date: .omitted,
                                                time: .shortened
                                            ) + "-"
                                                + Date(
                                                    timeIntervalSince1970: event
                                                        .endTime
                                                        ?? 0
                                                )
                                                .formatted(
                                                    date: .omitted,
                                                    time: .shortened
                                                )
                                    )
                                }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                                Text(
                                    event.location.isEmpty
                                        ? "No location" : event.location
                                )
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                                Text(event.desc)
                                    .lineLimit(5)
                                    .padding(.top, 4)
                            }
                            .foregroundStyle(Color.primary)
                        }
                        .listRowBackground(Color(.secondarySystemBackground))
                    }
                }
                .padding(.top, -sizing.x4)
                .scrollContentBackground(.hidden)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            NewGroupEventButton {
                activeSheet = .create
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .create:
                CreateEventView(
                    tg: $tg,
                    initialDate: Date()
                )
                .presentationDetents([.medium, .large])
            case .edit(let event):
                EditEventView(
                    events: $tg.events,
                    eventID: event.id,
                    onSave: { updatedEvent in
                        GroupStore.shared.updateEvent(updatedEvent, to: tg)
                    },
                    onDelete: { eventID in
                        GroupStore.shared.deleteEvent(eventID, from: tg)
                    }
                )
                .presentationDetents([.medium, .large])
            }
        }
    }
}

struct MoreInfoView: View {
    var sizing = Sizing()
    // rip Colors() struct
    @Binding var tg: TestGroup
    @Environment(\.dismiss) private var dismiss

    @State private var isConfirmingLeave = false
    @State private var isFilled = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        List {
            Section("Invite code") {
                HStack(spacing: 4) {
                    ForEach(0..<6, id: \.self) { index in
                        otpDigitBox(at: index)
                    }
                    Button {
                        resetTask?.cancel()

                        isFilled = true

                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                        
                        resetTask = Task {
                            try? await Task.sleep(for: .seconds(2))
                            guard !Task.isCancelled else { return }
                            isFilled = false
                        }

                        UIPasteboard.general.string = tg.code
                    } label: {
                        Image(systemName: isFilled ? "checkmark" : "doc.on.doc")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .padding(.leading, 8)
                }
            }
            .listRowBackground(Color(.secondarySystemBackground))

            Section("Event Color") {
                EventColorPicker(
                    selection: Binding(
                        get: { tg.eventColor },
                        set: { newColor in
                            tg.eventColor = newColor
                            Task {
                                await GroupStore.shared.setEventColor(
                                    newColor,
                                    for: tg
                                )
                            }
                        }
                    ),
                    includeAutomatic: false
                )
                Text("All events from this group use this color.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color(.secondarySystemBackground))

            //            Section("Description") {
            //                Text(tg.desc)
            //                Button("Edit description", systemImage: "pencil") {}
            //                    .foregroundStyle(Color(.accent))
            //            }
            //            .listRowBackground(Color(.secondarySystemBackground))

            Section("Members (\(tg.members.count))") {
                ForEach(tg.members) { member in
                    HStack(spacing: 16) {
                        ProfileAvatarView(person: member, size: 40)
                        VStack(alignment: .leading) {
                            Text(member.name)
                                .lineLimit(1)
                                .bold()
                            Text(member.status)
                                .lineLimit(1)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listRowBackground(Color(.secondarySystemBackground))

            Section("Actions") {
                Button(role: .destructive) {
                    isConfirmingLeave = true
                } label: {
                    Text("Leave Group")
                }
                .buttonStyle(.glass)
                .tint(.red)
            }
            .listRowBackground(Color(.secondarySystemBackground))
        }
        .scrollContentBackground(.hidden)
        .alert(
            "Leave this group?",
            isPresented: $isConfirmingLeave,
        ) {
            Button("Leave Group", role: .destructive) {
                leaveGroup()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "You'll be removed from the member list and stop seeing this group's events."
            )
        }
    }

    @ViewBuilder
    private func otpDigitBox(at index: Int) -> some View {
        //        guard index < tg.code.count else { return "" }
        let stringIndex = tg.code.index(tg.code.startIndex, offsetBy: index)
        let character = String(tg.code[stringIndex])

        Text(character)
            .font(.title2.bold())
            .frame(width: 30, height: 40)
            .background(Color(.secondarySystemFill))
            .cornerRadius(8)
    }

    private func leaveGroup() {
        // Capture the group's value up front and dismiss before the async
        // write. The Firestore listener removes the group from the store once
        // the write lands, so popping this view first avoids dangling an
        // index-based binding while the store updates.
        let group = tg
        dismiss()
        Task {
            await GroupStore.shared.leaveGroup(group)
        }
    }
}
