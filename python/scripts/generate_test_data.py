from __future__ import annotations

import argparse
import json
import math
import random
import wave
from array import array
from pathlib import Path


def read_wav_pcm16_mono(path: Path) -> tuple[int, list[float]]:
    with wave.open(str(path), "rb") as wf:
        if wf.getsampwidth() != 2:
            raise ValueError(f"Only PCM16 WAV supported: {path}")
        sample_rate = wf.getframerate()
        channels = wf.getnchannels()
        frames = wf.readframes(wf.getnframes())

    samples_i16 = array("h")
    samples_i16.frombytes(frames)

    if channels == 1:
        mono = [s / 32768.0 for s in samples_i16]
    elif channels == 2:
        mono = []
        it = iter(samples_i16)
        for left in it:
            right = next(it)
            mono.append(((left + right) / 2) / 32768.0)
    else:
        raise ValueError(f"Only mono/stereo WAV supported: {path} (channels={channels})")

    return sample_rate, mono


def write_wav_pcm16_mono(path: Path, sample_rate: int, samples: list[float]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)

    pcm = array("h")
    for x in samples:
        x = max(-1.0, min(1.0, x))
        pcm.append(int(round(x * 32767.0)))

    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(pcm.tobytes())


def _normalize_peak(samples: list[float], peak: float = 0.98) -> list[float]:
    m = 0.0
    for x in samples:
        ax = abs(x)
        if ax > m:
            m = ax
    if m <= 1e-12:
        return samples
    scale = min(1.0, peak / m)
    return [x * scale for x in samples]


def synth_bgm(sample_rate: int, duration_s: float, seed: int) -> list[float]:
    rnd = random.Random(seed)
    n = int(sample_rate * duration_s)
    freqs = [110.0, 220.0, 330.0, 440.0, 554.37, 659.25]
    phases = [rnd.random() * 2 * math.pi for _ in freqs]
    amps = [0.12, 0.10, 0.08, 0.06, 0.05, 0.04]

    out: list[float] = []
    for i in range(n):
        t = i / sample_rate
        env = 0.5 + 0.5 * math.sin(2 * math.pi * 0.25 * t)
        x = 0.0
        for f, a, p in zip(freqs, amps, phases, strict=True):
            x += a * math.sin(2 * math.pi * f * t + p)
        out.append(x * env)
    return _normalize_peak(out, 0.9)


def synth_speech_like(sample_rate: int, duration_s: float, seed: int) -> list[float]:
    rnd = random.Random(seed + 1)
    n = int(sample_rate * duration_s)
    out = [0.0] * n

    # Build 3 "utterances" with silences.
    utterances = [
        (0.8, 2.0),
        (3.0, 4.2),
        (5.0, 6.5),
    ]
    for start, end in utterances:
        s = int(start * sample_rate)
        e = min(n, int(end * sample_rate))
        for i in range(s, e):
            # Amplitude-modulated noise + weak voiced tone.
            t = i / sample_rate
            env = 0.6 + 0.4 * math.sin(2 * math.pi * 3.0 * t)
            noise = (rnd.random() * 2.0 - 1.0) * 0.35
            voiced = math.sin(2 * math.pi * 140.0 * t) * 0.10
            out[i] = (noise + voiced) * env

    # Simple low-pass (one-pole) to make it less harsh.
    alpha = 0.15
    y = 0.0
    for i in range(n):
        y = alpha * out[i] + (1.0 - alpha) * y
        out[i] = y

    return _normalize_peak(out, 0.95)


def simple_reverb(signal: list[float], delay_samples: int, decay: float, taps: int) -> list[float]:
    n = len(signal)
    out = signal[:]
    for k in range(1, taps + 1):
        d = delay_samples * k
        g = decay**k
        for i in range(d, n):
            out[i] += signal[i - d] * g
    return _normalize_peak(out, 0.98)


def mix(mic: list[float], echo: list[float], echo_gain: float) -> list[float]:
    n = min(len(mic), len(echo))
    out = [0.0] * n
    for i in range(n):
        out[i] = mic[i] + echo[i] * echo_gain
    return _normalize_peak(out, 0.98)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate deterministic offline AEC test WAVs.")
    parser.add_argument("--out-dir", type=Path, default=Path("out/test_data"))
    parser.add_argument("--sample-rate", type=int, default=48_000)
    parser.add_argument("--duration-s", type=float, default=8.0)
    parser.add_argument("--seed", type=int, default=1337)
    parser.add_argument("--echo-gain", type=float, default=0.2)
    parser.add_argument("--bgm", type=Path, default=None)
    parser.add_argument("--speech", type=Path, default=None)
    args = parser.parse_args()

    sr = args.sample_rate

    if args.bgm and args.speech:
        sr_bgm, bgm = read_wav_pcm16_mono(args.bgm)
        sr_speech, speech = read_wav_pcm16_mono(args.speech)
        if sr_bgm != sr or sr_speech != sr:
            raise ValueError(
                f"Input sample rate must match --sample-rate={sr}. "
                f"Got bgm={sr_bgm}, speech={sr_speech}."
            )
    else:
        bgm = synth_bgm(sr, args.duration_s, args.seed)
        speech = synth_speech_like(sr, args.duration_s, args.seed)

    echo = simple_reverb(bgm, delay_samples=int(sr * 0.015), decay=0.45, taps=6)
    mic_mixed = mix(speech, echo, echo_gain=args.echo_gain)

    out_dir: Path = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    write_wav_pcm16_mono(out_dir / "ref_signal.wav", sr, bgm)
    write_wav_pcm16_mono(out_dir / "mic_mixed.wav", sr, mic_mixed)
    write_wav_pcm16_mono(out_dir / "speech_sample.wav", sr, speech)
    write_wav_pcm16_mono(out_dir / "bgm_sample.wav", sr, bgm)

    meta = {
        "sample_rate": sr,
        "duration_s": args.duration_s,
        "seed": args.seed,
        "echo_gain": args.echo_gain,
        "notes": "mic_mixed = speech + reverb(bgm) * echo_gain",
    }
    (out_dir / "meta.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")

    print(f"[OK] Wrote: {out_dir / 'mic_mixed.wav'}")
    print(f"[OK] Wrote: {out_dir / 'ref_signal.wav'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

