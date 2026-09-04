# ============================================================
# CardSelector.gd — 卡牌选择弹窗（多层级树状选择）
# 层级：大类 → 子分类 → 具体卡牌（杀 → 属性）
#   出牌 → 基本牌 → 杀 → 火杀
#   出牌 → 锦囊牌 → 延时锦囊 → 闪电
#   出牌 → 装备牌 → 马 → +1马
# 所有列表用两列网格 + 滚动容器，避免一列排不下点不到后面的牌
# ============================================================
class_name CardSelector
extends Control

signal confirmed(sub_type: CardData.CardSubType)
signal cancelled()
# 点击「已确定的牌」时发出（由 GameManager 提示）
signal determined_card_clicked(card: CardBase)

# 当前玩家（由 GameManager 注入，用于显示「已确定的牌」）
var player: Player = null

var _selected_sub: CardData.CardSubType = -1
# 返回栈：当前页面的「上一页重建函数」
var _back_fn: Callable = Callable()
# 悬停效果描述浮层
var _tooltip: PanelContainer
var _tooltip_label: Label

# ---- 牌库分组 ----

const BASIC_CARDS = [
	CardData.CardSubType.STRIKE,
	CardData.CardSubType.DODGE,
	CardData.CardSubType.PEACH,
	CardData.CardSubType.WINE,
]

const STRATAGEM_NORMAL = [
	CardData.CardSubType.BARBARIAN_INVASION,
	CardData.CardSubType.VOLLEY_OF_ARROWS,
	CardData.CardSubType.DUEL,
	CardData.CardSubType.IRON_CHAIN,
	CardData.CardSubType.PEACH_GARDEN,
	CardData.CardSubType.HARVEST,
	CardData.CardSubType.DISARM,
	CardData.CardSubType.SNATCH,
	CardData.CardSubType.DISMANTLE,
	CardData.CardSubType.BURNING_CAMP,
	CardData.CardSubType.NULLIFICATION,
	CardData.CardSubType.SACRIFICE,
]

const STRATAGEM_DELAYED = [
	CardData.CardSubType.LIGHTNING,
	CardData.CardSubType.INDULGENCE,
	CardData.CardSubType.SUPPLY_SHORTAGE,
]

const EQUIP_MOUNT = [
	CardData.CardSubType.MOUNT_PLUS,
	CardData.CardSubType.MOUNT_MINUS,
	CardData.CardSubType.MULE_MINUS,
	CardData.CardSubType.MULE_PLUS,
]

const EQUIP_WEAPON = [
	CardData.CardSubType.LIANNU,
	CardData.CardSubType.ZHUGE_LIANNU,
	CardData.CardSubType.QINGLONG_BLADE,
	CardData.CardSubType.ZHANGBA_SPEAR,
	CardData.CardSubType.CHIXIONG_SHUANGGU,
	CardData.CardSubType.ICE_SWORD,
	CardData.CardSubType.QINGGANG_SWORD,
	CardData.CardSubType.GUDING_BLADE,
	CardData.CardSubType.GUANSHI_AXE,
	CardData.CardSubType.QILING_BOW,
	CardData.CardSubType.POFENG_SPEAR,
	CardData.CardSubType.FANGTIAN_HALBERD,
	CardData.CardSubType.FATE_BLADE,
	CardData.CardSubType.GOU_LIAN_CLAW,
	CardData.CardSubType.BLOODTHIRSTY_BLADE,
	CardData.CardSubType.CALAMITY_SWORD,
	CardData.CardSubType.HEAL_STAFF,
	CardData.CardSubType.RAGING_AXE,
	CardData.CardSubType.SOUL_BLADE,
]

const EQUIP_ARMOR = [
	CardData.CardSubType.RENWANG_DUN,
	CardData.CardSubType.BAIHUA_SKIRT,
	CardData.CardSubType.QIXING_PAO,
	CardData.CardSubType.SILVER_LION,
	CardData.CardSubType.SHENGGUANG_BAIYI,
	CardData.CardSubType.BAGUA_ZHEN,
	CardData.CardSubType.TENGJIA,
	CardData.CardSubType.ZHANQI,
	CardData.CardSubType.LIEHUO_SHIELD,
	CardData.CardSubType.QINGGANG_SHIELD,
	CardData.CardSubType.THORN_ARMOR,
	CardData.CardSubType.CALAMITY_ROBE,
	CardData.CardSubType.SAGE_PROTECTION,
]

const STRIKE_VARIANTS = [
	CardData.CardSubType.STRIKE,
	CardData.CardSubType.FIRE_STRIKE,
	CardData.CardSubType.THUNDER_STRIKE,
]

func _ready():
	_tooltip = $Tooltip
	_tooltip_label = $Tooltip/Label
	# 淡入
	modulate = Color(1, 1, 1, 0)
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.12)

	_show_categories()

	# 背景取消
	gui_input.connect(_on_bg_click)

# ============ 页面渲染 ============

func _clear_content():
	_hide_tooltip()
	for c in $Panel/Content/List.get_children():
		c.queue_free()

func _make_section() -> VBoxContainer:
	var box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	$Panel/Content/List.add_child(box)
	return box

func _make_grid(cols: int) -> GridContainer:
	var g = GridContainer.new()
	g.columns = cols
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	return g

func _add_btn(parent: Control, text: String, cb: Callable, gray := false) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(150, 34)
	if gray:
		btn.modulate = Color(0.7, 0.7, 0.7)
	btn.pressed.connect(cb)
	parent.add_child(btn)
	return btn

# 大类按钮（大号、全宽）
func _add_big_btn(parent: Control, text: String, cb: Callable) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(320, 56)
	btn.add_theme_font_size_override("font_size", 20)
	btn.pressed.connect(cb)
	parent.add_child(btn)
	return btn

# ---- 悬停效果描述浮层 ----

func _bind_tooltip(btn: Button, sub: CardData.CardSubType):
	var desc = CardData.get_description(sub)
	if desc == "":
		return
	btn.mouse_entered.connect(_show_tooltip.bind(desc, btn))
	btn.mouse_exited.connect(_hide_tooltip)

func _show_tooltip(text: String, btn: Button):
	_tooltip_label.text = text
	_tooltip.visible = true
	# 位置：按钮右侧；右侧放不下则放左侧
	var btn_rect = btn.get_global_rect()
	var tsize = _tooltip.get_combined_minimum_size()
	var pos = btn_rect.position + Vector2(btn_rect.size.x + 8, -4)
	var vp_w = get_viewport_rect().size.x
	if pos.x + tsize.x > vp_w - 8:
		pos.x = btn_rect.position.x - tsize.x - 8
	_tooltip.position = pos

func _hide_tooltip():
	if _tooltip:
		_tooltip.visible = false

func _add_back_button(parent: Control):
	var b = _add_btn(parent, "← 返回", _go_back, true)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

func _set_page(render: Callable, back: Callable):
	_back_fn = back
	render.call()

func _go_back():
	if _back_fn.is_valid():
		var b = _back_fn
		_back_fn = Callable()
		b.call()
	else:
		_show_categories()

# ---- 第一层：大类 ----

func _show_categories():
	_back_fn = Callable()
	_clear_content()
	$Panel/Title.text = "选择卡牌类型"

	var box = _make_section()
	_add_big_btn(box, "基本牌", _set_page.bind(_render_basic, _show_categories))
	_add_big_btn(box, "锦囊牌", _set_page.bind(_render_stratagem, _show_categories))
	_add_big_btn(box, "装备牌", _set_page.bind(_render_equipment, _show_categories))

	_add_determined_section(box)

	var cancel = _add_btn(box, "取消", _on_cancel, true)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

# ---- 第二层：子分类 ----

func _render_basic():
	_clear_content()
	$Panel/Title.text = "基本牌"
	var box = _make_section()
	_render_card_grid_into(box, BASIC_CARDS, _render_basic)
	_add_back_button(box)

func _render_stratagem():
	_clear_content()
	$Panel/Title.text = "锦囊牌"
	var box = _make_section()
	var g = _make_grid(2)
	_add_btn(g, "普通锦囊", _set_page.bind(_render_normal_stratagem, _render_stratagem))
	_add_btn(g, "延时锦囊", _set_page.bind(_render_delayed_stratagem, _render_stratagem))
	box.add_child(g)
	_add_back_button(box)

func _render_equipment():
	_clear_content()
	$Panel/Title.text = "装备牌"
	var box = _make_section()
	var g = _make_grid(2)
	_add_btn(g, "马", _set_page.bind(_render_mounts, _render_equipment))
	_add_btn(g, "武器", _set_page.bind(_render_weapons, _render_equipment))
	_add_btn(g, "防具", _set_page.bind(_render_armors, _render_equipment))
	box.add_child(g)
	_add_back_button(box)

# ---- 第三层：具体牌列表 ----

func _render_normal_stratagem():
	_clear_content()
	$Panel/Title.text = "普通锦囊"
	var box = _make_section()
	_render_card_grid_into(box, STRATAGEM_NORMAL, _render_stratagem)
	_add_back_button(box)

func _render_delayed_stratagem():
	_clear_content()
	$Panel/Title.text = "延时锦囊"
	var box = _make_section()
	_render_card_grid_into(box, STRATAGEM_DELAYED, _render_stratagem)
	_add_back_button(box)

func _render_mounts():
	_clear_content()
	$Panel/Title.text = "马"
	var box = _make_section()
	_render_card_grid_into(box, EQUIP_MOUNT, _render_equipment)
	_add_back_button(box)

func _render_weapons():
	_clear_content()
	$Panel/Title.text = "武器"
	var box = _make_section()
	_render_card_grid_into(box, EQUIP_WEAPON, _render_equipment)
	_add_back_button(box)

func _render_armors():
	_clear_content()
	$Panel/Title.text = "防具"
	var box = _make_section()
	_render_card_grid_into(box, EQUIP_ARMOR, _render_equipment)
	_add_back_button(box)

func _render_card_grid_into(box: VBoxContainer, cards: Array, _back_target: Callable):
	var g = _make_grid(2)
	for sub in cards:
		var btn = _add_btn(g, CardData.get_type_name(sub), _on_sub_chosen.bind(sub))
		_bind_tooltip(btn, sub)
	box.add_child(g)

# 杀的属性选择（普通杀 / 火杀 / 雷杀）
func _render_strike_variants():
	_clear_content()
	$Panel/Title.text = "选择杀的属性"
	var box = _make_section()
	var g = _make_grid(2)
	for v in STRIKE_VARIANTS:
		var btn = _add_btn(g, CardData.get_type_name(v), _on_variant_chosen.bind(v))
		_bind_tooltip(btn, v)
	box.add_child(g)
	_add_back_button(box)

# ---- 已确定的牌（顺手牵羊获得的装备/判定牌） ----

func _add_determined_section(box: VBoxContainer):
	if not player or player.determined_cards.size() <= 0:
		return
	var label = Label.new()
	label.text = "已确定的牌"
	label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.8))
	label.add_theme_font_size_override("font_size", 14)
	box.add_child(label)
	for card in player.determined_cards:
		var d_btn = _add_btn(box, card.card_name, _on_determined_card_clicked.bind(card))
		_bind_tooltip(d_btn, card.sub_type)

# ============ 选择逻辑 ============

func _on_sub_chosen(sub: CardData.CardSubType):
	# 杀：先选属性（普通杀/火杀/雷杀），返回回到基本牌列表
	if sub == CardData.CardSubType.STRIKE:
		_set_page(_render_strike_variants, _render_basic)
		return
	# 点击卡牌名直接出牌，跳过确认步骤
	_selected_sub = sub
	_on_confirm()

func _on_variant_chosen(sub: CardData.CardSubType):
	_selected_sub = sub
	_on_confirm()

func _on_confirm():
	if _selected_sub < 0:
		return
	_hide_tooltip()
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.1)
	await tween.finished
	confirmed.emit(_selected_sub)
	queue_free()

func _on_determined_card_clicked(card: CardBase):
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.1)
	await tween.finished
	determined_card_clicked.emit(card)
	queue_free()

func _on_cancel():
	_hide_tooltip()
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.1)
	await tween.finished
	cancelled.emit()
	queue_free()

func _on_bg_click(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var panel_rect = $Panel.get_global_rect()
			if not panel_rect.has_point(get_global_mouse_position()):
				_on_cancel()
