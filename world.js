// Live world: who's online, where they stand, and chat. One WebSocket per logged-in player at /ws.
//
// Client -> server (JSON):
//   {t:"hello", token, char}            char = {name, style, level, belt, body, skin, gi, look}
//   {t:"zone", zone}                    entered a zone (the client rebuilds its world)
//   {t:"pos", x, y, z, yaw, s, air, c}  ~8/s; s = speed 0..1, c = in combat
//   {t:"char", char}                    look / level changed
//   {t:"chat", ch, text, to?}           ch: say | zone | world | whisper | academy
//   {t:"report", name, reason}
//   {t:"party", to: id | [ids] | name, d}   party relay (any zone)
// Server -> client:
//   welcome / join / leave / st (batched positions) / char / chat / sys
const { URL } = require('url');
const WebSocket = require('ws');

const TICK_MS = 125;          // position broadcast rate (8/s)
const SAY_RANGE = 40;         // metres: /say reaches players this close
const MAX_TEXT = 200;
const RATE_N = 5;             // chat messages...
const RATE_MS = 10000;        // ...per 10 seconds, then a 30s chat timeout
const TIMEOUT_MS = 30000;
const ZONES = new Set(['caceres', 'pantanal', 'chapada', 'rio', 'socal', 'texas', 'everglades', 'sedona', 'cerrado', 'litoral', 'mata', 'serra', 'sertao', 'amazonia']);
// local testing only: WORLD_DEV=1 with no database accepts any token
const DEV = process.env.WORLD_DEV === '1';
const DUEL_RATE = 40;         // live duel relay: messages per second per client
const PARTY_RATE = 60;        // party relay (roster, chat, co-op dungeon snapshots): messages per second
const PARTY_MAX = 5;

// A short word filter (English + Portuguese). Matches whole words, ignoring case and simple
// letter swaps; the word is replaced with asterisks rather than the message being dropped.
const BAD = ['fuck', 'fucking', 'fucker', 'shit', 'bitch', 'cunt', 'dick', 'pussy', 'asshole', 'bastard', 'slut', 'whore',
  'fag', 'faggot', 'nigger', 'nigga', 'retard', 'porra', 'caralho', 'merda', 'puta', 'puto', 'foda', 'fodase', 'buceta',
  'cuzao', 'viado', 'arrombado', 'vagabunda', 'desgraca', 'piranha', 'otario', 'babaca'];
const LEET = { '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '@': 'a', '$': 's' };
const norm = (w) => w.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[013457@$]/g, (c) => LEET[c]).replace(/(.)\1+/g, '$1');
const BADSET = new Set(BAD.map(norm));
function clean(text) {
  let t = String(text || '').replace(/[\u0000-\u001f\u007f]/g, ' ').trim().slice(0, MAX_TEXT);
  t = t.replace(/\b(?:https?:\/\/|www\.)\S+/gi, '(link removed)').replace(/\b[a-z0-9-]+\.(?:com|net|org|io|gg|xyz|ru|br|co)\b\S*/gi, '(link removed)');
  return t.replace(/[\p{L}\p{N}@$]+/gu, (w) => (BADSET.has(norm(w)) ? '*'.repeat(w.length) : w));
}
const cleanName = (n) => String(n || 'Gringo').replace(/[^\p{L}\p{N} _'-]/gu, '').trim().slice(0, 16) || 'Gringo';
const num = (v, lim = 100000) => (Number.isFinite(+v) ? Math.max(-lim, Math.min(lim, +v)) : 0);

function attach(server, pool, isReady) {
  const wss = new WebSocket.Server({ noServer: true, maxPayload: 32 * 1024 });
  const clients = new Map();   // id -> client
  let nextId = 1;
  const recent = new Map();    // player_id -> last chat lines (report context)

  server.on('upgrade', (req, socket, head) => {
    if (new URL(req.url, 'http://x').pathname !== '/ws') return socket.destroy();
    wss.handleUpgrade(req, socket, head, (ws) => wss.emit('connection', ws, req));
  });

  const send = (c, m) => { if (c.ws.readyState === WebSocket.OPEN) c.ws.send(JSON.stringify(m)); };
  const inZone = (zone, except) => [...clients.values()].filter((c) => c.ok && c.zone === zone && c !== except);
  const seen = (zone, except) => inZone(zone, except).filter((c) => !c.invisible);
  const pub = (c) => ({ id: c.id, char: c.char, zone: c.zone, x: c.x, y: c.y, z: c.z, yaw: c.yaw, c: c.combat });
  const byName = (n) => [...clients.values()].find((c) => c.ok && c.char.name.toLowerCase() === String(n || '').toLowerCase());

  function leaveZone(c) {
    if (!c.zone) return;
    if (!c.invisible) for (const o of inZone(c.zone, c)) send(o, { t: 'leave', id: c.id });
    c.zone = '';
  }
  function enterZone(c, zone) {
    leaveZone(c);
    c.zone = zone;
    if (!c.invisible) for (const o of inZone(zone, c)) send(o, { t: 'join', ...pub(c) });
    send(c, { t: 'zone_list', players: seen(zone, c).map(pub) });
  }

  function sanitizeChar(ch) {
    ch = ch && typeof ch === 'object' ? ch : {};
    const s = JSON.stringify(ch.look || {});
    return {
      name: cleanName(ch.name), style: String(ch.style || '').slice(0, 16), faction: ch.faction === 'usa' ? 'usa' : 'brasil', level: Math.max(1, Math.min(99, ch.level | 0)),
      belt: Math.max(0, Math.min(9, ch.belt | 0)), body: ch.body === 'female' ? 'female' : 'male', skin: num(ch.skin, 1),
      gi: String(ch.gi || '').slice(0, 12), head: String(ch.head || '').replace(/[^a-z]/g, '').slice(0, 12), title: String(ch.title || '').slice(0, 40), look: s.length < 6000 ? ch.look || {} : {},
    };
  }

  function chat(c, m) {
    const now = Date.now();
    if (c.timeoutUntil > now) return send(c, { t: 'sys', text: `You're sending messages too fast. Wait ${Math.ceil((c.timeoutUntil - now) / 1000)}s.` });
    c.sent = c.sent.filter((t) => now - t < RATE_MS);
    c.sent.push(now);
    if (c.sent.length > RATE_N) {
      c.timeoutUntil = now + TIMEOUT_MS;
      return send(c, { t: 'sys', text: 'Slow down: chat paused for 30 seconds.' });
    }
    const text = clean(m.text);
    if (!text) return;
    if (c.last === text && now - c.lastAt < 15000) return send(c, { t: 'sys', text: 'You just said that.' });
    c.last = text; c.lastAt = now;
    const lines = recent.get(c.pid) || [];
    lines.push(`[${new Date().toISOString()}] ${m.ch}: ${text}`);
    recent.set(c.pid, lines.slice(-20));
    if (c.mutedUntil > now) return send(c, { t: 'sys', text: `A Game Master muted you for ${Math.ceil((c.mutedUntil - now) / 60000)} more minute(s).` });
    const msg = { t: 'chat', ch: m.ch, from: c.char.name, fid: c.id, style: c.char.style, text, gm: c.gm || undefined };
    if (m.ch === 'whisper') {
      const to = byName(m.to);
      if (!to) return send(c, { t: 'sys', text: `No one called ${cleanName(m.to)} is online.` });
      if (to === c) return;
      send(to, msg);
      return send(c, { ...msg, to: to.char.name, echo: true });
    }
    let targets;
    if (m.ch === 'academy') {
      if (!c.academy) return send(c, { t: 'sys', text: 'You are not in an academy. Open the Academy window to find one.' });
      targets = [...clients.values()].filter((o) => o.ok && o.academy && o.academy.id === c.academy.id);
    } else if (m.ch === 'world') targets = [...clients.values()].filter((o) => o.ok);
    else if (m.ch === 'zone') targets = inZone(c.zone).concat([c]);
    else {
      msg.ch = 'say';
      targets = inZone(c.zone).filter((o) => o === c || Math.hypot(o.x - c.x, o.z - c.z) <= SAY_RANGE).concat([c]);
    }
    const sent = new Set(targets);
    for (const o of sent) send(o, msg);
    for (const g of clients.values()) if (g.ok && g.gm && g.gmWatch && !sent.has(g)) send(g, { ...msg, watch: true, zone: c.zone });
  }

  async function report(c, m) {
    const t = byName(m.name);
    const reason = clean(m.reason).slice(0, 300);
    if (!t) return send(c, { t: 'sys', text: `No one called ${cleanName(m.name)} is online.` });
    try {
      await pool.query('INSERT INTO reports (reporter_id, target_id, target_name, reason, context) VALUES ($1, $2, $3, $4, $5)',
        [c.pid, t.pid, t.char.name, reason, (recent.get(t.pid) || []).join('\n')]);
      console.log(`report: ${c.char.name} -> ${t.char.name}: ${reason}`);
      send(c, { t: 'sys', text: `Thanks. ${t.char.name} has been reported. You can also /ignore them.` });
    } catch (e) {
      send(c, { t: 'sys', text: "Couldn't file the report right now." });
    }
  }

  // ---------------------------------------------------------------- Game Master tools
  // Only connections whose account has role 'gm' in the database get here (checked at hello).
  const glog = (c, action, target, detail) => pool.query('INSERT INTO gm_log (gm_id, action, target, detail) VALUES ($1, $2, $3, $4)', [c.pid, action, String(target || ''), String(detail || '').slice(0, 500)]).catch(() => {});
  const byId = (id) => clients.get(Number(id));
  async function gm(c, m) {
    const t = m.target != null ? byId(m.target) : null;
    switch (m.op) {
      case 'list':
        send(c, { t: 'gm_list', players: [...clients.values()].filter((o) => o.ok).map((o) => ({ id: o.id, name: o.char.name, style: o.char.style, level: o.char.level, zone: o.zone, x: +o.x.toFixed(1), z: +o.z.toFixed(1), combat: o.combat, gm: o.gm, muted: o.mutedUntil > Date.now(), invisible: !!o.invisible })) });
        break;
      case 'watch':
        c.gmWatch = !!m.on;
        send(c, { t: 'sys', text: c.gmWatch ? 'GM: watching chat in every zone.' : 'GM: chat watch off.' });
        break;
      case 'invisible':
        if (m.on && !c.invisible) { for (const o of inZone(c.zone, c)) send(o, { t: 'leave', id: c.id }); c.invisible = true; }
        else if (!m.on && c.invisible) { c.invisible = false; for (const o of inZone(c.zone, c)) send(o, { t: 'join', ...pub(c) }); }
        send(c, { t: 'sys', text: c.invisible ? 'GM: you are invisible to players.' : 'GM: you are visible again.' });
        glog(c, 'invisible', '', String(!!c.invisible));
        break;
      case 'announce': {
        const text = clean(m.text);
        if (!text) return;
        for (const o of clients.values()) if (o.ok) send(o, { t: 'announce', text, from: c.char.name });
        glog(c, 'announce', '', text);
        break;
      }
      case 'kick':
        if (!t) return send(c, { t: 'sys', text: 'GM: no such player online.' });
        send(t, { t: 'sys', text: `You were removed from the live world by a Game Master${m.reason ? ': ' + clean(m.reason) : '.'}` });
        t.ws.close(4000, 'kicked');
        send(c, { t: 'sys', text: `GM: kicked ${t.char.name}.` });
        glog(c, 'kick', t.char.name, m.reason);
        break;
      case 'mute': {
        if (!t) return send(c, { t: 'sys', text: 'GM: no such player online.' });
        const mins = Math.max(0, Math.min(10080, Number(m.minutes) || 10));
        t.mutedUntil = mins ? Date.now() + mins * 60000 : 0;
        await pool.query('UPDATE players SET muted_until = $2 WHERE id = $1', [t.pid, mins ? new Date(t.mutedUntil) : null]).catch(() => {});
        send(t, { t: 'sys', text: mins ? `A Game Master muted your chat for ${mins} minute(s).` : 'A Game Master unmuted your chat.' });
        send(c, { t: 'sys', text: mins ? `GM: muted ${t.char.name} for ${mins} min.` : `GM: unmuted ${t.char.name}.` });
        glog(c, 'mute', t.char.name, String(mins));
        break;
      }
      case 'goto':
        if (!t) return send(c, { t: 'sys', text: 'GM: no such player online.' });
        send(c, { t: 'gm_goto', zone: t.zone, x: t.x, y: t.y, z: t.z, name: t.char.name });
        break;
      case 'reports': {
        const r = await pool.query('SELECT r.id, r.target_name, r.reason, r.context, extract(epoch from r.created_at) AS at, p.email AS reporter FROM reports r LEFT JOIN players p ON p.id = r.reporter_id ORDER BY r.id DESC LIMIT 30').catch(() => ({ rows: [] }));
        send(c, { t: 'gm_reports', reports: r.rows.map((x) => ({ id: x.id, target: x.target_name, reason: x.reason, context: x.context, at: Number(x.at), reporter: String(x.reporter || '').replace(/(^.).*(@.*$)/, '$1***$2') })) });
        break;
      }
      default:
    }
  }

  wss.on('connection', (ws) => {
    const c = { ws, id: 0, ok: false, pid: 0, char: {}, zone: '', x: 0, y: 0, z: 0, yaw: 0, s: 0, air: 0, combat: 0, sent: [], timeoutUntil: 0, alive: true };
    ws.on('pong', () => { c.alive = true; });
    const helloTimer = setTimeout(() => { if (!c.ok) ws.close(4001, 'hello timeout'); }, 10000);
    ws.on('message', async (raw) => {
      let m;
      try { m = JSON.parse(raw); } catch { return; }
      if (!m || typeof m !== 'object') return;
      if (!c.ok) {
        if (m.t === 'hello' && DEV && !pool) {
          clearTimeout(helloTimer);
          c.pid = -(nextId + 1000);
          c.id = nextId++;
          c.ok = true;
          c.char = sanitizeChar(m.char);
          clients.set(c.id, c);
          send(c, { t: 'welcome', id: c.id, gm: false, online: [...clients.values()].filter((o) => o.ok).length });
          return;
        }
        if (m.t !== 'hello' || !pool || !isReady()) return;
        const r = await pool.query('SELECT p.id, p.role, extract(epoch from p.muted_until) AS mu FROM sessions s JOIN players p ON p.id = s.player_id WHERE s.token = $1', [String(m.token || '')]).catch(() => ({ rows: [] }));
        if (!r.rows.length) return ws.close(4003, 'not logged in');
        clearTimeout(helloTimer);
        c.pid = r.rows[0].id;
        c.gm = r.rows[0].role === 'gm';
        c.mutedUntil = r.rows[0].mu ? Number(r.rows[0].mu) * 1000 : 0;
        // one live connection per account: the newest wins
        for (const o of clients.values()) if (o.pid === c.pid) { send(o, { t: 'sys', text: 'You logged in somewhere else.' }); o.ws.close(4000, 'replaced'); }
        c.id = nextId++;
        c.ok = true;
        c.char = sanitizeChar(m.char);
        const ar = await pool.query('SELECT a.id, a.tag FROM academy_members m JOIN academies a ON a.id = m.academy_id WHERE m.player_id = $1', [c.pid]).catch(() => ({ rows: [] }));
        c.academy = ar.rows[0] || null;
        if (c.academy) c.char.tag = c.academy.tag;
        clients.set(c.id, c);
        send(c, { t: 'welcome', id: c.id, gm: c.gm, online: [...clients.values()].filter((o) => o.ok).length, academy: c.academy });
        return;
      }
      switch (m.t) {
        case 'zone':
          if (ZONES.has(m.zone)) enterZone(c, m.zone);
          break;
        case 'pos':
          c.x = num(m.x); c.y = num(m.y); c.z = num(m.z); c.yaw = num(m.yaw, 10); c.s = num(m.s, 1); c.air = m.air ? 1 : 0; c.combat = m.c ? 1 : 0;
          c.moved = true;
          break;
        case 'char':
          c.char = sanitizeChar(m.char);
          if (c.academy) c.char.tag = c.academy.tag;   // the tag comes from the server, never the client
          for (const o of inZone(c.zone, c)) send(o, { t: 'char', id: c.id, char: c.char });
          break;
        case 'chat':
          if (['say', 'zone', 'world', 'whisper', 'academy'].includes(m.ch)) chat(c, m);
          break;
        case 'who': {
          const list = [...clients.values()].filter((o) => o.ok).slice(0, 40).map((o) => `${o.char.name} (${o.char.level} ${o.char.style || '?'}, ${o.zone || '...'})`);
          send(c, { t: 'sys', text: `${list.length} online: ${list.join(', ')}` });
          break;
        }
        case 'report':
          report(c, m);
          break;
        case 'duel': {
          // live duels: a relay between two players in the same zone (the challenger's game
          // runs the fight, the other sends inputs and gets snapshots)
          const now = Date.now();
          if (!c.duelWin || now - c.duelWin > 1000) { c.duelWin = now; c.duelN = 0; }
          if (++c.duelN > DUEL_RATE) break;
          const to = clients.get(m.to | 0);
          if (to && to.ok && to !== c && to.zone === c.zone) send(to, { t: 'duel', from: c.id, d: m.d });
          break;
        }
        case 'party': {
          // parties: a relay to one or more players anywhere in the world (by id, or one name).
          // The party leader's game owns the roster and runs co-op dungeons; see party.gd / coop.gd
          const now = Date.now();
          if (!c.partyWin || now - c.partyWin > 1000) { c.partyWin = now; c.partyN = 0; }
          if (++c.partyN > PARTY_RATE) break;
          const d = m.d && typeof m.d === 'object' ? m.d : null;
          if (!d) break;
          if (d.k === 'chat') d.text = clean(d.text);
          let targets = [];
          if (m.name) {
            const want = String(m.name).toLowerCase();
            const hit = [...clients.values()].find((o) => o.ok && o !== c && !o.invisible && String(o.char.name || '').toLowerCase() === want);
            if (!hit) { send(c, { t: 'party', from: 0, d: { k: 'nf', name: cleanName(m.name) } }); break; }
            targets = [hit];
          } else {
            const ids = Array.isArray(m.to) ? m.to.slice(0, PARTY_MAX) : [m.to];
            targets = ids.map((i) => clients.get(i | 0)).filter((o) => o && o.ok && o !== c);
          }
          for (const o of targets) send(o, { t: 'party', from: c.id, zone: c.zone, d });
          break;
        }
        case 'emote': {
          // /oss, /wave...: everyone in the zone sees the pose (one per second)
          const now = Date.now();
          if (now - (c.emoteAt || 0) < 1000 || !/^[a-z]{2,10}$/.test(String(m.e || ''))) break;
          c.emoteAt = now;
          for (const o of inZone(c.zone, c)) send(o, { t: 'emote', id: c.id, e: m.e });
          break;
        }
        case 'gm':
          if (c.gm) gm(c, m);
          else send(c, { t: 'sys', text: 'Unknown command.' });
          break;
        default:
      }
    });
    ws.on('close', () => {
      clearTimeout(helloTimer);
      if (c.ok) { leaveZone(c); clients.delete(c.id); }
    });
    ws.on('error', () => {});
  });

  // batched positions per zone, 8 times a second
  setInterval(() => {
    const zones = new Map();
    for (const c of clients.values()) {
      if (!c.ok || !c.zone) continue;
      if (!zones.has(c.zone)) zones.set(c.zone, []);
      zones.get(c.zone).push(c);
    }
    for (const list of zones.values()) {
      if (list.length < 2) continue;
      const moved = list.filter((c) => c.moved && !c.invisible);
      if (!moved.length) continue;
      const rows = moved.map((c) => [c.id, +c.x.toFixed(2), +c.y.toFixed(2), +c.z.toFixed(2), +c.yaw.toFixed(2), +c.s.toFixed(2), c.air, c.combat]);
      const msg = JSON.stringify({ t: 'st', p: rows });
      for (const c of list) if (c.ws.readyState === WebSocket.OPEN) c.ws.send(msg);
    }
    for (const c of clients.values()) c.moved = false;
  }, TICK_MS);

  // drop dead sockets
  setInterval(() => {
    for (const c of clients.values()) {
      if (!c.alive) { c.ws.terminate(); continue; }
      c.alive = false;
      try { c.ws.ping(); } catch {}
    }
  }, 30000);

  return {
    online: () => [...clients.values()].filter((c) => c.ok).length,
    onlineIds: () => new Set([...clients.values()].filter((c) => c.ok && !c.invisible).map((c) => c.pid)),
    // academy joined / left / kicked: update the live tag and tell the zone
    setAcademy(pid, a) {
      for (const c of clients.values()) {
        if (!c.ok || c.pid !== pid) continue;
        c.academy = a;
        if (a) c.char.tag = a.tag; else delete c.char.tag;
        send(c, { t: 'academy', academy: a });
        for (const o of inZone(c.zone, c)) send(o, { t: 'char', id: c.id, char: c.char });
      }
    },
    academySys(id, text) {
      for (const c of clients.values()) if (c.ok && c.academy && c.academy.id === id) send(c, { t: 'chat', ch: 'academy', sys: true, text });
    },
  };
}

module.exports = { attach, clean };
