extends SceneTree


func _initialize() -> void:
	var bus_name := "Introspect"
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")

	var cap := AudioEffectCapture.new()
	AudioServer.add_bus_effect(idx, cap, 0)
	var inst: Object = AudioServer.get_bus_effect_instance(idx, 0)

	print("capture instance class: %s" % inst.get_class())
	for name in ["get_frames_available", "get_buffer", "can_get_buffer", "get_written_frames", "get_audio_buffer", "clear_buffer"]:
		print("- has_method(%s)=%s" % [name, inst.has_method(name)])

	var methods := inst.get_method_list()
	print("methods containing 'frame'/'buffer':")
	for m in methods:
		var n := String(m.get("name", ""))
		if "frame" in n or "buffer" in n:
			print("  - %s" % n)

	print("")
	print("capture effect class: %s" % cap.get_class())
	for name2 in ["get_frames_available", "get_buffer", "can_get_buffer", "clear_buffer"]:
		print("- cap.has_method(%s)=%s" % [name2, cap.has_method(name2)])
	var methods2 := cap.get_method_list()
	print("cap methods containing 'frame'/'buffer':")
	for m2 in methods2:
		var n2 := String(m2.get("name", ""))
		if "frame" in n2 or "buffer" in n2:
			print("  - %s" % n2)

	quit()
