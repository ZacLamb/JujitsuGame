#!/bin/bash
# Modular heads: trim each hero body's placeholder head, fit every face to every body, import.
#   tools/meshybuild/heads.sh   (bodies: hero_{gi,nogi}_{m,f}; faces: /home/claude/models3d/head_*.glb)
set -e
W=/home/claude/meshybuild; T=/home/claude/tatame
cp $T/tools/meshybuild/*.py $W/ && cd $W
mkdir -p $T/assets/models/heads
for B in hero_gi_m hero_gi_f hero_nogi_m hero_nogi_f; do
  python3 -I head.py --trim $B | tail -1
  python3 mask.py $B > /dev/null
  cp ${B}_mask.png $T/assets/models/
  for G in /home/claude/models3d/head_*.glb; do
    H=$(basename $G .glb); H=${H#head_}
    python3 -I head.py -- $G $B $H 2>&1 | grep -E "Trace|Error" || true
  done
done
cp $W/{fade,curly,blond,goatee,topknot,braid,puff,pixie}_albedo.png $T/assets/models/heads/
cd $T && timeout 300 godot --headless --import >/dev/null 2>&1 || true
for B in hero_gi_m hero_gi_f hero_nogi_m hero_nogi_f; do
  timeout 120 godot --headless -s tools/import_meshy.gd -- $B 2>&1 | grep -c "^save" | tr '\n' ' '
  for G in /home/claude/models3d/head_*.glb; do H=$(basename $G .glb); H=${H#head_}
    timeout 120 godot --headless -s tools/import_meshy.gd -- ${B}__$H 2>&1 | grep -c "^save" | tr '\n' ' '
  done
done
echo
