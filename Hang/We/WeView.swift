import SwiftUI

struct WeView: View {
    var sizing = Sizing()
    var colors = Colors()
    @Environment(GroupStore.self) private var groupStore
    @State var searchQuery = ""
    @State var countPicker: Int = 0
    @State var showingCreateSheet = false
    @State var showingJoinSheet = false

    var results: [TestGroup] {
        var filtered = groupStore.groups

        if !searchQuery.isEmpty {
            filtered = filtered.filter {
                $0.name.localizedCaseInsensitiveContains(searchQuery)
            }
        }

        if countPicker != 0 {
            filtered = filtered.filter { memberCount(for: $0) == countPicker }
        }

        return filtered
    }

    let columns = [
        GridItem(.adaptive(minimum: 150))
    ]
    @FocusState var isFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack {
                    LazyVGrid(columns: columns, spacing: sizing.x1) {
                        ForEach(results) { tg in
                            NavigationLink {
                                GroupView(groupID: tg.id ?? "")
                            } label: {
                                GroupCard(
                                    tg: tg,
                                    memberCount: memberCount(for: tg)
                                )
                            }
                            .buttonStyle(setStyle(styleName: .Shrink2))
                        }
                    }
                    .padding()
                    .ignoresSafeArea()
                    .searchable(
                        text: $searchQuery,
                        placement: .navigationBarDrawer(displayMode: .always)
                    )
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                CreateGroupView()
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingJoinSheet) {
                JoinGroupView()
                    .presentationDetents([.medium])
            }
            .navigationTitle("Groups")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: ProfileView()) {
                        Label("Profile", systemImage: "person.fill")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Menu {
                        Button("Create", systemImage: "star") {
                            showingCreateSheet = true
                        }
                        Button("Join", systemImage: "person.badge.plus") {
                            showingJoinSheet = true
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
        }
    }

    /// The roster is the live member count. Before it finishes loading, the
    /// group document's `memberUids` is a good stand-in.
    private func memberCount(for group: TestGroup) -> Int {
        let roster = groupStore.roster(group.id ?? "")
        return roster.isEmpty ? group.memberUids.count : roster.count
    }
}

struct GroupCard: View {
    var sizing = Sizing()
    var colors = Colors()
    let tg: TestGroup
    let memberCount: Int

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(colors.green)
                .aspectRatio(1, contentMode: .fit)
            VStack(alignment: .leading) {
                Text(tg.name)
                    .font(.system(size: sizing.x5, weight: .bold))
                    .lineLimit(1)
                    .foregroundStyle(colors.txt1)
                    .padding(.bottom, -sizing.x1)
                Divider()
                    .frame(height: 1)
                    .overlay(colors.obj)
                    .padding(.vertical, sizing.x2)
                Text(tg.desc)
                    .font(.system(size: sizing.x3))
                    .lineLimit(1)
                    .foregroundStyle(colors.txt2)
                HStack {
                    Text("\(memberCount)")
                        .font(.system(size: sizing.x4, weight: .bold))
                        .foregroundStyle(colors.txt2)
                    Image(systemName: "person.2.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(colors.txt2)
                        .frame(width: sizing.x4)
                }
            }
            .padding(.vertical, sizing.x3)
            .padding(.horizontal, sizing.x4)
        }
        .padding(5)
    }
}

#if DEBUG
#Preview {
    WeView()
        .environment(GroupStore.preview(with: PreviewData.members))
        .environment(AvailabilityStore.preview())
}
#endif
