# Tatame: Open Mat Brasil

A free, open-world jiu-jitsu adventure across Brazil. Roll your way from white belt in Cáceres,
through the Pantanal and the Chapada dos Guimarães, to black belt in Rio de Janeiro.

Play it: https://jujitsugame-production.up.railway.app

- `web/`: the playable browser build (open `index.html` through any web server).
- `game/`: the Godot 4.7.2 project. See `game/README.md` for how it's organized, tested and exported.
- `server.js`: a tiny Express server Railway runs to serve `web/` (gzip on, correct wasm headers).

## Deploy on Railway
New Project → Deploy from GitHub repo → pick this repo. Railway detects Node and runs `npm start`.
Add a domain under Settings → Networking. Every push to `main` redeploys.

## Update the web build
Open `game/` in Godot 4.7.2 and export the "Web" preset to `game/build/web/`, then copy those files into `web/`.
(Claude does this for you on each update.)

Art: CC0 models by Quaternius and Kenney (see `game/assets/models/CREDITS.md`). Fonts: Bebas Neue and Nunito (SIL OFL).
Music and sound effects are original, synthesized by `game/tools/make_audio.py`.
