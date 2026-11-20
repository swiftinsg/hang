//
//  ProfileView.swift
//  Hang
//
//  Created by Lim Shi Hui Serene on 13/11/26.
//

import SwiftUI
import FirebaseSignInWithApple

struct ProfileView: View {
    @Environment(\.firebaseSignInWithApple) private var firebaseSignInWithApple
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var saveManager = SaveManager()
    @State private var showingAlert = false
    @State private var permission: ReminderPermission = .notDetermined

    private var selectedReminder: ReminderPreference {
        saveManager.profile?.reminderPreference ?? .none
    }

    var body: some View {
        Form {
            Section("Account") {
                HStack {
                    Text("Username")
                    Spacer()
                    Text(saveManager.profile?.username ?? "Loading…")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Add Reminders") {
                Picker(
                    "All events",
                    selection: Binding(
                        get: { selectedReminder },
                        set: { updateReminderPreference($0) }
                    )
                ) {
                    ForEach(ReminderPreference.allCases) { preference in
                        Text(preference.title).tag(preference)
                    }
                }

                Text("Hang will notify you this long before every event — personal, group and device calendar events. Saved to your account, so you can change it any time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if selectedReminder != .none && permission != .granted {
                    if permission == .denied {
                        Text("Notifications are turned off in Settings. Enable them to get reminders.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Button("Enable Notifications") {
                            Task { await requestNotifications() }
                        }
                    }
                }
            }

            Section {
                Button {
                    showingAlert = true
                } label: {
                    Label(
                        "Sign Out",
                        systemImage: "rectangle.portrait.and.arrow.right"
                    )
                    .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Profile")
        .task {
            saveManager.loadProfile()
            await refreshPermission()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // The user may have changed notification permission in Settings.
            Task { await refreshPermission() }
        }
        .alert(isPresented: $showingAlert) {
            Alert(
                title: Text("Are you sure?"),
                message: Text("Are you sure you want to sign out?"),
                primaryButton: .default(Text("Confirm")) {
                    firebaseSignInWithApple.signOut()
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func updateReminderPreference(_ preference: ReminderPreference) {
        saveManager.saveReminderPreference(preference)
        guard preference != .none else { return }
        Task { await requestNotifications() }
    }

    private func requestNotifications() async {
        let granted = await ReminderScheduler.shared.requestPermission()
        if granted {
            permission = .granted
        } else {
            await refreshPermission()
        }
    }

    @discardableResult
    private func refreshPermission() async -> ReminderPermission {
        let status = await ReminderScheduler.shared.permissionStatus()
        permission = status
        return status
    }
}

#Preview {
    NavigationStack {
        ProfileView()
    }
}
