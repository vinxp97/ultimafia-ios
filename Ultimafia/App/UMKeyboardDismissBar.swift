import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// App-wide keyboard accessory for SwiftUI text inputs: a slim bar with a chevron.down that hides
/// the keyboard (the tab bar sits at the bottom, so there's otherwise no way out).
/// The in-game composer (UMComposerField, a UIKit text view) doesn't receive SwiftUI keyboard
/// toolbars, so it keeps only its own chevron toggle.
struct UMKeyboardDismissBar: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        content
        #else
        content
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(UMTheme.muted)
                    }
                    .accessibilityLabel("Hide keyboard")
                }
            }
        #endif
    }
}

extension View {
    func umKeyboardDismissBar() -> some View { modifier(UMKeyboardDismissBar()) }
}
