#!/usr/bin/env python3
"""Every Swift file on disk is in the Xcode project.

`Waypost.xcodeproj` is generated from `project.yml` and never committed, so a file added
to the repo does not exist as far as Xcode is concerned until `xcodegen generate` has run
again. The symptom is a build failure that reads like a code error and is not one —
*Cannot find 'AtlasScreen' in scope*, on a type that is declared, spelled correctly, and
sitting in the file right next to it.

That is a whole build cycle spent on a stale project file, and it is checkable in a
second. Run this after pulling, or before wondering why a new type cannot be found.

    python3 tools/check-project.py

Exits 1 on drift, with the one command that fixes it.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PBXPROJ = ROOT / "Waypost.xcodeproj" / "project.pbxproj"


def main() -> int:
    on_disk = {p.name for p in (ROOT / "Waypost").rglob("*.swift")}
    if not on_disk:
        print("no Swift files under Waypost/ — is this the right directory?")
        return 2

    if not PBXPROJ.exists():
        print("Waypost.xcodeproj is not generated yet.\n\n    xcodegen generate\n")
        return 1

    # The pbxproj lists every file reference by name. Matching on the name rather than the
    # path is deliberate: XcodeGen writes paths relative to a group, so a full-path compare
    # would report drift that is not there. The cost is that two files sharing a name in
    # different directories would cover for each other — the repo has none, and Swift's
    # own conventions make it unlikely, but it is the one thing this check cannot see.
    referenced = set(re.findall(r"[\w+.-]+\.swift", PBXPROJ.read_text(errors="ignore")))

    missing = sorted(on_disk - referenced)
    if missing:
        print(f"{len(missing)} file(s) on disk are not in Waypost.xcodeproj:\n")
        for name in missing:
            print(f"    {name}")
        print("\nThe project is generated, so it does not know about them yet:\n")
        print("    xcodegen generate\n")
        return 1

    # A stale reference is the other half of the same problem: a file deleted in the repo
    # and still listed builds until Xcode goes looking for it.
    stale = sorted(n for n in referenced - on_disk if not n.startswith("Package"))
    if stale:
        print(f"{len(stale)} file(s) in Waypost.xcodeproj no longer exist:\n")
        for name in stale:
            print(f"    {name}")
        print("\n    xcodegen generate\n")
        return 1

    print(f"project in sync: {len(on_disk)} Swift files, all referenced")
    return 0


if __name__ == "__main__":
    sys.exit(main())
