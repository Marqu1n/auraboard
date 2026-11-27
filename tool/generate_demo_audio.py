#!/usr/bin/env python3
"""Generate copyright-free synthesized WAV audio for the demo board and test fixtures.

Uses only the Python standard library with a fixed PRNG seed so output is 100%
deterministic and reproducible. All loopable tracks use exact cycle counts and
wrap-around overlap-add crossfading for click-free, gapless looping.
"""

from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 22050
ROOT = Path(__file__).resolve().parent.parent


def write_wav(path: Path, samples: list[float], sample_rate: int = SAMPLE_RATE) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    peak = max((abs(s) for s in samples), default=1.0)
    scale = 0.85 / peak if peak > 0.85 else 1.0
    frames = bytearray()
    for s in samples:
        clamped = max(-1.0, min(1.0, s * scale))
        frames.extend(struct.pack("<h", int(clamped * 32767)))
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(bytes(frames))


def make_seamless_loop(raw: list[float], target_len: int, xfade_len: int) -> list[float]:
    """Fold tail of length xfade_len over the start using equal-power crossfade."""
    out = list(raw[:target_len])
    tail = raw[target_len : target_len + xfade_len]
    for i in range(min(xfade_len, len(tail))):
        t = i / xfade_len
        fade_in = math.sin(0.5 * math.pi * t)
        fade_out = math.cos(0.5 * math.pi * t)
        out[i] = out[i] * fade_in + tail[i] * fade_out
    return out


def synth_sword_clash() -> list[float]:
    rng = random.Random(101)
    n = int(0.85 * SAMPLE_RATE)
    freqs = [880.0, 1412.0, 2190.0, 3260.0, 4410.0]
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        attack = min(1.0, t / 0.004)
        ring = sum(
            math.sin(2.0 * math.pi * f * t) * math.exp(-t * (4.5 + idx * 1.8))
            for idx, f in enumerate(freqs)
        ) / len(freqs)
        burst = (rng.random() * 2.0 - 1.0) * math.exp(-t * 32.0) * 0.65
        samples.append(attack * (ring * 0.8 + burst))
    return samples


def synth_fireball_boom() -> list[float]:
    rng = random.Random(202)
    n = int(1.35 * SAMPLE_RATE)
    samples = []
    lp = 0.0
    phase = 0.0
    for i in range(n):
        t = i / SAMPLE_RATE
        freq = 140.0 * math.exp(-t * 2.4) + 34.0
        phase += 2.0 * math.pi * freq / SAMPLE_RATE
        sub = math.sin(phase) * math.exp(-t * 2.2)
        noise = rng.random() * 2.0 - 1.0
        alpha = 0.18 if t < 0.2 else 0.06
        lp = lp + alpha * (noise - lp)
        whoosh = lp * math.sin(min(math.pi, t / 0.35 * math.pi)) * 0.9 + lp * math.exp(-t * 2.5) * 0.8
        env = min(1.0, t / 0.015) * (1.0 - max(0.0, (t - 1.1) / 0.25))
        samples.append(env * (sub * 0.7 + whoosh * 0.9))
    return samples


def synth_heroic_chime() -> list[float]:
    n = int(0.75 * SAMPLE_RATE)
    notes = [(0.0, 523.25), (0.09, 659.25), (0.18, 783.99)]
    samples = [0.0] * n
    for start_s, f in notes:
        start_i = int(start_s * SAMPLE_RATE)
        for i in range(start_i, n):
            t = (i - start_i) / SAMPLE_RATE
            env = min(1.0, t / 0.008) * math.exp(-t * 4.2)
            tone = (
                math.sin(2.0 * math.pi * f * t)
                + 0.35 * math.sin(2.0 * math.pi * f * 2.0 * t)
                + 0.12 * math.sin(2.0 * math.pi * f * 3.0 * t)
            )
            samples[i] += env * tone * 0.32
    return samples


def synth_tavern_hearth_music() -> list[float]:
    """4.0s warm D-Dorian plucked lute loop."""
    dur = 4.0
    xfade = int(0.35 * SAMPLE_RATE)
    target_n = int(dur * SAMPLE_RATE)
    total_n = target_n + xfade
    samples = [0.0] * total_n

    # D3, A3, F3, C4, G3, D4, A3, E3 arpeggio over 4 seconds (8 eighth-bar plucks)
    plucks = [
        (0.0, 146.83),
        (0.5, 220.00),
        (1.0, 174.61),
        (1.5, 261.63),
        (2.0, 196.00),
        (2.5, 293.66),
        (3.0, 220.00),
        (3.5, 164.81),
    ]
    # Warm drone pad in D2 + A2 (exact integer cycles in 4.0s)
    f_d2 = round(73.42 * dur) / dur
    f_a2 = round(110.0 * dur) / dur
    for i in range(total_n):
        t = i / SAMPLE_RATE
        drone = 0.16 * math.sin(2.0 * math.pi * f_d2 * t) + 0.10 * math.sin(2.0 * math.pi * f_a2 * t)
        samples[i] += drone

    for onset, freq in plucks:
        start_i = int(onset * SAMPLE_RATE)
        for j in range(int(0.85 * SAMPLE_RATE)):
            idx = start_i + j
            if idx >= total_n:
                break
            t = j / SAMPLE_RATE
            env = min(1.0, t / 0.01) * math.exp(-t * 4.0)
            body = (
                math.sin(2.0 * math.pi * freq * t)
                + 0.4 * math.sin(2.0 * math.pi * freq * 2.0 * t) * math.exp(-t * 3.0)
                + 0.15 * math.sin(2.0 * math.pi * freq * 3.0 * t) * math.exp(-t * 6.0)
            )
            samples[idx] += env * body * 0.36

    return make_seamless_loop(samples, target_n, xfade)


def synth_combat_drums_music() -> list[float]:
    """4.0s driving tabletop battle drums + low tension ostinato."""
    rng = random.Random(303)
    dur = 4.0
    xfade = int(0.25 * SAMPLE_RATE)
    target_n = int(dur * SAMPLE_RATE)
    total_n = target_n + xfade
    samples = [0.0] * total_n

    # Low brass-like tension drone (exact cycles in 4.0s)
    f_low = round(55.0 * dur) / dur
    f_fifth = round(82.5 * dur) / dur
    for i in range(total_n):
        t = i / SAMPLE_RATE
        pulse = 0.75 + 0.25 * math.sin(2.0 * math.pi * 1.0 * t)
        samples[i] += pulse * (
            0.18 * math.sin(2.0 * math.pi * f_low * t)
            + 0.10 * math.sin(2.0 * math.pi * f_fifth * t)
        )

    # War drum pattern (beats per 4s)
    hits = [
        (0.0, 95.0, 0.85),
        (0.5, 130.0, 0.45),
        (0.75, 115.0, 0.55),
        (1.0, 92.0, 0.75),
        (1.5, 145.0, 0.50),
        (2.0, 95.0, 0.85),
        (2.5, 130.0, 0.45),
        (2.75, 115.0, 0.60),
        (3.0, 90.0, 0.80),
        (3.25, 140.0, 0.40),
        (3.5, 120.0, 0.55),
    ]
    for onset, base_f, amp in hits:
        start_i = int(onset * SAMPLE_RATE)
        hit_len = int(0.32 * SAMPLE_RATE)
        phase = 0.0
        for j in range(hit_len):
            idx = start_i + j
            if idx >= total_n:
                break
            t = j / SAMPLE_RATE
            f = base_f * math.exp(-t * 9.0) + 42.0
            phase += 2.0 * math.pi * f / SAMPLE_RATE
            skin = math.sin(phase) * math.exp(-t * 11.0)
            slap = (rng.random() * 2.0 - 1.0) * math.exp(-t * 48.0) * 0.35
            samples[idx] += amp * (skin * 0.7 + slap)

    return make_seamless_loop(samples, target_n, xfade)


def synth_rain_ambience() -> list[float]:
    """4.0s gentle rain noise loop (pink-ish filtered noise)."""
    rng = random.Random(404)
    dur = 4.0
    xfade = int(0.45 * SAMPLE_RATE)
    target_n = int(dur * SAMPLE_RATE)
    total_n = target_n + xfade
    samples = []
    b0 = b1 = b2 = 0.0
    for i in range(total_n):
        w = rng.random() * 2.0 - 1.0
        b0 = 0.997 * b0 + w * 0.029
        b1 = 0.985 * b1 + w * 0.032
        b2 = 0.950 * b2 + w * 0.048
        pink = b0 + b1 + b2 + w * 0.08
        # Gentle patter modulation
        t = i / SAMPLE_RATE
        swell = 0.85 + 0.15 * math.sin(2.0 * math.pi * 0.5 * t)
        samples.append(pink * swell * 0.45)
    return make_seamless_loop(samples, target_n, xfade)


def synth_dungeon_wind_ambience() -> list[float]:
    """4.0s hollow cavern wind + low stone resonance loop."""
    rng = random.Random(505)
    dur = 4.0
    xfade = int(0.5 * SAMPLE_RATE)
    target_n = int(dur * SAMPLE_RATE)
    total_n = target_n + xfade
    samples = []
    lp1 = lp2 = 0.0
    f_res1 = round(65.4 * dur) / dur
    f_res2 = round(98.0 * dur) / dur
    for i in range(total_n):
        t = i / SAMPLE_RATE
        w = rng.random() * 2.0 - 1.0
        cutoff = 0.045 + 0.025 * math.sin(2.0 * math.pi * 0.25 * t)
        lp1 += cutoff * (w - lp1)
        lp2 += cutoff * (lp1 - lp2)
        howl = (
            0.14 * math.sin(2.0 * math.pi * f_res1 * t)
            + 0.08 * math.sin(2.0 * math.pi * f_res2 * t)
        ) * (0.65 + 0.35 * math.sin(2.0 * math.pi * 0.25 * t))
        samples.append(lp2 * 1.4 + howl)
    return make_seamless_loop(samples, target_n, xfade)


def synth_test_tone(duration_s: float = 0.25, freq: float = 440.0) -> list[float]:
    n = int(duration_s * SAMPLE_RATE)
    return [
        0.5 * math.sin(2.0 * math.pi * freq * (i / SAMPLE_RATE))
        for i in range(n)
    ]


def main() -> None:
    demo_dir = ROOT / "assets" / "demo_audio"
    fixtures_dir = ROOT / "test" / "fixtures"

    write_wav(demo_dir / "sword_clash.wav", synth_sword_clash())
    write_wav(demo_dir / "fireball_boom.wav", synth_fireball_boom())
    write_wav(demo_dir / "heroic_chime.wav", synth_heroic_chime())
    write_wav(demo_dir / "tavern_hearth_music.wav", synth_tavern_hearth_music())
    write_wav(demo_dir / "combat_drums_music.wav", synth_combat_drums_music())
    write_wav(demo_dir / "rain_ambience.wav", synth_rain_ambience())
    write_wav(demo_dir / "dungeon_wind_ambience.wav", synth_dungeon_wind_ambience())

    # Deterministic test fixtures
    write_wav(fixtures_dir / "sample_effect.wav", synth_test_tone(0.25, 440.0))
    write_wav(fixtures_dir / "sample_loop.wav", synth_test_tone(0.50, 220.0))
    fixtures_dir.mkdir(parents=True, exist_ok=True)
    (fixtures_dir / "corrupt.wav").write_bytes(b"RIFF\x00\x00\x00\x00NOT_A_VALID_WAV_STREAM")
    (fixtures_dir / "unsupported.txt").write_text("not audio", encoding="utf-8")

    print("Generated demo audio and test fixtures successfully.")


if __name__ == "__main__":
    main()
