#!/usr/bin/env python3
"""Native-scroll and phase-memory source checks; not a rendered UI test."""
from pathlib import Path
import sys
root=Path(__file__).resolve().parents[1]
game=(root/'Ultimafia/Features/Game/GameView.swift').read_text()
pane=game.split('private struct GameChatPane: View {',1)[1].split('private struct ChatComposer: View {',1)[0]
controller=root/'Ultimafia/Features/Game/UMTranscriptScrollController.swift'
driver=controller.read_text() if controller.exists() else ''
checks={
    'native controller owns continuous following': 'UMTranscriptScrollController()' in pane and '.onScrollGeometryChange' not in pane and '.defaultScrollAnchor' not in pane,
    'offsets use real UIKit bounds and adjusted insets': 'containerHeight: scroll.bounds.height' in driver and 'scroll.adjustedContentInset' in driver,
    'per-phase anchors and pinned state remain intact': 'session.phasePinned[oldPhase] = transcriptScroll.isFollowingLatest' in pane and 'session.phaseScrollAnchors[phase] = first' in pane,
    'past phases restore anchors or top without following': 'restorePhasePosition(anchor: anchor, phase: newPhase' in pane and 'transcriptScroll.pauseFollowing()' in pane and 'restoreGeneration == generation' in pane,
    'latest-button visibility uses actual native bottom': 'if !transcriptScroll.isAtBottom, !session.isReview' in pane,
    'content shrinking under the offset is still put back, and logged':
        'scroll.contentOffset.y > bounds.maximumY + 24' in driver
        and 'bounds.clampedY(scroll.contentOffset.y)' in driver and 'past end' in driver,
    'floating composer is retained': '.contentMargins(.bottom, composerOverlayHeight' in pane and 'if !show { composerOverlayHeight = 0 }' in pane,
}
for name,ok in checks.items(): print(f"{'PASS' if ok else 'FAIL'}: {name}")
sys.exit(0 if all(checks.values()) else 1)
