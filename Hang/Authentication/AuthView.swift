import SwiftUI

struct AuthView: View {
    @State private var appleSignIn = AppleSignInController()

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 32) {
                VStack(spacing: 8) {
                    Text("Welcome to \(Text("Hang!").foregroundStyle(.accent).fontWeight(.black).fontDesign(.rounded))")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("Sign in to join your friends, share your personal calendar and plan events.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                Button {
                    appleSignIn.signIn()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "apple.logo")
                            .font(.title3)
                        Text("Sign in with Apple")
                            .font(.headline)
                    }
                    .foregroundStyle(Color(uiColor: .systemBackground))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(appleSignIn.isAuthenticating)
                
                //            if appleSignIn.isAuthenticating {
                //                ProgressView()
                //            }
            }
            .padding(32)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .gray.opacity(0.25), radius: 16)
            .padding(16)
            .alert(
                "Couldn't sign in",
                isPresented: Binding(
                    get: { appleSignIn.errorMessage != nil },
                    set: { if !$0 { appleSignIn.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    appleSignIn.errorMessage = nil
                }
            } message: {
                Text(appleSignIn.errorMessage ?? "")
            }
        }
    }
}

#Preview {
    AuthView()
}
