extends Node

const RATE := 22050
const SCORES := {
	"work": [[480.0, 0.055], [650.0, 0.07]],
	"room": [[440.0, 0.09], [554.4, 0.09], [659.3, 0.18]],
	"shift": [[329.6, 0.12], [440.0, 0.12], [554.4, 0.14], [659.3, 0.28]],
	"haunt": [[132.0, 0.34], [93.0, 0.49]],
}

var cues := {}
var ambience: AudioStreamPlayer
var muted := false


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	for name in SCORES:
		cues[name] = synthesize(SCORES[name], name == "haunt")
	ambience = AudioStreamPlayer.new()
	ambience.stream = night_loop()
	ambience.volume_db = -20
	add_child(ambience)
	ambience.play()


func _exit_tree() -> void:
	if is_instance_valid(ambience):
		ambience.stop()


func set_muted(value: bool) -> void:
	muted = value
	if not is_instance_valid(ambience):
		return
	ambience.stream_paused = muted
	if muted:
		for child in get_children():
			if child != ambience:
				child.stop()
				child.queue_free()


func play_cue(name: String) -> void:
	if muted or not cues.has(name):
		return
	var cue := AudioStreamPlayer.new()
	cue.stream = cues[name]
	cue.volume_db = -12
	add_child(cue)
	cue.finished.connect(cue.queue_free)
	cue.play()


func synthesize(notes: Array, eerie: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	for note in notes:
		var frames := int(note[1] * RATE)
		var start := data.size()
		data.resize(start + frames * 2)
		for frame in frames:
			var time := float(frame) / RATE
			var phase: float = time * note[0] * TAU
			var envelope := minf(time * 110.0, 1.0) * pow(1.0 - float(frame) / frames, 1.5)
			var signal_value := sin(phase) * 0.55 + sin(phase * (1.37 if eerie else 2.0)) * 0.16
			data.encode_s16(start + frame * 2, int(signal_value * envelope * 22000))
	return wav(data)


func night_loop() -> AudioStreamWAV:
	var frames := RATE * 8
	var data := PackedByteArray()
	data.resize(frames * 2)
	for frame in frames:
		var time := float(frame) / RATE
		var breath := 0.52 + sin(time * TAU / 8.0) * 0.22
		var value := sin(time * TAU * 55.0) * 0.18 + sin(time * TAU * 82.5) * 0.08
		value += sin(time * TAU * 110.0) * 0.04
		data.encode_s16(frame * 2, int(value * breath * 20000))
	var stream := wav(data)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = frames
	return stream


func wav(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.mix_rate = RATE
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.data = data
	return stream
