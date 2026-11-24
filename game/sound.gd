extends Node

const NIGHT = preload("res://assets/audio/night.wav")
const CUES := {
	"work": preload("res://assets/audio/work.wav"),
	"room": preload("res://assets/audio/room.wav"),
	"shift": preload("res://assets/audio/shift.wav"),
	"haunt": preload("res://assets/audio/haunt.wav"),
}

var ambience: AudioStreamPlayer
var muted := false
var ambience_paused := true
var backgrounded := false


func start_audio() -> void:
	if is_instance_valid(ambience) or DisplayServer.get_name() == "headless":
		return
	ambience = AudioStreamPlayer.new()
	ambience.stream = NIGHT
	ambience.volume_db = -20
	add_child(ambience)
	update_ambience()


func set_muted(value: bool) -> void:
	muted = value
	update_ambience()
	if muted:
		stop_cues()


func set_ambience_paused(value: bool) -> void:
	ambience_paused = value
	update_ambience()


func set_backgrounded(value: bool) -> void:
	backgrounded = value
	update_ambience()
	if backgrounded:
		stop_cues()


func update_ambience() -> void:
	if not is_instance_valid(ambience):
		return
	var should_play := not (muted or ambience_paused or backgrounded)
	if should_play and not ambience.playing:
		ambience.play()
	elif not should_play and ambience.playing:
		ambience.stop()


func stop_cues() -> void:
	for child in get_children():
		if child != ambience:
			child.stop()
			child.queue_free()


func play_cue(name: String) -> void:
	if muted or backgrounded or not is_instance_valid(ambience) or not CUES.has(name):
		return
	var cue := AudioStreamPlayer.new()
	cue.stream = CUES[name]
	cue.volume_db = -12
	add_child(cue)
	cue.finished.connect(cue.queue_free)
	cue.play()
