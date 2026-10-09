import SwiftUI

extension View {
    /// Lets Magic Keyboard / trackpad two-finger pans drive this scroll view.
    func pointerScrolling() -> some View {
        self
            .scrollBounceBehavior(.always)
            .scrollIndicators(.automatic)
    }
}
