//
//  AppReloader.swift
//  Hang
//
//  The action behind pull-to-refresh on the app's scrollable screens. It acts
//  like a browser reload: pull down, wait for fresh data, then let go.
//

import FirebaseAuth
import SwiftUI

enum AppReloader {
    @MainActor
    static func reloadAll() async {
        await PersonalEventsStore.shared.refresh()
        await GroupStore.shared.refresh()
        await AvailabilityStore.shared.refresh()
        PersonalCalendarStore.shared.refresh()

        let groupIDs = GroupStore.shared.groups
            .map(\.documentID)
            .filter { !$0.isEmpty }
        guard let uid = Auth.auth().currentUser?.uid, !groupIDs.isEmpty else {
            return
        }

        await AvailabilityPublisher.shared.refresh(
            groups: groupIDs,
            uid: uid,
            force: true
        )
    }
}
