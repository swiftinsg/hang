import SwiftUI

struct MeView: View {
    @Environment(GroupStore.self) private var groupStore

    var body: some View {
        NavigationStack {
            PersonalCalendarView(groupEvents: groupStore.allGroupEvents())
                .navigationTitle("My Calendar")
                .toolbarTitleDisplayMode(.inlineLarge)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(destination: ProfileView()) {
                            Label("Profile", systemImage: "person.fill")
                        }
                    }
                }
        }
    }
}

#if DEBUG
#Preview {
    MeView()
        .environment(GroupStore.preview(with: PreviewData.members))
}
#endif
