//
//  MainView.swift
//  Hang
//
//  Created by Lim Shi Hui Serene     on 11/11/26.
//

import SwiftUI
import FirebaseSignInWithApple

struct MainView: View {
    
    @Environment(\.firebaseSignInWithApple) private var firebaseSignInWithApple
    
    var body: some View {
        Group{
            switch firebaseSignInWithApple.state {
            case .loading:
                AnimationView(screenType: .login)
//                ProgressView()
            case .authenticating:
                AnimationView(screenType: .authentication)
//                ProgressView()
            case .notAuthenticated:
                AuthView()
            case .authenticated:
                ContentView()
            }
        }
        .fontDesign(.rounded)
        .onChange(of: firebaseSignInWithApple.state) { oldValue, newValue in print("FirebaseSignInWithApple state changed from \(oldValue) to \(newValue)")}
        
    }
}

#Preview("Signed out") {
    let auth = FirebaseSignInWithAppleKey.defaultValue
    auth.state = .notAuthenticated

    return MainView()
        .environment(\.firebaseSignInWithApple, auth)
}
