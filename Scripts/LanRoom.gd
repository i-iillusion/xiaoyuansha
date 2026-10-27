extends Control

var session: LanSession
var body: VBoxContainer
var message: Label
var clock_label: Label
var pace_label: Label
var _screen := ""
var _game_shape := ""
var _submitted := ""
var _name := "玩家"
var _history_panel: ActionHistoryPanel
var _board: GridContainer

func _ready() -> void:
	session = LanSession.new()
	session.name = "Session" # RPC path is identical on host and clients.
	add_child(session)
	session.lobby_changed.connect(_lobby_changed)
	session.state_received.connect(_state_changed)
	session.notice.connect(func(text): message.text = text)
	var bg = ColorRect.new()
	bg.color = Color("18212b")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var top = HBoxContainer.new()
	box.add_child(top)
	var title = _label(top, "校园杀 · 局域网试玩")
	title.add_theme_font_size_override("font_size", 25)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clock_label = _label(top, "")
	_button(top, "离开房间 / 返回主菜单", _leave)
	message = _label(box, "仅用于信任的局域网；请所有成员使用同一个试玩包。")
	pace_label = _label(box, "")
	_history_panel = ActionHistoryPanel.new()
	box.add_child(_history_panel)
	_history_panel.bind(session.history)
	_history_panel.visible = false
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	scroll.add_child(body)
	_show_connection()
	get_viewport().size_changed.connect(_resize_board)
	print("[LAN] room ready · ", LanSession.PROTOCOL)

func _clear() -> void:
	_board = null
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()

func _label(parent: Node, text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(180, 42)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _edit(parent: Node, hint: String, value: String) -> LineEdit:
	var input = LineEdit.new()
	input.placeholder_text = hint
	input.text = value
	input.custom_minimum_size = Vector2(320, 42)
	parent.add_child(input)
	return input

func _show_connection() -> void:
	pace_label.text = ""
	_history_panel.visible = false
	_screen = "connect"
	_clear()
	_label(body, "连接方式：一人创建房间，其余人在同一局域网输入房主IP加入。无需安装Godot。")
	var name_input = _edit(body, "你的昵称", _name)
	name_input.max_length = 24
	var address = _edit(body, "房主的局域网IPv4地址，例如192.168.1.20", "127.0.0.1")
	var port = _edit(body, "UDP端口", str(LanSession.DEFAULT_PORT))
	port.max_length = 5
	var mode = OptionButton.new()
	mode.name = "RoomModePicker"
	var modes = GameModes.catalog().filter(func(row): return row.playable)
	for entry in modes: mode.add_item("%d人%s" % [entry.count, GameModes.title(entry.mode)])
	for index in modes.size():
		if modes[index].mode == GameModes.FREE_FOR_ALL and modes[index].count == 2: mode.select(index)
	body.add_child(mode)
	_button(body, "创建房间（我是房主）", func():
		_name = name_input.text
		var entry = modes[mode.selected]
		var error = session.host(_name, entry.count, int(port.text), entry.mode)
		if error != OK: message.text = "创建失败：%s。检查端口是否被占用。" % error_string(error))
	_button(body, "加入房间", func():
		_name = name_input.text
		var error = session.join_room(address.text.strip_edges(), _name, int(port.text))
		message.text = "正在连接……" if error == OK else "连接参数错误：%s" % error_string(error))
	var addresses: Array[String] = []
	for ip in IP.get_local_addresses():
		if ":" not in ip and not ip.begins_with("127.") and not ip.begins_with("169.254."): addresses.append(ip)
	_label(body, "本机候选局域网地址：" + " / ".join(addresses))
	_label(body, "127.0.0.1仅供同一台电脑多开测试。其他电脑必须填写房主的局域网地址。\n若Windows询问网络权限，仅允许你信任的私有网络；不需要关闭防火墙或设置公网端口转发。")

func _lobby_changed(state: Dictionary) -> void:
	if state.is_empty():
		_show_connection()
		return
	if state.playing: return
	pace_label.text = "房主AI速度：" + AiActionPacer.LABELS[session.pace] + " · 真人读条不变"
	_history_panel.visible = false
	_screen = "lobby"
	_game_shape = ""
	clock_label.text = ""
	_clear()
	_label(body, "房间：%d / %d 人 · %s" % [state.members.size(), state.count, GameModes.title(state.mode)])
	if multiplayer.is_server():
		var addresses: Array[String] = []
		for ip in IP.get_local_addresses():
			if ":" not in ip and not ip.begins_with("127.") and not ip.begins_with("169.254."): addresses.append(ip)
		_label(body, "让同伴加入：" + " / ".join(addresses) + " · UDP端口 %d" % session.port_number)
		var picker = OptionButton.new()
		picker.name = "HostPacePicker"
		for label in AiActionPacer.LABELS: picker.add_item(label)
		picker.select(session.pace)
		picker.item_selected.connect(func(index): session.set_pace(index))
		body.add_child(picker)
	var mine: Dictionary = {}
	for member in state.members:
		_label(body, "%s%s · %s · %s" % [member.name, "（房主）" if member.peer == 1 else "", member.general, "已准备" if member.ready else "未准备"])
		if member.peer == multiplayer.get_unique_id(): mine = member
	if mine.is_empty(): return
	var options = OptionButton.new()
	var names: Array[String] = ["随机", "稻草人"]
	names.append_array(LanSession.GENERALS)
	for general in names: options.add_item(general)
	options.select(names.find(mine.general))
	body.add_child(options)
	options.item_selected.connect(func(index): session.choose(names[index], false))
	_button(body, "取消准备" if mine.ready else "准备", func(): session.choose(names[options.selected], not mine.ready))
	if multiplayer.is_server():
		var start = _button(body, "全部准备后开始", func():
			if not session.begin_match(): message.text = "请等人数齐全、每人准备，并确保非稻草人武将不重复。")
		start.disabled = state.members.size() != state.count
	_label(body, "8名武将已有技能；随机池不足时补手册资料将，其技能尚未实装。稻草人可重复测试。\n中途断线中断本局，不自动托管、不判胜负；支持重新准备。")

func _send(token: String) -> void:
	if token.is_empty() or token == _submitted: return
	_submitted = token
	session.act(token)

func _state_changed(state: Dictionary) -> void:
	pace_label.text = "房主AI速度：" + AiActionPacer.LABELS[state.get("pace", AiActionPacer.Speed.STANDARD)] + " · 当前联机全是真人，不影响真人行动"
	_history_panel.visible = true
	_submitted = ""
	clock_label.text = str(state.clock)
	var shape = state.duplicate(true)
	shape.erase("clock")
	shape.erase("history") # Log refresh does not rebuild rule choices or scrolling.
	var fingerprint = var_to_str(shape)
	if _screen == "game" and fingerprint == _game_shape: return
	_screen = "game"
	_game_shape = fingerprint
	_clear()
	var me: Dictionary = state.players[int(state.actor)]
	_label(body, "你是 %d号 %s · %s · 身份：%s" % [int(state.actor) + 1, me.name, me.general, me.identity if me.identity != "" else "无"])
	if not state.ended:
		var acting = state.get("units", []).filter(func(unit): return unit.id == state.get("acting_unit", ""))
		var acting_name = "%d号" % [int(state.turn) + 1] if acting.is_empty() else "%s（%d号控制）" % [acting[0].name, acting[0].controller + 1]
		_label(body, "当前行动：%s · 当前窗口：%d号" % [acting_name, int(state.owner) + 1])
	var board = GridContainer.new()
	board.name = "PlayerBoard"
	_board = board
	board.columns = SeatLayout.columns(state.players.size(), get_viewport_rect().size.x - 36)
	body.add_child(board)
	for seat in state.get("space", range(state.players.size())):
		var player: Dictionary = state.players[seat]
		var text = "%d号 %s\n%s\n体力 %d/%d · 手牌 %d\n%s%s%s" % [int(player.seat) + 1, player.name, player.general,
			player.hp, player.max_hp, player.hand_count, "已阵亡 " if player.dead else "", "横置 " if player.chained else "", "翻面 " if player.facedown else ""]
		text += "\n身份：" + (player.identity if player.identity != "" else ("暗置" if state.mode != GameModes.FREE_FOR_ALL else "无"))
		var judgments: Array[String] = []
		for sub in player.judgments: judgments.append(CardData.get_type_name(int(sub)))
		text += "\n判定：" + ("、".join(judgments) if not judgments.is_empty() else "无")
		if player.kneeling: text += "\n下跪中"
		if player.dying: text += "\n濒死求救中"
		if int(player.prep) > 0: text += "\n预习标记：%d" % player.prep
		if int(player.wine) > 0: text += "\n酒：%d" % player.wine
		if player.general == "克里斯·西弗": text += "\n火龙蛋：%d" % int(player.get("eggs", 0))
		var token: String = state.targets.get(str(player.seat), "")
		var button = _button(board, text, func(): _send(token))
		button.set_meta("seat", int(player.seat))
		button.custom_minimum_size = Vector2(210, 140)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.disabled = token.is_empty()
		var equipment: Array[String] = []
		for slot in player.equipment:
			var sub = player.equipment[slot]
			if sub != null: equipment.append(str(slot) + ": " + CardData.get_type_name(sub))
		var skill_text = "技能尚未实装（资料武将）" if GeneralData.get_implementation_status(player.general) == "metadata_only" else "\n".join(GeneralData.get_skills(player.general))
		button.tooltip_text = "\n".join(equipment) + "\n" + skill_text
	var units: Array = state.get("units", [])
	if not units.is_empty():
		var unit_board = GridContainer.new()
		unit_board.name = "UnitBoard"
		unit_board.columns = SeatLayout.columns(units.size(), get_viewport_rect().size.x - 36)
		body.add_child(unit_board)
		for unit in units:
			var text = "%s · 召唤者%d号\n体力%d/%d · 手牌%d" % [unit.name, unit.summoner + 1, unit.hp, unit.max_hp, unit.hand_count]
			if unit.controller >= 0: text += "\n操作控制者%d号" % [unit.controller + 1]
			if unit.dying: text += "\n濒死中"
			if unit.facedown: text += "\n翻面"
			if unit.chained: text += "\n横置"
			if unit.wine > 0: text += "\n酒：%d" % unit.wine
			if unit.gender == "none": text += "\n无性别"
			var judgments: Array[String] = []
			for sub in unit.judgments: judgments.append(CardData.get_type_name(int(sub)))
			text += "\n判定：" + ("、".join(judgments) if not judgments.is_empty() else "无")
			var own: Array[String] = []
			for card in unit.own_cards: own.append("任意牌" if int(card.sub) < 0 else CardData.get_type_name(int(card.sub)))
			if not own.is_empty(): text += "\n你控制的单位手牌：" + "、".join(own)
			if unit.kind == UnitRegistry.Kind.FIRE_DRAGON:
				var token: String = state.targets.get(unit.id, "")
				var button = _button(unit_board, text, func(): _send(token))
				button.set_meta("unit", unit.id)
				button.custom_minimum_size = Vector2(240, 150)
				button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				button.disabled = token.is_empty()
				var equipment: Array[String] = []
				for slot in unit.equipment:
					if unit.equipment[slot] != null: equipment.append(str(slot) + ": " + CardData.get_type_name(int(unit.equipment[slot])))
				button.tooltip_text = "\n".join(equipment)
			else: _label(unit_board, text).set_meta("unit", unit.id)
	var cards: Array[String] = []
	for card in state.own_cards:
		cards.append("任意牌" if int(card.sub) < 0 else CardData.get_type_name(int(card.sub)))
	_label(body, "你的手牌：" + "、".join(cards))
	_label(body, str(state.status))
	if not str(state.notice).is_empty(): _label(body, str(state.notice))
	if state.ended:
		_label(body, "本局结束：" + str(state.winner))
		if multiplayer.is_server(): _button(body, "返回房间，再开一局", session.return_to_lobby)
		else: _label(body, "等待房主返回房间；也可离开返回主菜单。")
		return
	if not str(state.kneel).is_empty(): _button(body, "下跪 / 解除下跪", func(): _send(state.kneel))
	for text in state.labels: _label(body, str(text))
	var actions = GridContainer.new()
	actions.columns = 3
	body.add_child(actions)
	for action in state.controls:
		var text: String = ("☑ " if action.pressed else "□ ") + action.text if action.toggle else action.text
		var button = _button(actions, text, func(): _send(action.id))
		button.disabled = action.disabled
		button.tooltip_text = action.hint
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _resize_board() -> void:
	if is_instance_valid(_board) and not _board.is_queued_for_deletion():
		_board.columns = SeatLayout.columns(_board.get_child_count(), get_viewport_rect().size.x - 36)

func _leave() -> void:
	session.close()
	get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn")
