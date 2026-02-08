#include "api/audio/audio_processing.h"

#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <memory>
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
  (void)read_u32_le(in);  // riff size
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
    uint32_t chunk_size = read_u32_le(in);
    const std::string id(chunk_id, 4);

    if (id == "fmt ") {
      audio_format = read_u16_le(in);
      num_channels = read_u16_le(in);
      sample_rate = read_u32_le(in);
      (void)read_u32_le(in);  // byte rate
      (void)read_u16_le(in);  // block align
      bits_per_sample = read_u16_le(in);
      if (chunk_size > 16) {
        skip(in, chunk_size - 16);
      }
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

    if (chunk_size % 2 == 1) {
      skip(in, 1);  // padding byte
    }
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
                                 const std::vector<int16_t>& samples) {
  std::ofstream out(path, std::ios::binary);
  if (!out) {
    std::cerr << "[ERROR] Cannot write: " << path << "\n";
    return false;
  }

  const uint16_t num_channels = 1;
  const uint16_t bits_per_sample = 16;
  const uint16_t block_align = num_channels * (bits_per_sample / 8);
  const uint32_t byte_rate = static_cast<uint32_t>(sample_rate_hz) * block_align;
  const uint32_t data_bytes = static_cast<uint32_t>(samples.size() * sizeof(int16_t));
  const uint32_t riff_size = 4 + (8 + 16) + (8 + data_bytes);

  out.write("RIFF", 4);
  const uint32_t riff_size_le = riff_size;
  out.write(reinterpret_cast<const char*>(&riff_size_le), 4);
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
  out.write(reinterpret_cast<const char*>(samples.data()),
            static_cast<std::streamsize>(samples.size() * sizeof(int16_t)));

  return true;
}

struct Args {
  std::string mic_path;
  std::string ref_path;
  std::string out_path;
};

static void print_usage() {
  std::cout << "offline_aec (WSL)\n"
               "Usage:\n"
               "  offline_aec --mic <mic.wav> --ref <ref.wav> --out <clean.wav>\n"
               "\n"
               "Notes:\n"
               "  - WAV must be mono PCM16\n"
               "  - sample rate must match between mic/ref\n";
}

static std::optional<Args> parse_args(int argc, char** argv) {
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

    if (a == "--mic") {
      auto v = need("--mic");
      if (!v) return std::nullopt;
      args.mic_path = *v;
    } else if (a == "--ref") {
      auto v = need("--ref");
      if (!v) return std::nullopt;
      args.ref_path = *v;
    } else if (a == "--out") {
      auto v = need("--out");
      if (!v) return std::nullopt;
      args.out_path = *v;
    } else if (a == "-h" || a == "--help") {
      print_usage();
      return std::nullopt;
    } else {
      std::cerr << "[ERROR] Unknown arg: " << a << "\n";
      return std::nullopt;
    }
  }

  if (args.mic_path.empty() || args.ref_path.empty() || args.out_path.empty()) {
    print_usage();
    return std::nullopt;
  }
  return args;
}

static int16_t float_to_pcm16(float x) {
  if (x > 1.0f) x = 1.0f;
  if (x < -1.0f) x = -1.0f;
  return static_cast<int16_t>(std::lrintf(x * 32767.0f));
}

}  // namespace

int main(int argc, char** argv) {
  const auto args_opt = parse_args(argc, argv);
  if (!args_opt) return 2;
  const Args args = *args_opt;

  const auto mic_wav = read_wav_pcm16_mono(args.mic_path);
  const auto ref_wav = read_wav_pcm16_mono(args.ref_path);
  if (!mic_wav || !ref_wav) return 1;

  if (mic_wav->sample_rate_hz != ref_wav->sample_rate_hz) {
    std::cerr << "[ERROR] Sample rates differ: mic=" << mic_wav->sample_rate_hz
              << " ref=" << ref_wav->sample_rate_hz << "\n";
    return 1;
  }

  const int sample_rate = mic_wav->sample_rate_hz;
  const webrtc::StreamConfig mono_cfg(sample_rate, 1);
  webrtc::ProcessingConfig proc_cfg;
  proc_cfg.input_stream() = mono_cfg;
  proc_cfg.output_stream() = mono_cfg;
  proc_cfg.reverse_input_stream() = mono_cfg;
  proc_cfg.reverse_output_stream() = mono_cfg;

  webrtc::AudioProcessing::Config apm_cfg;
  apm_cfg.echo_canceller.enabled = true;
  apm_cfg.echo_canceller.mobile_mode = false;

  apm_cfg.noise_suppression.enabled = true;
  apm_cfg.noise_suppression.level =
      webrtc::AudioProcessing::Config::NoiseSuppression::kHigh;

  apm_cfg.gain_controller1.enabled = true;
  apm_cfg.gain_controller1.mode =
      webrtc::AudioProcessing::Config::GainController1::kAdaptiveDigital;

  apm_cfg.high_pass_filter.enabled = true;

  rtc::scoped_refptr<webrtc::AudioProcessing> apm =
      webrtc::AudioProcessingBuilder().SetConfig(apm_cfg).Create();
  if (!apm) {
    std::cerr << "[ERROR] AudioProcessingBuilder().Create failed\n";
    return 1;
  }

  if (apm->Initialize(proc_cfg) != 0) {
    std::cerr << "[ERROR] apm->Initialize failed\n";
    return 1;
  }

  const size_t frame = mono_cfg.num_frames();
  const size_t n = std::min(mic_wav->samples.size(), ref_wav->samples.size());

  std::vector<int16_t> out_pcm;
  out_pcm.reserve(n);

  std::vector<float> rev_buf(frame, 0.0f);
  std::vector<float> cap_in(frame, 0.0f);
  std::vector<float> cap_out(frame, 0.0f);

  for (size_t pos = 0; pos < n; pos += frame) {
    const size_t remain = n - pos;
    const size_t chunk = remain < frame ? remain : frame;

    for (size_t i = 0; i < frame; i++) {
      const size_t idx = pos + i;
      if (i < chunk) {
        rev_buf[i] = ref_wav->samples[idx] / 32768.0f;
        cap_in[i] = mic_wav->samples[idx] / 32768.0f;
      } else {
        rev_buf[i] = 0.0f;
        cap_in[i] = 0.0f;
      }
      cap_out[i] = 0.0f;
    }

    const float* rev_src[1] = {rev_buf.data()};
    float* rev_dst[1] = {rev_buf.data()};
    const int rev_rc = apm->ProcessReverseStream(rev_src, mono_cfg, mono_cfg, rev_dst);
    if (rev_rc != webrtc::AudioProcessing::kNoError) {
      std::cerr << "[ERROR] ProcessReverseStream failed at pos=" << pos << " rc=" << rev_rc
                << "\n";
      return 1;
    }

    const float* cap_src[1] = {cap_in.data()};
    float* cap_dst[1] = {cap_out.data()};
    apm->set_stream_key_pressed(false);

    const int cap_rc = apm->ProcessStream(cap_src, mono_cfg, mono_cfg, cap_dst);
    if (cap_rc != webrtc::AudioProcessing::kNoError) {
      std::cerr << "[ERROR] ProcessStream failed at pos=" << pos << " rc=" << cap_rc << "\n";
      return 1;
    }

    for (size_t i = 0; i < chunk; i++) {
      out_pcm.push_back(float_to_pcm16(cap_out[i]));
    }
  }

  if (!write_wav_pcm16_mono(args.out_path, sample_rate, out_pcm)) return 1;

  std::cout << "[OK] Wrote: " << args.out_path << "\n";
  return 0;
}
