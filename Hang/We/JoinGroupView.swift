import SwiftUI

struct JoinGroupView: View {
    let codeLength = 6
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var isJoining = false
    @State private var showError = false
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    private var store: GroupStore { GroupStore.shared }
 
    var body: some View {
        NavigationStack {
            VStack {
                Text("Enter group code")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                ZStack {
                    HStack(spacing: 4) {
                        ForEach(0..<codeLength, id: \.self) { index in
                            otpDigitBox(at: index)
                        }
                    }

                    TextField("", text: $code)
                        .tint(.clear)
                        .textContentType(.oneTimeCode)  // Enables iOS SMS AutoFill
                        .focused($isFocused)
                        .accentColor(.clear)
                        .foregroundColor(.clear)
                        .background(Color.clear)
                        .onChange(of: code) { _, newValue in
                            code = String(newValue.prefix(codeLength)).uppercased()
                        }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    isFocused = true
                }
                .onAppear {
                    isFocused = true
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Join Group")
            .alert("Couldn't join group", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm", systemImage: "checkmark") {
                        joinGroup()
                    }
                    .disabled(code.count != codeLength || isJoining)
                }
            }
        }
    }

    private func joinGroup() {
        isJoining = true
        Task {
            do {
                try await store.joinGroup(
                    inviteCode: code.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                isJoining = false
            }
        }
    }

    @ViewBuilder
    private func otpDigitBox(at index: Int) -> some View {
        let character = characterAt(index)
        let isCurrentBox =
            isFocused
            && (index == code.count
                || (index == codeLength - 1 && code.count == codeLength))

        Text(character)
            .font(.title2.bold())
            .frame(width: 30, height: 40)
            .background(Color(.systemBackground))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isCurrentBox ? Color("AccentColor") : Color.clear,
                        lineWidth: 2
                    )
            )
    }

    private func characterAt(_ index: Int) -> String {
        guard index < code.count else { return "" }
        let stringIndex = code.index(code.startIndex, offsetBy: index)
        return String(code[stringIndex])
    }
}

#Preview {
    JoinGroupView()
}
