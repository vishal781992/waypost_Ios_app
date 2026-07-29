#!/usr/bin/env bash
# Stamp the version from ./VERSION into the generated Xcode project.
#
# The version the app shows in its nav badge is read from the bundle
# (CFBundleShortVersionString -> MARKETING_VERSION), so the only place it is written by
# hand is project.yml. That is exactly the drift the web repo's sync-version.sh exists to
# stop, so this repo keeps the same habit and the same VERSION file semantics.
#
#   ./sync-version.sh          stamp ./VERSION into project.yml (and regenerate)
#   ./sync-version.sh --check  verify they match, change nothing (exit 1 on drift)
#
# Release flow:
#   1. edit VERSION            (match the web repo when the release is a shared one)
#   2. ./sync-version.sh
#   3. note the change in CHANGELOG.md
#   4. git commit && git tag -a "v$(cat VERSION)" && git push --follow-tags
set -euo pipefail
cd "$(dirname "$0")"

V=$(tr -d ' \n\r' < VERSION)
[[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "VERSION must be semver, got '$V'" >&2; exit 1; }

CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

CURRENT=$(sed -n 's/^ *MARKETING_VERSION: *//p' project.yml | head -1)
[ -n "$CURRENT" ] || { echo "no MARKETING_VERSION in project.yml" >&2; exit 2; }

if [ "$CHECK" = "1" ]; then
  if [ "$CURRENT" = "$V" ]; then
    echo "version in sync: v$V"
    exit 0
  fi
  echo "DRIFT: project.yml has v$CURRENT, VERSION says v$V — run ./sync-version.sh"
  exit 1
fi

if [ "$CURRENT" = "$V" ]; then
  echo "already v$V -> project.yml"
else
  # macOS sed needs the empty -i argument.
  sed -i '' "s/^\( *MARKETING_VERSION: \).*/\1$V/" project.yml
  echo "stamped v$V -> project.yml"
fi

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate >/dev/null
  echo "regenerated Waypost.xcodeproj"
else
  echo "xcodegen not installed — run 'brew install xcodegen', then 'xcodegen generate'" >&2
fi
