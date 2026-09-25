#!/usr/bin/env bash
# Open the side-screen demo notes in Obsidian, with the command block refreshed
# from DEMO_BEATS and marked with whatever the last preflight found broken.
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
head_ "Socket Firewall demo - notes"
render_notes
open_notes
