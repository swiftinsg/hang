//
//  GroupStore.swift
//  Hang
//
//  Shared group and event data. Events added in the We group calendar flow
//  one way into the Me personal calendar, where they are read only.
//

import Foundation
import Observation

@Observable
final class GroupStore {
    static let shared = GroupStore()

    var groups: [TestGroup] = [
        TestGroup(code: "ABCD67", name: "CODZEE")
    ]

    private init() {}
}
