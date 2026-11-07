# Tatame: Open Mat Brasil

Open-world jiu-jitsu adventure built in **Godot 4.7.2** (GDScript, Compatibility renderer).
Zone 1: Cáceres (white → blue). Zone 2: the Pantanal (blue → purple). Zone 3: Chapada dos Guimarães (purple → brown).
Buses at each zone travel to any unlocked zone. A date-seeded Daily Challenge (same for every player that day)
runs from the gym boards or the journal, with streak rewards. One project exports to Web, Windows/Mac/Linux (Steam) and iOS/Android.

## Run it
1. Install Godot 4.7.2 (standard, not .NET) from godotengine.org.
2. Open `project.godot`, press Play (F5).

## Change things
- `scripts/data.gd`: all game content: techniques, opponents, belts, achievements, landmarks.
  Set `COMMUNITY_URL` to your community link and a "Join the community" button appears on
  the title screen and in the journal.
- `scripts/rpg.gd`: the RPG layer: 5 fighting styles, 5 attributes, 3 talent trees, the level curve, and
  `build_mods()`, which turns a build into the numbers a roll uses. Tune balance here.
- `scripts/roll/`: the roll (match) logic (`roll_sim.gd`, unit-tested), poses and UI.
- `scripts/world/`: both zones (Cáceres and the Pantanal, built in `world.gd` by `build(zone)`), player, NPCs,
  drill stations and travel points.
- `scripts/ui/drill_scene.gd`: training drill minigames (3 good sessions = +1 attribute, max +5 each).
- `assets/models/`: CC0 low-poly models (Quaternius characters, Kenney nature/props). See `assets/models/CREDITS.md`.
  `BodyRig` keeps its primitive skeleton as an invisible pose guide and retargets it onto the skinned model, so
  every grappling pose works on real characters; exploring uses the models' own idle/walk/run/jump animations.
- `scripts/audio.gd` + `assets/audio/`: sound effects and music. Every sound is synthesized by
  `tools/make_audio.py` (original, no samples, no licensing), so run it again after changing a sound.
- `scripts/ui/`: HUD, journal, touch controls.

## Tests (headless)
    godot --headless --path . res://tests/test_sim.tscn    # match logic, progression
    godot --headless --path . res://tests/test_flow.tscn   # bot plays all 5 fighters end to end

## Export for web
    godot --headless --path . --export-release "Web" build/web/index.html
Upload `build/web` to any static host (Netlify, itch.io, Railway). Threads are off, so no special headers are needed.

## QA shortcuts (web build only)
`index.html#roll=onca` jumps into a roll; `#tp=-36,52` teleports; `#journal=1` opens the journal. These sessions never save.
