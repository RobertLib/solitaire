#!/usr/bin/env python3
"""Writes the music bed for the App Preview.

    Tools/gen_preview_music.py <out.wav> [seconds]

Solitaire ships with no audio: the sound effects are synthesised at launch, so
there is no track in the bundle to put under the trailer. App Store Connect
nevertheless *requires* stereo AAC at 256 kbps on an App Preview, and a silent
track does not satisfy it — AAC compresses digital silence to about 2 kbps, two
orders of magnitude under the rate asked for, and Connect reports a file with no
usable audio as an unsupported audio configuration. So the bed is synthesised
here, in the same spirit as the game's own sounds, and looped under the cut by
Tools/appstore_conform.swift.

Stdlib only (`wave`, `math`, `random`) so it runs on a stock macOS Python.

What it plays: a slow I-vi-IV-V in C at 66 BPM, as plucked nylon-ish strings
over a soft pad, with no percussion at all. Solitaire is a game people play to
wind down, and a beat under the trailer would argue with that — where the poker
trailer wanted a card room, this one wants a quiet afternoon. Mixed quiet and
dull on purpose: it sits under the deal and the cascade and must not compete
with them.
"""

import math
import random
import struct
import sys
import wave

RATE = 48_000
CHANNELS = 2
BPM = 66.0
BEAT = 60.0 / BPM
BAR = 4 * BEAT

# I-vi-IV-V in C, one chord per bar. Semitones from A0 (27.5 Hz), so the root
# sits where a bass actually plays.
A0 = 27.5
PROGRESSION = [
    (27, [39, 43, 46, 51]),  # C     C  E  G  C
    (24, [36, 43, 48, 51]),  # Am    A  E  A  C
    (32, [39, 44, 48, 51]),  # F     C  F  A  C
    (34, [38, 43, 46, 50]),  # G     B  E  G  B
]


def hz(semitone: float) -> float:
    return A0 * 2 ** (semitone / 12.0)


def pluck(t: float, freq: float) -> float:
    """One plucked note: a bright attack over a long, soft decay.

    The upper partials die away several times faster than the fundamental,
    which is most of what makes a string sound plucked rather than bowed.
    """
    if t < 0:
        return 0.0
    attack = min(1.0, t / 0.008)
    body = math.exp(-t * 0.9)
    edge = math.exp(-t * 3.6)
    w = 2 * math.pi * freq * t
    return attack * (
        body * math.sin(w)
        + 0.28 * edge * math.sin(2 * w)
        + 0.09 * math.exp(-t * 7.0) * math.sin(3 * w)
    )


def pad(t: float, freq: float, length: float) -> float:
    """A breathing chord underneath: two detuned sines that swell and fall."""
    if t < 0 or t > length:
        return 0.0
    env = math.sin(math.pi * t / length) ** 1.5
    w = 2 * math.pi * freq * t
    return env * (math.sin(w) + 0.5 * math.sin(w * 1.0035 + 0.6))


def bass(t: float, freq: float) -> float:
    """Root note: a sine with a touch of second harmonic and a soft attack."""
    if t < 0:
        return 0.0
    attack = min(1.0, t / 0.03)
    env = math.exp(-t * 0.95)
    w = 2 * math.pi * freq * t
    return attack * env * (math.sin(w) + 0.18 * math.sin(2 * w))


def render(seconds: float, seed: int = 20260830):
    """Returns interleaved float samples for `seconds` of music."""
    jitterer = random.Random(seed)
    total = int(seconds * RATE)
    left = [0.0] * total
    right = [0.0] * total

    def add(start: float, dur: float, gen, gain: float, pan: float):
        """Mixes one voice in. `pan` is -1 hard left, +1 hard right."""
        i0 = max(0, int(start * RATE))
        i1 = min(total, int((start + dur) * RATE))
        gl = gain * math.sqrt((1.0 - pan) / 2.0)
        gr = gain * math.sqrt((1.0 + pan) / 2.0)
        for i in range(i0, i1):
            value = gen((i - start * RATE) / RATE)
            left[i] += value * gl
            right[i] += value * gr

    bar = 0
    while bar * BAR < seconds:
        root, voicing = PROGRESSION[bar % len(PROGRESSION)]
        t0 = bar * BAR

        # Root on 1 only. A walking bass would pull attention to itself, and
        # there is nothing here for it to walk towards.
        add(t0, BAR, lambda t, f=hz(root): bass(t, f), 0.26, 0.0)

        # The pad: the same voicing an octave down, swelling across the bar.
        for semitone in voicing:
            add(t0, BAR, lambda t, f=hz(semitone - 12): pad(t, f, BAR), 0.045, 0.0)

        # The chord, arpeggiated across the bar rather than struck, spread over
        # the stereo field. Each note is a little late and a little uneven, so
        # the loop point does not stand out as a mechanical repeat.
        for index, semitone in enumerate(voicing):
            pan = -0.55 + index * (1.1 / max(1, len(voicing) - 1))
            at = t0 + index * BEAT * 0.75 + jitterer.uniform(-0.012, 0.012)
            level = 0.15 * (1.0 + jitterer.uniform(-0.12, 0.12))
            add(at, BAR, lambda t, f=hz(semitone): pluck(t, f), level, pan)
            # One note answering high up on the second half of the bar keeps
            # the bar from sagging without adding a beat.
            if index == len(voicing) - 1:
                add(t0 + 2.5 * BEAT, 1.5 * BEAT,
                    lambda t, f=hz(semitone + 12): pluck(t, f), 0.07, -pan)

        bar += 1

    # Soft-knee limiter, then a fade at both ends so the loop join is inaudible.
    peak = max(1e-6, max(max(abs(v) for v in left), max(abs(v) for v in right)))
    scale = 0.70 / peak
    fade = int(0.4 * RATE)
    out = []
    for i in range(total):
        env = 1.0
        if i < fade:
            env = i / fade
        elif i > total - fade:
            env = max(0.0, (total - i) / fade)
        out.append(math.tanh(left[i] * scale) * env)
        out.append(math.tanh(right[i] * scale) * env)
    return out


def main() -> int:
    if not 2 <= len(sys.argv) <= 3:
        print(__doc__.strip().splitlines()[2].strip(), file=sys.stderr)
        return 2
    path = sys.argv[1]
    # Four bars is one full turnaround; conform loops it to the cut's length, so
    # the default only has to be long enough not to loop audibly often.
    seconds = float(sys.argv[2]) if len(sys.argv) > 2 else 4 * BAR * 2

    samples = render(seconds)
    with wave.open(path, "wb") as f:
        f.setnchannels(CHANNELS)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(b"".join(
            struct.pack("<h", max(-32768, min(32767, int(v * 32767)))) for v in samples))
    print(f"→ {path}  {seconds:.1f}s  {RATE} Hz stereo")
    return 0


if __name__ == "__main__":
    sys.exit(main())
