import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation
import SwiftUI

public struct Colors {
    let green = Color(red: 0.4, green: 0.7, blue: 0.6)
    let green1 = Color(red: 0.6, green: 0.9, blue: 0.8)
    let green2 = Color(red: 0.7, green: 1, blue: 0.9)
    let dgreen = Color(red: 0.2, green: 0.5, blue: 0.4)
    let dgreen1 = Color(red: 0.1, green: 0.4, blue: 0.3)
    let dgreen2 = Color(red: 0, green: 0.3, blue: 0.2)
    let brown = Color.brown
    let txt1 = Color(red: 0.1, green: 0.25, blue: 0.2)
    let txt2 = Color(red: 0.05, green: 0.2, blue: 0.15)
    let obj = Color(red: 0.25, green: 0.15, blue: 0)
}

struct Sizing: DynamicProperty {
    @ScaledMetric var x1: CGFloat = 5
    @ScaledMetric var x2: CGFloat = 10
    @ScaledMetric var x3: CGFloat = 15
    @ScaledMetric var x4: CGFloat = 20
    @ScaledMetric var x5: CGFloat = 25
    @ScaledMetric var x6: CGFloat = 30
    @ScaledMetric var x7: CGFloat = 35
    @ScaledMetric var x8: CGFloat = 40
    @ScaledMetric var x9: CGFloat = 45
    @ScaledMetric var x10: CGFloat = 50
}

// MARK: - Models
//
// These three types are the whole app's data model. They are shaped for
// Firestore (`@DocumentID`, `Codable`) because Checkpoint D/E start writing
// them straight into `Groups/…` and its subcollections.

/// A member of a group.
///
/// Identity is the Firebase uid, not a fresh `UUID()`. The old `UUID()`-per-
/// launch id meant the same person was a different person on every run, which
/// would break `ForEach` diffing and every Firestore comparison.
public struct Person: Identifiable, Hashable, Codable {
    public var uid: String
    public var name: String
    public var status: String
    /// Mirrors `sharingEnabled` on the member document. It controls whether this
    /// person is publishing busy times to the group; it is not calendar data.
    public var sharingEnabled: Bool

    public var id: String { uid }

    /// True only for the signed-in account. Previews run without a configured
    /// Firebase app, so this deliberately returns false instead of trapping.
    public var isCurrentUser: Bool {
        guard FirebaseApp.app() != nil else { return false }
        return uid == Auth.auth().currentUser?.uid
    }

    /// Stable per-member colour, derived from the name so it survives a
    /// relaunch and does not need to be stored.
    public var tint: Color {
        let palette: [Color] = [
            .teal, .indigo, .orange, .pink, .purple, .blue, .mint,
        ]
        return palette[scheduleSeed % palette.count]
    }

    /// Stable offset so each member gets a different (but repeatable) schedule
    /// when sample data is used.
    public var scheduleSeed: Int {
        name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
    }

    public init(uid: String, name: String, status: String = "", sharingEnabled: Bool = true) {
        self.uid = uid
        self.name = name
        self.status = status
        self.sharingEnabled = sharingEnabled
    }
}

/// An event planned by a group.
///
/// Was `time: Double` with an implicit one-hour duration; now carries an
/// explicit end so the timeline and the busiest-day maths agree.
public struct GroupEvents: Identifiable, Codable {
    @DocumentID public var id: String?
    public var name: String
    public var desc: String
    public var startTime: Date
    public var endTime: Date
    public var createdBy: String

    public var interval: DateInterval {
        DateInterval(start: startTime, end: endTime)
    }

    public init(
        name: String,
        desc: String = "",
        startTime: Date,
        endTime: Date,
        createdBy: String = ""
    ) {
        self.name = name
        self.desc = desc
        self.startTime = startTime
        self.endTime = endTime
        self.createdBy = createdBy
    }
}

/// A group. Members and events live in subcollections, so this document stays
/// small no matter how many events a group collects.
public struct TestGroup: Identifiable, Codable {
    @DocumentID public var id: String?
    public var code: String
    public var name: String
    public var desc: String
    public var ownerUid: String
    public var memberUids: [String]
    public var createdAt: Date?

    public init(
        code: String,
        name: String,
        desc: String = "Add description here...",
        ownerUid: String = "",
        memberUids: [String] = [],
        createdAt: Date? = nil
    ) {
        self.code = code
        self.name = name
        self.desc = desc
        self.ownerUid = ownerUid
        self.memberUids = memberUids
        self.createdAt = createdAt
    }
}

public enum clickStyle {
    case None, Tint, Fade, Shrink1, Shrink2
}

public struct setStyle: ButtonStyle {
    public let styleName: clickStyle

    public func makeBody(configuration: Configuration) -> some View {
        switch styleName {
        case .None:
            configuration.label
        case .Tint:
            configuration.label
                .overlay {
                    Color.black
                        .opacity(configuration.isPressed ? 0.2 : 0)
                }
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        case .Fade:
            configuration.label
                .opacity(configuration.isPressed ? 0.75 : 1.0)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        case .Shrink1:
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        case .Shrink2:
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}
