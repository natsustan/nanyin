#!/usr/bin/env bash
# Regenerates Nanyin.xcodeproj from project.yml. Never edit the project by hand.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
exec mise exec -- xcodegen generate --quiet
