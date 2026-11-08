#!/bin/bash
# Build a fighter body type end to end and render the preview.
set -e
B=${1:-male}
cd /home/claude/charbuild
python3 -I build.py $B 2>&1 | grep -E "Error|Traceback|line [0-9]+|EMPTY" || true
python3 -I to_godot.py $B
cd /home/claude/tatame
timeout 120 godot --headless -s tools/import_fighter.gd -- $B 2>&1 | grep -E "^save"
timeout 120 xvfb-run -a -s "-screen 0 1400x800x24" godot --rendering-driver opengl3 --resolution 1400x800 tests/probe_model.tscn -- $B 2>&1 | grep -E "SCRIPT" | head -3 || true
