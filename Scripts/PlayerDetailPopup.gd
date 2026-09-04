# ============================================================
# PlayerDetailPopup.gd — 玩家详情弹窗
# 显示：武将头像（大）、技能、装备、标记
# ============================================================
class_name PlayerDetailPopup
extends Control

# 装备区点击（目前只有贤者的加护可点击发动；sub = 被点击的装备子类型）
signal equip_clicked(sub: CardData.CardSubType)
# 技能区点击（目前只有【下跪】可点击；skill_key = 技能名，如 "下跪"）
signal skill_clicked(skill_key: String)

var _player: Player
var _wine_stacks: int = 0
# 悬停效果描述浮层
var _tooltip: PanelContainer
var _tooltip_label: Label

@onready var _avatar_label: Label = $Panel/Content/AvatarSection/AvatarLabel
@onready var _name_label: Label = $Panel/Content/AvatarSection/AvatarInfo/NameLabel
@onready var _general_label: Label = $Panel/Content/AvatarSection/AvatarInfo/GeneralLabel
@onready var _hp_label: Label = $Panel/Content/AvatarSection/AvatarInfo/HPLabel
@onready var _identity_label: Label = $Panel/Content/AvatarSection/AvatarInfo/IdentityLabel
@onready var _skills_container: VBoxContainer = $Panel/Content/SkillsSection/SkillsList
@onready var _status_container: VBoxContainer = $Panel/Content/StatusSection/StatusList
@onready var _equip_container: VBoxContainer = $Panel/Content/EquipmentSection/EquipmentList
@onready var _marks_container: VBoxContainer = $Panel/Content/MarksSection/MarksList
@onready var _close_btn: Button = $Panel/CloseBtn

# 静态方法：创建一个新的详情弹窗
static func create(parent: Node, player: Player, wine_stacks: int = 0) -> PlayerDetailPopup:
	var scene = load("res://Scenes/PlayerDetailPopup.tscn")
	if scene == null:
		# 代码兜底：直接实例化
		var popup = PlayerDetailPopup.new()
		popup._player = player
		popup._wine_stacks = wine_stacks
		parent.add_child(popup)
		return popup

	var popup = scene.instantiate()
	popup._player = player
	popup._wine_stacks = wine_stacks
	parent.add_child(popup)
	return popup

func _ready():
	_tooltip = $Tooltip
	_tooltip_label = $Tooltip/Label
	_close_btn.pressed.connect(_on_close)
	gui_input.connect(_on_bg_click)
	# _player 在 create 时已注入，_ready 时 @onready 就绪后再填充内容
	_populate()

func _populate():
	if not _player:
		return

	_avatar_label.text = GeneralData.get_avatar(_player.general_name)
	_name_label.text = _player.player_name
	_general_label.text = "武将：%s" % _player.general_name
	_hp_label.text = "体力：%d/%d" % [_player.hp, _player.max_hp]
	# 身份显示：主公开局公开；其他身份阵亡（翻开）后显示，否则隐藏为？
	if _player.identity == "":
		_identity_label.text = "身份：无"
	elif _player.identity_revealed:
		_identity_label.text = "身份：%s" % _player.identity
	else:
		_identity_label.text = "身份：？"

	# 技能区：显示武将技能（稻草人无技能）；布鲁斯·萨维奇的【下跪】/安普提的【苕】/史蒂芬的【装逼】可点击发动
	_clear_container(_skills_container)
	var sep = HSeparator.new()
	_skills_container.add_child(sep)
	var skills = GeneralData.get_skills(_player.general_name)
	if skills.is_empty():
		var skill_label = Label.new()
		skill_label.text = "%s 没有技能" % _player.general_name
		skill_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
		_skills_container.add_child(skill_label)
	else:
		for sk in skills:
			# 【下跪】：可点击的按钮（发动/解除/已使用提示）
			if sk.begins_with("【下跪】"):
				_add_skill_btn("下跪", sk)
			# 【苕】：可点击的按钮（暗置 / 明置 / 替换）
			elif sk.begins_with("【苕】"):
				_add_skill_btn("苕", sk)
			# 【装逼】：可点击的按钮（出牌阶段发动，选目标后拼点）
			elif sk.begins_with("【装逼】"):
				_add_skill_btn("装逼", sk)
			# 【校园霸主】：可点击的按钮（出牌阶段发动，选一名角色拼点）
			elif sk.begins_with("【校园霸主】"):
				_add_skill_btn("校园霸主", sk)
			# 【烂忠厚】：可点击的按钮（出牌阶段发动，选两名角色交换装备区域）
			elif sk.begins_with("【烂忠厚】"):
				_add_skill_btn("烂忠厚", sk)
			# 【Gay】：可点击的按钮（出牌阶段限一次，弃 X 张手牌双方回血）
			elif sk.begins_with("【Gay】"):
				_add_skill_btn("Gay", sk)
			# 【无谋】：下跪状态下技能失效 → 灰色
			elif sk.begins_with("【无谋】") and _player.general_name == "布鲁斯·萨维奇" and _player.kneeling:
				_add_skill_label(sk, Color(0.55, 0.55, 0.6))
			else:
				_add_skill_label(sk, Color(0.9, 0.9, 0.7))

	# 装备区：只显示名字，悬停浮现效果描述；顺序 = 武器 → 防具 → 坐骑
	_clear_container(_equip_container)
	var equip_rows := 0
	if _player.equipment.has("weapon"):
		var wsub = _player.equipment["weapon"]
		if wsub == CardData.CardSubType.HIDDEN_EQUIPMENT:
			_add_equip_row(wsub, "武器：一件装备（暗置）", "暗置装备：点击技能【苕】可明置为具体装备")
		else:
			_add_equip_row(wsub, "武器：%s" % CardData.get_type_name(wsub), CardData.get_description(wsub))
		equip_rows += 1
	if _player.equipment.has("armor"):
		var asub = _player.equipment["armor"]
		if asub == CardData.CardSubType.HIDDEN_EQUIPMENT:
			_add_equip_row(asub, "护甲：一件装备（暗置）", "暗置装备：点击技能【苕】可明置为具体装备")
		else:
			_add_equip_row(asub, "护甲：%s" % CardData.get_type_name(asub), CardData.get_description(asub))
		equip_rows += 1
	# 坐骑统计（按类型计数，保持 +1/-1/劣马 顺序）
	var mount_counts := {}
	for s in Player.MOUNT_SLOTS:
		if _player.equipment.has(s):
			var msub = _player.equipment[s]
			mount_counts[msub] = mount_counts.get(msub, 0) + 1
	if not mount_counts.is_empty():
		var parts: Array[String] = []
		var tip_parts: Array[String] = []
		if mount_counts.has(CardData.CardSubType.HIDDEN_EQUIPMENT):
			parts.append("一件装备（暗置） ×%d" % mount_counts[CardData.CardSubType.HIDDEN_EQUIPMENT])
			tip_parts.append("暗置装备：点击技能【苕】可明置为具体装备")
		for msub in [CardData.CardSubType.MOUNT_PLUS, CardData.CardSubType.MOUNT_MINUS, CardData.CardSubType.MULE_MINUS, CardData.CardSubType.MULE_PLUS]:
			if mount_counts.has(msub):
				parts.append("%s ×%d" % [CardData.get_type_name(msub), mount_counts[msub]])
				tip_parts.append("%s：%s" % [CardData.get_type_name(msub), CardData.get_description(msub)])
		_add_equip_row(-1, "坐骑：" + " / ".join(parts), "\n".join(tip_parts))
		equip_rows += 1
	if equip_rows == 0:
		var empty = Label.new()
		empty.text = "（无装备）"
		empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
		_equip_container.add_child(empty)

	# 状态（铁索连环、酒、技能buff等）
	_clear_container(_status_container)
	var has_status = false

	if _player.chained:
		var chain_status = Label.new()
		chain_status.text = "🔗 铁索连环（受属性伤害后传导）"
		chain_status.add_theme_color_override("font_color", Color(0.6, 0.9, 0.8))
		chain_status.add_theme_font_size_override("font_size", 14)
		_status_container.add_child(chain_status)
		has_status = true

	if _player.facedown:
		var facedown_status = Label.new()
		facedown_status.text = "🃏 武将牌反面（下个回合开始前翻回，回合被跳过）"
		facedown_status.add_theme_color_override("font_color", Color(0.9, 0.7, 0.9))
		facedown_status.add_theme_font_size_override("font_size", 14)
		_status_container.add_child(facedown_status)
		has_status = true

	if _player.kneeling:
		var kneel_status = Label.new()
		kneel_status.text = "🙇 下跪状态（不会成为任何效果的目标，无法使用或打出任何牌，手牌上限固定为 5）"
		kneel_status.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
		kneel_status.add_theme_font_size_override("font_size", 14)
		_status_container.add_child(kneel_status)
		has_status = true

	# 觉醒状态（史蒂芬·彼特先斯）
	if _player.awoken:
		var awake_status = Label.new()
		var desc = "不能成为【杀】的目标" if _player.awake_choice == 1 else ("不能成为【决斗】的目标" if _player.awake_choice == 2 else "不能成为【南蛮入侵】和【万箭齐发】的目标")
		awake_status.text = "🌟 已觉醒（%s）" % desc
		awake_status.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
		awake_status.add_theme_font_size_override("font_size", 14)
		_status_container.add_child(awake_status)
		has_status = true

	if _wine_stacks > 0:
		var wine_status = Label.new()
		wine_status.text = "🍺 酒 ×%d（下一张杀伤害+%d）" % [_wine_stacks, _wine_stacks]
		wine_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		wine_status.add_theme_font_size_override("font_size", 14)
		_status_container.add_child(wine_status)
		has_status = true

	if not has_status:
		var empty = Label.new()
		empty.text = "（无）"
		empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
		_status_container.add_child(empty)

	# 标记：贤者标记 + 判定区延时锦囊
	_clear_container(_marks_container)
	var has_marks := false

	# 贤者标记（贤者的加护的拼点标记/激活状态）
	if _player.sage_tokens > 0 or _player.sage_activated:
		var sage_mark = Label.new()
		if _player.sage_activated:
			sage_mark.text = "🛡 贤者的加护（已激活：濒死时可弃所有牌复原武将牌并摸四张）"
		else:
			sage_mark.text = "🛡 贤者的加护（贤者标记 %d/3，出牌阶段弃一张手牌拼点赢可得）" % _player.sage_tokens
		sage_mark.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
		sage_mark.add_theme_font_size_override("font_size", 14)
		_marks_container.add_child(sage_mark)
		has_marks = true

	if not _player.judgment_cards.is_empty():
		var j_title = Label.new()
		j_title.text = "⚖ 判定区（后放置的先判定）"
		j_title.add_theme_color_override("font_color", Color(1.0, 0.6, 0.4))
		j_title.add_theme_font_size_override("font_size", 14)
		_marks_container.add_child(j_title)
		for card in _player.judgment_cards:
			var j_label = Label.new()
			j_label.text = "  · %s" % card.card_name
			j_label.add_theme_color_override("font_color", Color(0.95, 0.8, 0.6))
			_marks_container.add_child(j_label)
		has_marks = true

	if not has_marks:
		var mark_label = Label.new()
		mark_label.text = "（暂无标记）"
		mark_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
		_marks_container.add_child(mark_label)

	# 淡入
	modulate = Color(1, 1, 1, 0)
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.12)

func _clear_container(c: Container):
	for child in c.get_children():
		child.queue_free()

# 普通技能行（不可点击）
func _add_skill_label(sk: String, color: Color):
	var skill_label = Label.new()
	skill_label.text = "· %s" % sk
	skill_label.add_theme_color_override("font_color", color)
	skill_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skill_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_skills_container.add_child(skill_label)

# 【下跪】技能行：可点击按钮（发动 / 解除 / 已使用提示）
func _add_skill_btn(skill_key: String, sk: String):
	var btn = Button.new()
	btn.text = "· %s" % sk
	btn.flat = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.add_theme_font_size_override("font_size", 14)
	if _player.general_name == "布鲁斯·萨维奇" and _player.kneel_used and not _player.kneeling:
		# 限定技已使用 → 灰色
		btn.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
	elif _player.general_name == "布鲁斯·萨维奇" and _player.kneeling:
		# 下跪状态中 → 高亮（点击可解除）
		btn.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	elif _player.general_name == "安普提·斯丢皮得" and _player.has_hidden_equip():
		# 【苕】已有暗置装备 → 点击可明置/替换
		btn.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	else:
		# 可发动 → 金色可点击
		btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	btn.pressed.connect(_on_skill_btn_pressed.bind(skill_key))
	_skills_container.add_child(btn)

func _on_skill_btn_pressed(skill_key: String):
	skill_clicked.emit(skill_key)

# 状态变化后刷新（下跪发动/解除后技能颜色、状态区需要更新）
func refresh():
	_populate()

# 装备行：只显示名字的按钮，悬停浮现效果描述；点击发出 equip_clicked（sub 为 -1 时不可点击）
func _add_equip_row(sub: int, label_text: String, tooltip_text: String):
	var btn = Button.new()
	btn.text = label_text
	btn.flat = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_color_override("font_color", Color(0.9, 0.9, 0.6))
	btn.add_theme_font_size_override("font_size", 14)
	_equip_container.add_child(btn)
	if sub >= 0:
		btn.pressed.connect(_on_equip_btn_pressed.bind(sub))
	if tooltip_text != "":
		btn.mouse_entered.connect(_show_tooltip.bind(tooltip_text, btn))
		btn.mouse_exited.connect(_hide_tooltip)

func _on_equip_btn_pressed(sub: CardData.CardSubType):
	equip_clicked.emit(sub)

# ---- 悬停效果描述浮层 ----

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

func _on_close():
	_dismiss()

func _on_bg_click(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var panel_rect = $Panel.get_global_rect()
		if not panel_rect.has_point(get_global_mouse_position()):
			_dismiss()

func _dismiss():
	_hide_tooltip()
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.1)
	await tween.finished
	queue_free()
