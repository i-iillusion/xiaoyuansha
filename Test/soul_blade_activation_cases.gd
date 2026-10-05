extends RefCounted

var suite
var game: GameManager
var asks := 0
var punches := 0

func reset():
	suite.reset_players()
	game.deck._discard.clear()
	game.equipment_pool.clear()
	game._clear_pending_determined_card()
	game._soul_blade_activate_override = Callable()
	game._soul_blade_discard_override = Callable()
	game._kaiwen_override = Callable()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game.turn_manager.play_actor_idx = 0
	asks = 0
	punches = 0
	game._rps_override = func(p):
		punches += 1
		return GameManager.RPS_ROCK if p.seat_index == 0 else GameManager.RPS_SCISSORS
	for p in game.players:
		p.facedown = false
		p.hidden_equip_slot = ""
		p.hidden_equip_card = null

func kill(source: Player, victim: Player, concrete: bool, remaining: int = 0):
	game.turn_manager._reset_turn_counts()
	var card = CardBase.create(CardData.CardSubType.STRIKE) if concrete else null
	if concrete:
		source.determined_cards.append(card)
		game._pending_determined_card = card
	else: source.hand.append(null)
	source.wine_stacks = 1
	await game.execute_card_on_target(victim, CardData.CardSubType.STRIKE)
	suite.check(source.hand_size() == remaining and (not concrete or game.deck._discard.count(card) == 1), "E03e-14d：每次真实酒杀原费用仅付一次，流转原刀不误当杀费")

func drive(action: String, source: Player, victim: Player):
	asks += 1
	var pending = game._choice_prompt_stack.back()
	var buttons = pending.overlay.find_children("*", "Button", true, false)
	suite.check(buttons.size() == 2 and not game._countdown_active, "E03e-14d：已激活每点确认独立且保持无计时")
	if asks == 2:
		match action:
			"close":
				pending.overlay.queue_free()
				return
			"phase":
				game.turn_manager.current_phase = TurnManager.Phase.END
				game.turn_manager.current_phase = TurnManager.Phase.PLAY
			"weapon":
				source.determined_cards.append(source.remove_equipment("weapon"))
				var next = CardBase.create(CardData.CardSubType.SOUL_BLADE)
				next.soul_blade_activated = true
				source.equip_card_to_slot("weapon", next)
			"shield": victim.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.QINGGANG_SHIELD))
			"ended":
				game._finish_game("平局", "摄魂逐点测试")
				return
	if asks == 1: drive.call_deferred(action, source, victim)
	var no = action == "no" or (action == "first_no" and asks == 1) or (action == "second_no" and asks == 2)
	buttons[1 if no else 0].pressed.emit()

func run(host):
	suite = host
	game = host.game
	for concrete in [false, true]:
		for action in ["yes", "no", "first_no", "second_no", "close", "phase", "weapon", "shield", "ended"]:
			reset()
			var source = game.players[0]
			var victim = game.players[1]
			var blade = CardBase.create(CardData.CardSubType.SOUL_BLADE)
			source.equip_card_to_slot("weapon", blade)
			source.soul_blade_track_target = victim
			source.soul_blade_track_count = 2
			# 首次伤害不安排任何确认驱动：错误询问会令正式套件失败/超时。
			await kill(source, victim, concrete)
			suite.check(source.soul_blade_activated and source.soul_blade_track_count == 4 and asks == 0 and punches == 0 and not victim.facedown, "E03e-14d：累计2→4整次只激活，零拼点零翻面")
			suite.check(victim.hp == 8 and game._choice_prompt_stack.is_empty(), "E03e-14d：首次酒杀两伤及无额外确认")
			victim.general_name = "凯文·罗本"
			suite.check(victim.equip_card_to_slot(Player.MOUNT_SLOTS[0], CardBase.create(CardData.CardSubType.MOUNT_MINUS)), "E03e-14d：组合目标真实装备普通马，排除裸奔免疫且不改变伤害量")
			var later: Array = []
			game._kaiwen_override = func():
				later.append(true)
				return false
			drive.call_deferred(action, source, victim)
			await kill(source, victim, concrete, 1 if action == "weapon" else 0)
			suite.check(asks == 2 and victim.hp == 6, "E03e-14d：下一次两点杀伤害逐点提供两次独立机会，不重复扣血")
			var full = action == "yes"
			var none = action == "no"
			suite.check(punches == (8 if full else (0 if none else 4)), "E03e-14d：每个发动点两次拼点，拒绝或失效点不出拳")
			suite.check(victim.facedown == (not full and not none), "E03e-14d：两次获胜翻两次；拒绝/第二点失效保留前次翻面")
			suite.check(game._choice_prompt_stack.is_empty(), "E03e-14d：各点确认全部清理")
			suite.check(later.size() == (2 if action in ["yes", "no", "first_no", "second_no"] else 0), "E03e-14d：摄魂技术失效停止受伤后凯文机会，主动拒绝仍正常继续")
			# 换刀例原刀已流转入手，不重置原刀的激活状态。
			if action == "weapon": suite.check(blade.soul_blade_activated and source.determined_cards.has(blade), "E03e-14d：同名新刀不接收旧答复，原刀激活随原牌保留")
			await suite.process_frame
	reset()
	var source = game.players[0]
	var victim = game.players[1]
	var blade = CardBase.create(CardData.CardSubType.SOUL_BLADE)
	blade.soul_blade_activated = true
	source.equip_card_to_slot("weapon", blade)
	await game._deal_damage(source, victim, 2, EffectChain.DamageType.PHYSICAL)
	suite.check(punches == 0 and not victim.facedown and victim.hp == 8, "E03e-14d：非杀伤害不因已激活刀而触发摄魂拼点")
	reset()
	game._rps_override = Callable()
	game._kaiwen_override = Callable()
	suite = null
	game = null
