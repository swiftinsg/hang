import FirebaseAuth
import FirebaseCore
import SwiftUI

struct ContentView: View {
    @StateObject private var saveManager = SaveManager()
    @State private var userName = ""
    @State private var showNamePrompt = false

    @State private var calendarStore = PersonalCalendarStore.shared
    @State private var personalStore = PersonalEventsStore.shared
    @State private var availabilityStore = AvailabilityStore.shared
    @Environment(\.scenePhase) private var scenePhase

    /// Groups with a saved Firestore ID. Locally created groups have an empty
    /// documentID until the create flow lands them in Firestore.
    private var groupIDs: [String] {
        GroupStore.shared.groups.map(\.documentID).filter { !$0.isEmpty }
    }

    private var currentUID: String? {
        guard FirebaseApp.app() != nil else { return nil }
        return Auth.auth().currentUser?.uid
    }

    init() {
        // Previews build ContentView directly and never run HangApp's init,
        // so apply the UIKit (navigation/tab bar) rounded fonts here too.
        SwiftChallenge2App.configureRoundedSystemFonts()
    }

    var body: some View {
        TabView {
            Tab("We", systemImage: "person.and.person.fill") {
                WeView()
            }
            Tab("Me", systemImage: "calendar") {
                MeView()
            }
        }
        .tint(Color("AccentColor"))
        .fontDesign(.rounded)
        .onAppear {
            saveManager.loadProfile()
            // Keep the personal calendar in sync with the signed-in account.
            PersonalEventsStore.shared.startListening()
            // Keep the list of groups the user belongs to in sync.
            GroupStore.shared.startListening()
        }
        .onChange(of: groupIDs, initial: true) { _, ids in
            // Watch the busy times other members publish for each group, and
            // publish our own to any newly joined group.
            availabilityStore.sync(groupIDs: ids)
            Task { await publishAvailability(to: ids) }
        }
        .onChange(of: calendarStore.events) { _, _ in
            Task { await publishAvailability(to: groupIDs, force: true) }
        }
        .onChange(of: personalStore.events) { _, _ in
            Task { await publishAvailability(to: groupIDs, force: true) }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            calendarStore.loadEventsIfAuthorized()
            Task { await publishAvailability(to: groupIDs, force: true) }
        }
        .onDisappear {
            availabilityStore.stopAll()
        }
        .onChange(of: saveManager.hasLoadedProfile) { _, loaded in
            guard loaded else { return }
            // Only accounts without a username get the prompt.
            let trimmedName =
                saveManager.profile?.username.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ) ?? ""
            showNamePrompt = trimmedName.isEmpty
        }
        .alert("Enter your username", isPresented: $showNamePrompt) {
            TextField("Your name", text: $userName)
            Button("Done", role: .confirm) {
                let trimmedName = userName.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard !trimmedName.isEmpty else { return }
                saveManager.saveUsername(trimmedName)
                userName = ""
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Publishes anonymous busy intervals to every group this account belongs
    /// to. Event titles never enter this path.
    private func publishAvailability(to ids: [String], force: Bool = false) async {
        guard let uid = currentUID else { return }
        await AvailabilityPublisher.shared.refresh(
            groups: ids,
            uid: uid,
            force: force
        )
    }
}

#Preview {
    ContentView()
}
