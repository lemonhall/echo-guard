#include "echo_guard_processor.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cmath>

namespace godot {

void EchoGuardProcessor::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_sample_rate_hz", "hz"), &EchoGuardProcessor::set_sample_rate_hz);
	ClassDB::bind_method(D_METHOD("get_sample_rate_hz"), &EchoGuardProcessor::get_sample_rate_hz);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "sample_rate_hz"), "set_sample_rate_hz", "get_sample_rate_hz");

	ClassDB::bind_method(D_METHOD("set_aec_enabled", "enabled"), &EchoGuardProcessor::set_aec_enabled);
	ClassDB::bind_method(D_METHOD("get_aec_enabled"), &EchoGuardProcessor::get_aec_enabled);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "aec_enabled"), "set_aec_enabled", "get_aec_enabled");

	ClassDB::bind_method(D_METHOD("set_aec_mobile_mode", "enabled"), &EchoGuardProcessor::set_aec_mobile_mode);
	ClassDB::bind_method(D_METHOD("get_aec_mobile_mode"), &EchoGuardProcessor::get_aec_mobile_mode);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "aec_mobile_mode"), "set_aec_mobile_mode", "get_aec_mobile_mode");

	ClassDB::bind_method(D_METHOD("set_vad_enabled", "enabled"), &EchoGuardProcessor::set_vad_enabled);
	ClassDB::bind_method(D_METHOD("get_vad_enabled"), &EchoGuardProcessor::get_vad_enabled);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "vad_enabled"), "set_vad_enabled", "get_vad_enabled");

	ClassDB::bind_method(D_METHOD("set_vad_likelihood", "likelihood"), &EchoGuardProcessor::set_vad_likelihood);
	ClassDB::bind_method(D_METHOD("get_vad_likelihood"), &EchoGuardProcessor::get_vad_likelihood);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "vad_likelihood"), "set_vad_likelihood", "get_vad_likelihood");

	ClassDB::bind_method(D_METHOD("set_post_gain", "gain"), &EchoGuardProcessor::set_post_gain);
	ClassDB::bind_method(D_METHOD("get_post_gain"), &EchoGuardProcessor::get_post_gain);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "post_gain"), "set_post_gain", "get_post_gain");

	ClassDB::bind_method(D_METHOD("process_chunk", "mic", "ref"), &EchoGuardProcessor::process_chunk);
}

void EchoGuardProcessor::set_sample_rate_hz(int p_hz) {
	sample_rate_hz = p_hz;
#if defined(ECHO_GUARD_HAVE_WEBRTC_APM) && ECHO_GUARD_HAVE_WEBRTC_APM
	apm = nullptr;
#endif
}

int EchoGuardProcessor::get_sample_rate_hz() const {
	return sample_rate_hz;
}

void EchoGuardProcessor::set_aec_enabled(bool p_enabled) {
	aec_enabled = p_enabled;
#if defined(ECHO_GUARD_HAVE_WEBRTC_APM) && ECHO_GUARD_HAVE_WEBRTC_APM
	apm = nullptr;
#endif
}

bool EchoGuardProcessor::get_aec_enabled() const {
	return aec_enabled;
}

void EchoGuardProcessor::set_aec_mobile_mode(bool p_enabled) {
	aec_mobile_mode = p_enabled;
#if defined(ECHO_GUARD_HAVE_WEBRTC_APM) && ECHO_GUARD_HAVE_WEBRTC_APM
	apm = nullptr;
#endif
}

bool EchoGuardProcessor::get_aec_mobile_mode() const {
	return aec_mobile_mode;
}

void EchoGuardProcessor::set_vad_enabled(bool p_enabled) {
	vad_enabled = p_enabled;
}

bool EchoGuardProcessor::get_vad_enabled() const {
	return vad_enabled;
}

void EchoGuardProcessor::set_vad_likelihood(int p_likelihood) {
	vad_likelihood = p_likelihood;
}

int EchoGuardProcessor::get_vad_likelihood() const {
	return vad_likelihood;
}

void EchoGuardProcessor::set_post_gain(float p_gain) {
	post_gain = p_gain;
}

float EchoGuardProcessor::get_post_gain() const {
	return post_gain;
}

#if defined(ECHO_GUARD_HAVE_WEBRTC_APM) && ECHO_GUARD_HAVE_WEBRTC_APM
void EchoGuardProcessor::ensure_apm() {
	if (apm) {
		return;
	}

	if (sample_rate_hz != 8000 && sample_rate_hz != 16000 && sample_rate_hz != 32000 && sample_rate_hz != 48000) {
		UtilityFunctions::push_warning(String("EchoGuardProcessor: unsupported sample_rate_hz=") + String::num_int64(sample_rate_hz) +
				" (expected 8000/16000/32000/48000). Falling back to passthrough.");
		return;
	}

	mono_cfg = webrtc::StreamConfig(sample_rate_hz, 1);
	proc_cfg = webrtc::ProcessingConfig();
	proc_cfg.input_stream() = mono_cfg;
	proc_cfg.output_stream() = mono_cfg;
	proc_cfg.reverse_input_stream() = mono_cfg;
	proc_cfg.reverse_output_stream() = mono_cfg;

	webrtc::AudioProcessing::Config apm_cfg;
	apm_cfg.echo_canceller.enabled = aec_enabled;
	apm_cfg.echo_canceller.mobile_mode = aec_mobile_mode;

	apm_cfg.noise_suppression.enabled = true;
	apm_cfg.noise_suppression.level =
			webrtc::AudioProcessing::Config::NoiseSuppression::kHigh;

	apm_cfg.gain_controller1.enabled = true;
	apm_cfg.gain_controller1.mode =
			webrtc::AudioProcessing::Config::GainController1::kAdaptiveDigital;

	apm_cfg.high_pass_filter.enabled = true;

	apm = webrtc::AudioProcessingBuilder().SetConfig(apm_cfg).Create();
	if (!apm) {
		UtilityFunctions::push_error("EchoGuardProcessor: AudioProcessingBuilder().Create failed");
		return;
	}

	if (apm->Initialize(proc_cfg) != 0) {
		UtilityFunctions::push_error("EchoGuardProcessor: apm->Initialize failed");
		apm = nullptr;
		return;
	}

	const size_t frame = mono_cfg.num_frames();
	rev_buf.assign(frame, 0.0f);
	cap_in.assign(frame, 0.0f);
	cap_out.assign(frame, 0.0f);
}
#endif

Dictionary EchoGuardProcessor::process_chunk(const PackedFloat32Array &p_mic, const PackedFloat32Array &p_ref) {
	Dictionary out;

	const int n = p_mic.size();
	if (n <= 0) {
		out["clean"] = PackedFloat32Array();
		out["rms"] = 0.0;
		out["frames"] = 0;
		out["has_voice"] = false;
		out["voice_frames"] = PackedByteArray();
		return out;
	}
	if (p_ref.size() != n) {
		UtilityFunctions::push_warning(String("EchoGuardProcessor.process_chunk: mic/ref size mismatch: ") + String::num_int64(n) +
				" vs " + String::num_int64(p_ref.size()));
	}

	PackedFloat32Array clean;
	clean.resize(n);

	bool has_voice = false;
	PackedByteArray voice_frames;
	double sum_sq = 0.0;

#if defined(ECHO_GUARD_HAVE_WEBRTC_APM) && ECHO_GUARD_HAVE_WEBRTC_APM
	ensure_apm();
#endif

#if defined(ECHO_GUARD_HAVE_WEBRTC_APM) && ECHO_GUARD_HAVE_WEBRTC_APM
	if (apm) {
		const size_t frame = mono_cfg.num_frames();
		const float *rev_src[1] = {rev_buf.data()};
		float *rev_dst[1] = {rev_buf.data()};
		const float *cap_src[1] = {cap_in.data()};
		float *cap_dst[1] = {cap_out.data()};

		const float g = post_gain;
		const int num_frames = (n + int(frame) - 1) / int(frame);
		if (vad_enabled) {
			voice_frames.resize(num_frames);
		}
		const int likelihood = vad_likelihood < 0 ? 0 : (vad_likelihood > 3 ? 3 : vad_likelihood);
		const float threshold_dbfs =
				likelihood == 0 ? -25.0f : (likelihood == 1 ? -30.0f : (likelihood == 2 ? -35.0f : -40.0f));
		const float threshold = std::pow(10.0f, threshold_dbfs / 20.0f);
		for (int pos = 0; pos < n; pos += int(frame)) {
			const int remain = n - pos;
			const int chunk = remain < int(frame) ? remain : int(frame);

			for (size_t i = 0; i < frame; i++) {
				const int idx = pos + int(i);
				if (int(i) < chunk && idx < n && idx < p_ref.size()) {
					rev_buf[i] = p_ref[idx];
					cap_in[i] = p_mic[idx];
				} else {
					rev_buf[i] = 0.0f;
					cap_in[i] = 0.0f;
				}
				cap_out[i] = 0.0f;
			}

			if (aec_enabled) {
				const int rev_rc = apm->ProcessReverseStream(rev_src, mono_cfg, mono_cfg, rev_dst);
				if (rev_rc != webrtc::AudioProcessing::kNoError) {
					UtilityFunctions::push_error(String("EchoGuardProcessor: ProcessReverseStream failed rc=") + String::num_int64(rev_rc));
					break;
				}
			}

			apm->set_stream_key_pressed(false);
			const int cap_rc = apm->ProcessStream(cap_src, mono_cfg, mono_cfg, cap_dst);
			if (cap_rc != webrtc::AudioProcessing::kNoError) {
				UtilityFunctions::push_error(String("EchoGuardProcessor: ProcessStream failed rc=") + String::num_int64(cap_rc));
				break;
			}

			bool frame_voice = false;
			if (vad_enabled) {
				double frame_sum_sq = 0.0;
				for (int i = 0; i < chunk; i++) {
					const float x = cap_out[size_t(i)];
					frame_sum_sq += double(x) * double(x);
				}
				const double frame_rms = std::sqrt(frame_sum_sq / double(chunk));
				frame_voice = float(frame_rms) >= threshold;
				has_voice = has_voice || frame_voice;
				voice_frames[pos / int(frame)] = frame_voice ? 1 : 0;
			}

			for (int i = 0; i < chunk; i++) {
				const float x = cap_out[size_t(i)] * g;
				clean[pos + i] = x;
				sum_sq += double(x) * double(x);
			}
		}
	} else
#endif
	{
		// Fallback passthrough (no WebRTC available).
		const float g = post_gain;
		const int frame = sample_rate_hz > 0 ? (sample_rate_hz / 100) : 480;
		const int num_frames = (n + frame - 1) / frame;
		if (vad_enabled) {
			voice_frames.resize(num_frames);
		}
		const int likelihood = vad_likelihood < 0 ? 0 : (vad_likelihood > 3 ? 3 : vad_likelihood);
		const float threshold_dbfs =
				likelihood == 0 ? -25.0f : (likelihood == 1 ? -30.0f : (likelihood == 2 ? -35.0f : -40.0f));
		const float threshold = std::pow(10.0f, threshold_dbfs / 20.0f);
		for (int i = 0; i < n; i++) {
			const float x = p_mic[i] * g;
			clean[i] = x;
			sum_sq += double(x) * double(x);
		}
		if (vad_enabled) {
			for (int f = 0; f < num_frames; f++) {
				const int pos = f * frame;
				const int remain = n - pos;
				const int chunk = remain < frame ? remain : frame;
				if (chunk <= 0) break;

				double frame_sum_sq = 0.0;
				for (int i = 0; i < chunk; i++) {
					const float x = clean[pos + i];
					frame_sum_sq += double(x) * double(x);
				}
				const double frame_rms = std::sqrt(frame_sum_sq / double(chunk));
				const bool frame_voice = float(frame_rms) >= threshold;
				has_voice = has_voice || frame_voice;
				voice_frames[f] = frame_voice ? 1 : 0;
			}
		}
	}

	const double rms = std::sqrt(sum_sq / double(n));

	out["clean"] = clean;
	out["rms"] = rms;
	out["frames"] = n;
	out["has_voice"] = has_voice;
	out["voice_frames"] = voice_frames;
	return out;
}

} // namespace godot
