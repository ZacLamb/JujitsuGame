"""Exploration music per zone (Team USA zones, plus Rio, Pantanal and Chapada) (original, synthesized, no samples).
python3 tools/make_music_usa.py  ->  assets/audio/music_explore_{texas,everglades,sedona,socal}.ogg
Uses the helpers from make_audio.py (tone, noise, env, place, save_ogg)."""
import numpy as np, os
src = open(os.path.join(os.path.dirname(__file__), 'make_audio.py')).read().split('# ---------------- SFX')[0]
exec(src)
rng = np.random.default_rng(23)


def echo(x, delay=0.28, fb=0.35, n=4):
    out = x.copy()
    d = int(SR * delay)
    g = fb
    for k in range(1, n + 1):
        out[d * k:] += x[:len(x) - d * k] * g
        g *= fb
    return out


def strum(notes, d, amp=0.12, spread=0.012):
    buf = np.zeros(int(SR * (d + spread * len(notes))) + 10)
    for i, nn in enumerate(notes):
        place(buf, tone(midi(nn), d, 'pluck', 0.002, d * 0.9) * amp, i * spread)
    return buf


def fiddle(f, d, amp=0.2):
    x = t(d)
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.5 * x) * np.clip(x / 0.15, 0, 1)
    ph = 2 * np.pi * np.cumsum(np.full(len(x), f) * vib) / SR
    s = sum(np.sin(ph * k) / k for k in range(1, 7))
    return s * env(len(x), 0.04, d * 0.4) * amp


def slide(f0, f1, d, amp=0.2):
    x = t(d)
    f = f0 + (f1 - f0) * np.clip(x / (d * 0.3), 0, 1)
    ph = 2 * np.pi * np.cumsum(f) / SR
    s = np.sin(ph) + 0.4 * np.sin(2 * ph) + 0.2 * np.sin(3 * ph)
    return s * env(len(x), 0.01, d * 0.6) * amp


def kick(amp=1.0):
    x = t(0.25)
    return np.sin(2 * np.pi * 55 * x * (1 + 2 * np.exp(-x * 30))) * np.exp(-x * 12) * amp


def snare(amp=1.0, d=0.18):
    return noise(d, 0.5) * env(int(SR * d), 0.001, d * 0.8) * amp


def flute(f, d, amp=0.2):
    x = t(d)
    vib = 1 + 0.004 * np.sin(2 * np.pi * 4.5 * x)
    ph = 2 * np.pi * np.cumsum(np.full(len(x), f) * vib) / SR
    breath = noise(d, 0.2) * 0.08
    return (np.sin(ph) + 0.15 * np.sin(2 * ph) + breath) * env(len(x), 0.08, d * 0.5) * amp


# ---------------------------------------------------------------- Texas: Hill Country two-step
def texas():
    bpm = 112; beat = 60 / bpm; bars = 16; L = bars * 4 * beat
    m = np.zeros(int(SR * L) + SR)
    prog = [('G', 43, [55, 59, 62]), ('C', 48, [60, 64, 67]), ('G', 43, [55, 59, 62]), ('D', 50, [57, 62, 66])] * 2 + \
           [('C', 48, [60, 64, 67]), ('G', 43, [55, 59, 62]), ('D', 50, [57, 62, 66]), ('G', 43, [55, 59, 62])] * 2
    tune = [[79, 76, 74, 71], [72, 74, 76, 79], [74, 71, 69, 67], [69, 71, 74, 69],
            [79, 81, 79, 76], [76, 74, 72, 76], [74, 76, 78, 74], [71, 74, 67, 0]]
    for b, (_, root, tri) in enumerate(prog):
        t0 = b * 4 * beat
        place(m, tone(midi(root), beat * 0.9, 'sine', 0.005, beat * 0.7) * 0.5, t0)                 # boom
        place(m, tone(midi(root + 7), beat * 0.9, 'sine', 0.005, beat * 0.7) * 0.42, t0 + 2 * beat)  # alternating bass
        for off in (1, 3):                                                                           # chick
            place(m, strum(tri, beat * 0.5, 0.1), t0 + off * beat)
        for k in range(8):
            place(m, noise(0.03, 0.8) * env(int(SR * 0.03), 0.001, 0.025) * (0.05 if k % 2 else 0.08), t0 + k * beat / 2)
        if b % 2 == 0:
            line = tune[(b // 2) % len(tune)]
            for i, nn in enumerate(line):
                if nn:
                    place(m, fiddle(midi(nn), beat * 0.95, 0.16), t0 + i * beat)
    return echo(m[:int(SR * L)], 0.18, 0.2, 2)


# ---------------------------------------------------------------- Everglades: slow swamp blues
def everglades():
    bpm = 74; beat = 60 / bpm; L = 12 * 4 * beat
    m = np.zeros(int(SR * L) + SR)
    roots = [40, 40, 40, 40, 45, 45, 40, 40, 47, 45, 40, 47]   # E7 E7 E7 E7 A7 A7 E7 E7 B7 A7 E7 B7
    for b, r in enumerate(roots):
        t0 = b * 4 * beat
        for k in range(4):   # shuffle bass: root, 5th, 6th, b7 on the long-short triplet feel
            iv = [0, 7, 9, 10][k]
            place(m, tone(midi(r + iv), beat * 0.6, 'tri', 0.005, beat * 0.5) * 0.4, t0 + k * beat)
            place(m, tone(midi(r + iv), beat * 0.25, 'tri', 0.005, beat * 0.2) * 0.25, t0 + k * beat + beat * 2 / 3)
        for k in range(4):   # brushes
            place(m, noise(0.12, 0.25) * env(int(SR * 0.12), 0.02, 0.1) * 0.06, t0 + k * beat + beat * 2 / 3)
        place(m, kick(0.4), t0)
        place(m, kick(0.3), t0 + 2 * beat)
        if b in (0, 2, 4, 6, 8, 10):
            phrase = [(0.5, 67, 64), (1.5, 64, 64), (2.0, 62, 62), (2.67, 64, 59)] if b % 4 == 0 else [(1.0, 71, 69), (2.0, 67, 67), (3.0, 64, 62)]
            for off, f0, f1 in phrase:
                place(m, slide(midi(f0 + (r - 40) + 12 - 1), midi(f1 + (r - 40) + 12), beat * 1.2, 0.14), t0 + off * beat)
    return echo(m[:int(SR * L)], 0.32, 0.3, 3)


# ---------------------------------------------------------------- Sedona: red-rock canyon, open and slow
def sedona():
    bpm = 78; beat = 60 / bpm; bars = 16; L = bars * 4 * beat
    m = np.zeros(int(SR * L) + SR)
    # a slow drone pad on D and A, breathing in and out
    x = t(L)
    pad = (np.sin(2 * np.pi * midi(38) * x) + 0.6 * np.sin(2 * np.pi * midi(45) * x) + 0.3 * np.sin(2 * np.pi * midi(50) * x))
    pad *= 0.06 * (0.7 + 0.3 * np.sin(2 * np.pi * x / (8 * beat)))
    m[:len(pad)] += pad
    scale = [62, 64, 65, 67, 69, 72, 74]   # D dorian-ish (no 6th for an open, high-desert sound)
    phrases = [[69, 67, 64, 62], [72, 69, 67, 69], [74, 72, 69, 67], [64, 67, 69, 62]]
    for b in range(bars):
        t0 = b * 4 * beat
        # sparse guitar harmonics
        for off in (0, 1.5, 3):
            place(m, tone(midi(rng.choice([62, 69, 74, 76])), beat * 2, 'pluck', 0.002, beat * 1.8) * 0.12, t0 + off * beat)
        if b % 2 == 1:
            for i, nn in enumerate(phrases[(b // 2) % 4]):
                place(m, flute(midi(nn), beat * 1.6, 0.13), t0 + i * beat * 0.9)
        place(m, tone(55, beat * 2, 'sine', 0.01, beat * 1.5) * 0.25, t0)   # soft low drum
    return echo(m[:int(SR * L)], 0.45, 0.4, 4)


# ---------------------------------------------------------------- San Diego: clean surf guitar
def socal():
    bpm = 132; beat = 60 / bpm; bars = 16; L = bars * 4 * beat
    m = np.zeros(int(SR * L) + SR)
    prog = [(45, [57, 60, 64]), (43, [55, 59, 62]), (41, [53, 57, 60]), (40, [52, 56, 59])] * 4   # Am G F E
    mel = [[76, 74, 72, 71], [74, 72, 71, 69], [72, 71, 69, 67], [68, 69, 71, 64]]
    for b, (root, tri) in enumerate(prog):
        t0 = b * 4 * beat
        for k in range(8):   # driving eighth-note bass
            place(m, tone(midi(root), beat * 0.45, 'tri', 0.003, beat * 0.4) * 0.38, t0 + k * beat / 2)
        place(m, kick(0.7), t0); place(m, kick(0.6), t0 + 2 * beat)
        place(m, snare(0.35), t0 + beat); place(m, snare(0.35), t0 + 3 * beat)
        for k in range(8):
            place(m, noise(0.02, 0.9) * env(int(SR * 0.02), 0.001, 0.018) * 0.06, t0 + k * beat / 2)
        for off in (0.5, 2.5):
            place(m, strum(tri, beat * 0.4, 0.08, 0.006), t0 + off * beat)
        if b >= 4:   # tremolo-picked lead on the melody
            line = mel[b % 4]
            for i, nn in enumerate(line):
                for r in range(4):
                    place(m, tone(midi(nn), beat / 4, 'pluck', 0.001, beat / 4) * 0.13, t0 + i * beat + r * beat / 4)
    return echo(m[:int(SR * L)], 0.22, 0.35, 3)



# ---------------------------------------------------------------- Brazil: Rio (samba), Pantanal (chamamé waltz), Chapada (moda de viola)
def rio():
    bpm = 100; beat = 60 / bpm; bars = 16; L = bars * 4 * beat
    m = np.zeros(int(SR * L) + SR)
    prog = [(45, [57, 60, 64, 67]), (50, [57, 60, 62, 66]), (43, [55, 59, 62, 66]), (48, [55, 60, 64, 71])] * 4   # Am7 D7 Gmaj7 Cmaj7
    cav = [0, 0.75, 1.5, 2.0, 2.75, 3.5]    # cavaquinho syncopation
    tam = [0, 0.5, 0.75, 1.25, 1.75, 2.0, 2.5, 2.75, 3.25, 3.75]
    for b, (root, ch) in enumerate(prog):
        t0 = b * 4 * beat
        place(m, kick(0.45), t0 + beat); place(m, kick(0.75), t0 + 3 * beat)     # surdo on 2 and 4 (marcação)
        place(m, tone(midi(root), beat * 0.8, 'sine', 0.005, beat * 0.6) * 0.4, t0)
        place(m, tone(midi(root + 7), beat * 0.8, 'sine', 0.005, beat * 0.6) * 0.32, t0 + 2 * beat)
        for off in cav:
            place(m, strum([n + 12 for n in ch], beat * 0.3, 0.06, 0.004), t0 + off * beat)
        for off in tam:
            place(m, tone(1400, 0.05, 'sine', 0.001, 0.04) * 0.08 + noise(0.05, 0.9)[:int(SR * 0.05)] * env(int(SR * 0.05), 0.001, 0.04) * 0.04, t0 + off * beat)
        for k in range(16):
            place(m, noise(0.03, 0.85) * env(int(SR * 0.03), 0.001, 0.025) * 0.04, t0 + k * beat / 4)
        if b % 4 in (1, 3) and b >= 4:
            for i, iv in enumerate([12, 10, 7, 9, 7, 4]):
                place(m, flute(midi(ch[0] + iv + 12), beat * 0.45, 0.1), t0 + (i * 0.5 + 0.5) * beat)
    return echo(m[:int(SR * L)], 0.2, 0.2, 2)


def accordion(f, d, amp=0.15):
    x = t(d)
    s = sum(np.sin(2 * np.pi * f * k * x) / k for k in range(1, 6)) + 0.6 * sum(np.sin(2 * np.pi * f * 1.004 * k * x) / k for k in range(1, 4))
    return s * (0.85 + 0.15 * np.sin(2 * np.pi * 5 * x)) * env(len(x), 0.04, d * 0.3) * amp


def pantanal():
    bpm = 120; beat = 60 / bpm; bars = 24; L = bars * 3 * beat   # 3/4 waltz feel
    m = np.zeros(int(SR * L) + SR)
    prog = [(38, [62, 65, 69]), (45, [61, 64, 69]), (45, [61, 64, 67]), (38, [62, 65, 69]),
            (43, [62, 67, 70]), (38, [62, 65, 69]), (45, [61, 64, 67]), (38, [62, 65, 69])] * 3
    mel = [[74, 72, 70], [69, 70, 72], [73, 72, 69], [69, 0, 0], [70, 72, 74], [77, 76, 74], [73, 76, 73], [74, 0, 0]]
    for b, (root, tri) in enumerate(prog):
        t0 = b * 3 * beat
        place(m, tone(midi(root), beat, 'sine', 0.005, beat * 0.8) * 0.45, t0)
        for off in (1, 2):
            place(m, strum(tri, beat * 0.6, 0.07), t0 + off * beat)
        line = mel[b % 8]
        for i, nn in enumerate(line):
            if nn:
                place(m, accordion(midi(nn), beat * 0.95, 0.11), t0 + i * beat)
    return echo(m[:int(SR * L)], 0.25, 0.2, 2)


def chapada():
    bpm = 84; beat = 60 / bpm; bars = 16; L = bars * 4 * beat
    m = np.zeros(int(SR * L) + SR)
    prog = [(40, 'E'), (45, 'A'), (47, 'B'), (40, 'E')] * 4
    # viola caipira: melody in parallel thirds, plucked, with drone strings
    phr = [[76, 74, 72, 71], [72, 74, 76, 74], [75, 74, 72, 71], [71, 72, 71, 0]]
    third = {76: 72, 74: 71, 72: 69, 71: 68, 75: 71, 0: 0}
    for b, (root, _) in enumerate(prog):
        t0 = b * 4 * beat
        place(m, tone(midi(root), beat * 3, 'pluck', 0.002, beat * 2.5) * 0.3, t0)
        place(m, tone(midi(root + 12), beat * 2, 'pluck', 0.002, beat * 1.8) * 0.12, t0 + 2 * beat)
        line = phr[b % 4]
        for i, nn in enumerate(line):
            if nn:
                place(m, tone(midi(nn), beat * 0.9, 'pluck', 0.002, beat * 0.8) * 0.18, t0 + i * beat)
                place(m, tone(midi(third.get(nn, nn - 3)), beat * 0.9, 'pluck', 0.002, beat * 0.8) * 0.14, t0 + i * beat + 0.01)
    return echo(m[:int(SR * L)], 0.4, 0.3, 3)

import sys
TRACKS = [('texas', texas), ('everglades', everglades), ('sedona', sedona), ('socal', socal), ('rio', rio), ('pantanal', pantanal), ('chapada', chapada)]
for name, fn in [x for x in TRACKS if len(sys.argv) < 2 or x[0] in sys.argv[1:]]:
    save_ogg('music_explore_' + name, fn(), 0.5)
    print('saved music_explore_' + name)
for f in os.listdir(OUT):
    if f.endswith('_tmp.wav'):
        os.remove(os.path.join(OUT, f))
