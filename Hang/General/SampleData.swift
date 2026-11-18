//
//  SampleData.swift
//  Hang
//
//  TEMPORARY SCAFFOLDING — delete at Checkpoint E.
//
//  Before this checkpoint the sample group, its members and its events lived
//  inside `TestGroup`'s default property values, so every view silently shared
//  one hard-coded group. Group data is now loaded from Firestore in Checkpoint
//  D, and these fixtures keep the existing screens runnable until the views are
//  rewired to `GroupStore`.
//
//  This is *not* availability data. Fabricated busy time stays in
//  `Availability.swift` behind `#if DEBUG`, and nothing here invents free/busy.
//

import FirebaseAuth
import FirebaseCore
import Foundation

enum SampleData {
    /// The signed-in account when there is one, otherwise a stable stand-in so
    /// previews render the "you" column. Previews have no Firebase app.
    static var currentUid: String {
        guard FirebaseApp.app() != nil else { return "sample-you" }
        return Auth.auth().currentUser?.uid ?? "sample-you"
    }

    static var members: [Person] {
        [
            Person(uid: currentUid, name: "You", status: "hello"),
            Person(uid: "sample-serene", name: "Serene", status: "hi"),
            Person(uid: "sample-iain", name: "Iain", status: "hey"),
            Person(uid: "sample-zixi", name: "Zixi", status: "wassup"),
        ]
    }

    static var group: TestGroup {
        var group = TestGroup(
            code: "ABCD67",
            name: "CODZEE",
            ownerUid: currentUid,
            memberUids: members.map(\.uid)
        )
        group.id = "sample-group"
        return group
    }

    static var events: [GroupEvents] {
        [
            event(id: "sample-event-1", name: "event1", at: 1_720_708_600),
            event(id: "sample-event-2", name: "event2", at: 1_790_403_500),
        ]
    }

    private static func event(id: String, name: String, at seconds: TimeInterval) -> GroupEvents {
        let start = Date(timeIntervalSince1970: seconds)
        var event = GroupEvents(
            name: name,
            startTime: start,
            endTime: start.addingTimeInterval(3600)
        )
        event.id = id
        return event
    }
}
