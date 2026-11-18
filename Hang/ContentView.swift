import FirebaseAuth
import FirebaseCore
import SwiftUI

struct ContentView: View {
    @StateObject private var saveManager = SaveManager()
    @State private var groupStore = GroupStore()
    @State private var availabilityStore = AvailabilityStore()
    @State private var calendarStore = PersonalCalendarStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var userName = ""
    @State private var showNamePrompt = false

    private var uid: String? {
        guard FirebaseApp.app() != nil else { return nil }
        return Auth.auth().currentUser?.uid
    }

    private var groupIDs: [String] {
        groupStore.groups.compactMap(\.id)
    }

    /// Groups this account is actually publishing to.
    ///
    /// A member who turned sharing off must not have availability re-uploaded
    /// just because another group appeared. A missing roster means "not loaded
    /// yet", and the create/join paths already publish for themselves, so an
    /// unknown state is treated as "do not publish".
    private var sharingGroupIDs: [String] {
        guard let uid else { return [] }

        return groupIDs.filter { groupID in
            groupStore.roster(groupID).contains {
                $0.uid == uid && $0.sharingEnabled
            }
        }
    }

    var body: some View {
        TabView {
            Tab("We", systemImage: "person.and.person.fill") {
                WeView()
                    .environment(groupStore)
                    .environment(availabilityStore)
            }
            Tab("Me", systemImage: "calendar") {
                MeView()
                    .environment(groupStore)
                    .environment(availabilityStore)
            }
        }
        .tint(.green)
        .task {
            groupStore.start()
            saveManager.loadProfile()
        }
        .onDisappear {
            groupStore.stop()
            availabilityStore.stopAll()
        }
        .onChange(of: groupIDs, initial: true) { _, ids in
            // Watch every group the account belongs to, and stop watching
            // groups that disappeared because this account left them.
            availabilityStore.sync(groupIDs: ids)
        }
        .onChange(of: sharingGroupIDs, initial: true) { _, ids in
            Task { await publishAvailability(to: ids) }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // Re-import after the device calendar may have changed while the
            // app was in the background. The change below triggers a publish.
            calendarStore.loadEventsIfAuthorized()
        }
        .onChange(of: calendarStore.events) { _, _ in
            Task { await publishAvailability(to: sharingGroupIDs) }
        }
        .onChange(of: saveManager.hasLoadedProfile) { _, loaded in
            guard loaded else { return }
            // Only accounts without a username get the prompt.
            let trimmedName = saveManager.profile?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            showNamePrompt = trimmedName.isEmpty
        }
        .alert("Enter your username", isPresented: $showNamePrompt) {
            TextField("Your name", text: $userName)
            Button("Done") {
                let trimmedName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedName.isEmpty else { return }
                saveManager.saveUsername(trimmedName)
                userName = ""
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func publishAvailability(to groupIDs: [String]) async {
        guard let uid else { return }

        for groupID in groupIDs {
            try? await AvailabilityPublisher.shared.publish(to: groupID, uid: uid)
        }
    }
}

#Preview {
    ContentView()
}
