//
//  AppleSignInController.swift
//  Hang
//
//  Runs the Sign in with Apple request and exchanges the Apple identity token for a
//  Firebase session.
//
//  Why this exists instead of `firebaseSignInWithApple.authenticate()`:
//  - The package starts `ASAuthorizationController.performRequests()` immediately, even
//    if something else (like the old "Are you sure?" confirm alert) is still being
//    presented. When AuthenticationServices can't present its sheet, it aborts with
//    `ASAuthorizationError.unknown` (code 1000) and the user just sees "An unknown error
//    occurred." We wait for the current presentation to finish before asking.
//  - The package's presentation anchor is `UIApplication.shared.connectedScenes.first`,
//    which is not guaranteed to be the active scene, and it force-unwraps the result.
//    We anchor to the key window of the active scene instead.
//  - We keep the controller alive until the request finishes and surface the real error
//    code instead of a generic message.
//

import AuthenticationServices
import CryptoKit
import FirebaseAuth
import SwiftUI

@MainActor
@Observable
final class AppleSignInController: NSObject {
    /// True while the Apple sheet or the Firebase exchange is in flight.
    private(set) var isAuthenticating = false
    /// Set when the request fails so the view can show an alert. Cancellation is silent.
    var errorMessage: String?

    private var authorizationController: ASAuthorizationController?
    private var currentNonce: String?
    private var hostWindow: UIWindow?

    func signIn() {
        guard !isAuthenticating else { return }

        isAuthenticating = true
        errorMessage = nil

        let nonce = Self.randomNonceString()
        currentNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        authorizationController = controller

        // Wait for any presentation that is still dismissing (for example an alert)
        // before asking AuthenticationServices to take over the screen.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard self.authorizationController === controller else { return }
            controller.performRequests()
        }
    }

    // MARK: - Private helpers

    private func finish(with error: Error) {
        isAuthenticating = false
        authorizationController = nil
        currentNonce = nil

        print("[AppleSignIn] failed: \(error)")

        if let authorizationError = error as? ASAuthorizationError {
            switch authorizationError.code {
            case .canceled:
                // The user backed out; don't nag them with an alert.
                return
            case .unknown:
                errorMessage = """
                Apple couldn't complete the sign-in (error 1000). Make sure this device \
                is signed in to an Apple Account and that “Sign in with Apple” is enabled \
                for \(Bundle.main.bundleIdentifier ?? "this app") in the Apple Developer portal.
                """
            case .invalidResponse:
                errorMessage = "Apple returned an invalid response. Please try again."
            case .notHandled:
                errorMessage = "The sign-in request wasn't handled. Please try again."
            case .failed:
                errorMessage = "Apple failed to authorize the sign-in. Please try again."
            case .notInteractive:
                errorMessage = "Sign in with Apple needs an interactive window to continue."
            default:
                errorMessage = authorizationError.localizedDescription
            }
            return
        }

        errorMessage = error.localizedDescription
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleSignInController: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            finish(with: AppleSignInError.unexpectedCredential)
            return
        }
        guard let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            finish(with: AppleSignInError.missingIdentityToken)
            return
        }
        guard let nonce = currentNonce else {
            finish(with: AppleSignInError.missingNonce)
            return
        }

        Task { @MainActor in
            do {
                let firebaseCredential = OAuthProvider.appleCredential(
                    withIDToken: idToken,
                    rawNonce: nonce,
                    fullName: credential.fullName
                )
                try await Auth.auth().signIn(with: firebaseCredential)
                // FirebaseSignInWithApple's auth listener takes it from here: it makes
                // sure users/<uid> exists and switches the app to .authenticated.
                isAuthenticating = false
                authorizationController = nil
                currentNonce = nil
            } catch {
                finish(with: error)
            }
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        finish(with: error)
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AppleSignInController: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        if let hostWindow, hostWindow.windowScene != nil {
            return hostWindow
        }

        let windowScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        guard let activeScene = windowScenes.first(where: {
            $0.activationState == .foregroundActive
        }) ?? windowScenes.first(where: {
            $0.activationState == .foregroundInactive
        }) ?? windowScenes.first else {
            // AuthenticationServices only asks for an anchor while it is
            // presenting, so an active scene always exists here.
            preconditionFailure("Apple sign-in requires an active window scene.")
        }

        let window = activeScene.windows.first { $0.isKeyWindow }
            ?? activeScene.windows.first
            ?? UIWindow(windowScene: activeScene)

        hostWindow = window
        return window
    }
}

// MARK: - Errors

private enum AppleSignInError: LocalizedError {
    case unexpectedCredential
    case missingIdentityToken
    case missingNonce

    var errorDescription: String? {
        switch self {
        case .unexpectedCredential:
            return "Apple returned an unexpected credential. Please try again."
        case .missingIdentityToken:
            return "Apple didn't return an identity token. Please try again."
        case .missingNonce:
            return "The sign-in request expired. Please try again."
        }
    }
}

// MARK: - Nonce

private extension AppleSignInController {
    static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            // Never crash the sign-in flow. A UUID v4 still supplies enough
            // entropy for this one-shot nonce and uses only allowed characters.
            return UUID().uuidString
        }

        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    static func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
