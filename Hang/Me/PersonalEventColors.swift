//
//  PersonalEventColors.swift
//  Hang
//
//  Outline colours are a personal sorting aid in My Calendar. They are stored
//  in AppStorage on this device only: they never go to Firestore and are never
//  shared with group members. Group events instead use the colour saved on the
//  group document (`eventColor`), which every member sees.
//

import SwiftUI

/// Colours a user can assign to an event in the personal calendar, and that a
/// group can assign to all of its shared events. `.automatic` keeps the
/// source-based default without writing anything to storage.
public enum PersonalEventOutlineColor: String, CaseIterable, Identifiable {
    case automatic = "automatic"
    case orange, red, pink, purple, blue, cyan, green, yellow

    public var id: String { rawValue }

    var label: String {
        self == .automatic ? "Automatic" : rawValue.capitalized
    }

    /// Choices that can be stored as an actual colour (not "Automatic").
    static var selectable: [PersonalEventOutlineColor] {
        allCases.filter { $0 != .automatic }
    }

    /// A random palette colour for a newly created group.
    static var randomGroupColor: PersonalEventOutlineColor {
        selectable.randomElement() ?? .blue
    }

    /// Stable colour for older groups saved before `eventColor` existed.
    static func stableColor(forID id: String) -> PersonalEventOutlineColor {
        let hash = id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return selectable[hash % selectable.count]
    }

    var color: Color? {
        switch self {
        case .automatic:
            return nil
        case .orange:
            return .orange
        case .red:
            return .red
        case .pink:
            return .pink
        case .purple:
            return .purple
        case .blue:
            return .blue
        case .cyan:
            return .cyan
        case .green:
            return .green
        case .yellow:
            return .yellow
        }
    }

    /// The closest colour in the `HangColors` palette used by group events.
    /// `HangColors` has no orange or purple, so those two map to their nearest
    /// neighbour instead of growing the palette.
    var hangColor: HangColors? {
        switch self {
        case .automatic:
            return nil
        case .orange:
            return .yellow
        case .red:
            return .red
        case .pink:
            return .pink
        case .purple:
            return .blue
        case .blue:
            return .blue
        case .cyan:
            return .cyan
        case .green:
            return .green
        case .yellow:
            return .yellow
        }
    }
}

/// Stable keys so a colour keeps following an event across Firestore refreshes
/// and EventKit imports. Prefixes stop IDs from different sources colliding.
enum PersonalEventColorKey {
    static func imported(_ id: String) -> String { "imported:\(id)" }
    static func personal(_ id: UUID) -> String { "personal:\(id.uuidString)" }
    static func group(_ id: UUID) -> String { "group:\(id.uuidString)" }
}

/// Helpers around the local AppStorage dictionary (`event ID -> colour`).
/// The calendar view owns the `@AppStorage` binding and passes it down so any
/// colour change immediately redraws both the month grid and the day list.
enum PersonalEventColors {
    static let storageKey = "Hang.PersonalEventOutlineColors"
    /// AppStorage supports strings but not dictionaries on this SDK, so the
    /// event-ID -> colour map is persisted as JSON text.
    static let emptyJSON = "{}"

    static func encode(_ stored: [String: String]) -> String {
        guard
            let data = try? JSONEncoder().encode(stored),
            let json = String(data: data, encoding: .utf8)
        else {
            return emptyJSON
        }
        return json
    }

    static func decode(_ json: String) -> [String: String] {
        guard
            let data = json.data(using: .utf8),
            let stored = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return stored
    }

    /// Turns the stored JSON string into a normal dictionary binding so the
    /// views can read and update individual events without knowing the format.
    static func binding(_ json: Binding<String>) -> Binding<[String: String]> {
        Binding(
            get: { decode(json.wrappedValue) },
            set: { json.wrappedValue = encode($0) }
        )
    }

    static func choice(
        in stored: [String: String],
        for key: String
    ) -> PersonalEventOutlineColor {
        guard
            let rawValue = stored[key],
            let choice = PersonalEventOutlineColor(rawValue: rawValue)
        else {
            return .automatic
        }
        return choice
    }

    /// Effective outline colour, falling back to the source default used
    /// before the user chose one.
    static func color(
        in stored: [String: String],
        for key: String,
        default defaultColor: Color
    ) -> Color {
        choice(in: stored, for: key).color ?? defaultColor
    }

    static func setChoice(
        _ choice: PersonalEventOutlineColor,
        in stored: inout [String: String],
        for key: String
    ) {
        if choice == .automatic {
            stored.removeValue(forKey: key)
        } else {
            stored[key] = choice.rawValue
        }
    }

    /// Reads the current choice before a view's `@AppStorage` has initialised
    /// (used to seed create/edit sheets).
    static func storedChoice(forKey key: String) -> PersonalEventOutlineColor {
        let json = UserDefaults.standard.string(forKey: storageKey) ?? emptyJSON
        return choice(in: decode(json), for: key)
    }
}

/// Colour swatch menu shown on each event in My Calendar's day event list.
struct EventOutlineColorMenu: View {
    let selection: Binding<PersonalEventOutlineColor>
    /// Effective colour shown on the menu's trigger button.
    let displayColor: Color

    var body: some View {
        Menu {
            ForEach(PersonalEventOutlineColor.allCases) { option in
                Button {
                    selection.wrappedValue = option
                } label: {
                    Label {
                        Text(
                            option == selection.wrappedValue
                                ? "\(option.label) ✓"
                                : option.label
                        )
                    } icon: {
                        Image(
                            systemName: option.color == nil
                                ? "circle.dashed" : "circle.fill"
                        )
                        .tint(option.color ?? .secondary)
                    }
                }
            }
        } label: {
            Image(systemName: "circle.fill")
                .tint(displayColor)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Event outline color")
    }
}

/// Palette row used in the create/edit screens and group More Info screen.
struct EventColorPicker: View {
    @Binding var selection: PersonalEventOutlineColor
    /// Groups always have a real colour, so "Automatic" can be hidden.
    var includeAutomatic: Bool = true

    private var options: [PersonalEventOutlineColor] {
        includeAutomatic
            ? PersonalEventOutlineColor.allCases
            : PersonalEventOutlineColor.selectable
    }

    var body: some View {
        Picker("Color", selection: $selection) {
            ForEach(options) { option in
                Label {
                    Text(option.label)
                } icon: {
                    Image(
                        systemName: option.color == nil
                            ? "circle.dashed" : "circle.fill"
                    )
                    .tint(option.color ?? .secondary)
                }
                .tag(option)
            }
        }
    }
}
