"""Mixes one looping soundscape per building into assets/sounds/buildings/<key>.wav.

Each loop is 20 seconds and joins up seamlessly. It layers:
  - beds made here in code: waves, wind, machine hum, fire crackle, bubbling, crowd murmur, gulls, foghorn, bells
  - one-off sounds from Kenney's CC0 packs (tools/sound_sources): coins, creaks, doors, hammers, chops, pages...
The recipes are in RECIPES below: change a layer's loudness (dB) or how often it happens, then run again.

Needs numpy, scipy and av (ComfyUI's Python has all three):
  D:/ComfyUI/ComfyUI_windows_portable/python_embeded/python.exe tools/make_sounds.py            (every building)
  D:/ComfyUI/ComfyUI_windows_portable/python_embeded/python.exe tools/make_sounds.py bank       (just the bank)
"""
import sys
import wave
import zlib
from pathlib import Path

import av
import numpy as np
from scipy import signal

ROOT = Path(__file__).resolve().parent.parent
SOURCES = Path(__file__).resolve().parent / "sound_sources"
OUT = ROOT / "assets" / "sounds" / "buildings"
RATE = 24000
LENGTH = 20.0
N = int(RATE * LENGTH)


# ---------- Helpers ----------

def db(x):
    return 10 ** (x / 20)


def loop_filter(x, low=None, high=None):
    # Band-pass by zeroing frequencies in the FFT. The FFT treats the sound as a circle, so loops stay seamless.
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1 / RATE)
    gain = np.ones_like(freqs)
    if low:
        gain *= 1 / np.sqrt(1 + (low / np.maximum(freqs, 1)) ** 4)
    if high:
        gain *= 1 / np.sqrt(1 + (freqs / high) ** 4)
    return np.fft.irfft(spec * gain, len(x))


def slow_wave(rng, period_min, period_max):
    # A smooth random wobble between 0 and 1 that loops: a few sine waves with whole numbers of cycles per loop
    t = np.arange(N) / RATE
    out = np.zeros(N)
    for _ in range(3):
        cycles = max(1, round(LENGTH / rng.uniform(period_min, period_max)))
        out += np.sin(2 * np.pi * cycles * t / LENGTH + rng.uniform(0, 2 * np.pi))
    return (out - out.min()) / (out.max() - out.min() + 1e-9)


def normalise(x, rms_db=-20.0):
    rms = np.sqrt(np.mean(x ** 2)) + 1e-9
    return x * db(rms_db) / rms


def place(buf, clip, at):
    # Add a clip at a time (seconds), wrapping past the end back to the start so the loop stays seamless
    start = int(at * RATE) % N
    end = start + len(clip)
    if end <= N:
        buf[start:end] += clip
    else:
        cut = N - start
        buf[start:] += clip[:cut]
        buf[: end - N] += clip[cut:]


_cache = {}


def load(name):
    # A Kenney one-off as mono floats at RATE
    if name not in _cache:
        with av.open(str(SOURCES / (name + ".ogg"))) as f:
            res = av.AudioResampler(format="flt", layout="mono", rate=RATE)
            parts = []
            for frame in f.decode(audio=0):
                for r in res.resample(frame):
                    parts.append(r.to_ndarray().reshape(-1))
            for r in res.resample(None):
                parts.append(r.to_ndarray().reshape(-1))
        clip = np.concatenate(parts).astype(np.float64)
        _cache[name] = clip / (np.abs(clip).max() + 1e-9)
    return _cache[name]


def scatter(rng, names, per_minute, level_db, jitter_db=4.0, pitch=0.08, burst=1, burst_gap=0.0):
    # One-off sounds at random times: `per_minute` events, each a random pick from `names`,
    # with a little random loudness and pitch so repeats don't sound copied. A burst plays several in a row.
    buf = np.zeros(N)
    count = max(1, round(per_minute * LENGTH / 60))
    for _ in range(count):
        at = rng.uniform(0, LENGTH)
        for k in range(burst):
            clip = load(rng.choice(names))
            speed = 1 + rng.uniform(-pitch, pitch)
            clip = signal.resample(clip, max(8, int(len(clip) / speed)))
            place(buf, clip * db(level_db + rng.uniform(-jitter_db, 0)), at + k * burst_gap * rng.uniform(0.8, 1.2))
    return buf


def steady(rng, names, every, level_db, jitter=0.0):
    # Evenly spaced one-offs (a clock tick, a printing press, a pump)
    buf = np.zeros(N)
    step = LENGTH / max(1, round(LENGTH / every))
    t = rng.uniform(0, step)
    while t < LENGTH:
        place(buf, load(rng.choice(names)) * db(level_db + rng.uniform(-1.5, 0)), t + rng.uniform(-jitter, jitter))
        t += step
    return buf


# ---------- Beds made in code ----------

def waves(rng, level_db, rough=1.0):
    # Brown-ish noise, low-passed, swelling every few seconds, with a hiss on each crest
    noise = rng.standard_normal(N)
    body = loop_filter(noise, 60, 700 * rough)
    hiss = loop_filter(rng.standard_normal(N), 1500, 5000)
    swell = slow_wave(rng, 4, 9) ** 1.5
    out = normalise(body) * (0.35 + 0.65 * swell) + normalise(hiss) * 0.25 * swell ** 3 * rough
    return normalise(out) * db(level_db)


def lapping(rng, level_db):
    # Small water slaps against wood: short low bursts
    buf = np.zeros(N)
    for _ in range(int(LENGTH * 1.3)):
        n = int(RATE * rng.uniform(0.15, 0.4))
        clip = signal.lfilter(*signal.butter(2, [150, 900], "band", fs=RATE), rng.standard_normal(n))
        clip *= np.hanning(n) ** 2
        place(buf, normalise(clip, -20) * db(rng.uniform(-8, 0)), rng.uniform(0, LENGTH))
    return normalise(buf) * db(level_db)


def wind(rng, level_db, strength=1.0):
    noise = rng.standard_normal(N)
    low = loop_filter(noise, 120, 500)
    high = loop_filter(noise, 500, 1800 * strength)
    gust = slow_wave(rng, 3, 8)
    out = normalise(low) * (0.4 + 0.6 * gust) + normalise(high) * 0.5 * gust ** 2 * strength
    return normalise(out) * db(level_db)


def hum(rng, level_db, base=55.0, grit=0.3):
    # Machinery: a low tone with harmonics, a slight wobble and some grinding noise
    t = np.arange(N) / RATE
    # Whole number of cycles per loop, so it joins cleanly
    f = round(base * LENGTH) / LENGTH
    wob = 1 + 0.15 * slow_wave(rng, 1, 3)
    tone = sum(np.sin(2 * np.pi * f * h * t) / h for h in (1, 2, 3, 4, 6))
    grind = loop_filter(rng.standard_normal(N), 200, 2000)
    return normalise(normalise(tone) * wob + normalise(grind) * grit) * db(level_db)


def crackle(rng, level_db, per_second=12):
    # Fire: random tiny pops over a soft roar
    buf = loop_filter(rng.standard_normal(N), 100, 600) * 0.3
    for _ in range(int(LENGTH * per_second)):
        n = int(RATE * rng.uniform(0.002, 0.012))
        place(buf, rng.standard_normal(n) * np.exp(-np.linspace(0, 6, n)) * rng.uniform(0.5, 3), rng.uniform(0, LENGTH))
    return normalise(loop_filter(buf, 80, 6000)) * db(level_db)


def bubbles(rng, level_db, per_second=6, low=300, high=900):
    # Bubbling: short sine chirps that rise in pitch
    buf = np.zeros(N)
    for _ in range(int(LENGTH * per_second)):
        n = int(RATE * rng.uniform(0.03, 0.09))
        tt = np.arange(n) / RATE
        f0 = rng.uniform(low, high)
        f = f0 * (1 + 2.5 * tt / tt[-1])
        clip = np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.exp(-np.linspace(0, 5, n))
        place(buf, clip * rng.uniform(0.3, 1), rng.uniform(0, LENGTH))
    return normalise(buf) * db(level_db)


def murmur(rng, level_db, voices=8, rowdy=0.0):
    # Crowd talk: noise shaped by vowel-like formants, switched on and off in syllables
    t = np.arange(N) / RATE
    vowels = [(730, 1090), (270, 2290), (300, 870), (530, 1840), (640, 1190)]
    out = np.zeros(N)
    for _ in range(voices):
        voice = np.zeros(N)
        src = rng.standard_normal(N)
        for f1, f2 in vowels:
            shift = rng.uniform(0.8, 1.25)
            part = loop_filter(src, f1 * shift * 0.8, f1 * shift * 1.2) + 0.5 * loop_filter(src, f2 * shift * 0.85, f2 * shift * 1.15)
            # Syllable rate rounded to whole cycles per loop, so the loop joins mid-sentence without a click
            rate = round(rng.uniform(3, 6) * LENGTH) / LENGTH
            gate = (np.sin(2 * np.pi * rate * t + rng.uniform(0, 6.28)) > rng.uniform(-0.2, 0.5)).astype(float)
            voice += part * gate
        talk = slow_wave(rng, 2, 6)
        out += normalise(voice) * (talk > 0.35) * rng.uniform(0.4, 1)
    out = loop_filter(out, 150, 3000)
    if rowdy:
        out += normalise(loop_filter(rng.standard_normal(N), 300, 1500)) * rowdy * slow_wave(rng, 1, 3) ** 4
    return normalise(out) * db(level_db)


def gull(rng):
    # One "kee-ow": a bright harmonic call that slides down, with a little warble
    n = int(RATE * rng.uniform(0.35, 0.6))
    tt = np.linspace(0, 1, n)
    f = rng.uniform(1300, 1700) * (1 - 0.35 * tt ** 1.5) * (1 + 0.02 * np.sin(2 * np.pi * 28 * tt))
    ph = 2 * np.pi * np.cumsum(f) / RATE
    clip = np.sin(ph) + 0.6 * np.sin(2 * ph) + 0.3 * np.sin(3 * ph) + 0.15 * np.sin(4 * ph)
    clip *= np.sin(np.pi * tt) ** 0.6 * np.exp(-1.5 * tt)
    return clip / np.abs(clip).max()


def gulls(rng, level_db, per_minute=8):
    buf = np.zeros(N)
    for _ in range(max(1, round(per_minute * LENGTH / 60))):
        at = rng.uniform(0, LENGTH)
        for k in range(rng.integers(1, 4)):
            place(buf, gull(rng) * db(rng.uniform(-6, 0)), at + k * rng.uniform(0.4, 0.7))
    return buf * db(level_db)


def bell(rng, freq, level_db, length=3.0):
    # A struck bell: inharmonic partials that ring and fade
    n = int(RATE * length)
    t = np.arange(n) / RATE
    clip = sum(a * np.sin(2 * np.pi * freq * r * t) * np.exp(-t * d) for r, a, d in
               [(0.5, 0.6, 0.8), (1, 1, 1.2), (1.19, 0.5, 1.8), (1.56, 0.4, 2.2), (2, 0.35, 2.8), (2.51, 0.25, 3.5), (3, 0.2, 4)])
    return clip / np.abs(clip).max() * db(level_db)


def bells(rng, freq, level_db, per_minute=3, strikes=1):
    buf = np.zeros(N)
    for _ in range(max(1, round(per_minute * LENGTH / 60))):
        at = rng.uniform(0, LENGTH)
        for k in range(strikes):
            place(buf, bell(rng, freq, level_db + rng.uniform(-3, 0)), at + k * 1.1)
    return buf


def foghorn(rng, level_db, every=10.0):
    buf = np.zeros(N)
    n = int(RATE * 2.6)
    tt = np.arange(n) / RATE
    saw = signal.sawtooth(2 * np.pi * 98 * tt) + 0.5 * signal.sawtooth(2 * np.pi * 147 * tt)
    clip = signal.lfilter(*signal.butter(2, 500, fs=RATE), saw) * np.minimum(1, tt / 0.4) * np.minimum(1, (tt[-1] - tt) / 0.8)
    clip /= np.abs(clip).max()
    t = rng.uniform(0, every)
    while t < LENGTH:
        place(buf, clip * db(level_db), t)
        t += every
    return buf


def boom(rng, level_db, per_minute=2):
    # A distant cannon: a thump with a rumbling tail
    buf = np.zeros(N)
    for _ in range(max(1, round(per_minute * LENGTH / 60))):
        n = int(RATE * 1.8)
        tt = np.arange(n) / RATE
        clip = np.sin(2 * np.pi * 50 * tt) * np.exp(-tt * 5) + signal.lfilter(*signal.butter(2, 300, fs=RATE), rng.standard_normal(n)) * np.exp(-tt * 2.5) * 0.8
        place(buf, clip / np.abs(clip).max() * db(level_db), rng.uniform(0, LENGTH))
    return buf


def steam(rng, level_db, per_minute=5):
    # A hiss of steam that fades in and out
    buf = np.zeros(N)
    for _ in range(max(1, round(per_minute * LENGTH / 60))):
        n = int(RATE * rng.uniform(0.8, 1.6))
        clip = signal.lfilter(*signal.butter(2, [2000, 7000], "band", fs=RATE), rng.standard_normal(n)) * np.sin(np.linspace(0, np.pi, n)) ** 0.5
        place(buf, normalise(clip, -20) * db(level_db + rng.uniform(-3, 0)), rng.uniform(0, LENGTH))
    return buf


def sawing(rng, level_db, per_minute=3):
    # Hand saw: rasping noise pushed back and forth
    buf = np.zeros(N)
    for _ in range(max(1, round(per_minute * LENGTH / 60))):
        strokes = rng.integers(4, 9)
        n = int(RATE * strokes * 0.32)
        tt = np.arange(n) / RATE
        rasp = signal.lfilter(*signal.butter(2, [900, 4500], "band", fs=RATE), rng.standard_normal(n))
        stroke = np.abs(np.sin(np.pi * tt / 0.32)) ** 0.7
        place(buf, normalise(rasp * stroke, -20) * db(level_db), rng.uniform(0, LENGTH))
    return buf


def whir(rng, level_db):
    # A spinning wind gauge: a soft whirr whose speed follows the wind
    t = np.arange(N) / RATE
    speed = 8 + 10 * slow_wave(rng, 3, 7)
    # Stretch the speed slightly so the gauge makes a whole number of turns per loop
    turns = np.sum(speed) / RATE
    speed *= round(turns) / turns
    clicks = (np.sin(2 * np.pi * np.cumsum(speed) / RATE) > 0.97).astype(float)
    whirr = loop_filter(rng.standard_normal(N), 800, 2500) * (0.3 + 0.7 * slow_wave(rng, 3, 7))
    return normalise(loop_filter(clicks, 1000, 6000) * 0.6 + normalise(whirr) * 0.4) * db(level_db)


def room(rng, level_db):
    # Indoors: a soft low hush with townsfolk faintly through the walls, so quiet rooms don't drop to silence
    hush = loop_filter(rng.standard_normal(N), 60, 400) * (0.7 + 0.3 * slow_wave(rng, 4, 9))
    town = loop_filter(murmur(rng, -20, 5), 150, 900)
    return normalise(normalise(hush) + normalise(town) * 0.5) * db(level_db)


# ---------- One-off sound groups (Kenney CC0) ----------

def k(prefix, count=5):
    return [prefix + "_%03d" % i for i in range(count)]


COINS = ["handleCoins", "handleCoins2"]
CREAK = ["creak1", "creak2", "creak3"]
DOOR = ["doorOpen_1", "doorOpen_2", "doorClose_1", "doorClose_2", "doorClose_3", "doorClose_4"]
PAGES = ["bookFlip1", "bookFlip2", "bookFlip3", "bookPlace1", "bookPlace2"]
STEPS_WOOD = k("footstep_wood")
STEPS_STONE = k("footstep_concrete")
WOOD = k("impactWood_light") + k("impactWood_medium")
PLANK = k("impactPlank_medium")
METAL_LIGHT = k("impactMetal_light")
METAL = k("impactMetal_medium") + k("impactMetal_heavy")
GLASS = k("impactGlass_light")
TIN = k("impactTin_medium")
PLATE = k("impactPlate_light")
SOFT = k("impactSoft_medium")
MINING = k("impactMining")
CHOP = ["chop", "knifeSlice", "knifeSlice2"]
CLICK = ["metalClick", "metalLatch"]
POTS = ["metalPot1", "metalPot2", "metalPot3"]
CLOTH = ["cloth1", "cloth2", "cloth3", "cloth4"]
BELL_HEAVY = k("impactBell_heavy")


# ---------- Recipes: one per building ----------
# Each recipe is a function of a random generator that returns a list of layers (all length N).
RECIPES = {
    "deep": lambda r: [waves(r, -22), gulls(r, -20, 6), scatter(r, CREAK, 6, -18), scatter(r, WOOD, 5, -20),
                       hum(r, -32, 48, 0.2)],
    "pearl": lambda r: [waves(r, -24), lapping(r, -26), bubbles(r, -28, 4), gulls(r, -24, 4),
                        scatter(r, SOFT, 4, -22)],
    "crab": lambda r: [waves(r, -24), scatter(r, PLATE, 10, -20, burst=3, burst_gap=0.12), scatter(r, WOOD, 6, -18),
                       gulls(r, -22, 6)],
    "cray": lambda r: [waves(r, -24), scatter(r, WOOD, 12, -18, burst=2, burst_gap=0.25), scatter(r, CREAK, 5, -20),
                       lapping(r, -28)],
    "salvage": lambda r: [waves(r, -22, 1.2), scatter(r, METAL, 8, -16), scatter(r, METAL_LIGHT, 6, -20, burst=6, burst_gap=0.07),
                          scatter(r, CREAK, 5, -18)],
    "treasure": lambda r: [wind(r, -30, 0.6), scatter(r, MINING, 10, -16), scatter(r, COINS, 4, -14), scatter(r, CREAK, 3, -20)],
    "whaling": lambda r: [waves(r, -20, 1.4), wind(r, -28), scatter(r, CREAK, 6, -18), bells(r, 330, -24, 2),
                          scatter(r, WOOD, 4, -20)],
    "smuggle": lambda r: [lapping(r, -24), murmur(r, -30, 3), scatter(r, SOFT, 6, -18), scatter(r, DOOR, 3, -20),
                          scatter(r, CREAK, 4, -22)],
    "hiding": lambda r: [lapping(r, -24), bubbles(r, -30, 2, 900, 2200), wind(r, -34, 0.4), scatter(r, CREAK, 4, -22)],
    "piracy": lambda r: [waves(r, -22), murmur(r, -26, 10, rowdy=0.6), boom(r, -16, 2), bells(r, 440, -26, 2, 2)],
    "oil": lambda r: [hum(r, -20, 42, 0.5), steady(r, METAL, 1.6, -18, 0.05), steam(r, -24, 4), waves(r, -26), wind(r, -30)],
    "lighthouse": lambda r: [wind(r, -20, 1.3), waves(r, -22, 1.2), foghorn(r, -16, 10.0), gulls(r, -24, 5)],
    "meteo": lambda r: [wind(r, -22, 1.1), whir(r, -24), scatter(r, CLICK, 6, -22), bells(r, 1100, -30, 2)],
    "bank": lambda r: [room(r, -30), scatter(r, COINS, 10, -14), steady(r, CLICK, 1.0, -28), scatter(r, PAGES, 5, -20), scatter(r, DOOR, 2, -22)],
    "bait_works": lambda r: [room(r, -30), scatter(r, CHOP, 16, -16), bubbles(r, -26, 8, 150, 400), gulls(r, -22, 6), scatter(r, POTS, 3, -22)],
    "research_lab": lambda r: [bubbles(r, -22, 10, 300, 1200), scatter(r, GLASS, 8, -18), hum(r, -32, 120, 0.1),
                               scatter(r, CLICK, 4, -22)],
    "exchange": lambda r: [murmur(r, -20, 14), scatter(r, COINS, 8, -16), bells(r, 660, -26, 2), scatter(r, WOOD, 4, -22)],
    "shipyard": lambda r: [scatter(r, WOOD + PLANK, 14, -14, burst=4, burst_gap=0.45), sawing(r, -22, 3), waves(r, -26),
                           scatter(r, CREAK, 3, -22)],
    "diving_school": lambda r: [waves(r, -24), lapping(r, -22), bubbles(r, -26, 6), scatter(r, STEPS_WOOD, 10, -20, burst=4, burst_gap=0.35),
                                bells(r, 880, -28, 1)],
    "law_office": lambda r: [room(r, -30), steady(r, CLICK, 1.0, -30), scatter(r, PAGES, 10, -16), scatter(r, ["bookClose", "bookOpen"], 3, -18),
                             scatter(r, CLOTH, 3, -24)],
    "supply_depot": lambda r: [scatter(r, SOFT + WOOD, 12, -16), scatter(r, STEPS_WOOD, 8, -20, burst=4, burst_gap=0.4),
                               scatter(r, CREAK, 3, -22), waves(r, -30)],
    "refinery": lambda r: [hum(r, -18, 36, 0.7), steam(r, -20, 8), scatter(r, METAL, 8, -18), crackle(r, -28, 15)],
    "weather_station": lambda r: [wind(r, -20, 1.2), whir(r, -22), bells(r, 1300, -30, 1)],
    "harbour_office": lambda r: [waves(r, -26), bells(r, 520, -24, 2, 2), scatter(r, PAGES, 6, -20), scatter(r, STEPS_STONE, 6, -22, burst=3, burst_gap=0.4)],
    "gazette_office": lambda r: [room(r, -30), steady(r, PLATE, 0.6, -20, 0.02), steady(r, CLICK, 1.2, -24, 0.02), scatter(r, PAGES, 8, -18)],
    "counting_house": lambda r: [room(r, -30), scatter(r, COINS, 10, -16), scatter(r, CLICK, 14, -22, burst=3, burst_gap=0.15),
                                 steady(r, CLICK, 1.0, -30), scatter(r, PAGES, 4, -22)],
    "customs_house": lambda r: [waves(r, -26), murmur(r, -28, 4), scatter(r, CLICK, 4, -20), scatter(r, STEPS_STONE, 8, -20, burst=4, burst_gap=0.4),
                                scatter(r, DOOR, 2, -22)],
    "watch_house": lambda r: [wind(r, -22, 1.0), scatter(r, BELL_HEAVY, 1, -22), scatter(r, STEPS_STONE, 4, -24, burst=4, burst_gap=0.45)],
    "town_hall": lambda r: [murmur(r, -22, 12), bells(r, 392, -20, 2, 3), scatter(r, DOOR, 3, -22), scatter(r, STEPS_STONE, 6, -24, burst=4, burst_gap=0.4)],
    "house": lambda r: [crackle(r, -22, 10), steady(r, CLICK, 1.0, -32), waves(r, -30), scatter(r, POTS, 2, -24)],
}


def mix(key):
    # Seeded from the building's name, so the same building always mixes the same way
    rng = np.random.default_rng(zlib.crc32(key.encode()))
    layers = RECIPES[key](rng)
    out = np.sum(layers, axis=0)
    # Even loudness across buildings, then a soft limiter so peaks never clip
    out = normalise(out, -20)
    out = np.tanh(out * 1.4) / 1.4
    return out


def write(path, x):
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    keys = sys.argv[1:] or list(RECIPES)
    for key in keys:
        write(OUT / (key + ".wav"), mix(key))
        print("mixed", key)


if __name__ == "__main__":
    main()
