#!/bin/bash
# Turn a Meshy A-pose character GLB into a game body:  build.sh <model.glb> <meshy_name>
#   e.g. build.sh ~/Downloads/Grappler.glb meshy_male
# Steps: estimate joints -> decimate + auto-weight in Blender -> bake recolour mask -> Godot import.
set -e
GLB=$1; NAME=$2; W=/home/claude/meshybuild; T=/home/claude/tatame
mkdir -p $W && cp $T/tools/meshybuild/*.py $W/ && cd $W
python3 -I joints.py "$GLB" $NAME.joints.json | tail -1
python3 -I skin.py "$GLB" $NAME.joints.json $NAME 16000 | grep -E "^(faces|verts|skin_ref)"
python3 mask.py $NAME
cp ${NAME}_albedo.png ${NAME}_mask.png $T/assets/models/
cd $T && timeout 300 godot --headless --import >/dev/null 2>&1 || true
timeout 120 godot --headless -s tools/import_meshy.gd -- $NAME | grep "^save"
