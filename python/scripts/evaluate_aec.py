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


def corrcoef(a: list[float], b: list[float]) -> float:
    n = min(len(a), len(b))
    if n == 0:
        return 0.0

    sa = 0.0
    sb = 0.0
    saa = 0.0
    sbb = 0.0
    sab = 0.0
    for i in range(n):
        x = a[i]
        y = b[i]
        sa += x
        sb += y
        saa += x * x
        sbb += y * y
        sab += x * y

    ma = sa / n
    mb = sb / n
    va = max(0.0, (saa / n) - ma * ma)
    vb = max(0.0, (sbb / n) - mb * mb)
    denom = math.sqrt(va * vb)
    if denom <= 1e-12:
        return 0.0

    cov = (sab / n) - ma * mb
    return cov / denom


def main() -> int:
    parser = argparse.ArgumentParser(description="Quick numeric sanity check for AEC output.")
    parser.add_argument("--dir", type=Path, default=Path("out/test_data"))
    args = parser.parse_args()

    ref_p = args.dir / "ref_signal.wav"
    mic_p = args.dir / "mic_mixed.wav"
    clean_p = args.dir / "clean.wav"

    sr_ref, ref = read_wav_pcm16_mono(ref_p)
    sr_mic, mic = read_wav_pcm16_mono(mic_p)
    sr_clean, clean = read_wav_pcm16_mono(clean_p)
    if sr_ref != sr_mic or sr_ref != sr_clean:
        raise ValueError(f"Sample rates differ: ref={sr_ref}, mic={sr_mic}, clean={sr_clean}")

    c_mic = corrcoef(mic, ref)
    c_clean = corrcoef(clean, ref)

    print("AEC evaluation (corr with reference, lower is better):")
    print(f"- corr(mic_mixed, ref): {c_mic:.4f}")
    print(f"- corr(clean, ref):     {c_clean:.4f}")

    if abs(c_clean) < abs(c_mic):
        print("[OK] clean is less correlated with ref than mic_mixed")
        return 0

    print("[WARN] clean is not less correlated than mic_mixed (check delay/alignment)")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

