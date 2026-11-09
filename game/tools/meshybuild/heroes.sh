#!/bin/bash
# Rebuild every hero body + every face from the Higgsfield GLBs in /home/claude/models3d.
# Belt bands (BELT_GEO) were found by eye per body: see the README.
set -e
T=/home/claude/tatame; M=/home/claude/models3d; cd $T
ARM_WIDE=1 BELT_GEO=0.2,0.25 KNOT_DROP=0.09 bash tools/meshybuild/build.sh $M/apose_gi_m.glb hero_gi_m | grep "^save"
ARM_WIDE=1 BELT_GEO=0.25,0.30 KNOT_DROP=0.09 bash tools/meshybuild/build.sh $M/apose_gi_f.glb hero_gi_f | grep "^save"
ARM_WIDE=1 bash tools/meshybuild/build.sh $M/apose_nogi_m.glb hero_nogi_m | grep "^save"
ARM_WIDE=1 bash tools/meshybuild/build.sh $M/apose_nogi_f.glb hero_nogi_f | grep "^save"
bash tools/meshybuild/heads.sh
