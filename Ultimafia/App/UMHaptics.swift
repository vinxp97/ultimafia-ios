import UIKit

/// Haptic feedback used across the app.
enum UMHaptics {
    /// Light tap when a chat line is quoted.
    static func quoteTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
