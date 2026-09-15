#!/usr/bin/env bash
# Print the demo talk track.
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
sed -n '/^## Talk track/,$p' "${ROOT}/README.md" | sed '1d'
