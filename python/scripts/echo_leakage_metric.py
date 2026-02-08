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
    # a[t] vs b[t-lag], lag>=0.
    start_a = lag
    start_b = 0
    n = min(len(a) - start_a, len(b))
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


def rms(x: list[float]) -> float:
    if not x:
        return 0.0
    s = 0.0
    for v in x:
        s += v * v
    return math.sqrt(s / len(x))


def best_corr(sig: list[float], ref: list[float], sample_rate: int, max_delay_ms: int, decimate: int) -> tuple[int, float]:
    sig_ds = sig[::decimate]
    ref_ds = ref[::decimate]
    sr_ds = sample_rate / decimate
    max_lag = int(round((max_delay_ms / 1000.0) * sr_ds))

    best_lag = 0
    best = -1.0
    for lag in range(0, max_lag + 1):
        s_ab, s_aa, s_bb = _dot(sig_ds, ref_ds, lag)
        corr = s_ab / (math.sqrt(s_aa * s_bb) + 1e-12)
        if corr > best:
            best = corr
            best_lag = lag

    lag_ms = int(round((best_lag / sr_ds) * 1000.0))
    return lag_ms, best


def main() -> int:
    p = argparse.ArgumentParser(description="Compute a coarse 'echo leakage' proxy via best correlation(sig, ref) over lag window.")
    p.add_argument("--sig", type=Path, required=True, help="Signal to evaluate (e.g., mic or clean).")
    p.add_argument("--ref", type=Path, required=True, help="Reference/far-end signal.")
    p.add_argument("--max-delay-ms", type=int, default=300)
    p.add_argument("--decimate", type=int, default=20)
    args = p.parse_args()

    sr_sig, sig = read_wav_pcm16_mono(args.sig)
    sr_ref, ref = read_wav_pcm16_mono(args.ref)
    if sr_sig != sr_ref:
        raise SystemExit(f"[ERROR] Sample rates differ: sig={sr_sig} ref={sr_ref}")

    lag_ms, corr = best_corr(sig, ref, sample_rate=sr_sig, max_delay_ms=args.max_delay_ms, decimate=args.decimate)
    print(f"[OK] sig_rms={rms(sig):.4f} best_lag_ms={lag_ms} best_corr={corr:.4f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

