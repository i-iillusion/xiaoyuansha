extends RefCounted

func run(suite):
	var game: GameManager = suite.game
	var phase = game.turn_manager.current_phase
	game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
	suite.reset_players()
	var p: Player = game.players[0]
	p.general_name = "麦克斯·欧尼斯特"
	p.hand.append(null)
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game._lanzhonghou_used = false
	var popup = PlayerDetailPopup.create(game, p)
	var clicked: Array = []
	popup.skill_clicked.connect(func(key): clicked.append(key))
	var buttons: Array = []
	for child in popup._skills_container.get_children():
		if child is Button:
			buttons.append(child)
	suite.check(buttons.size() == 1 and buttons[0].text.contains("【没用】")
		and buttons[0].text.contains("交换"), "E01a：详情唯一主动按钮为没用交换")
	if buttons.size() == 1:
		buttons[0].pressed.emit()
	suite.check(clicked == ["没用"], "E01a：真实按钮发送没用技能键")
	await game._on_detail_skill_clicked("烂忠厚", p)
	suite.check(not game._is_lanzhonghou_targeting, "E01a：赠送名称不误触交换")
	await game._on_detail_skill_clicked("没用", p)
	suite.check(game._is_lanzhonghou_targeting, "E01a：没用技能键进入交换目标选择")
	game._on_cancel_target_pressed()
	suite.check(not game._is_lanzhonghou_targeting and p.hand_size() == 1,
		"E01a：交换选择可取消且不支付费用")
	popup.queue_free()
	var skills = GeneralData.get_skills(p.general_name)
	suite.check(skills[0].contains("空槽和暗置装备均可参与交换")
		and skills[1].begins_with("【烂忠厚】回合开始"), "E01a：说明采用名称裁决及E05空槽暗置规则")
	var old_activate = game._meiyong_override
	var old_option = game._meiyong_option_override
	var old_target = game._meiyong_target_override
	var old_granted = game.turn_manager.granted_play_target_idx
	game._meiyong_override = func(): return true
	game._meiyong_option_override = func(): return 2
	game._meiyong_target_override = func(): return game.players[1]
	game.turn_manager.current_phase = TurnManager.Phase.START
	await game._maybe_meiyong(p)
	suite.check(game.turn_manager.granted_play_target_idx == 1 and p.hand_size() == 2
		and not game._is_lanzhonghou_targeting, "E01a：赠送内部入口仍摸一牌并授予出牌阶段")
	game._meiyong_override = old_activate
	game._meiyong_option_override = old_option
	game._meiyong_target_override = old_target
	game.turn_manager.granted_play_target_idx = old_granted
	suite.reset_players()
	game.turn_manager.current_phase = phase
	game.turn_manager.phase_changed.connect(game._on_phase_changed)
