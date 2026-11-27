//
//  ProfilePicture.swift
//  Hang
//
//  The avatar choices a member can pick on the Profile screen. The raw values
//  for the premade pictures match the asset names in Assets.xcassets/profilePictures,
//  so the same string can be stored in Firestore and used to load the image.
//

import SwiftUI

enum ProfilePicture: String, Codable, CaseIterable, Identifiable, Hashable {
    /// Show the first letter of the member's username instead of an image.
    case initial = "initial"
    case happy = "Happy (1)"
    case calendar = "calendar"
    case derpyAlien = "derpy alien"
    case hangingHang = "hanginghang"
    case sneepy = "sneepy"
    case confused = "confused"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .initial: return "original"
        case .happy: return "Happy"
        case .calendar: return "Calendar"
        case .derpyAlien: return "Derpy alien"
        case .hangingHang: return "Hanging hang"
        case .sneepy: return "Sneepy"
        case .confused: return "Confused"
        }
    }

    /// `nil` for the initial-only option; otherwise the asset name to load.
    var assetName: String? {
        self == .initial ? nil : rawValue
    }
}

/// One member avatar, used on the Profile screen and in shared calendars.
/// Premade pictures fill a circle; the initial option uses the member's name
/// (or their explicit username when the display name is just "You").
struct ProfileAvatarView: View {
    let profilePicture: ProfilePicture
    var name: String = ""
    var size: CGFloat = 40
    var tint: Color?

    init(
        profilePicture: ProfilePicture,
        name: String = "",
        size: CGFloat = 40,
        tint: Color? = nil
    ) {
        self.profilePicture = profilePicture
        self.name = name
        self.size = size
        self.tint = tint
    }

    init(person: Person, size: CGFloat = 40) {
        self.profilePicture = person.profilePicture
        self.name = person.avatarName ?? person.name
        self.size = size
        self.tint = person.tint
    }

    var body: some View {
        Group {
            if let assetName = profilePicture.assetName {
                Image(assetName)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(initial)
                    .font(.system(size: max(size * 0.38, 9), weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background((tint ?? Color.accentColor), in: Circle())
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        }
    }

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }
}
