//
//  GroupFireModel.swift
//  Hang
//
//  Firestore models for the `groups` collection. Each group is a document at
//  `groups/<autoID>` whose members are stored as references to their
//  `users/<uid>` documents. Shared events live in the group's `events`
//  subcollection: `groups/<groupID>/events/<eventID>`.
//

import FirebaseFirestore
import Foundation

/// A group as it is stored in Firestore.
struct GroupData: Codable {
    /// The auto-generated group document ID. Filled in when reading, ignored
    /// when writing.
    @DocumentID var id: String?
    var inviteCode: String
    var name: String
    var desc: String
    /// References to the members' `users/<uid>` documents.
    var people: [DocumentReference]

    /// Rebuilds the in-app group. The Firestore document ID becomes the group's
    /// UUID so it keeps the same identity every time it loads, and is also kept
    /// as `documentID` so the group's events subcollection can be addressed.
    ///
    /// The current user is left out of `members` because the calendar shows them
    /// separately as `Person.currentUser` (with their real personal calendar).
    func testGroup(
        documentID: String,
        currentUserDocument: DocumentReference?,
        events: [GroupEvents] = []
    ) -> TestGroup {
        TestGroup(
            id: UUID(uuidString: documentID) ?? UUID(),
            code: inviteCode,
            name: name,
            desc: desc,
            members: people.compactMap { reference in
                guard let currentUserDocument,
                      reference.path != currentUserDocument.path else {
                    return nil
                }
                // Other members are placeholders until names can be resolved.
                return Person(name: "Member", status: "Member")
            },
            events: events,
            documentID: documentID
        )
    }
}

/// One event in a group's shared calendar, stored at
/// `groups/<groupID>/events/<eventID>`.
struct GroupEventData: Identifiable, Codable {
    /// Filled in from the document ID when reading, and left out when writing.
    @DocumentID var id: String?
    var name: String
    var desc: String
    var location: String
    /// When the event starts.
    var time: Timestamp
    /// When the event ends. Optional so events written without an end time
    /// still decode (the app treats those as one hour long).
    var endTime: Timestamp?

    init(event: GroupEvents) {
        self.name = event.name
        self.desc = event.desc
        self.location = ""
        self.time = Timestamp(date: event.startDate)
        self.endTime = Timestamp(date: event.endDate)
    }

    /// Rebuilds the in-app event. The Firestore document ID is the event's
    /// UUID, so the same record keeps its identity every time it loads.
    func groupEvent(documentID: String) -> GroupEvents {
        GroupEvents(
            id: UUID(uuidString: documentID) ?? UUID(),
            name: name,
            desc: desc,
            time: time.dateValue().timeIntervalSince1970,
            endTime: endTime?.dateValue().timeIntervalSince1970
        )
    }
}
