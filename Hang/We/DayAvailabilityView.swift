//
//  DayAvailabilityView.swift
//  Hang
//
//  Shows each group member's free and busy blocks for a single day, plus your
//  own personal calendar as a read-only member column.
//
//  Layout: time runs down the page on the leading edge, and every member gets
//  their own column with their avatar on top. The view lays out at its full
//  height and leaves scrolling to the enclosing CalendarView, so the whole
//  calendar scrolls as one page. Pinching changes the height of each hour row.
//

import SwiftUI

private struct PersonalBusyItem: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    /// Key into the device-local colour map, so this block matches the colour
    /// shown on the month grid and in the day event list.
    let colorKey: String
    /// Set only for events created in Hang, so the personal calendar can open
    /// them for editing. Imported device-calendar events stay read only.
    let personalEvent: GroupEvents?
}

struct DayAvailabilityView: View {
    // rip Colors() struct
    let date: Date
    /// Firestore group document ID, used to read this group's shared busy times.
    var groupID: String = ""
    let members: [Person]
    let calendar: Calendar
    var groupEvents: [GroupEvents] = []
    var personalEvents: [GroupEvents] = []
    var importedEvents: [PersonalCalendarEvent] = []

    /// Device-local event colours, so the bars match the month grid's line
    /// segments and event list. Never written to Firestore.
    var storedColors: Binding<[String: String]> = .constant([:])
    /// Colour shared by this group's events, chosen in the group's More Info.
    var groupColor: HangColors = HangColors.blue

    /// Called when a group event block is tapped. Personal events stay read
    /// only in the shared calendar.
    var onEditGroupEvent: ((GroupEvents) -> Void)? = nil

    /// Called when one of your own events is tapped. Only the personal
    /// calendar passes this, so your events remain editable there while the
    /// shared calendar keeps them read only.
    var onEditPersonalEvent: ((GroupEvents) -> Void)? = nil

    /// Committed pinch-to-zoom level for the hour rows.
    @State private var zoom: CGFloat = 1

    @State private var isShowingLegend = false

    /// Live pinch delta. `@GestureState` resets it to 1 when the gesture ends.
    @GestureState private var pinch: CGFloat = 1

    private let gutterWidth: CGFloat = 44
    private let avatarRowHeight: CGFloat = 50
    private let baseHourHeight: CGFloat = 54

    @State private var availabilityStore = AvailabilityStore.shared

    private var calculator: AvailabilityCalculator {
        AvailabilityCalculator(
            calendar: calendar,
            personalEvents: personalEvents,
            importedEvents: importedEvents,
            groupEvents: groupEvents,
            sharedBusy: availabilityStore.busyIntervals(inGroup: groupID),
            sharedUpdatedAt: availabilityStore.updatedAt(inGroup: groupID)
        )
    }

    private var window: DateInterval {
        calculator.window(for: date)
    }

    /// Every whole hour in the availability window, e.g. 8 through 21.
    private var hours: [Int] {
        Array(AvailabilityDay.startHour..<AvailabilityDay.endHour)
    }

    /// Events from the group calendar that fall on this day, in time order.
    private var dayGroupEvents: [GroupEvents] {
        groupEvents
            .filter { calendar.isDate(eventStart($0), inSameDayAs: date) }
            .sorted { $0.time < $1.time }
    }

    /// Day events that overlap the visible availability window.
    private var timedGroupEvents: [GroupEvents] {
        dayGroupEvents.filter { event in
            eventStart(event) < window.end && eventEnd(event) > window.start
        }
    }

    /// Your personal events (created in Me plus imported device-calendar
    /// events). They appear read only in your own column.
    private var personalBusyItems: [PersonalBusyItem] {
        let created = personalEvents.map { event in
            PersonalBusyItem(
                id: event.id.uuidString,
                title: event.name,
                start: event.startDate,
                end: event.endDate,
                colorKey: PersonalEventColorKey.personal(event.id),
                personalEvent: event
            )
        }
        let imported = importedEvents.map { event in
            PersonalBusyItem(
                id: event.id,
                title: event.title,
                start: event.startDate,
                end: event.endDate,
                colorKey: PersonalEventColorKey.imported(event.id),
                personalEvent: nil
            )
        }

        return (created + imported).sorted { $0.start < $1.start }
    }

    private var timedPersonalItems: [PersonalBusyItem] {
        personalBusyItems.filter { $0.start < window.end && $0.end > window.start }
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
        let offset = hour - AvailabilityDay.startHour
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
                    CalendarLegendView()
                        .presentationCompactAdaptation(.automatic)
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
                    ProfileAvatarView(person: member, size: 26)

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

    @ViewBuilder
    private func memberColumn(_ member: Person, columnWidth: CGFloat) -> some View {
        let status = calculator.status(for: member)
        let busy = calculator.memberBusyIntervals(for: member, on: date)
        let isCurrentUser = member.isCurrentUser

        ZStack(alignment: .topLeading) {
            // A member who hasn't shared is not silently shown as free.
            Color.green.adjusted(saturation: 0.5, brightness: -0.07).opacity(status == .sharing ? 0.12 : 0.03)

            if isCurrentUser {
                // Your own events stay on this device; only you see the titles.
                ForEach(timedPersonalItems) { item in
                    personalBlock(
                        item,
                        columnWidth: columnWidth,
                        onEdit: personalEditAction(for: item)
                    )
                }
            } else {
                // Anonymous busy intervals published by this member.
                ForEach(Array(busy.enumerated()), id: \.offset) { _, interval in
                    busyBlock(interval, tint: member.tint, columnWidth: columnWidth)
                }
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

    /// Diagonal hatching for a member who has not published anything.
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
            .allowsHitTesting(false)
    }

    private func busyBlock(
        _ interval: DateInterval,
        tint: Color,
        columnWidth: CGFloat
    ) -> some View {
        let startHours = interval.start.timeIntervalSince(window.start) / 3600
        let durationHours = interval.duration / 3600

        let barWidth = max(columnWidth - 10, 6)
        let barHeight = max(4, CGFloat(durationHours) * hourHeight - 1)
        let cornerRadius = min(8, barWidth / 3)

        return RoundedRectangle(cornerRadius: cornerRadius)
            .fill(tint.opacity(0.75))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(tint, lineWidth: 1)
            )
            .frame(width: barWidth, height: barHeight)
            .offset(
                x: (columnWidth - barWidth) / 2,
                y: CGFloat(startHours) * hourHeight
            )
    }

    private func personalEditAction(
        for item: PersonalBusyItem
    ) -> (() -> Void)? {
        guard let event = item.personalEvent, let onEditPersonalEvent else {
            return nil
        }
        return { onEditPersonalEvent(event) }
    }

    /// Your personal events fill your own column. They are read only in the
    /// shared calendar and tappable in the personal calendar.
    private func personalBlock(
        _ item: PersonalBusyItem,
        columnWidth: CGFloat,
        onEdit: (() -> Void)? = nil
    ) -> some View {
        let visibleStart = max(item.start, window.start)
        let visibleEnd = min(item.end, window.end)
        let startHours = visibleStart.timeIntervalSince(window.start) / 3600
        let durationHours = visibleEnd.timeIntervalSince(visibleStart) / 3600

        let barWidth = max(columnWidth - 10, 6)
        let barHeight = max(4, CGFloat(durationHours) * hourHeight - 1)
        let cornerRadius = min(8, barWidth / 3)
        let color = PersonalEventColors.color(
            in: storedColors.wrappedValue,
            for: item.colorKey,
            default: .gray
        )

        let block = RoundedRectangle(cornerRadius: cornerRadius)
            .fill(color.opacity(0.75))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(color, lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                if barHeight > 20 {
                    Text(item.title)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 3)
                        .padding(.top, 2)
                }
            }
            .frame(width: barWidth, height: barHeight)

        return Group {
            if let onEdit {
                Button(action: onEdit) {
                    block
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityHint("Edit or delete this event")
            } else {
                block
                    .allowsHitTesting(false)
            }
        }
        .offset(
            x: (columnWidth - barWidth) / 2,
            y: CGFloat(startHours) * hourHeight
        )
    }

    /// One band per group event, tinted with that group's chosen colour.
    private func groupEventBands(contentWidth: CGFloat) -> some View {
        ForEach(timedGroupEvents) { event in
            groupEventBand(
                start: eventStart(event),
                end: eventEnd(event),
                title: event.name,
                color: event.groupColor.col,
                contentWidth: contentWidth,
                onTap: {
                    onEditGroupEvent?(event)
                }
            )
        }
    }

    private func groupEventBand(
        start: Date,
        end: Date,
        title: String,
        color: Color,
        contentWidth: CGFloat,
        onTap: (() -> Void)? = nil
    ) -> some View {
        let visibleStart = max(start, window.start)
        let visibleEnd = min(end, window.end)
        let startHours = visibleStart.timeIntervalSince(window.start) / 3600
        let durationHours = visibleEnd.timeIntervalSince(visibleStart) / 3600
        let bandHeight = max(18, CGFloat(durationHours) * hourHeight - 1)

        let band = RoundedRectangle(cornerRadius: 6)
            .fill(color.opacity(0.15))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        color,
                        style: StrokeStyle(lineWidth: 1.5, dash: [4, 2])
                    )
            }
            .overlay(alignment: .topLeading) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
            }
            .frame(width: max(contentWidth - 4, 10), height: bandHeight)

        return Group {
            if let onTap {
                Button(action: onTap) {
                    band
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityHint("Edit or delete this event")
            } else {
                band
                    .allowsHitTesting(false)
            }
        }
        .offset(x: 2, y: CGFloat(startHours) * hourHeight)
    }

    private func eventStart(_ event: GroupEvents) -> Date {
        Date(timeIntervalSince1970: event.time)
    }

    private func eventEnd(_ event: GroupEvents) -> Date {
        if let endTime = event.endTime {
            return Date(timeIntervalSince1970: endTime)
        }
        // Older events only store a start time, so show them for an hour.
        return eventStart(event).addingTimeInterval(60 * 60)
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

#Preview {
    let calendar = Calendar.current
    let today = Date()
    let day = calendar.startOfDay(for: today)

    return ScrollView {
        DayAvailabilityView(
            date: today,
            members: [Person.currentUser]
                + TestGroup(code: "ABCD67", name: "CODZEE").members,
            calendar: calendar,
            groupEvents: [
                GroupEvents(
                    name: "Dinner",
                    desc: "Group dinner",
                    time: (calendar.date(byAdding: .hour, value: 18, to: day) ?? today)
                        .timeIntervalSince1970,
                    endTime: (calendar.date(byAdding: .hour, value: 20, to: day) ?? today)
                        .timeIntervalSince1970
                )
            ],
            personalEvents: [
                GroupEvents(
                    name: "Gym",
                    time: (calendar.date(byAdding: .hour, value: 9, to: day) ?? today)
                        .timeIntervalSince1970,
                    endTime: (calendar.date(byAdding: .hour, value: 10, to: day) ?? today)
                        .timeIntervalSince1970
                )
            ]
        )
        .padding()
    }
}
