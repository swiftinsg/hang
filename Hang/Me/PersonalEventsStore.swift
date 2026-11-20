//
//  PersonalEventsStore.swift
//  Hang
//
//  Events created on the Me calendar. They belong to you, are shown read only
//  in the We group calendar, and are separate from the group's shared events.
//
//  They are saved in Firestore under users/<uid>/calendar/<entryID> so they
//  follow the account onto every device.
//

import FirebaseAuth
import FirebaseFirestore
import Foundation
import Observation

@Observable
final class PersonalEventsStore {
    static let shared = PersonalEventsStore()

    var events: [GroupEvents] = []
    private(set) var errorMessage: String?

    @ObservationIgnored private let db = Firestore.firestore()
    @ObservationIgnored private var listener: ListenerRegistration?
    @ObservationIgnored private var listeningUID: String?

    private init() {}

    /// users/<uid>/calendar
    private var calendarCollection: CollectionReference? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        return db.collection(Path.Firestore.Users)
            .document(uid)
            .collection(Path.Firestore.Calendar)
    }

    /// Starts listening to the signed-in user's calendar. Safe to call more
    /// than once; it only re-subscribes when the account changes.
    func startListening() {
        let uid = Auth.auth().currentUser?.uid
        guard listener == nil || listeningUID != uid else { return }

        listener?.remove()
        listener = nil
        listeningUID = uid

        guard let collection = calendarCollection else {
            events = []
            return
        }

        listener = collection.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }

            if let error {
                Task { @MainActor in
                    self.errorMessage = error.localizedDescription
                }
                return
            }

            let loaded = (snapshot?.documents ?? []).compactMap {
                document -> GroupEvents? in
                guard
                    let data = try? document.data(as: PersonalEventData.self)
                else {
                    return nil
                }
                return data.groupEvent(documentID: document.documentID)
            }
            .sorted { $0.time < $1.time }

            Task { @MainActor in
                self.events = loaded
                self.errorMessage = nil
            }
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        listeningUID = nil
    }

    /// Saves a new personal event. Its UUID becomes the document ID so the
    /// event keeps the same identity in Firestore and in the app.
    func add(_ event: GroupEvents) {
        guard let collection = calendarCollection else {
            errorMessage = "Sign in to save your calendar."
            return
        }

        do {
            try collection.document(event.id.uuidString)
                .setData(from: PersonalEventData(event: event))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func add(_ newEvents: [GroupEvents]) {
        for event in newEvents {
            add(event)
        }
    }

    /// Saves changes to an existing event, keeping its document ID.
    func update(_ event: GroupEvents) {
        add(event)
    }

    func delete(_ eventID: UUID) {
        guard let collection = calendarCollection else { return }

        collection.document(eventID.uuidString).delete { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                self?.errorMessage = error.localizedDescription
            }
        }
    }
}
