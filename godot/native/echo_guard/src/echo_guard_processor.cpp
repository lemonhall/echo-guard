#include "echo_guard_processor.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cmath>

namespace godot {

void EchoGuardProcessor::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_sample_rate_hz", "hz"), &EchoGuardProcessor::set_sample_rate_hz);
	ClassDB::bind_method(D_METHOD("get_sample_rate_hz"), &EchoGuardProcessor::get_sample_rate_hz);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "sample_rate_hz"), "set_sample_rate_hz", "get_sample_rate_hz");

	ClassDB::bind_method(D_METHOD("set_delay_ms", "ms"), &EchoGuardProcessor::set_delay_ms);
	ClassDB::bind_method(D_METHOD("get_delay_ms"), &EchoGuardProcessor::get_delay_ms);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "delay_ms"), "set_delay_ms", "get_delay_ms");

	ClassDB::bind_method(D_METHOD("set_aec_enabled", "enabled"), &EchoGuardProcessor::set_aec_enabled);
	ClassDB::bind_method(D_METHOD("get_aec_enabled"), &EchoGuardProcessor::get_aec_enabled);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "aec_enabled"), "set_aec_enabled", "get_aec_enabled");

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
#ifdef ECHO_GUARD_HAVE_WEBRTC_APM
	apm.reset();
#endif
}

int EchoGuardProcessor::get_sample_rate_hz() const {
	return sample_rate_hz;
}

void EchoGuardProcessor::set_delay_ms(int p_ms) {
	delay_ms = p_ms;
}

int EchoGuardProcessor::get_delay_ms() const {
	return delay_ms;
}

void EchoGuardProcessor::set_aec_enabled(bool p_enabled) {
	aec_enabled = p_enabled;
#ifdef ECHO_GUARD_HAVE_WEBRTC_APM
	apm.reset();
#endif
}

bool EchoGuardProcessor::get_aec_enabled() const {
	return aec_enabled;
}

void EchoGuardProcessor::set_vad_enabled(bool p_enabled) {
	vad_enabled = p_enabled;
#ifdef ECHO_GUARD_HAVE_WEBRTC_APM
	apm.reset();
#endif
}

bool EchoGuardProcessor::get_vad_enabled() const {
	return vad_enabled;
}

void EchoGuardProcessor::set_vad_likelihood(int p_likelihood) {
	vad_likelihood = p_likelihood;
#ifdef ECHO_GUARD_HAVE_WEBRTC_APM
	apm.reset();
#endif
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

#ifdef ECHO_GUARD_HAVE_WEBRTC_APM
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

	apm.reset(webrtc::AudioProcessing::Create());
	if (!apm) {
		UtilityFunctions::push_error("EchoGuardProcessor: AudioProcessing::Create failed");
		return;
	}

	webrtc::Config extra;
	apm->SetExtraOptions(extra);

	if (apm->Initialize(proc_cfg) != 0) {
		UtilityFunctions::push_error("EchoGuardProcessor: apm->Initialize failed");
		apm.reset();
		return;
	}

	if (aec_enabled) {
		auto *aec = apm->echo_cancellation();
		if (!aec) {
			UtilityFunctions::push_error("EchoGuardProcessor: apm->echo_cancellation() returned null");
			apm.reset();
			return;
		}
		aec->enable_drift_compensation(false);
		aec->set_suppression_level(webrtc::EchoCancellation::kHighSuppression);
		aec->Enable(true);
	}

	if (vad_enabled) {
		auto *vd = apm->voice_detection();
		if (vd) {
			vd->set_frame_size_ms(10);
			vd->set_likelihood(static_cast<webrtc::VoiceDetection::Likelihood>(vad_likelihood));
			vd->Enable(true);
		}
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

#ifdef ECHO_GUARD_HAVE_WEBRTC_APM
	ensure_apm();
#endif

#ifdef ECHO_GUARD_HAVE_WEBRTC_APM
	if (apm) {
		const size_t frame = mono_cfg.num_frames();
		const float *rev_src[1] = {rev_buf.data()};
		float *rev_dst[1] = {rev_buf.data()};
		const float *cap_src[1] = {cap_in.data()};
		float *cap_dst[1] = {cap_out.data()};

		const float g = post_gain;
		const int num_frames = (n + int(frame) - 1) / int(frame);
		voice_frames.resize(num_frames);
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

			const int rev_rc = apm->ProcessReverseStream(rev_src, mono_cfg, mono_cfg, rev_dst);
			if (rev_rc != webrtc::AudioProcessing::kNoError) {
				UtilityFunctions::push_error(String("EchoGuardProcessor: ProcessReverseStream failed rc=") + String::num_int64(rev_rc));
				break;
			}

			apm->set_stream_key_pressed(false);
			apm->set_stream_delay_ms(delay_ms);
			const int cap_rc = apm->ProcessStream(cap_src, mono_cfg, mono_cfg, cap_dst);
			if (cap_rc != webrtc::AudioProcessing::kNoError) {
				UtilityFunctions::push_error(String("EchoGuardProcessor: ProcessStream failed rc=") + String::num_int64(cap_rc));
				break;
			}

			bool frame_voice = false;
			if (vad_enabled && apm->voice_detection()) {
				frame_voice = apm->voice_detection()->stream_has_voice();
				has_voice = has_voice || frame_voice;
			}
			voice_frames[pos / int(frame)] = frame_voice ? 1 : 0;

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
		for (int i = 0; i < n; i++) {
			const float x = p_mic[i] * g;
			clean[i] = x;
			sum_sq += double(x) * double(x);
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
