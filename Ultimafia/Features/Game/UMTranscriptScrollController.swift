#if canImport(UIKit)
import SwiftUI
import UIKit
import Observation

/// Controls the actual transcript UIScrollView without replacing SwiftUI's delegate.
/// Geometry callbacks are observational only; they never feed position commands back into SwiftUI.
@MainActor @Observable
final class UMTranscriptScrollController {
    private(set) var isFollowingLatest = true
    private(set) var isAtBottom = true
    private(set) var isAtTop = true
    @ObservationIgnored private weak var scroll: UIScrollView?
    @ObservationIgnored private var policy = UMTranscriptFollowPolicy()
    @ObservationIgnored private var followsLivePhase = true
    /// One diagnostics line per past-the-end episode, so a self-correction shows up in a trace.
    @ObservationIgnored private var reportedPastEnd = false

    func setFollowingAllowed(_ allowed: Bool) {
        guard followsLivePhase != allowed else { return }
        followsLivePhase = allowed
        if !allowed { pauseFollowing() }
        if let scroll { refresh(scroll) }
    }

    func requestLatest() {
        policy.requestLatest()
        if let scroll { refresh(scroll) }
    }

    func requestTop() {
        policy.requestTop()
        if let scroll { refresh(scroll) }
    }

    func pauseFollowing() {
        policy.pauseFollowing()
        if isFollowingLatest { isFollowingLatest = false }
    }

    /// Apply the pending state right now instead of waiting for the next per-frame sample. Used when
    /// a row arrives while following: the row is laid out during the same update pass that requests
    /// the scroll, so the display-link tick that follows is one frame too late, and the row spends
    /// that frame drawn behind the floating composer.
    func applyPendingNow() {
        if let scroll { refresh(scroll) }
    }

    fileprivate func refresh(_ scroll: UIScrollView) {
        self.scroll = scroll
        let inset = scroll.adjustedContentInset
        let bounds = ChatScrollBounds(
            contentHeight: scroll.contentSize.height,
            containerHeight: scroll.bounds.height,
            topInset: inset.top,
            bottomInset: inset.bottom,
            leadingInset: inset.left
        )
        let atBottom = scroll.contentOffset.y >= bounds.maximumY - 2
        // Content can shrink under the offset (a shorter phase, or the join history batch replacing
        // what was laid out with rows that measure smaller than their estimates). The view then sat
        // past the end, showing an empty chat until the user dragged. Sampling the real bounds every
        // frame is exactly where that is visible, so put the offset back instead of waiting for a drag.
        if scroll.contentOffset.y > bounds.maximumY + 24 {
            if !reportedPastEnd, !(scroll.isDragging || scroll.isDecelerating) {
                reportedPastEnd = true
                UMDiag.log("scroll", "past end (content \(Int(bounds.contentHeight)) container \(Int(bounds.containerHeight))), snapping back")
                scroll.setContentOffset(CGPoint(x: bounds.minimumX, y: bounds.clampedY(scroll.contentOffset.y)), animated: false)
            }
        } else if reportedPastEnd {
            reportedPastEnd = false
        }
        let action = policy.action(
            userIsScrolling: scroll.isDragging || scroll.isDecelerating,
            atBottom: atBottom,
            allowsFollowingLatest: followsLivePhase
        )
        if action != .none {
            let target = CGPoint(x: bounds.minimumX, y: action == .top ? bounds.minimumY : bounds.maximumY)
            if UMTranscriptFollowPolicy.needsPositionChange(
                currentX: scroll.contentOffset.x, currentY: scroll.contentOffset.y,
                targetX: target.x, targetY: target.y
            ) {
                scroll.setContentOffset(target, animated: false)
            }
        }
        let bottom = scroll.contentOffset.y >= bounds.maximumY - 2
        let top = scroll.contentOffset.y <= bounds.minimumY + 2
        if isAtBottom != bottom { isAtBottom = bottom }
        if isAtTop != top { isAtTop = top }
        if isFollowingLatest != policy.isFollowingLatest { isFollowingLatest = policy.isFollowingLatest }
    }
}

/// A transparent content background that locates the native scroll view and checks it once per frame.
struct UMTranscriptScrollBridge: UIViewRepresentable {
    var controller: UMTranscriptScrollController

    func makeUIView(context: Context) -> BridgeView {
        let view = BridgeView()
        view.controller = controller
        return view
    }
    func updateUIView(_ uiView: BridgeView, context: Context) { uiView.controller = controller }

    final class TickTarget: NSObject {
        weak var view: BridgeView?
        @objc func tick(_ link: CADisplayLink) { view?.sample() }
    }

    final class BridgeView: UIView {
        var controller: UMTranscriptScrollController?
        private let target = TickTarget()
        private var link: CADisplayLink?
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            target.view = self
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            link?.invalidate()
            link = nil
            guard let window else { return }
            let next = CADisplayLink(target: target, selector: #selector(TickTarget.tick(_:)))
            let rate = Float(window.screen.maximumFramesPerSecond)
            next.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: rate, preferred: rate)
            next.add(to: .main, forMode: .common)
            link = next
        }
        func sample() {
            guard window != nil else { return }
            var node = superview
            while let view = node, !(view is UIScrollView) { node = view.superview }
            if let scroll = node as? UIScrollView { controller?.refresh(scroll) }
        }
        deinit { link?.invalidate() }
    }
}
#endif
