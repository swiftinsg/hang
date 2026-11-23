//
//  AnimationView.swift
//  Hang
//
//  Created by T Krobot on 20/11/26.
//

import SwiftUI

public enum LoadScreen {
    case login
    case authentication
    case loadGroup
}

struct AnimationView: View {
    var screenType: LoadScreen
    @State var screenSize: CGSize = .zero
    var body: some View {
        ZStack {
            Color(.clear)
                .ignoresSafeArea()
            switch(screenType) {
            case .login:
                LogAnim(size: screenSize, time: 1.5, time2: 0.3, text: "Logging in")
            case .authentication:
                LogAnim(size: screenSize, time: 1.5, time2: 0.3, text: "Authenticating")
            case .loadGroup:
                GroupAnim(size: screenSize, time: 0.075, time2: 0.3, text: "Loading")
            }
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            screenSize = newSize
        }
    }
}

#Preview {
    AnimationView(screenType: .authentication)
}

struct LogAnim: View {
    var size: CGSize
    var time: CGFloat
    var time2: CGFloat
    var text: String
    @State var xoff: CGFloat = .zero
    @State var rotation: CGFloat = 1
    @State var shownText: String = ""
    var body: some View {
        VStack {
            ZStack {
                Image("logImage")
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(x: 1, y: 0.9)
                    .frame(maxWidth: size.width*0.5)
                Image("loginHangImage")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: size.width*0.15)
                    .scaleEffect(x: rotation, y: 1)
                    .offset(x: xoff, y: -size.width*0.08)
            }
            .task(id: size) {
                await repeater(action: {
                    await animacro(ease: .easeInOut(duration: 0.15), first: {rotation = 1}, delay: 0)
                    await animacro(ease: .easeInOut(duration: time), first: {xoff = -size.width*0.06}, delay: time, next: {
                        await animacro(ease: .easeInOut(duration: 0.15), first: {rotation = -1}, delay: 0)
                        await animacro(ease: .easeInOut(duration: time), first: {xoff = size.width*0.18}, delay: time)
                    })
                }, delay: 0)
            }
            ZStack (alignment: .leading) {
                Text("\(text)...")
                    .hidden()
                Text(shownText)
                    .foregroundStyle(.primary)
            }
            .fontDesign(.rounded)
            .font(.system(size: size.width*0.06, weight: .medium))
            .padding(-size.width*0.04)
            .task(id: size) {
                await repeater(action: {
                    await animacro(first: {shownText = "\(text)."}, delay: time2)
                    await animacro(first: {shownText = "\(text).."}, delay: time2)
                    await animacro(first: {shownText = "\(text)..."}, delay: time2)
                }, delay: 0)
            }
        }
    }
}

struct GroupAnim: View {
    var size: CGSize
    var time: CGFloat
    var time2: CGFloat
    var text: String
    @State var state: Int = 0
    @State var selfSize: CGSize = .zero
    @State var shownText: String = ""
    @State var frames: Array<Image> = [
        Image("groupframe1"),
        Image("groupframe2"),
        Image("groupframe3"),
        Image("groupframe4"),
        Image("groupframe5"),
        Image("groupframe6"),
        Image("groupframe7"),
        Image("groupframe8"),
        Image("groupframe9"),
        Image("groupframe10"),
        Image("groupframe11")
    ]
    var body: some View {
        VStack {
            frames[state]
                .resizable()
                .scaledToFit()
                .onGeometryChange(for: CGSize.self) { proxy in proxy.size } action: { newSize in selfSize = newSize }
                .task(id: size) {
                    await repeater(action: {
                        if state < frames.count-1 {
                            state += 1
                        } else {
                            state = 0
                        }
                    }, delay: time)
                }
            ZStack (alignment: .leading) {
                Text("\(text)...")
                    .hidden()
                Text(shownText)
                    .foregroundStyle(Color.black)
            }
            .fontDesign(.rounded)
            .font(.system(size: selfSize.width*0.15, weight: .medium))
            .padding(selfSize.height*0.05)
            .task(id: size) {
                await repeater(action: {
                    await animacro(first: {shownText = "\(text)."}, delay: time2)
                    await animacro(first: {shownText = "\(text).."}, delay: time2)
                    await animacro(first: {shownText = "\(text)..."}, delay: time2)
                }, delay: 0)
            }
            
        }
        .frame(maxWidth: size.width*0.35, maxHeight: size.height*0.5)
        
    }
}

public func repeater(action: @escaping @MainActor () async -> Void, delay: CGFloat, reps: Double? = .infinity, esc: Binding<Bool>? = nil) async {
    var i = 0.0
    while !Task.isCancelled && i < (reps ?? .infinity) && !(esc?.wrappedValue ?? false) {
        await action()
        try? await Task.sleep(for: .seconds(delay))
        i += 1
    }
    
}

public func animacro(ease: Animation? = nil, first: @escaping @MainActor () -> Void, delay: CGFloat, next: (@MainActor () async -> Void)? = nil) async {
    guard !Task.isCancelled else { return }
    withAnimation(ease) {
        first()
    }
    try? await Task.sleep(for: .seconds(delay))
    await next?()
    
}


