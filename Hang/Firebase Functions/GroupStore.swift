//
//  GroupStore.swift
//  Hang
//
//  Owns group documents and their two subcollections.
//
//  Groups/{groupID}                  name, code, owner, memberUids
//  Groups/{groupID}/members/{uid}    display name, join date, sharing flag
//  Groups/{groupID}/events/{id}      group-owned events (shared with everyone)
//  Groups/{groupID}/availability/{uid}  anonymous busy intervals (see
//                                       AvailabilityPublisher for the contract)
//
//  A member document holds a name and a sharing flag, never any calendar data.
//

import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation
import Observation

@Observable
final class GroupStore {
    private(set) var groups: [TestGroup] = []
    private(set) var members: [String: [Person]] = [:]
    private(set) var events: [String: [GroupEvents]] = [:]
    private(set) var errorMessage: String?

    /// Resolved lazily so constructing a store (for example in a `#Preview`)
    /// never touches Firebase before the app has been configured.
    private var db: Firestore { Firestore.firestore() }

    @ObservationIgnored private var groupListener: ListenerRegistration?
    @ObservationIgnored private var memberListeners: [String: ListenerRegistration] = [:]
    @ObservationIgnored private var eventListeners: [String: ListenerRegistration] = [:]

    /// Previews and signed-out states have no Firebase app; treat that as
    /// "nobody is signed in" rather than trapping.
    private var uid: String? {
        guard FirebaseApp.app() != nil else { return nil }
        return Auth.auth().currentUser?.uid
    }

    // MARK: - Lifecycle

    func start() {
        guard let uid, groupListener == nil else { return }

        groupListener = db
            .collection(Path.Firestore.groups)
            .whereField("memberUids", arrayContains: uid)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }

                if let error {
                    Task { @MainActor in self.errorMessage = error.localizedDescription }
                    return
                }
                guard let snapshot else { return }

                let decoded = snapshot.documents.compactMap { document in
                    try? document.data(as: TestGroup.self)
                }

                Task { @MainActor in
                    self.groups = decoded.sorted {
                        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }
                    self.errorMessage = nil
                    self.reconcileChildListeners()
                }
            }
    }

    func stop() {
        groupListener?.remove()
        groupListener = nil
        for listener in memberListeners.values { listener.remove() }
        for listener in eventListeners.values { listener.remove() }
        memberListeners = [:]
        eventListeners = [:]
        groups = []
        members = [:]
        events = [:]
    }

    /// Keeps one listener per visible group, and drops listeners for groups
    /// that no longer exist or that we left.
    private func reconcileChildListeners() {
        let liveIDs = Set(groups.compactMap(\.id))

        for gone in Array(memberListeners.keys) where !liveIDs.contains(gone) {
            memberListeners.removeValue(forKey: gone)?.remove()
            members[gone] = nil
        }
        for gone in Array(eventListeners.keys) where !liveIDs.contains(gone) {
            eventListeners.removeValue(forKey: gone)?.remove()
            events[gone] = nil
        }
        for id in liveIDs {
            listenMembers(groupID: id)
            listenEvents(groupID: id)
        }
    }

    // MARK: - Child listeners

    private func listenMembers(groupID: String) {
        guard memberListeners[groupID] == nil else { return }

        memberListeners[groupID] = db
            .collection(Path.Firestore.groups)
            .document(groupID)
            .collection(Path.Firestore.members)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let snapshot else { return }

                let people = snapshot.documents.map { document -> Person in
                    let data = document.data()
                    return Person(
                        uid: document.documentID,
                        name: data["name"] as? String ?? "Member",
                        status: data["status"] as? String ?? "",
                        sharingEnabled: data["sharingEnabled"] as? Bool ?? true
                    )
                }

                Task { @MainActor in
                    self.members[groupID] = people.sorted {
                        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }
                }
            }
    }

    private func listenEvents(groupID: String) {
        guard eventListeners[groupID] == nil else { return }

        eventListeners[groupID] = db
            .collection(Path.Firestore.groups)
            .document(groupID)
            .collection(Path.Firestore.events)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let snapshot else { return }

                let list = snapshot.documents.compactMap { document in
                    try? document.data(as: GroupEvents.self)
                }

                Task { @MainActor in
                    self.events[groupID] = list.sorted { $0.startTime < $1.startTime }
                }
            }
    }

    // MARK: - Creating and joining

    /// Creates the group document, reserves its code, and registers the owner
    /// as the first member. Returns the new group's id and the code that was
    /// actually reserved (a collision can make it differ from any code the UI
    /// previewed).
    ///
    /// The group is written before its code on purpose: the security rules only
    /// let an owner reserve a code for a group they already own (see
    /// `firestore.rules`). `code` therefore starts empty and is set immediately
    /// afterwards, exactly once.
    @discardableResult
    func createGroup(name rawName: String) async throws -> (id: String, code: String) {
        guard let uid else { throw JoinError.notSignedIn }

        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let reference = db.collection(Path.Firestore.groups).document()

        try await reference.setData([
            "name": name,
            "desc": "Add description here...",
            "code": "",
            "ownerUid": uid,
            "memberUids": [uid],
            "createdAt": FieldValue.serverTimestamp(),
        ])

        var reservedCode: String?
        let code: String
        do {
            let claimed = try await InviteCode.claimRandomCode(
                for: reference.documentID,
                uid: uid
            )
            reservedCode = claimed
            try await reference.updateData(["code": claimed])
            code = claimed
        } catch {
            // Don't leave a group with no code, or a reservation pointing at a
            // group that never finished being created.
            if let reservedCode {
                await InviteCode.release(reservedCode)
            }
            try? await reference.delete()
            throw error
        }

        try await addMember(groupID: reference.documentID, uid: uid)

        // The owner is sharing by default, so publish immediately. An empty
        // calendar still writes the document, which is what distinguishes
        // "sharing and free" from "not sharing".
        try? await AvailabilityPublisher.shared.publish(
            to: reference.documentID,
            uid: uid
        )

        return (reference.documentID, code)
    }

    func joinGroup(code raw: String, shareAvailability: Bool) async throws {
        guard let uid else { throw JoinError.notSignedIn }

        let code = InviteCode.normalize(raw)
        guard !code.isEmpty else { throw JoinError.codeNotFound }

        let groupID = try await InviteCode.resolve(code)
        let reference = db.collection(Path.Firestore.groups).document(groupID)
        let snapshot = try await reference.getDocument()

        guard snapshot.exists else { throw JoinError.groupMissing }

        let memberUids = snapshot.data()?["memberUids"] as? [String] ?? []
        guard !memberUids.contains(uid) else { throw JoinError.alreadyMember }

        try await reference.updateData(["memberUids": FieldValue.arrayUnion([uid])])
        try await addMember(groupID: groupID, uid: uid, sharing: shareAvailability)

        if shareAvailability {
            try? await AvailabilityPublisher.shared.publish(to: groupID, uid: uid)
        }
    }

    /// Leaves a group, cleaning up everything that belonged to this member.
    ///
    /// - The published availability document is deleted (nothing left to read).
    /// - The roster entry is deleted while still a member, so the rules allow it.
    /// - The owner hands ownership to a remaining member, or deletes an empty
    ///   group along with its invite code.
    ///
    /// The group is read before anything changes because the owner and member
    /// list decide what happens next: transfer ownership, or delete an empty
    /// group.
    func leaveGroup(_ groupID: String) async {
        guard let uid else { return }

        let reference = db.collection(Path.Firestore.groups).document(groupID)
        let snapshot = try? await reference.getDocument()
        let group = snapshot.flatMap { try? $0.data(as: TestGroup.self) }

        await AvailabilityPublisher.shared.unpublish(from: groupID, uid: uid)
        try? await reference
            .collection(Path.Firestore.members)
            .document(uid)
            .delete()

        let isOwner = group?.ownerUid == uid
        let isLastMember = (group?.memberUids.count ?? 0) <= 1

        if isOwner && isLastMember {
            // Release before deleting: the rules can then still look up the
            // group to confirm the caller owns it.
            if let code = group?.code, !code.isEmpty {
                await InviteCode.release(code)
            }
            try? await reference.delete()
            return
        }

        var update: [String: Any] = ["memberUids": FieldValue.arrayRemove([uid])]
        if isOwner, let heir = group?.memberUids.first(where: { $0 != uid }) {
            update["ownerUid"] = heir
        }
        try? await reference.updateData(update)
    }

    /// Turns availability sharing on or off for one group. Turning it off
    /// deletes the published document, so there is nothing left to read.
    func setSharing(_ enabled: Bool, groupID: String) async {
        guard let uid else { return }

        try? await db
            .collection(Path.Firestore.groups)
            .document(groupID)
            .collection(Path.Firestore.members)
            .document(uid)
            .setData(["sharingEnabled": enabled], merge: true)

        if enabled {
            try? await AvailabilityPublisher.shared.publish(to: groupID, uid: uid)
        } else {
            await AvailabilityPublisher.shared.unpublish(from: groupID, uid: uid)
        }
    }

    private func addMember(groupID: String, uid: String, sharing: Bool = true) async throws {
        let profile = try? await db
            .collection(Path.Firestore.profiles)
            .document(uid)
            .getDocument()
        let name = (profile?.data()?["username"] as? String) ?? "Member"

        try await db
            .collection(Path.Firestore.groups)
            .document(groupID)
            .collection(Path.Firestore.members)
            .document(uid)
            .setData([
                "name": name,
                "joinedAt": FieldValue.serverTimestamp(),
                "sharingEnabled": sharing,
            ])
    }

    // MARK: - Events

    @discardableResult
    func addEvent(
        to groupID: String,
        name: String,
        desc: String,
        start: Date,
        end: Date
    ) async throws -> String {
        guard let uid else { throw JoinError.notSignedIn }

        let event = GroupEvents(
            name: name,
            desc: desc,
            startTime: start,
            endTime: end,
            createdBy: uid
        )
        // This SDK has no async `addDocument(from:)`, only a callback variant
        // whose errors a bare `try await` would drop. Encode, then use the
        // async data write so failures actually surface.
        let encoded = try Firestore.Encoder().encode(event)
        let reference = try await db
            .collection(Path.Firestore.groups)
            .document(groupID)
            .collection(Path.Firestore.events)
            .addDocument(data: encoded)
        return reference.documentID
    }

    func updateEvent(_ event: GroupEvents, in groupID: String) async throws {
        guard let id = event.id else { return }
        let encoded = try Firestore.Encoder().encode(event)
        try await db
            .collection(Path.Firestore.groups)
            .document(groupID)
            .collection(Path.Firestore.events)
            .document(id)
            .setData(encoded)
    }

    func deleteEvent(_ event: GroupEvents, in groupID: String) async {
        guard let id = event.id else { return }
        try? await db
            .collection(Path.Firestore.groups)
            .document(groupID)
            .collection(Path.Firestore.events)
            .document(id)
            .delete()
    }

    // MARK: - Reading

    func group(_ id: String) -> TestGroup? {
        groups.first { $0.id == id }
    }

    func roster(_ id: String) -> [Person] {
        members[id] ?? []
    }

    func groupEvents(_ id: String) -> [GroupEvents] {
        events[id] ?? []
    }

    func allGroupEvents() -> [GroupEvents] {
        events.values.flatMap { $0 }
    }
}

#if DEBUG
extension GroupStore {
    /// A fully in-memory store for previews. It never touches Firestore, which
    /// is the point: previews run without a configured Firebase app.
    static func preview(
        with members: [Person],
        group: TestGroup = PreviewData.group,
        events: [GroupEvents] = PreviewData.events
    ) -> GroupStore {
        let store = GroupStore()
        store.groups = [group]

        if let id = group.id {
            store.members[id] = members
            store.events[id] = events
        }

        return store
    }
}
#endif
