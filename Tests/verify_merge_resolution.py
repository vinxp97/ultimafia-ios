#!/usr/bin/env python3
"""Merge-resolution contract for #5 rebased onto the #2/#3 tip.

Upstream #2 owns the game header's controls (returnToLobby + onLeave) and review #2's accepted
behaviour must survive; this branch owns the single leave rule and the four-section shell.
"""
from pathlib import Path
import sys
root = Path(__file__).resolve().parents[1]
game = (root/'Ultimafia/Features/Game/GameView.swift').read_text()
model = (root/'Ultimafia/App/AppModel.swift').read_text()
shell = (root/'Ultimafia/ContentView.swift').read_text()
checks = {
    'no conflict markers anywhere': all('<<<<<<< ' not in p
        and '>>>>>>> ' not in p for p in
        (game, model, shell)),
    'the header is wired with upstream\'s own controls':
        'GameHeader(session: session,' in game and 'onClose: returnToLobby, onLeave: onLeave' in game,
    'returnToLobby keeps a seated player connected but closes spectators/reviews':
        'if session.isReview || session.spectate { onDetach() }' in game
        and 'else { app.goToLobby() }' in game,
    'only one way back to the lobby in the header':
        game.count('app.goToLobby()') == 1 and 'accessibilityLabel("Back to lobby")' not in game,
    'the seated leave goes through the single rule':
        'onLeave: { app.requestLeave() }' in game,
    "upstream's header controls still reach the screen (a way back, and a leave)":
        'onClose: returnToLobby, onLeave: onLeave' in game
        and 'Button(action: onClose)' in game
        and 'Button(role: .destructive, action: onLeave)' in game
        and 'Button("Return to Lobby", action: onClose)' not in game,
    'the leave rule stays in the model, not duplicated in the view':
        'func requestLeave()' in model and 'session.leaveNeedsConfirm' not in game,
}
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {name}")
sys.exit(0 if all(checks.values()) else 1)
