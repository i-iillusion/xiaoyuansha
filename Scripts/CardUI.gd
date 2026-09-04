# ============================================================
# CardUI.gd — 卡牌的可视化控件
# 支持 hover 放大、拖拽、点击信号
# 无花色点数，只显示卡牌名称和类型
# ============================================================
class_name CardUI
extends Panel

@onready var bg: ColorRect = $BG
@onready var name_label: Label = $NameLabel
@onready var type_label: Label = $TypeLabel

var card_data: CardBase : set = _set_card_data
var _dragging: bool = false
var _drag_offset: Vector2
var _press_pos: Vector2
var _was_dragged: bool = false

signal card_clicked(card_ui: CardUI)

const DRAG_THRESHOLD: float = 10.0

func _ready():
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(_on_unhover)
	gui_input.connect(_on_gui_input)
	# 避免被父控件拦截事件
	mouse_filter = Control.MOUSE_FILTER_STOP
	_update_display()

func _set_card_data(data: CardBase):
	card_data = data
	if not is_node_ready():
		await ready
	_update_display()

func _update_display():
	if not card_data:
		# 空白卡牌
		name_label.text = "待选"
		type_label.text = ""
		bg.color = Color(0.2, 0.2, 0.25)
		return

	name_label.text = card_data.card_name
	var ct = CardData.get_category_name(CardData.get_type_category(card_data.sub_type))
	type_label.text = ct

	# 按类型配色
	match card_data.sub_type:
		CardData.CardSubType.STRIKE:
			bg.color = Color(0.35, 0.12, 0.12)   # 暗红
		CardData.CardSubType.DODGE:
			bg.color = Color(0.12, 0.28, 0.35)   # 暗蓝
		CardData.CardSubType.PEACH:
			bg.color = Color(0.30, 0.20, 0.35)   # 暗紫
		_:
			bg.color = Color(0.15, 0.15, 0.28)   # 锦囊蓝

func is_dragging() -> bool:
	return _dragging

func _on_hover():
	scale = Vector2(1.12, 1.12)
	z_index = 10

func _on_unhover():
	scale = Vector2(1.0, 1.0)
	z_index = 0

func _on_gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_was_dragged = false
				_press_pos = get_global_mouse_position()
				_drag_offset = _press_pos - global_position
				z_index = 20
			elif _dragging:
				_dragging = false
				z_index = 0
				if not _was_dragged:
					card_clicked.emit(self)
	elif event is InputEventMouseMotion and _dragging:
		var mouse_pos = get_global_mouse_position()
		if _press_pos.distance_to(mouse_pos) > DRAG_THRESHOLD:
			_was_dragged = true
		global_position = mouse_pos - _drag_offset
