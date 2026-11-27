import FirebaseAuth
import FirebaseCore
import SwiftUI

struct ContentView: View {
    let notify = NotificationHandler()
    @ObservedObject private var saveManager = SaveManager.shared
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
        mainTabs
            .disabled(accountDeletion.isDeleting)
            .tint(Color("AccentColor"))
            .fontDesign(.rounded)
            .overlay {
                if accountDeletion.isDeleting {
                    deletingOverlay
                }
            }
            .modifier(ContentSyncModifier(
                groupIDs: groupIDs,
                calendarEvents: calendarStore.events,
                personalEvents: personalStore.events,
                scenePhase: scenePhase,
                hasLoadedProfile: saveManager.hasLoadedProfile,
                onAppear: handleAppear,
                onDisappear: handleDisappear,
                onGroupIDsChange: handleGroupIDsChange,
                onEventsChange: { Task { await publishAvailability(to: groupIDs) } },
                onSceneBecameActive: handleSceneBecameActive,
                onProfileLoaded: handleProfileLoaded
            ))
            .modifier(ReminderSyncModifier(
                events: reminderEvents,
                preference: saveManager.profile?.reminderPreference ?? .none,
                scenePhase: scenePhase,
                onSync: { Task { await syncReminders() } }
            ))
            .alert("Enter your username", isPresented: $showNamePrompt) {
                TextField("Your name", text: $userName)
                Button("Done", action: saveUsername)
                    .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {}
            }
            .task{
                notify.askPermission()
            }
            
    }

    // MARK: - Subviews

    private var mainTabs: some View {
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
    }

    private var deletingOverlay: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .opacity(0.85)
                .ignoresSafeArea()
            ProgressView("Deleting Account…")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    // MARK: - Lifecycle & Sync Handlers

    private func handleAppear() {
        saveManager.loadProfile()
        PersonalEventsStore.shared.startListening()
        GroupStore.shared.startListening()
        GroupNotificationStore.shared.startListening()
    }

    private func handleDisappear() {
        availabilityStore.stopAll()
        // Sign-out removes ContentView. Clear every singleton store so the next
        // account can't see stale groups, private events, notices or reminders.
        PersonalEventsStore.shared.stopListening()
        GroupStore.shared.stopListening()
        GroupNotificationStore.shared.stopListening()
        saveManager.stopListening()
        Task { await ReminderScheduler.shared.cancelAll() }
    }

    private func handleGroupIDsChange(_ ids: [String]) {
        availabilityStore.sync(groupIDs: ids)
        Task { await publishAvailability(to: ids) }
    }

    private func handleSceneBecameActive() {
        calendarStore.loadEventsIfAuthorized()
        Task { await publishAvailability(to: groupIDs) }
    }

    private func handleProfileLoaded() {
        let trimmedName = saveManager.profile?.username.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? ""
        showNamePrompt = trimmedName.isEmpty
    }

    private func saveUsername() {
        let trimmedName = String(
            userName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100)
        )
        guard !trimmedName.isEmpty else { return }
        saveManager.saveUsername(trimmedName)
        userName = ""
        // Group documents carry a copy of the display name; keep it in step.
        Task { await GroupStore.shared.refreshMyProfile() }
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

// MARK: - Extracted Sync Modifiers

private struct ContentSyncModifier<CalendarEvent: Equatable, PersonalEvent: Equatable>: ViewModifier {
    let groupIDs: [String]
    let calendarEvents: [CalendarEvent]
    let personalEvents: [PersonalEvent]
    let scenePhase: ScenePhase
    let hasLoadedProfile: Bool

    let onAppear: () -> Void
    let onDisappear: () -> Void
    let onGroupIDsChange: ([String]) -> Void
    let onEventsChange: () -> Void
    let onSceneBecameActive: () -> Void
    let onProfileLoaded: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear(perform: onAppear)
            .onDisappear(perform: onDisappear)
            .onChange(of: groupIDs, initial: true) { _, ids in
                onGroupIDsChange(ids)
            }
            .onChange(of: calendarEvents) { _, _ in
                onEventsChange()
            }
            .onChange(of: personalEvents) { _, _ in
                onEventsChange()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    onSceneBecameActive()
                }
            }
            .onChange(of: hasLoadedProfile) { _, loaded in
                if loaded {
                    onProfileLoaded()
                }
            }
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
