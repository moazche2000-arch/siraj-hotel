extends Node

const NIGHT = preload("res://assets/audio/night.wav")
const CUES := {
	"work": preload("res://assets/audio/work.wav"),
	"room": preload("res://assets/audio/room.wav"),
	"shift": preload("res://assets/audio/shift.wav"),
	"haunt": preload("res://assets/audio/haunt.wav"),
}

var ambience: AudioStreamPlayer
var cue_player: AudioStreamPlayer
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
	cue_player = AudioStreamPlayer.new()
	cue_player.volume_db = -12
	add_child(cue_player)
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
	if is_instance_valid(cue_player):
		cue_player.stop()


func play_cue(name: String) -> void:
	if muted or backgrounded or not is_instance_valid(cue_player) or not CUES.has(name):
		return
	cue_player.stream = CUES[name]
	cue_player.play()
