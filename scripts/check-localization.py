#!/usr/bin/env python3
"""
Localization coverage check for RodaAi.

Verifies that:
1. Every dot-notation key referenced in Sources/RodaAi/**/*.swift exists in
   Localizable.xcstrings.
2. Every key in xcstrings has both pt-BR and en translations.
3. Reports extra (unused) keys as warnings.

Run: python3 scripts/check-localization.py
Exit codes:
  0 = all checks passed (warnings allowed)
  1 = missing keys or missing translations (failure)

This script exists because the SwiftPM test target for RodaAi cannot link
mlx-swift-lm's Hub framework cleanly when running as a unit test on macOS.
We get the same coverage check via Python instead.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).parent.parent
XCSTRINGS = ROOT / "Sources/RodaAi/Resources/Localizable.xcstrings"
SOURCES = ROOT / "Sources/RodaAi"

# Top-level namespaces we treat as localization keys.
# Keys outside these namespaces are NOT considered localization references
# (e.g. UTType identifiers, image asset names, bundle identifiers).
LOC_NAMESPACES = {
    "tab", "app", "chat", "model", "voice",
    "conversation", "settings", "onboarding", "common"
}

# Pattern to match dot-notation strings inside double quotes.
KEY_PATTERN = re.compile(r'"([a-z][a-zA-Z]+(?:\.[a-zA-Z][a-zA-Z0-9]+)+)"')


def main() -> int:
    if not XCSTRINGS.exists():
        print(f"❌ xcstrings file not found: {XCSTRINGS}", file=sys.stderr)
        return 1

    with open(XCSTRINGS) as f:
        data = json.load(f)

    xkeys = set(data.get("strings", {}).keys())
    print(f"📚 xcstrings contains {len(xkeys)} keys")

    # Scan all Swift sources for localization key references.
    used_keys: set[str] = set()
    for swift_file in SOURCES.rglob("*.swift"):
        text = swift_file.read_text()
        for match in KEY_PATTERN.finditer(text):
            key = match.group(1)
            if key.split(".")[0] in LOC_NAMESPACES:
                used_keys.add(key)

    print(f"🔍 Source code references {len(used_keys)} localization keys")

    failures: list[str] = []
    warnings: list[str] = []

    # Check 1: every used key exists in xcstrings
    missing = used_keys - xkeys
    if missing:
        failures.append(
            f"Missing in xcstrings (used in code, not defined):\n"
            + "\n".join(f"   - {k}" for k in sorted(missing))
        )

    # Check 2: every key in xcstrings has both translations
    missing_translations: list[str] = []
    for key, entry in data["strings"].items():
        locs = entry.get("localizations", {})
        if "pt-BR" not in locs:
            missing_translations.append(f"{key} (no pt-BR)")
        if "en" not in locs:
            missing_translations.append(f"{key} (no en)")
    if missing_translations:
        failures.append(
            "Missing translations:\n"
            + "\n".join(f"   - {k}" for k in missing_translations)
        )

    # Check 3 (warning): extra keys in xcstrings not used in code
    extra = xkeys - used_keys
    if extra:
        warnings.append(
            f"Extra keys in xcstrings (defined but not used in code):\n"
            + "\n".join(f"   - {k}" for k in sorted(extra))
        )

    # Report
    if failures:
        for f in failures:
            print(f"\n❌ {f}", file=sys.stderr)
    if warnings:
        for w in warnings:
            print(f"\n⚠️  {w}")

    if failures:
        print("\n💥 Localization check FAILED", file=sys.stderr)
        return 1

    print("\n✅ Localization check PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
