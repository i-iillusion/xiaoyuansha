extends "res://Test/terminal_boundary_cases.gd"

# G02d-b: real placement/judgment, Q2 center-chain completion and Q4 snapshot.
func judge(suite, game, granted: bool):
	if granted:
		var a = game.players[0]
		a.general_name = "麦克斯·欧尼斯特"
		a.hand.append(null)
		game.turn_manager.current_player_idx = 0
		game.turn_manager.current_phase = TurnManager.Phase.START
		game._meiyong_override = func(): return true
		game._meiyong_option_override = func(): return 0
		game._meiyong_target_override = func(): return game.players[1]
		suite.check(await game._maybe_meiyong(a) == 1 and game.turn_manager.current_phase == TurnManager.Phase.START, "G02d-b gifted judgment restores suspended source START")
	else:
		game.turn_manager.current_player_idx = 1
		game.turn_manager.current_phase = TurnManager.Phase.JUDGE
		await game._do_judge(1)
		suite.check(game.turn_manager.current_phase == TurnManager.Phase.DRAW, "G02d-b normal judgment advances to DRAW")

func run(suite):
	var previous = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general,
		GameManager.random_general, GameManager.random_identity]
	for concrete in [false, true]:
		for granted in [false, true]:
			for d_dies in [false, true]:
				var game = await new_game(suite, 5)
				for p in game.players: p.hp = 4
				var a = game.players[0]
				var b = game.players[1]
				var c = game.players[2]
				var d = game.players[3]
				var e = game.players[4]
				b.chained = true
				c.chained = true
				c.hp = 1
				d.hp = 1 if d_dies else 4
				var original: CardBase = CardBase.create(CardData.CardSubType.BURNING_CAMP) if concrete else null
				if concrete: a.determined_cards.append(original)
				else: a.hand.append(null)
				await game.execute_card_on_target(b, CardData.CardSubType.BURNING_CAMP)
				var placed = b.judgment_cards[0]
				suite.check((not concrete or placed == original) and c.is_alive() and b.hp == 4 and game.deck._discard.is_empty(), "G02d-b paid original waits; no damage before actual judgment")
				await judge(suite, game, granted)
				suite.check(c.is_dead() and b.hp == 3 and a.hp == 3 and e.hp == 4 and not game._game_over, "G02d-Q2 center chain completes before choosing living A/D neighbors")
				suite.check((d.is_dead() if d_dies else d.hp == 3) and e.judgment_cards.is_empty() and c.judgment_cards.is_empty(), "G02d-Q4 later dead D is not replaced with E for propagation")
				suite.check(a.judgment_cards.size() == 1 and d.judgment_cards.size() == (0 if d_dies else 1) and b.judgment_cards.is_empty(), "G02d-b only surviving selected neighbors receive waiting fire cards")
				suite.check(a.judgment_cards[0] != placed and a.judgment_cards[0].source_seat == 0 and game.deck._discard.count(placed) == 1 and a.hand_size() == (2 if granted else 0), "G02d-b original discarded once; new cards distinct, no sourced kill reward")
				suite.check(game._dying_contexts.is_empty() and game._choice_prompt_stack.is_empty() and game._pending_card_actions.is_empty(), "G02d-b completed chain has no leaked window/action/dying owner")
				game.queue_free()
				await suite.process_frame
	# Source finally dies before judgment: original metadata remains, damage stays unsourced.
	var game = await new_game(suite, 5)
	for p in game.players: p.hp = 4
	game.turn_manager.current_player_idx = 2
	game.players[2].hand.append(null)
	await game.execute_card_on_target(game.players[1], CardData.CardSubType.BURNING_CAMP)
	var original = game.players[1].judgment_cards[0]
	await game._deal_damage_result(null, game.players[2], 4, EffectChain.DamageType.PHYSICAL)
	suite.check(game.players[2].is_dead() and not game._game_over and game.players[1].judgment_cards == [original], "G02d-b final source death does not remove delayed original")
	await judge(suite, game, false)
	suite.check(game.players[1].hp == 3 and game.players[0].hp == 3 and game.players[3].hp == 3 and game.players[4].hp == 4, "G02d-b source-dead circle skips dead C and uses A/D")
	suite.check(game.players[0].judgment_cards.size() == 1 and game.players[3].judgment_cards.size() == 1 and game.players[3].judgment_cards[0].source_seat == 2 and game.deck._discard.count(original) == 1, "G02d-b source-dead original finishes once and propagates waiting cards")
	game.queue_free()
	await suite.process_frame
	# Center itself finally dies without ending the game; its spatial anchor remains.
	game = await new_game(suite, 5)
	for p in game.players: p.hp = 4
	game.players[1].hp = 1
	game.players[0].hand.append(null)
	await game.execute_card_on_target(game.players[1], CardData.CardSubType.BURNING_CAMP)
	original = game.players[1].judgment_cards[0]
	game.turn_manager.current_player_idx = 1
	game.turn_manager.current_phase = TurnManager.Phase.JUDGE
	await game._do_judge(1)
	suite.check(game.players[1].is_dead() and not game._game_over and game.players[0].hp == 3 and game.players[2].hp == 3, "G02d-b final center death keeps spatial anchor for A/C damage")
	suite.check(game.players[0].judgment_cards.size() == 1 and game.players[2].judgment_cards.size() == 1 and game.deck._discard.count(original) == 1, "G02d-b dead center original discarded once, live selected neighbors wait")
	game.queue_free()
	await suite.process_frame
	# Existing 6.2 target immunity: a kneeling neighbor is not replaced with a farther one.
	game = await new_game(suite, 5, "布鲁斯·萨维奇")
	for p in game.players: p.hp = 4
	game.players[0].hp = 2
	game.turn_manager.current_player_idx = 2
	game.players[2].hand.append(null)
	await game.execute_card_on_target(game.players[1], CardData.CardSubType.BURNING_CAMP)
	original = game.players[1].judgment_cards[0]
	game._kneel_override = func(): return true
	await game._on_kneel_skill_clicked(game.players[0])
	suite.check(game.players[0].kneeling and game.players[0].hand_size() == 0, "G02d-b real out-of-turn wounded empty-hand Bruce legally kneels")
	await judge(suite, game, false)
	suite.check(game.players[0].hp == 2 and game.players[0].judgment_cards.is_empty() and game.players[1].hp == 3 and game.players[2].hp == 3, "G02d-b kneeling neighbor immune to direct fire and new delayed placement")
	suite.check(game.players[4].hp == 4 and game.players[4].judgment_cards.is_empty() and game.deck._discard.count(original) == 1, "G02d-b immunity does not replace selected neighbor with E; original finishes once")
	game.queue_free()
	await suite.process_frame
	# Earlier legal fire on A: no duplicate on propagation or attempted second placement.
	game = await new_game(suite, 5)
	for p in game.players: p.hp = 4
	game.turn_manager.current_player_idx = 4
	game.players[4].hand.append(null)
	await game.execute_card_on_target(game.players[0], CardData.CardSubType.BURNING_CAMP)
	var existing = game.players[0].judgment_cards[0]
	game.turn_manager.current_player_idx = 0
	game.players[0].hand.assign([null, null])
	await game.execute_card_on_target(game.players[1], CardData.CardSubType.BURNING_CAMP)
	original = game.players[1].judgment_cards[0]
	await game.execute_card_on_target(game.players[1], CardData.CardSubType.BURNING_CAMP)
	suite.check(game.players[0].hand_size() == 1 and game.players[1].judgment_cards == [original], "G02d-b same-name fire rejected before payment")
	await judge(suite, game, false)
	suite.check(game.players[0].judgment_cards == [existing] and game.players[0].hp == 3 and game.deck._discard.count(existing) == 0, "G02d-b propagation preserves existing original without duplicate or immediate judgment")
	game.turn_manager.current_player_idx = 0
	game.turn_manager.current_phase = TurnManager.Phase.JUDGE
	await game._do_judge(0)
	suite.check(game.deck._discard.count(existing) == 1 and game.players[0].hp == 2 and game.players[1].hp == 2 and game.players[4].hp == 3, "G02d-b waiting card resolves only at recipient actual judgment")
	game.queue_free()
	await suite.process_frame
	# Real LE + BING + FIRE placement, LIFO normal and gifted exceptions together.
	for granted in [false, true]:
		game = await new_game(suite, 5)
		for p in game.players: p.hp = 4
		game.players[0].hand.assign([null, null, null])
		for sub in [CardData.CardSubType.INDULGENCE, CardData.CardSubType.SUPPLY_SHORTAGE, CardData.CardSubType.BURNING_CAMP]:
			await game.execute_card_on_target(game.players[1], sub)
		var originals = game.players[1].judgment_cards.duplicate()
		suite.check(originals.size() == 3 and game.players[0].hand_size() == 0, "G02d-b different delayed cards coexist after three legal real payments")
		await judge(suite, game, granted)
		var each_once = true
		for card in originals: each_once = each_once and game.deck._discard.count(card) == 1
		suite.check(each_once and game.players[1].judgment_cards.is_empty() and game.players[1].hp == 3, "G02d-b combined judgment consumes originals once; gifted fire still damages")
		suite.check(game.turn_manager.skip_play_phase == not granted and game.turn_manager.supply_shortage_active == not granted, "G02d-b normal LE/BING penalties but no gifted later-stage penalties")
		if not granted:
			await game._do_draw(1)
			suite.check(game.players[1].hand_size() == 1 and game.turn_manager.current_phase == TurnManager.Phase.DISCARD, "G02d-b combined normal BING draws one, LE skips PLAY")
		game.queue_free()
		await suite.process_frame
	# Real human nullification on the real paid delayed original, normal and granted.
	for granted in [false, true]:
		for mode in ["accept", "close", "phase", "reset", "move", "end"]:
			game = await new_game(suite, 5)
			for p in game.players: p.hp = 4
			game.players[0].hand.append(null)
			await game.execute_card_on_target(game.players[1], CardData.CardSubType.BURNING_CAMP)
			original = game.players[1].judgment_cards[0]
			game.players[0].hand.append(null)
			game._nullify_override = Callable()
			game.turn_manager.current_player_idx = 1
			game.turn_manager.current_phase = TurnManager.Phase.JUDGE
			var active_game = game
			var active_card = original
			var active_mode = mode
			var drive = func():
				var pending = active_game._choice_prompt_stack.back()
				match active_mode:
					"close": pending.overlay.queue_free()
					"phase":
						active_game.turn_manager.current_phase = TurnManager.Phase.END
						pending.overlay.find_children("*", "Button", true, false)[0].pressed.emit()
					"reset":
						active_game.reset_game_over_state()
						pending.overlay.queue_free()
					"move":
						active_game.players[1].judgment_cards.erase(active_card)
						active_game.players[2].judgment_cards.append(active_card)
						pending.overlay.find_children("*", "Button", true, false)[0].pressed.emit()
					"end": active_game._finish_game("平局", "G02d-b defensive terminal injection")
					_:
						active_game._nullify_override = func(): return false
						pending.overlay.find_children("*", "Button", true, false)[0].pressed.emit()
			drive.call_deferred()
			var completed = await game._run_judgment(game.players[1], granted)
			suite.check(completed == (mode == "accept") and game.players[0].hp == 4 and game.players[1].hp == 4 and game.players[2].hp == 4, "G02d-b real nullification or technical invalidation never deals fire damage: " + mode)
			suite.check(game.deck._discard.count(original) == (1 if mode == "accept" else 0) and game.players[0].judgment_cards.is_empty() and game.players[4].judgment_cards.is_empty(), "G02d-b nullified original discarded once; invalid original retained/moved, no propagation: " + mode)
			suite.check((game.players[2].judgment_cards == [original] if mode == "move" else game.players[1].judgment_cards.size() == (0 if mode == "accept" else 1)) and game._choice_prompt_stack.is_empty(), "G02d-b stale reply cannot recover moved card; prompt owner cleaned: " + mode)
			game.queue_free()
			await suite.process_frame
	GameManager.selected_players = previous[0]
	GameManager.selected_mode = previous[1]
	GameManager.selected_general = previous[2]
	GameManager.random_general = previous[3]
	GameManager.random_identity = previous[4]
