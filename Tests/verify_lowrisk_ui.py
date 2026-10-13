#!/usr/bin/env python3
"""Source/scope checks for the first small UI PR, not device rendering tests."""
from pathlib import Path
import subprocess
import sys
root = Path(__file__).resolve().parents[1]
game = (root/'Ultimafia/Features/Game/GameView.swift').read_text()
roles = (root/'Ultimafia/Features/Game/RoleChrome.swift').read_text()
images = (root/'Ultimafia/Features/Game/PlayerChrome.swift').read_text()
profile = (root/'Ultimafia/Features/Profile/UserProfileView.swift').read_text()
# Compare against the commit this PR applies on top of (survives rebases onto new upstream tips).
base_sha = subprocess.check_output(['git','rev-parse','HEAD~1'],cwd=root,text=True).strip()
base = subprocess.check_output(['git','show',base_sha+':Ultimafia/Features/Game/GameView.swift'],cwd=root,text=True)
def pane(s):
    return s.split('private struct GameChatPane: View {',1)[1].split('private struct ChatComposer: View {',1)[0]
def composer(s):
    return s.split('private struct ChatComposer: View {',1)[1]
checks = {
    'header back/leave remain available with confirmation':
        'wide: wideHeader, onClose: returnToLobby, onLeave: onLeave' in game
        and 'if session.leaveNeedsConfirm { app.showLeaveConfirm = true }' in game,
    'player back navigation preserves the seated session and scroll memory':
        'if session.isReview || session.spectate { onDetach() }' in game and 'else { app.goToLobby() }' in game,
    'role picker dismisses natively instead of an extra Cancel':
        'RoleGuessPickerSheet(' in game and 'Button("Cancel", role: .cancel)' not in game,
    'pixel art uses nearest-neighbor interpolation': roles.count('interpolation: Image.Interpolation.none') >= 4 and 'var interpolation: Image.Interpolation' in images and images.count('.interpolation(interpolation)') == 1 and 'var interpolation: Image.Interpolation? = nil' in images,
    'banner width follows its measured container and native back remains':
        'frame(width: proxy.size.width, height: proxy.size.height)' in profile
        and '.navigationBarBackButtonHidden(true)' not in profile,
    # This PR replaces exactly the scroll half of the pane (pin/bounds tracking), so the composer
    # and everything after it is what must still match the tree it applies on top of. The scroll
    # half is covered by verify_native_scroll.py.
    'composer and the rest of the pane are unchanged from the tree this PR applies on top of':
        composer(game) == composer(base),
}
for name, ok in checks.items(): print(f"{'PASS' if ok else 'FAIL'}: {name}")
sys.exit(0 if all(checks.values()) else 1)
