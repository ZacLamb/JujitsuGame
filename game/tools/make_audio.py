"""Synthesizes all game audio (original, no samples). Run: python3 tools/make_audio.py"""
import numpy as np, wave, subprocess, os
SR = 44100
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'audio')
rng = np.random.default_rng(7)

def t(d): return np.arange(int(SR * d)) / SR
def env(n, a=0.005, r=0.2):
    e = np.ones(n); A = max(1, int(SR * a)); e[:A] = np.linspace(0, 1, A)
    R = min(n, int(SR * r)); e[-R:] *= np.linspace(1, 0, R) ** 2; return e
def tone(f, d, kind='sine', a=0.005, r=None, amp=1.0):
    x = t(d); ph = 2 * np.pi * f * x
    if kind == 'sine': s = np.sin(ph)
    elif kind == 'tri': s = 2 / np.pi * np.arcsin(np.sin(ph))
    elif kind == 'saw': s = 2 * (x * f % 1) - 1
    elif kind == 'pluck':
        s = sum(np.sin(ph * k) / k * np.exp(-x * (3 + k * 2)) for k in range(1, 6))
    return s * env(len(x), a, r if r is not None else d * 0.8) * amp
def noise(d, lp=0.0):
    n = rng.standard_normal(int(SR * d))
    if lp > 0:
        y = np.zeros_like(n); acc = 0.0
        for i, v in enumerate(n): acc += lp * (v - acc); y[i] = acc
        n = y / (np.abs(y).max() + 1e-9)
    return n
def mix(*parts):
    L = max(len(p) for p in parts); out = np.zeros(L)
    for p in parts: out[:len(p)] += p
    return out
def place(buf, snd, at):
    i = int(at * SR); j = min(len(buf), i + len(snd)); buf[i:j] += snd[:j - i]
def save_wav(name, x, vol=0.8):
    x = x / (np.abs(x).max() + 1e-9) * vol
    with wave.open(os.path.join(OUT, name + '.wav'), 'w') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
def save_ogg(name, x, vol=0.7):
    save_wav(name + '_tmp', x, vol)
    src = os.path.join(OUT, name + '_tmp.wav'); dst = os.path.join(OUT, name + '.ogg')
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', src, '-c:a', 'libvorbis', '-q:a', '3', dst], check=True)
    os.remove(src)
def midi(n): return 440 * 2 ** ((n - 69) / 12)

# ---------------- SFX
save_wav('click', tone(1800, 0.04, 'sine', 0.001, 0.035) * 0.6)
thud = mix(tone(70, 0.22, 'sine', 0.002, 0.2), noise(0.08, 0.15) * env(int(SR * 0.08), 0.001, 0.07) * 0.5)
save_wav('hit', thud)
save_wav('perfect', mix(tone(midi(84), 0.35, 'pluck', 0.002, 0.3), np.pad(tone(midi(91), 0.45, 'pluck', 0.002, 0.4), (int(SR * 0.07), 0))))
sw = noise(0.3, 0.05) * env(int(SR * 0.3), 0.05, 0.2) * np.linspace(1, 0.2, int(SR * 0.3))
save_wav('miss', mix(sw, tone(110, 0.3, 'tri', 0.01, 0.25) * 0.4), 0.6)
slap = noise(0.06, 0.6) * env(int(SR * 0.06), 0.0005, 0.05)
tapb = np.zeros(int(SR * 0.45)); place(tapb, slap, 0); place(tapb, slap, 0.16); place(tapb, slap * 0.8, 0.3)
save_wav('tap', tapb)
save_wav('squeeze', tone(220, 0.06, 'tri', 0.002, 0.05) * 0.5, 0.4)
arp = np.zeros(int(SR * 1.6))
for i, n in enumerate([60, 64, 67, 72, 76]): place(arp, tone(midi(n), 0.6, 'pluck', 0.002, 0.5), i * 0.11)
crowd = noise(1.6, 0.08) * env(int(SR * 1.6), 0.3, 0.8) * 0.35
save_wav('win', mix(arp, crowd))
lose = np.zeros(int(SR * 1.2))
for i, n in enumerate([64, 62, 59, 55]): place(lose, tone(midi(n), 0.5, 'tri', 0.01, 0.4) * 0.8, i * 0.2)
save_wav('lose', lose, 0.6)
lv = np.zeros(int(SR * 1.0))
for i, n in enumerate([67, 71, 74, 79, 83]): place(lv, tone(midi(n), 0.4, 'pluck', 0.002, 0.35), i * 0.07)
save_wav('levelup', lv)
col = np.zeros(int(SR * 0.5))
for i, n in enumerate([88, 91, 95]): place(col, tone(midi(n), 0.25, 'sine', 0.001, 0.2) * 0.6, i * 0.05)
save_wav('collect', col, 0.6)
save_wav('jump', tone(300, 0.12, 'sine', 0.002, 0.1) * np.linspace(1, 0.3, int(SR * 0.12)), 0.35)

# ---------------- music: explore (bossa-ish, 100 bpm, 16 bars: A A B A')
bpm = 100; beat = 60 / bpm; bars = 16; L = bars * 4 * beat
mus = np.zeros(int(SR * L) + SR)
progA = [[62, 65, 69, 72], [55, 59, 62, 65], [60, 64, 67, 71], [57, 61, 64, 67]]  # Dm9-ish, G7, Cmaj7, A7
rootsA = [38, 43, 36, 45]
progB = [[65, 69, 72, 76], [64, 67, 71, 74], [62, 65, 69, 72], [55, 59, 62, 65]]  # Fmaj7, Em7, Dm7, G7
rootsB = [41, 40, 38, 43]
melA = [[12, 9, 12, 7], [10, 7, 5, 4], [12, 11, 7, 4], [9, 7, 4, 1]]
for b in range(bars):
    section = 'B' if 8 <= b < 12 else 'A'
    ch = (progB if section == 'B' else progA)[b % 4]; r = (rootsB if section == 'B' else rootsA)[b % 4]; t0 = b * 4 * beat
    for n in ch:
        for off in ([0, 1.5, 2.5] if section == 'A' else [0, 2]):
            place(mus, tone(midi(n), beat * (0.9 if section == 'A' else 1.8), 'tri', 0.02, beat * 0.6) * 0.12, t0 + off * beat)
    place(mus, tone(midi(r), beat * 1.4, 'sine', 0.01, beat) * 0.5, t0)
    place(mus, tone(midi(r + 7), beat * 1.4, 'sine', 0.01, beat) * 0.4, t0 + 2 * beat)
    for k in range(16):
        if section == 'B' and k % 2:
            continue
        place(mus, noise(0.04, 0.7) * env(int(SR * 0.04), 0.001, 0.035) * (0.07 if k % 2 else 0.11), t0 + k * beat / 4)
    if b % 4 in (0, 2) and b < 15:
        line = melA[(b // 2) % 4]
        for i, iv in enumerate(line):
            place(mus, tone(midi(ch[0] + iv + 12), beat * 0.8, 'pluck', 0.003, beat * 0.7) * 0.22, t0 + (i * 0.75 + 0.5) * beat)
    if section == 'B' and b % 2 == 1:
        for i, iv in enumerate([7, 5, 4, 2, 0]):
            place(mus, tone(midi(ch[0] + iv + 12), beat * 0.6, 'pluck', 0.003, beat * 0.5) * 0.2, t0 + (i * 0.5 + 1) * beat)
mus = mus[:int(SR * L)]
save_ogg('music_explore', mus, 0.55)

# ---------------- music: roll (capoeira-inspired berimbau + atabaque, 120 bpm, 8 bars with fills)
bpm = 120; beat = 60 / bpm; bars = 8; L = bars * 4 * beat
rm = np.zeros(int(SR * L) + SR)
def berimbau(f, d=0.3):
    x = t(d); s = np.sin(2 * np.pi * f * x * (1 + 0.02 * np.exp(-x * 30)))
    s += 0.5 * np.sin(2 * np.pi * 2 * f * x) * np.exp(-x * 12)
    return s * env(len(x), 0.001, d * 0.9)
def drum(f, d=0.25, amp=1.0):
    x = t(d); return (np.sin(2 * np.pi * f * x * (1 + 0.5 * np.exp(-x * 40))) * np.exp(-x * 14) + noise(d, 0.3) * np.exp(-x * 50) * 0.3) * amp
for b in range(bars):
    t0 = b * 4 * beat
    pat = [(0, 110), (0.5, 110), (1, 123), (2, 110), (2.5, 110), (3, 98)] if b % 4 != 3 else [(0, 110), (1, 123), (1.5, 131), (2, 123), (3, 110), (3.5, 98)]
    for off, f in pat:
        place(rm, berimbau(f) * 0.5, t0 + off * beat)
    if b % 4 == 3:  # drum fill
        for k in range(8):
            place(rm, drum(120 + k * 8, amp=0.5 + k * 0.05) * 0.7, t0 + k * beat / 2)
    else:
        for off, f, a in [(0, 80, 1.0), (1, 140, 0.6), (1.5, 140, 0.5), (2, 80, 0.9), (3, 140, 0.6), (3.5, 160, 0.5)]:
            place(rm, drum(f, amp=a) * 0.7, t0 + off * beat)
    for k in range(8):
        place(rm, noise(0.05, 0.8) * env(int(SR * 0.05), 0.001, 0.04) * 0.12, t0 + k * beat / 2 + beat / 4)
    if b >= 4:  # agogô bell answers in the second half
        for off, n in [(0.5, 81), (1.0, 76), (2.5, 81), (3.0, 76)]:
            place(rm, tone(midi(n), 0.12, 'sine', 0.001, 0.1) * 0.12, t0 + off * beat)
rm = rm[:int(SR * L)]
save_ogg('music_roll', rm, 0.55)
print('audio written to', os.path.abspath(OUT)); print(sorted(os.listdir(OUT)))
