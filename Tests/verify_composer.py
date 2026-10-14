#!/usr/bin/env python3
"""Composer source contract; visual behavior still requires device checks."""
from pathlib import Path
import sys
root=Path(__file__).resolve().parents[1]
game=(root/'Ultimafia/Features/Game/GameView.swift').read_text()
editor=(root/'Ultimafia/Features/Game/UMComposerField.swift').read_text()
checks={
    'eight-line cap, and an empty draft measured exactly like a typed line':
        'static let maxLines = 8' in editor and 'let sample = text.isEmpty ? "Ag" : text' in editor,
    'stock iPad keyboard assistant remains untouched': 'inputAssistantItem' not in editor and 'GCKeyboard' not in editor and 'reloadInputViews' not in editor,
    'composer floats over content without opaque bottom strip':
        "Only the composer's own controls draw a glass" in game
        and '.contentMargins(.bottom, composerOverlayHeight' in game,
    'the keyboard toggle is a glass bubble like the Say pill': game.count('.glassEffect(') == 3,
    'the last line sits close under the floating composer':
        'The last line sits close under the floating composer' in game,
    'separate Say pill matches idle height and Return sends': '.frame(width: 52, height: composerIdleHeight)' in game and 'onReturn: send' in game and 'Button(action: send)' not in game,
    'phase memory remains intact with either follow engine': ('session.phasePinned[oldPhase] = stickToBottom' in game or 'session.phasePinned[oldPhase] = transcriptScroll.isFollowingLatest' in game) and 'session.phaseScrollAnchors[phase] = first' in game,
}
for name,ok in checks.items(): print(f"{'PASS' if ok else 'FAIL'}: {name}")
sys.exit(0 if all(checks.values()) else 1)
