import SwiftUI

struct CreateGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(GroupStore.self) private var groupStore

    @State private var groupName = ""
    @State private var createdCode: String?
    @State private var errorMessage: String?
    @State private var isCreating = false

    private var trimmedName: String {
        groupName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                TextField("Group name", text: $groupName)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(.capsule)
                    .disabled(createdCode != nil)

                VStack {
                    Text(
                        createdCode == nil
                            ? "Your invite code appears once the group is created."
                            : "Invite friends with this code"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                    HStack(spacing: 4) {
                        ForEach(0..<InviteCode.length, id: \.self) { index in
                            otpDigitBox(at: index)
                        }
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle(createdCode == nil ? "Create Group" : "Group Created")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(createdCode == nil ? "Cancel" : "Close") {
                        dismiss()
                    }
                    .disabled(isCreating)
                }

                ToolbarItem(placement: .confirmationAction) {
                    if createdCode != nil {
                        Button("Done") {
                            dismiss()
                        }
                    } else {
                        Button("Create", systemImage: "checkmark") {
                            Task { await create() }
                        }
                        .disabled(trimmedName.isEmpty || isCreating)
                    }
                }
            }
            .alert(
                "Couldn't create group",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func create() async {
        guard !isCreating, !trimmedName.isEmpty else { return }

        isCreating = true
        defer { isCreating = false }

        do {
            let created = try await groupStore.createGroup(name: trimmedName)
            // Show the code the store actually reserved; a collision retry can
            // pick a different one than any code previewed in the UI.
            createdCode = created.code
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private func otpDigitBox(at index: Int) -> some View {
        let character = characterAt(index)

        Text(character)
            .font(.title2.bold())
            .frame(width: 30, height: 40)
            .background(Color(.systemGray6))
            .cornerRadius(8)
    }

    private func characterAt(_ index: Int) -> String {
        guard let createdCode, index < createdCode.count else { return "" }
        let stringIndex = createdCode.index(createdCode.startIndex, offsetBy: index)
        return String(createdCode[stringIndex])
    }
}

#if DEBUG
#Preview {
    CreateGroupView()
        .environment(GroupStore.preview(with: PreviewData.members))
}
#endif
