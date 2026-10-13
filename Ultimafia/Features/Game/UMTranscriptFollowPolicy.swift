import Foundation

struct UMTranscriptFollowPolicy {
    enum Action { case none, bottom, top }
    private(set) var isFollowingLatest = true
    private var requested: Action = .none

    mutating func requestLatest() { requested = .bottom; isFollowingLatest = true }
    mutating func requestTop() { requested = .top; isFollowingLatest = false }
    mutating func pauseFollowing() { requested = .none; isFollowingLatest = false }

    mutating func action(userIsScrolling: Bool, atBottom: Bool, allowsFollowingLatest: Bool = true) -> Action {
        if requested != .none {
            let action = requested
            requested = .none
            if !allowsFollowingLatest { isFollowingLatest = false }
            return action
        }
        guard allowsFollowingLatest else {
            isFollowingLatest = false
            return .none
        }
        if userIsScrolling {
            isFollowingLatest = atBottom
            return .none
        }
        return isFollowingLatest ? .bottom : .none
    }

    static func needsPositionChange(currentX: CGFloat, currentY: CGFloat, targetX: CGFloat, targetY: CGFloat) -> Bool {
        abs(currentX - targetX) > 0.5 || abs(currentY - targetY) > 0.5
    }
}
