extends ColorRect

signal chosen(index: int)

func setup(options: Array):
	name = "RoarChoicePrompt"
	color = Color(0, 0, 0, 0.65)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 150
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box = VBoxContainer.new()
	box.custom_minimum_size = Vector2(720, 0)
	center.add_child(box)
	var title = Label.new()
	title.text = "【恶龙咆哮】牺牲火龙、弃1颗蛋，对所选角色造成6点火焰伤害"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(720, 48)
	box.add_child(title)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(720, 360)
	box.add_child(scroll)
	var grid = GridContainer.new()
	grid.columns = 2
	scroll.add_child(grid)
	for i in options.size():
		var option: Dictionary = options[i]
		var button = Button.new()
		button.text = "牺牲%s → %d号 %s" % [option.id, option.target.seat_index + 1, option.target.player_name]
		button.tooltip_text = button.text
		button.custom_minimum_size = Vector2(350, 44)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.pressed.connect(func(): chosen.emit(i))
		grid.add_child(button)
	var cancel = Button.new()
	cancel.text = "取消咆哮"
	cancel.custom_minimum_size = Vector2(350, 44)
	cancel.pressed.connect(func(): chosen.emit(-1))
	box.add_child(cancel)
