extends RefCounted

var replies: Array = []

func launch(game: GameManager, kind: String):
	var result: Variant
	if kind == "mandatory":
		result = await game._select_hand_discard_result(game.players[0], 1, true)
	elif kind == "basic":
		result = await game._ask_basic_card_response_result(game.players[0], CardData.CardSubType.DODGE,
			game._show_dodge_prompt.bind("玩家2", "杀"))
	else:
		result = await game._show_kneel_confirm("G01 no-countdown lifecycle", "发动", "放弃")
	replies.append([kind, result])

func run(suite):
	var previous = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general,
		GameManager.random_general, GameManager.random_identity]
	var factory = load("res://Test/terminal_boundary_cases.gd").new()
	for kind in ["mandatory", "basic", "choice"]:
		for concrete in [false, true]:
			var game = await factory.new_game(suite, 2)
			var a = game.players[0]
			var b = game.players[1]
			var card: CardBase = CardBase.create(CardData.CardSubType.DODGE) if concrete else null
			if concrete: a.determined_cards.append(card)
			else: a.hand.append(null)
			b.hp = 1
			replies.clear()
			launch(game, kind)
			suite.check(game._choice_prompt_stack.size() == 1 and replies.is_empty(), "G01c actual window is awaiting owned choice: " + kind)
			var pending = game._choice_prompt_stack.back()
			var overlay: Control = pending.overlay
			var old_timeout: Callable = game._countdown_on_timeout
			var old_click: Callable
			if kind == "mandatory":
				old_click = overlay.timeout
			else:
				var button = overlay.find_children("*", "Button", true, false)[0]
				old_click = button.get_signal_connection_list("pressed")[0].callable
			# Defensive overlap, NOT a legal second player action during a prompt.
			# It exercises the real terminal notification against an active window.
			await game._deal_damage_result(a, b, 1, EffectChain.DamageType.PHYSICAL)
			var expected = GameManager.HandDiscardOutcome.GAME_ENDED if kind == "mandatory" else (
				GameManager.BasicResponseOutcome.INVALIDATED if kind == "basic" else GameManager.CHOICE_INVALID)
			suite.check(replies == [[kind, expected]] and game._choice_prompt_stack.is_empty(), "G01c terminal invalidates UI, not voluntary refusal or mandatory payment")
			await suite.process_frame
			suite.check(not is_instance_valid(overlay) and not game._countdown_active and not game._countdown_on_timeout.is_valid(), "G01c ended prompt destroyed, no old countdown restoration")
			suite.check(a.hand_size() == 1 and game.deck._discard.is_empty(), "G01c pending voluntary/mandatory resource never paid at terminal")
			var revision = game.turn_manager.get_context_revision()
			game._on_cancel_target_pressed()
			game._on_end_play_pressed()
			game._on_play_btn_pressed()
			await game.execute_card_on_target(b, CardData.CardSubType.STRIKE)
			await game.execute_multi_strike([b] as Array[Player], CardData.CardSubType.STRIKE)
			await game.play_card(CardData.CardSubType.WINE)
			await game._on_selector_confirmed(CardData.CardSubType.WINE)
			if concrete: await game._on_determined_card_clicked(card)
			if kind != "mandatory": old_click.call()
			if old_timeout.is_valid(): old_timeout.call()
			suite.check(a.hand_size() == 1 and game.deck._discard.is_empty() and game.turn_manager.get_context_revision() == revision
				and game._pending_determined_card == null and not game._play_btn.visible and not game._end_play_btn.visible and not game._cancel_target_btn.visible and not game._confirm_target_btn.visible, "G01c stale action/UI callbacks after victory cannot pay, advance or reopen controls")
			# Reset is only a lifecycle fixture here, not G03 menu/restart acceptance.
			game.reset_game_over_state()
			for p in game.players: p.hp = p.max_hp
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
			replies.clear()
			launch(game, "choice")
			if kind != "mandatory": old_click.call()
			if old_timeout.is_valid(): old_timeout.call()
			suite.check(replies.is_empty() and game._choice_prompt_stack.size() == 1, "G01c old terminal callbacks cannot answer next legitimate window")
			game._choice_prompt_stack.back().answer.submit(0)
			await suite.process_frame
			suite.check(replies == [["choice", 0]] and game._choice_prompt_stack.is_empty(), "G01c next window finishes independently after old terminal owners released")
			game.queue_free()
			await suite.process_frame
	# The ordinary card selector owns signals but is not an awaited choice stack.
	for concrete in [false, true]:
		var game = await factory.new_game(suite, 2)
		var a = game.players[0]
		var b = game.players[1]
		var card: CardBase = CardBase.create(CardData.CardSubType.WINE) if concrete else null
		if concrete: a.determined_cards.append(card)
		else: a.hand.append(null)
		b.hp = 1
		game._on_play_btn_pressed()
		var selector: CardSelector
		for child in game.get_node("UI").get_children():
			if child is CardSelector: selector = child
		suite.check(is_instance_valid(selector) and selector.player == a and game._choice_prompt_stack.is_empty(), "G01c actual ordinary card selector has separate owner")
		var stale_confirm: Callable = selector.get_signal_connection_list("confirmed")[0].callable
		await game._deal_damage_result(a, b, 1, EffectChain.DamageType.PHYSICAL)
		await suite.process_frame
		suite.check(not is_instance_valid(selector), "G01c terminal destroys ordinary card selector, not only awaited prompts")
		stale_confirm.call(CardData.CardSubType.WINE)
		suite.check(a.hand_size() == 1 and game.deck._discard.is_empty() and game._pending_determined_card == null, "G01c stale card selector confirmation cannot consume original arbitrary/concrete card")
		game.queue_free()
		await suite.process_frame
	GameManager.selected_players = previous[0]
	GameManager.selected_mode = previous[1]
	GameManager.selected_general = previous[2]
	GameManager.random_general = previous[3]
	GameManager.random_identity = previous[4]
