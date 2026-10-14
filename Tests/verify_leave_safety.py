#!/usr/bin/env python3
"""Leave-safety contract: a seated game may only end through the confirmation rule, and a second
game must never start over a live one. Source checks only — they do not exercise the server or
the rendered dialogs."""
from pathlib import Path
import sys
root = Path(__file__).resolve().parents[1]
files = {
    'AppModel.swift': root/'Ultimafia/App/AppModel.swift',
    'ContentView.swift': root/'Ultimafia/ContentView.swift',
    'GameView.swift': root/'Ultimafia/Features/Game/GameView.swift',
    'ReadyCheck.swift': root/'Ultimafia/Features/Game/ReadyCheck.swift',
    'HostGameView.swift': root/'Ultimafia/Features/Host/HostGameView.swift',
    'SetupSearchView.swift': root/'Ultimafia/Features/Host/SetupSearchView.swift',
    'ProfileView.swift': root/'Ultimafia/Features/Profile/ProfileView.swift',
    'LobbyView.swift': root/'Ultimafia/Features/Lobby/LobbyView.swift',
}
text = {name: p.read_text() for name, p in files.items()}
model, shell = text['AppModel.swift'], text['ContentView.swift']
game, profile = text['GameView.swift'], text['ProfileView.swift']

calls = {}
for name, body in text.items():
    calls[name] = [(i, l.strip()) for i, l in enumerate(body.splitlines(), 1)
                   if 'leaveActiveGame' in l and 'func ' not in l]

# The confirmation overlay's own action legitimately calls the leave: that is what the user
# just confirmed. Everything else must go through requestLeave.
shell_lines = shell.splitlines()
overlay_start = next(i for i, l in enumerate(shell_lines, 1) if 'LeaveConfirmOverlay(' in l)
overlay_end = next(i for i in range(overlay_start, len(shell_lines) + 1)
                   if shell_lines[i - 1].strip() == ')')
overlay_span = set(range(overlay_start, overlay_end + 1))

checks = {
    'replacing a session never sends a leave':
        'prev.stop()' not in model and 'Never `stop()` here' in model,
    'leaveActiveGame is called only from the confirmation overlay':
        all(i in overlay_span for i, _ in calls['ContentView.swift'])
        and all(not calls[n] for n in ('GameView.swift', 'HostGameView.swift',
                                       'SetupSearchView.swift', 'ProfileView.swift')),
    'every Leave affordance asks through requestLeave':
        text['LobbyView.swift'].count('app.requestLeave()') == 2
        # One in the game screen: the header's Leave Game, revealed from the (!). The panel row at
        # the bottom carries no leave, and the lobby's own cards are the other two.
        and game.count('app.requestLeave()') == 1
        and 'onLeave: { app.requestLeave() }' in shell,
    'being seated refuses a second game instead of replacing it':
        "if let seated = seatedGameId, seated != id {" in model
        and 'already in a game. Leave it before spectating another.' in model,
    'hosting is refused while seated, early and at the server call':
        'app.seatedGameId != nil' in text['SetupSearchView.swift']
        and 'app.seatedGameId != nil' in text['HostGameView.swift'],
    'signing out while a live game runs confirms first':
        'leaveNeedsConfirm == true' in profile and 'Sign out and leave' in profile,
    'review teardown never sends a leave':
        'reviewSession?.disconnectWithoutLeaving()' in model and 'reviewSession?.stop()' not in model,
    'a refused action is actually shown to the user':
        'var alertMessage: String?' in model and 'app.alertMessage' in shell,
    'the header always offers a way out, and a seated player keeps their session':
        'onClose: returnToLobby, onLeave: onLeave' in game
        and 'if session.isReview || session.spectate { onDetach() }' in game,
}
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {name}")
print()
print("direct leaveActiveGame call sites:")
for name, sites in calls.items():
    for i, line in sites:
        where = ' (confirmation overlay action)' if name == 'ContentView.swift' and i in overlay_span else ''
        print(f"  {name}:{i}: {line}{where}")
sys.exit(0 if all(checks.values()) else 1)
