extends RefCounted

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	for skill in ["zhuangbi", "campus", "exchange"]:
		for mode in ["hidden", "shown", "remove"]:
			await check_skill(t, skill, mode)
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]

func check_skill(t, skill: String, mode: String):
	var game = load("res://Test/i03_egg_cases.gd").new().fixture(t)
	game.lan_enabled = true
	game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
	var owner: Player = game.players[0]
	var actor: Player = game.players[1]
	var dragon = load("res://Test/i03_summon_cases.gd").new().seed_dragon(game, owner)
	var id = game.unit_registry.id_for(dragon)
	for p in game.players: p.hand.clear()
	actor.general_name = {"zhuangbi": "史蒂芬·彼特先斯", "campus": "杰基·斯特朗", "exchange": "麦克斯·欧尼斯特"}[skill]
	actor.hand.assign([null, null])
	dragon.hand.append(null)
	game.turn_manager.current_player_idx = 1
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game._set_input_player(actor)
	game._rps_override = func(body): return 0 if body == actor else 2
	game._zhuangbi_again_override = func(): return false
	game._sacrifice_override = func(): return false
	game._rescue_choice_override = func(_r, _d, _o): return -1
	var paid: Array = []
	game._hand_discard_override = func(snapshot, count, mandatory):
		paid.append([snapshot.owner, count, mandatory])
		if mode == "remove":
			owner.mark_dead() # Defensive invalidation during a real cost window.
			game._remove_summoner_units(owner)
		return snapshot.defaults(count)
	if mode != "hidden":
		var shown: Array[Player] = [actor]
		game.fire_dragon_state.record_use(id, 1, shown)
	var original: CardBase
	if skill == "exchange":
		original = CardBase.create(CardData.CardSubType.LIANNU)
		dragon.equip_card_to_slot("weapon", original)
		var zones: Array = ["weapon", "done"]
		game._lanzhonghou_zone_override = func(): return zones.pop_front()
		game._on_lanzhonghou_skill_clicked(actor)
		await game._on_lanzhonghou_target_click(dragon)
		if mode != "hidden": await game._on_lanzhonghou_target_click(actor)
	elif skill == "zhuangbi":
		game._on_zhuangbi_skill_clicked(actor)
		game._on_zhuangbi_target_click(dragon)
		if mode == "hidden":
			t.check(not game._zhuangbi_targets.has(dragon), "I03 hidden dragon cannot be selected for Zhuangbi")
			var targets: Array[Player] = [dragon]
			await game._execute_zhuangbi(targets)
		else: await game._on_confirm_zhuangbi()
	else:
		game._on_campus_skill_clicked(actor)
		await game._on_campus_target_click(dragon)
		if mode == "hidden": await game._execute_campus_dominator(actor, dragon)
	if mode == "hidden":
		t.check(paid.is_empty() and actor.hand_size() == 2 and dragon.hand_size() == 1 and dragon.hp == 3,
			"I03 hidden unit target cannot start skill payment/effect: " + skill)
		if skill == "exchange":
			t.check(not game._lanzhonghou_selected.has(dragon), "I03 hidden dragon cannot enter exchange selection")
			await game._run_lanzhonghou(actor, dragon)
			t.check(paid.is_empty() and dragon.get_equipment_card("weapon") == original, "I03 direct exchange also rejects hidden unit before cost")
	elif mode == "remove":
		t.check(actor.hand_size() == 2 and not game._lanzhonghou_used and dragon.sage_tokens == 0,
			"I03 removed target invalidates real skill cost before committing: " + skill)
	else:
		if skill == "exchange":
			t.check(paid == [[actor, 1, false]] and actor.get_equipment_card("weapon") == original and dragon.get_equipment_card("weapon") == null and game._lanzhonghou_used,
				"I03 actual exchange moves original unit equipment into empty fixed-player slot with one cost")
		else:
			t.check(paid == [[actor, 1, true], [dragon, 1, true]] and actor.hand_size() == 1 and dragon.hand_size() == 0 and dragon.hp == 2,
				"I03 actual skill includes visible unit, both mandatory costs and one RPS damage: " + skill)
		t.check(game.unit_registry.zhuangsha_count_participants().size() == 5 and game.unit_registry.science_count_participants().size() == 5,
			"I03 targetable unit never changes fixed count-only participant queries")
	game._game_over = true
	game.queue_free()
	await t.process_frame
