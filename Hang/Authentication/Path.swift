//
//  Path.swift
//  Hang
//
//  Created by Lim Shi Hui Serene     on 11/11/26.
//

import Foundation

struct Path {
    struct Firestore {
        // One collection that holds one document per signed-in Apple account.
        static let profiles = "Profiles"

        // Groups/{groupID} plus its subcollections.
        static let groups = "Groups"
        static let members = "members"
        static let events = "events"
        static let availability = "availability"

        // GroupCodes/{code} → { groupID } so a code can only be claimed once.
        static let groupCodes = "GroupCodes"
    }
}
