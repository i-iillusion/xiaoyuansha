class_name HandDiscardPrompt
extends ColorRect

signal answered(indices: Array[int])
var settled := false
var selected: Array[int] = []
var required := 1
var fallback: Array[int] = []
var confirm: Button

func setup(snapshot: HandSelection, count: int, mandatory: bool):
	required = count
	# 三元表达式的 [] 是无类型 Array，不能赋给 Array[int]（运行时错误）。
	fallback.clear()
	if mandatory:
		fallback.assign(snapshot.defaults(count))
	color = Color(0, 0, 0, 0.8)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 150
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box = VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	center.add_child(box)
	var title = Label.new()
	title.text = "选择弃置 %d 张手牌（%s）" % [count, "必须弃牌" if mandatory else "技能费用，可取消"]
	box.add_child(title)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 300)
	box.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	confirm = Button.new()
	confirm.text = "确认弃牌"
	confirm.disabled = true
	for i in snapshot.cards.size():
		var button = CheckButton.new()
		var card = snapshot.cards[i]
		button.text = "%d · %s" % [i + 1, "任意牌（未具体化）" if card == null else CardData.get_type_name(card.sub_type)]
		button.toggled.connect(func(on):
			if on:
				selected.append(i)
			else:
				selected.erase(i)
			confirm.disabled = selected.size() != required)
		list.add_child(button)
	confirm.pressed.connect(func():
		if selected.size() == required:
			submit(selected))
	box.add_child(confirm)
	var cancel = Button.new()
	cancel.text = "自动选牌" if mandatory else "取消发动"
	cancel.pressed.connect(timeout)
	box.add_child(cancel)
	var hint = Label.new()
	hint.text = "超时自动选择剩余应弃的牌" if mandatory else "取消或超时不支付费用"
	box.add_child(hint)

func timeout():
	submit(fallback)

func submit(indices: Array[int]):
	if settled:
		return
	settled = true
	answered.emit(indices.duplicate())
