# DEV-LAN01/02: actual rule windows, privacy, ownership and replay protection.
extends SceneTree

var checks := 0
var failures := 0
var bridge: LanGameBridge
var answer: Variant = null

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, text: String) -> void:
	checks += 1
	if not value: failures += 1
	print(("PASS " if value else "FAIL ") + text)

func _capture(callback: Callable) -> void:
	answer = await callback.call()

func frames(count: int = 3) -> void:
	for i in count: await process_frame

func _click(seat: int, text: String) -> bool:
	var state = bridge.snapshot(seat)
	for button in state.controls:
		if text in button.text and not button.disabled:
			return bridge.submit(seat, button.id)
	print("MISSING BUTTON ", text, " in ", state.controls)
	return false

func _run() -> void:
	var roster: Array[Dictionary] = []
	for i in 5: roster.append({"name": "P%d" % i, "general": "稻草人"})
	bridge = LanGameBridge.new()
	root.add_child(bridge)
	bridge.start(roster, GameManager.MODE_CLASSIC_IDENTITY)
	await create_timer(0.8).timeout
	var game = bridge.game
	game._halt_countdown()
	for seat in 5:
		var state = bridge.snapshot(seat)
		check(state.actor == seat, "snapshot recipient seat %d" % seat)
		check(state.own_cards.size() == game.players[seat].hand_size(), "only own cards %d" % seat)
		for row in state.players:
			check(row.identity == (game.players[row.seat].identity if row.seat == seat or game.players[row.seat].identity_revealed else ""), "identity privacy %d/%d" % [seat, row.seat])
	# Same real rock-paper-scissors window for every nonzero human seat.
	for seat in range(1, 5):
		answer = null
		_capture(game._rps_choice.bind(game.players[seat], "opponent"))
		await frames()
		var state = bridge.snapshot(seat)
		check(state.owner == seat and not state.controls.is_empty(), "remote RPS owner %d" % seat)
		check(bridge.snapshot(0).controls.is_empty(), "host cannot see remote RPS controls")
		var token = state.controls[0].id
		check(not bridge.submit(0, token), "forged seat rejected")
		check(bridge.submit(seat, token), "remote RPS accepted")
		check(not bridge.submit(seat, token), "RPS replay rejected")
		await frames()
		check(answer != null and int(answer) >= 0, "remote RPS completed")
	# Forced discard exposes checkbox state only to the payer, not the target/host.
	answer = null
	var before = game.players[2].hand_size()
	_capture(game._select_hand_discard_result.bind(game.players[2], 1, true))
	await frames()
	var discard = bridge.snapshot(2)
	check(discard.owner == 2, "forced discard owner")
	var selected = false
	for button in discard.controls:
		if button.toggle:
			selected = bridge.submit(2, button.id)
			break
	check(selected, "remote checkbox can be selected")
	await frames()
	check(_click(2, "确认"), "remote mandatory confirm")
	await frames()
	check(answer == GameManager.HandDiscardOutcome.PAID and game.players[2].hand_size() == before - 1, "discard pays exactly one")
	# Each player's reserve is independent; changing views must not mint time.
	game._select_time_bank(1)
	game._bank_remaining = 7.0
	game._select_time_bank(2)
	check(game._bank_remaining == game.BANK_SECONDS, "new seat full reserve")
	game._bank_remaining = 3.0
	game._select_time_bank(1)
	check(game._bank_remaining == 7.0, "seat reserve restored")
	# Nested response windows keep their own actor and remaining step time.
	_capture(game._rps_choice.bind(game.players[1], "outer"))
	await frames()
	game._step_remaining = 11.0
	_capture(game._rps_choice.bind(game.players[3], "inner"))
	await frames()
	check(bridge.input_owner() == 3, "nested response belongs to inner remote seat")
	check(bridge.submit(3, bridge.snapshot(3).controls[0].id), "inner response resolves")
	await frames()
	check(bridge.input_owner() == 1, "outer remote response resumes")
	check(game._step_remaining <= 11.0 and game._step_remaining > 9.0, "outer timer budget preserved")
	check(bridge.submit(1, bridge.snapshot(1).controls[0].id), "outer response resolves")
	await frames()
	# Rescue selection must go to the rescuer, not the dying role or room host.
	var dying = game.players[4]
	dying.hp = 0
	dying.life_state = Player.LifeState.DYING
	var options: Array[int] = [CardData.CardSubType.PEACH]
	_capture(game._ask_rescue_card_pending.bind(game.players[2], dying, options, func(): return true))
	await frames()
	check(bridge.input_owner() == 2, "rescue belongs to remote rescuer")
	check(bridge.snapshot(4).controls.is_empty(), "dying player cannot answer another rescuer's prompt")
	check(_click(2, "放弃"), "remote rescuer can decline")
	await frames()
	check(answer == -1, "decline keeps existing rescue meaning")
	dying.hp = dying.max_hp
	dying.life_state = Player.LifeState.ACTIVE
	# Viewing another player's skill description never grants control of it.
	game.players[2].general_name = "安普提·斯丢皮得"
	var hidden = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
	hidden.hidden_category = "weapon"
	game.players[2].equip_hidden_card_to_slot("weapon", hidden)
	game._set_input_player(game.players[1])
	game._on_detail_skill_clicked("苕", game.players[2])
	game._on_sao_skill_clicked(game.players[2])
	await frames()
	check(game._choice_prompt_stack.is_empty(), "another human cannot open owner's hidden equipment declaration")
	check(game.players[2].get_hidden_equipment_card("weapon") == hidden, "unauthorized skill does not change equipment")
	game.players[2].general_name = "稻草人"
	# Real CardSelector and normal action controls remain available for seat 1.
	game.turn_manager.current_player_idx = 1
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game._do_play(1)
	await frames()
	check(bridge.input_owner() == 1, "nonzero play actor receives controls, not AI")
	var grant = game.turn_manager.begin_standalone_play(3)
	game._do_play(3)
	await frames()
	check(bridge.input_owner() == 3 and not bridge.snapshot(3).controls.is_empty(), "granted play belongs to its remote actor")
	check(bridge.snapshot(1).controls.is_empty(), "turn owner cannot operate gifted play")
	game.turn_manager.cancel_standalone_play(grant)
	game._do_play(1)
	await frames()
	check(_click(1, "出牌"), "remote opens actual selector")
	await frames()
	check(_click(1, "基本牌"), "remote card categories")
	await frames()
	check(not bridge.snapshot(1).controls.is_empty(), "remote basic card choices")
	check(bridge.snapshot(0).controls.is_empty(), "selector private to owner")
	game.players[1].judgment_cards.append(CardBase.create(CardData.CardSubType.INDULGENCE))
	var rendered_state = bridge.snapshot(1)
	_capture(game._rps_choice.bind(game.players[3], "disconnect"))
	await frames()
	bridge.abort()
	await frames(5)
	# Build actual front-end scene too; import success alone does not run _ready.
	var room = load("res://Scenes/LanRoom.tscn").instantiate()
	root.add_child(room)
	await frames()
	check(room.session != null and room.body.get_child_count() > 0, "LAN room renders connection form")
	room._state_changed(rendered_state)
	await frames()
	check(room._screen == "game" and room.body.get_child_count() > 5, "LAN frontend renders actual five-seat game state")
	var board = room.body.get_child(2)
	check(board is GridContainer and "乐不思蜀" in board.get_child(1).text, "public judgment visible on remote board")
	room.queue_free()
	await frames(5)
	print("RESULT: %d asserts, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
