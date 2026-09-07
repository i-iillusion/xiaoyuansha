# test_size.gd — temp: compare window size vs viewport size (delete after)
extends SceneTree

func _initialize():
	await process_frame
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	await process_frame
	DisplayServer.window_set_size(Vector2i(800, 500))
	await process_frame
	print("WIN=", DisplayServer.window_get_size())
	print("VP_RECT=", root.get_visible_rect().size)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await process_frame
	print("WIN2=", DisplayServer.window_get_size())
	print("VP2=", root.get_visible_rect().size)
	quit()
