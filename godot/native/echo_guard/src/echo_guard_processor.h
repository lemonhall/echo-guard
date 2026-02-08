#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

#if defined(ECHO_GUARD_HAVE_WEBRTC_APM) && ECHO_GUARD_HAVE_WEBRTC_APM
#include <webrtc/modules/audio_processing/include/audio_processing.h>
#include <memory>
#include <vector>
#endif

namespace godot {

class EchoGuardProcessor : public RefCounted {
	GDCLASS(EchoGuardProcessor, RefCounted)

	int sample_rate_hz = 48000;
	int delay_ms = 0;
	bool aec_enabled = true;
	bool vad_enabled = true;
	int vad_likelihood = 2; // VoiceDetection::kModerateLikelihood
	float post_gain = 1.0f;

#if defined(ECHO_GUARD_HAVE_WEBRTC_APM) && ECHO_GUARD_HAVE_WEBRTC_APM
	std::unique_ptr<webrtc::AudioProcessing> apm;
	webrtc::StreamConfig mono_cfg;
	webrtc::ProcessingConfig proc_cfg;
	std::vector<float> rev_buf;
	std::vector<float> cap_in;
	std::vector<float> cap_out;

	void ensure_apm();
#endif

protected:
	static void _bind_methods();

public:
	void set_sample_rate_hz(int p_hz);
	int get_sample_rate_hz() const;

	void set_delay_ms(int p_ms);
	int get_delay_ms() const;

	void set_aec_enabled(bool p_enabled);
	bool get_aec_enabled() const;

	void set_vad_enabled(bool p_enabled);
	bool get_vad_enabled() const;

	void set_vad_likelihood(int p_likelihood);
	int get_vad_likelihood() const;

	void set_post_gain(float p_gain);
	float get_post_gain() const;

	Dictionary process_chunk(const PackedFloat32Array &p_mic, const PackedFloat32Array &p_ref);
};

} // namespace godot
