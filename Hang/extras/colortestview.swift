import SwiftUI

struct colorView: View {
    @State var screenSize: CGSize = .zero
    var body: some View {
        HStack(spacing: 8) {
            Text("name")
                .font(.largeTitle.bold())
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            ZStack{
                Circle()
                    .frame(width: screenSize.width*0.09)
                    .tint(.accentColor)
                Image(systemName: "pencil")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                
            }
        }.onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            screenSize = newSize
        }
    }
}

#Preview {
    colorView()
}
//Color(red: 1.0, green: 0.55, blue: 0.0)


