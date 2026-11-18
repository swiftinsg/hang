//
//  InviteCode.swift
//  Hang
//
//  Six-character group codes, reserved in `GroupCodes/{code}` so two groups
//  can never claim the same one. The reservation is what makes "join by code"
//  unambiguous; the random generator alone cannot guarantee it.
//

import FirebaseFirestore
import Foundation

enum JoinError: LocalizedError, Equatable {
    case codeNotFound
    case codeTaken
    case alreadyMember
    case notOwner
    case notSignedIn
    case groupMissing

    var errorDescription: String? {
        switch self {
        case .codeNotFound:
            "No group uses that code. Double-check it."
        case .codeTaken:
            "That code is already in use. Try creating the group again."
        case .alreadyMember:
            "You're already in this group."
        case .notOwner:
            "Only the group owner can do that."
        case .notSignedIn:
            "Sign in to use groups."
        case .groupMissing:
            "That group no longer exists."
        }
    }
}

enum InviteCode {
    /// No vowels, so a code cannot spell a word, and no I/O, which are the
    /// letters most easily confused with 1 and 0. Digits are allowed.
    private static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ1234567890")

    static let length = 6

    static func generate(length: Int = InviteCode.length) -> String {
        String((0..<length).compactMap { _ in alphabet.randomElement() })
    }

    /// Uppercases, strips anything that isn't a letter or digit, and trims to
    /// six characters. Shared by the join field and the creator so both sides
    /// agree on what a code looks like.
    static func normalize(_ raw: String) -> String {
        String(
            raw.uppercased()
                .filter { $0.isLetter || $0.isNumber }
                .prefix(length)
        )
    }

    // MARK: - Reserving

    /// Reserves `code` for `groupID` unless it is already taken.
    ///
    /// Uses a transaction because check-then-write across two requests would
    /// let two groups claim the same code. `createdBy` is stored so the server
    /// rules can let only that account release the code again.
    ///
    /// The transaction block is non-throwing (it reports failure through the
    /// error pointer), so a Swift `throw` inside is caught and re-raised after
    /// the transaction fails. That keeps `JoinError.codeTaken` recognisable to
    /// `claimRandomCode`.
    static func claim(_ code: String, for groupID: String, uid: String) async throws {
        let db = Firestore.firestore()
        let reference = db.collection(Path.Firestore.groupCodes).document(code)
        var failure: Error?

        do {
            _ = try await db.runTransaction { transaction, errorPointer in
                do {
                    let snapshot = try transaction.getDocument(reference)
                    guard !snapshot.exists else { throw JoinError.codeTaken }

                    transaction.setData(
                        [
                            "groupID": groupID,
                            "createdBy": uid,
                            "createdAt": FieldValue.serverTimestamp(),
                        ],
                        forDocument: reference
                    )
                } catch {
                    failure = error
                    errorPointer?.pointee = error as NSError
                }
                return nil
            }
        } catch {
            throw failure ?? error
        }
    }

    /// Returns the group that owns a code, or throws when it is unused.
    static func resolve(_ code: String) async throws -> String {
        let snapshot = try await Firestore.firestore()
            .collection(Path.Firestore.groupCodes)
            .document(code)
            .getDocument()

        guard snapshot.exists, let groupID = snapshot.data()?["groupID"] as? String else {
            throw JoinError.codeNotFound
        }
        return groupID
    }

    static func release(_ code: String) async {
        try? await Firestore.firestore()
            .collection(Path.Firestore.groupCodes)
            .document(code)
            .delete()
    }

    /// Tries random codes until one is free. Three attempts is plenty with a
    /// 34-character alphabet at length 6; the failure mode is a thrown error,
    /// never a duplicate code.
    static func claimRandomCode(for groupID: String, uid: String) async throws -> String {
        for _ in 0..<3 {
            let candidate = generate()
            do {
                try await claim(candidate, for: groupID, uid: uid)
                return candidate
            } catch JoinError.codeTaken {
                continue
            }
        }
        throw JoinError.codeTaken
    }
}
