# QA-103 / QA-110 / QA-111：已确认但先前未落地的规则。
extends SceneTree

var game: GameManager
var failures := 0
var checks := 0
var _check_log_buffer: Array[String] = []

func _init():
	_run()

func _flush_check_log():
	if _check_log_buffer.is_empty(): return
	print("\n".join(_check_log_buffer))
	_check_log_buffer.clear()

func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
	# Keep every line and flush failures immediately, as in the core suite.
	_check_log_buffer.append(("PASS: " if ok else "FAIL: ") + message)
	if not ok or _check_log_buffer.size() >= 256: _flush_check_log()

func reset_players():
	game._hand_discard_override = func(snapshot, count, _mandatory): return snapshot.defaults(count)
	game.reset_game_over_state()
	game._sacrifice_override = func(): return false
	game._sacrifice_actor_override = Callable()
	game._ai_response_override = func(_view, _kind, _options): return -1
	game._prep_replace_override = func(_leo, _user, _target, _sub, _options): return -1
	game._dodge_override = func(): return false
	game._dying_peach_override = func(): return false
	game._rescue_choice_override = func(_rescuer, _dying, _options): return -1
	game._nullify_override = func(): return false
	game._yes_ah_override = Callable()
	game._aoe_override = func(): return false
	game._duel_respond_override = func(): return false
	game._duel_second_override = func(): return false
	game.turn_manager.current_player_idx = 0
	game.turn_manager.play_actor_idx = -1
	game.turn_manager._reset_turn_counts()
	game.turn_manager._phase_skill_uses.clear()
	for p in game.players:
		p.reset_death_state()
		p.general_name = "稻草人"
		p.max_hp = 10
		p.hp = 10
		p.hand.clear()
		p.determined_cards.clear() # 两个手牌存储区均须隔离，避免前例牌参与后例救援。
		p.equipment.clear()
		p.equipment_cards.clear()
		p.chained = false
		p.kneeling = false
		p.consume_wine_bonus()
		p.heal_staff_peach_used = false
		p.awoken = false
		p.awake_choice = 0
		p.prep_tokens = 0
		p.capture_game_start_state()

func strike(source: Player, target: Player, ignore_restrictions: bool = false):
	return await game._execute_single_strike(source, target,
		CardBase.create(CardData.CardSubType.STRIKE), CardData.CardSubType.STRIKE,
		EffectChain.DamageType.PHYSICAL, 1, ignore_restrictions)

func _run():
	GameManager.random_identity = false
	GameManager.random_general = false
	GameManager.selected_general = "稻草人"
	game = load("res://Scenes/Game.tscn").instantiate()
	game.auto_start = false
	root.add_child(game)
	await process_frame
	game.start_game()
	game._stop_countdown()
	game._sacrifice_override = func(): return false
	game._nullify_override = func(): return false
	game._rescue_choice_override = func(_rescuer, _dying, _options): return -1
	game._zhuangbi_again_override = func(): return false
	game._hand_discard_override = func(snapshot, count, _mandatory): return snapshot.defaults(count)
	for p in game.players:
		p.hp = 10
		p.max_hp = 10
		p.hand.clear()
	var owner = game.players[0]
	owner.general_name = "史蒂芬·彼特先斯"
	owner.awoken = true # 本测试不触发另一个技能的交互弹窗。
	for i in range(3):
		owner.hand.append(null)
	var opponents: Array[Player] = []
	for i in range(1, 5):
		var p = game.players[i]
		p.hand.append(null)
		opponents.append(p)
	game._rps_override = func(p):
		if p == owner: return game.RPS_ROCK
		return game.RPS_SCISSORS if p.seat_index <= 2 else game.RPS_PAPER
	await game._execute_zhuangbi(opponents)
	check(not game._zhuangbi_blocked_this_phase, "2026-10-05：2胜2负成功，不再设置旧各半禁用")
	check(game.turn_manager.current_phase == TurnManager.Phase.PLAY, "胜负各半成功不结束出牌阶段")
	check(owner.hand_size() == 2, "本次已支付的费用不退回")
	for p in opponents:
		check(p.hp == (9 if p.seat_index <= 2 else 10) and p.hand_size() == 0, "成功仅给输家1伤，所有目标均付费用")
		p.hand.append(null)
	await game._execute_zhuangbi(opponents)
	check(owner.hand_size() == 1 and opponents[0].hand_size() == 0, "既有再次发动路径独立支付，不复用上次费用")
	opponents[0].hand.append(null) # 为菜单再选提供合法目标，不把无牌失败误当阶段禁用。
	await game._on_zhuangbi_skill_clicked(owner)
	check(game._is_zhuangbi_targeting, "既有成功后再选入口不再被旧各半禁用阻挡")
	game.turn_manager.start_waiting("test", 1)
	game.turn_manager.end_waiting()
	check(not game._zhuangbi_blocked_this_phase, "普通响应返回不生成旧各半禁用")
	game.turn_manager.current_phase = TurnManager.Phase.DRAW
	game.turn_manager.advance_phase()
	check(not game._zhuangbi_blocked_this_phase, "新的出牌阶段恢复可用")

	owner.general_name = "稻草人"
	owner.hand.clear()
	for i in range(2):
		owner.hand.append(CardBase.create(CardData.CardSubType.DISARM))
	await game._play_disarm()
	check(game.turn_manager.disarm_count_this_turn == 1, "首次卸甲归田记录使用次数")
	check(owner.hand_size() == 1, "首次卸甲归田支付一张牌")
	await game._play_disarm()
	check(owner.hand_size() == 1 and game.turn_manager.disarm_count_this_turn == 1, "重复使用被阻止且不消耗手牌")
	game.turn_manager.start_waiting("test", 1)
	game.turn_manager.end_waiting()
	check(not game.turn_manager.can_use("disarm"), "响应返回不会重置卸甲归田次数")
	game.turn_manager.current_phase = TurnManager.Phase.DRAW
	game.turn_manager.advance_phase()
	check(not game.turn_manager.can_use("disarm"), "同一回合新增出牌阶段仍不能再用卸甲归田")
	# 独立状态机验证回合边界，避免开启另一角色的异步 UI 流程。
	var turns = TurnManager.new()
	turns.use_card("disarm")
	turns.next_turn()
	check(turns.can_use("disarm"), "下一回合重置卸甲归田次数")
	turns.free()

	owner.hand.clear()
	var burning_card = CardBase.create(CardData.CardSubType.BURNING_CAMP)
	owner.hand.append(burning_card)
	for p in game.players: p.hp = 10 # 隔离前例新增成功伤害，保留原延时伤害断言。
	var center = game.players[1]
	var discard_before_burning = game.deck.discard_count()
	await game.execute_card_on_target(center, CardData.CardSubType.BURNING_CAMP)
	check(center.judgment_cards.size() == 1, "火烧连营先进入目标判定区")
	check(center.judgment_cards[0] == burning_card, "火烧连营进入判定区时保留原实例")
	check(game.deck.discard_count() == discard_before_burning, "放置延时锦囊时不同时加入弃牌堆")
	check(owner.hand_size() == 0, "放置延时锦囊时支付费用")
	check(center.hp == 10 and owner.hp == 10 and game.players[2].hp == 10, "使用时目标与相邻角色不受伤")
	check(owner.judgment_cards.is_empty() and game.players[2].judgment_cards.is_empty(), "使用时不提前蔓延")
	await game._run_judgment(center, false)
	check(center.hp == 9 and owner.hp == 9 and game.players[2].hp == 9, "等到判定才造成三处火焰伤害")
	check(center.judgment_cards.is_empty(), "判定完成移除当前火烧连营")
	check(game.deck._discard.count(burning_card) == 1, "原火烧连营结算后只入弃牌堆一次")
	check(owner.judgment_cards.size() == 1 and game.players[2].judgment_cards.size() == 1, "判定生效后才向相邻判定区蔓延")
	# GEN-01：抽将池只含可用武将；随机分配无放回，不拿稻草人补足。
	var pool = GeneralData.get_available_random_generals()
	check(pool.size() == 8 and pool.has("里奥·普利威尔") and not pool.has("稻草人"), "随机池含当前八名非占位武将，里奥已开放")
	for count in [2, 3, 5, 7, 8]:
		var draw = GeneralData.draw_unique_random_generals(count)
		var unique = {}
		for name in draw:
			unique[name] = true
		check(draw.size() == count and unique.size() == count, "%d人随机选将无重复" % count)
	check(GeneralData.METADATA_ONLY_GENERALS.size() == 23
		and GeneralData.get_implementation_status("安迪·沃费尔") == "deferred",
		"手册其余23将均有资料状态，安迪仍暂缓")
	for count in [8, 10]:
		var draw = GeneralData.draw_unique_random_generals(count)
		var unique = {}
		var metadata_count = 0
		for name in draw:
			unique[name] = true
			if GeneralData.get_implementation_status(name) == "metadata_only":
				metadata_count += 1
		check(draw.size() == count and unique.size() == count
			and metadata_count == count - pool.size() and not unique.has("安迪·沃费尔")
			and not unique.has("稻草人"),
			"%d人名单只以手册未实装将补足，仍无重复和暂缓将" % count)
	check(GeneralData.draw_unique_random_generals(31).is_empty(), "超过非暂缓武将总数不返回部分名单")
	check(GeneralData.get_max_hp("里奥·普利威尔", 5) == 5
		and GeneralData.get_max_hp("吉姆·芒顿", 10) == 6
		and GeneralData.get_max_hp("泰瑞·谢尔", 5) == 4
		and GeneralData.get_max_hp("泰瑞·谢尔", 10) == 9,
		"手册固定体力与泰瑞按开局其他玩家人数计算")
	check(GeneralData.get_gender("克莉丝汀·艾") == "female"
		and GeneralData.get_gender("萨利·赛克斯") == "female"
		and GeneralData.get_gender("里奥·普利威尔") == "male",
		"手册女性武将资料不再沿用全员男性默认")
	var metadata_player = Player.new()
	metadata_player.general_name = "彼得·伊茨·朗·欧弗·约尔·欧耳·麦·彼茨尼兹"
	metadata_player.max_hp = GeneralData.get_max_hp(metadata_player.general_name, 5)
	root.add_child(metadata_player)
	var metadata_popup = PlayerDetailPopup.create(root, metadata_player)
	await process_frame
	var skill_rows = metadata_popup.get_node("Panel/Content/SkillsSection/SkillsList").get_children()
	var warning_found = false
	for row in skill_rows:
		if row is Label and row.text.contains("技能尚未实装") and row.text.contains("6.8"):
			warning_found = true
	check(warning_found, "资料武将详情明确显示技能未实装及手册章节，而非没有技能")
	check(GeneralData.get_implementation_status(metadata_player.general_name) == "metadata_only", "资料警告仍以未实装武将验收，不把已开放里奥当资料将")
	metadata_popup.queue_free()
	metadata_player.queue_free()
	var previous_count = GameManager.selected_players
	var previous_mode = GameManager.selected_mode
	GameManager.selected_players = 5
	GameManager.selected_mode = GameManager.MODE_CLASSIC_IDENTITY
	GameManager.random_general = true
	var random_game: GameManager = load("res://Scenes/Game.tscn").instantiate()
	random_game.auto_start = false
	root.add_child(random_game)
	await process_frame
	random_game._shensu_override = func(): return false
	random_game._meiyong_override = func(): return false
	random_game.start_game()
	random_game._stop_countdown()
	var actual_names = {}
	for player in random_game.players:
		actual_names[player.general_name] = true
	check(random_game.players.size() == 5 and actual_names.size() == 5
		and not actual_names.has("稻草人"), "真实五人开局每名玩家获得不同的非占位武将")
	random_game.queue_free()
	GameManager.selected_players = previous_count
	GameManager.selected_mode = previous_mode
	GameManager.random_general = false
	# 独立换牌回归归入本组，仍保留七组及各组60秒门槛。
	var delayed_fire_basic_cases = load("res://Test/delayed_fire_basic_cases.gd").new()
	await delayed_fire_basic_cases.run(self)
	var delayed_fire_living_cases = load("res://Test/delayed_fire_living_cases.gd").new()
	await delayed_fire_living_cases.run(self)
	var prep_completion_cases = load("res://Test/prep_completion_cases.gd").new()
	await prep_completion_cases.run(self)
	var prep_strike_completion_cases = load("res://Test/prep_strike_completion_cases.gd").new()
	await prep_strike_completion_cases.run(self)
	var prep_equipment_completion_cases = load("res://Test/prep_equipment_completion_cases.gd").new()
	await prep_equipment_completion_cases.run(self)
	var prep_global_completion_cases = load("res://Test/prep_global_completion_cases.gd").new()
	await prep_global_completion_cases.run(self)
	var prep_single_trick_completion_cases = load("res://Test/prep_single_trick_completion_cases.gd").new()
	await prep_single_trick_completion_cases.run(self)
	var prep_nullification_completion_cases = load("res://Test/prep_nullification_completion_cases.gd").new()
	await prep_nullification_completion_cases.run(self)
	var prep_sacrifice_completion_cases = load("res://Test/prep_sacrifice_completion_cases.gd").new()
	await prep_sacrifice_completion_cases.run(self)
	var prep_single_replace_cases = load("res://Test/prep_single_replace_cases.gd").new()
	await prep_single_replace_cases.run(self)
	var prep_fixed_chain_replace_cases = load("res://Test/prep_fixed_chain_replace_cases.gd").new()
	await prep_fixed_chain_replace_cases.run(self)
	var prep_paid_steal_cases = load("res://Test/prep_paid_steal_cases.gd").new()
	await prep_paid_steal_cases.run(self)
	var prep_steal_replace_cases = load("res://Test/prep_steal_replace_cases.gd").new()
	await prep_steal_replace_cases.run(self)
	var prep_paid_global_cases = load("res://Test/prep_paid_global_cases.gd").new()
	await prep_paid_global_cases.run(self)
	var prep_group_replace_cases = load("res://Test/prep_group_replace_cases.gd").new()
	await prep_group_replace_cases.run(self)
	var prep_group_scope_cases = load("res://Test/prep_group_scope_cases.gd").new()
	await prep_group_scope_cases.run(self)
	var borrowed_sword_foundation_cases = load("res://Test/borrowed_sword_foundation_cases.gd").new()
	borrowed_sword_foundation_cases.run(self)
	var borrowed_second_target_cases = load("res://Test/borrowed_second_target_cases.gd").new()
	await borrowed_second_target_cases.run(self)
	var borrowed_paid_effect_cases = load("res://Test/borrowed_paid_effect_cases.gd").new()
	await borrowed_paid_effect_cases.run(self)
	var borrowed_multi_effect_cases = load("res://Test/borrowed_multi_effect_cases.gd").new()
	await borrowed_multi_effect_cases.run(self)
	var borrowed_death_nullification_cases = load("res://Test/borrowed_death_nullification_cases.gd").new()
	await borrowed_death_nullification_cases.run(self)
	var borrowed_extra_targets_cases = load("res://Test/borrowed_extra_targets_cases.gd").new()
	await borrowed_extra_targets_cases.run(self)
	var borrowed_original_entry_cases = load("res://Test/borrowed_original_entry_cases.gd").new()
	await borrowed_original_entry_cases.run(self)
	var prep_borrowed_replace_cases = load("res://Test/prep_borrowed_replace_cases.gd").new()
	await prep_borrowed_replace_cases.run(self)
	var prep_integration_cases = load("res://Test/prep_integration_cases.gd").new()
	await prep_integration_cases.run(self)
	var choice_prompt_cases = load("res://Test/choice_prompt_cases.gd").new()
	await choice_prompt_cases.run(self)
	var awaken_lifecycle_cases = load("res://Test/awaken_lifecycle_cases.gd").new()
	await awaken_lifecycle_cases.run(self)
	var awaken_default_cases = load("res://Test/awaken_default_cases.gd").new()
	await awaken_default_cases.run(self)
	# F03c: two complete response modules moved to core to balance fixed 60s suites.
	var sacrifice_prompt_cases = load("res://Test/sacrifice_prompt_cases.gd").new()
	await sacrifice_prompt_cases.run(self)
	var liehuo_prompt_cases = load("res://Test/liehuo_prompt_cases.gd").new()
	await liehuo_prompt_cases.run(self)
	var zhangba_prompt_cases = load("res://Test/zhangba_prompt_cases.gd").new()
	await zhangba_prompt_cases.run(self)
	var chixiong_prompt_cases = load("res://Test/chixiong_prompt_cases.gd").new()
	await chixiong_prompt_cases.run(self)
	var ice_sword_prompt_cases = load("res://Test/ice_sword_prompt_cases.gd").new()
	await ice_sword_prompt_cases.run(self)
	var ice_short_hand_cases = load("res://Test/ice_short_hand_cases.gd").new()
	await ice_short_hand_cases.run(self)
	var guanshi_prompt_cases = load("res://Test/guanshi_prompt_cases.gd").new()
	await guanshi_prompt_cases.run(self)
	var guanshi_mount_cases = load("res://Test/guanshi_mount_cases.gd").new()
	await guanshi_mount_cases.run(self)
	var fate_blade_prompt_cases = load("res://Test/fate_blade_prompt_cases.gd").new()
	await fate_blade_prompt_cases.run(self)
	var gou_lian_prompt_cases = load("res://Test/gou_lian_prompt_cases.gd").new()
	await gou_lian_prompt_cases.run(self)
	var gou_lian_hidden_cases = load("res://Test/gou_lian_hidden_cases.gd").new()
	await gou_lian_hidden_cases.run(self)
	var bloodthirsty_prompt_cases = load("res://Test/bloodthirsty_prompt_cases.gd").new()
	await bloodthirsty_prompt_cases.run(self)
	# F03c: complete bloodthirsty RPS regression now runs once in core.
	var calamity_prompt_cases = load("res://Test/calamity_prompt_cases.gd").new()
	await calamity_prompt_cases.run(self)
	var calamity_combination_cases = load("res://Test/calamity_combination_cases.gd").new()
	await calamity_combination_cases.run(self)
	var calamity_robe_prompt_cases = load("res://Test/calamity_robe_prompt_cases.gd").new()
	await calamity_robe_prompt_cases.run(self)
	var calamity_robe_combination_cases = load("res://Test/calamity_robe_combination_cases.gd").new()
	await calamity_robe_combination_cases.run(self)
	var mule_prompt_cases = load("res://Test/mule_prompt_cases.gd").new()
	await mule_prompt_cases.run(self)
	var mule_combination_cases = load("res://Test/mule_combination_cases.gd").new()
	await mule_combination_cases.run(self)
	var mule_full_slot_cases = load("res://Test/mule_full_slot_cases.gd").new()
	await mule_full_slot_cases.run(self)
	# G03: four whole unchanged soul-blade modules now run exactly once in the
	# identity suite's isolated host, preserving every old assertion and timeout.
	_flush_check_log()
	print("RESULT: %d asserts, %d failures" % [checks, failures])
	quit(1 if failures else 0)
