import SwiftUI

struct JoinGroupView: View {
    let codeLength = InviteCode.length

    @Environment(\.dismiss) private var dismiss
    @Environment(GroupStore.self) private var groupStore
    @FocusState private var isFocused: Bool

    @State private var code = ""
    @State private var shareAvailability = true
    @State private var errorMessage: String?
    @State private var isJoining = false

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
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .textContentType(.oneTimeCode)  // Enables iOS SMS AutoFill
                        .focused($isFocused)
                        .accentColor(.clear)
                        .foregroundColor(.clear)
                        .background(Color.clear)
                        .onChange(of: code) { _, newValue in
                            code = InviteCode.normalize(newValue)
                        }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    isFocused = true
                }
                .onAppear {
                    isFocused = true
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle(
                        "Share my busy times with this group",
                        isOn: $shareAvailability
                    )
                    .toggleStyle(.switch)

                    Text("Only start and end times are shared. Event titles never leave your phone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                Spacer()
            }
            .padding()
            .navigationTitle("Join Group")
            .alert(
                "Couldn't join group",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isJoining)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Join", systemImage: "checkmark") {
                        Task { await join() }
                    }
                    .disabled(code.count < codeLength || isJoining)
                }
            }
        }
    }

    private func join() async {
        guard code.count == codeLength, !isJoining else { return }

        isJoining = true
        defer { isJoining = false }

        do {
            try await groupStore.joinGroup(
                code: code,
                shareAvailability: shareAvailability
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
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
            .background(Color(.systemGray6))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isCurrentBox ? Color.accentColor : Color.clear,
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

#if DEBUG
#Preview {
    JoinGroupView()
        .environment(GroupStore.preview(with: PreviewData.members))
}
#endif
