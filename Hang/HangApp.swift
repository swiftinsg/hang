//
//  HangApp.swift
//  Hang
//
//  Created by Lim Shi Hui Serene on 11/11/26.
//

import SwiftUI
import FirebaseCore
import FirebaseSignInWithApple

@main
struct SwiftChallenge2App: App {
    init() {
        FirebaseApp.configure()
        print("configured Firebase")
        Self.configureRoundedSystemFonts()
    }

    /// SwiftUI's `.fontDesign(.rounded)` only reaches text SwiftUI draws.
    /// Navigation-bar titles and tab-bar labels are drawn by UIKit, so they
    /// need their fonts set through the UIKit appearance proxies instead.
    static func configureRoundedSystemFonts() {
        let nav = UINavigationBarAppearance()
        nav.titleTextAttributes = [
            .font: roundedFont(size: 17, weight: .semibold)
        ]
        nav.largeTitleTextAttributes = [
            .font: roundedFont(size: 34, weight: .bold)
        ]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav

        UITabBarItem.appearance().setTitleTextAttributes(
            [.font: roundedFont(size: 10, weight: .medium)],
            for: .normal
        )
    }

    /// Builds a rounded UIFont at a given size and weight. SwiftUI exposes
    /// `.fontDesign(.rounded)` as a view modifier, but UIKit (which draws
    /// navigation and tab bars) needs a real UIFont with the rounded design
    /// applied through its descriptor.
    private static func roundedFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let descriptor = UIFont.systemFont(ofSize: size, weight: weight)
            .fontDescriptor
            .withDesign(.rounded)
        return UIFont(descriptor: descriptor ?? UIFont.systemFont(
            ofSize: size, weight: weight
        ).fontDescriptor, size: size)
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .tint(Color("AccentColor"))
                .fontDesign(.rounded)
                // FirebaseSignInWithApple creates users/<uid> for every new account
                .configureFirebaseSignInWithAppleWith(firestoreUserCollectionPath: Path.Firestore.Users)
        }
    }
}
