class_name SallyWomanPrompt
extends ColorRect

signal answered(index: int)
var selected_target := -1
var selected_card := -1
var card_count := 0
var settled := false
var confirm: Button

func setup(names: Array[String], snapshot: HandSelection):
	color = Color(0, 0, 0, 0.8)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 150
	card_count = snapshot.cards.size()
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box = VBoxContainer.new()
	box.custom_minimum_size = Vector2(600, 0)
	center.add_child(box)
	var title = Label.new()
	title.text = "【女人】选择其他角色及弃置的1张手牌，确认后使其变为女性"
	box.add_child(title)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 360)
	box.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var targets = ButtonGroup.new()
	for i in names.size():
		var button = Button.new()
		button.text = "目标：" + names[i]
		button.toggle_mode = true
		button.button_group = targets
		button.custom_minimum_size.y = 44
		button.pressed.connect(func(): selected_target = i; refresh())
		list.add_child(button)
	var cards = ButtonGroup.new()
	for i in card_count:
		var button = Button.new()
		var card = snapshot.cards[i]
		button.text = "弃牌%d：%s" % [i+1, "任意牌（未具体化）" if card == null else CardData.get_type_name(card.sub_type)]
		button.toggle_mode = true
		button.button_group = cards
		button.custom_minimum_size.y = 44
		button.pressed.connect(func(): selected_card = i; refresh())
		list.add_child(button)
	confirm = Button.new()
	confirm.text = "确认发动女人"
	confirm.disabled = true
	confirm.pressed.connect(func():
		if selected_target >= 0 and selected_card >= 0: submit(selected_target * card_count + selected_card))
	box.add_child(confirm)
	var cancel = Button.new()
	cancel.text = "取消发动女人"
	cancel.pressed.connect(submit.bind(-1))
	box.add_child(cancel)

func refresh():
	confirm.disabled = selected_target < 0 or selected_card < 0

func submit(index: int):
	if settled: return
	settled = true
	answered.emit(index)
