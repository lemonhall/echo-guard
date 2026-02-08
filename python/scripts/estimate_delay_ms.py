from __future__ import annotations

import argparse
import math
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


def _dot(a: list[float], b: list[float], lag: int) -> tuple[float, float, float]:
    # Correlate a against b shifted by lag samples:
    # lag > 0 => a[t] vs b[t-lag]
    # lag < 0 => a[t] vs b[t-lag] where -lag is positive shift of b forward.
    if lag >= 0:
        start_a = lag
        start_b = 0
        n = min(len(a) - start_a, len(b))
    else:
        start_a = 0
        start_b = -lag
        n = min(len(a), len(b) - start_b)
    if n <= 0:
        return 0.0, 0.0, 0.0

    s_ab = 0.0
    s_aa = 0.0
    s_bb = 0.0
    for i in range(n):
        x = a[start_a + i]
        y = b[start_b + i]
        s_ab += x * y
        s_aa += x * x
        s_bb += y * y
    return s_ab, s_aa, s_bb


def estimate_delay_ms(
    mic: list[float],
    ref: list[float],
    sample_rate: int,
    max_delay_ms: int,
    decimate: int,
) -> tuple[int, float]:
    if decimate < 1:
        raise ValueError("--decimate must be >= 1")

    mic_ds = mic[::decimate]
    ref_ds = ref[::decimate]
    sr_ds = sample_rate / decimate

    max_lag = int(round((max_delay_ms / 1000.0) * sr_ds))
    best_lag = 0
    best_corr = -1.0

    # Search only non-negative lags: mic is typically delayed relative to ref.
    for lag in range(0, max_lag + 1):
        s_ab, s_aa, s_bb = _dot(mic_ds, ref_ds, lag)
        denom = math.sqrt(s_aa * s_bb) + 1e-12
        corr = s_ab / denom
        if corr > best_corr:
            best_corr = corr
            best_lag = lag

    delay_ms = int(round((best_lag / sr_ds) * 1000.0))
    return delay_ms, best_corr


def main() -> int:
    p = argparse.ArgumentParser(description="Estimate mic/ref delay via coarse cross-correlation.")
    p.add_argument("--mic", type=Path, required=True)
    p.add_argument("--ref", type=Path, required=True)
    p.add_argument("--max-delay-ms", type=int, default=300)
    p.add_argument("--decimate", type=int, default=20, help="Downsample factor for speed (20 => 2.4 kHz at 48 kHz).")
    args = p.parse_args()

    sr_mic, mic = read_wav_pcm16_mono(args.mic)
    sr_ref, ref = read_wav_pcm16_mono(args.ref)
    if sr_mic != sr_ref:
        raise SystemExit(f"[ERROR] Sample rates differ: mic={sr_mic} ref={sr_ref}")

    delay_ms, corr = estimate_delay_ms(
        mic=mic,
        ref=ref,
        sample_rate=sr_mic,
        max_delay_ms=args.max_delay_ms,
        decimate=args.decimate,
    )

    print(f"[OK] estimated_delay_ms={delay_ms} corr={corr:.4f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

