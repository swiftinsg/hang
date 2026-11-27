import SwiftUI

struct CreateGroupView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var groupName = ""
    @State private var groupDesc = ""
    @State private var code = ""
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage: String?

    private var store: GroupStore { GroupStore.shared }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                TextField("Group name", text: $groupName)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(.capsule)

                VStack {
                    Text("Invite friends with code")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        ForEach(0..<6, id: \.self) { index in
                            otpDigitBox(at: index)
                        }
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Create Group")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm", systemImage: "checkmark") {
                        createGroup()
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .alert("Couldn't create group", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .task {
            code = store.suggestedInviteCode()
        }
    }

    private var canSave: Bool {
        !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && code.count == 6
            && !isSaving
    }

    private func createGroup() {
        isSaving = true
        Task {
            do {
                try await store.createGroup(
                    name: groupName.trimmingCharacters(in: .whitespacesAndNewlines),
                    desc: groupDesc.trimmingCharacters(in: .whitespacesAndNewlines),
                    inviteCode: code
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                isSaving = false
            }
        }
    }

    @ViewBuilder
    private func otpDigitBox(at index: Int) -> some View {
        let character = characterAt(index)

        Text(character)
            .font(.title2.bold())
            .frame(width: 30, height: 40)
            .background(Color(.systemBackground))
            .cornerRadius(8)
    }

    private func characterAt(_ index: Int) -> String {
        guard index < code.count else { return "" }
        let stringIndex = code.index(code.startIndex, offsetBy: index)
        return String(code[stringIndex])
    }
}

#Preview {
    CreateGroupView()
}
