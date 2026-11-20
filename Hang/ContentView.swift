import SwiftUI

struct ContentView: View {
    @StateObject private var saveManager = SaveManager()
    @State private var userName = ""
    @State private var showNamePrompt = false

    var body: some View {
        TabView {
            Tab("We", systemImage: "person.and.person.fill") {
                WeView()
            }
            Tab("Me", systemImage: "calendar") {
                MeView()
            }
        }
        .tint(Color.accentColor)
        .onAppear {
            saveManager.loadProfile()
            // Keep the personal calendar in sync with the signed-in account.
            PersonalEventsStore.shared.startListening()
            // Keep the list of groups the user belongs to in sync.
            GroupStore.shared.startListening()
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
}

#Preview {
    ContentView()
}
