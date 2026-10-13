#!/usr/bin/env python3
"""Focused checks for xtool resource wiring and documented asset omissions."""
from pathlib import Path
import plistlib
import re

ROOT = Path(__file__).resolve().parents[1]
manifest = (ROOT / "Package.swift").read_text()
config = (ROOT / "xtool.yml").read_text()
readme = (ROOT / "README.md").read_text()
project = (ROOT / "Ultimafia.xcodeproj/project.pbxproj").read_text()

assert '"Assets.xcassets"' in manifest, "SwiftPM must exclude the unsupported asset catalog"
assert '"PrivacyInfo.xcprivacy"' in manifest, "privacy manifest must not be an unhandled SwiftPM input"
assert "Ultimafia/PrivacyInfo.xcprivacy" in config, "xtool must package the privacy manifest"
plistlib.loads((ROOT / "Ultimafia/PrivacyInfo.xcprivacy").read_bytes())
assert '"UMTerminology.json"' in manifest
assert "Ultimafia/UMTerminology.json" in config

for resource in ("Sounds", "Fonts", "RoleIcons"):
    assert f"Ultimafia/{resource}" in config, f"missing xtool resource: {resource}"
    assert (ROOT / "Ultimafia" / resource).is_dir(), f"resource directory missing: {resource}"

icon = re.search(r"^iconPath:\s*(\S+)\s*$", config, re.MULTILINE)
assert icon, "xtool iconPath is required"
assert (ROOT / icon.group(1)).is_file(), "standalone xtool icon file is missing"
assert "com.ue2020.ultimafia.dev" in config
assert "PRODUCT_BUNDLE_IDENTIFIER = VCCCLLC.Ultimafia;" in project
assert "Associated Domains" in readme
assert "iCloud Key-Value Store" in readme
assert "declared-age-range" in readme
assert "cp Secrets.swift.template Ultimafia/App/Secrets.swift" in readme
assert "do not commit or publish it" in readme

catalog_dirs = {p.name for p in (ROOT / "Ultimafia/Assets.xcassets").iterdir() if p.is_dir()}
expected = {
    "AccentColor.colorset", "AppIcon.appiconset", "AppLogo.imageset",
    "Logo-default.imageset", "Logo-halloween.imageset", "Logo-july.imageset",
    "Logo-pride.imageset", "Logo-thanksgiving.imageset", "Logo-valentines.imageset",
    "Logo-winter.imageset", "Trophy-bronze.imageset", "Trophy-crown.imageset",
    "Trophy-gold.imageset", "Trophy-silver.imageset",
}
assert catalog_dirs == expected, f"catalog contents changed; review exclusions: {sorted(catalog_dirs ^ expected)}"
for name in ("AccentColor", "AppIcon", "AppLogo", "Logo-*", "Trophy-*"):
    assert f"`{name}`" in readme, f"README omits excluded catalog item {name}"
assert "AppIcon-1024.png" in readme and "iconPath" in readme

print("PASS: privacy manifest plist parses and is wired as a resource, not an unhandled SwiftPM input")
print("PASS: xtool resource directories and standalone icon exist")
print(f"PASS: README documents all {len(catalog_dirs)} excluded asset-catalog groups and standalone icon behavior")
print("PASS: development bundle ID, preserved Xcode bundle ID, entitlements, and Secrets setup are documented")
