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
        static let Users = "users"

        // Subcollection under each user document that holds their personal
        // calendar events: users/<uid>/calendar/<entryID>
        static let Calendar = "calendar"

        // Subcollection under each user document that holds group activity
        // delivered to that member: users/<uid>/notifications/<autoID>
        static let Notifications = "notifications"

        // One collection that holds one document per group.
        static let Groups = "groups"

        // Subcollection under each group document for shared events:
        // groups/<groupID>/events/<eventID>
        static let Events = "events"

        // Subcollection under each group document for anonymous busy times:
        // groups/<groupID>/availability/<uid>. Contains only start/end pairs.
        static let Availability = "availability"
    }
}
