// Test bot for the live world: registers, joins Cáceres, walks a circle near the spawn and chats.
// usage: node bot.js http://localhost:3077 <name> <style> <cx> <cz>
const base = process.argv[2] || 'http://localhost:3077';
const name = process.argv[3] || 'Bot';
const style = process.argv[4] || 'wrestler';
const cx = +(process.argv[5] || 3), cz = +(process.argv[6] || 18);
const WebSocket = require(require.resolve('ws', { paths: ['/home/claude/jujitsugame'] }));
const looks = {
  wrestler: { kit: 'nogi', rash: { color: { _c: 'c72929ff' } }, spats: { color: { _c: 'c72929ff' } }, head: { color: { _c: '1f1f24ff' } }, head_piece: 'EarGuards' },
  judoka: { kit: 'gi', jacket: { color: { _c: 'f0f2f7ff' }, trim: { _c: '1f408cff' }, pattern: 'feathers', accent: { _c: '9ebdf2ff' }, pscale: 0.8 }, pants: { color: { _c: 'f0f2f7ff' } } },
  athlete: { kit: 'nogi', rash: { color: { _c: 'ff8c1fff' } }, spats: { color: { _c: '1a1a1fff' }, pattern: 'stripes', accent: { _c: 'ff8c1fff' }, pscale: 1.6 }, head: { color: { _c: 'ff9e29ff' } }, head_piece: 'Headband' },
};
(async () => {
  const email = `${name.toLowerCase()}${Date.now() % 100000}@example.com`;
  const r = await fetch(base + '/api/register', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ email, password: 'oss12345' }) });
  const { token } = await r.json();
  const ws = new WebSocket(base.replace('http', 'ws') + '/ws');
  let t = 0;
  ws.on('open', () => {
    ws.send(JSON.stringify({ t: 'hello', token, char: { name, style, level: 23, belt: 2, body: style === 'athlete' ? 'female' : 'male', skin: 0.6, gi: 'f2f2eeff', look: looks[style] } }));
  });
  ws.on('message', (raw) => {
    const m = JSON.parse(raw);
    if (m.t !== 'st') console.log(name, 'got', JSON.stringify(m).slice(0, 160));
    if (m.t === 'welcome') {
      ws.send(JSON.stringify({ t: 'zone', zone: 'caceres' }));
      setInterval(() => {
        t += 0.125;
        const a = t * 0.35;
        const x = cx + Math.cos(a) * 3, z = cz + Math.sin(a) * 3;
        ws.send(JSON.stringify({ t: 'pos', x, y: 0.05, z, yaw: Math.atan2(Math.sin(a), -Math.cos(a)), s: 0.45, air: 0, c: 0 }));
      }, 125);
      const lines = [['say', 'Oss! Anyone up for rolls at the plaza?'], ['zone', 'LFG Covil da Sucuri, need a coach'], ['world', 'first time here, this game is sick'], ['say', 'that porra jacaré boss ate me alive lol']];
      let li = Math.floor(Math.random() * lines.length);
      setInterval(() => { const [ch, text] = lines[li++ % lines.length]; ws.send(JSON.stringify({ t: 'chat', ch, text })); }, 2500 + Math.random() * 1500);
    }
  });
  ws.on('close', (c) => console.log(name, 'closed', c));
})();
