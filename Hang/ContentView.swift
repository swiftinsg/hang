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
    @State private var accountDeletion = AccountDeletionController.shared
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

    /// Every event the user can see in Hang, normalised for reminder scheduling.
    private var reminderEvents: [ReminderEvent] {
        var result: [ReminderEvent] = []

        for event in personalStore.events {
            result.append(ReminderEvent(
                id: event.id.uuidString,
                source: .personal,
                title: event.name,
                startDate: event.startDate,
                location: event.location
            ))
        }

        for group in GroupStore.shared.groups where !group.documentID.isEmpty {
            for event in group.events {
                result.append(ReminderEvent(
                    id: "\(group.documentID)-\(event.id.uuidString)",
                    source: .group,
                    title: event.name,
                    startDate: event.startDate,
                    location: event.location
                ))
            }
        }

        for event in calendarStore.events {
            result.append(ReminderEvent(
                id: event.id,
                source: .device,
                title: event.title,
                startDate: event.startDate,
                location: ""
            ))
        }

        return result
    }

    init() {
        // Previews build ContentView directly and never run HangApp's init,
        // so apply the UIKit (navigation/tab bar) rounded fonts here too.
        SwiftChallenge2App.configureRoundedSystemFonts()
    }
    
    var body: some View {
        TabView {
            Tab {
                WeView()
            } label: {
                Label {
                    Text("We")
                } icon: {
                    Image("MonoDoubleHang")
                }
            }
            Tab {
                MeView()
            } label: {
                Label {
                    Text("Me")
                } icon: {
                    Image("MonoSingleHang")
                }
            }
        }
        .disabled(accountDeletion.isDeleting)
        .tint(Color("AccentColor"))
        .fontDesign(.rounded)
        .overlay {
            if accountDeletion.isDeleting {
                ZStack {
                    Color(.systemBackground)
                        .opacity(0.85)
                        .ignoresSafeArea()
                    ProgressView("Deleting Account…")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            }
        }
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
            // Once membership is known, backfill the copied name/avatar into
            // those groups (also covers a profile change made before load).
            if !ids.isEmpty {
                Task { await GroupStore.shared.refreshMyProfile() }
            }
        }
        .onChange(of: calendarStore.events) { _, _ in
            Task { await publishAvailability(to: groupIDs, force: true) }
        }
        .onChange(of: personalStore.events) { _, _ in
            Task { await publishAvailability(to: groupIDs, force: true) }
        }
        // Rebuild local reminders whenever events, the preference or
        // notification permission change. Kept in a modifier to keep this
        // view's body type-checkable.
        .modifier(ReminderSyncModifier(
            events: reminderEvents,
            preference: saveManager.profile?.reminderPreference ?? .none,
            scenePhase: scenePhase,
            onSync: { Task { await syncReminders() } }
        ))
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            calendarStore.loadEventsIfAuthorized()
            Task { await publishAvailability(to: groupIDs, force: true) }
        }
        .onDisappear {
            availabilityStore.stopAll()
            Task { await ReminderScheduler.shared.cancelAll() }
        }
        .onChange(of: saveManager.hasLoadedProfile) { _, loaded in
            guard loaded else { return }
            // Only accounts without a username get the prompt.
            let trimmedName =
            saveManager.profile?.username.trimmingCharacters(
                in: .whitespacesAndNewlines
            ) ?? ""
            showNamePrompt = trimmedName.isEmpty
            if !trimmedName.isEmpty {
                Task { await GroupStore.shared.refreshMyProfile() }
            }
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
                Task { await GroupStore.shared.refreshMyProfile() }
            }
            .keyboardShortcut(.defaultAction)
            
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Schedules the user's chosen reminder for all their events on this device.
    private func syncReminders() async {
        guard currentUID != nil else {
            await ReminderScheduler.shared.cancelAll()
            return
        }

        await ReminderScheduler.shared.sync(
            events: reminderEvents,
            preference: saveManager.profile?.reminderPreference ?? .none
        )
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

/// Watches everything that can invalidate scheduled reminders and asks the
/// parent to rebuild them. Sync replaces all Hang requests, so event edits and
/// deletions can't leave stale notifications behind.
private struct ReminderSyncModifier: ViewModifier {
    let events: [ReminderEvent]
    let preference: ReminderPreference
    let scenePhase: ScenePhase
    let onSync: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: events, initial: true) { _, _ in onSync() }
            .onChange(of: preference) { _, _ in onSync() }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .hangRemindersShouldResync
                )
            ) { _ in onSync() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                onSync()
            }
    }
}

#Preview {
    ContentView()
}
