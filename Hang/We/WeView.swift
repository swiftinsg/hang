import SwiftUI

struct WeView: View {
    @State var searchQuery = ""
    @State var countPicker: Int = 0
    @State private var store = GroupStore.shared
    @State var showingCreateSheet = false
    @State var showingJoinSheet = false

    var results: [TestGroup] {
        var filtered = store.groups
        if !searchQuery.isEmpty {
            filtered = filtered.filter {
                $0.name.localizedCaseInsensitiveContains(searchQuery)
            }
        }
        if countPicker != 0 {
            filtered = filtered.filter { $0.members.count == countPicker }
        }
        return filtered
    }

    let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 16)
    ]
    @FocusState var isFocused: Bool

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            ScrollView {
                VStack {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(results) { tg in
                            if let index = store.groups.firstIndex(where: {
                                $0.id == tg.id
                            }) {
                                NavigationLink {
                                    GroupView(tg: $store.groups[index])
                                } label: {
                                    GroupCard(tg: tg, members: tg.members)
                                }
                                .buttonStyle(setStyle(styleName: .Shrink2))
                            }
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
            .overlay {
                if results.isEmpty {
                    if searchQuery.isEmpty {
                        ContentUnavailableView(
                            "No Groups",
                            image: "trayHang",
                            description: Text(
                                "Press + to create or join your first group!"
                            )
                        )
                    } else {
                        ContentUnavailableView.search
                    }
                }
            }
            .refreshable {
                await AppReloader.reloadAll()
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
}

struct GroupCard: View {
    let tg: TestGroup
    let members: [Person]
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(.accent.mix(with: .white, by: 0.25))
                .shadow(color: .black.opacity(0.15), radius: 16)
            //                .fill(Color(.secondarySystemBackground))
            //                .shadow(color: Color(.systemGray4), radius: 16)
            VStack(alignment: .leading, spacing: 16) {
                Text(tg.name)
                    .font(.title3)
                    .bold()
                    .lineLimit(2)
                    .padding(.bottom, -4)
                Text(
                    "\(tg.members.count) member\(tg.members.count != 1 ? "s" : "")"
                )
                .foregroundStyle(.secondary)
                HStack(spacing: -8) {
                    ForEach(Array(tg.members.prefix(5))) { member in
                        ProfileAvatarView(person: member, size: 32)
                            .background(
                                .background
                            )
                            .clipShape(.circle)
                    }
                }
            }
            .padding(24)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
    }
}

#Preview {
    WeView()

    // Preview for GroupCard
    /*
    GroupCard(
        tg: TestGroup(
            code: "CODZEE",
            name: "CODZEE hahaha ahaodhuau oiwhdsa do",
            desc: "hang",
            members: [Person(name: "e", profilePicture: .derpyAlien)],
            events: [],
            documentID: ""
        ),
        members: []
    )
    .frame(width: 200, height: 200)
    */
}
