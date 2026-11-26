import SwiftUI

/// How a newly created personal event should be repeated.
enum EventRepeatMode: String, CaseIterable, Identifiable {
    case never = "Never"
    case weekly = "Weekly"
    case custom = "Custom Dates"

    var id: Self { self }
}

/// Creates one or more events on the personal ("My Calendar") screen, with
/// support for repeating weekly or on hand-picked dates.
struct CreatePersonalEventView: View {
    @Environment(\.dismiss) private var dismiss

    // rip Colors() struct
    @Binding var events: [GroupEvents]

    /// Called with the events that were just created so they can be persisted.
    var onSave: (([GroupEvents]) -> Void)? = nil

    @State private var eventName = ""
    @State private var eventDesc = ""
    @State private var eventLocation = ""
    @State private var startDate: Date
    @State private var endDate: Date

    /// Local-only colour for every event created by this form.
    @AppStorage(PersonalEventColors.storageKey) private var colorsJSON: String = PersonalEventColors.emptyJSON
    @State private var chosenColor: PersonalEventOutlineColor = .automatic

    @State private var repeatMode: EventRepeatMode = .never
    @State private var repeatUntil: Date
    @State private var customRepeatDates: Set<Date> = []
    @State private var isShowingRepeatDates = false

    private let calendar: Calendar = {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }()

    init(
        events: Binding<[GroupEvents]>,
        initialDate: Date = Date(),
        onSave: (([GroupEvents]) -> Void)? = nil
    ) {
        _events = events
        self.onSave = onSave

        // Default to a 9–10am slot on the chosen day so the time pickers start
        // somewhere sensible instead of at midnight.
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: initialDate)
        let start = calendar.date(byAdding: .hour, value: 9, to: day) ?? initialDate

        _startDate = State(initialValue: start)
        _endDate = State(initialValue: start.addingTimeInterval(60 * 60))

        // Repeating weekly defaults to four occurrences, a common starting point.
        _repeatUntil = State(
            initialValue: calendar.date(byAdding: .weekOfYear, value: 4, to: start)
                ?? start
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Details") {
                    TextField("Name", text: $eventName)
                    TextField("Description", text: $eventDesc, axis: .vertical)
                    TextField("Location (optional)", text: $eventLocation)
                }

                Section("Date and Time") {
                    DatePicker(
                        "Starts",
                        selection: $startDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    DatePicker(
                        "Ends",
                        selection: $endDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section("Repeat") {
                    Picker("Repeat", selection: $repeatMode) {
                        ForEach(EventRepeatMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }

                    switch repeatMode {
                    case .never:
                        EmptyView()
                    case .weekly:
                        DatePicker(
                            "Repeat Until",
                            selection: $repeatUntil,
                            in: calendar.startOfDay(for: startDate)...,
                            displayedComponents: .date
                        )
                        Text(occurrenceSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    case .custom:
                        Button {
                            isShowingRepeatDates = true
                        } label: {
                            HStack {
                                Text("Choose Dates")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(customDatesSummary)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(occurrenceSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Color") {
                    EventColorPicker(selection: $chosenColor)
                }
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: startDate) { oldStart, newStart in
                // Keep the event at least an hour long when the start moves
                // past the current end.
                if endDate <= newStart {
                    endDate = newStart.addingTimeInterval(60 * 60)
                }

                // A weekly repeat can't end before it starts.
                if repeatMode == .weekly,
                    repeatUntil < calendar.startOfDay(for: newStart)
                {
                    repeatUntil =
                        calendar.date(
                            byAdding: .weekOfYear,
                            value: 4,
                            to: newStart
                        ) ?? newStart
                }

                // In a custom series the event's own day is always included, so
                // move that selection along when the start date changes.
                if repeatMode == .custom {
                    customRepeatDates.remove(calendar.startOfDay(for: oldStart))
                    customRepeatDates.insert(calendar.startOfDay(for: newStart))
                }
            }
            .onChange(of: repeatMode) { _, newMode in
                // Preselect the event's own day when switching into custom mode.
                if newMode == .custom {
                    customRepeatDates.insert(
                        calendar.startOfDay(for: startDate)
                    )
                } else if newMode == .weekly,
                    repeatUntil < calendar.startOfDay(for: startDate)
                {
                    repeatUntil =
                        calendar.date(
                            byAdding: .weekOfYear,
                            value: 4,
                            to: startDate
                        ) ?? startDate
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", systemImage: "checkmark") {
                        addEvents()
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.accent)
                    .disabled(!canSave)
                }
            }
            .sheet(isPresented: $isShowingRepeatDates) {
                RepeatDatePickerView(
                    requiredDate: calendar.startOfDay(for: startDate),
                    initialMonth: startDate,
                    selectedDates: $customRepeatDates
                )
            }
        }
    }

    private var storedColors: Binding<[String: String]> {
        PersonalEventColors.binding($colorsJSON)
    }

    private var canSave: Bool {
        !eventName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && endDate > startDate
            && !occurrenceDates.isEmpty
    }

    /// The start time of every event that will be created, including the
    /// original start date and any repeat occurrences.
    private var occurrenceDates: [Date] {
        switch repeatMode {
        case .never:
            return [startDate]
        case .weekly:
            return weeklyOccurrences()
        case .custom:
            return customOccurrences()
        }
    }

    private var occurrenceSummary: String {
        let count = occurrenceDates.count
        let noun = count == 1 ? "event" : "events"

        switch repeatMode {
        case .never:
            return "Single event"
        case .weekly:
            let weekday = startDate.formatted(.dateTime.weekday(.wide))
            let until = repeatUntil.formatted(
                date: .abbreviated,
                time: .omitted
            )
            return "Every \(weekday) until \(until) — \(count) \(noun)"
        case .custom:
            return "\(count) \(noun) on the selected dates"
        }
    }

    private var customDatesSummary: String {
        customRepeatDates.isEmpty
            ? "None"
            : "\(customRepeatDates.count) selected"
    }

    /// The same weekday as the event start, repeated every week through the
    /// chosen "Repeat Until" day (inclusive).
    private func weeklyOccurrences() -> [Date] {
        let lastDay = calendar.startOfDay(for: max(repeatUntil, startDate))
        var occurrences: [Date] = []
        var current = startDate

        // Cap the series so an accidental far-off end date can't create
        // thousands of events. Two years of weekly repeats is plenty.
        while calendar.startOfDay(for: current) <= lastDay,
            occurrences.count < 104
        {
            occurrences.append(current)
            guard
                let next = calendar.date(
                    byAdding: .weekOfYear,
                    value: 1,
                    to: current
                )
            else {
                break
            }
            current = next
        }

        return occurrences
    }

    /// One event on every date picked in the custom calendar, always
    /// including the event's own start date.
    private func customOccurrences() -> [Date] {
        let time = calendar.dateComponents([.hour, .minute], from: startDate)
        var days = customRepeatDates.map { calendar.startOfDay(for: $0) }
        days.append(calendar.startOfDay(for: startDate))

        return Array(Set(days)).sorted().compactMap { day in
            calendar.date(
                bySettingHour: time.hour ?? 9,
                minute: time.minute ?? 0,
                second: 0,
                of: day
            )
        }
    }

    private func addEvents() {
        let name = eventName.trimmingCharacters(in: .whitespacesAndNewlines)
        let desc = eventDesc.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = eventLocation.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        // Every occurrence keeps the same duration as the original event.
        let duration = endDate.timeIntervalSince(startDate)

        let created = occurrenceDates.map { occurrenceStart in
            GroupEvents(
                name: name,
                desc: desc,
                location: location,
                time: occurrenceStart.timeIntervalSince1970,
                endTime: occurrenceStart.addingTimeInterval(duration)
                    .timeIntervalSince1970
            )
        }

        // Colour every occurrence the same way, locally on this device.
        var stored = storedColors.wrappedValue
        for event in created {
            PersonalEventColors.setChoice(
                chosenColor,
                in: &stored,
                for: PersonalEventColorKey.personal(event.id)
            )
        }
        storedColors.wrappedValue = stored

        events.append(contentsOf: created)

        // Persist what was created. The store's snapshot listener will refresh
        // the list once Firestore confirms the writes.
        onSave?(created)

        dismiss()
    }
}

#Preview {
    CreatePersonalEventView(
        events: .constant([])
    )
}

/// A month calendar used to pick several separate days for a repeating event.
struct RepeatDatePickerView: View {
    @Environment(\.dismiss) private var dismiss

    // rip Colors() struct

    /// The event's own start date. It is always part of the series and can't
    /// be deselected.
    let requiredDate: Date

    @Binding var selectedDates: Set<Date>

    private let calendar: Calendar = {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }()

    @State private var displayedMonth: Date
    @State private var draftDates: Set<Date>

    init(
        requiredDate: Date,
        initialMonth: Date,
        selectedDates: Binding<Set<Date>>
    ) {
        self.requiredDate = requiredDate
        _selectedDates = selectedDates
        _displayedMonth = State(initialValue: initialMonth)
        _draftDates = State(initialValue: selectedDates.wrappedValue)
    }

    private var weekdays: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        return Array(symbols[1...6] + [symbols[0]])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    monthHeader
                    weekdayHeader
                    monthGrid
                    selectionFooter
                }
                .padding()
            }
            .navigationTitle("Repeat Dates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        selectedDates = draftDates
                        dismiss()
                    }
//                    .tint(.red)
                    .disabled(draftDates.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var monthHeader: some View {
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
//        .tint(.primary)
        .padding(.horizontal)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 2) {
            ForEach(weekdays.indices, id: \.self) { index in
                Text(weekdays[index])
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.gray)
            }
        }
    }

    private var monthGrid: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 2),
                count: 7
            ),
            spacing: 6
        ) {
            ForEach(generateMonthGrid(), id: \.self) { date in
                dayCell(for: date)
            }
        }
    }

    private var selectionFooter: some View {
        HStack {
            Text(
                "\(draftDates.count) \(draftDates.count == 1 ? "date" : "dates") selected"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            Spacer()

            Button("Clear") {
                // The event's own start date always stays selected.
                draftDates = [requiredDate]
            }
            .font(.footnote)
//            .tint(.red)
        }
        .padding(.horizontal)
    }

    private func dayCell(for date: Date) -> some View {
        let day = calendar.startOfDay(for: date)
        let isSelected = draftDates.contains(day)
        let isRequired = calendar.isDate(day, inSameDayAs: requiredDate)
        let isCurrentMonth = calendar.isDate(
            date,
            equalTo: displayedMonth,
            toGranularity: .month
        )

        return Button {
            // The start date is locked because the event happens on it.
            guard !isRequired else { return }

            if isSelected {
                draftDates.remove(day)
            } else {
                draftDates.insert(day)
            }
        } label: {
            Text("\(calendar.component(.day, from: date))")
                .font(.subheadline)
                .frame(width: 36, height: 36)
                .foregroundStyle(
                    isSelected
                        ? Color.white
                        : (isCurrentMonth ? Color.primary : Color.secondary)
                )
                .background(
                    Circle()
                        .fill(isSelected ? .green.adjusted(saturation: 0.75, brightness: -0.25) : Color.clear)
                )
                .overlay {
                    if calendar.isDateInToday(date) && !isSelected {
                        Circle()
                            .strokeBorder(Color.secondary, lineWidth: 1)
                    }
                }
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(date: .long, time: .omitted))
        .accessibilityAddTraits(
            isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits()
        )
    }

    private func changeMonth(by value: Int) {
        displayedMonth =
            calendar.date(byAdding: .month, value: value, to: displayedMonth)
            ?? displayedMonth
    }

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
}
