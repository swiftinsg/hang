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
                .fill(Color(
                    red: Double.random(in: 0.35...0.45),
                    green: Double.random(in: 0.6...0.7),
                    blue: Double.random(in: 0.4...0.5)
                ))
                .aspectRatio(1, contentMode: .fit)
            VStack(alignment: .leading, spacing: 16) {
                Text("are you free on 23 november 2026 for a thing")
                    .font(.title3)
                    .bold()
                    .lineLimit(2)
                    //                    .foregroundStyle(colors.txt1)
                    .padding(.bottom, -sizing.x1)
//                                Text("That's not great.")
                //                    .font(.system(size: sizing.x3))
                //                    .lineLimit(1)
                //                    .foregroundStyle(colors.txt2)
//                Text("Hang! in 3 days")
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.subheadline)
//                        .resizable()
//                        .scaledToFit()
                        //                        .foregroundStyle(colors.txt2)
//                        .frame(width: sizing.x4)
                    Text("500")
                        .font(.headline)
                        .fontWeight(.medium)
//                        .font(.system(size: sizing.x4, weight: .bold))
                    //                        .foregroundStyle(colors.txt2)
                }
                HStack(spacing: -8) {
                    Circle()
                        .foregroundStyle(.red)
                        .frame(width: 32)
                    Circle()
                        .foregroundStyle(.orange)
                        .frame(width: 32)
                    Circle()
                        .foregroundStyle(.yellow)
                        .frame(width: 32)
                    Circle()
                        .foregroundStyle(.green)
                        .frame(width: 32)
                    Circle()
                        .foregroundStyle(.blue)
                        .frame(width: 32)
                }
            }
            .padding(.vertical, sizing.x3)
            .padding(.horizontal, sizing.x4)
        }
        .frame(width: 200, height: 200)
        .padding(5)

    }
}

#Preview {
    temp()
}
