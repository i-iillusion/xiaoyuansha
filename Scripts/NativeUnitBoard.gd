class_name NativeUnitBoard
extends PanelContainer

# Units are a separate interaction surface, never additional spatial seats.
var _signature := ""
var _list: VBoxContainer

func _init():
	name = "NativeUnitBoard"
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -260
	offset_right = 260
	offset_top = -325
	offset_bottom = -115
	z_index = 35
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

func refresh(game: GameManager):
	# LAN renders its separate value-only board; do not allocate a hidden native view every frame.
	if game.lan_enabled:
		visible=false
		return
	var rows = UnitObservation.capture(game.unit_registry, game._local_player())
	visible = not rows.is_empty() and not game.lan_enabled
	if not visible: return
	var originals: Array = []
	for unit in game.unit_registry.turn_units():
		if game._is_human(unit):
			for card in unit.determined_cards: originals.append(card.get_instance_id())
	var signature = var_to_str([rows, originals, game.turn_manager.get_context_revision(), game._game_over, game._selecting_strike_targets(), game.mountain_space.markers()])
	if signature == _signature: return
	_signature = signature
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if rows.any(func(row): return row.kind==UnitRegistry.Kind.MOUNTAIN):
		var circle=Label.new()
		circle.text="圆桌位置："+TerrainObservation.describe(game.terrain_markers(),rows)
		circle.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(circle)
	for row in rows:
		var body: Player = game.unit_registry.entry(row.id).get("body")
		var text = "%s（%d号附属）  %d/%d  手牌%d%s%s" % [row.name, row.summoner + 1, row.hp, row.max_hp, row.hand_count, " 翻面" if row.facedown else "", " 横置" if row.chained else ""]
		if row.kind==UnitRegistry.Kind.MOUNTAIN: text += "\n位置："+TerrainObservation.location(row.id,game.terrain_markers(),rows)
		if row.wine > 0: text += " 酒：%d" % row.wine
		if row.kind != UnitRegistry.Kind.FIRE_DRAGON and not (game._selecting_strike_targets() and game._get_strike_targets(game._play_actor()).has(body)):
			var label = Label.new()
			label.text = text
			_list.add_child(label)
			continue
		var button = Button.new()
		button.text = text
		button.custom_minimum_size = Vector2(0, 52)
		button.set_meta("player", body)
		button.set_meta("unit", row.id)
		button.pressed.connect(func():
			if not game.unit_registry.contains_active(body): return
			var event = InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = true
			game._on_player_panel_click(event, button))
		_list.add_child(button)
		if row.controller == game._local_player().seat_index:
			var hand = Label.new()
			hand.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var names: Array[String] = []
			for card in row.own_cards: names.append("任意牌" if card.sub < 0 else CardData.get_type_name(card.sub))
			hand.text = "单位手牌：" + "、".join(names)
			_list.add_child(hand)
			for card in body.determined_cards:
				var concrete = Button.new()
				concrete.text = "使用单位牌：" + CardData.get_type_name(card.sub_type)
				concrete.disabled = game._play_actor() != body or not game._can_use_play_skill(body) or not game._is_human(body)
				concrete.pressed.connect(func():
					if game.unit_registry.contains_active(body) and game._play_actor() == body: game._on_determined_card_clicked(card))
				_list.add_child(concrete)
