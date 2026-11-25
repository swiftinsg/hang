//
//  ProfileView.swift
//  Hang
//
//  Created by Lim Shi Hui Serene on 13/11/26.
//

import FirebaseSignInWithApple
import SwiftUI

struct ProfileView: View {
    @State private var profile = false
    @Environment(\.firebaseSignInWithApple) private var firebaseSignInWithApple
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var saveManager = SaveManager()
    @State private var accountDeletion = AccountDeletionController.shared
    @State private var showingAlert = false
    @State private var showingDeleteAlert = false
    @State private var permission: ReminderPermission = .notDetermined

    private var selectedReminder: ReminderPreference {
        saveManager.profile?.reminderPreference ?? .none
    }

    private var selectedPicture: ProfilePicture {
        saveManager.profile?.profilePicture ?? .initial
    }

    private var username: String {
        saveManager.profile?.username ?? ""
    }

    /// Same deterministic colour the group views use for this member's initial
    /// avatar, so the preview here matches what everyone else sees.
    private var avatarTint: Color {
        Person.currentUser.tint
    }

    /// The five premade pictures. "original" is shown as its own button above
    /// the loop so it always appears first.
    private var selectablePictures: [ProfilePicture] {
        ProfilePicture.allCases.filter { $0 != .initial }
    }

    var body: some View {
        VStack {
            Menu {
                Button {
                    updateProfilePicture(.initial)
                } label: {
                    Text("original")
                }
                Divider()
                ForEach(selectablePictures) { picture in
                    Button {
                        updateProfilePicture(picture)
                    } label: {
                        VStack(spacing: 6) {
                            ProfileAvatarView(
                                profilePicture: picture,
                                name: username,
                                size: 48,
                                tint: avatarTint
                            )
                            Text(picture.title)
                                .font(.caption2)
                                .lineLimit(1)
                                .foregroundStyle(
                                    picture == selectedPicture
                                        ? .primary : .secondary
                                )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            picture == selectedPicture
                                ? Color.accentColor.opacity(0.12)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(picture.title)
                    .accessibilityAddTraits(
                        picture == selectedPicture ? [.isSelected] : []
                    )
                }

            } label: {
                ProfileAvatarView(
                    profilePicture: selectedPicture,
                    name: username,
                    size: 100,
                    tint: avatarTint
                )
            }
            .padding(2)
            Form {
                Section {
                    HStack {
                        Text("Username")
                        Spacer()
                        Text(saveManager.profile?.username ?? "Loading…")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Reminders") {
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

                    Text(
                        "Hang will send a notification this long before every group hangout."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    if selectedReminder != .none && permission != .granted {
                        if permission == .denied {
                            Text(
                                "Notifications are turned off in Settings. Enable them to get reminders."
                            )
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
                    Button(
                        "Sign Out",
                        systemImage: "rectangle.portrait.and.arrow.right",
                        role: .destructive
                    ) {
                        showingAlert = true
                    }
                    .foregroundStyle(.red)
                    .disabled(accountDeletion.isDeleting)

                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        HStack {
                            Label("Delete Account", systemImage: "trash")
                            if accountDeletion.isDeleting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .bold()
                    .foregroundStyle(.red)
                    .disabled(accountDeletion.isDeleting)
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
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
        .alert("Delete Account?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                Task { await accountDeletion.deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This permanently deletes your profile, personal Hang events and shared availability, and removes you from all groups. Shared group events are not deleted. You'll be asked to confirm with Sign in with Apple. This can't be undone."
            )
        }
        .alert(
            "Couldn't Delete Account",
            isPresented: Binding(
                get: { accountDeletion.errorMessage != nil },
                set: { if !$0 { accountDeletion.errorMessage = nil } }
            )
        ) {
            Button("OK") { accountDeletion.errorMessage = nil }
        } message: {
            Text(accountDeletion.errorMessage ?? "Please try again.")
        }
    }

    private func updateProfilePicture(_ picture: ProfilePicture) {
        saveManager.saveProfilePicture(picture)
        // Groups keep their own copy of the avatar so every member can see it
        // without reading another account's private profile document.
        Task { await GroupStore.shared.refreshMyProfile(picture: picture) }
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
