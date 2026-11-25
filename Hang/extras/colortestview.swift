import SwiftUI

struct colorView: View {
    var body: some View {
        VStack {
            Color(.orange)
                .padding(-5)
            Color(Colors().red.col)
                .padding(-5)
        }
        .ignoresSafeArea()
    }
}

#Preview {
    colorView()
}
//Color(red: 1.0, green: 0.55, blue: 0.0)


