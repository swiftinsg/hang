//
//  EditEventView.swift
//  Hang
//
//  Edits or deletes one event from a list of group events. The same screen is
//  used for personal events in Me and shared events in We.
//

import SwiftUI

struct EditEventView: View {
    @Environment(\.dismiss) private var dismiss

    // rip Colors() struct
    @Binding var events: [GroupEvents]
    let eventID: UUID

    /// Called after an edit is saved so the change can be persisted.
    var onSave: ((GroupEvents) -> Void)? = nil
    /// Called when the event is deleted so it can be removed from storage.
    var onDelete: ((UUID) -> Void)? = nil

    @State private var eventName: String
    @State private var eventDesc: String
    @State private var eventLocation: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var isConfirmingDelete = false

    init(
        events: Binding<[GroupEvents]>,
        eventID: UUID,
        onSave: ((GroupEvents) -> Void)? = nil,
        onDelete: ((UUID) -> Void)? = nil
    ) {
        _events = events
        self.eventID = eventID
        self.onSave = onSave
        self.onDelete = onDelete

        let event = events.wrappedValue.first(where: { $0.id == eventID })
        _eventName = State(initialValue: event?.name ?? "")
        _eventDesc = State(initialValue: event?.desc ?? "")
        _eventLocation = State(initialValue: event?.location ?? "")
        _startDate = State(initialValue: event?.startDate ?? Date())
        _endDate = State(
            initialValue: event?.endDate
                ?? Date().addingTimeInterval(60 * 60)
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

                Section {
                    Button("Delete Event", role: .destructive) {
                        isConfirmingDelete = true
                    }
                }
            }
            .navigationTitle("Edit Event")
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
                    Button("Save", systemImage: "checkmark") {
                        saveEvent()
                    }
//                    .tint(.red)
                    .disabled(!canSave)
                }
            }
            .confirmationDialog(
                "Delete this event?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Event", role: .destructive) {
                    deleteEvent()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
        }
    }

    private var canSave: Bool {
        !eventName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && endDate > startDate
    }

    private func saveEvent() {
        guard
            let index = events.firstIndex(where: { $0.id == eventID })
        else {
            dismiss()
            return
        }

        events[index].name = eventName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        events[index].desc = eventDesc.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        events[index].location = eventLocation.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        events[index].time = startDate.timeIntervalSince1970
        events[index].endTime = endDate.timeIntervalSince1970
        onSave?(events[index])
        dismiss()
    }

    private func deleteEvent() {
        onDelete?(eventID)
        events.removeAll { $0.id == eventID }
        dismiss()
    }
}

#Preview {
    let calendar = Calendar.current
    let start =
        calendar.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: Date()
        ) ?? Date()
    let event = GroupEvents(
        name: "Dinner",
        desc: "Group dinner",
        time: start.timeIntervalSince1970,
        endTime: start.addingTimeInterval(60 * 60)
            .timeIntervalSince1970
    )

    return EditEventView(
        events: .constant([event]),
        eventID: event.id
    )
}
