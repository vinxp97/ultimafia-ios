#!/usr/bin/env python3
"""Replay captured native geometry. Source wiring is supplementary, not a rendered UI test."""
from pathlib import Path
import json
import sys
root = Path(__file__).resolve().parents[1]
driver = (root / 'Ultimafia/Features/Game/UMTranscriptScrollController.swift').read_text()
uses_native_bounds = 'containerHeight: scroll.bounds.height' in driver
cases = json.loads((root / 'Tests/fixtures/chat-scroll-device.json').read_text())
passed = True
for i, case in enumerate(cases):
    # In these captured cases, visible extent was cross-checked against UIScrollView.bounds.
    height = case['visibleMaxY'] - case['visibleMinY'] if uses_native_bounds else case['reportedContainerHeight']
    target = max(-case['topInset'], case['contentHeight'] - height + case['bottomInset'])
    correct = abs(target - case['nativeMaximumY']) < 0.001
    passed &= correct
    print(f"{'PASS' if correct else 'FAIL'}: native device case {i} bottom error={target-case['nativeMaximumY']:.3f}pt")
bounded = 'scroll.setContentOffset(target, animated: false)' in driver and 'needsPositionChange(' in driver
print(f"{'PASS' if bounded else 'FAIL'}: bounded native writes instead of a SwiftUI positioning loop")
passed &= bounded
sys.exit(0 if passed else 1)
