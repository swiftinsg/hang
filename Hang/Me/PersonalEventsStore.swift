//
//  PersonalEventsStore.swift
//  Hang
//
//  Events created on the Me calendar. They belong to you, are shown read only
//  in the We group calendar, and are separate from the group's shared events.
//

import Foundation
import Observation

@Observable
final class PersonalEventsStore {
    static let shared = PersonalEventsStore()

    var events: [GroupEvents] = []

    private init() {}
}
