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
    /// Present only for personal events. Group events use the group's colour.
    let colorKey: String?

    /// Called after an edit is saved so the change can be persisted.
    var onSave: ((GroupEvents) async throws -> Void)? = nil
    /// Called when the event is deleted so it can be removed from storage.
    var onDelete: ((UUID) async throws -> Void)? = nil

    @State private var eventName: String
    @State private var eventDesc: String
    @State private var eventLocation: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var isConfirmingDelete = false
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    /// Local-only colour choice, stored in AppStorage on this device.
    @AppStorage(PersonalEventColors.storageKey) private var colorsJSON: String = PersonalEventColors.emptyJSON
    @State private var chosenColor: PersonalEventOutlineColor = .automatic

    init(
        events: Binding<[GroupEvents]>,
        eventID: UUID,
        colorKey: String? = nil,
        onSave: ((GroupEvents) async throws -> Void)? = nil,
        onDelete: ((UUID) async throws -> Void)? = nil
    ) {
        _events = events
        self.eventID = eventID
        self.colorKey = colorKey
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
        _chosenColor = State(
            initialValue: colorKey.map {
                PersonalEventColors.storedChoice(forKey: $0)
            } ?? .automatic
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

                if colorKey != nil {
                    Section("Color") {
                        EventColorPicker(selection: $chosenColor)
                    }
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
                        Task { await saveEvent() }
                    }
                    .disabled(!canSave)
                }
            }
            .confirmationDialog(
                "Delete this event?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Event", role: .destructive) {
                    Task { await deleteEvent() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
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

    private var storedColors: Binding<[String: String]> {
        PersonalEventColors.binding($colorsJSON)
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

    private func saveEvent() async {
        guard !isSaving else { return }
        guard
            let index = events.firstIndex(where: { $0.id == eventID })
        else {
            dismiss()
            return
        }
        isSaving = true

        let previous = events[index]
        var updated = previous
        updated.name = eventName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        updated.desc = eventDesc.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        updated.location = eventLocation.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        updated.time = startDate.timeIntervalSince1970
        updated.endTime = endDate.timeIntervalSince1970

        do {
            try await onSave?(updated)
            // The live listener may have re-sorted the array while awaiting.
            if let currentIndex = events.firstIndex(where: { $0.id == eventID }) {
                events[currentIndex] = updated
            }
            if let colorKey {
                var stored = storedColors.wrappedValue
                PersonalEventColors.setChoice(
                    chosenColor,
                    in: &stored,
                    for: colorKey
                )
                storedColors.wrappedValue = stored
            }
            dismiss()
        } catch {
            // Leave the sheet and the original event untouched on failure.
            saveErrorMessage = error.localizedDescription
            isSaving = false
        }
    }

    private func deleteEvent() async {
        guard !isSaving else { return }
        isSaving = true
        do {
            try await onDelete?(eventID)
            events.removeAll { $0.id == eventID }
            if let colorKey {
                var stored = storedColors.wrappedValue
                PersonalEventColors.setChoice(
                    .automatic,
                    in: &stored,
                    for: colorKey
                )
                storedColors.wrappedValue = stored
            }
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            isSaving = false
        }
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
