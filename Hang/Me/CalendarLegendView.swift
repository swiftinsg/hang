//
//  CalendarLegendView.swift
//  Hang
//
//  Shared legend content shown from the info buttons.
//

import SwiftUI

struct CalendarLegendEntry: Identifiable {
    let id = UUID()
    let title: String
    let fill: Color
    var stroke: Color?
    var dashed: Bool = false
}

struct CalendarLegendView: View {
    let title: String
    let entries: [CalendarLegendEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            ForEach(entries) { entry in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(entry.fill)
                        .overlay {
                            if let stroke = entry.stroke {
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(
                                        stroke,
                                        style: StrokeStyle(
                                            lineWidth: 1.5,
                                            dash: entry.dashed ? [3, 2] : []
                                        )
                                    )
                            }
                        }
                        .frame(width: 18, height: 12)

                    Text(entry.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 220, alignment: .leading)
    }
}

#Preview {
    let colors = Colors()

    CalendarLegendView(
        title: "Calendar Legend",
        entries: [
            CalendarLegendEntry(title: "Free", fill: colors.green.opacity(0.4)),
            CalendarLegendEntry(title: "Your calendar", fill: colors.dgreen.opacity(0.85)),
            CalendarLegendEntry(
                title: "Hang event",
                fill: .orange.opacity(0.15),
                stroke: .orange,
                dashed: true
            ),
        ]
    )
}
