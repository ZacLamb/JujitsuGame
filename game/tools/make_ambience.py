"""Synthesizes the zone ambience loops and footsteps (original, no samples).
Run: python3 tools/make_ambience.py   (needs numpy, scipy, ffmpeg)

Loops are seamless: the tail is crossfaded into the head.
"""
import os, subprocess, wave
import numpy as np
from scipy.signal import lfilter, butter

SR = 22050
L = 24.0
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'audio')
rng = np.random.default_rng(11)


def n(d):
    return rng.standard_normal(int(SR * d))


def lp(x, hz):
    b, a = butter(2, hz / (SR / 2), 'low')
    return lfilter(b, a, x)


def hp(x, hz):
    b, a = butter(2, hz / (SR / 2), 'high')
    return lfilter(b, a, x)


def bp(x, lo, hi):
    b, a = butter(2, [lo / (SR / 2), hi / (SR / 2)], 'band')
    return lfilter(b, a, x)


def tt(d):
    return np.arange(int(SR * d)) / SR


def place(buf, snd, at):
    i = int(at * SR) % len(buf)
    j = min(len(buf), i + len(snd))
    buf[i:j] += snd[:j - i]
    if i + len(snd) > len(buf):  # wrap around the loop
        rest = snd[j - i:]
        buf[:len(rest)] += rest


def norm(x, peak=0.9):
    return x / (np.abs(x).max() + 1e-9) * peak


def seamless(x, fade=1.5):
    f = int(SR * fade)
    head = x[:f].copy()
    tail = x[-f:]
    ramp = np.linspace(0, 1, f)
    x[:f] = head * ramp + tail * (1 - ramp)
    return x[:-f]


def save(name, x, peak=0.6, q=3):
    x = norm(x, peak)
    tmp = os.path.join(OUT, name + '_tmp.wav')
    with wave.open(tmp, 'w') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    if name.startswith('step'):
        os.replace(tmp, os.path.join(OUT, name + '.wav'))
        return
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', tmp, '-c:a', 'libvorbis', '-q:a', str(q),
                    os.path.join(OUT, name + '.ogg')], check=True)
    os.remove(tmp)


# ---------------------------------------------------------------- building blocks
def chirp(f0, f1, d, amp=1.0):
    x = tt(d)
    f = np.linspace(f0, f1, len(x))
    ph = 2 * np.pi * np.cumsum(f) / SR
    e = np.sin(np.pi * np.clip(x / d, 0, 1)) ** 2
    return np.sin(ph) * e * amp


def bird_song(base, notes=4):
    out = []
    for k in range(notes):
        f0 = base * rng.uniform(0.85, 1.25)
        out.append(chirp(f0, f0 * rng.uniform(0.7, 1.5), rng.uniform(0.05, 0.14), rng.uniform(0.5, 1.0)))
        out.append(np.zeros(int(SR * rng.uniform(0.03, 0.09))))
    return np.concatenate(out)


def croak(f=140, d=0.22):
    x = tt(d)
    pulse = (np.sin(2 * np.pi * 28 * x) > 0).astype(float)
    tone = np.sin(2 * np.pi * f * x) + 0.5 * np.sin(2 * np.pi * f * 2.02 * x)
    return tone * pulse * np.sin(np.pi * x / d) ** 1.5


def wind(d, depth=0.6):
    x = lp(n(d), 500)
    lfo = 0.6 + depth * 0.4 * np.sin(2 * np.pi * tt(d) * 0.11) + 0.2 * np.sin(2 * np.pi * tt(d) * 0.037)
    return x * lfo


def river(d):
    return bp(n(d), 300, 2600) * (0.8 + 0.2 * np.sin(2 * np.pi * tt(d) * 0.3))


def insects(d, f=5200):
    x = tt(d)
    carrier = bp(n(d), f * 0.85, f * 1.15)
    am = 0.5 + 0.5 * np.sin(2 * np.pi * 34 * x)
    swell = 0.6 + 0.4 * np.sin(2 * np.pi * x / 7.0)
    return carrier * am * swell


def crickets(d):
    x = tt(d)
    out = np.zeros(len(x))
    for f, rate, phase in [(4300, 2.4, 0.0), (4700, 2.9, 0.3), (3900, 2.1, 0.6)]:
        gate = (np.sin(2 * np.pi * rate * x + phase * 6) > 0.55).astype(float)
        trill = (np.sin(2 * np.pi * 45 * x) > 0).astype(float)
        out += np.sin(2 * np.pi * f * x) * gate * trill * 0.5
    return lp(out, 6000)


def waves(d):
    x = tt(d)
    base = lp(n(d), 900)
    swell = np.zeros(len(x))
    period = 6.0
    for k in range(int(d / period) + 2):
        c = k * period + rng.uniform(-0.6, 0.6)
        swell += np.exp(-((x - c) ** 2) / 1.2) + 0.6 * np.exp(-((x - c - 1.4) ** 2) / 0.5)
    return base * (0.25 + swell) + hp(n(d), 3000) * swell * 0.25


def gull(d=0.5):
    x = tt(d)
    f = 1800 - 700 * x / d
    ph = 2 * np.pi * np.cumsum(f) / SR
    s = np.sign(np.sin(ph)) * 0.3 + np.sin(ph)
    return bp(s, 900, 3500) * np.sin(np.pi * x / d) ** 2


def hawk(d=1.1):
    x = tt(d)
    f = 2600 - 1200 * (x / d) ** 0.6
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * (1 - x / d) ** 1.5 * np.minimum(1, x * 40)


def city(d):
    hum = lp(n(d), 180) * 0.8
    for _ in range(4):
        place(hum, lp(n(2.5), 400) * np.sin(np.pi * tt(2.5) / 2.5) * 0.6, rng.uniform(0, d))
    return hum


# ---------------------------------------------------------------- loops
D = L + 1.5


def caceres_day():
    b = river(D) * 0.25 + wind(D, 0.4) * 0.3
    for _ in range(14):
        place(b, bird_song(rng.choice([2600, 3200, 3800, 4400]), rng.integers(3, 7)) * 0.45, rng.uniform(0, D))
    return seamless(b)


def pantanal_day():
    b = insects(D, 5600) * 0.12 + wind(D, 0.3) * 0.15
    for _ in range(9):
        place(b, croak(rng.uniform(110, 180)) * 0.5, rng.uniform(0, D))
    for _ in range(12):
        place(b, bird_song(rng.choice([1800, 2400, 3000]), rng.integers(2, 6)) * 0.5, rng.uniform(0, D))
    for _ in range(3):  # macaw squawks
        place(b, bp(np.sign(np.sin(2 * np.pi * 900 * tt(0.35))) * np.sin(np.pi * tt(0.35) / 0.35), 700, 2500) * 0.4, rng.uniform(0, D))
    return seamless(b)


def chapada_day():
    b = wind(D, 0.9) * 0.6 + lp(n(D), 220) * 0.12  # distant waterfall rumble
    for _ in range(3):
        place(b, hawk() * 0.35, rng.uniform(0, D))
    for _ in range(5):
        place(b, bird_song(3000, rng.integers(2, 4)) * 0.25, rng.uniform(0, D))
    return seamless(b)


def rio_day():
    b = waves(D) * 0.7 + city(D) * 0.18
    for _ in range(6):
        place(b, gull() * 0.35, rng.uniform(0, D))
    return seamless(b)


def night(zone):
    b = crickets(D) * 0.35 + wind(D, 0.3) * 0.12
    if zone == 'pantanal':
        b += insects(D, 3800) * 0.08
        for _ in range(16):
            place(b, croak(rng.uniform(90, 170)) * 0.55, rng.uniform(0, D))
    elif zone == 'rio':
        b = b * 0.6 + waves(D) * 0.6
    elif zone == 'caceres':
        b += river(D) * 0.18
        for _ in range(5):
            place(b, croak(rng.uniform(120, 160)) * 0.3, rng.uniform(0, D))
    return seamless(b)


def step(kind):
    d = 0.12
    x = tt(d)
    e = np.exp(-x * 45)
    if kind == 'sand':
        s = hp(n(d), 1500) * np.exp(-x * 28) * 0.6
    else:
        s = lp(n(d), 900) * e + np.sin(2 * np.pi * 85 * x) * e * 0.8
    return s


if __name__ == '__main__':
    save('amb_caceres_day', caceres_day())
    save('amb_pantanal_day', pantanal_day())
    save('amb_chapada_day', chapada_day())
    save('amb_rio_day', rio_day())
    for z in ['caceres', 'pantanal', 'chapada', 'rio']:
        save('amb_%s_night' % z, night(z), 0.5)
    save('step_ground', step('ground'), 0.7)
    save('step_sand', step('sand'), 0.6)
    print('ambience written to', os.path.abspath(OUT))
