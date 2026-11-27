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

            let loaded = Self.decodeEvents(from: snapshot?.documents ?? [])

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
        // Never carry one account's private events into the next sign-in.
        events = []
        errorMessage = nil
    }

    /// Forces a fresh read for pull-to-refresh. The live listener stays in
    /// place, so later changes still arrive without another manual refresh.
    func refresh() async {
        guard let collection = calendarCollection else {
            events = []
            return
        }

        do {
            let snapshot = try await collection.getDocuments()
            events = Self.decodeEvents(from: snapshot.documents)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func decodeEvents(
        from documents: [QueryDocumentSnapshot]
    ) -> [GroupEvents] {
        documents.compactMap { document in
            guard
                let data = try? document.data(as: PersonalEventData.self)
            else {
                return nil
            }
            return data.groupEvent(documentID: document.documentID)
        }
        .sorted { $0.time < $1.time }
    }

    /// Saves new personal events in one batch. Their UUIDs become document IDs
    /// so they keep the same identity in Firestore and in the app.
    func add(_ newEvents: [GroupEvents]) async throws {
        guard let collection = calendarCollection else {
            throw GroupStoreError.notSignedIn
        }
        guard !newEvents.isEmpty else { return }

        do {
            // Repeats are capped well below Firestore's 500-write limit.
            for chunk in newEvents.chunks(of: 400) {
                let batch = db.batch()
                for event in chunk {
                    try batch.setData(
                        from: PersonalEventData(event: event),
                        forDocument: collection.document(event.id.uuidString)
                    )
                }
                try await batch.commit()
            }
            await MainActor.run { self.errorMessage = nil }
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription }
            throw error
        }
    }

    func add(_ event: GroupEvents) async throws {
        try await add([event])
    }

    /// Saves changes to an existing event, keeping its document ID.
    func update(_ event: GroupEvents) async throws {
        try await add(event)
    }

    func delete(_ eventID: UUID) async throws {
        guard let collection = calendarCollection else {
            throw GroupStoreError.notSignedIn
        }

        do {
            try await collection.document(eventID.uuidString).delete()
            await MainActor.run { self.errorMessage = nil }
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription }
            throw error
        }
    }
}
