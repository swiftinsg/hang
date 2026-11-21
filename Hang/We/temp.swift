//
//  temp.swift
//  Hang
//
//  Created by Tiffany Lim on 20/11/26.
//

import SwiftUI

struct temp: View {
    var sizing = Sizing()
    var colors = Colors()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    Color(
                        red: Double.random(in: 0.35...0.45),
                        green: Double.random(in: 0.6...0.7),
                        blue: Double.random(in: 0.4...0.5)
                    )
                )
                .aspectRatio(1, contentMode: .fit)
            VStack(alignment: .leading, spacing: 16) {
                Text("Order of the Rolling J")
                    .font(.title3)
                    .bold()
                    .lineLimit(2)
                    .padding(.bottom, -sizing.x1)
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.subheadline)
                    Text("100")
                        .font(.headline)
                        .fontWeight(.medium)
                }
                HStack(spacing: -8) {
                    ForEach(0..<5, id: \.self) { member in
                        Circle()
                            .foregroundStyle(
                                Color(
                                    red: Double.random(in: 0.1...0.8),
                                    green: Double.random(in: 0.1...0.8),
                                    blue: Double.random(in: 0.1...0.8)
                                )
                            )
                            .frame(width: 32)
                    }
                }
            }
            .padding(.vertical, sizing.x3)
            .padding(.horizontal, sizing.x4)
        }
        .padding(5)
        .frame(width: 200, height: 200)
    }
}

#Preview {
    temp()
}
