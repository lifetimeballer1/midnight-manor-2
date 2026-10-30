"""Synthesises Midnight Manor's ambience and event sounds into audio/ambience/ (Ogg Vorbis).

Everything here is generated from code (no samples), so the output is the project's own work.
Run: python3 scripts/audio/make_soundscape.py   (needs numpy and ffmpeg with libvorbis)
The seed is fixed, so a re-run writes the same sounds.
"""
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "audio", "ambience")
rng = np.random.default_rng(1793)


def t_of(seconds):
    return np.arange(int(seconds * RATE)) / RATE


def env(n, attack, release):
    e = np.ones(n)
    a = max(1, int(attack * RATE))
    r = max(1, int(release * RATE))
    e[:a] = np.linspace(0.0, 1.0, a)
    e[-r:] *= np.linspace(1.0, 0.0, r)
    return e


def lowpass(x, cutoff):
    # One-pole low-pass, run twice for a gentler slope.
    a = np.exp(-2.0 * np.pi * cutoff / RATE)
    for _ in range(2):
        y = np.empty_like(x)
        acc = 0.0
        for i, v in enumerate(x):
            acc = (1.0 - a) * v + a * acc
            y[i] = acc
        x = y
    return x


def place(buf, clip, at):
    start = int(at * RATE)
    end = min(len(buf), start + len(clip))
    if end > start:
        buf[start:end] += clip[: end - start]


def loop_seam(x, fade=0.6):
    # Crossfade the tail into the head so the loop has no click.
    n = int(fade * RATE)
    head = x[:n].copy()
    tail = x[-n:]
    ramp = np.linspace(0.0, 1.0, n)
    x[:n] = head * ramp + tail * (1.0 - ramp)
    return x[:-n]


def write(name, x, peak=0.7):
    x = x / max(1e-9, np.max(np.abs(x))) * peak
    pcm = (np.clip(x, -1.0, 1.0) * 32767).astype(np.int16)
    os.makedirs(OUT, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = os.path.join(tmp, name + ".wav")
        with wave.open(wav_path, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(pcm.tobytes())
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path, "-c:a", "libvorbis", "-q:a", "3",
                        os.path.join(OUT, name + ".ogg")], check=True)
    print("wrote", name, "%.1fs" % (len(x) / RATE))


def chirp(f0, f1, dur, vol=1.0):
    t = t_of(dur)
    f = np.linspace(f0, f1, len(t)) + 120.0 * np.sin(2 * np.pi * 38.0 * t)
    phase = 2 * np.pi * np.cumsum(f) / RATE
    return np.sin(phase) * env(len(t), 0.008, dur * 0.6) * vol


def day_birds(seconds=24.0):
    buf = np.zeros(int(seconds * RATE))
    # A soft leafy hush under the birds.
    buf += lowpass(rng.normal(0.0, 1.0, len(buf)), 900.0) * 0.05
    at = 0.4
    while at < seconds - 1.5:
        kind = rng.integers(0, 3)
        base = rng.uniform(2600.0, 4200.0)
        vol = rng.uniform(0.25, 0.6)
        if kind == 0:  # a run of falling notes
            for k in range(rng.integers(3, 7)):
                place(buf, chirp(base * 1.15, base * 0.9, 0.07, vol), at + k * 0.11)
        elif kind == 1:  # two-note call
            place(buf, chirp(base, base * 1.25, 0.12, vol), at)
            place(buf, chirp(base * 1.2, base * 0.95, 0.16, vol), at + 0.2)
        else:  # a quick trill
            for k in range(rng.integers(6, 12)):
                place(buf, chirp(base, base * 1.06, 0.035, vol * 0.7), at + k * 0.045)
        at += rng.uniform(0.9, 2.6)
    return loop_seam(buf)


def night_crickets(seconds=24.0):
    buf = np.zeros(int(seconds * RATE))
    buf += lowpass(rng.normal(0.0, 1.0, len(buf)), 300.0) * 0.06
    t = t_of(seconds)
    for carrier, rate, gap, vol in [(4400.0, 0.52, 0.0, 0.5), (5100.0, 0.71, 0.21, 0.35), (3900.0, 0.93, 0.4, 0.22)]:
        tone = np.sin(2 * np.pi * carrier * t)
        gate = np.zeros(len(t))
        at = gap
        while at < seconds:
            for k in range(3):  # three pulses a chirp
                start = int((at + k * 0.032) * RATE)
                n = int(0.022 * RATE)
                if start + n < len(gate):
                    gate[start:start + n] = np.hanning(n)
            at += rate * rng.uniform(0.92, 1.08)
        buf += tone * gate * vol
    return loop_seam(buf)


def owl():
    out = np.zeros(int(1.8 * RATE))
    for at, dur, f in [(0.0, 0.42, 410.0), (0.62, 0.7, 395.0)]:
        t = t_of(dur)
        f_t = f * (1.0 + 0.012 * np.sin(2 * np.pi * 5.0 * t)) * np.linspace(1.02, 0.97, len(t))
        voice = np.sin(2 * np.pi * np.cumsum(f_t) / RATE) + 0.25 * np.sin(4 * np.pi * np.cumsum(f_t) / RATE)
        breath = lowpass(rng.normal(0.0, 1.0, len(t)), 1200.0) * 0.15
        place(out, (voice + breath) * env(len(t), 0.08, dur * 0.5), at)
    return out


def water(seconds=10.0):
    buf = lowpass(rng.normal(0.0, 1.0, int(seconds * RATE)), 650.0) * 0.5
    at = 0.1
    while at < seconds - 0.2:
        f = rng.uniform(280.0, 900.0)
        dur = rng.uniform(0.03, 0.08)
        t = t_of(dur)
        blip = np.sin(2 * np.pi * np.cumsum(np.linspace(f, f * 1.6, len(t))) / RATE) * env(len(t), 0.004, dur * 0.7)
        place(buf, blip * rng.uniform(0.15, 0.4), at)
        at += rng.uniform(0.08, 0.4)
    return loop_seam(buf, 0.5)


def brass(f, dur, vol=1.0):
    t = t_of(dur)
    tone = np.zeros(len(t))
    for h in range(1, 9):
        tone += np.sin(2 * np.pi * f * h * t * (1.0 + 0.002 * np.sin(2 * np.pi * 5.5 * t))) / h ** 1.1
    # Brighten on the attack, mellow as the note holds.
    bright = lowpass(tone, 2400.0)
    mellow = lowpass(tone, 900.0)
    blend = np.clip(np.linspace(0.0, 1.0, len(t)) * 3.0, 0.0, 1.0)
    return (bright * (1.0 - blend) + mellow * blend) * env(len(t), 0.03, min(0.25, dur * 0.5)) * vol


def fanfare():
    out = np.zeros(int(1.6 * RATE))
    for at, f, dur in [(0.0, 392.0, 0.16), (0.17, 523.25, 0.16), (0.34, 659.25, 0.16), (0.52, 783.99, 0.9)]:
        place(out, brass(f, dur), at)
        place(out, brass(f / 2.0, dur, 0.4), at)
    return out


def drum(f0=86.0, dur=0.55, vol=1.0):
    t = t_of(dur)
    f = f0 * (0.55 + 0.45 * np.exp(-t * 18.0))
    body = np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.exp(-t * 7.0)
    skin = lowpass(rng.normal(0.0, 1.0, len(t)), 1800.0) * np.exp(-t * 40.0) * 0.6
    return (body + skin) * vol


def war_drums():
    beat = 60.0 / 92.0
    bars = 4
    out = np.zeros(int(bars * 4 * beat * RATE))
    for bar in range(bars):
        base = bar * 4 * beat
        place(out, drum(80.0, 0.6, 1.0), base)
        place(out, drum(80.0, 0.6, 0.8), base + 1.5 * beat)
        place(out, drum(118.0, 0.35, 0.55), base + 2.0 * beat)
        place(out, drum(80.0, 0.6, 0.9), base + 3.0 * beat)
        if bar % 2 == 1:
            place(out, drum(118.0, 0.3, 0.45), base + 3.5 * beat)
    return out


def main():
    write("day", day_birds(), 0.55)
    write("night", night_crickets(), 0.45)
    write("owl", owl(), 0.6)
    write("water", water(), 0.5)
    write("fanfare", fanfare(), 0.7)
    write("war_drums", war_drums(), 0.8)


if __name__ == "__main__":
    sys.exit(main())
