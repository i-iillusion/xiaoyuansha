extends RefCounted

func run(suite):
	var game: GameManager = suite.game
	var actor: Player = game.players[0]
	var original_identity = actor.identity
	var original_revealed = actor.identity_revealed
	var original_bonus = actor.identity_max_hp_bonus
	var old_history = [game._gay_used, game._lanzhonghou_used, game._zhuangbi_blocked_this_phase,
		game.turn_manager.duel_count_this_turn, game.turn_manager.granted_play_target_idx]
	var generals = ["比尔·盖伊", "凯文·罗本", "布鲁斯·萨维奇", "安普提·斯丢皮得",
		"史蒂芬·彼特先斯", "杰基·斯特朗", "麦克斯·欧尼斯特"]
	for general in generals:
		for initially_lord in [false, true]:
			suite.reset_players()
			actor.identity_max_hp_bonus = 0
			actor.general_name = general
			actor.gender = "male"
			actor.max_hp = GeneralData.get_max_hp(general)
			actor.identity = "主公" if initially_lord else "忠臣"
			actor.identity_max_hp_bonus = 1 if initially_lord else 0
			actor.awoken = false
			actor.awake_choice = 0
			actor.kneeling = false
			actor.kneel_used = false
			actor.facedown = false
			actor.shensu_penalty = 0
			actor.shensu_used_this_turn = false
			actor.capture_game_start_state()
			# H03尚未开放身份交换：这里注入交换后的身份层，验证贤者不会回滚它。
			actor.identity = "反贼" if initially_lord else "主公"
			actor.identity_revealed = true
			actor.hp = 1
			actor.identity_max_hp_bonus = 0 if initially_lord else 1
			suite.check(actor.hp == 1, "E01b：身份上限层调整本身不隐含回血")
			actor.max_hp -= 1
			actor.gender = "female"
			actor.awoken = true
			actor.awake_choice = 2
			actor.kneeling = true
			actor.kneel_used = true
			actor.facedown = true
			actor.shensu_penalty = 3
			actor.shensu_used_this_turn = true
			var physical = [CardBase.create(CardData.CardSubType.STRIKE),
				CardBase.create(CardData.CardSubType.PEACH),
				CardBase.create(CardData.CardSubType.SAGE_PROTECTION),
				CardBase.create(CardData.CardSubType.LIGHTNING)]
			actor.hand.append(physical[0])
			actor.determined_cards.append(physical[1])
			actor.equip_card_to_slot("armor", physical[2])
			actor.judgment_cards.append(physical[3])
			actor.sage_activated = true
			actor.hp = 0
			var other: Player = game.players[1]
			other.shensu_penalty = 7
			game._gay_used = true
			game._lanzhonghou_used = true
			game._zhuangbi_blocked_this_phase = true
			game.turn_manager.duel_count_this_turn = 2
			game.turn_manager.granted_play_target_idx = 1
			var discarded_before = game.deck.discard_count()
			game._do_sage_save(actor)
			var expected_hp = GeneralData.get_max_hp(general) + (0 if initially_lord else 1)
			suite.check(actor.max_hp == expected_hp and actor.hp == expected_hp
				and actor.is_alive(), "E01b：贤者恢复基础上限并保留当前身份加成：" + general)
			suite.check(actor.identity == ("反贼" if initially_lord else "主公")
				and actor.identity_revealed, "E01b：不恢复旧身份或公开状态")
			suite.check(actor.general_name == general and actor.gender == "male"
				and not actor.awoken and actor.awake_choice == 0 and not actor.kneeling
				and not actor.kneel_used and not actor.facedown and actor.shensu_penalty == 0
				and not actor.shensu_used_this_turn, "E01b：七将自身登记字段完整恢复")
			var exact_discard = game.deck.discard_count() == discarded_before + 4
			for card in physical:
				exact_discard = exact_discard and game.deck._discard.count(card) == 1
			suite.check(exact_discard and actor.hand == [null, null, null, null]
				and actor.determined_cards.is_empty() and actor.equipment.is_empty()
				and actor.judgment_cards.is_empty(), "E01b：仅弃自身四张原牌再摸四张任意牌")
			suite.check(other.shensu_penalty == 7 and game._gay_used and game._lanzhonghou_used
				and game._zhuangbi_blocked_this_phase and game.turn_manager.duel_count_this_turn == 2
				and game.turn_manager.granted_play_target_idx == 1,
				"E01b：复原不回滚其他角色、已发生次数及已授予阶段")
	actor.identity = original_identity
	actor.identity_revealed = original_revealed
	actor.identity_max_hp_bonus = original_bonus
	actor.shensu_penalty = 0
	game.players[1].shensu_penalty = 0
	game._gay_used = old_history[0]
	game._lanzhonghou_used = old_history[1]
	game._zhuangbi_blocked_this_phase = old_history[2]
	game.turn_manager.duel_count_this_turn = old_history[3]
	game.turn_manager.granted_play_target_idx = old_history[4]
	suite.reset_players()
