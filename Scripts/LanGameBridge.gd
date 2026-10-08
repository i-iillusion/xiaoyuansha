class_name LanGameBridge
extends Node

# Server-only adapter. Actual rule windows remain the source of available input.
# Wire messages contain values and opaque action IDs, never Nodes or Callables.
var game: GameManager
var viewport: SubViewport
var winner := ""
var _epoch := 0
var _signature := ""
var _commands: Dictionary = {}
var _controls: Array = []
var _labels: Array = []

func start(roster: Array[Dictionary], mode: String) -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	game = preload("res://Scenes/Game.tscn").instantiate()
	game.auto_start = false
	game.lan_enabled = true
	game.lan_roster = roster.duplicate(true)
	var old_count = GameManager.selected_players
	var old_mode = GameManager.selected_mode
	GameManager.selected_players = roster.size()
	GameManager.selected_mode = mode
	viewport.add_child(game)
	GameManager.selected_players = old_count
	GameManager.selected_mode = old_mode
	game.game_over.connect(func(result): winner = result)
	game.start_game()

func input_owner() -> int:
	if game == null or game._game_over: return -1
	if not game._choice_prompt_stack.is_empty():
		return int(game._choice_prompt_stack.back().seat)
	return game._input_seat

func _root() -> Node:
	if not game._choice_prompt_stack.is_empty():
		return game._choice_prompt_stack.back().overlay
	for child in game.get_node("UI").get_children():
		if child is CardSelector and not child.is_queued_for_deletion(): return child
	if game._detail_popup_root.visible:
		for child in game._detail_popup_root.get_children():
			if not child.is_queued_for_deletion(): return child
	return null

func _walk(node: Node, buttons: Array, labels: Array) -> void:
	if node.is_queued_for_deletion(): return
	if node is Control and not node.is_visible_in_tree(): return
	if node is BaseButton:
		buttons.append(node)
	elif node is Label and not node.text.is_empty():
		labels.append(node.text)
	for child in node.get_children(): _walk(child, buttons, labels)

func _targeting() -> bool:
	return game._is_targeting or game._is_multi_targeting or game._is_iron_chain_targeting \
		or game._is_zhuangbi_targeting or game._is_campus_targeting or game._is_gay_targeting \
		or game._is_shensu_targeting or game._is_lanzhonghou_targeting or game._is_meiyong_targeting \
		or game._is_sage_targeting

func _refresh_commands() -> void:
	var buttons: Array = []
	var labels: Array = []
	var root = _root()
	if root != null:
		_walk(root, buttons, labels)
	else:
		for button in [game._play_btn, game._end_play_btn, game._cancel_target_btn, game._confirm_target_btn]:
			if is_instance_valid(button) and button.is_visible_in_tree(): buttons.append(button)
	# Timing text deliberately excluded: a ticking clock must not expire a click.
	var shape: Array = [input_owner(), game.turn_manager.get_context_revision(),
		root.get_instance_id() if root != null else 0, _targeting(), game._game_over]
	var selector_busy = root is CardSelector and root._confirm_pending
	shape.append(selector_busy)
	for button in buttons:
		shape.append([button.get_instance_id(), button.text, button.disabled, button.button_pressed])
	shape.append(labels)
	for p in game.players:
		shape.append([p.hp, p.hand_size(), p.kneeling, p.kneel_used, p.is_dead()])
	var signature = var_to_str(shape)
	if signature == _signature: return
	_signature = signature
	_epoch += 1
	_commands.clear()
	_controls.clear()
	_labels = labels
	var owner = input_owner()
	if owner < 0: return
	for button in buttons:
		var token = _add_command(owner, "button", weakref(button))
		_controls.append({"id": token, "text": button.text, "disabled": button.disabled or selector_busy,
			"toggle": button.toggle_mode, "pressed": button.button_pressed, "hint": button.tooltip_text})
	if root == null or game._is_meiyong_targeting:
		for p in game.players:
			_add_command(owner, "target", p.seat_index)
	# Out-of-turn 下跪 is not an AI decision. It gets a separate, owner-only input.
	for p in game.players:
		if p.general_name == "布鲁斯·萨维奇" and p.is_alive() and (p.kneeling or game._kneel_conditions_met(p)):
			_add_command(p.seat_index, "kneel", p.seat_index)

func _add_command(seat: int, kind: String, value: Variant) -> String:
	var token = "%d:%d" % [_epoch, _commands.size()]
	_commands[token] = {"seat": seat, "kind": kind, "value": value}
	return token

func snapshot(seat: int) -> Dictionary:
	_refresh_commands()
	var p: Player = game.players[seat]
	var state = PlayerObservation.capture(game.players, p, game.turn_manager.current_phase,
		game.turn_manager.get_context_revision())
	state["owner"] = input_owner()
	state["turn"] = game.turn_manager.get_play_actor_idx()
	state["winner"] = winner
	state["ended"] = game._game_over
	state["targeting"] = _targeting()
	state["controls"] = _controls.duplicate(true) if seat == input_owner() else []
	state["labels"] = _labels.duplicate() if seat == input_owner() else []
	state["status"] = game._debug_label.text if seat == input_owner() else "等待其他玩家操作"
	state["clock"] = game._countdown_label.text
	state["notice"] = game._log_label.text if seat == input_owner() else ""
	state["targets"] = {}
	state["kneel"] = ""
	for token in _commands:
		var command: Dictionary = _commands[token]
		if command.seat != seat: continue
		if command.kind == "target": state.targets[str(command.value)] = token
		if command.kind == "kneel": state.kneel = token
	for row in state.players:
		var subject: Player = game.players[row.seat]
		row["name"] = subject.player_name
		row["kneeling"] = subject.kneeling
		row["prep"] = subject.prep_tokens
		row["wine"] = subject.wine_stacks
	return state

func submit(seat: int, token: String) -> bool:
	if game == null or game._game_over: return false
	var current_root = _root()
	if current_root is CardSelector and current_root._confirm_pending: return false
	_refresh_commands() # Revalidate against the live window, not the last sent view.
	if not _commands.has(token): return false
	var command: Dictionary = _commands[token]
	if int(command.seat) != seat: return false
	if command.kind != "kneel" and seat != input_owner(): return false
	# Consume the whole view before invoking callbacks (including synchronous ones).
	_commands.clear()
	_signature = ""
	game._set_input_player(game.players[seat])
	match command.kind:
		"button":
			var button = command.value.get_ref()
			if button == null or button.is_queued_for_deletion() or button.disabled or not button.is_visible_in_tree(): return false
			if button.toggle_mode: button.button_pressed = not button.button_pressed
			button.pressed.emit()
		"target":
			var panel = Control.new()
			panel.set_meta("player", game.players[int(command.value)])
			var event = InputEventMouseButton.new()
			event.pressed = true
			event.button_index = MOUSE_BUTTON_LEFT
			game._on_player_panel_click(event, panel)
			panel.free()
		"kneel":
			game._on_kneel_skill_clicked(game.players[seat])
	return true

func abort() -> void:
	# Technical interruption is not a game result. Prevent further phase advancement.
	if game != null:
		game._game_over = true
		game._halt_countdown()
	_commands.clear()
	queue_free()
