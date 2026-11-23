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
    /// uid → username, copied into the group when someone joins. Personal
    /// calendars stay private; only the display name is shared with the group.
    var memberNames: [String: String] = [:]
    /// uid → profile picture raw value, copied in alongside `memberNames` so
    /// every member can render avatars without reading private user documents.
    var memberProfilePictures: [String: String] = [:]

    init(
        inviteCode: String,
        name: String,
        desc: String,
        people: [DocumentReference],
        memberNames: [String: String] = [:],
        memberProfilePictures: [String: String] = [:]
    ) {
        self.inviteCode = inviteCode
        self.name = name
        self.desc = desc
        self.people = people
        self.memberNames = memberNames
        self.memberProfilePictures = memberProfilePictures
    }

    /// Older groups were saved without `memberNames` or `memberProfilePictures`.
    /// Decode those as empty so they still load; both are backfilled when each
    /// member next opens the app.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inviteCode = try container.decode(String.self, forKey: .inviteCode)
        name = try container.decode(String.self, forKey: .name)
        desc = try container.decode(String.self, forKey: .desc)
        people = try container.decode([DocumentReference].self, forKey: .people)
        memberNames =
            try container.decodeIfPresent([String: String].self, forKey: .memberNames)
            ?? [:]
        memberProfilePictures =
            try container.decodeIfPresent(
                [String: String].self,
                forKey: .memberProfilePictures
            ) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case id, inviteCode, name, desc, people, memberNames, memberProfilePictures
    }

    /// Rebuilds the in-app group. The Firestore document ID becomes the group's
    /// UUID so it keeps the same identity every time it loads, and is also kept
    /// as `documentID` so the group's events subcollection can be addressed.
    ///
    /// `members` includes the signed-in user as `Person.currentUser` (always
    /// first) plus every other member, so the member list and count include the
    /// user while the calendar shows them left-most.
    func testGroup(
        documentID: String,
        currentUserDocument: DocumentReference?,
        events: [GroupEvents] = []
    ) -> TestGroup {
        let otherMembers = people.compactMap { reference -> Person? in
            guard let currentUserDocument,
                  reference.path != currentUserDocument.path else {
                return nil
            }
            let uid = reference.documentID
            let resolvedName = memberNames[uid]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return Person(
                uid: uid,
                name: resolvedName.isEmpty ? "Member" : resolvedName,
                status: "Group member",
                profilePicture: picture(for: uid)
            )
        }

        // The current user is labelled "You" in the shared calendar, but an
        // initial-only avatar should still use their actual username.
        let currentUID = currentUserDocument?.documentID ?? ""
        var current = Person.currentUser
        current.profilePicture = picture(for: currentUID)
        if let name = memberNames[currentUID] {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { current.avatarName = trimmed }
        }

        return TestGroup(
            id: UUID(uuidString: documentID) ?? UUID(),
            code: inviteCode,
            name: name,
            desc: desc,
            members: [current] + otherMembers,
            events: events,
            documentID: documentID
        )
    }

    /// Members added before profile pictures existed fall back to the initial.
    private func picture(for uid: String) -> ProfilePicture {
        guard let raw = memberProfilePictures[uid] else { return .initial }
        return ProfilePicture(rawValue: raw) ?? .initial
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
        self.location = event.location
        self.time = Timestamp(date: event.startDate)
        self.endTime = Timestamp(date: event.endDate)
    }

    /// Older event documents were written without a `location` key. Default it
    /// to an empty string so those events still decode instead of being dropped
    /// by the store's `compactMap`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        desc = try container.decode(String.self, forKey: .desc)
        location = try container.decodeIfPresent(String.self, forKey: .location) ?? ""
        time = try container.decode(Timestamp.self, forKey: .time)
        endTime = try container.decodeIfPresent(Timestamp.self, forKey: .endTime)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, desc, location, time, endTime
    }

    /// Rebuilds the in-app event. The Firestore document ID is the event's
    /// UUID, so the same record keeps its identity every time it loads.
    func groupEvent(documentID: String) -> GroupEvents {
        GroupEvents(
            id: UUID(uuidString: documentID) ?? UUID(),
            name: name,
            desc: desc,
            location: location,
            time: time.dateValue().timeIntervalSince1970,
            endTime: endTime?.dateValue().timeIntervalSince1970
        )
    }
}
