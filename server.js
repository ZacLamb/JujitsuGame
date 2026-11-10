// Serves the Godot web build in /web, plus a small account + cloud-save API backed by Postgres.
// Gzip makes the 39 MB engine download ~10 MB.
const express = require('express');
const compression = require('compression');
const path = require('path');
const crypto = require('crypto');
const { Pool } = require('pg');
const world = require('./world');
const isGmEmail = (e) => (process.env.GM_EMAILS || '').split(',').map((x) => x.trim().toLowerCase()).includes(String(e || '').toLowerCase());

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
    );
    ALTER TABLE players ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'player';
    ALTER TABLE players ADD COLUMN IF NOT EXISTS muted_until TIMESTAMPTZ;
    ALTER TABLE players ADD COLUMN IF NOT EXISTS marketing_optin BOOLEAN NOT NULL DEFAULT false;
    CREATE TABLE IF NOT EXISTS war (
      week TEXT NOT NULL,
      player_id INT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
      faction TEXT NOT NULL,
      name TEXT,
      points INT NOT NULL DEFAULT 0,
      PRIMARY KEY (week, player_id, faction)
    );
    CREATE TABLE IF NOT EXISTS arena (
      week TEXT NOT NULL,
      player_id INT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
      name TEXT, faction TEXT, style TEXT, level INT NOT NULL DEFAULT 1,
      rating INT NOT NULL DEFAULT 1000,
      wins INT NOT NULL DEFAULT 0, losses INT NOT NULL DEFAULT 0,
      char JSONB, claimed BOOLEAN NOT NULL DEFAULT false,
      updated_at TIMESTAMPTZ DEFAULT now(),
      PRIMARY KEY (week, player_id)
    );
    CREATE TABLE IF NOT EXISTS gm_log (
      id SERIAL PRIMARY KEY,
      gm_id INT REFERENCES players(id) ON DELETE SET NULL,
      action TEXT, target TEXT, detail TEXT,
      created_at TIMESTAMPTZ DEFAULT now()
    );`);
  // Game Masters come from the GM_EMAILS variable on Railway (comma separated); nobody can
  // promote themselves from the game.
  const gms = (process.env.GM_EMAILS || '').split(',').map((e) => e.trim().toLowerCase()).filter(Boolean);
  await pool.query("UPDATE players SET role = 'player' WHERE role = 'gm' AND NOT (lower(email) = ANY($1))", [gms]);
  if (gms.length) await pool.query("UPDATE players SET role = 'gm' WHERE lower(email) = ANY($1)", [gms]);
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
  const r = await pool.query('SELECT p.id, p.email, p.role FROM sessions s JOIN players p ON p.id = s.player_id WHERE s.token = $1', [token]);
  if (!r.rows.length) return res.status(401).json({ error: 'Session expired. Log in again.' });
  req.player = r.rows[0];
  req.token = token;
  next();
}

// ------------------------------------------------------------------ lead magnet plumbing
// Railway variables (all optional):
//   COMMUNITY_URL / COMMUNITY_LABEL  the in-game "join the community" button (title screen, quest log)
//   SIGNUP_WEBHOOK_URL               every new account is POSTed here as JSON (e.g. a GHL inbound
//                                    webhook trigger): {email, optin, source, event, created_at}
function signupHook(body) {
  const url = process.env.SIGNUP_WEBHOOK_URL;
  if (!url) return;
  fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
    .catch((e) => console.error('signup webhook failed', e.message));
}
app.get('/api/config', (_req, res) => res.json({
  community_url: process.env.COMMUNITY_URL || '',
  community_label: process.env.COMMUNITY_LABEL || 'Join the community',
}));
// Game Master: how the lead magnet is doing
app.get('/api/stats', needDb, auth, async (req, res) => {
  if (req.player.role !== 'gm') return res.status(403).json({ error: 'Game Masters only.' });
  const q = async (sql) => (await pool.query(sql)).rows[0];
  res.json({
    players: (await q('SELECT count(*)::int AS n FROM players')).n,
    optin: (await q('SELECT count(*)::int AS n FROM players WHERE marketing_optin')).n,
    last7: (await q("SELECT count(*)::int AS n FROM players WHERE created_at > now() - interval '7 days'")).n,
    last24: (await q("SELECT count(*)::int AS n FROM players WHERE created_at > now() - interval '1 day'")).n,
    saves: (await q('SELECT count(*)::int AS n FROM saves')).n,
    online: live ? live.online() : 0,
  });
});

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
    const optin = req.body.optin === true;
    const r = await pool.query('INSERT INTO players (email, pw_hash, role, marketing_optin) VALUES ($1, $2, $3, $4) RETURNING id', [email, await hashPw(pw), isGmEmail(email) ? 'gm' : 'player', optin]);
    signupHook({ email, optin, source: 'tatame-game', event: 'signup', created_at: new Date().toISOString() });
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

app.get('/api/me', needDb, auth, (req, res) => res.json({ email: req.player.email, role: req.player.role }));

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


// ------------------------------------------------------------------ faction war
// Every win a player earns adds points to their faction's weekly total (Brasil vs USA). The
// client batches points; the server caps each push and each player's week so nobody can
// hand their side the war on their own.
const FACTIONS = ['brasil', 'usa'];
const WAR_PUSH_MAX = 300;
const WAR_WEEK_MAX = 15000;
function isoWeek(d = new Date()) {
  const t = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const day = t.getUTCDay() || 7;
  t.setUTCDate(t.getUTCDate() + 4 - day);
  const y0 = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
  return `${t.getUTCFullYear()}-W${String(Math.ceil(((t - y0) / 86400000 + 1) / 7)).padStart(2, '0')}`;
}
function lastWeek() {
  return isoWeek(new Date(Date.now() - 7 * 86400000));
}
const warPushAt = new Map();
let warCache = null;
let warCacheAt = 0;
async function warState() {
  if (warCache && Date.now() - warCacheAt < 15000) return warCache;
  const week = isoWeek();
  const prev = lastWeek();
  const tot = await pool.query('SELECT week, faction, SUM(points)::int AS p FROM war WHERE week = ANY($1) GROUP BY week, faction', [[week, prev]]);
  const sum = (w, f) => (tot.rows.find((r) => r.week === w && r.faction === f) || { p: 0 }).p;
  const top = {};
  for (const f of FACTIONS) {
    const r = await pool.query('SELECT name, points FROM war WHERE week = $1 AND faction = $2 ORDER BY points DESC LIMIT 5', [week, f]);
    top[f] = r.rows.map((x) => ({ name: x.name || '?', points: x.points }));
  }
  const pb = sum(prev, 'brasil');
  const pu = sum(prev, 'usa');
  warCache = { week, brasil: sum(week, 'brasil'), usa: sum(week, 'usa'), top,
    last: { week: prev, brasil: pb, usa: pu, winner: pb === pu ? '' : (pb > pu ? 'brasil' : 'usa') } };
  warCacheAt = Date.now();
  return warCache;
}
app.get('/api/war', needDb, async (_req, res) => {
  try { res.json(await warState()); } catch (e) { console.error(e); res.status(500).json({ error: 'War report unavailable.' }); }
});
app.post('/api/war', needDb, auth, async (req, res) => {
  try {
    const faction = String(req.body.faction || '');
    const name = String(req.body.name || '').slice(0, 16);
    let pts = Math.floor(Number(req.body.points) || 0);
    if (!FACTIONS.includes(faction) || pts <= 0) return res.status(400).json({ error: 'Bad report.' });
    const last = warPushAt.get(req.player.id) || 0;
    if (Date.now() - last < 25000) return res.status(429).json({ error: 'Slow down.' });
    warPushAt.set(req.player.id, Date.now());
    pts = Math.min(pts, WAR_PUSH_MAX);
    const week = isoWeek();
    const cur = await pool.query('SELECT COALESCE(SUM(points),0)::int AS p FROM war WHERE week = $1 AND player_id = $2', [week, req.player.id]);
    pts = Math.max(0, Math.min(pts, WAR_WEEK_MAX - cur.rows[0].p));
    if (pts > 0) {
      await pool.query(
        `INSERT INTO war (week, player_id, faction, name, points) VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (week, player_id, faction) DO UPDATE SET points = war.points + EXCLUDED.points, name = EXCLUDED.name`,
        [week, req.player.id, faction, name, pts]);
      warCache = null;
    }
    const mine = await pool.query('SELECT COALESCE(SUM(points),0)::int AS p FROM war WHERE week = $1 AND player_id = $2', [week, req.player.id]);
    res.json({ ok: true, added: pts, mine: mine.rows[0].p, war: await warState() });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

// ------------------------------------------------------------------ ranked arena
// Weekly ladder of shadow fights: the server picks an opponent near your rating (another
// player's saved build, or a house fighter when the ladder is thin), hands out a one-use match
// ticket, and moves both ratings (Elo) when the result comes back. Ratings reset every week;
// last week's standings pay out once (see /api/arena/claim).
const ARENA_START = 1000;
const ARENA_K = 32;
const ARENA_MIN_GAP_MS = 20000;
const ARENA_TICKET_MS = 15 * 60000;
const ARENA_PAY_MIN = 5;   // matches to qualify for the weekly payout
const HOUSE = ['Rato de Tatame', 'Faixa Coral Fantasma', 'Old School Ronin', 'Garage Legend', 'Sombra do Arpoador', 'Swamp Phantom', 'Vortex Monk', 'Iron Mike B.'];
const arenaTickets = new Map();   // player id -> {opp, oppRating, house, at}
const arenaLast = new Map();
const cleanChar = (c) => (c && typeof c === 'object' ? JSON.parse(JSON.stringify(c).slice(0, 6000)) : {});
async function arenaRow(pid, week) {
  const r = await pool.query('SELECT * FROM arena WHERE week = $1 AND player_id = $2', [week, pid]);
  return r.rows[0] || null;
}
async function arenaUpsert(pid, week, b) {
  const lvl = Math.max(1, Math.min(60, Math.floor(Number(b.level) || 1)));
  await pool.query(
    `INSERT INTO arena (week, player_id, name, faction, style, level, char) VALUES ($1, $2, $3, $4, $5, $6, $7)
     ON CONFLICT (week, player_id) DO UPDATE SET name = EXCLUDED.name, faction = EXCLUDED.faction, style = EXCLUDED.style,
       level = EXCLUDED.level, char = EXCLUDED.char, updated_at = now()`,
    [week, pid, String(b.name || '?').slice(0, 16), FACTIONS.includes(b.faction) ? b.faction : 'brasil', String(b.style || '').slice(0, 16), lvl, cleanChar(b.char)]);
}
async function arenaBoard(pid) {
  const week = isoWeek();
  const top = await pool.query('SELECT name, faction, style, level, rating, wins, losses FROM arena WHERE week = $1 AND wins + losses > 0 ORDER BY rating DESC, wins DESC LIMIT 20', [week]);
  let me = null;
  if (pid) {
    const r = await arenaRow(pid, week);
    if (r) {
      const rank = await pool.query('SELECT COUNT(*)::int AS n FROM arena WHERE week = $1 AND wins + losses > 0 AND rating > $2', [week, r.rating]);
      me = { rating: r.rating, wins: r.wins, losses: r.losses, rank: r.wins + r.losses > 0 ? rank.rows[0].n + 1 : 0 };
    }
  }
  const prev = await pool.query('SELECT name, faction, rating FROM arena WHERE week = $1 AND wins + losses >= $2 ORDER BY rating DESC LIMIT 3', [lastWeek(), ARENA_PAY_MIN]);
  return { week, top: top.rows, me, last: { week: lastWeek(), top: prev.rows }, pay_min: ARENA_PAY_MIN };
}
app.get('/api/arena', needDb, async (req, res) => {
  try {
    let pid = 0;
    const token = (req.get('authorization') || '').replace(/^Bearer\s+/i, '');
    if (token) {
      const r = await pool.query('SELECT player_id FROM sessions WHERE token = $1', [token]);
      if (r.rows.length) pid = r.rows[0].player_id;
    }
    res.json(await arenaBoard(pid));
  } catch (e) { console.error(e); res.status(500).json({ error: 'Arena unavailable.' }); }
});
// Find a match: you enter this week's ladder with your current build, and get an opponent.
app.post('/api/arena/match', needDb, auth, async (req, res) => {
  try {
    const week = isoWeek();
    const pid = req.player.id;
    await arenaUpsert(pid, week, req.body || {});
    const me = await arenaRow(pid, week);
    const lvl = me.level;
    // closest rating among other players this week or last (any faction), similar level first
    const cand = await pool.query(
      `SELECT DISTINCT ON (player_id) player_id, name, faction, style, level, char,
         COALESCE((SELECT rating FROM arena a2 WHERE a2.week = $1 AND a2.player_id = arena.player_id), $3) AS rating
       FROM arena WHERE week = ANY($2) AND player_id <> $4 AND char IS NOT NULL
       ORDER BY player_id, week DESC`, [week, [week, lastWeek()], ARENA_START, pid]);
    const pool2 = cand.rows.filter((r) => Math.abs(r.level - lvl) <= 12);
    pool2.sort((a, b) => Math.abs(a.rating - me.rating) - Math.abs(b.rating - me.rating));
    const pick = pool2.slice(0, 4)[Math.floor(Math.random() * Math.min(4, pool2.length))];
    let opp;
    if (pick) {
      opp = { name: pick.name, faction: pick.faction, style: pick.style, level: pick.level, rating: pick.rating, char: pick.char, house: false };
      arenaTickets.set(pid, { opp: pick.player_id, oppRating: pick.rating, house: false, at: Date.now() });
    } else {
      const r = me.rating + Math.round((Math.random() - 0.5) * 120);
      opp = { name: HOUSE[Math.floor(Math.random() * HOUSE.length)], faction: Math.random() < 0.5 ? 'brasil' : 'usa', style: '', level: lvl, rating: r, char: null, house: true };
      arenaTickets.set(pid, { opp: 0, oppRating: r, house: true, at: Date.now() });
    }
    res.json({ ok: true, opp, me: { rating: me.rating } });
  } catch (e) { console.error(e); res.status(500).json({ error: 'Something went wrong.' }); }
});
app.post('/api/arena/result', needDb, auth, async (req, res) => {
  try {
    const pid = req.player.id;
    const t = arenaTickets.get(pid);
    if (!t || Date.now() - t.at > ARENA_TICKET_MS) return res.status(400).json({ error: 'No ranked match in progress.' });
    if (Date.now() - (arenaLast.get(pid) || 0) < ARENA_MIN_GAP_MS) return res.status(429).json({ error: 'Slow down.' });
    arenaTickets.delete(pid);
    arenaLast.set(pid, Date.now());
    const won = !!req.body.won;
    const week = isoWeek();
    const me = await arenaRow(pid, week);
    if (!me) return res.status(400).json({ error: 'No ranked match in progress.' });
    const exp = 1 / (1 + 10 ** ((t.oppRating - me.rating) / 400));
    const delta = Math.round(ARENA_K * ((won ? 1 : 0) - exp));
    await pool.query(`UPDATE arena SET rating = GREATEST(0, rating + $3), wins = wins + $4, losses = losses + $5, updated_at = now()
      WHERE week = $1 AND player_id = $2`, [week, pid, delta, won ? 1 : 0, won ? 0 : 1]);
    // the defender's shadow fought too: half the swing (they don't get a match counted)
    if (!t.house && t.opp) {
      await pool.query('UPDATE arena SET rating = GREATEST(0, rating - $3) WHERE week = $1 AND player_id = $2', [week, t.opp, Math.round(delta / 2)]);
    }
    res.json({ ok: true, delta, board: await arenaBoard(pid) });
  } catch (e) { console.error(e); res.status(500).json({ error: 'Something went wrong.' }); }
});
// Last week's payout, once: rank 1 / top 3 / top 10 / everyone who played enough.
app.post('/api/arena/claim', needDb, auth, async (req, res) => {
  try {
    const w = lastWeek();
    const r = await arenaRow(req.player.id, w);
    if (!r || r.claimed || r.wins + r.losses < ARENA_PAY_MIN) return res.json({ ok: true, reward: null });
    const rank = await pool.query('SELECT COUNT(*)::int AS n FROM arena WHERE week = $1 AND wins + losses >= $2 AND rating > $3', [w, ARENA_PAY_MIN, r.rating]);
    const place = rank.rows[0].n + 1;
    await pool.query('UPDATE arena SET claimed = true WHERE week = $1 AND player_id = $2', [w, req.player.id]);
    const tier = place === 1 ? 'champion' : place <= 3 ? 'podium' : place <= 10 ? 'top10' : 'ranked';
    res.json({ ok: true, reward: { week: w, place, rating: r.rating, tier } });
  } catch (e) { console.error(e); res.status(500).json({ error: 'Something went wrong.' }); }
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
