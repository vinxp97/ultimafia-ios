import Foundation

@main
struct TranscriptFollowPolicyTests {
    static func main() {
        var policy = UMTranscriptFollowPolicy()
        expect(policy.action(userIsScrolling: false, atBottom: true) == .bottom, "idle transcript follows latest")
        expect(policy.action(userIsScrolling: true, atBottom: false) == .none && !policy.isFollowingLatest,
               "manual upward drag stops following")
        expect(policy.action(userIsScrolling: false, atBottom: false) == .none, "history remains stationary when layout changes")
        policy.requestLatest()
        expect(policy.action(userIsScrolling: true, atBottom: false) == .bottom && policy.isFollowingLatest,
               "latest button overrides ongoing deceleration")
        expect(policy.action(userIsScrolling: false, atBottom: true) == .bottom, "following survives arrival")
        policy.requestTop()
        expect(policy.action(userIsScrolling: false, atBottom: false) == .top && !policy.isFollowingLatest,
               "review/top request does not enable bottom following")
        _ = policy.action(userIsScrolling: true, atBottom: true)
        expect(policy.isFollowingLatest, "manually reaching bottom resumes following")
        policy.pauseFollowing()
        expect(policy.action(userIsScrolling: false, atBottom: false) == .none, "restoring history suppresses following")
        expect(!UMTranscriptFollowPolicy.needsPositionChange(currentX: 0, currentY: 100, targetX: 0, targetY: 100),
               "settled frames never write another offset")
        expect(UMTranscriptFollowPolicy.needsPositionChange(currentX: 12, currentY: 100, targetX: 0, targetY: 100),
               "native horizontal displacement is corrected")
        expect(UMTranscriptFollowPolicy.needsPositionChange(currentX: 0, currentY: 90, targetX: 0, targetY: 100),
               "real distance to bottom is corrected")
        expect(!UMTranscriptFollowPolicy.needsPositionChange(currentX: 0, currentY: 100.00001, targetX: 0, targetY: 100),
               "floating point noise never creates a positioning loop")
        policy.requestLatest()
        expect(policy.action(userIsScrolling: false, atBottom: false, allowsFollowingLatest: false) == .bottom,
               "past phase permits a one-shot explicit bottom request")
        expect(!policy.isFollowingLatest, "past phase never keeps following latest")
        expect(policy.action(userIsScrolling: false, atBottom: true, allowsFollowingLatest: false) == .none,
               "past-phase idle layout changes never repin to bottom")
        expect(policy.action(userIsScrolling: true, atBottom: true, allowsFollowingLatest: false) == .none && !policy.isFollowingLatest,
               "reaching the end of a past phase cannot resume live following")
    }
    static func expect(_ condition: Bool, _ message: String) {
        guard condition else { print("FAIL: \(message)"); exit(1) }
        print("PASS: \(message)")
    }
}
