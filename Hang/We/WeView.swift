import SwiftUI

struct WeView: View {
    var sizing = Sizing()
    var colors = Colors()
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
        GridItem(.adaptive(minimum: 150))
    ]
    @FocusState var isFocused: Bool
    
    var body: some View {
        @Bindable var store = store
        
        NavigationStack {
            ScrollView {
                VStack {
                    LazyVGrid(columns: columns, spacing: sizing.x1) {
                        ForEach(results) { tg in
                            if let index = store.groups.firstIndex(where: { $0.id == tg.id }) {
                                NavigationLink {
                                    GroupView(tg: $store.groups[index])
                                } label: {
                                    GroupCard(tg: tg)
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
    var sizing = Sizing()
    var colors = Colors()
    let tg: TestGroup
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(
                    red: Double.random(in: 0.35...0.45),
                    green: Double.random(in: 0.6...0.7),
                    blue: Double.random(in: 0.4...0.5)
                ))
                .aspectRatio(1, contentMode: .fit)
            VStack(alignment: .leading, spacing: 16) {
                Text(tg.name)
                    .font(.title3)
                    .bold()
                    .lineLimit(2)
                    .padding(.bottom, -sizing.x1)
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.subheadline)
                    Text(String(tg.members.count))
                        .font(.headline)
                        .fontWeight(.medium)
                }
                HStack(spacing: -8) {
                    ForEach(Array(tg.members.prefix(5))) { member in
                        Circle()
                            .foregroundStyle(Color(
                                red: Double.random(in: 0.1...0.8),
                                green: Double.random(in: 0.1...0.8),
                                blue: Double.random(in: 0.1...0.8)
                            ))
                            .frame(width: 32)
                    }
                }
            }
            .padding(.vertical, sizing.x3)
            .padding(.horizontal, sizing.x4)
        }
        .padding(5)
    }
}

#Preview {
    WeView()
}
