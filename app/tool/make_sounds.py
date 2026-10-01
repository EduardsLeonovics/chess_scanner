"""Synthesizes the app's board sounds into app/assets/sounds/.

Physical model: a short contact pulse (how long the piece and the surface
touch) excites a set of damped wood resonances. A soft, felt-bottomed piece
touches for longer, which rounds off the highs; wood striking wood touches
very briefly, which gives a crisp, bright transient. No noise and no
randomness: the same move always makes the same sound.

    pip install numpy
    python app/tool/make_sounds.py

  move     soft, grounded "tock": a piece set down on a wooden board
  capture  crisp "tack": piece knocks piece, then lands firmly
  check    "thud-clack" with a short hollow wooden ring
  castle   two quick soft tocks, king then rook
"""

import wave
from pathlib import Path

import numpy as np

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "assets" / "sounds"

# Resonances (Hz, relative amplitude, decay time constant in seconds).
BOARD = [  # a solid wooden board under a piece
    (240, 0.22, 0.008),
    (910, 0.85, 0.014),
    (1420, 0.85, 0.010),
    (2180, 0.60, 0.006),
    (3100, 0.30, 0.0035),
]
PIECE = [  # the small, dense wooden piece itself: higher, shorter
    (1650, 0.90, 0.009),
    (2580, 0.70, 0.006),
    (3720, 0.40, 0.0035),
    (5150, 0.18, 0.002),
]
HOLLOW = [  # a hollow wooden box: lower, rings a little longer
    (410, 0.80, 0.040),
    (830, 0.55, 0.026),
    (1240, 0.35, 0.016),
]


def modes(partials, seconds=0.3):
    t = np.arange(int(seconds * RATE)) / RATE
    out = np.zeros_like(t)
    for freq, amp, tau in partials:
        out += amp * np.exp(-t / tau) * np.sin(2 * np.pi * freq * t)
    return out


def strike(partials, contact_ms, gain=1.0, seconds=0.3):
    """Resonances excited by a half-sine contact pulse of [contact_ms]."""
    n = max(2, int(contact_ms / 1000 * RATE))
    pulse = np.sin(np.pi * np.arange(n) / n)
    pulse /= pulse.sum()
    return gain * np.convolve(modes(partials, seconds), pulse)[: int(seconds * RATE)]


def place(*layers, seconds):
    """Mixes (sound, start_seconds) layers into one buffer."""
    out = np.zeros(int(seconds * RATE))
    for sound, at in layers:
        start = int(at * RATE)
        end = min(len(out), start + len(sound))
        out[start:end] += sound[: end - start]
    return out


def finish(x, peak_db):
    x = x / np.max(np.abs(x)) * 10 ** (peak_db / 20)
    # Trim the silent tail, then fade the last 15 ms.
    audible = np.nonzero(np.abs(x) > 10 ** (-60 / 20))[0]
    x = x[: audible[-1] + 1] if len(audible) else x
    fade = min(len(x), int(0.015 * RATE))
    x[-fade:] *= np.linspace(1, 0, fade)
    return x


def write(name, x):
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((x * 32767).astype("<i2").tobytes())
    spectrum = np.abs(np.fft.rfft(x))
    freqs = np.fft.rfftfreq(len(x), 1 / RATE)
    centroid = (spectrum * freqs).sum() / spectrum.sum()
    print(f"{name:12} {len(x) / RATE * 1000:4.0f} ms  brightness (centroid) {centroid:5.0f} Hz")


def move():
    # Felt-bottomed piece: ~0.3 ms contact keeps it soft but not dull.
    return finish(strike(BOARD, 0.3), peak_db=-5)


def capture():
    knock = strike(PIECE, 0.07, gain=1.0)  # wood on wood: very short contact
    land = strike(BOARD, 0.22, gain=0.9)
    return finish(place((knock, 0), (land, 0.009), seconds=0.3), peak_db=-1.5)


def check():
    thud = strike(HOLLOW, 0.6, gain=0.75)
    clack = strike(PIECE, 0.18, gain=0.7) + strike(BOARD, 0.25, gain=0.6)
    return finish(place((thud, 0), (clack, 0.024), seconds=0.4), peak_db=-2)


def castle():
    king = strike(BOARD, 0.3)
    rook = strike([(f * 1.06, a, t) for f, a, t in BOARD], 0.3, gain=0.85)
    return finish(place((king, 0), (rook, 0.085), seconds=0.4), peak_db=-5)


def main():
    write("move.wav", move())
    write("capture.wav", capture())
    write("check.wav", check())
    write("castle.wav", castle())


if __name__ == "__main__":
    main()
