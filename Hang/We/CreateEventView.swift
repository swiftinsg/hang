import SwiftUI

struct CreateEventView: View {
    @Environment(\.dismiss) private var dismiss

    var colors = Colors()
    @Binding var tg: TestGroup

    @State private var eventName = ""
    @State private var eventDesc = ""
    @State private var eventLocation = ""
    @State private var startDate: Date
    @State private var endDate: Date

    init(tg: Binding<TestGroup>, initialDate: Date = Date()) {
        _tg = tg

        // Default to a 9–10am slot on the chosen day so the time pickers start
        // somewhere sensible instead of at midnight.
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: initialDate)
        let start = calendar.date(byAdding: .hour, value: 9, to: day) ?? initialDate

        _startDate = State(initialValue: start)
        _endDate = State(initialValue: start.addingTimeInterval(60 * 60))
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
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: startDate) { _, newStart in
                // Keep the event at least an hour long when the start moves
                // past the current end.
                if endDate <= newStart {
                    endDate = newStart.addingTimeInterval(60 * 60)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let event = GroupEvents(
                            name: eventName.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ),
                            desc: eventDesc.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ),
                            location: eventLocation.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ),
                            time: startDate.timeIntervalSince1970,
                            endTime: endDate.timeIntervalSince1970
                        )
                        tg.events.append(event)
                        GroupStore.shared.addEvent(event, to: tg)
                        dismiss()
                    }
//                    .tint(.red)
                    .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        !eventName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && endDate > startDate
    }
}

#Preview {
    CreateEventView(
        tg: .constant(
            TestGroup(
                code: "HELLO1",
                name: "CODZEE",
                events: [
                    GroupEvents(name: "event1", time: 1_720_708_600),
                    GroupEvents(name: "event2", time: 1_790_403_500),
                ]
            )
        )
    )
}
