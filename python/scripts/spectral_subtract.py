from __future__ import annotations

import argparse
import math
import wave
from array import array
from pathlib import Path

import numpy as np


def read_wav_pcm16_mono(path: Path) -> tuple[int, np.ndarray]:
    with wave.open(str(path), "rb") as wf:
        if wf.getsampwidth() != 2:
            raise ValueError(f"Only PCM16 WAV supported: {path}")
        sample_rate = wf.getframerate()
        channels = wf.getnchannels()
        frames = wf.readframes(wf.getnframes())

    samples_i16 = np.frombuffer(frames, dtype="<i2")
    if channels == 1:
        mono = samples_i16.astype(np.float32) / 32768.0
    elif channels == 2:
        stereo = samples_i16.reshape(-1, 2).astype(np.float32) / 32768.0
        mono = stereo.mean(axis=1)
    else:
        raise ValueError(f"Only mono/stereo WAV supported: {path} (channels={channels})")

    return sample_rate, mono


def write_wav_pcm16_mono(path: Path, sample_rate: int, samples: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)

    x = np.asarray(samples, dtype=np.float32)
    x = np.clip(x, -1.0, 1.0)
    pcm = (x * 32767.0).round().astype("<i2")

    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(pcm.tobytes())


def next_pow2(n: int) -> int:
    if n <= 0:
        return 1
    return 1 << (n - 1).bit_length()


def estimate_delay_ms_fft(
    mic: np.ndarray,
    ref: np.ndarray,
    sample_rate: int,
    max_delay_ms: int,
    decimate: int,
    window_s: float,
) -> tuple[int, float]:
    if decimate < 1:
        raise ValueError("--decimate must be >= 1")

    n_win = int(sample_rate * window_s)
    mic = mic[:n_win]
    ref = ref[:n_win]

    mic_ds = mic[::decimate]
    ref_ds = ref[::decimate]
    sr_ds = sample_rate / decimate

    if mic_ds.size == 0 or ref_ds.size == 0:
        return 0, 0.0

    max_lag = int(round((max_delay_ms / 1000.0) * sr_ds))
    max_lag = max(0, min(max_lag, mic_ds.size - 1))

    n_fft = next_pow2(int(mic_ds.size + ref_ds.size))
    X = np.fft.rfft(mic_ds, n=n_fft)
    Y = np.fft.rfft(ref_ds, n=n_fft)
    R = X * np.conj(Y)

    # PHAT weighting helps when spectra are colored (e.g., music).
    R /= (np.abs(R) + 1e-12)
    cc = np.fft.irfft(R, n=n_fft)

    # Positive lags: mic is typically delayed relative to ref.
    cc_pos = cc[: max_lag + 1]
    best_lag = int(np.argmax(cc_pos))
    best = float(cc_pos[best_lag])

    delay_ms = int(round((best_lag / sr_ds) * 1000.0))
    return delay_ms, best


def delay_ref(ref: np.ndarray, delay_samples: int, out_len: int) -> np.ndarray:
    if delay_samples <= 0:
        y = ref
    else:
        y = np.concatenate([np.zeros(delay_samples, dtype=np.float32), ref])
    if y.size < out_len:
        y = np.pad(y, (0, out_len - y.size))
    return y[:out_len]


def stft_frames(x: np.ndarray, n_fft: int, hop: int) -> np.ndarray:
    if n_fft <= 0 or hop <= 0:
        raise ValueError("n_fft and hop must be > 0")

    x = np.asarray(x, dtype=np.float32)
    if x.size < n_fft:
        x = np.pad(x, (0, n_fft - x.size))

    from numpy.lib.stride_tricks import sliding_window_view

    frames = sliding_window_view(x, n_fft)[::hop]
    return frames.astype(np.float32, copy=False)


def istft(frames: np.ndarray, win: np.ndarray, hop: int, out_len: int) -> np.ndarray:
    n_frames, n_fft = frames.shape
    y_len = hop * (n_frames - 1) + n_fft
    y = np.zeros(y_len, dtype=np.float32)
    wsum = np.zeros(y_len, dtype=np.float32)

    win2 = (win * win).astype(np.float32)
    for i in range(n_frames):
        start = i * hop
        y[start : start + n_fft] += frames[i] * win
        wsum[start : start + n_fft] += win2

    y /= np.maximum(wsum, 1e-8)
    return y[:out_len]


def spectral_cancel(
    mic: np.ndarray,
    ref: np.ndarray,
    sample_rate: int,
    *,
    delay_ms: int,
    n_fft: int,
    hop: int,
    alpha: float,
    beta: float,
    gate_ratio: float,
    h_smooth: float,
) -> np.ndarray:
    delay_samples = int(round((delay_ms / 1000.0) * sample_rate))
    ref_aligned = delay_ref(ref, delay_samples=delay_samples, out_len=mic.size)

    win = np.hanning(n_fft).astype(np.float32)
    mic_f = stft_frames(mic, n_fft=n_fft, hop=hop) * win
    ref_f = stft_frames(ref_aligned, n_fft=n_fft, hop=hop) * win

    M = np.fft.rfft(mic_f, axis=1)
    R = np.fft.rfft(ref_f, axis=1)

    n_frames, n_bins = M.shape
    C = np.empty_like(M)
    H = np.zeros((n_bins,), dtype=np.complex64)

    eps = 1e-10
    hs = float(np.clip(h_smooth, 0.0, 1.0))
    gr = max(0.0, float(gate_ratio))
    a = float(alpha)
    b = max(0.0, float(beta))

    for t in range(n_frames):
        m = M[t]
        r = R[t]

        rr = (np.abs(r) ** 2) + eps
        h_inst = (m * np.conj(r)) / rr
        H = (1.0 - hs) * H + hs * h_inst

        ratio = np.abs(r) / (np.abs(m) + eps)
        mask = (ratio >= gr).astype(np.float32)

        echo = (H * r) * mask
        c = m - (a * echo)

        if b > 0.0:
            mag_c = np.abs(c)
            mag_m = np.abs(m)
            mag_c = np.maximum(mag_c, b * mag_m)
            c = mag_c * np.exp(1j * np.angle(c))

        C[t] = c

    clean_frames = np.fft.irfft(C, n=n_fft, axis=1).astype(np.float32)
    clean = istft(clean_frames, win=win, hop=hop, out_len=mic.size)
    return clean


def main() -> int:
    p = argparse.ArgumentParser(description="Offline ref-based spectral cancellation experiment (WAV PCM16 mono).")
    p.add_argument("--mic", type=Path, required=True)
    p.add_argument("--ref", type=Path, required=True)
    p.add_argument("--out", type=Path, default=Path("clean_spectral.wav"))

    p.add_argument("--max-delay-ms", type=int, default=300)
    p.add_argument("--decimate", type=int, default=20)
    p.add_argument("--delay-window-s", type=float, default=3.0)
    p.add_argument("--delay-ms", type=int, default=-1, help="Override delay estimate; -1 to auto-estimate.")

    p.add_argument("--n-fft", type=int, default=2048)
    p.add_argument("--hop", type=int, default=512)
    p.add_argument("--alpha", type=float, default=1.0, help="Echo subtraction strength.")
    p.add_argument("--beta", type=float, default=0.01, help="Magnitude floor ratio vs mic (0 disables).")
    p.add_argument("--gate-ratio", type=float, default=0.02, help="Skip subtraction when |ref|/|mic| is below this.")
    p.add_argument("--h-smooth", type=float, default=0.05, help="Transfer smoothing (0..1).")
    args = p.parse_args()

    sr_mic, mic = read_wav_pcm16_mono(args.mic)
    sr_ref, ref = read_wav_pcm16_mono(args.ref)
    if sr_mic != sr_ref:
        raise SystemExit(f"[ERROR] Sample rates differ: mic={sr_mic} ref={sr_ref}")

    out_path = args.out
    if not out_path.is_absolute():
        # If the user passed just a filename, default to writing next to --mic.
        # If they passed a relative path with directories, respect it as-is.
        if out_path.parent == Path("."):
            out_path = args.mic.parent / out_path

    if args.delay_ms >= 0:
        delay_ms = int(args.delay_ms)
        score = float("nan")
    else:
        delay_ms, score = estimate_delay_ms_fft(
            mic=mic,
            ref=ref,
            sample_rate=sr_mic,
            max_delay_ms=args.max_delay_ms,
            decimate=args.decimate,
            window_s=args.delay_window_s,
        )

    clean = spectral_cancel(
        mic=mic,
        ref=ref,
        sample_rate=sr_mic,
        delay_ms=delay_ms,
        n_fft=args.n_fft,
        hop=args.hop,
        alpha=args.alpha,
        beta=args.beta,
        gate_ratio=args.gate_ratio,
        h_smooth=args.h_smooth,
    )

    write_wav_pcm16_mono(out_path, sr_mic, clean)
    if math.isnan(score):
        print(f"[OK] delay_ms={delay_ms} (manual)")
    else:
        print(f"[OK] delay_ms={delay_ms} delay_score={score:.4f}")
    print(f"[OK] wrote: {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
