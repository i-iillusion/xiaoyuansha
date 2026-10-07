# Only intercept the final scene navigation. The real menu builds its controls
# and writes GameManager selection statics; headless tests then start that scene.
extends MainMenu

var launches: Array = []

func _start_game_5p():
	launches.append([GameManager.selected_players, GameManager.selected_mode,
		GameManager.selected_general, GameManager.random_general, GameManager.random_identity])
