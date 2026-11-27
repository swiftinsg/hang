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
import SwiftUI

@Observable
final class GroupStore {
    static let shared = GroupStore()

    var groups: [TestGroup] = []
    private(set) var errorMessage: String?

    @ObservationIgnored private let db = Firestore.firestore()
    @ObservationIgnored private var listener: ListenerRegistration?
    @ObservationIgnored private var listeningUID: String?
    /// Live listeners on each opened group's `events` subcollection, keyed by
    /// the group's Firestore document ID, so new hangouts show up for every
    /// member without reopening the app.
    @ObservationIgnored private var eventListeners: [String: ListenerRegistration] = [:]

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
                        self.syncEventListeners(for: loaded)
                        self.errorMessage = nil
                    }
                }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        listeningUID = nil

        // Tear down every group-event listener too, so a previous account's
        // live updates can't leak into the next one.
        for registration in eventListeners.values {
            registration.remove()
        }
        eventListeners.removeAll()
    }

    /// Forces a fresh read of groups and their events for pull-to-refresh.
    /// Existing live listeners are kept so later changes still arrive.
    func refresh() async {
        guard let userDocument = currentUserDocument else {
            groups = []
            return
        }

        do {
            let snapshot = try await groupsCollection
                .whereField("people", arrayContains: userDocument)
                .getDocuments()
            let loaded = await buildGroups(
                documents: snapshot.documents,
                groupsCollection: groupsCollection,
                currentUserDocument: userDocument
            )

            groups = loaded
            syncEventListeners(for: loaded)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Creating a group

    /// Creates a group in Firestore with the given name and description, using
    /// the provided invite code after making sure it is still available. Adds
    /// the creator to the group's `people` list and the group to the creator's
    /// `groupsIn` list in one atomic write. The store updates once the group
    /// lands.
    func createGroup(name: String, desc: String, inviteCode: String) async throws {
        guard let userDocument = currentUserDocument else {
            throw GroupStoreError.notSignedIn
        }

        var code = inviteCode.isEmpty ? Self.randomInviteCode() : inviteCode
        while try await isInviteCodeTaken(code) {
            code = Self.randomInviteCode()
        }

        let groupDocument = groupsCollection.document()
        let uid = userDocument.documentID
        let profile = await currentProfile()
        guard !AccountDeletionController.shared.isDeleting else {
            throw GroupStoreError.accountDeletionInProgress
        }

        let data = GroupData(
            inviteCode: code,
            name: name,
            desc: desc,
            people: [userDocument],
            memberNames: profile.username.isEmpty ? [:] : [uid: profile.username],
            memberProfilePictures: [uid: profile.picture.rawValue],
            eventColor: PersonalEventOutlineColor.randomGroupColor.rawValue
        )

        let batch = db.batch()
        try batch.setData(from: data, forDocument: groupDocument)
        batch.updateData(
            ["groupsIn": FieldValue.arrayUnion([groupDocument])],
            forDocument: userDocument
        )
        try await batch.commit()
    }

    /// Persists the colour used by this group's shared events. Any member can
    /// change it from More Info; the group listener then updates everyone's
    /// local copy, including the colour attached to each loaded event.
    func setEventColor(_ color: PersonalEventOutlineColor, for group: TestGroup) async {
        guard !group.documentID.isEmpty else {
            await MainActor.run {
                self.errorMessage = GroupStoreError.groupNotSaved.errorDescription
            }
            return
        }

        do {
            try await groupsCollection
                .document(group.documentID)
                .updateData(["eventColor": color.rawValue])

            await MainActor.run {
                guard let index = self.groups.firstIndex(where: {
                    $0.documentID == group.documentID
                }) else { return }
                self.groups[index].eventColor = color
                let hangColor = color.hangColor ?? .blue
                self.groups[index].events = self.groups[index].events.map { event in
                    var colored = event
                    colored.groupColor = hangColor
                    return colored
                }
                self.errorMessage = nil
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }
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

        let uid = userDocument.documentID
        let profile = await currentProfile()
        guard !AccountDeletionController.shared.isDeleting else {
            throw GroupStoreError.accountDeletionInProgress
        }

        var groupUpdate: [String: Any] = [
            "people": FieldValue.arrayUnion([userDocument]),
            "memberProfilePictures.\(uid)": profile.picture.rawValue
        ]
        if !profile.username.isEmpty {
            groupUpdate["memberNames.\(uid)"] = profile.username
        }

        let batch = db.batch()
        batch.updateData(groupUpdate, forDocument: groupDocument)
        batch.updateData(
            ["groupsIn": FieldValue.arrayUnion([groupDocument])],
            forDocument: userDocument
        )
        try await batch.commit()
    }

    // MARK: - Leaving a group

    /// Removes the signed-in user from the group's `people` list and the group
    /// from the user's `groupsIn` list in one atomic write. The live group
    /// listener then drops the group from the store, so the user stops seeing
    /// it and every remaining member sees them leave.
    func leaveGroup(_ group: TestGroup) async {
        guard let userDocument = currentUserDocument else {
            await MainActor.run {
                self.errorMessage = GroupStoreError.notSignedIn.errorDescription
            }
            return
        }

        guard !group.documentID.isEmpty else {
            await MainActor.run {
                self.errorMessage = GroupStoreError.groupNotSaved.errorDescription
            }
            return
        }

        let groupDocument = groupsCollection.document(group.documentID)

        let batch = db.batch()
        batch.updateData(
            [
                "people": FieldValue.arrayRemove([userDocument]),
                "memberNames.\(userDocument.documentID)": FieldValue.delete(),
                "memberProfilePictures.\(userDocument.documentID)": FieldValue.delete()
            ],
            forDocument: groupDocument
        )
        batch.updateData(
            ["groupsIn": FieldValue.arrayRemove([groupDocument])],
            forDocument: userDocument
        )

        do {
            try await batch.commit()
            // Remove the busy intervals we shared with this group. After we
            // leave, nobody in it should still be able to read them.
            if let uid = Auth.auth().currentUser?.uid {
                await AvailabilityPublisher.shared.unpublish(
                    from: group.documentID,
                    uid: uid
                )
            }
            await MainActor.run {
                // Stop watching this group's events now that we're no longer a
                // member, so stale updates can't keep firing for a group we left.
                self.stopListeningToEvents(for: group.documentID)
                self.errorMessage = nil
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }
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

    /// Saves changes to an existing group event. It reuses the same write as
    /// `addEvent`, overwriting the document at the event's UUID so every member
    /// sees the edit through the live listener.
    func updateEvent(_ event: GroupEvents, to group: TestGroup) {
        addEvent(event, to: group)
    }

    /// Removes a group event. The live listener reflects the deletion to every
    /// member.
    func deleteEvent(_ eventID: UUID, from group: TestGroup) {
        guard !group.documentID.isEmpty else {
            errorMessage = "This group isn't saved to Firestore yet."
            return
        }
        Task {
            do {
                try await eventsCollection(for: group.documentID)
                    .document(eventID.uuidString)
                    .delete()
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    /// `groups/<groupID>/events`
    private func eventsCollection(for groupID: String) -> CollectionReference {
        groupsCollection.document(groupID).collection(Path.Firestore.Events)
    }

    /// Starts a live listener on one group's shared events so new hangouts
    /// appear for every member as soon as they're created. Safe to call more
    /// than once; it only subscribes once per group.
    func startListeningToEvents(for group: TestGroup) {
        let documentID = group.documentID
        guard !documentID.isEmpty, eventListeners[documentID] == nil else {
            return
        }

        eventListeners[documentID] = eventsCollection(for: documentID)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }

                if let error {
                    Task { @MainActor in
                        self.errorMessage = error.localizedDescription
                    }
                    return
                }

                let events = (snapshot?.documents ?? [])
                    .compactMap { document -> GroupEvents? in
                        guard
                            let data = try? document.data(as: GroupEventData.self)
                        else {
                            return nil
                        }
                        return data.groupEvent(documentID: document.documentID)
                    }
                    .sorted { $0.time < $1.time }

                Task { @MainActor in
                    guard let index = self.groups.firstIndex(where: {
                        $0.documentID == documentID
                    }) else {
                        return
                    }
                    // Keep the group's display colour on each event so the
                    // personal calendar can tint every group's mini-bar bar.
                    let groupColor = self.groups[index].eventColor.hangColor ?? .blue
                    self.groups[index].events = events.map { event in
                        var colored = event
                        colored.groupColor = groupColor
                        return colored
                    }
                }
            }
    }

    /// Stops listening to one group's shared events.
    func stopListeningToEvents(for documentID: String) {
        eventListeners.removeValue(forKey: documentID)?.remove()
    }

    /// Keeps one live event listener per group the user still belongs to. The
    /// personal calendar reads events from every group, not just the first one
    /// the user happens to open, so all of them must stay live.
    @MainActor
    private func syncEventListeners(for groups: [TestGroup]) {
        let liveIDs = Set(groups.map(\.documentID).filter { !$0.isEmpty })

        for documentID in Array(eventListeners.keys) where !liveIDs.contains(documentID) {
            stopListeningToEvents(for: documentID)
        }
        for group in groups where !group.documentID.isEmpty {
            startListeningToEvents(for: group)
        }
    }

    // MARK: - Helpers

    /// The signed-in user's display data from their own profile document. Only
    /// the account owner can read this, which is why it is copied into groups.
    private func currentProfile() async -> (username: String, picture: ProfilePicture) {
        guard let uid = Auth.auth().currentUser?.uid else { return ("", .initial) }
        let document = try? await db
            .collection(Path.Firestore.Users)
            .document(uid)
            .getDocument()
        let data = document?.data()
        let raw = data?["username"] as? String ?? ""
        let rawPicture = data?["profilePicture"] as? String ?? ""
        return (
            raw.trimmingCharacters(in: .whitespacesAndNewlines),
            ProfilePicture(rawValue: rawPicture) ?? .initial
        )
    }

    /// Copies this user's current username and profile picture into every group
    /// they belong to, so other members see a real name and avatar instead of
    /// placeholders. Safe to call on launch and whenever either choice changes.
    func refreshMyProfile(picture: ProfilePicture? = nil) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let profile = await currentProfile()
        // The caller may have just saved a new picture; prefer that over a
        // profile read that could still return the previous value.
        let selectedPicture = picture ?? profile.picture

        // Only groups from the membership listener are safe to update. A stale
        // `groupsIn` reference would be denied by the tightened rules and could
        // fail the entire batch, so it is deliberately not used here.
        let ids = Set(groups.map(\.documentID).filter { !$0.isEmpty })
        guard !ids.isEmpty else { return }

        var update: [String: Any] = [
            "memberProfilePictures.\(uid)": selectedPicture.rawValue
        ]
        if !profile.username.isEmpty {
            update["memberNames.\(uid)"] = profile.username
        }

        let batch = db.batch()
        for id in ids {
            batch.updateData(update, forDocument: groupsCollection.document(id))
        }
        // The profile read above can finish after account deletion has begun.
        // Do not let that older operation recreate membership data afterward.
        guard !AccountDeletionController.shared.isDeleting else { return }
        do {
            try await batch.commit()
            await MainActor.run { self.errorMessage = nil }
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription }
        }
    }

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
    case groupNotSaved
    case accountDeletionInProgress

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "You must be signed in to do that."
        case .groupNotFound:
            return "Group not found. Please double-check the entered group code."
        case .groupNotSaved:
            return "This group isn't saved to Firestore yet."
        case .accountDeletionInProgress:
            return "Account deletion is in progress."
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
