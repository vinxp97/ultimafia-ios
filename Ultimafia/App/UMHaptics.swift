import UIKit

/// Haptic feedback used across the app.
enum UMHaptics {
    /// Light tap when a chat line is quoted.
    static func quoteTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Firm Haptic Touch-style thump when a press-and-hold triggers (e.g. hold the back arrow to leave).
    static func holdTriggered() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1.0)
    }
}
