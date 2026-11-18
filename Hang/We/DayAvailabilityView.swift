//
//  DayAvailabilityView.swift
//  Hang
//
//  Shows each group member's free and busy blocks for a single day.
//
//  Layout: time runs down the page on the leading edge, and every member gets
//  their own column with their avatar on top. The view lays out at its full
//  height and leaves scrolling to the enclosing calendar, so the whole
//  calendar scrolls as one page. Pinching changes the height of each hour row.
//
//  Privacy: a member's busy block is a translucent bar with no text. Only the
//  current user's own column ever shows an event title, because that title is
//  already on this device.
//

import SwiftUI

struct DayAvailabilityView: View {
    let date: Date
    let groupID: String
    let calendar: Calendar

    @Environment(GroupStore.self) private var groupStore
    @Environment(AvailabilityStore.self) private var availabilityStore
    @State private var calendarStore = PersonalCalendarStore.shared

    /// Preview-only: fills lanes that have no shared data with the debug sample
    /// schedule. Has no effect in a release build, where the mock generator is
    /// compiled out.
    var useMockFallback = false

    /// Committed pinch-to-zoom level for the hour rows.
    @State private var zoom: CGFloat = 1

    @State private var isShowingLegend = false

    /// Live pinch delta. `@GestureState` resets it to 1 when the gesture ends.
    @GestureState private var pinch: CGFloat = 1

    private let gutterWidth: CGFloat = 44
    private let avatarRowHeight: CGFloat = 50
    private let baseHourHeight: CGFloat = 54

    // MARK: - Data

    private var members: [Person] { groupStore.roster(groupID) }

    private var calculator: AvailabilityCalculator {
        AvailabilityCalculator(
            calendar: calendar,
            personalEvents: calendarStore.events,
            groupEvents: groupStore.groupEvents(groupID),
            sharedBusy: availabilityStore.busyIntervals(inGroup: groupID),
            sharedUpdatedAt: availabilityStore.updatedAt(inGroup: groupID),
            useMockFallback: useMockFallback
        )
    }

    private var window: DateInterval {
        calculator.window(for: date)
    }

    /// Every whole hour in the availability window, e.g. 8 through 21.
    private var hours: [Int] {
        Array(DayWindow.standard.startHour..<DayWindow.standard.endHour)
    }

    // MARK: - Zoom

    private var effectiveZoom: CGFloat {
        min(max(zoom * pinch, 0.7), 2.2)
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .updating($pinch) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                zoom = min(max(zoom * value.magnification, 0.7), 2.2)
            }
    }

    // MARK: - Metrics

    private var hourHeight: CGFloat {
        baseHourHeight * effectiveZoom
    }

    /// Height of one member column, covering the whole availability window.
    private var gridHeight: CGFloat {
        CGFloat(hours.count) * hourHeight
    }

    private var totalHeight: CGFloat {
        avatarRowHeight + gridHeight
    }

    // MARK: - Formatting

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        return formatter
    }()

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("ha")
        return formatter
    }()

    private func hourLabel(for hour: Int) -> String {
        let offset = hour - DayWindow.standard.startHour
        let hourDate =
            calendar.date(byAdding: .hour, value: offset, to: window.start)
            ?? window.start
        return Self.hourFormatter.string(from: hourDate)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            timeline
        }
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Availability")
                .font(.subheadline.bold())
            Text(Self.dateFormatter.string(from: date))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()

            Button {
                isShowingLegend = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Availability legend")
            .popover(isPresented: $isShowingLegend) {
                CalendarLegendView(
                    title: "Availability Legend",
                    entries: [
                        CalendarLegendEntry(title: "Free", fill: .green.opacity(0.2)),
                        CalendarLegendEntry(title: "Member busy", fill: .secondary.opacity(0.45)),
                        CalendarLegendEntry(title: "Your calendar event", fill: .purple.opacity(0.45)),
                        CalendarLegendEntry(
                            title: "Group event",
                            fill: .orange.opacity(0.15),
                            stroke: .orange,
                            dashed: true
                        ),
                        CalendarLegendEntry(
                            title: "Not shared yet",
                            fill: .clear,
                            stroke: .secondary,
                            dashed: true
                        ),
                    ]
                )
                .presentationCompactAdaptation(.popover)
            }
        }
    }

    /// Hour labels on the leading edge, member columns filling the rest of the width.
    private var timeline: some View {
        GeometryReader { proxy in
            let contentWidth = max(proxy.size.width - gutterWidth, 1)
            let columnWidth = contentWidth / CGFloat(max(members.count, 1))

            HStack(alignment: .top, spacing: 0) {
                hourGutter

                VStack(spacing: 0) {
                    avatarRow(columnWidth: columnWidth, contentWidth: contentWidth)
                    grid(columnWidth: columnWidth, contentWidth: contentWidth)
                }
            }
        }
        .frame(height: totalHeight)
        .simultaneousGesture(magnificationGesture)
        .background(
            Color.primary.opacity(0.03),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    private var hourGutter: some View {
        VStack(spacing: 0) {
            // Aligns the first hour label with the top of the member columns.
            Color.clear
                .frame(width: gutterWidth, height: avatarRowHeight)

            ForEach(hours, id: \.self) { hour in
                Text(hourLabel(for: hour))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(
                        width: gutterWidth - 6,
                        height: hourHeight,
                        alignment: .topTrailing
                    )
                    .padding(.trailing, 6)
                    .offset(y: -5)
            }
        }
        .frame(width: gutterWidth)
        .allowsHitTesting(false)
    }

    private func avatarRow(columnWidth: CGFloat, contentWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(members) { member in
                VStack(spacing: 3) {
                    Text(String(member.name.prefix(1)))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(member.tint, in: Circle())

                    Text(member.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(width: columnWidth, height: avatarRowHeight)
            }
        }
        .frame(width: contentWidth, height: avatarRowHeight, alignment: .leading)
        .accessibilityHidden(true)
    }

    /// Member columns with group event bands and hour gridlines over the top.
    private func grid(columnWidth: CGFloat, contentWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                ForEach(members) { member in
                    memberColumn(member, columnWidth: columnWidth)
                }
            }

            groupEventBands(contentWidth: contentWidth)
            hourLines(contentWidth: contentWidth)
        }
        .frame(width: contentWidth, height: gridHeight, alignment: .topLeading)
    }

    private func memberColumn(_ member: Person, columnWidth: CGFloat) -> some View {
        let status = calculator.status(for: member)
        // Deliberately not `busyIntervals`: group events are drawn once as
        // bands across the whole grid, not repeated in every member column.
        let busy = calculator.memberBusyIntervals(for: member, on: date)

        return ZStack(alignment: .topLeading) {
            // The whole window is free until a busy block says otherwise.
            Color.green.opacity(status == .sharing || status == .mock ? 0.12 : 0.03)

            ForEach(Array(busy.enumerated()), id: \.offset) { _, interval in
                busyBlock(
                    interval,
                    tint: member.tint,
                    columnWidth: columnWidth,
                    title: member.isCurrentUser
                        ? personalEventTitle(for: interval)
                        : nil
                )
            }

            if status == .notSharing {
                notSharedOverlay(columnWidth: columnWidth)
            } else if status == .stale {
                staleBadge()
            }
        }
        .frame(width: columnWidth, height: gridHeight)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(width: 1)
        }
    }

    private func personalEventTitle(for interval: DateInterval) -> String? {
        calendarStore.events
            .filter { $0.linkedEventID == nil }
            .first(where: {
                $0.startDate < interval.end && $0.endDate > interval.start
            })?.title
    }

    private func busyBlock(
        _ interval: DateInterval,
        tint: Color,
        columnWidth: CGFloat,
        title: String?
    ) -> some View {
        let startHours = interval.start.timeIntervalSince(window.start) / 3600
        let durationHours = interval.duration / 3600

        let barWidth = max(columnWidth - 10, 6)
        let barHeight = max(4, CGFloat(durationHours) * hourHeight - 1)
        let cornerRadius = min(8, barWidth / 3)

        // At most 50% opacity, so two overlapping blocks compound rather than
        // hide one another.
        let fill = tint.opacity(0.4)

        return RoundedRectangle(cornerRadius: cornerRadius)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(tint.opacity(0.8), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if let title, barHeight > 20 {
                    Text(title)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 3)
                        .padding(.top, 2)
                }
            }
            .frame(width: barWidth, height: barHeight)
            .offset(
                x: (columnWidth - barWidth) / 2,
                y: CGFloat(startHours) * hourHeight
            )
    }

    /// Diagonal hatching for a member who has not published anything. Their
    /// lane is not silently treated as free.
    private func notSharedOverlay(columnWidth: CGFloat) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "eye.slash")
            Text("Not shared")
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .frame(width: columnWidth, height: gridHeight)
        .background {
            Canvas { context, size in
                var path = SwiftUI.Path()
                let spacing: CGFloat = 12

                for x in stride(
                    from: -size.height,
                    through: size.width,
                    by: spacing
                ) {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                }

                context.stroke(
                    path,
                    with: .color(.secondary.opacity(0.14)),
                    lineWidth: 1
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func staleBadge() -> some View {
        Text("Out of date")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.orange)
            .padding(2)
            .background(.background, in: Capsule())
            .padding(.top, 2)
            .padding(.leading, 2)
    }

    /// One orange band per group event, spanning every member column.
    private func groupEventBands(contentWidth: CGFloat) -> some View {
        let events = calculator.groupEventIntervals(on: date)

        return ForEach(Array(events.enumerated()), id: \.offset) { _, event in
            groupEventBand(
                event.interval,
                title: event.title,
                contentWidth: contentWidth
            )
        }
    }

    private func groupEventBand(
        _ interval: DateInterval,
        title: String,
        contentWidth: CGFloat
    ) -> some View {
        let startHours = interval.start.timeIntervalSince(window.start) / 3600
        let durationHours = interval.duration / 3600
        let bandHeight = max(18, CGFloat(durationHours) * hourHeight - 1)

        return RoundedRectangle(cornerRadius: 6)
            .fill(Color.orange.opacity(0.15))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        Color.orange,
                        style: StrokeStyle(lineWidth: 1.5, dash: [4, 2])
                    )
            }
            .overlay(alignment: .topLeading) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
            }
            .frame(width: max(contentWidth - 4, 10), height: bandHeight)
            .offset(x: 2, y: CGFloat(startHours) * hourHeight)
            .allowsHitTesting(false)
    }

    /// Faint line at each hour boundary, including one at the bottom edge.
    private func hourLines(contentWidth: CGFloat) -> some View {
        Canvas { context, size in
            for index in 0...hours.count {
                let y = CGFloat(index) * hourHeight
                var path = SwiftUI.Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(
                    path,
                    with: .color(Color.primary.opacity(index == 0 ? 0.18 : 0.10)),
                    lineWidth: 0.6
                )
            }
        }
        .frame(width: contentWidth, height: gridHeight)
        .allowsHitTesting(false)
    }
}

#if DEBUG
#Preview("Shared and not shared") {
    ScrollView {
        DayAvailabilityView(
            date: Date(),
            groupID: PreviewData.groupID,
            calendar: .current
        )
        .environment(GroupStore.preview(with: PreviewData.members))
        .environment(AvailabilityStore.preview())
        .padding()
    }
}

#Preview("Mock fallback") {
    ScrollView {
        DayAvailabilityView(
            date: Date(),
            groupID: PreviewData.groupID,
            calendar: .current,
            useMockFallback: true
        )
        .environment(GroupStore.preview(with: PreviewData.members))
        .environment(AvailabilityStore())
        .padding()
    }
}
#endif
