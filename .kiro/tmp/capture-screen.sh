#!/bin/zsh
set -e
name="$1"
shift
xcrun simctl launch --terminate-running-process booted us.parkhop.waypost "$@"
sleep 4
xcrun simctl io booted screenshot "/tmp/waypost-${name}.png"
