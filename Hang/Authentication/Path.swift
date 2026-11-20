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
    }
}
