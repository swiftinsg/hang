//
//  AccountDeletionController.swift
//  Hang
//
//  Deletes the signed-in user's Hang data before deleting their Firebase Auth
//  account. Reauthentication happens first so cancelling the Apple prompt does
//  not delete any Firestore data.
//

import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseFirestore
import SwiftUI

@MainActor
@Observable
final class AccountDeletionController: NSObject {
    static let shared = AccountDeletionController()

    private(set) var isDeleting = false
    var errorMessage: String?

    private var db: Firestore { Firestore.firestore() }
    private var authorizationController: ASAuthorizationController?
    private var currentNonce: String?
    private var hostWindow: UIWindow?
    private var authorizationContinuation: CheckedContinuation<AppleAuthorization, Error>?

    /// Reauthenticates with Apple, removes this account's Firestore data,
    /// revokes its Apple token, and finally deletes the Firebase Auth user.
    func deleteAccount() async {
        guard !isDeleting else { return }
        guard let user = Auth.auth().currentUser else {
            errorMessage = AccountDeletionError.notSignedIn.errorDescription
            return
        }

        isDeleting = true
        errorMessage = nil
        AvailabilityPublisher.shared.pausePublishing()

        defer {
            isDeleting = false
            AvailabilityPublisher.shared.resumePublishing()
            authorizationController = nil
            currentNonce = nil
            hostWindow = nil
        }

        do {
            // Ask for Apple credentials before touching Firestore. Besides being
            // required for token revocation, this makes account deletion work
            // when Firebase demands a recent sign-in.
            let authorization = try await requestAppleAuthorization()
            guard let tokenData = authorization.credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                throw AccountDeletionError.missingIdentityToken
            }
            guard let codeData = authorization.credential.authorizationCode,
                  let authorizationCode = String(data: codeData, encoding: .utf8) else {
                throw AccountDeletionError.missingAuthorizationCode
            }

            let credential = OAuthProvider.credential(
                providerID: .apple,
                idToken: idToken,
                rawNonce: authorization.nonce
            )
            try await user.reauthenticate(with: credential)

            // Redeem the short-lived authorization code before starting a
            // potentially long Firestore cleanup. A revocation/configuration
            // failure therefore happens before any user data is deleted.
            try await Auth.auth().revokeToken(
                withAuthorizationCode: authorizationCode
            )

            // Let writes that started before the Apple prompt finish. New ones
            // are blocked by the deletion overlay, and availability publishing
            // is paused so cleanup cannot recreate a deleted document.
            await AvailabilityPublisher.shared.waitForPendingPublishes()
            try await db.waitForPendingWrites()
            try await deleteFirestoreData(uid: user.uid)

            try await user.delete()
            await ReminderScheduler.shared.cancelAll()
        } catch {
            // Cancelling Apple's confirmation is not an error and needs no alert.
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
            // Do NOT republish queued groups here: cleanup may already have
            // removed this user from them. `defer` resumes publishing, and the
            // next normal membership sync publishes only current groups.
        }
    }

    // MARK: - Firestore

    private func deleteFirestoreData(uid: String) async throws {
        let userDocument = db.collection(Path.Firestore.Users).document(uid)
        let groups = try await db.collection(Path.Firestore.Groups).getDocuments()

        // Group events belong to the group, not to this account, so leave them
        // for the other members. Check every group rather than only current
        // memberships: older versions could leave a name or availability behind
        // after someone left. Never read or delete any other member's busy times.
        for group in groups.documents {
            let data = group.data()
            let people = data["people"] as? [DocumentReference] ?? []
            let isMember = people.contains { $0.path == userDocument.path }
            let memberNames = data["memberNames"] as? [String: Any] ?? [:]
            let memberPictures = data["memberProfilePictures"] as? [String: Any] ?? [:]
            var updates: [String: Any] = [:]

            if isMember {
                updates["people"] = FieldValue.arrayRemove([userDocument])
            }
            if memberNames[uid] != nil {
                updates["memberNames.\(uid)"] = FieldValue.delete()
            }
            if memberPictures[uid] != nil {
                updates["memberProfilePictures.\(uid)"] = FieldValue.delete()
            }

            let batch = db.batch()
            if !updates.isEmpty {
                batch.updateData(updates, forDocument: group.reference)
            }
            batch.deleteDocument(
                group.reference
                    .collection(Path.Firestore.Availability)
                    .document(uid)
            )
            try await batch.commit()
        }

        // Deleting users/<uid> does not cascade to its subcollections. Delete
        // every personal event first, in batches below Firestore's 500-write cap.
        let calendarDocuments = try await userDocument
            .collection(Path.Firestore.Calendar)
            .getDocuments()
            .documents
        try await deleteInBatches(calendarDocuments)

        let notificationDocuments = try await userDocument
            .collection(Path.Firestore.Notifications)
            .getDocuments()
            .documents
        try await deleteInBatches(notificationDocuments)

        try await userDocument.delete()
    }

    /// Deletes subcollection documents in batches below Firestore's 500-write cap.
    private func deleteInBatches(_ documents: [QueryDocumentSnapshot]) async throws {
        for start in stride(from: 0, to: documents.count, by: 400) {
            let batch = db.batch()
            let end = min(start + 400, documents.count)
            for document in documents[start..<end] {
                batch.deleteDocument(document.reference)
            }
            try await batch.commit()
        }
    }

    // MARK: - Sign in with Apple

    private struct AppleAuthorization {
        let credential: ASAuthorizationAppleIDCredential
        let nonce: String
    }

    private func requestAppleAuthorization() async throws -> AppleAuthorization {
        let nonce = Self.randomNonceString()
        currentNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.nonce = Self.sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        authorizationController = controller

        // The confirmation alert may still be dismissing. Waiting avoids the
        // ASAuthorizationError.unknown failure caused by competing presentations.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, self.authorizationController === controller else { return }
            controller.performRequests()
        }

        return try await withCheckedThrowingContinuation { continuation in
            authorizationContinuation = continuation
        }
    }

    private func finishAppleAuthorization(with result: Result<AppleAuthorization, Error>) {
        guard let continuation = authorizationContinuation else { return }
        authorizationContinuation = nil
        authorizationController = nil
        currentNonce = nil
        hostWindow = nil
        continuation.resume(with: result)
    }

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(
            kSecRandomDefault,
            randomBytes.count,
            &randomBytes
        )
        guard errorCode == errSecSuccess else {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }

        let charset = Array(
            "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._"
        )
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AccountDeletionController: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            finishAppleAuthorization(with: .failure(AccountDeletionError.unexpectedCredential))
            return
        }
        guard let currentNonce else {
            finishAppleAuthorization(with: .failure(AccountDeletionError.missingNonce))
            return
        }

        finishAppleAuthorization(
            with: .success(AppleAuthorization(credential: credential, nonce: currentNonce))
        )
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        finishAppleAuthorization(with: .failure(error))
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AccountDeletionController: ASAuthorizationControllerPresentationContextProviding {
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
            preconditionFailure("Account deletion requires an active window scene.")
        }
        let window = activeScene.windows.first { $0.isKeyWindow }
            ?? activeScene.windows.first
            ?? UIWindow(windowScene: activeScene)

        hostWindow = window
        return window
    }
}

private enum AccountDeletionError: LocalizedError {
    case notSignedIn
    case unexpectedCredential
    case missingIdentityToken
    case missingAuthorizationCode
    case missingNonce

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "You must be signed in to delete your account."
        case .unexpectedCredential:
            return "Apple returned an unexpected credential. Please try again."
        case .missingIdentityToken:
            return "Apple didn't return an identity token. Please try again."
        case .missingAuthorizationCode:
            return "Apple didn't return an authorization code. Please try again."
        case .missingNonce:
            return "The Apple authorization expired. Please try again."
        }
    }
}
