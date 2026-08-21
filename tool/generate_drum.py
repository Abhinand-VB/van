"""Synthesises Van's notification sounds.

The sounds are generated from this script rather than committed as opaque
binaries, for the same reason the launcher icon is a vector: they can be read,
reviewed and tweaked in a diff instead of being a blob nobody dares touch.

A struck drum is three things layered:

  1. A sine whose pitch drops sharply right after the strike. This is what
     makes it read as a membrane rather than a beep - a fixed-frequency tone
     sounds electronic no matter what envelope you put on it.
  2. A short noise transient for the stick contact, a few milliseconds long.
     Without it the hit sounds soft and far away.
  3. An exponential amplitude decay, fast enough not to ring.

Standard library only - no numpy, no ffmpeg. Android plays 16-bit PCM WAV
from res/raw directly, so there is nothing to convert.

Run:  python tool/generate_drum.py
"""

import math
import random
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 44_100
OUT_DIR = Path("android/app/src/main/res/raw")


def strike(
    start_hz: float,
    end_hz: float,
    duration: float,
    pitch_decay: float,
    amp_decay: float,
    click_level: float,
    rng: random.Random,
) -> list[float]:
    """Renders one drum hit as floats in roughly -1.0 to 1.0."""
    samples: list[float] = []
    phase = 0.0
    total = int(SAMPLE_RATE * duration)

    for i in range(total):
        t = i / SAMPLE_RATE

        # Pitch falls from start_hz towards end_hz. Integrating the changing
        # frequency into a running phase is what keeps the sweep smooth; the
        # naive sin(2*pi*f(t)*t) produces audible artefacts.
        freq = end_hz + (start_hz - end_hz) * math.exp(-t / pitch_decay)
        phase += 2.0 * math.pi * freq / SAMPLE_RATE

        body = math.sin(phase)

        # A little second harmonic keeps it from sounding like a pure tone.
        body += 0.18 * math.sin(2.0 * phase)

        amplitude = math.exp(-t / amp_decay)

        # Stick contact: white noise for the first few milliseconds only.
        click = 0.0
        if t < 0.012:
            click = rng.uniform(-1.0, 1.0) * click_level * math.exp(-t / 0.003)

        samples.append(body * amplitude + click)

    return samples


def fade_out(samples: list[float], millis: float = 6.0) -> None:
    """Ramps the tail to zero so the sound does not end on a click."""
    n = min(len(samples), int(SAMPLE_RATE * millis / 1000.0))
    for i in range(n):
        samples[len(samples) - n + i] *= 1.0 - (i / n)


def normalise(samples: list[float], peak: float = 0.89) -> list[float]:
    """Scales to a fixed headroom, leaving room below full scale."""
    loudest = max((abs(s) for s in samples), default=0.0)
    if loudest == 0.0:
        return samples
    gain = peak / loudest
    return [s * gain for s in samples]


def mix(layers: list[tuple[float, list[float]]]) -> list[float]:
    """Sums hits at given start offsets in seconds."""
    length = max(
        int(offset * SAMPLE_RATE) + len(data) for offset, data in layers
    )
    out = [0.0] * length
    for offset, data in layers:
        start = int(offset * SAMPLE_RATE)
        for i, value in enumerate(data):
            out[start + i] += value
    return out


def write_wav(path: Path, samples: list[float]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frames = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32_767)) for s in samples
    )
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(frames)
    kb = path.stat().st_size / 1024
    print(f"  {path}  {len(samples) / SAMPLE_RATE:.2f}s  {kb:.0f} KB")


def main() -> None:
    # Seeded so regenerating produces byte-identical files and the diff stays
    # empty unless the parameters actually changed.
    rng = random.Random(20260821)

    print("Van notification sounds:")

    # Ordinary nudge: one warm, low hit. Present without being startling.
    normal = strike(
        start_hz=196.0,
        end_hz=74.0,
        duration=0.42,
        pitch_decay=0.028,
        amp_decay=0.115,
        click_level=0.30,
        rng=rng,
    )
    fade_out(normal)
    write_wav(OUT_DIR / "nudge_drum.wav", normalise(normal))

    # Urgent nudge: two hits, tighter and brighter. Distinguishable from the
    # ordinary one without looking at the phone, which is the entire point of
    # giving Van its own sound.
    first = strike(
        start_hz=252.0,
        end_hz=96.0,
        duration=0.26,
        pitch_decay=0.020,
        amp_decay=0.070,
        click_level=0.42,
        rng=rng,
    )
    second = strike(
        start_hz=252.0,
        end_hz=96.0,
        duration=0.40,
        pitch_decay=0.020,
        amp_decay=0.100,
        click_level=0.42,
        rng=rng,
    )
    fade_out(first)
    fade_out(second)
    urgent = mix([(0.0, first), (0.155, second)])
    write_wav(OUT_DIR / "nudge_drum_urgent.wav", normalise(urgent))


if __name__ == "__main__":
    main()
