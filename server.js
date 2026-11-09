// Serves the Godot web build in /web, plus a small account + cloud-save API backed by Postgres.
// Gzip makes the 39 MB engine download ~10 MB.
const express = require('express');
const compression = require('compression');
const path = require('path');
const crypto = require('crypto');
const { Pool } = require('pg');
const world = require('./world');

const app = express();
app.use(compression({ filter: (req, res) => /\.(wasm|pck|js|html)$/.test(req.path) || compression.filter(req, res) }));
app.use('/api', express.json({ limit: '2mb' }));

// ------------------------------------------------------------------ database
const pool = process.env.DATABASE_URL ? new Pool({ connectionString: process.env.DATABASE_URL }) : null;
let ready = false;
async function migrate() {
  if (!pool) return;
  await pool.query(`
    CREATE TABLE IF NOT EXISTS players (
      id SERIAL PRIMARY KEY,
      email TEXT UNIQUE NOT NULL,
      pw_hash TEXT NOT NULL,
      created_at TIMESTAMPTZ DEFAULT now()
    );
    CREATE TABLE IF NOT EXISTS sessions (
      token TEXT PRIMARY KEY,
      player_id INT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
      created_at TIMESTAMPTZ DEFAULT now()
    );
    CREATE TABLE IF NOT EXISTS saves (
      player_id INT PRIMARY KEY REFERENCES players(id) ON DELETE CASCADE,
      data JSONB NOT NULL,
      updated_at TIMESTAMPTZ DEFAULT now()
    );
    CREATE TABLE IF NOT EXISTS reports (
      id SERIAL PRIMARY KEY,
      reporter_id INT REFERENCES players(id) ON DELETE SET NULL,
      target_id INT REFERENCES players(id) ON DELETE SET NULL,
      target_name TEXT,
      reason TEXT,
      context TEXT,
      created_at TIMESTAMPTZ DEFAULT now()
    );`);
  ready = true;
  console.log('db ready');
}
migrate().catch((e) => console.error('migrate failed', e));

// ------------------------------------------------------------------ helpers
const hashPw = (pw, salt = crypto.randomBytes(16).toString('hex')) =>
  new Promise((res, rej) => crypto.scrypt(pw, salt, 64, (err, key) => (err ? rej(err) : res(`${salt}:${key.toString('hex')}`))));
async function checkPw(pw, stored) {
  const [salt, key] = stored.split(':');
  const again = (await hashPw(pw, salt)).split(':')[1];
  return crypto.timingSafeEqual(Buffer.from(key, 'hex'), Buffer.from(again, 'hex'));
}
const newToken = () => crypto.randomBytes(32).toString('hex');
const okEmail = (e) => typeof e === 'string' && e.length <= 200 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e);

// simple brute-force guard: 10 attempts / 10 min per ip+email
const attempts = new Map();
function limited(key) {
  const now = Date.now();
  const a = (attempts.get(key) || []).filter((t) => now - t < 600000);
  a.push(now);
  attempts.set(key, a);
  return a.length > 10;
}

function needDb(_req, res, next) {
  if (!pool || !ready) return res.status(503).json({ error: 'Accounts are offline right now.' });
  next();
}
async function auth(req, res, next) {
  const token = (req.get('authorization') || '').replace(/^Bearer\s+/i, '');
  if (!token) return res.status(401).json({ error: 'Not logged in.' });
  const r = await pool.query('SELECT p.id, p.email FROM sessions s JOIN players p ON p.id = s.player_id WHERE s.token = $1', [token]);
  if (!r.rows.length) return res.status(401).json({ error: 'Session expired. Log in again.' });
  req.player = r.rows[0];
  req.token = token;
  next();
}

// ------------------------------------------------------------------ account
app.post('/api/register', needDb, async (req, res) => {
  try {
    const email = String(req.body.email || '').trim().toLowerCase();
    const pw = String(req.body.password || '');
    if (!okEmail(email)) return res.status(400).json({ error: 'That email doesn\'t look right.' });
    if (pw.length < 8) return res.status(400).json({ error: 'Use at least 8 characters for the password.' });
    if (limited(`${req.ip}|reg`)) return res.status(429).json({ error: 'Too many tries. Wait a few minutes.' });
    const exists = await pool.query('SELECT 1 FROM players WHERE email = $1', [email]);
    if (exists.rows.length) return res.status(409).json({ error: 'That email already has an account. Log in instead.' });
    const r = await pool.query('INSERT INTO players (email, pw_hash) VALUES ($1, $2) RETURNING id', [email, await hashPw(pw)]);
    const token = newToken();
    await pool.query('INSERT INTO sessions (token, player_id) VALUES ($1, $2)', [token, r.rows[0].id]);
    res.json({ token, email });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'Something went wrong. Try again.' });
  }
});

app.post('/api/login', needDb, async (req, res) => {
  try {
    const email = String(req.body.email || '').trim().toLowerCase();
    const pw = String(req.body.password || '');
    if (limited(`${req.ip}|${email}`)) return res.status(429).json({ error: 'Too many tries. Wait a few minutes.' });
    const r = await pool.query('SELECT id, pw_hash FROM players WHERE email = $1', [email]);
    if (!r.rows.length || !(await checkPw(pw, r.rows[0].pw_hash))) return res.status(401).json({ error: 'Wrong email or password.' });
    const token = newToken();
    await pool.query('INSERT INTO sessions (token, player_id) VALUES ($1, $2)', [token, r.rows[0].id]);
    res.json({ token, email });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'Something went wrong. Try again.' });
  }
});

app.post('/api/logout', needDb, auth, async (req, res) => {
  await pool.query('DELETE FROM sessions WHERE token = $1', [req.token]);
  res.json({ ok: true });
});

app.get('/api/me', needDb, auth, (req, res) => res.json({ email: req.player.email }));

// ------------------------------------------------------------------ cloud saves
// data: {index: {...}, chars: {id: save}, at: unix seconds of the client's last save}
app.get('/api/saves', needDb, auth, async (req, res) => {
  const r = await pool.query('SELECT data, extract(epoch from updated_at) AS t FROM saves WHERE player_id = $1', [req.player.id]);
  res.json(r.rows.length ? { data: r.rows[0].data, updated: Number(r.rows[0].t) } : { data: null, updated: 0 });
});

app.put('/api/saves', needDb, auth, async (req, res) => {
  const data = req.body && req.body.data;
  if (!data || typeof data !== 'object' || typeof data.chars !== 'object') return res.status(400).json({ error: 'Bad save.' });
  if (Object.keys(data.chars).length > 20) return res.status(400).json({ error: 'Too many characters.' });
  await pool.query(
    `INSERT INTO saves (player_id, data, updated_at) VALUES ($1, $2, now())
     ON CONFLICT (player_id) DO UPDATE SET data = EXCLUDED.data, updated_at = now()`,
    [req.player.id, data]
  );
  res.json({ ok: true });
});

// ------------------------------------------------------------------ the game
app.use(express.static(path.join(__dirname, 'web'), {
  setHeaders(res, file) {
    if (file.endsWith('.wasm')) res.setHeader('Content-Type', 'application/wasm');
    // engine files rarely change; game data (.pck) and the page should always be fresh
    if (file.endsWith('.wasm') || file.endsWith('.js')) res.setHeader('Cache-Control', 'public, max-age=604800');
    else res.setHeader('Cache-Control', 'no-cache');
  },
}));
let live = null;
app.get('/health', (_req, res) => res.send((pool ? (ready ? 'ok db' : 'ok db-starting') : 'ok no-db') + (live ? ` online ${live.online()}` : '')));
const port = process.env.PORT || 3000;
const server = app.listen(port, () => console.log(`Tatame running on :${port}`));
live = world.attach(server, pool, () => ready);
