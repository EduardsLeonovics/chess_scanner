"""Builds the app's board sounds from real recordings of wood impacts.

Sources: Kenney "Impact Sounds" (CC0, public domain), the takes used are in
tool/sound_sources/. The raw takes resonate at ~300 Hz, like a big wooden
block. Speeding a take up raises that resonance and shortens the decay, the
way a smaller object (a chess piece) sounds, while keeping the real attack
and texture. Takes are then filtered, trimmed, layered and levelled.

    pip install numpy scipy soundfile
    python app/tool/make_sounds.py

  move     a light wooden tap: short, dry, in the background
  capture  a bright "tack" (piece hits piece), then the landing: punchier
  check    a wooden thud, then a hollow plank clack that rings a bit longer
  castle   two light taps, king then rook
  correct  a quick rising chime (C-E-G), for a right move in a puzzle;
           synthesized, no recording
"""

import wave
from pathlib import Path

import numpy as np
import soundfile as sf
from fractions import Fraction

from scipy.signal import butter, resample_poly, sosfilt

RATE = 44100
HERE = Path(__file__).resolve().parent
SOURCES = HERE / "sound_sources"
OUT = HERE.parent / "assets" / "sounds"


def load(name):
    x, sr = sf.read(SOURCES / f"{name}.ogg")
    assert sr == RATE, (name, sr)
    if x.ndim > 1:
        x = x.mean(axis=1)
    # Start at the attack.
    start = max(0, int(np.argmax(np.abs(x) > np.max(np.abs(x)) * 0.05)) - 20)
    return x[start:]


def faster(x, speed):
    """Plays [x] [speed] times faster: higher pitch, shorter decay."""
    f = Fraction(speed).limit_denominator(20)
    return resample_poly(x, f.denominator, f.numerator)


def highpass(x, hz, order=2):
    return sosfilt(butter(order, hz, "highpass", fs=RATE, output="sos"), x)


def lowpass(x, hz, order=2):
    return sosfilt(butter(order, hz, "lowpass", fs=RATE, output="sos"), x)


def trim(x, ms, fade_ms=25):
    x = x[: int(ms / 1000 * RATE)].copy()
    fade = min(len(x), int(fade_ms / 1000 * RATE))
    x[-fade:] *= np.linspace(1, 0, fade) ** 2
    return x


def place(*layers, ms):
    out = np.zeros(int(ms / 1000 * RATE))
    for sound, at_ms, gain in layers:
        start = int(at_ms / 1000 * RATE)
        end = min(len(out), start + len(sound))
        out[start:end] += gain * sound[: end - start]
    return out


def level(x, peak_db):
    return x / np.max(np.abs(x)) * 10 ** (peak_db / 20)


def tap(name, speed=1.6, cut_hz=250):
    """A wood take sped up to piece size, rumble removed, top softened a touch."""
    return lowpass(highpass(faster(load(name), speed), cut_hz), 9000)


def move():
    return level(trim(tap("impactWood_light_000"), 110), -6)


def capture():
    tack = highpass(faster(load("impactGeneric_light_000"), 1.3), 500)
    land = tap("impactWood_light_004", speed=1.7)
    mix = place((trim(tack, 60, 15), 0, 1.0), (trim(land, 120), 14, 0.9), ms=140)
    return level(mix, -1.5)


def check():
    thud = tap("impactWood_light_002", speed=1.4)
    # The plank take hisses and rings up high; keep only its hollow wooden body.
    clack = lowpass(highpass(faster(load("impactPlank_medium_004"), 1.25), 400), 3800, order=4)
    mix = place((trim(thud, 90), 0, 0.9), (trim(clack, 150, 70), 22, 0.85), ms=180)
    return level(mix, -3)


def castle():
    king = trim(tap("impactWood_light_000"), 100)
    rook = trim(tap("impactWood_light_002"), 100)
    return level(place((king, 0, 1.0), (rook, 95, 0.85), ms=200), -6)


def bell(hz, ms, decay_ms):
    """A soft mallet-on-metal note: a sine with a few quiet overtones (the
    2.76x one is a marimba's), a 3 ms attack and an exponential decay."""
    t = np.arange(int(ms / 1000 * RATE)) / RATE
    tone = (np.sin(2 * np.pi * hz * t)
            + 0.25 * np.sin(2 * np.pi * 2 * hz * t)
            + 0.08 * np.sin(2 * np.pi * 2.76 * hz * t))
    envelope = np.minimum(1, t / 0.003) * np.exp(-t / (decay_ms / 1000))
    return tone * envelope


def correct():
    notes = [(1046.5, 0, 0.8), (1318.5, 70, 0.85), (1568.0, 140, 1.0)]
    mix = place(*[(bell(hz, 520, 160), at, gain) for hz, at, gain in notes], ms=660)
    return level(trim(mix, 660, 120), -5)


def write(name, x):
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())
    print(f"wrote {name}")


def main():
    write("move.wav", move())
    write("capture.wav", capture())
    write("check.wav", check())
    write("castle.wav", castle())
    write("correct.wav", correct())


if __name__ == "__main__":
    main()
