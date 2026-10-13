import Foundation

/// Counts received votes without attributing ballots whose target is hidden by the server.
struct VoteTally {
    private let counts: [String: Int]

    init(votes: [String: [String]], hiddenVoterIds: Set<String> = []) {
        var counts: [String: Int] = [:]
        for (voterId, targets) in votes where !hiddenVoterIds.contains(voterId) {
            for target in targets {
                counts[target, default: 0] += 1
            }
        }
        self.counts = counts
    }

    func count(for target: String) -> Int {
        counts[target, default: 0]
    }
}
