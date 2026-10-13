from pathlib import Path

root = Path(__file__).resolve().parents[1]
session = (root / "Ultimafia/Features/Game/GameSession.swift").read_text()
view = (root / "Ultimafia/Features/Game/GameView.swift").read_text()

assert "VoteTally(votes: votes, hiddenVoterIds: hiddenVoterIds).count(for: target)" in session
assert session.count("let hiddenVoters = parseHiddenVoterIds(obj[\"votes\"])") == 2
assert "value is NSNull ? key : nil" in session
assert "meetings[idx].hiddenVoterIds.insert(voter)" in session
assert "meetings[idx].hiddenVoterIds.remove(voter)" in session
assert "!meeting.hiddenVoterIds.contains(voter)" in view
assert "let receivedCount = selectionIds.reduce(0) { $0 + meeting.count(for: $1) }" in view
assert 'Text("Vote targets are hidden.")' in view
assert "let targets = meeting.targets" in view
assert "let canTap = clickable && !locked" in view
assert "(isPlayer && !meeting.votesInvisible && !meeting.hiddenVoterIds.contains(target)) ? meeting.selections(of: target) : []" in view

print("verify_vote_wiring.py passed: hidden ballots, counts, server targets, vote gating, and invisible-target guard")
