# ============================================================
# HandArea.gd — 手牌显示区域
# 自动将子卡片横向居中排列
# ============================================================
class_name HandArea
extends Control

@export var spacing: int = 25

func _process(_delta):
	_arrange_children()

func _arrange_children():
	var children = get_children()
	if children.is_empty():
		return

	# 如果有牌正在被拖拽，跳过重排
	for child in children:
		if child is CardUI and child.is_dragging():
			return

	var total = (children.size() - 1) * spacing
	var start_x = maxf(0.0, (size.x - total) / 2.0)

	for i in children.size():
		var child = children[i]
		if child is Control:
			child.position = Vector2(start_x + i * spacing, (size.y - child.size.y) / 2.0)

# ---- 便捷方法 ----

func add_card(data: CardBase) -> CardUI:
	var scene = preload("res://Scenes/CardUI.tscn")
	var card = scene.instantiate()
	card.card_data = data
	add_child(card)
	return card

func remove_card(card: CardUI):
	if card in get_children():
		remove_child(card)
		card.queue_free()

func clear():
	for child in get_children().duplicate():
		child.queue_free()

func get_card_count() -> int:
	return get_child_count()
