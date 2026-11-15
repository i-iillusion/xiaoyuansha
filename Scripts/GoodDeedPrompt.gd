class_name GoodDeedPrompt
extends ColorRect

signal answered(index: int)
var selected := -1
var settled := false
var confirm: Button

func setup(title: String, names: Array[String]):
	color = Color(0, 0, 0, 0.75)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 150
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box = VBoxContainer.new()
	box.custom_minimum_size = Vector2(600, 0)
	center.add_child(box)
	var label = Label.new()
	label.text = title
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 300)
	box.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var group = ButtonGroup.new()
	for i in names.size():
		var button = Button.new()
		button.text = names[i]
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size.y = 44
		button.pressed.connect(func():
			selected = i
			confirm.disabled = false)
		list.add_child(button)
	confirm = Button.new()
	confirm.text = "确认回收" if title.begins_with("回收") else "确认做好事"
	confirm.disabled = true
	confirm.pressed.connect(func():
		if selected >= 0: submit(selected))
	box.add_child(confirm)
	var cancel = Button.new()
	cancel.text = "放弃回收" if title.begins_with("回收") else "取消做好事"
	cancel.pressed.connect(submit.bind(-1))
	box.add_child(cancel)

func submit(index: int):
	if settled: return
	settled = true
	answered.emit(index)
