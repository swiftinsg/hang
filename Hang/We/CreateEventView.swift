import SwiftUI

struct CreateEventView: View {
    let groupID: String

    @Environment(\.dismiss) private var dismiss
    @Environment(GroupStore.self) private var groupStore
    @State private var calendarStore = PersonalCalendarStore.shared

    @State private var eventName = ""
    @State private var eventDesc = ""
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var alert: EventAlert?
    @State private var isSaving = false

    private enum EventAlert {
        case error(String)
        case savedToGroup(String)

        var title: String {
            switch self {
            case .error:
                return "Couldn't add event"
            case .savedToGroup:
                return "Added to group calendar"
            }
        }

        var message: String {
            switch self {
            case .error(let message), .savedToGroup(let message):
                return message
            }
        }

        var closesSheet: Bool {
            if case .savedToGroup = self { return true }
            return false
        }
    }

    init(groupID: String, initialDate: Date = Date()) {
        self.groupID = groupID
        _startDate = State(initialValue: initialDate)
        _endDate = State(initialValue: initialDate.addingTimeInterval(3600))
    }

    private var trimmedName: String {
        eventName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        !trimmedName.isEmpty && endDate > startDate
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $eventName)
                    TextField("Description", text: $eventDesc, axis: .vertical)
                        .lineLimit(2...5)
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

                    if endDate <= startDate {
                        Text("End time must be after the start time.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .tint(.red)
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task { await save() }
                    }
                    .tint(.green)
                    .disabled(!isValid || isSaving)
                }
            }
            .alert(
                alert?.title ?? "",
                isPresented: Binding(
                    get: { alert != nil },
                    set: { if !$0 { alert = nil } }
                )
            ) {
                if alert?.closesSheet == true {
                    Button("Done") {
                        alert = nil
                        dismiss()
                    }
                } else {
                    Button("OK", role: .cancel) {
                        alert = nil
                    }
                }
            } message: {
                Text(alert?.message ?? "")
            }
        }
    }

    /// Adds the event to the group and, when access allows, to the person's own
    /// calendar so it shows up in the Calendar app too.
    ///
    /// The group write happens first. If the Calendar write then fails, the
    /// event is *not* lost: the alert says so and closes the sheet without
    /// inviting a second Add tap that would create a duplicate.
    private func save() async {
        guard !isSaving, isValid else { return }

        let name = trimmedName
        let desc = eventDesc.trimmingCharacters(in: .whitespacesAndNewlines)

        isSaving = true
        defer { isSaving = false }

        let eventID: String
        do {
            eventID = try await groupStore.addEvent(
                to: groupID,
                name: name,
                desc: desc,
                start: startDate,
                end: endDate
            )
        } catch {
            alert = .error(error.localizedDescription)
            return
        }

        if let message = await calendarStore.saveEventToCalendar(
            title: name,
            notes: desc,
            startDate: startDate,
            endDate: endDate,
            linkedEventID: eventID
        ) {
            // Saved to the group, not to Calendar. Keep the sheet up until the
            // person acknowledges, then close it.
            alert = .savedToGroup(message)
            return
        }

        dismiss()
    }
}

#if DEBUG
#Preview {
    CreateEventView(groupID: PreviewData.groupID)
        .environment(GroupStore.preview(with: PreviewData.members))
}
#endif
