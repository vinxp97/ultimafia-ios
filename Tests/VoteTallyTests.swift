import Foundation

@main
struct VoteTallyTests {
    static func main() {
        let tally = VoteTally(
            votes: ["v1": ["alice"], "v2": ["alice", "bob"], "v3": ["bob"]],
            hiddenVoterIds: ["v2"]
        )
        precondition(tally.count(for: "alice") == 1, "hidden ballots must not expose their target in counts")
        precondition(tally.count(for: "bob") == 1, "visible ballots should be counted")
        precondition(tally.count(for: "nobody") == 0, "missing targets have zero votes")
        print("VoteTallyTests passed: visible tally, hidden ballot exclusion, absent target")
    }
}
