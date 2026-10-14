#!/usr/bin/env python3
"""Native-scroll and phase-memory source checks; not a rendered UI test."""
from pathlib import Path
import sys
root=Path(__file__).resolve().parents[1]
game=(root/'Ultimafia/Features/Game/GameView.swift').read_text()
pane=game.split('private struct GameChatPane: View {',1)[1].split('private struct ChatComposer: View {',1)[0]
controller=root/'Ultimafia/Features/Game/UMTranscriptScrollController.swift'
driver=controller.read_text() if controller.exists() else ''
session=(root/'Ultimafia/Features/Game/GameSession.swift').read_text()
haptics_file=root/'Ultimafia/App/UMHaptics.swift'
haptics=haptics_file.read_text() if haptics_file.exists() else ''
checks={
    'native controller owns continuous following': 'UMTranscriptScrollController()' in pane and '.onScrollGeometryChange' not in pane and '.defaultScrollAnchor' not in pane,
    'offsets use real UIKit bounds and adjusted insets': 'containerHeight: scroll.bounds.height' in driver and 'scroll.adjustedContentInset' in driver,
    'per-phase anchors and pinned state remain intact': 'session.phasePinned[oldPhase] = transcriptScroll.isFollowingLatest' in pane and 'session.phaseScrollAnchors[phase] = first' in pane,
    'past phases restore anchors or top without following': 'restorePhasePosition(anchor: anchor, phase: newPhase' in pane and 'transcriptScroll.pauseFollowing()' in pane and 'restoreGeneration == generation' in pane,
    'latest-button visibility uses actual native bottom': 'if !transcriptScroll.isAtBottom, !session.isReview' in pane,
    'quoting keeps your place instead of following your own quote':
        'if mine, last.isQuote, !transcriptScroll.isFollowingLatest { return }' in game,
    'leaving the chat and coming back keeps its position':
        'isOnScreen: selectedPanel == 0' in game and 'guard isOnScreen else { return }' in game
        and 'switch selectedPanel {' not in game,
    'a row arriving while following is not drawn behind the composer':
        'func applyPendingNow()' in driver and 'transcriptScroll.applyPendingNow()' in pane,
    'the transcript bottom moves with the composer in the same pass':
        'composerOverlayHeight = height' in pane and pane.count('applyPendingNow()') == 2,
    'the quote double tap gets one haptic, and stays silent when it cannot quote':
        'guard session.canQuote(line) else { return }' in game and 'UMHaptics.quoteTapped()' in game
        and 'func canQuote(_ line: ChatLine) -> Bool' in session
        and 'UIImpactFeedbackGenerator(style: .light).impactOccurred()' in haptics,
    'content shrinking under the offset is still put back, and logged':
        'scroll.contentOffset.y > bounds.maximumY + 24' in driver
        and 'bounds.clampedY(scroll.contentOffset.y)' in driver and 'past end' in driver,
    'floating composer is retained': '.contentMargins(.bottom, composerOverlayHeight' in pane and 'if !show { composerOverlayHeight = 0 }' in pane,
}
for name,ok in checks.items(): print(f"{'PASS' if ok else 'FAIL'}: {name}")
sys.exit(0 if all(checks.values()) else 1)
