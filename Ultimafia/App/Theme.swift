import SwiftUI

enum UMTheme {
    static let bg = Color(red: 0.07, green: 0.07, blue: 0.07)
    static let card = Color(red: 0.12, green: 0.12, blue: 0.13)
    static let elevated = Color(red: 0.16, green: 0.16, blue: 0.17)
    static let blood = Color(red: 0.76, green: 0.22, blue: 0.17)
    static let village = Color(red: 0.45, green: 0.72, blue: 0.45)
    static let mafia = Color(red: 0.85, green: 0.28, blue: 0.28)
    static let muted = Color.white.opacity(0.55)
    static let roleMention = Color(red: 0.98, green: 0.82, blue: 0.22)
    static let line = Color.white.opacity(0.08)
}

extension View {
    @ViewBuilder
    func umKeyboardEmail() -> some View {
        #if os(iOS) || os(visionOS)
        self.keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    @ViewBuilder
    func umPagedTabs() -> some View {
        #if os(iOS) || os(visionOS)
        self.tabViewStyle(.page(indexDisplayMode: .never))
        #else
        self
        #endif
    }

    @ViewBuilder
    func umTabBarBackground(_ color: Color) -> some View {
        #if os(iOS) || os(visionOS)
        self.toolbarBackground(color, for: .tabBar)
        #else
        self
        #endif
    }

    @ViewBuilder
    func umHideBackButton() -> some View {
        #if os(iOS) || os(visionOS)
        self.navigationBarBackButtonHidden(true)
        #else
        self
        #endif
    }
}
