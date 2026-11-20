//
//  GroupStore.swift
//  Hang
//
//  The signed-in user's groups. Groups live in Firestore under
//  `groups/<autoID>`; the list here is the local store of the groups the user
//  belongs to. Creating a group writes it to Firestore, and this store updates
//  from the resulting snapshot.
//

import FirebaseAuth
import FirebaseFirestore
import Foundation
import Observation

@Observable
final class GroupStore {
    static let shared = GroupStore()

    var groups: [TestGroup] = []
    private(set) var errorMessage: String?

    @ObservationIgnored private let db = Firestore.firestore()
    @ObservationIgnored private var listener: ListenerRegistration?
    @ObservationIgnored private var listeningUID: String?

    private init() {}

    /// `groups` collection reference.
    private var groupsCollection: CollectionReference {
        db.collection(Path.Firestore.Groups)
    }

    /// The signed-in user's `users/<uid>` document reference.
    private var currentUserDocument: DocumentReference? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        return db.collection(Path.Firestore.Users).document(uid)
    }

    // MARK: - Reading the user's groups

    /// Starts listening to the groups the signed-in user belongs to. Safe to
    /// call more than once; it only re-subscribes when the account changes.
    func startListening() {
        let uid = Auth.auth().currentUser?.uid
        guard listener == nil || listeningUID != uid else { return }

        listener?.remove()
        listener = nil
        listeningUID = uid

        guard let userDocument = currentUserDocument else {
            groups = []
            return
        }

        let collection = groupsCollection

        listener = collection
            .whereField("people", arrayContains: userDocument)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }

                if let error {
                    Task { @MainActor in
                        self.errorMessage = error.localizedDescription
                    }
                    return
                }

                let documents = snapshot?.documents ?? []

                Task {
                    let loaded = await buildGroups(
                        documents: documents,
                        groupsCollection: collection,
                        currentUserDocument: userDocument
                    )

                    await MainActor.run {
                        self.groups = loaded
                        self.errorMessage = nil
                    }
                }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        listeningUID = nil
    }

    // MARK: - Creating a group

    /// Creates a group in Firestore with the given name and description, using
    /// the provided invite code after making sure it is still available. The
    /// store updates once the group lands.
    func createGroup(name: String, desc: String, inviteCode: String) async throws {
        guard let userDocument = currentUserDocument else {
            throw GroupStoreError.notSignedIn
        }

        var code = inviteCode.isEmpty ? Self.randomInviteCode() : inviteCode
        while try await isInviteCodeTaken(code) {
            code = Self.randomInviteCode()
        }

        let data = GroupData(
            inviteCode: code,
            name: name,
            desc: desc,
            people: [userDocument]
        )

        try groupsCollection.document().setData(from: data)
    }

    /// Generates a 6-letter invite code that isn't already in use.
    func makeUniqueInviteCode() async throws -> String {
        var code = Self.randomInviteCode()
        while try await isInviteCodeTaken(code) {
            code = Self.randomInviteCode()
        }
        return code
    }

    // MARK: - Joining a group

    /// Joins the group with the given invite code. Adds the current user to the
    /// group's `people` list and the group to the user's `groupsIn` list in one
    /// atomic write. The store updates once the snapshot reflects the change.
    func joinGroup(inviteCode: String) async throws {
        guard let userDocument = currentUserDocument else {
            throw GroupStoreError.notSignedIn
        }

        let snapshot = try await groupsCollection
            .whereField("inviteCode", isEqualTo: inviteCode)
            .getDocuments()

        guard let groupDocument = snapshot.documents.first?.reference else {
            throw GroupStoreError.groupNotFound
        }

        let batch = db.batch()
        batch.updateData(
            ["people": FieldValue.arrayUnion([userDocument])],
            forDocument: groupDocument
        )
        batch.updateData(
            ["groupsIn": FieldValue.arrayUnion([groupDocument])],
            forDocument: userDocument
        )
        try await batch.commit()
    }

    // MARK: - Group events

    /// Writes a new event to the group's events subcollection. The event's UUID
    /// becomes the document ID, mirroring the personal events store.
    func addEvent(_ event: GroupEvents, to group: TestGroup) {
        guard !group.documentID.isEmpty else {
            errorMessage = "This group isn't saved to Firestore yet."
            return
        }

        do {
            try eventsCollection(for: group.documentID)
                .document(event.id.uuidString)
                .setData(from: GroupEventData(event: event))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// `groups/<groupID>/events`
    private func eventsCollection(for groupID: String) -> CollectionReference {
        groupsCollection.document(groupID).collection(Path.Firestore.Events)
    }

    // MARK: - Helpers

    private func isInviteCodeTaken(_ code: String) async throws -> Bool {
        let snapshot = try await groupsCollection
            .whereField("inviteCode", isEqualTo: code)
            .getDocuments()
        return !snapshot.isEmpty
    }

    private static func randomInviteCode(length: Int = 6) -> String {
        let characters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String(
            (0..<length).compactMap { _ in characters.randomElement() }
        )
    }
}

enum GroupStoreError: LocalizedError {
    case notSignedIn
    case groupNotFound

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "You must be signed in to do that."
        case .groupNotFound:
            return "Group not found. Please double-check the entered group code."
        }
    }
}

/// Builds the in-app groups from Firestore snapshots, pulling each group's
/// shared events from its `events` subcollection. Runs off the main actor.
private func buildGroups(
    documents: [QueryDocumentSnapshot],
    groupsCollection: CollectionReference,
    currentUserDocument: DocumentReference?
) async -> [TestGroup] {
    var loaded: [TestGroup] = []

    for document in documents {
        guard let data = try? document.data(as: GroupData.self) else { continue }

        let events = await loadGroupEvents(
            for: document.documentID,
            groupsCollection: groupsCollection
        )

        loaded.append(
            data.testGroup(
                documentID: document.documentID,
                currentUserDocument: currentUserDocument,
                events: events
            )
        )
    }

    return loaded
}

/// Fetches one group's shared events, oldest first.
private func loadGroupEvents(
    for groupID: String,
    groupsCollection: CollectionReference
) async -> [GroupEvents] {
    guard let snapshot = try? await groupsCollection
        .document(groupID)
        .collection(Path.Firestore.Events)
        .getDocuments()
    else {
        return []
    }

    return snapshot.documents
        .compactMap { document -> GroupEvents? in
            guard let data = try? document.data(as: GroupEventData.self) else {
                return nil
            }
            return data.groupEvent(documentID: document.documentID)
        }
        .sorted { $0.time < $1.time }
}
