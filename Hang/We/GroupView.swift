import SwiftUI

public enum GroupTab: String, CaseIterable, Identifiable {
    case cal = "Calendar"
    case events = "Events"
    case info = "More Info"

    public var id: Self { self }
}

struct GroupView: View {
    let groupID: String
    @Environment(GroupStore.self) private var groupStore
    @State private var selectedGroupTab: GroupTab = .events

    private var tg: TestGroup? { groupStore.group(groupID) }

    var body: some View {
        NavigationStack {
            VStack {
                Picker("Picker", selection: $selectedGroupTab) {
                    ForEach(GroupTab.allCases) { gtab in
                        Text(gtab.rawValue)
                    }
                }
                .padding()
                .pickerStyle(.segmented)

                switch selectedGroupTab {
                case .cal:
                    GroupCalendarView(groupID: groupID)
                case .events:
                    EventView(groupID: groupID)
                case .info:
                    MoreInfoView(groupID: groupID)
                }
            }
            .navigationTitle(tg?.name ?? "Group")
        }
    }
}

// MARK: - Events

struct EventView: View {
    var sizing = Sizing()
    let groupID: String
    @Environment(GroupStore.self) private var groupStore
    @State private var showAddView = false

    private var events: [GroupEvents] {
        groupStore.groupEvents(groupID)
    }

    var body: some View {
        List {
            ForEach(events) { event in
                VStack(alignment: .leading) {
                    HStack {
                        Text(event.name)
                            .font(.system(size: sizing.x4))
                        Divider()
                            .frame(width: 1)
                            .overlay(.black)
                        Text(
                            event.startTime
                                .formatted(date: .abbreviated, time: .shortened)
                        )
                        .font(.system(size: sizing.x4))
                    }

                    if !event.desc.isEmpty {
                        Text(event.desc)
                            .font(.system(size: sizing.x3))
                            .lineLimit(1)
                    }
                }
                .listRowBackground(Color(.systemGray6))
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        Task { await groupStore.deleteEvent(event, in: groupID) }
                    }
                }
            }

            Button {
                showAddView = true
            } label: {
                Text("+ Add New Event")
                    .font(.system(size: sizing.x4))
            }
            .listRowBackground(Color(.systemGray6))
        }
        .padding(.top, -sizing.x4)
        .scrollContentBackground(.hidden)
        .sheet(isPresented: $showAddView) {
            CreateEventView(groupID: groupID, initialDate: Date())
                .presentationDetents([.medium])
                .presentationBackground(.ultraThinMaterial)
        }
    }
}

// MARK: - More info

struct MoreInfoView: View {
    var sizing = Sizing()
    @Environment(GroupStore.self) private var groupStore
    @Environment(AvailabilityStore.self) private var availabilityStore
    @Environment(\.dismiss) private var dismiss

    let groupID: String

    private var tg: TestGroup? { groupStore.group(groupID) }
    private var members: [Person] { groupStore.roster(groupID) }

    private var currentMember: Person? {
        members.first(where: \.isCurrentUser)
    }

    /// Reads the live member document and writes changes back through the
    /// store. The toggle therefore reflects the server's answer, not a local
    /// guess that could disagree after a relaunch.
    private var sharingBinding: Binding<Bool> {
        Binding(
            get: { currentMember?.sharingEnabled ?? false },
            set: { enabled in
                Task { await groupStore.setSharing(enabled, groupID: groupID) }
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack {
                Text("Invite Code")
                    .font(.system(size: sizing.x5, weight: .medium))
                    .padding(.bottom, -sizing.x1)

                ZStack {
                    RoundedRectangle(cornerRadius: sizing.x3)
                        .foregroundStyle(Color.black.opacity(0.1))
                    Text(tg?.code ?? "------")
                        .font(.system(size: sizing.x7, weight: .medium))
                        .padding(.vertical, sizing.x1)
                        .padding(.horizontal, sizing.x3)
                }
                .fixedSize(horizontal: true, vertical: false)
                .padding(sizing.x1)

                Divider()
                    .frame(height: 0.8)
                    .overlay(.black)
                    .padding(.vertical, sizing.x2)

                VStack(alignment: .leading) {
                    Text("Description")
                        .font(.system(size: sizing.x6, weight: .bold))
                    Text(tg?.desc ?? "")
                        .font(.system(size: sizing.x5))

                    Divider()
                        .frame(height: 0.8)
                        .overlay(.black)
                        .padding(.vertical, sizing.x2)

                    Text("Members (\(members.count))")
                        .font(.system(size: sizing.x6, weight: .bold))

                    ForEach(members) { member in
                        HStack {
                            Image(systemName: "person.crop.circle")
                                .resizable()
                                .scaledToFit()
                                .frame(width: sizing.x10)
                                .fontWeight(.light)

                            VStack(alignment: .leading) {
                                Text(member.name)
                                    .font(.system(size: sizing.x5))
                                Text(member.status)
                                    .font(.system(size: sizing.x4))
                                    .lineLimit(1)
                            }

                            Spacer()

                            Circle()
                                .fill(statusColor(for: member))
                                .frame(width: 8, height: 8)
                                .accessibilityLabel(statusText(for: member))
                        }
                    }

                    Divider()
                        .frame(height: 0.8)
                        .overlay(.black)
                        .padding(.vertical, sizing.x2)

                    Toggle("Share my availability", isOn: sharingBinding)
                        .font(.system(size: sizing.x5))
                        .disabled(currentMember == nil)

                    Text("Only start and end times are shared. Event titles never leave your phone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Leave group", role: .destructive) {
                        Task {
                            await groupStore.leaveGroup(groupID)
                            dismiss()
                        }
                    }
                    .font(.system(size: sizing.x5))
                    .padding(.top, sizing.x1)
                }
            }
        }
        .padding(.horizontal, sizing.x4)
    }

    private func status(for member: Person) -> MemberAvailabilityStatus {
        AvailabilityCalculator.sharedStatus(
            shared: availabilityStore.isSharing(member.uid, inGroup: groupID),
            updatedAt: availabilityStore.byGroup[groupID]?[member.uid]?.updatedAt
        )
    }

    private func statusColor(for member: Person) -> Color {
        switch status(for: member) {
        case .sharing, .mock:
            return .green
        case .stale:
            return .orange
        case .notSharing:
            return .secondary
        }
    }

    private func statusText(for member: Person) -> String {
        switch status(for: member) {
        case .sharing, .mock:
            return "Sharing availability"
        case .stale:
            return "Availability is out of date"
        case .notSharing:
            return "Not sharing availability"
        }
    }
}

#if DEBUG
#Preview("Group") {
    GroupView(groupID: PreviewData.groupID)
        .environment(GroupStore.preview(with: PreviewData.members))
        .environment(AvailabilityStore.preview())
}

#Preview("Events") {
    EventView(groupID: PreviewData.groupID)
        .environment(GroupStore.preview(with: PreviewData.members))
        .environment(AvailabilityStore.preview())
}
#endif
