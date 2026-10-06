extends RefCounted

func run(suite):
	var sub = CardData.CardSubType.BORROWED_SWORD
	var card = CardBase.create(sub)
	suite.check(sub == CardData.CardSubType.HIDDEN_EQUIPMENT + 1 and CardData.CardSubType.STRIKE == 0 and CardData.CardSubType.DUEL == 8 and CardData.CardSubType.DISARM == 12, "F02b-3b-2a borrowed appended without shifting old enum IDs")
	suite.check(card.sub_type == sub and card.card_name == "借刀杀人" and CardData.CARD_TYPE_MAP[sub] == CardData.CardType.STRATAGEM and card.description == CardData.CARD_DESCRIPTIONS[sub], "F02b-3b-2a original borrowed entity metadata")
	suite.check(not CardData.get_playable_sub_types().has(sub) and not suite.game.TARGET_TRICKS.has(sub), "F02b-3b-2a incomplete borrowed runtime not advertised")
	var tm = TurnManager.new()
	tm.player_count = 5
	tm.debug_log = false
	tm.start_game()
	var original_turn = tm.turn_id
	tm.current_phase = TurnManager.Phase.PLAY
	for actor in [0, 1, 2]:
		tm.play_actor_idx = actor
		suite.check(tm.borrowed_sword_count_this_turn == 0 and tm.can_use("borrowed_sword"), "F02b-3b-2a borrowed card quota belongs to actual user")
		tm.use_strike()
		for n in range(2):
			suite.check(tm.borrowed_sword_count_this_turn == n and tm.can_use("borrowed_sword"), "F02b-3b-2a first and second borrowed card allowed")
			tm.use_card("borrowed_sword")
			suite.check(tm.borrowed_sword_count_this_turn == n + 1 and tm.strikes_used() == 1 and tm.duel_count_this_turn == 0, "F02b-3b-2a borrowed card not normal strike or duel quota")
		suite.check(not tm.can_use("borrowed_sword") and tm.borrowed_sword_count_this_turn == 2, "F02b-3b-2a third borrowed card blocked")
	tm.play_actor_idx = 0
	tm.start_waiting("strike", 2)
	tm.end_waiting()
	suite.check(tm.borrowed_sword_count_this_turn == 2 and not tm.can_use("borrowed_sword") and tm.turn_id == original_turn, "F02b-3b-2a WAITING retains card quota")
	tm._change_phase(TurnManager.Phase.DRAW)
	tm._change_phase(TurnManager.Phase.PLAY)
	suite.check(tm.borrowed_sword_count_this_turn == 2 and not tm.can_use("borrowed_sword"), "F02b-3b-2a phase changes do not reset quota")
	tm.current_phase = TurnManager.Phase.START
	var frame = tm.begin_standalone_play(1)
	suite.check(not frame.is_empty() and tm.borrowed_sword_count_this_turn == 2 and tm.turn_id == original_turn, "F02b-3b-2a standalone play reads gifted user's existing quota")
	tm.complete_standalone_phase(frame)
	suite.check(tm._get_turn_count("borrowed_sword", 0) == 2 and tm._get_turn_count("borrowed_sword", 1) == 2, "F02b-3b-2a return from gift preserves both users' quota")
	tm.next_turn()
	suite.check(tm.turn_id == original_turn + 1 and tm.current_player_idx == 1 and tm.borrowed_sword_count_this_turn == 0 and tm.can_use("borrowed_sword") and tm.strikes_used() == 0, "F02b-3b-2a actual next turn resets card histories")
	for actor in [0, 1, 2]: suite.check(tm._get_turn_count("borrowed_sword", actor) == 0, "F02b-3b-2a next turn resets every user's borrowed quota")
	tm.use_card("borrowed_sword")
	tm.start_game()
	suite.check(tm.borrowed_sword_count_this_turn == 0 and tm.current_player_idx == 0 and tm.can_use("borrowed_sword"), "F02b-3b-2a restart clears card quota")
	tm.free()
