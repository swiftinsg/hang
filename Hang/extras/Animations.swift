import Foundation
import SwiftUI



public struct Colors {
    let red = (col: Color(red: 1.0, green: 0.55, blue: 0.55), img: Image("FlatRedHang"))
    let yellow = (col: Color(red: 1.0, green: 0.85, blue: 0.55), img: Image("FlatYellowHang"))
    let green = (col: Color(red: 0.55, green: 1.0, blue: 0.55), img: Image("FlatYellowHang"))
    let cyan = (col: Color(red: 0.55, green: 1.0, blue: 0.85), img: Image("FlatYellowHang"))
    let blue = (col: Color(red: 0.55, green: 0.55, blue: 1.0), img: Image("FlatYellowHang"))
    let pink = (col: Color(red: 1.0, green: 0.55, blue: 0.85), img: Image("FlatYellowHang"))
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

public struct TestGroup: Hashable, Identifiable {
    public let id: UUID
    public let code: String
    var name: String
    var desc: String
    var members: [Person]
    var events: [GroupEvents]
    /// Colour shared by this group's events. Randomised when the group is
    /// created and editable from the group's More Info screen.
    var eventColor: PersonalEventOutlineColor = .blue
    /// Firestore document ID (`groups/<documentID>`). Empty for locally
    /// created groups that haven't been saved to Firestore yet.
    let documentID: String

    public init(
        id: UUID = UUID(),
        code: String,
        name: String,
        desc: String = "Add description here...",
        members: [Person] = [],
        events: [GroupEvents] = [],
        eventColor: PersonalEventOutlineColor = .blue,
        documentID: String = ""
    ) {
        self.id = id
        self.code = code
        self.name = name
        self.desc = desc
        self.members = members
        self.events = events
        self.eventColor = eventColor
        self.documentID = documentID
    }
}

public struct GroupEvents: Hashable, Identifiable {
    public let id: UUID
    var name: String
    var desc: String = "Add description here..."
    /// Where the hangout happens. Empty when no location is provided.
    var location: String = ""
    var time: Double
    /// Optional end time. Events created before this was added only store a start.
    var endTime: Double? = nil
    /// Display-only colour inherited from the group this event came from.
    /// Personal events leave it nil and use the device-local colour choice.
    /// It is never written to Firestore: `GroupEventData` owns the wire format.
    var groupColor: Color? = nil

    /// `id` can be supplied so events loaded from Firestore keep the same
    /// identity across refreshes (the document ID is stored as a UUID).
    public init(
        id: UUID = UUID(),
        name: String,
        desc: String = "Add description here...",
        location: String = "",
        time: Double,
        endTime: Double? = nil,
        groupColor: Color? = nil
    ) {
        self.id = id
        self.name = name
        self.desc = desc
        self.location = location
        self.time = time
        self.endTime = endTime
        self.groupColor = groupColor
    }
}

extension GroupEvents {
    /// The moment the event starts.
    var startDate: Date {
        Date(timeIntervalSince1970: time)
    }

    /// The moment the event ends. Older events without an end time last one hour.
    var endDate: Date {
        if let endTime {
            return Date(timeIntervalSince1970: endTime)
        }
        return startDate.addingTimeInterval(60 * 60)
    }
}

public struct Person: Hashable, Identifiable {
    /// Firebase uid. Stable across launches and devices, so it can be used as
    /// the identity for published availability documents.
    public var uid: String = ""
    /// Identity follows the account, not a fresh UUID per instance.
    public var id: String { uid }
    var name: String
    var status: String = "Add description here..."
    /// The member's chosen avatar. `.initial` falls back to the first letter of
    /// `avatarName` (or `name`) instead of showing an image.
    var profilePicture: ProfilePicture = .initial
    /// Username used for the fallback initial when the visible name is generic,
    /// e.g. "You" for the signed-in user in a shared calendar.
    var avatarName: String? = nil
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

extension Color {
    func adjusted(saturation: Double = 1.0, brightness: Double = 0.0) -> Color {
        #if os(iOS)
        Color(uiColor: UIColor { traits in
            let resolved = UIColor(self).resolvedColor(with: traits)
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            
            guard resolved.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else {
                return resolved
            }
            
            let newS = min(max(s * saturation, 0), 1)
            let newB = min(max(b + brightness, 0), 1)
            return UIColor(hue: h, saturation: newS, brightness: newB, alpha: a)
        })
        #else
        self
        #endif
    }
}
