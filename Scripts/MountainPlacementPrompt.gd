extends ColorRect

signal chosen(index: int)

func setup(texts: Array[String]):
	name = "MountainPlacementPrompt"
	color = Color(0,0,0,0.65)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 150
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box = VBoxContainer.new()
	box.custom_minimum_size = Vector2(760,0)
	center.add_child(box)
	var title = Label.new()
	title.text = "【王屋太行】选择两座山的位置（可同间隔）；超时自动放在自身左右"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(760,60)
	box.add_child(title)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(760,400)
	box.add_child(scroll)
	var grid = GridContainer.new()
	grid.columns = 2
	scroll.add_child(grid)
	for index in texts.size():
		var button = Button.new()
		button.text = texts[index]
		button.tooltip_text = texts[index]
		button.custom_minimum_size = Vector2(370,44)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.pressed.connect(func(): chosen.emit(index))
		grid.add_child(button)
