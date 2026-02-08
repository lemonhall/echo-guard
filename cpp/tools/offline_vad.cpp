#include "webrtc/common_audio/vad/include/webrtc_vad.h"

#include <cstdint>
#include <fstream>
#include <iostream>
#include <optional>
#include <string>
#include <vector>

namespace {

struct WavPcm16Mono {
  int sample_rate_hz = 0;
  std::vector<int16_t> samples;
};

static uint32_t read_u32_le(std::istream& in) {
  uint8_t b[4]{};
  in.read(reinterpret_cast<char*>(b), 4);
  return static_cast<uint32_t>(b[0]) | (static_cast<uint32_t>(b[1]) << 8) |
         (static_cast<uint32_t>(b[2]) << 16) | (static_cast<uint32_t>(b[3]) << 24);
}

static uint16_t read_u16_le(std::istream& in) {
  uint8_t b[2]{};
  in.read(reinterpret_cast<char*>(b), 2);
  return static_cast<uint16_t>(b[0]) | (static_cast<uint16_t>(b[1]) << 8);
}

static void skip(std::istream& in, size_t n) {
  in.seekg(static_cast<std::streamoff>(n), std::ios::cur);
}

static std::optional<WavPcm16Mono> read_wav_pcm16_mono(const std::string& path) {
  std::ifstream in(path, std::ios::binary);
  if (!in) {
    std::cerr << "[ERROR] Cannot open: " << path << "\n";
    return std::nullopt;
  }

  char riff[4]{};
  in.read(riff, 4);
  if (std::string(riff, 4) != "RIFF") {
    std::cerr << "[ERROR] Not RIFF: " << path << "\n";
    return std::nullopt;
  }
  (void)read_u32_le(in);
  char wave[4]{};
  in.read(wave, 4);
  if (std::string(wave, 4) != "WAVE") {
    std::cerr << "[ERROR] Not WAVE: " << path << "\n";
    return std::nullopt;
  }

  bool has_fmt = false;
  bool has_data = false;
  uint16_t audio_format = 0;
  uint16_t num_channels = 0;
  uint32_t sample_rate = 0;
  uint16_t bits_per_sample = 0;
  std::vector<int16_t> data;

  while (in && !(has_fmt && has_data)) {
    char chunk_id[4]{};
    in.read(chunk_id, 4);
    if (!in) break;
    const uint32_t chunk_size = read_u32_le(in);
    const std::string id(chunk_id, 4);

    if (id == "fmt ") {
      audio_format = read_u16_le(in);
      num_channels = read_u16_le(in);
      sample_rate = read_u32_le(in);
      (void)read_u32_le(in);
      (void)read_u16_le(in);
      bits_per_sample = read_u16_le(in);
      if (chunk_size > 16) skip(in, chunk_size - 16);
      has_fmt = true;
    } else if (id == "data") {
      if (!has_fmt) {
        std::cerr << "[ERROR] WAV missing fmt before data: " << path << "\n";
        return std::nullopt;
      }
      if (audio_format != 1 || bits_per_sample != 16) {
        std::cerr << "[ERROR] Only PCM16 supported: " << path << "\n";
        return std::nullopt;
      }
      if (num_channels != 1) {
        std::cerr << "[ERROR] Only mono supported: " << path << " (channels=" << num_channels
                  << ")\n";
        return std::nullopt;
      }
      if (chunk_size % 2 != 0) {
        std::cerr << "[ERROR] Invalid PCM16 data size: " << path << "\n";
        return std::nullopt;
      }

      const size_t samples = chunk_size / 2;
      data.resize(samples);
      in.read(reinterpret_cast<char*>(data.data()), static_cast<std::streamsize>(chunk_size));
      has_data = true;
    } else {
      skip(in, chunk_size);
    }

    if (chunk_size % 2 == 1) skip(in, 1);
  }

  if (!has_fmt || !has_data) {
    std::cerr << "[ERROR] Incomplete WAV: " << path << "\n";
    return std::nullopt;
  }

  WavPcm16Mono wav;
  wav.sample_rate_hz = static_cast<int>(sample_rate);
  wav.samples = std::move(data);
  return wav;
}

static bool write_wav_pcm16_mono(const std::string& path,
                                 int sample_rate_hz,
                                 const std::vector<int16_t>& samples,
                                 size_t start,
                                 size_t end) {
  if (start > end || end > samples.size()) return false;

  std::ofstream out(path, std::ios::binary);
  if (!out) {
    std::cerr << "[ERROR] Cannot write: " << path << "\n";
    return false;
  }

  const uint16_t num_channels = 1;
  const uint16_t bits_per_sample = 16;
  const uint16_t block_align = num_channels * (bits_per_sample / 8);
  const uint32_t byte_rate = static_cast<uint32_t>(sample_rate_hz) * block_align;
  const uint32_t data_bytes = static_cast<uint32_t>((end - start) * sizeof(int16_t));
  const uint32_t riff_size = 4 + (8 + 16) + (8 + data_bytes);

  out.write("RIFF", 4);
  out.write(reinterpret_cast<const char*>(&riff_size), 4);
  out.write("WAVE", 4);

  out.write("fmt ", 4);
  const uint32_t fmt_size = 16;
  out.write(reinterpret_cast<const char*>(&fmt_size), 4);
  const uint16_t pcm_format = 1;
  out.write(reinterpret_cast<const char*>(&pcm_format), 2);
  out.write(reinterpret_cast<const char*>(&num_channels), 2);
  const uint32_t sr = static_cast<uint32_t>(sample_rate_hz);
  out.write(reinterpret_cast<const char*>(&sr), 4);
  out.write(reinterpret_cast<const char*>(&byte_rate), 4);
  out.write(reinterpret_cast<const char*>(&block_align), 2);
  out.write(reinterpret_cast<const char*>(&bits_per_sample), 2);

  out.write("data", 4);
  out.write(reinterpret_cast<const char*>(&data_bytes), 4);
  out.write(reinterpret_cast<const char*>(samples.data() + start),
            static_cast<std::streamsize>((end - start) * sizeof(int16_t)));
  return true;
}

struct Args {
  std::string in_path;
  std::string out_dir;
  int aggressiveness = 2;
  int frame_ms = 10;
  int start_trigger = 2;
  int end_trigger = 10;
  int pad_ms = 80;
  int min_segment_ms = 200;
};

static void usage() {
  std::cout << "offline_vad (WSL)\n"
               "Usage:\n"
               "  offline_vad --in <clean.wav> --out-dir <dir> [--aggr 0..3]\n"
               "             [--start 1..] [--end 1..] [--pad-ms N] [--min-ms N]\n"
               "\n"
               "Outputs:\n"
               "  <out-dir>/vad_result.txt\n"
               "  <out-dir>/segment_001.wav ...\n";
}

static std::optional<Args> parse(int argc, char** argv) {
  Args args;
  for (int i = 1; i < argc; i++) {
    const std::string a = argv[i];
    auto need = [&](const char* name) -> std::optional<std::string> {
      if (i + 1 >= argc) {
        std::cerr << "[ERROR] Missing value for " << name << "\n";
        return std::nullopt;
      }
      return std::string(argv[++i]);
    };

    if (a == "--in") {
      auto v = need("--in");
      if (!v) return std::nullopt;
      args.in_path = *v;
    } else if (a == "--out-dir") {
      auto v = need("--out-dir");
      if (!v) return std::nullopt;
      args.out_dir = *v;
    } else if (a == "--aggr") {
      auto v = need("--aggr");
      if (!v) return std::nullopt;
      args.aggressiveness = std::stoi(*v);
    } else if (a == "--start") {
      auto v = need("--start");
      if (!v) return std::nullopt;
      args.start_trigger = std::stoi(*v);
    } else if (a == "--end") {
      auto v = need("--end");
      if (!v) return std::nullopt;
      args.end_trigger = std::stoi(*v);
    } else if (a == "--pad-ms") {
      auto v = need("--pad-ms");
      if (!v) return std::nullopt;
      args.pad_ms = std::stoi(*v);
    } else if (a == "--min-ms") {
      auto v = need("--min-ms");
      if (!v) return std::nullopt;
      args.min_segment_ms = std::stoi(*v);
    } else if (a == "-h" || a == "--help") {
      usage();
      return std::nullopt;
    } else {
      std::cerr << "[ERROR] Unknown arg: " << a << "\n";
      return std::nullopt;
    }
  }

  if (args.in_path.empty() || args.out_dir.empty()) {
    usage();
    return std::nullopt;
  }
  if (args.aggressiveness < 0 || args.aggressiveness > 3) {
    std::cerr << "[ERROR] --aggr must be 0..3\n";
    return std::nullopt;
  }
  return args;
}

struct SegmentMs {
  int start_ms = 0;
  int end_ms = 0;
};

}  // namespace

int main(int argc, char** argv) {
  const auto args_opt = parse(argc, argv);
  if (!args_opt) return 2;
  const Args args = *args_opt;

  const auto wav = read_wav_pcm16_mono(args.in_path);
  if (!wav) return 1;
  const int sr = wav->sample_rate_hz;

  const int frame_len = (sr * args.frame_ms) / 1000;
  if (frame_len <= 0) {
    std::cerr << "[ERROR] Bad frame length\n";
    return 1;
  }

  if (WebRtcVad_ValidRateAndFrameLength(sr, static_cast<size_t>(frame_len)) != 0) {
    std::cerr << "[ERROR] Unsupported sample rate / frame length for WebRTC VAD: sr=" << sr
              << " frame_len=" << frame_len << "\n";
    std::cerr << "        Try 8000/16000/32000/48000 Hz with 10/20/30 ms frames.\n";
    return 1;
  }

  VadInst* vad = WebRtcVad_Create();
  if (!vad) {
    std::cerr << "[ERROR] WebRtcVad_Create failed\n";
    return 1;
  }
  if (WebRtcVad_Init(vad) != 0) {
    std::cerr << "[ERROR] WebRtcVad_Init failed\n";
    WebRtcVad_Free(vad);
    return 1;
  }
  if (WebRtcVad_set_mode(vad, args.aggressiveness) != 0) {
    std::cerr << "[ERROR] WebRtcVad_set_mode failed\n";
    WebRtcVad_Free(vad);
    return 1;
  }

  const std::string result_path = args.out_dir + "/vad_result.txt";
  std::ofstream result(result_path);
  if (!result) {
    std::cerr << "[ERROR] Cannot write: " << result_path << "\n";
    WebRtcVad_Free(vad);
    return 1;
  }

  result << "# frame_index\tstart_ms\tvad\n";

  const size_t total = wav->samples.size();
  const size_t num_frames = (total + frame_len - 1) / frame_len;

  // Hysteresis segmenter.
  std::vector<SegmentMs> segments;
  bool in_speech = false;
  int active_run = 0;
  int passive_run = 0;
  int seg_start_ms = 0;

  auto ms_for_frame = [&](size_t frame_index) -> int {
    return static_cast<int>(frame_index * args.frame_ms);
  };

  for (size_t f = 0; f < num_frames; f++) {
    const size_t start = f * frame_len;
    int vad_rc = 0;
    if (start + frame_len <= total) {
      vad_rc = WebRtcVad_Process(vad, sr, wav->samples.data() + start, static_cast<size_t>(frame_len));
    } else {
      // Pad last frame with zeros.
      std::vector<int16_t> tmp(static_cast<size_t>(frame_len), 0);
      const size_t remain = total - start;
      for (size_t i = 0; i < remain; i++) tmp[i] = wav->samples[start + i];
      vad_rc = WebRtcVad_Process(vad, sr, tmp.data(), static_cast<size_t>(frame_len));
    }

    const int vad_label = (vad_rc == 1) ? 1 : 0;
    result << f << "\t" << ms_for_frame(f) << "\t" << vad_label << "\n";

    if (vad_rc == 1) {
      active_run++;
      passive_run = 0;
    } else {
      passive_run++;
      active_run = 0;
    }

    if (!in_speech) {
      if (vad_rc == 1 && active_run >= args.start_trigger) {
        const size_t start_frame = (f + 1) - static_cast<size_t>(args.start_trigger);
        seg_start_ms = ms_for_frame(start_frame);
        in_speech = true;
      }
    } else {
      if (vad_rc == 0 && passive_run >= args.end_trigger) {
        const size_t end_frame = (f + 1) - static_cast<size_t>(args.end_trigger);
        const int seg_end_ms = ms_for_frame(end_frame + 1);
        segments.push_back({seg_start_ms, seg_end_ms});
        in_speech = false;
      }
    }
  }

  if (in_speech) {
    const int seg_end_ms = ms_for_frame(num_frames);
    segments.push_back({seg_start_ms, seg_end_ms});
  }

  WebRtcVad_Free(vad);
  result.close();

  // Export segments.
  const int pad = args.pad_ms;
  const int min_ms = args.min_segment_ms;
  int written = 0;

  for (size_t i = 0; i < segments.size(); i++) {
    int s_ms = segments[i].start_ms - pad;
    int e_ms = segments[i].end_ms + pad;
    if (s_ms < 0) s_ms = 0;
    if (e_ms < s_ms) continue;
    if ((e_ms - s_ms) < min_ms) continue;

    const size_t s = static_cast<size_t>((static_cast<int64_t>(s_ms) * sr) / 1000);
    const size_t e = static_cast<size_t>((static_cast<int64_t>(e_ms) * sr) / 1000);
    const size_t s_clamped = (s > total) ? total : s;
    const size_t e_clamped = (e > total) ? total : e;
    if (e_clamped <= s_clamped) continue;

    char name[64];
    std::snprintf(name, sizeof(name), "/segment_%03d.wav", written + 1);
    const std::string out_path = args.out_dir + name;

    if (!write_wav_pcm16_mono(out_path, sr, wav->samples, s_clamped, e_clamped)) {
      std::cerr << "[ERROR] Failed writing: " << out_path << "\n";
      return 1;
    }
    written++;
  }

  std::cout << "[OK] Wrote: " << result_path << "\n";
  std::cout << "[OK] Segments: " << written << "\n";
  return (written > 0) ? 0 : 1;
}

