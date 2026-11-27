//
//  CalendarLegendView.swift
//  Hang
//
//  Shared legend content shown from the info buttons.
//

import SwiftUI

//struct CalendarLegendEntry: Identifiable {
//    let id = UUID()
//    let title: String
//    let fill: Color
//    var stroke: Color?
//    var dashed: Bool = false
//}

struct CalendarLegendView: View {
    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How to understand your calendars")
                .font(.title)
                .fontWeight(.bold)
            Text("There are two different types of calendars, personal nd group calendars!")
                .font(.subheadline)
            Spacer()
            HStack{
                VStack{
                    Image(.monoSingleHang)
                        .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 40) 
                    Text("Me")
                    Spacer()
                    
                    HStack{
                        ZStack{
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.yellow, lineWidth: 3)
                                .fill(.clear)
                                .frame(width:80, height:70)
                            Text("9")
                            Image("legendFalseBar")
                                
                                .offset(y:25)
                                
                        }
                        Text("The bar at the bottom shows your color coded personal events")
                            .font(.caption)
                        
                    }
                    Spacer()
                    HStack{
                        ZStack{
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.yellow, lineWidth: 3)
                                .fill(.clear)
                                .frame(width:80, height:70)
                            Text("8")
                                .offset(y:-10)
                            
                            
                                
                            Image("legendFalseBar")
                                
                                .offset(y:25)
                            Image(.flatYellowHang)
                                
                                .resizable()
                                .scaledToFit()
                                .frame(width:50,height:50)
                                .offset(y:15)
                        }
                        Text("If this little guy is there it means you have a group event")
                            
                            .font(.caption)
                        
                    }
                    Spacer()
                }
                Divider()
                VStack{
                    Image(.monoDoubleHang)
                        .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 40)
                    Text("We")
                    Spacer()
                    HStack(alignment: .bottom, spacing: 16){
                        VStack{
                            Text("less vibrant\n(less available)")
                                .font(.caption)
                            ZStack{
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.green.adjusted(saturation: 0.5, brightness: -0.07))
                                    .opacity(0.3)
                                    .frame(width:80, height:70)
                                Text("8")
                            }
                        }
                        VStack{
                            Text("more vibrant\n(more available)")
                                .font(.caption)
                            ZStack{
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.green.adjusted(saturation: 0.5, brightness: -0.07))
                                    .opacity(0.6)
                                    .frame(width:80, height:70)
                                Text("9")
                            }
                        }

                    }
                    Spacer()
                    HStack{
                        ZStack{
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.green.adjusted(saturation: 0.5, brightness: -0.07))
                                .opacity(0.8)
                                .frame(width:80, height:70)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(
                                        Color.blue,
                                        style: StrokeStyle(
                                            lineWidth: 3,
                                            dash: [3, 2]
                                        )
                                    )

                                )

                                Text("6")
                            }
                        Text("recommended most free dates")
                            .font(.caption)
                    }
                    Spacer()
                    if colorScheme == .dark {
                            Image(.darkAvailability)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 70)
                                .padding()
                            Text("press on a day and you can see peoples schedules(minus any details for their privacy)")
                            .font(.caption)
                       } else {
                           Image(.lightAvailability)
                               .resizable()
                                   .scaledToFit()
                                   .frame(maxHeight: 70)
                                   .padding()
                           Text("press on a day and you can see peoples schedules\n(minus any details for their privacy)")
                               .font(.caption)
                       }
                    Spacer()
                }
            }
        }
        .padding(16)
    }
}

#Preview {
    CalendarLegendView()
}
