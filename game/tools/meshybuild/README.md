# Meshy body pipeline

Turns a textured Meshy character (standing, arms relaxed at the sides, GLB with texture) into a
fighter body driven by the same worker skeleton, animations and BodyRig retargeting as everything
else. Needs `bpy`, `numpy`, `scipy`, `Pillow`; Python 3.13.

    tools/meshybuild/build.sh <model.glb> meshy_<name>

1. `joints.py`  scales the model to the worker's height and finds its joints from mesh slices
   (legs, spine at worker proportions, arms traced down to the fingertips).
2. `skin.py`    welds + decimates to ~16k tris in Blender, builds an armature on those joints,
   bone-heat weights it, downsizes the albedo to 1024 and dumps JSON (+ belt / skin region flags).
3. `mask.py`    rasterises the region flags into `<name>_mask.png` (R = belt, G = bare skin) so the
   shader can recolour belt rank, gi colour and skin tone.
4. `tools/import_meshy.gd` builds `assets/models/<name>.scn`. The mesh keeps its A-pose; each
   bind pose maps the mesh's own joint (stretched along the bone to the worker's length) onto the
   worker bone, so no re-posing is needed.

`viz.py <glb> <joints.json> <out.png>` plots the estimated joints for a quick check.
BodyRig uses these bodies for plain gi looks (`BodyRig.MESHY`); patterned gear sets, no-gi and
casual clothes stay on the sculpted piece models.
