import SwiftUI

struct CreateEventView: View {
    @Environment(\.dismiss) private var dismiss

    // rip Colors() struct
    @Binding var tg: TestGroup

    @State private var eventName = ""
    @State private var eventDesc = ""
    @State private var eventLocation = ""
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

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
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", systemImage: "checkmark") {
                        Task { await addEvent() }
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.accent)
                    .disabled(!canSave)
                }
            }
            .alert(
                "Couldn't save event",
                isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { if !$0 { saveErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage ?? "Please try again.")
            }
        }
    }

    private var canSave: Bool {
        let name = eventName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty
            && name.count <= 200
            && eventDesc.count <= 2000
            && eventLocation.count <= 200
            && endDate > startDate
            && !isSaving
    }

    private func addEvent() async {
        guard !isSaving else { return }
        isSaving = true
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
            endTime: endDate.timeIntervalSince1970,
            groupColor: tg.eventColor.hangColor ?? .blue
        )

        do {
            try await GroupStore.shared.addEvent(event, to: tg)
            // The live listener may have landed before the write returned.
            if !tg.events.contains(where: { $0.id == event.id }) {
                tg.events.append(event)
            }
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            isSaving = false
        }
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
