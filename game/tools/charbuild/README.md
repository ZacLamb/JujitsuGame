# Fighter model builder

Original CC0 character meshes for Tatame, sculpted from signed-distance shapes and skinned to the
Quaternius worker skeleton (assets/models/worker.glb), so all existing animations and the BodyRig
retargeting keep working.

Pipeline (needs `pip install bpy scikit-image`, Python 3.13, run Python with `-I`):

1. `godot --headless -s tools/dump_skeleton.gd`: writes the worker skin bind heads.
2. `python3 -I build.py male|female`: SDF body, face, 6 hair styles and every gear piece, meshed
   with marching cubes, smoothed, decimated and weighted in Blender. Dumps JSON.
3. `python3 -I to_godot.py male|female`: fits the dump onto the worker bind space.
4. `godot --headless -s tools/import_fighter.gd -- male|female`: builds
   `assets/models/fighter_<body>.scn` (one MeshInstance3D per piece, auto LODs, bind-space UVs
   for the pattern shader in scripts/fighter_look.gd).

`run.sh <body>` runs steps 2-4 and renders tests/probe_model.tscn. Paths assume the build folder
is /home/claude/charbuild; adjust at the top of each script.

Pieces: Body, Face, Hair_{short,buzz,bun,curly,long,ponytail}, Jacket, JacketTrim, Pants, Belt,
Rash, Spats, KneeSleeves, EarGuards, Headband, Tape.
