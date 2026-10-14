import Foundation

/// Legal vertical content offsets. Both bottom detection and scroll commands use these bounds.
struct ChatScrollBounds: Equatable {
    var contentHeight: CGFloat
    var containerHeight: CGFloat
    var topInset: CGFloat
    var bottomInset: CGFloat
    var leadingInset: CGFloat = 0

    var minimumX: CGFloat { -leadingInset }
    var minimumY: CGFloat { -topInset }
    var maximumY: CGFloat { max(minimumY, contentHeight - containerHeight + bottomInset) }

    func clampedY(_ offset: CGFloat) -> CGFloat {
        min(maximumY, max(minimumY, offset))
    }

    func isAtBottom(offsetY: CGFloat) -> Bool {
        offsetY >= maximumY - 0.5
    }
}
