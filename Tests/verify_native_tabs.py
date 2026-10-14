#!/usr/bin/env python3
"""Four-section wiring contract: no actions in the bar, one owner for its visibility, and one
stack per section. Source checks only — they do not measure the rendered bar or its animation."""
from pathlib import Path
import sys
root = Path(__file__).resolve().parents[1]
shell = (root/'Ultimafia/ContentView.swift').read_text()
model = (root/'Ultimafia/App/AppModel.swift').read_text()
section = (root/'Ultimafia/App/AppSection.swift').read_text()
tabs = (root/'Ultimafia/App/NativeAppTabs.swift').read_text()
sections = (root/'Ultimafia/App/AppSections.swift').read_text()
game = (root/'Ultimafia/Features/Game/GameView.swift').read_text()
host = (root/'Ultimafia/Features/Host/SetupSearchView.swift').read_text()
lobby = (root/'Ultimafia/Features/Lobby/LobbyView.swift').read_text()
checks = {
    'system tab controller owns the bar and its selection effect':
        'NativeAppTabs(' in shell and 'UITabBarController' in tabs
        and 'matchedGeometryEffect' not in shell and '.glassEffect' not in shell,
    'no separate custom bar strip below page content':
        'private var bar:' not in shell and 'bar.transition' not in shell,
    'three sections in a fixed order, every one a destination':
        'case play, game, you' in section
        and 'UMAppSection.allCases' in tabs
        and 'isDestination' not in tabs and 'case leave' not in tabs and 'case create' not in tabs,
    'each section keeps its own stack':
        all(decl in model for decl in ('var path: [Route] = []',
                                       'var gamePath: [Route] = []', 'var youPath: [Route] = []'))
        and '$app.gamePath' in sections and 'hostPath' not in model,
    're-selecting the visible section pops it to its root':
        'if section == target { popToRoot(target) } else { section = target }' in model,
    'one owner hides the bar, and only for a live game':
        'var showsAppTabs: Bool { !(section == .game && game != nil) }' in model
        and 'hideAppTabs' not in model and 'suppressAppBar' not in model
        and 'showsBar: app.showsAppTabs' in shell,
    'hosting is a lobby route, and never a reason to switch the bar off':
        'func openHost()' in model and 'case host' in model and 'app.openHost()' in lobby
        and 'suppressAppBar' not in host and 'for: .tabBar' not in host
        and 'HostSectionView' not in shell,
    'the game screen reaches the lobby while the bar is hidden':
        'app.goToLobby()' in game and 'Return to lobby' in game,
    'leaving is a toolbar action on the game screen':
        'app.requestLeave()' in game and 'showLeaveConfirm' in model,
    'one leave affordance, folded behind the header (!)':
        'leaveBtn' not in game and 'Label("Leave"' not in game
        and 'Image(systemName: "exclamationmark.circle")' in game
        and 'if leaveRevealed {' in game
        and 'Button("Leave Game", role: .destructive, action: onLeave)' not in game,
    'the panel row is drawn only when it has panels to switch':
        'if showsPanelTabs {' in game and 'showsGuides: threeColumns' in game
        and 'SetupGuidesButton(session: session, fillsWidth: false)' in game,
    'empty Game section explains itself instead of hiding':
        "You're not in a game" in sections,
    'mention badge retained':
        'badgeValue' in tabs and 'mentionBadge' in shell,
}
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {name}")
sys.exit(0 if all(checks.values()) else 1)
