#!/usr/bin/env python3
"""Checks the design system is actually shared, not merely intended to be.

Written because it was not. The park screen and the trip screen each grew their own
floating back control, and they drifted the moment they existed: one sat six points under
the status bar, the other a whole status bar lower. Nothing failed, nothing warned — the
two files simply disagreed, and the only way to notice was to look at both screens at once.

Run: python3 tools/design-lint.py
"""
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent / "Waypost"
DESIGN = ROOT / "Design"
swift = sorted(ROOT.rglob("*.swift"))
def read(p): return p.read_text(encoding="utf-8")
def strip(src):  # comments out, so prose about a rule never satisfies the rule
    src = re.sub(r"/\*.*?\*/", " ", src, flags=re.S)
    return re.sub(r"//[^\n]*", " ", src)

failures, checks = [], 0
def check(name, ok, detail=""):
    global checks
    checks += 1
    print(("  PASS  " if ok else "  FAIL  ") + name + (("\n         " + detail) if detail and not ok else ""))
    if not ok: failures.append(name)

print("Shared components")

# 1. One back control, defined in Design/, used everywhere.
hand_rolled = []
for p in swift:
    if p.parent == DESIGN: continue
    body = strip(read(p))
    for m in re.finditer(r'Image\(systemName: "chevron\.left"\)', body):
        window = body[m.start():m.start() + 400]
        if "glassControl()" in window:
            hand_rolled.append(f"{p.relative_to(ROOT)}")
check("no screen hand-rolls a floating back control",
      not hand_rolled, "hand-rolled in: " + ", ".join(sorted(set(hand_rolled))))

# 2. Call sites add no placement of their own — the component owns it.
bad_padding = []
for p in swift:
    body = strip(read(p))
    for m in re.finditer(r"FloatingBack\([^)]*\)\s*\{[^}]*\}\s*((?:\.\w+\([^)]*\)\s*)*)", body):
        for mod in re.findall(r"\.(padding|offset|position)\(", m.group(1)):
            bad_padding.append(f"{p.relative_to(ROOT)} adds .{mod}")
check("FloatingBack call sites add no padding, offset or position",
      not bad_padding, "; ".join(bad_padding))

print("\nShared values")

# 3. Both full-bleed heroes dissolve with the same gradient stops.
def stops(src):
    """The dissolve, specifically — the gradient whose stops are the page colour.

    Taking the first `stops:` in the file found a different gradient entirely and reported
    a drift that was not there. A check that fails for its own reasons is worse than no
    check, because the next person turns it off."""
    for m in re.finditer(r"stops:\s*\[(.*?)\]", strip(src), re.S):
        block = m.group(1)
        if "WP.bg" in block:
            return re.findall(r"location:\s*([0-9.]+)", block)
    return None
park = stops(read(ROOT / "Features/Park/ParkScreen.swift"))
plate = stops(read(ROOT / "Features/Trips/TripsScreen.swift"))
check("the park hero and the map hero dissolve identically",
      park is not None and park == plate, f"park={park} map={plate}")

# 4. Literals that duplicate a token.
tokens = {}
for m in re.finditer(r"static let (\w+): CGFloat = ([0-9.]+)", read(DESIGN / "Tokens.swift")):
    tokens[float(m.group(2))] = m.group(1)
dupes = []
for p in swift:
    if p.parent == DESIGN: continue
    for m in re.finditer(r"\.padding\(\.(?:horizontal|leading|trailing), (\d+(?:\.\d+)?)\)", strip(read(p))):
        value = float(m.group(1))
        if value in tokens and tokens[value] == "gutter":
            dupes.append(f"{p.relative_to(ROOT)}:{value} is WP.gutter")
check("no view hard-codes a value that is already a token",
      not dupes, "; ".join(sorted(set(dupes))[:6]))

print(f"\n{checks - len(failures)}/{checks} checks passed")
sys.exit(1 if failures else 0)
