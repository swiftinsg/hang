//
//  GroupNotificationStore.swift
//  Hang
//
//  Group edits are fanned out through Firestore to every member's inbox. Each
//  device watches its own inbox and turns new records into the same local
//  notification GroupView used to fire on the editing device only.
//

import FirebaseAuth
import FirebaseFirestore
import Foundation

@MainActor
final class GroupNotificationStore {
    static let shared = GroupNotificationStore()

    private let db = Firestore.firestore()
    private let handler = NotificationHandler()
    private var authHandle: AuthStateDidChangeListenerHandle?
    private var listener: ListenerRegistration?
    private var listeningUID: String?
    /// Records this device has already shown. Seeded from the first snapshot so
    /// inbox history is not replayed after a launch or a sign-in.
    private var presentedIDs: Set<String> = []
    private var hasSeededExisting = false

    private init() {}

    /// Watches auth state so the inbox listener starts as soon as a session is
    /// available and is torn down on sign-out. Safe to call more than once.
    func startListening() {
        guard authHandle == nil else { return }
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.subscribe(uid: user?.uid)
            }
        }
    }

    /// Moves the Firestore listener to the given account. Only resubscribes
    /// when the uid actually changes.
    private func subscribe(uid: String?) {
        guard listener == nil || listeningUID != uid else { return }

        listener?.remove()
        listener = nil
        listeningUID = uid
        presentedIDs.removeAll()
        hasSeededExisting = false

        guard let uid else { return }

        listener = db.collection(Path.Firestore.Users)
            .document(uid)
            .collection(Path.Firestore.Notifications)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }

                if let error {
                    print("Group notification listener failed: \(error)")
                    return
                }

                let notices = (snapshot?.documents ?? []).compactMap { document -> (id: String, title: String, body: String)? in
                    let data = document.data()
                    guard data["kind"] as? String == "eventEdited",
                          let title = data["title"] as? String,
                          let body = data["body"] as? String else { return nil }
                    return (document.documentID, title, body)
                }

                Task { @MainActor in
                    // The first snapshot is inbox history, not a fresh edit.
                    guard self.hasSeededExisting else {
                        self.presentedIDs = Set(notices.map(\.id))
                        self.hasSeededExisting = true
                        return
                    }

                    for notice in notices where !self.presentedIDs.contains(notice.id) {
                        self.presentedIDs.insert(notice.id)
                        self.handler.sendNotification(title: notice.title, body: notice.body)
                    }
                }
            }
    }

    /// Writes one notice to every member's inbox, including the editor. The
    /// group document is the source of truth for membership, so the fan-out
    /// follows who is actually in the group at edit time.
    func notifyEventEdited(
        eventName: String,
        groupName: String,
        groupID: String,
        eventID: String
    ) async {
        guard !groupID.isEmpty, !AccountDeletionController.shared.isDeleting else { return }

        do {
            let snapshot = try await db.collection(Path.Firestore.Groups)
                .document(groupID)
                .getDocument()
            guard let group = try? snapshot.data(as: GroupData.self) else { return }

            let batch = db.batch()
            for member in group.people {
                let inbox = db.collection(Path.Firestore.Users)
                    .document(member.documentID)
                    .collection(Path.Firestore.Notifications)
                batch.setData([
                    "kind": "eventEdited",
                    "title": "\(eventName) has been edited",
                    "body": "\(eventName) in group \(groupName) has been edited",
                    "groupID": groupID,
                    "eventID": eventID,
                    "createdAt": FieldValue.serverTimestamp()
                ], forDocument: inbox.document())
            }
            try await batch.commit()
        } catch {
            print("Failed to deliver event edit notification: \(error)")
        }
    }
}
