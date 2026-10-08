# DEV-UI01: exercise the real root viewport stretch and in-game controls.
extends SceneTree

var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1
	print(("PASS " if value else "FAIL ") + message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	check(root.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS, "UI uses resolution-independent canvas scaling")
	check(root.content_scale_size == Vector2i(1280, 720), "1280x720 logical design size")
	check(root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_KEEP, "aspect ratio is preserved")
	for dimensions in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3840, 2160), Vector2i(2560, 1600), Vector2i(960, 540)]:
		root.size = dimensions
		await process_frame
		await process_frame
		var scale_factor := minf(float(dimensions.x) / 1280.0, float(dimensions.y) / 720.0)
		check(root.get_stretch_transform().get_scale().is_equal_approx(Vector2(scale_factor, scale_factor)), "actual canvas scale matches " + str(dimensions))
		check(root.get_visible_rect().size.is_equal_approx(Vector2(1280, 720)), "logical viewport stays readable at " + str(dimensions))
	root.size = Vector2i(1280, 720)
	var game = load("res://Scenes/Game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	check(game._play_btn.custom_minimum_size.y >= 40, "play button retains a 40px logical hit area")
	check(game._end_play_btn.custom_minimum_size.y >= 40, "end-phase button retains a 40px logical hit area")
	check(game._confirm_target_btn.custom_minimum_size.y >= 40, "multi-target confirmation retains a 40px logical hit area")
	check(game._play_btn.get_theme_font_size("font_size") >= 18, "default action text is at least 18px")
	game.queue_free()
	await process_frame
	print("RESULT: %d asserts, %d failures" % [checks, failures])
	quit(1 if failures else 0)
