// Serves the Godot web build in /web. Gzip makes the 39 MB engine download ~10 MB.
const express = require('express');
const compression = require('compression');
const path = require('path');

const app = express();
app.use(compression({ filter: (req, res) => /\.(wasm|pck|js|html)$/.test(req.path) || compression.filter(req, res) }));
app.use(express.static(path.join(__dirname, 'web'), {
  setHeaders(res, file) {
    if (file.endsWith('.wasm')) res.setHeader('Content-Type', 'application/wasm');
    // engine files rarely change; game data (.pck) and the page should always be fresh
    if (file.endsWith('.wasm') || file.endsWith('.js')) res.setHeader('Cache-Control', 'public, max-age=604800');
    else res.setHeader('Cache-Control', 'no-cache');
  },
}));
app.get('/health', (_req, res) => res.send('ok'));
const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`Tatame running on :${port}`));
