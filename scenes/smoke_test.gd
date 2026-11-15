extends Node2D

## Minimal smoke test: logs a few facts, runs for one second, then quits with exit code 0.

var _frames := 0


func _ready() -> void:
	print("[smoke_test] ready, engine ", Engine.get_version_info().string)
	print("[smoke_test] renderer: ", RenderingServer.get_video_adapter_name())
	print("[smoke_test] label text: ", $Label.text)
	await get_tree().create_timer(1.0).timeout
	print("[smoke_test] ran %d frames, quitting cleanly" % _frames)
	get_tree().quit(0)


func _process(_delta: float) -> void:
	_frames += 1
