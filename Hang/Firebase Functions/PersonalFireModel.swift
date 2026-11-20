//
//  FireModel.swift
//  Hang
//
//  Created by Lim Shi Hui Serene     on 12/11/26.
//

import Foundation
import FirebaseFirestore

struct ProfileData: Identifiable, Codable {
    @DocumentID var id: String?
    var username: String
}

/// One entry in the signed-in user's personal calendar, stored at
/// `users/<uid>/calendar/<entryID>`.
struct PersonalEventData: Identifiable, Codable {
    /// Filled in from the document ID when reading, and left out when writing.
    @DocumentID var id: String?
    var name: String
    var desc: String
    /// When the event starts.
    var time: Timestamp
    /// When the event ends. Optional so events written without an end time
    /// still decode (the app treats those as one hour long).
    var endTime: Timestamp?

    init(event: GroupEvents) {
        self.name = event.name
        self.desc = event.desc
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
