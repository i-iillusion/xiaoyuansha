# ============================================================
# GameManager.gd — 游戏主控
# 五人局 + 攻击距离 + 点击头像选目标出牌
# ============================================================
class_name GameManager
extends Node

signal game_started()
signal game_over(winner_identity: String)

@export var player_count: int = 5
@export var auto_start: bool = true

# 主菜单选中的武将（玩家0 使用），静态变量跨场景保留；直接加载游戏（测试）时默认凯文·罗本
static var selected_general: String = "凯文·罗本"
# 主菜单选中的对局人数（1V1=2 / 5人标准=5），静态跨场景保留；直接加载默认 5 人
static var selected_players: int = 5
# 随机身份：true = 身份牌洗牌随机分配（主公仍开局公开）；false = 固定按座位（主公/忠臣/反贼/反贼/内奸）
static var random_identity: bool = true
# 随机武将：true = 所有玩家（含玩家0）从已实现武将里随机选；false = 玩家0用主菜单选择、其余稻草人
static var random_general: bool = true

var players: Array[Player] = []
var deck: Deck
var turn_manager: TurnManager
# 武器/防具唯一性管理（每种装备全场仅一张，装备过即永久占用）
var equipment_pool: EquipmentPool

# --- UI 引用（场景提供）---
@onready var _debug_label: Label = $UI/DebugLabel
@onready var _log_label: Label = $UI/LogLabel
@onready var _countdown_label: Label = $UI/CountdownLabel

# ---- 倒计时（出牌阶段/响应弹窗）----
# 每步倒计时：出牌/响应时重置为 30 秒
var _step_remaining: float = 0.0
# 整局通用储备：30 秒，只扣不加（每步 30 秒耗尽后开始扣）
var _bank_remaining: float = 30.0
var _countdown_active: bool = false
var _countdown_on_timeout: Callable = Callable()
# 实时日志显示剩余时间（5 秒后消失）
var _log_remaining: float = 0.0
const STEP_SECONDS: float = 30.0
const BANK_SECONDS: float = 30.0
@onready var _bottom_bar: ColorRect = $UI/BottomBar
@onready var _self_info_container: VBoxContainer = $UI/BottomBar/SelfInfo
@onready var _play_area_container: VBoxContainer = $UI/BottomBar/PlayArea
@onready var _quick_play_container: VBoxContainer = $UI/BottomBar/QuickPlay
@onready var _detail_popup_root: ColorRect = $UI/DetailPopup

# 四周玩家位置锚点
@onready var _pos_left: Control = $UI/PlayerPosLeft
@onready var _pos_top_left: Control = $UI/PlayerPosTopLeft
@onready var _pos_top_right: Control = $UI/PlayerPosTopRight
@onready var _pos_right: Control = $UI/PlayerPosRight
@onready var _pos_top: Control = $UI/PlayerPosTop
var _player_positions: Array[Control] = []

# --- 自建 UI 元素 ---
var _play_btn: Button
var _end_play_btn: Button
var _cancel_target_btn: Button
var _confirm_target_btn: Button

# 其他玩家的面板
var _other_player_panels: Array[Control] = []
var _self_info_panel: Control

var _selector_scene = preload("res://Scenes/CardSelector.tscn")

# 目标选择模式状态
var _is_targeting: bool = false
var _targeting_card_sub: CardData.CardSubType = -1

# 铁索连环选择模式（1-2 名目标）
var _is_iron_chain_targeting: bool = false
var _iron_chain_targets: Array[Player] = []

# 方天画戟多目标选择模式（攻击范围内任意数量目标）
var _is_multi_targeting: bool = false
var _multi_targets: Array[Player] = []

# 【贤者的加护】拼点目标选择模式
var _is_sage_targeting: bool = false

# 无懈可击响应测试钩子（正常游戏不设置）：返回 true = 玩家0打出无懈
var _nullify_override: Callable = Callable()

# 舍己为人响应测试钩子（正常游戏不设置）：返回 true = 玩家0打出舍己为人
var rule_scheduler = RuleScheduler.new()
var _sacrifice_override: Callable = Callable()

# AOE 响应测试钩子（正常游戏不设置，南蛮/万箭）：返回 true = 玩家0打出响应牌
var _aoe_override: Callable = Callable()

# 烈火盾测试钩子（正常游戏不设置）：返回 true = 玩家0流失 1 点体力代替失去牌
var _liehuo_override: Callable = Callable()

# 灾厄袍转移目标测试钩子（正常游戏不设置）：返回目标 Player 或 "cancel"
var _calamity_robe_target_override: Callable = Callable()

# 贤者的加护濒死保命测试钩子（正常游戏不设置）：返回 true = 使用保命（弃所有牌复原摸四张）
var _sage_save_override: Callable = Callable()

# 凯文·罗本【你个壊货】发动测试钩子（正常游戏不设置）：返回 true = 发动拼点
var _kaiwen_override: Callable = Callable()

# 选牌区域测试钩子（正常游戏不设置，顺/拆）：返回 "hand" / "equip" / "judgment" / "cancel"
var _zone_pick_override: Callable = Callable()

# 装备选择测试钩子（正常游戏不设置，顺/拆选装备槽）：返回槽位名如 "armor" / "cancel"
var _equip_pick_override: Callable = Callable()

# 【下跪】确认弹窗结果信号（独立 signal，避免与响应流程 _response_ready 串线）
signal _kneel_cfm_result(result: bool)

# 短提示（居中浮层，自动淡出）
var _toast_label: Label
var _toast_remaining: float = 0.0

# 劣马转移目标测试钩子（正常游戏不设置）：返回目标 Player 或 "cancel"
var _minus_mule_target_override: Callable = Callable()
var _plus_mule_target_override: Callable = Callable()

# 武器替换确认测试钩子（正常游戏不设置）：返回 true = 玩家0同意替换武器
var _weapon_replace_override: Callable = Callable()

# 丈八蛇矛流失测试钩子（正常游戏不设置）：返回 0-3（流失的体力数）
var _zhangba_override: Callable = Callable()

# 雌雄双股剑测试钩子（正常游戏不设置）：
# _chixiong_activate_override：返回 true = 使用者（玩家0）发动雌雄双股剑
# _chixiong_target_override：返回 true = 目标（玩家0）选择弃一张手牌，false = 令使用者摸牌
var _chixiong_activate_override: Callable = Callable()
var _chixiong_target_override: Callable = Callable()

# 寒冰剑测试钩子（正常游戏不设置）：返回 true = 玩家0 发动寒冰剑（防止伤害弃两张）
var _ice_sword_override: Callable = Callable()

# 贯石斧测试钩子（正常游戏不设置）：返回 true = 玩家0 发动贯石斧（弃坐骑强制命中）
var _guanshi_override: Callable = Callable()

# 贯石斧弃马测试钩子（正常游戏不设置）：返回要弃置的坐骑槽位（如 "mount_1"）
var _guanshi_mount_override: Callable = Callable()

# 出闪测试钩子（正常游戏不设置）：返回 true = 响应者打出【闪】（对任意响应者生效，含 AI）
var _dodge_override: Callable = Callable()

# 目标确认弹窗测试钩子（正常游戏不设置）：返回 true = 玩家0确认出牌
var _target_confirm_override: Callable = Callable()

# 命运之刃测试钩子（正常游戏不设置）：返回 true = 玩家0弃置命运之刃防止致命伤害
var _fate_blade_override: Callable = Callable()

# 勾镰爪测试钩子（正常游戏不设置）：返回要获得的坐骑槽位（如 "mount_1"），"cancel" = 放弃发动
var _gou_lian_slot_override: Callable = Callable()

# 【下跪】确认弹窗测试钩子（正常游戏不设置）：返回 true = 发动/解除，false = 取消
var _kneel_override: Callable = Callable()

# 猜拳拼点测试钩子（正常游戏不设置）：返回指定玩家出的拳（0=石头 1=剪刀 2=布）
var _rps_override: Callable = Callable()

# 噬血之刃测试钩子（正常游戏不设置）：返回 true = 玩家0发动噬血之刃（拼点）
var _bloodthirsty_override: Callable = Callable()

# 灾厄剑转移测试钩子（正常游戏不设置）：返回目标 Player 或 "cancel" = 放弃转移
var _calamity_target_override: Callable = Callable()

# 濒死自救测试钩子（正常游戏不设置）：返回 true = 玩家0使用【桃】自救（没桃照样用不了）
var _dying_peach_override: Callable = Callable()

# 比尔·盖伊测试钩子（正常游戏不设置）：
# _shensu_override：返回 true = 发动【神速】；_shensu_option_override：返回 1/2 = 选哪项；
# _shensu_target_override：神速杀目标玩家（Player 对象，null=取消）
# _gay_x_override：返回 X = 【Gay】弃牌数（0=取消）
var _shensu_override: Callable = Callable()
var _shensu_option_override: Callable = Callable()
var _shensu_target_override: Callable = Callable()
var _gay_x_override: Callable = Callable()

# 【是~啊~】测试钩子（正常游戏不设置）：返回 "skill"（发动，流失体力不消耗手牌）/ "card"（不发动，照常消耗）/ "cancel"（取消，视为没有打出）
var _yes_ah_override: Callable = Callable()
# 【苕】测试钩子（正常游戏不设置）：
# _sao_type_override：返回 "weapon" / "armor" / "mount" / "cancel"（暗置类型选择）
# _sao_reveal_override：返回 true = 玩家0同意明置（明置时机询问 / 抢先明置）
# _sao_reveal_sub_override：返回要明置的具体装备 CardSubType（如 CardData.CardSubType.ICE_SWORD），-1 = 取消
# _sao_menu_override：已暗置时菜单选择，0 = 明置 / 1 = 替换 / -1 = 取消
var _sao_type_override: Callable = Callable()
var _sao_reveal_override: Callable = Callable()
var _sao_reveal_sub_override: Callable = Callable()
var _sao_menu_override: Callable = Callable()

# 【是~啊~】本张锦囊是否已激活技能（激活后消耗手牌改为流失体力）
var _yes_ah_active: bool = false
# 【苕】明置询问：同一个行动窗口内只问一次
var _reveal_ask_pending: bool = true

# ============================
#  阵亡 / 胜负状态
# ============================
# 游戏是否已结束（胜负已分）：结束弹窗显示后不再推进回合
var _game_over: bool = false
var _game_over_overlay: Control = null
# 已走完阵亡管线的角色（防重复处理：一名角色一局只阵亡一次）
var _dead_processed: Array[Player] = []
# 跳过阵亡角色回合时的重入保护（next_turn 会同步触发 START 阶段回调）
var _skipping_dead: bool = false

# 【装逼】（史蒂芬·彼特先斯）：点击头像 → 详情弹窗 → 技能发动 + 目标选择模式
var _is_zhuangbi_targeting: bool = false
var _zhuangbi_blocked_this_phase: bool = false
var _zhuangbi_targets: Array[Player] = []

# 【拍胸脯】测试钩子（正常游戏不设置）：返回 true = 玩家0发动【拍胸脯】（要求伤害来源弃一张手牌）
var _paixiong_override: Callable = Callable()
# 【装逼】再发动测试钩子（正常游戏不设置）：返回 true = 玩家0在赢局后再次使用【装逼】
var _zhuangbi_again_override: Callable = Callable()
# 【霸王】决斗响应测试钩子（正常游戏不设置）：返回 true = 玩家0响应决斗时出【杀】（第一次出牌询问）
var _duel_respond_override: Callable = Callable()
# 【霸王】决斗第二张杀测试钩子（正常游戏不设置）：返回 true = 玩家0响应决斗打出第一张杀后继续出第二张
var _duel_second_override: Callable = Callable()
# 【校园霸主】（杰基·斯特朗）：目标选择模式
var _is_campus_targeting: bool = false                          
# 【神速】（比尔·盖伊）：回合开始选项1 的杀目标选择中
var _is_shensu_targeting: bool = false
# 【Gay】（比尔·盖伊）：回复目标选择中
var _is_gay_targeting: bool = false
# 【Gay】本回合是否已使用（出牌阶段限一次）
var _gay_used: bool = false
# 【觉醒】三选一测试钩子（正常游戏不设置）：返回 1 / 2 / 3（觉醒效果选择）
var _awaken_pick_override: Callable = Callable()

# ---- 【烂忠厚】（麦克斯·欧尼斯特）：出牌阶段限一次，弃 X 张牌交换两名角色的 X 个装备区域 ----
var _lanzhonghou_used: bool = false                 # 本回合是否已使用（每回合重置）
var _is_lanzhonghou_targeting: bool = false         # 选择两名角色中
var _lanzhonghou_selected: Array[Player] = []       # 已选角色（0/1 个，选满 2 个进入区域选择）
var _lanzhonghou_pending: Array = []                # 待执行交换（确认后统一结算）：{a, slot_a, b, slot_b, ok}
# 测试钩子（正常游戏不设置）：
var _lanzhonghou_char_override: Callable = Callable()    # 返回 Array[Player] = [A, B]（两名角色）
var _lanzhonghou_zone_override: Callable = Callable()    # 返回 "weapon"/"armor"/"mount"/"done"/"cancel"（区域选择循环）
var _lanzhonghou_mount_override: Callable = Callable()   # 返回 {"a": 槽位, "b": 槽位} 或 "cancel"（坐骑槽选择）

# ---- 【没用】（麦克斯·欧尼斯特）：回合开始阶段摸一张牌并跳过自己的一个阶段 ----
var _is_meiyong_targeting: bool = false             # 选择目标中
var _meiyong_option: int = -1                       # 0=判定 / 1=摸牌 / 2=出牌
# 测试钩子（正常游戏不设置）：
var _meiyong_override: Callable = Callable()             # 返回 true = 发动【没用】
var _meiyong_option_override: Callable = Callable()      # 返回 0/1/2（三选一）
var _meiyong_target_override: Callable = Callable()      # 返回 Player（目标角色）

# 通用按钮选择弹窗结果（返回选中索引，-1 = 取消）
signal _choice_pick_result(idx: int)
# 【没用】目标选择结果（返回 Player，null = 取消）
signal _meiyong_pick_result(target: Player)                       
signal _shensu_pick_result(target: Player)                       
# 【烂忠厚】区域选择结果（"weapon"/"armor"/"mount"/"done"/"cancel"）
signal _lanzhonghou_zone_result(zone: String)
# 【烂忠厚】坐骑槽选择结果（返回槽位，"cancel" = 取消）
signal _lanzhonghou_mount_result(slot: String)

# 【苕】可明置的装备列表（武器/防具/马）
const SAO_WEAPON_SUBS: Array[int] = [
	CardData.CardSubType.LIANNU, CardData.CardSubType.ZHUGE_LIANNU, CardData.CardSubType.QINGLONG_BLADE,
	CardData.CardSubType.ZHANGBA_SPEAR, CardData.CardSubType.CHIXIONG_SHUANGGU, CardData.CardSubType.ICE_SWORD,
	CardData.CardSubType.QINGGANG_SWORD, CardData.CardSubType.GUDING_BLADE, CardData.CardSubType.GUANSHI_AXE,
	CardData.CardSubType.QILING_BOW, CardData.CardSubType.POFENG_SPEAR, CardData.CardSubType.FANGTIAN_HALBERD,
	CardData.CardSubType.FATE_BLADE, CardData.CardSubType.GOU_LIAN_CLAW, CardData.CardSubType.BLOODTHIRSTY_BLADE,
	CardData.CardSubType.CALAMITY_SWORD, CardData.CardSubType.HEAL_STAFF, CardData.CardSubType.RAGING_AXE,
	CardData.CardSubType.SOUL_BLADE,
]
const SAO_ARMOR_SUBS: Array[int] = [
	CardData.CardSubType.RENWANG_DUN, CardData.CardSubType.BAIHUA_SKIRT, CardData.CardSubType.QIXING_PAO,
	CardData.CardSubType.SILVER_LION, CardData.CardSubType.SHENGGUANG_BAIYI, CardData.CardSubType.BAGUA_ZHEN,
	CardData.CardSubType.TENGJIA, CardData.CardSubType.ZHANQI, CardData.CardSubType.LIEHUO_SHIELD,
	CardData.CardSubType.QINGGANG_SHIELD, CardData.CardSubType.THORN_ARMOR, CardData.CardSubType.CALAMITY_ROBE,
	CardData.CardSubType.SAGE_PROTECTION,
]
const SAO_MOUNT_SUBS: Array[int] = [
	CardData.CardSubType.MOUNT_PLUS, CardData.CardSubType.MOUNT_MINUS,
	CardData.CardSubType.MULE_PLUS, CardData.CardSubType.MULE_MINUS,
]

# 摄魂刀测试钩子（正常游戏不设置）：
# _soul_blade_activate_override：返回 true = 玩家0发动摄魂刀拼点
# _soul_blade_discard_override：返回 true = 玩家0弃手牌令目标翻面
var _soul_blade_activate_override: Callable = Callable()
var _soul_blade_discard_override: Callable = Callable()

# 猜拳拼点（石头/剪刀/布）
const RPS_ROCK = 0
const RPS_PAPER = 1
const RPS_SCISSORS = 2
# 拼点结果（发起者视角）
const RPS_WIN = 1
const RPS_DRAW = 0
const RPS_LOSE = -1

func _ready():
	# 主菜单选择的对局人数（1V1=2 / 5人标准=5）
	player_count = GameManager.selected_players
	deck = Deck.new()
	equipment_pool = EquipmentPool.new()

	turn_manager = TurnManager.new()
	turn_manager.player_count = player_count
	add_child(turn_manager)
	turn_manager.phase_changed.connect(_on_phase_changed)
	turn_manager.turn_ended.connect(_on_turn_ended)
	game_over.connect(_on_game_over)

	_player_positions = [_pos_left, _pos_top_left, _pos_top_right, _pos_right]
	# 位置容器只是锚点（不拦鼠标，只有面板接收点击）——避免空容器覆盖拦截点击
	for p in _player_positions:
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pos_top.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_create_ui()

	if auto_start:
		start_game()

# ============================
#  UI 构建
# ============================

func _create_ui():
	_debug_label.text = "初始化中..."
	_countdown_label.text = ""
	_log_label.text = ""

	# 底栏 - 左侧：己方状态
	_self_info_panel = _create_player_info_panel(_self_info_container, null)
	_self_info_container.mouse_filter = 0

	# 底栏 - 中间：出牌区
	_play_btn = Button.new()
	_play_btn.text = "出牌"
	_play_btn.size = Vector2(120, 40)
	_play_btn.pressed.connect(_on_play_btn_pressed)
	_play_btn.visible = false
	_play_area_container.add_child(_play_btn)

	_end_play_btn = Button.new()
	_end_play_btn.text = "结束出牌"
	_end_play_btn.size = Vector2(120, 40)
	_end_play_btn.pressed.connect(_on_end_play_pressed)
	_end_play_btn.visible = false
	_play_area_container.add_child(_end_play_btn)

	# 取消目标选择按钮（平时隐藏）
	_cancel_target_btn = Button.new()
	_cancel_target_btn.text = "取消选择"
	_cancel_target_btn.size = Vector2(120, 40)
	_cancel_target_btn.pressed.connect(_on_cancel_target_pressed)
	_cancel_target_btn.visible = false
	_play_area_container.add_child(_cancel_target_btn)

	# 多目标确认按钮（方天画戟，平时隐藏）
	_confirm_target_btn = Button.new()
	_confirm_target_btn.text = "确认出牌（0 名目标）"
	_confirm_target_btn.size = Vector2(160, 40)
	_confirm_target_btn.pressed.connect(_on_confirm_multi_target)
	_confirm_target_btn.visible = false
	_confirm_target_btn.disabled = true
	_play_area_container.add_child(_confirm_target_btn)

	# 底栏 - 右侧：快捷出牌（占位）
	var quick_title = Label.new()
	quick_title.text = "快捷出牌"
	quick_title.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	quick_title.add_theme_font_size_override("font_size", 12)
	_quick_play_container.add_child(quick_title)

	var quick_placeholder = Label.new()
	quick_placeholder.text = "（待实现）"
	quick_placeholder.add_theme_color_override("font_color", Color(0.35, 0.35, 0.45))
	quick_placeholder.add_theme_font_size_override("font_size", 11)
	_quick_play_container.add_child(quick_placeholder)

# ============================
#  玩家信息面板
# ============================

func _create_player_info_panel(parent: Node, player: Player) -> Control:
	var panel = Control.new()
	panel.custom_minimum_size = Vector2(200, 100)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	parent.add_child(panel)
	# 四周位置容器（非 Container）：面板居中于容器（底栏 SelfInfo 是 VBox 由容器管理）
	if not parent is Container:
		panel.anchor_left = 0.5
		panel.anchor_right = 0.5
		panel.anchor_top = 0.5
		panel.anchor_bottom = 0.5
		panel.offset_left = -100
		panel.offset_right = 100
		panel.offset_top = -50
		panel.offset_bottom = 50

	var avatar_bg = ColorRect.new()
	avatar_bg.size = Vector2(56, 56)
	avatar_bg.position = Vector2(4, 4)
	avatar_bg.color = Color(0.15, 0.15, 0.22)
	avatar_bg.mouse_filter = 2
	panel.add_child(avatar_bg)

	var avatar_label = Label.new()
	avatar_label.text = "🦊"
	avatar_label.position = Vector2(8, 4)
	avatar_label.size = Vector2(48, 56)
	avatar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	avatar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	avatar_label.add_theme_font_size_override("font_size", 32)
	avatar_label.mouse_filter = 2
	panel.add_child(avatar_label)

	var name_label = Label.new()
	name_label.position = Vector2(64, 2)
	name_label.size = Vector2(140, 22)
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.85))
	name_label.mouse_filter = 2
	panel.add_child(name_label)

	var hp_label = Label.new()
	hp_label.position = Vector2(64, 26)
	hp_label.size = Vector2(140, 20)
	hp_label.add_theme_font_size_override("font_size", 14)
	hp_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	hp_label.mouse_filter = 2
	panel.add_child(hp_label)

	var hand_label = Label.new()
	hand_label.position = Vector2(64, 48)
	hand_label.size = Vector2(140, 20)
	hand_label.add_theme_font_size_override("font_size", 13)
	hand_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.6))
	hand_label.mouse_filter = 2
	panel.add_child(hand_label)

	var identity_label = Label.new()
	identity_label.position = Vector2(64, 68)
	identity_label.size = Vector2(140, 20)
	identity_label.add_theme_font_size_override("font_size", 11)
	identity_label.add_theme_color_override("font_color", Color(0.8, 0.6, 0.4))
	identity_label.mouse_filter = 2
	panel.add_child(identity_label)

	var hp_bar_bg = ColorRect.new()
	hp_bar_bg.position = Vector2(64, 90)
	hp_bar_bg.size = Vector2(120, 8)
	hp_bar_bg.color = Color(0.15, 0.15, 0.15)
	hp_bar_bg.mouse_filter = 2
	panel.add_child(hp_bar_bg)

	var hp_bar = ColorRect.new()
	hp_bar.position = Vector2(64, 90)
	hp_bar.size = Vector2(120, 8)
	hp_bar.color = Color(0.25, 0.55, 0.25)
	hp_bar.mouse_filter = 2
	panel.add_child(hp_bar)

	# 酒标记（默认隐藏）
	var wine_indicator = Label.new()
	wine_indicator.text = "🍺"
	wine_indicator.position = Vector2(4, 40)
	wine_indicator.size = Vector2(20, 20)
	wine_indicator.add_theme_font_size_override("font_size", 14)
	wine_indicator.mouse_filter = 2
	wine_indicator.visible = false
	panel.add_child(wine_indicator)

	# 连环标记（默认隐藏）
	var chain_indicator = Label.new()
	chain_indicator.text = "🔗"
	chain_indicator.position = Vector2(28, 40)
	chain_indicator.size = Vector2(20, 20)
	chain_indicator.add_theme_font_size_override("font_size", 14)
	chain_indicator.mouse_filter = 2
	chain_indicator.visible = false
	panel.add_child(chain_indicator)

	# 武将牌反面标记（摄魂刀翻面，默认隐藏）
	var facedown_indicator = Label.new()
	facedown_indicator.text = "🃏"
	facedown_indicator.position = Vector2(52, 40)
	facedown_indicator.size = Vector2(20, 20)
	facedown_indicator.add_theme_font_size_override("font_size", 14)
	facedown_indicator.mouse_filter = 2
	facedown_indicator.visible = false
	panel.add_child(facedown_indicator)

	# 【下跪】状态标记（布鲁斯·萨维奇，默认隐藏）
	var kneeling_indicator = Label.new()
	kneeling_indicator.text = "🙇"
	kneeling_indicator.position = Vector2(76, 40)
	kneeling_indicator.size = Vector2(20, 20)
	kneeling_indicator.add_theme_font_size_override("font_size", 14)
	kneeling_indicator.mouse_filter = 2
	kneeling_indicator.visible = false
	panel.add_child(kneeling_indicator)

	# 判定牌数量标记（延时锦囊，默认隐藏）
	var judgment_indicator = Label.new()
	judgment_indicator.text = ""
	judgment_indicator.position = Vector2(4, 62)
	judgment_indicator.size = Vector2(56, 18)
	judgment_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	judgment_indicator.add_theme_font_size_override("font_size", 11)
	judgment_indicator.add_theme_color_override("font_color", Color(1.0, 0.55, 0.35))
	judgment_indicator.mouse_filter = 2
	panel.add_child(judgment_indicator)

	panel.set_meta("avatar_label", avatar_label)
	panel.set_meta("name_label", name_label)
	panel.set_meta("hp_label", hp_label)
	panel.set_meta("hand_label", hand_label)
	panel.set_meta("identity_label", identity_label)
	panel.set_meta("hp_bar", hp_bar)
	panel.set_meta("wine_indicator", wine_indicator)
	panel.set_meta("chain_indicator", chain_indicator)
	panel.set_meta("facedown_indicator", facedown_indicator)
	panel.set_meta("kneeling_indicator", kneeling_indicator)
	panel.set_meta("judgment_indicator", judgment_indicator)
	panel.set_meta("player", player)

	panel.gui_input.connect(_on_player_panel_click.bind(panel))

	return panel

func _update_player_panel(panel: Control, player: Player):
	if not panel or not player:
		return

	var name_label: Label = panel.get_meta("name_label")
	var hp_label: Label = panel.get_meta("hp_label")
	var hand_label: Label = panel.get_meta("hand_label")
	var identity_label: Label = panel.get_meta("identity_label")
	var hp_bar: ColorRect = panel.get_meta("hp_bar")

	name_label.text = "%s · %s" % [player.player_name, player.general_name]
	hp_label.text = "❤ %d/%d" % [player.hp, player.max_hp]
	hand_label.text = "手牌：%d 张" % player.hand_size()
	# 身份显示：主公开局公开；其他身份阵亡（翻开）后显示，否则隐藏为【?】
	if player.identity == "":
		identity_label.text = ""
	elif player.identity_revealed:
		identity_label.text = "【%s】" % player.identity
	else:
		identity_label.text = "【?】"
	# 身份颜色：主公金 / 忠臣绿 / 反贼红 / 内奸紫（未公开灰色）
	match player.identity:
		"主公":
			identity_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
		"忠臣":
			identity_label.add_theme_color_override("font_color", Color(0.45, 0.9, 0.45))
		"反贼":
			identity_label.add_theme_color_override("font_color", Color(0.95, 0.4, 0.35))
		"内奸":
			identity_label.add_theme_color_override("font_color", Color(0.75, 0.5, 0.95))
		_:
			identity_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	# 阵亡：面板置灰
	panel.modulate = Color(0.45, 0.45, 0.45, 1) if not player.is_alive() else Color.WHITE

	var ratio = float(player.hp) / float(player.max_hp)
	hp_bar.size.x = 120 * ratio
	if ratio > 0.5:
		hp_bar.color = Color(0.25, 0.55, 0.25)
	elif ratio > 0.25:
		hp_bar.color = Color(0.6, 0.5, 0.15)
	else:
		hp_bar.color = Color(0.55, 0.2, 0.15)

	# 更新酒标记
	var wine_indicator: Label = panel.get_meta("wine_indicator")
	var is_current = (turn_manager.current_player_idx == player.seat_index)
	wine_indicator.visible = is_current and player.wine_stacks > 0

	# 更新连环标记
	var chain_indicator: Label = panel.get_meta("chain_indicator")
	chain_indicator.visible = player.chained

	# 更新武将牌反面标记
	var facedown_indicator: Label = panel.get_meta("facedown_indicator")
	facedown_indicator.visible = player.facedown

	# 更新【下跪】状态标记
	var kneeling_indicator: Label = panel.get_meta("kneeling_indicator")
	kneeling_indicator.visible = _is_kneeling(player)

	# 更新判定牌数量标记
	var judgment_indicator: Label = panel.get_meta("judgment_indicator")
	if player.judgment_cards.is_empty():
		judgment_indicator.text = ""
	else:
		judgment_indicator.text = "⚖×%d" % player.judgment_cards.size()

	panel.set_meta("player", player)

# ============================
#  游戏流程
# ============================

func start_game():
	# 身份分配：标准局（5人：主公/忠臣/反贼/反贼/内奸）；1V1 无身份
	# random_identity = true 时身份牌洗牌随机分配（主公仍开局公开）
	var identities: Array = []
	if player_count >= 3:
		var full_identities = ["主公", "忠臣", "反贼", "反贼", "内奸"]
		identities = full_identities.slice(0, player_count)
		if random_identity:
			identities.shuffle()
	else:
		identities = ["", ""]

	for i in player_count:
		var p = Player.new()
		p.player_name = "玩家 %d" % (i + 1)
		p.seat_index = i
		p.set_total_players(player_count)
		p.identity = identities[i] if i < identities.size() else ""
		# 身份公开：主公开局公开，其余身份阵亡（翻开）后才显示
		p.identity_revealed = (p.identity == "主公")
		# 武将分配：random_general = true 时所有玩家（含玩家0）随机；否则玩家0用主菜单选择、其余稻草人
		if random_general:
			p.general_name = GeneralData.get_random_general()
		else:
			p.general_name = GameManager.selected_general if i == 0 else "稻草人"
		p.max_hp = GeneralData.get_max_hp(p.general_name)
		# 性别：稻草人与凯文·罗本均为男性
		p.gender = "male"
		add_child(p)
		players.append(p)
		# 【觉醒】监听手牌变化（史蒂芬·彼特先斯：手牌为 0 时立即觉醒）
		p.hand_updated.connect(_on_hand_updated.bind(p))

	for p in players:
		_draw_blank_cards(p, 4)

	_update_player_panel(_self_info_panel, players[0])

	for i in range(player_count - 1):
		var seat = i + 1
		if seat < players.size():
			# 1V1：对方在正上方（玩家对面）；多人按四周布局
			var pos_node = _pos_top if player_count == 2 else _player_positions[i]
			var panel = _create_player_info_panel(pos_node, players[seat])
			_update_player_panel(panel, players[seat])
			_other_player_panels.append(panel)

	_sync_all_ui()
	_update_debug("—— 校园杀 %d 人局开始 ——" % player_count)
	if player_count >= 3:
		var seat_desc = "座位："
		for i in player_count:
			seat_desc += "%d→%s | " % [i, identities[i]]
		_update_debug(seat_desc)
	_update_debug("距离规则：武器无攻击距离，4 个坐骑槽位自由搭配 +1/-1 马")
	_update_debug("武器规则：每种武器/防具全场仅一张，装备过即永久占用")
	turn_manager.start_game()
	game_started.emit()

# ---- 阶段响应 ----

func _on_phase_changed(old_phase: TurnManager.Phase, new_phase: TurnManager.Phase, pid: int):
	# 胜负已分：不再推进任何阶段逻辑（当前结算链由各调用方的 _game_over 检查自行收尾）
	if _game_over:
		return
	match new_phase:
		TurnManager.Phase.START:
			# 阵亡角色跳过自己的回合：推进到下一位存活角色
			# （next_turn 会同步触发 START 回调 → 用 _skipping_dead 挡重入；
			#   胜负判定保证至少还有一名对手存活，guard 仅兜底防死循环）
			if _skipping_dead:
				return
			_skipping_dead = true
			var guard := 0
			while guard < player_count and not players[turn_manager.current_player_idx].is_alive():
				turn_manager.next_turn()
				guard += 1
				if _game_over:
					_skipping_dead = false
					return
			_skipping_dead = false
			_do_start(turn_manager.current_player_idx)
		TurnManager.Phase.JUDGE:   _do_judge(pid)
		TurnManager.Phase.DRAW:    _do_draw(pid)
		TurnManager.Phase.PLAY:
			if old_phase != TurnManager.Phase.WAITING:
				_zhuangbi_blocked_this_phase = false
			_do_play(pid)
		TurnManager.Phase.DISCARD: _do_discard(pid)
		TurnManager.Phase.END:     _do_end(pid)

func _do_start(pid: int):
	var p = players[pid]
	# 武将牌反面：翻回正面并跳过本回合（不摸牌/不出牌/不弃牌）
	if p.facedown:
		p.facedown = false
		_update_debug("%s 武将牌翻回正面，本回合被跳过！" % p.player_name)
		turn_manager.skip_full_turn = true
	_update_debug("%s 回合开始（手牌 %d 张）" % [p.player_name, p.hand_size()])
	# 每回合重置回合级标志（治疗权杖桃计数 / 酒层数——狂暴战斧装备者的酒跨回合保留）
	_reset_turn_flags()
	# 【神速】（比尔·盖伊）：回合开始阶段二选一（跳过判定+视为出杀 / 跳出牌弃牌+摸牌减益）
	# （武将牌反面跳过整回合时不询问）
	if p.general_name == "比尔·盖伊" and p.is_alive() and not turn_manager.skip_full_turn:
		await _maybe_shensu(p)
	# 【没用】（麦克斯·欧尼斯特）：回合开始阶段可摸一张牌并选择跳过自己的一个阶段
	# （武将牌反面跳过整回合时不询问）
	if p.general_name == "麦克斯·欧尼斯特" and p.is_alive() and not turn_manager.skip_full_turn:
		await _maybe_meiyong(p)
	_sync_all_ui()
	turn_manager.advance_phase()

# 回合开始统一重置（测试可直接调用）：治疗权杖桃计数全清；酒层数——未装备狂暴战斧的玩家清零
func _reset_turn_flags():
	for pl in players:
		pl.heal_staff_peach_used = false
		pl.shensu_used_this_turn = false  # 【神速】选2 标记每回合重置
		if pl.get_weapon() != CardData.CardSubType.RAGING_AXE:
			pl.wine_stacks = 0
	_lanzhonghou_used = false  # 【烂忠厚】每回合限一次
	_gay_used = false  # 【Gay】每回合限一次

# 判定阶段：结算判定区的延时锦囊（后放置的先判定）
# 无花色点数 → 判定必定生效
func _do_judge(pid: int):
	var p = players[pid]
	# 【神速】（比尔·盖伊）选项1：跳过判定阶段（判定区延时锦囊保留，下回合再判）
	if turn_manager.skip_judge_phase:
		turn_manager.skip_judge_phase = false
		_update_debug("%s 发动【神速】：跳过判定阶段（判定区 %d 张牌保留）" % [p.player_name, p.judgment_cards.size()])
		_sync_all_ui()
		turn_manager.advance_phase()
		return
	# 【没用】（麦克斯·欧尼斯特）授予的判定阶段：跳过自己的判定，目标角色立刻进行判定阶段
	# （其乐不思蜀/兵粮寸断失效，闪电/火烧连营正常生效）
	if turn_manager.granted_judge_target_idx >= 0:
		var target = players[turn_manager.granted_judge_target_idx]
		turn_manager.granted_judge_target_idx = -1
		if target.is_alive():
			await _run_judgment(target, true)
		_sync_all_ui()
		turn_manager.advance_phase()
		return
	# 【下跪】：下跪状态不会成为任何效果的目标 → 判定牌不结算（保留，解除后下回合再判定）
	if _is_kneeling(p):
		_update_debug("%s 处于【下跪】状态，跳过判定（判定区 %d 张牌保留）" % [p.player_name, p.judgment_cards.size()])
		_sync_all_ui()
		turn_manager.advance_phase()
		return
	if p.judgment_cards.is_empty():
		_sync_all_ui()
		turn_manager.advance_phase()
		return

	await _run_judgment(p, false)
	_sync_all_ui()
	turn_manager.advance_phase()

# 判定结算循环（抽取公用）：结算角色 p 判定区的全部延时锦囊（后放置的先判定）
# granted=true = 【没用】授予的判定阶段：乐不思蜀/兵粮寸断失效（不触发效果）；闪电/火烧连营正常生效
func _run_judgment(p: Player, granted: bool):
	if granted:
		_update_debug("%s 进行（授予的）判定阶段：判定区 %d 张牌（乐不思蜀/兵粮寸断失效）" % [p.player_name, p.judgment_cards.size()])
	else:
		_update_debug("%s 判定阶段：判定区 %d 张牌（后放置的先判定）" % [p.player_name, p.judgment_cards.size()])

	while not p.judgment_cards.is_empty() and p.is_alive():
		var card = p.judgment_cards.pop_back()
		match card.sub_type:
			CardData.CardSubType.LIGHTNING:
				# 无懈可击：判定生效前询问
				var lt_nullified = await _ask_nullification_chain("%s的【闪电】即将生效，是否打出一张【无懈可击】？" % p.player_name)
				if lt_nullified:
					_update_debug("【闪电】的效果被【无懈可击】抵消")
				else:
					_update_debug("【闪电】判定：必定命中！即将对 %s 造成 3 点雷电伤害" % p.player_name)
					# 规则（朋友设定）：闪电造成的属性伤害无伤害来源（铁索传导随之为无来源）
					await _deal_damage(null, p, 3, EffectChain.DamageType.THUNDER)
			CardData.CardSubType.INDULGENCE:
				if granted:
					# 【没用】授予的判定阶段：乐不思蜀失效（不触发效果）
					_update_debug("【乐不思蜀】在授予的判定阶段失效，不触发效果")
				else:
					var ig_nullified = await _ask_nullification_chain("%s的【乐不思蜀】即将生效，是否打出一张【无懈可击】？" % p.player_name)
					if ig_nullified:
						_update_debug("【乐不思蜀】的效果被【无懈可击】抵消")
					else:
						_update_debug("【乐不思蜀】判定：必定生效！%s 本回合跳过出牌阶段" % p.player_name)
						turn_manager.skip_play_phase = true
			CardData.CardSubType.SUPPLY_SHORTAGE:
				if granted:
					# 【没用】授予的判定阶段：兵粮寸断失效（不触发效果）
					_update_debug("【兵粮寸断】在授予的判定阶段失效，不触发效果")
				else:
					var ss_nullified = await _ask_nullification_chain("%s的【兵粮寸断】即将生效，是否打出一张【无懈可击】？" % p.player_name)
					if ss_nullified:
						_update_debug("【兵粮寸断】的效果被【无懈可击】抵消")
					else:
						_update_debug("【兵粮寸断】判定：必定生效！%s 本回合摸牌阶段少摸一张" % p.player_name)
						turn_manager.supply_shortage_active = true
			CardData.CardSubType.BURNING_CAMP:
				# 无懈可击：判定生效前询问
				var bc_nullified = await _ask_nullification_chain("%s的【火烧连营】即将生效，是否打出一张【无懈可击】？" % p.player_name)
				if bc_nullified:
					_update_debug("【火烧连营】的效果被【无懈可击】抵消")
				else:
					_update_debug("【火烧连营】判定生效！%s 及其左右角色受到 1 点火焰伤害" % p.player_name)
					# 规则（朋友设定）：火烧连营造成的属性伤害无伤害来源（与闪电一致）
					await _resolve_burning_camp_damage(null, p, 1)
					# 蔓延：判定者左右判定区各生成一张火烧连营（已有则不重复）
					var bc_left = players[(p.seat_index + 1) % player_count]
					var bc_right = players[(p.seat_index - 1 + player_count) % player_count]
					_spawn_burning_camp(bc_left, card.source_seat)
					_spawn_burning_camp(bc_right, card.source_seat)
			_:
				_update_debug("%s 的判定牌【%s】无效果" % [p.player_name, card.card_name])
		deck.discard(card)

	# 判定中阵亡 → 剩余判定牌直接进弃牌堆
	if not p.is_alive():
		for c in p.judgment_cards:
			deck.discard(c)
		p.judgment_cards.clear()

func _do_draw(pid: int):
	var p = players[pid]
	# 【没用】（麦克斯·欧尼斯特）授予的摸牌阶段：跳过自己的摸牌，目标角色立刻获得一个摸牌阶段
	if turn_manager.granted_draw_target_idx >= 0:
		var target = players[turn_manager.granted_draw_target_idx]
		turn_manager.granted_draw_target_idx = -1
		if target.is_alive():
			_draw_blank_cards(target, 2)
			_update_debug("【没用】：%s 立刻获得一个摸牌阶段，摸了 2 张牌（手牌 %d 张）" % [target.player_name, target.hand_size()])
		_sync_all_ui()
		turn_manager.advance_phase()
		return
	var draw_count = 2
	# 【英姿】（比尔·盖伊）锁定技：摸牌阶段多摸一张
	if p.general_name == "比尔·盖伊" and p.is_alive():
		draw_count += 1
		_update_debug("%s 发动【英姿】：摸牌阶段多摸一张" % p.player_name)
	if turn_manager.supply_shortage_active:
		turn_manager.supply_shortage_active = false
		draw_count -= 1
		_update_debug("【兵粮寸断】生效，摸牌阶段少摸一张")
	# 【神速】（比尔·盖伊）选项2 的减益结算：非发动回合的摸牌阶段按累计欠账扣减后清零
	# （选2 的当回合摸牌不受影响，减益顺延到之后第一个未发动的回合，一次扣清；下限 0 张）
	if p.general_name == "比尔·盖伊" and not p.shensu_used_this_turn and p.shensu_penalty > 0:
		var owed = p.shensu_penalty
		p.shensu_penalty = 0
		draw_count = maxi(draw_count - owed, 0)
		_update_debug("%s 的【神速】摸牌减益结算：少摸 %d 张（实际摸 %d 张）" % [p.player_name, owed, draw_count])
	_draw_blank_cards(p, draw_count)
	_update_debug("%s 摸了 %d 张牌（手牌 %d 张）" % [p.player_name, draw_count, p.hand_size()])
	_sync_all_ui()
	turn_manager.advance_phase()

func _do_play(pid: int):
	var p = players[pid]
	# 【没用】（麦克斯·欧尼斯特）授予的出牌阶段：跳过自己的出牌，目标角色立刻获得一个出牌阶段
	if turn_manager.granted_play_target_idx >= 0:
		var target = players[turn_manager.granted_play_target_idx]
		turn_manager.granted_play_target_idx = -1
		turn_manager.skip_play_phase = false  # 自己已不出牌，乐不思蜀的跳过效果无意义（已判定消耗）
		if target.is_alive() and target.seat_index == 0:
			# 玩家0 被授予出牌阶段（正常不会出现：麦克斯·欧尼斯特即玩家0，目标必须除自己以外）
			_play_btn.visible = true
			_end_play_btn.visible = true
			_sync_all_ui()
			_refresh_status_line()
			_update_debug("【没用】：你立刻获得一个出牌阶段！")
			return
		# AI 不出牌：立即结束
		_update_debug("【没用】：%s 立刻获得一个出牌阶段（AI 不出牌，立即结束）" % target.player_name)
		_sync_all_ui()
		turn_manager.advance_phase()
		return
	_play_btn.visible = (pid == 0)
	_end_play_btn.visible = (pid == 0)
	_sync_all_ui()
	_refresh_status_line()
	_update_debug("%s 出牌阶段 — 点击「出牌」选择牌型，或「结束出牌」" % p.player_name)

func _do_discard(pid: int):
	var p = players[pid]
	# 跳过出牌阶段时按钮可能仍可见，统一隐藏
	_play_btn.visible = false
	_end_play_btn.visible = false
	_cancel_target_btn.visible = false
	_confirm_target_btn.visible = false
	_is_multi_targeting = false
	_multi_targets.clear()
	_is_sage_targeting = false
	_is_zhuangbi_targeting = false
	_zhuangbi_targets.clear()
	_is_campus_targeting = false
	_is_lanzhonghou_targeting = false
	_lanzhonghou_selected.clear()
	_lanzhonghou_pending.clear()
	_is_meiyong_targeting = false
	var limit = p.hand_limit()
	var excess = p.hand_size() - limit
	if excess > 0:
		if p.hand_limit_bonus > 0:
			_update_debug("%s 弃牌阶段 — 手牌 %d > 上限 %d（体力 %d + 破风枪 %d），弃 %d 张" % [p.player_name, p.hand_size(), limit, p.hp, p.hand_limit_bonus, excess])
		else:
			_update_debug("%s 弃牌阶段 — 手牌 %d > 体力 %d，弃 %d 张" % [p.player_name, p.hand_size(), limit, excess])
		for i in excess:
			# 【烈火盾】：可流失 1 点体力代替弃置这张手牌（弃牌阶段）
			if await _maybe_liehuo_save(p):
				continue
			p.hand.pop_back()
		_sync_all_ui()
	_refresh_status_line()
	turn_manager.advance_phase()

func _do_end(pid: int):
	_play_btn.visible = false
	_end_play_btn.visible = false
	_cancel_target_btn.visible = false
	_confirm_target_btn.visible = false
	_is_targeting = false
	_is_iron_chain_targeting = false
	_iron_chain_targets.clear()
	_is_multi_targeting = false
	_multi_targets.clear()
	_is_sage_targeting = false
	_is_zhuangbi_targeting = false
	_zhuangbi_targets.clear()
	_is_campus_targeting = false
	_is_lanzhonghou_targeting = false
	_lanzhonghou_selected.clear()
	_lanzhonghou_pending.clear()
	_is_meiyong_targeting = false
	_refresh_status_line()
	_update_debug("%s 回合结束" % players[pid].player_name)
	turn_manager.advance_phase()

func _on_turn_ended(pid: int):
	# 胜负已分：不再进入下一回合
	if _game_over:
		return
	turn_manager.next_turn()

# ============================
#  手牌管理
# ============================

func _draw_blank_cards(p: Player, count: int):
	for i in count:
		p.hand.append(null)

# ============================
#  可攻击目标查询
# ============================

func _get_attackable_targets(attacker: Player) -> Array[Player]:
	var targets: Array[Player] = []
	for p in players:
		# 【下跪】：下跪状态不会成为任何效果的目标
		if p != attacker and p.is_alive() and attacker.can_attack(p) and not _is_kneeling(p):
			targets.append(p)
	return targets

# 杀的目标查询：【麒麟弓】无距离限制（任意存活角色）；否则攻击范围内
# 【藤甲】锁定技：不能成为【杀】的目标（杀专属过滤；顺手牵羊/兵粮/火烧等不受影响）
# 【裸奔】锁定技（凯文·罗本）：装备区没有装备时，不能成为【杀】的目标
func _get_strike_targets(attacker: Player) -> Array[Player]:
	var targets: Array[Player]
	if attacker.get_weapon() == CardData.CardSubType.QILING_BOW:
		targets = _get_all_alive_targets(attacker)
	else:
		targets = _get_attackable_targets(attacker)
	var filtered: Array[Player] = []
	for t in targets:
		if t.get_armor() != CardData.CardSubType.TENGJIA and not _is_bare_running(t) and not _awake_blocks(t, 1):
			filtered.append(t)
	return filtered

# 【裸奔】锁定技（凯文·罗本）：装备区没有任何装备时，不能成为【杀】的目标
func _is_bare_running(p: Player) -> bool:
	return p.general_name == "凯文·罗本" and p.equipment.is_empty()

# 【下跪】状态判定（布鲁斯·萨维奇限定技）
func _is_kneeling(p: Player) -> bool:
	return p.general_name == "布鲁斯·萨维奇" and p.kneeling

# 【暴怒】锁定技（布鲁斯·萨维奇）：已损失体力值 = 体力上限 - 当前体力
func _rage_bonus(p: Player) -> int:
	if p.general_name != "布鲁斯·萨维奇":
		return 0
	return maxi(p.max_hp - p.hp, 0)

# 【下跪】发动条件：回合外 + 没有手牌 + 已经受伤（且未下跪、限定技未使用）
func _kneel_conditions_met(p: Player) -> bool:
	if p.general_name != "布鲁斯·萨维奇":
		return false
	if p.kneeling or p.kneel_used:
		return false
	if turn_manager.current_player_idx == p.seat_index:
		return false
	if p.hand_size() > 0:
		return false
	if p.hp >= p.max_hp:
		return false
	return true

# 【劣马】全局距离修正：-1劣马 → 其他玩家（非持有者）视作额外装备 -1马（攻击距离-1）；
# +1劣马 → 其他玩家（非持有者）视作额外装备 +1马（被攻击距离+1）
# 返回 Vector2i(minus, plus)；由 Player.attack_distance_to 调用（玩家是 GameManager 子节点）
func _mule_distance_mod(attacker: Player, target: Player) -> Vector2i:
	var minus = 0
	var plus = 0
	for p in players:
		if p != attacker and p.has_mule_minus():
			minus += 1
		if p != target and p.has_mule_plus():
			plus += 1
	return Vector2i(minus, plus)

func _get_all_alive_targets(attacker: Player) -> Array[Player]:
	var targets: Array[Player] = []
	for p in players:
		# 【下跪】：下跪状态不会成为任何效果的目标
		if p != attacker and p.is_alive() and not _is_kneeling(p):
			targets.append(p)
	return targets

# 【决斗】目标查询：距离 2 内（含马修正；无距离限制规则已作废，2026-08-24 朋友规则修订）
# 【霸王】（杰基·斯特朗）：你的【决斗】无距离限制 → 返回全部存活目标
func _get_duel_targets(attacker: Player) -> Array[Player]:
	if attacker.general_name == "杰基·斯特朗":
		return _get_all_alive_targets(attacker)
	var targets: Array[Player] = []
	for p in players:
		# 【下跪】：下跪状态不会成为任何效果的目标
		if p != attacker and p.is_alive() and not _is_kneeling(p) and attacker.attack_distance_to(p) <= 2:
			targets.append(p)
	return targets

# ============================
#  目标选择模式
# ============================

func _enter_targeting_mode(sub: CardData.CardSubType):
	_is_targeting = true
	_targeting_card_sub = sub

	# 隐藏常规按钮，显示取消按钮
	_play_btn.visible = false
	_end_play_btn.visible = false
	_cancel_target_btn.visible = true

	_update_debug("请点击一名玩家头像，选择【%s】的目标（或点击「取消选择」）" % CardData.get_type_name(sub))

func _exit_targeting_mode():
	_is_targeting = false
	_targeting_card_sub = -1
	_cancel_target_btn.visible = false
	_play_btn.visible = true
	_end_play_btn.visible = true
	_update_debug("取消目标选择")

# 取消按钮统一处理（普通目标模式 / 铁索连环模式 / 方天画戟多目标模式）
func _on_cancel_target_pressed():
	# 【是~啊~】：取消目标选择则本张锦囊视为未发动（未流失体力、不消耗手牌）
	_yes_ah_active = false
	if _is_zhuangbi_targeting:
		_exit_zhuangbi_mode()
		_update_debug("取消【装逼】")
		return
	if _is_campus_targeting:
		_is_campus_targeting = false
		_cancel_target_btn.visible = false
		_play_btn.visible = true
		_end_play_btn.visible = true
		_update_debug("取消【校园霸主】")
		return
	if _is_shensu_targeting:
		_is_shensu_targeting = false
		_cancel_target_btn.visible = false
		_shensu_pick_result.emit(null)
		_update_debug("取消【神速】杀目标")
		return
	if _is_gay_targeting:
		_is_gay_targeting = false
		_cancel_target_btn.visible = false
		_play_btn.visible = true
		_end_play_btn.visible = true
		_update_debug("取消【Gay】")
		return
	if _is_lanzhonghou_targeting:
		_is_lanzhonghou_targeting = false
		_lanzhonghou_selected.clear()
		_cancel_target_btn.visible = false
		_play_btn.visible = true
		_end_play_btn.visible = true
		_update_debug("取消【烂忠厚】")
		return
	if _is_meiyong_targeting:
		_is_meiyong_targeting = false
		_cancel_target_btn.visible = false
		_meiyong_pick_result.emit(null)
		_update_debug("取消【没用】")
		return
	if _is_sage_targeting:
		_is_sage_targeting = false
		_cancel_target_btn.visible = false
		_play_btn.visible = true
		_end_play_btn.visible = true
		_update_debug("取消【贤者的加护】拼点")
		return
	if _is_iron_chain_targeting:
		_is_iron_chain_targeting = false
		_iron_chain_targets.clear()
		_cancel_target_btn.visible = false
		_play_btn.visible = true
		_end_play_btn.visible = true
		_update_debug("取消【铁索连环】")
		return
	if _is_multi_targeting:
		_exit_multi_target_mode()
		_update_debug("取消【方天画戟】多目标出杀")
		return
	_exit_targeting_mode()

# ============================
#  方天画戟：多目标选择模式
# ============================

func _enter_multi_target_mode(sub: CardData.CardSubType):
	_is_multi_targeting = true
	_targeting_card_sub = sub
	_multi_targets.clear()

	_play_btn.visible = false
	_end_play_btn.visible = false
	_cancel_target_btn.visible = true
	_confirm_target_btn.visible = true
	_confirm_target_btn.disabled = true
	_confirm_target_btn.text = "确认出牌（0 名目标）"

	_update_debug("【方天画戟】：请点击攻击范围内的角色作为目标（可多选，点已选角色取消），选好后点击「确认出牌」")

func _exit_multi_target_mode():
	_is_multi_targeting = false
	_multi_targets.clear()
	_targeting_card_sub = -1
	_cancel_target_btn.visible = false
	_confirm_target_btn.visible = false
	_play_btn.visible = true
	_end_play_btn.visible = true

# 方天画戟：点击角色头像 toggle 加入/移除目标
func _on_multi_target_click(target: Player):
	var attacker = players[turn_manager.current_player_idx]

	if target == attacker:
		_update_debug("不能选择自己作为目标")
		return
	if not target.is_alive():
		_update_debug("目标已阵亡")
		return
	# 【下跪】：下跪状态不会成为任何效果的目标（方天画戟多目标同样生效）
	if _is_kneeling(target):
		_update_debug("%s 处于【下跪】状态，不能成为目标！" % target.player_name)
		return
	# 【藤甲】：你不能成为【杀】的目标（方天画戟多目标同样生效）
	if target.get_armor() == CardData.CardSubType.TENGJIA:
		_update_debug("%s 的【藤甲】：不能成为【杀】的目标！" % target.player_name)
		return
	# 【觉醒】选择1：不能成为【杀】的目标（方天画戟多目标同样生效）
	if _awake_blocks(target, 1):
		_update_debug("%s 的【觉醒】：不能成为【杀】的目标！" % target.player_name)
		return
	# 【裸奔】：凯文·罗本装备区无装备时不能成为【杀】的目标（方天画戟多目标同样生效）
	if _is_bare_running(target):
		_update_debug("%s 的【裸奔】：装备区没有装备，不能成为【杀】的目标！" % target.player_name)
		return
	# 方天画戟限攻击范围内（与麒麟弓互斥，不受其加成）
	if not attacker.can_attack(target):
		var dist = attacker.attack_distance_to(target)
		_update_debug("%s 距离 %s 为 %d，超出攻击距离 1！" % [attacker.player_name, target.player_name, dist])
		return

	if _multi_targets.has(target):
		_multi_targets.erase(target)
		_update_debug("已取消选择 %s（当前 %d 名目标）" % [target.player_name, _multi_targets.size()])
	else:
		_multi_targets.append(target)
		_update_debug("已选择 %s（当前 %d 名目标）" % [target.player_name, _multi_targets.size()])

	_confirm_target_btn.text = "确认出牌（%d 名目标）" % _multi_targets.size()
	_confirm_target_btn.disabled = _multi_targets.is_empty()

# 方天画戟：确认出牌
func _on_confirm_multi_target():
	if _is_zhuangbi_targeting:
		await _on_confirm_zhuangbi()
		return
	if _multi_targets.is_empty():
		return
	var targets = _multi_targets.duplicate()
	var sub = _targeting_card_sub
	_exit_multi_target_mode()
	await execute_multi_strike(targets, sub)

# ============================
#  【贤者的加护】激活拼点（入口：详情弹窗装备区点击）
# ============================

# 从详情弹窗发动：检查条件后进入拼点目标选择模式
func _on_detail_equip_clicked(sub: CardData.CardSubType, owner_player: Player):
	if sub != CardData.CardSubType.SAGE_PROTECTION:
		return
	var p = players[turn_manager.current_player_idx]
	if owner_player != p or p.seat_index != 0:
		_update_debug("只有装备者本人（你）能发动【贤者的加护】")
		return
	if turn_manager.current_phase != TurnManager.Phase.PLAY:
		_update_debug("只能在出牌阶段发动【贤者的加护】")
		return
	# 关闭详情弹窗
	for child in _detail_popup_root.get_children():
		child.queue_free()
	_detail_popup_root.visible = false
	_start_sage_ping_mode(p)

func _start_sage_ping_mode(p: Player):
	if p.get_armor() != CardData.CardSubType.SAGE_PROTECTION or p.sage_activated:
		_update_debug("【贤者的加护】未装备或已激活")
		return
	if p.hand_size() <= 0:
		_update_debug("没有手牌可弃置")
		return
	_is_sage_targeting = true
	_play_btn.visible = false
	_end_play_btn.visible = false
	_cancel_target_btn.visible = true
	_update_debug("【贤者的加护】：请点击一名角色进行拼点（需弃置一张手牌，赢则获得贤者标记）")

# 拼点目标点击（任意其他存活角色，无距离限制）
func _on_sage_target_click(target: Player):
	var p = players[turn_manager.current_player_idx]
	if target == p or not target.is_alive():
		_update_debug("目标无效")
		return
	_is_sage_targeting = false
	_cancel_target_btn.visible = false
	await _sage_ping(p, target)
	_play_btn.visible = true
	_end_play_btn.visible = true
	_sync_all_ui()

# 核心拼点：弃一张手牌 → 与目标拼点（平局继续直到分出胜负）→ 赢则 +1 贤者标记；3 标记激活
func _sage_ping(wearer: Player, target: Player) -> bool:
	if wearer.get_armor() != CardData.CardSubType.SAGE_PROTECTION or wearer.sage_activated:
		return false
	if wearer.hand_size() <= 0:
		return false
	if target == wearer or not target.is_alive():
		return false
	var c = wearer.hand.pop_back()
	if c != null:
		deck.discard(c)
	_update_debug("%s 弃置一张手牌，与 %s 进行拼点（【贤者的加护】）" % [wearer.player_name, target.player_name])
	var r = await _do_ping_dian(wearer, target)
	if r == RPS_WIN:
		wearer.sage_tokens += 1
		_update_debug("%s 赢得拼点，获得 1 个贤者标记（%d/3）" % [wearer.player_name, wearer.sage_tokens])
		if wearer.sage_tokens >= 3:
			wearer.sage_tokens = 0
			wearer.sage_activated = true
			_update_debug("【贤者的加护】激活！%s 获得保命能力：即将死亡时可弃置所有牌，复原武将牌并摸四张牌" % wearer.player_name)
	else:
		_update_debug("%s 拼点失败，未获得贤者标记" % wearer.player_name)
	_sync_all_ui()
	return r == RPS_WIN

# ============================
#  出牌逻辑
# ============================

func execute_card_on_target(target: Player, sub: CardData.CardSubType):
	var p = players[turn_manager.current_player_idx]
	# 选完目标开始执行：玩家0出牌阶段重置每步倒计时
	_reset_play_countdown_if_p0()
	var card = CardBase.create(sub)

	match sub:
		CardData.CardSubType.STRIKE, CardData.CardSubType.FIRE_STRIKE, CardData.CardSubType.THUNDER_STRIKE:
			card = HandPayment.take(p.hand, sub)
			if card == null:
				_update_debug("没有可用的【%s】或任意牌，未使用杀" % CardData.get_type_name(sub))
				return
			# 青龙偃月刀：每回合第一次打出【杀】时摸一张牌（被闪避也算打出）
			# 用出杀前的击杀次数判断「第一次」：中途装卸武器语义自动正确
			var is_first_strike = turn_manager.strike_count_this_turn == 0
			turn_manager.use_strike()
			if is_first_strike and p.get_weapon() == CardData.CardSubType.QINGLONG_BLADE:
				_draw_blank_cards(p, 1)
				_update_debug("%s 发动【青龙偃月刀】：打出【杀】，摸一张牌（手牌 %d 张）" % [p.player_name, p.hand_size()])
			var base_damage = 1
			var wine_stacks = p.wine_stacks
			p.wine_stacks = 0
			base_damage += wine_stacks
			# 【暴怒】锁定技（布鲁斯·萨维奇）：杀额外造成已损失体力值的伤害
			base_damage += _rage_bonus(p)
			# 已在计数、酒和青龙效果前支付物理手牌，保留原实例。
			deck.discard(card)
			_sync_all_ui()

			var element = EffectChain.DamageType.PHYSICAL
			match sub:
				CardData.CardSubType.FIRE_STRIKE:
					element = EffectChain.DamageType.FIRE
				CardData.CardSubType.THUNDER_STRIKE:
					element = EffectChain.DamageType.THUNDER

			var dealt = await _execute_single_strike(p, target, card, sub, element, base_damage)

			# 【灾厄剑】转移：本次杀的全部伤害处理完成后，可选择将灾厄剑移至其他角色
			if dealt:
				await _try_calamity_transfer(p)

		CardData.CardSubType.DUEL:
			if not await _consume_trick(p, CardData.CardSubType.DUEL):
				return
			_sync_all_ui()
			turn_manager.use_card("duel")
			await _play_duel(p, target)

		CardData.CardSubType.DISMANTLE:
			await _play_steal_card(p, target, false)

		CardData.CardSubType.SNATCH:
			await _play_steal_card(p, target, true)

		CardData.CardSubType.INDULGENCE, CardData.CardSubType.SUPPLY_SHORTAGE, CardData.CardSubType.BURNING_CAMP:
			# 延时锦囊（对目标使用）：进入目标判定区，待其下回合判定阶段结算
			# （闪电不走此路径：只能对自己，由 play_card 直接处理）
			card = await _take_trick_card(p, sub)
			if card == null:
				return
			card.source_seat = p.seat_index
			target.judgment_cards.append(card)
			_update_debug("%s 对 %s 使用了【%s】，已置入其判定区（下回合判定）" % [p.player_name, target.player_name, CardData.get_type_name(sub)])
			_sync_all_ui()


	_sync_all_ui()

# 单个目标的杀结算（防具 → 雌雄 → 响应 → 伤害）：单目标杀与【方天画戟】多目标杀共用
# 杀次数/手牌/酒 buff 已在调用方消耗
# 返回 true = 本次结算对目标造成了伤害（供【灾厄剑】转移判定：全部处理完成后再转移）
func _execute_single_strike(p: Player, target: Player, card: CardBase, sub: CardData.CardSubType, element: EffectChain.DamageType, base_damage: int, ignore_target_restrictions: bool = false) -> bool:
	if target == null or not target.is_alive():
		return false
	# “无论是否合法”只越过选目标限制，不跳过响应和伤害防止。
	if not ignore_target_restrictions and (target.get_armor() == CardData.CardSubType.TENGJIA \
			or _awake_blocks(target, 1) or _is_bare_running(target) or _is_kneeling(target)):
		return false
	var chain = _new_damage_chain(p, target, card, base_damage, element)
	chain.ignore_target_restrictions = ignore_target_restrictions
	chain.response_callback = _on_chain_response_check
	var result = await chain.start()
	if result == EffectChain.ResponseResult.DODGED:
		var actual = chain.target_player
		_update_debug("%s → %s 被【闪】避" % [p.player_name, actual.player_name])
		if p.is_alive() and actual.is_alive() and p.get_weapon() == CardData.CardSubType.GUANSHI_AXE \
				and p.mount_count() > 0 and actual.get_armor() != CardData.CardSubType.QINGGANG_SHIELD:
			var activate = p.seat_index != 0 or await _ask_guanshi(actual.player_name)
			if activate:
				var slots = p.get_mount_slots()
				var slot: String = await _show_mount_discard_picker(p) if p.seat_index == 0 else slots.pick_random()
				if not p.equipment.has(slot):
					return false
				deck.discard(CardBase.create(p.equipment[slot]))
				p.remove_equipment(slot)
				_update_debug("%s 发动【贯石斧】：此【杀】依然造成伤害" % p.player_name)
				var hit = _new_damage_chain(p, actual, card, base_damage, element)
				hit.damage.original_target = chain.damage.original_target
				hit.damage.sacrifice_offered = true
				hit.skip_response = true
				hit.skip_targeting = true # 同一张杀，不重复声明、付费或询问代受。
				await hit.start()
				await _finish_damage_chain(hit)
				return hit.damage.committed
		return false
	await _finish_damage_chain(chain)
	return chain.damage.committed

func _prepare_strike_target(p: Player, target: Player, ignore_restrictions: bool) -> bool:
	# 【藤甲】：你不能成为【杀】的目标（目标选择已过滤，这里兜底防直调）
	if not ignore_restrictions and target.get_armor() == CardData.CardSubType.TENGJIA:
		_update_debug("%s 的【藤甲】：不能成为【杀】的目标！" % target.player_name)
		return false
	# 【觉醒】选择1：不能成为【杀】的目标（兜底防直调）
	if not ignore_restrictions and _awake_blocks(target, 1):
		_update_debug("%s 的【觉醒】：不能成为【杀】的目标！" % target.player_name)
		return false
	# 【裸奔】：凯文·罗本装备区无装备时不能成为【杀】的目标（兜底防直调）
	if not ignore_restrictions and _is_bare_running(target):
		_update_debug("%s 的【裸奔】：装备区没有装备，不能成为【杀】的目标！" % target.player_name)
		return false

	if p == null:
		return true

	# 【烈火盾】vs【寒冰剑】：装备寒冰剑者杀装备烈火盾者 → 双方分别弃置这两张装备，再进行之后的结算
	# 时机在雌雄/响应/伤害之前；装备弃置后寒冰剑的「防止伤害弃两张」不再触发
	if p.get_weapon() == CardData.CardSubType.ICE_SWORD and target.get_armor() == CardData.CardSubType.LIEHUO_SHIELD:
		p.remove_equipment("weapon")
		deck.discard(CardBase.create(CardData.CardSubType.ICE_SWORD))
		target.remove_equipment("armor")
		deck.discard(CardBase.create(CardData.CardSubType.LIEHUO_SHIELD))
		_update_debug("%s 的【寒冰剑】与 %s 的【烈火盾】相撞，双双进入弃牌堆！" % [p.player_name, target.player_name])
		_sync_all_ui()

	# 【青釭盾】vs【青釭剑】：装备青釭剑者杀装备青釭盾者 → 双方分别弃置这两张装备，再进行之后的结算
	if p.get_weapon() == CardData.CardSubType.QINGGANG_SWORD and target.get_armor() == CardData.CardSubType.QINGGANG_SHIELD:
		p.remove_equipment("weapon")
		deck.discard(CardBase.create(CardData.CardSubType.QINGGANG_SWORD))
		target.remove_equipment("armor")
		deck.discard(CardBase.create(CardData.CardSubType.QINGGANG_SHIELD))
		_update_debug("%s 的【青釭剑】与 %s 的【青釭盾】相撞，双双进入弃牌堆！" % [p.player_name, target.player_name])
		_sync_all_ui()

	# 雌雄双股剑：使用【杀】指定异性目标后，可令其选择：弃一张手牌 / 令你摸一张牌
	# 时机在目标响应（出闪）之前，先于伤害结算（与方天画戟互斥武器，正常不会同时触发）
	if target.is_alive() and p.get_weapon() == CardData.CardSubType.CHIXIONG_SHUANGGU and target.gender != p.gender \
			and target.get_armor() != CardData.CardSubType.QINGGANG_SHIELD:
		var activate = true
		if p.seat_index == 0:
			activate = await _ask_chixiong_activate(target.player_name)
		if activate:
			await _resolve_chixiong(p, target)

	return true

# 【方天画戟】多目标杀：一次打出、逐目标结算。

func execute_multi_strike(targets: Array[Player], sub: CardData.CardSubType):
	if targets.is_empty():
		return
	# 方天画戟多目标：选完目标确认出牌后重置每步倒计时
	_reset_play_countdown_if_p0()
	var p = players[turn_manager.current_player_idx]
	var card = HandPayment.take(p.hand, sub)
	if card == null:
		_update_debug("没有可用的【%s】或任意牌，未使用多目标杀" % CardData.get_type_name(sub))
		return

	turn_manager.use_strike()
	var base_damage = 1
	var wine_stacks = p.wine_stacks
	p.wine_stacks = 0
	base_damage += wine_stacks
	# 【暴怒】锁定技（布鲁斯·萨维奇）：杀额外造成已损失体力值的伤害
	base_damage += _rage_bonus(p)
	deck.discard(card)
	_sync_all_ui()

	var element = EffectChain.DamageType.PHYSICAL
	match sub:
		CardData.CardSubType.FIRE_STRIKE:
			element = EffectChain.DamageType.FIRE
		CardData.CardSubType.THUNDER_STRIKE:
			element = EffectChain.DamageType.THUNDER

	var names: Array[String] = []
	for t in targets:
		names.append(t.player_name)
	_update_debug("%s 使用【方天画戟】对 %s 打出【%s】（基础伤害 %d）" % [p.player_name, "、".join(names), CardData.get_type_name(sub), base_damage])

	var dealt_any = false
	for target in targets:
		# 目标可能在前一个目标的结算中阵亡（如铁索传导波及）→ 跳过
		if not target.is_alive():
			_update_debug("%s 已阵亡，跳过" % target.player_name)
			continue
		# 胜负已分：不再结算后续目标
		if _game_over:
			break
		if await _execute_single_strike(p, target, card, sub, element, base_damage):
			dealt_any = true

	# 【灾厄剑】转移：全部目标的伤害都处理完成后，再选择是否转移（双武器假想下语义正确）
	if dealt_any:
		await _try_calamity_transfer(p)

	_sync_all_ui()

# 杀、普通伤害与传导共用同一条伤害链。
func _new_damage_chain(source: Player, target: Player, card: CardBase, amount: int, element: EffectChain.DamageType) -> EffectChain:
	var chain = EffectChain.new(source, target, card, EffectChain.EffectType.DAMAGE, amount)
	chain.damage_element = element
	chain.scheduler = rule_scheduler
	chain.trigger_callback = _on_chain_trigger
	return chain

# 伤害提交及濒死/死亡已经完成；此处不再补扣体力或重新套用武器修正。
func _finish_damage_chain(chain: EffectChain):
	if not chain.damage.committed:
		return
	var actual = chain.target_player
	var source = chain.source_player
	if not chain.damage.is_chain and actual.chained and chain.damage_element != EffectChain.DamageType.PHYSICAL:
		await _resolve_chain_propagation(source, actual, chain.effect_value, chain.damage_element, chain.damage.from_strike)
	await _try_calamity_robe_transfer(actual)
	await _try_minus_mule_transfer(actual)
	await _try_plus_mule_transfer(actual)
	_sync_all_ui()

func play_card(sub: CardData.CardSubType):
	var p = players[turn_manager.current_player_idx]

	# 【下跪】：无法使用或打出任何牌
	if _is_kneeling(p):
		_update_debug("%s 处于【下跪】状态，无法使用或打出任何牌（可点击头像→技能解除）" % p.player_name)
		return

	if not turn_manager.can_play_card():
		_update_debug("当前不能出牌")
		return
	if p.hand_size() <= 0:
		_update_debug("没有手牌了")
		return
	# 每张牌从干净状态开始（【是~啊~】激活标记：选锦囊时设置，消耗锦囊时消费；取消/中止路径由下次出牌重置）
	_yes_ah_active = false

	match sub:
		CardData.CardSubType.STRIKE, CardData.CardSubType.FIRE_STRIKE, CardData.CardSubType.THUNDER_STRIKE:
			if HandPayment.find_index(p.hand, sub) < 0:
				_update_debug("没有可用的【%s】或任意牌" % CardData.get_type_name(sub))
				return
			var strike_limit = p.strike_limit()
			if not turn_manager.can_play_strike(strike_limit):
				if strike_limit == -1:
					_update_debug("一回合内使用【杀】无次数限制")  # 防御：不会走到
				elif strike_limit == 2:
					_update_debug("本回合已使用 2 张【杀】（连弩上限）")
				else:
					_update_debug("一回合只能出一张杀")
				return

			# 检查是否至少有一个可选目标（麒麟弓：杀无距离限制）
			var targets = _get_strike_targets(p)
			if targets.is_empty():
				_update_debug("没有可攻击的目标！")
				return

			# 方天画戟：进入多目标选择模式（攻击范围内任意数量角色）
			if p.get_weapon() == CardData.CardSubType.FANGTIAN_HALBERD:
				_enter_multi_target_mode(sub)
			else:
				_enter_targeting_mode(sub)

		CardData.CardSubType.IRON_CHAIN:
			_yes_ah_active = (await _ask_yes_ah(p, "铁索连环", true)) == "skill"
			_enter_iron_chain_mode()

		CardData.CardSubType.WINE:
			# 出牌阶段使用：buff 下一张杀（狂暴战斧可叠加：连续喝；普通玩家本回合只能喝一次）
			if p.get_weapon() != CardData.CardSubType.RAGING_AXE and p.wine_stacks > 0:
				_update_debug("【酒】的效果尚未消耗，不能连续使用")
				return
			var used_wine = HandPayment.take(p.hand, sub)
			if used_wine == null:
				_update_debug("没有可用的【酒】或任意牌")
				return
			p.wine_stacks += 1
			deck.discard(used_wine)
			_update_debug("%s 使用了【酒】（当前 %d 层，下一张【杀】伤害+%d）" % [p.player_name, p.wine_stacks, p.wine_stacks])
			_sync_all_ui()
			_reset_play_countdown_if_p0()

		CardData.CardSubType.PEACH:
			if p.hp >= p.max_hp:
				_update_debug("体力已满")
				return
			var used_peach = HandPayment.take(p.hand, sub)
			if used_peach == null:
				_update_debug("没有可用的【桃】或任意牌")
				return
			var healed = _heal_with_staff(p)
			deck.discard(used_peach)
			_update_debug("%s 使用了【桃】，回复 %d 点体力（%d/%d）" % [p.player_name, healed, p.hp, p.max_hp])
			_sync_all_ui()
			_reset_play_countdown_if_p0()

		CardData.CardSubType.DODGE:
			_update_debug("【闪】只能在响应阶段使用")
			return

		CardData.CardSubType.NULLIFICATION, CardData.CardSubType.SACRIFICE:
			_update_debug("【%s】只能在响应阶段使用" % CardData.get_type_name(sub))
			return

		CardData.CardSubType.DUEL:
			# 【霸王】（杰基·斯特朗）：每回合可以额外使用一张决斗（上限 2 → 3）
			var duel_limit = 3 if p.general_name == "杰基·斯特朗" else 2
			if not turn_manager.can_use("duel", duel_limit):
				_update_debug("本回合已使用 %d 次【决斗】" % duel_limit)
				return
			var targets = _get_duel_targets(p)
			if targets.is_empty():
				_update_debug("没有可用的目标！")
				return
			_yes_ah_active = (await _ask_yes_ah(p, "决斗", true)) == "skill"
			_enter_targeting_mode(sub)

		CardData.CardSubType.BARBARIAN_INVASION:
			if not turn_manager.can_use("aoe"):
				_update_debug("本回合【南蛮入侵】/【万箭齐发】已使用 2 次")
				return
			_yes_ah_active = (await _ask_yes_ah(p, "南蛮入侵", true)) == "skill"
			await _play_aoe(CardData.CardSubType.STRIKE, "南蛮入侵", "杀")

		CardData.CardSubType.VOLLEY_OF_ARROWS:
			if not turn_manager.can_use("aoe"):
				_update_debug("本回合【南蛮入侵】/【万箭齐发】已使用 2 次")
				return
			_yes_ah_active = (await _ask_yes_ah(p, "万箭齐发", true)) == "skill"
			await _play_aoe(CardData.CardSubType.DODGE, "万箭齐发", "闪")

		CardData.CardSubType.PEACH_GARDEN:
			if not turn_manager.can_use("peach_garden"):
				_update_debug("本回合已使用【桃园结义】")
				return
			_yes_ah_active = (await _ask_yes_ah(p, "桃园结义", true)) == "skill"
			await _play_peach_garden()

		CardData.CardSubType.HARVEST:
			if not turn_manager.can_use("harvest"):
				_update_debug("本回合已使用【五谷丰登】")
				return
			_yes_ah_active = (await _ask_yes_ah(p, "五谷丰登", true)) == "skill"
			await _play_harvest()

		CardData.CardSubType.DISARM:
			if not turn_manager.can_use("disarm"):
				_update_debug("本回合已使用【卸甲归田】")
				return
			_yes_ah_active = (await _ask_yes_ah(p, "卸甲归田", true)) == "skill"
			await _play_disarm()

		CardData.CardSubType.DISMANTLE:
			# 过河拆桥：无距离限制（每回合与顺手牵羊合计 ≤2）
			if not turn_manager.can_use("steal"):
				_update_debug("本回合【顺手牵羊】/【过河拆桥】已使用 2 次")
				return
			var dis_targets = _get_all_alive_targets(p)
			if dis_targets.is_empty():
				_update_debug("没有可用的目标！")
				return
			_yes_ah_active = (await _ask_yes_ah(p, "过河拆桥", true)) == "skill"
			_enter_targeting_mode(sub)

		CardData.CardSubType.SNATCH:
			# 顺手牵羊：距离 1 内（每回合与过河拆桥合计 ≤2）
			if not turn_manager.can_use("steal"):
				_update_debug("本回合【顺手牵羊】/【过河拆桥】已使用 2 次")
				return
			var snatch_targets = _get_attackable_targets(p)
			if snatch_targets.is_empty():
				_update_debug("距离 1 内没有可牵的目标！")
				return
			_yes_ah_active = (await _ask_yes_ah(p, "顺手牵羊", true)) == "skill"
			_enter_targeting_mode(sub)

		CardData.CardSubType.LIGHTNING:
			# 闪电：只能对自己使用（无目标选择）
			if not p.is_alive():
				_update_debug("你已阵亡，无法使用【闪电】")
				return
			var card = await _take_trick_card(p, sub)
			if card == null:
				return
			card.source_seat = p.seat_index
			p.judgment_cards.append(card)
			_update_debug("%s 对自己使用了【闪电】，已置入判定区（下回合判定）" % p.player_name)
			_sync_all_ui()
			_reset_play_countdown_if_p0()

		CardData.CardSubType.INDULGENCE:
			# 乐不思蜀：对其他存活角色使用，无距离限制
			var delay_targets = _get_all_alive_targets(p)
			if delay_targets.is_empty():
				_update_debug("没有可用的目标！")
				return
			_yes_ah_active = (await _ask_yes_ah(p, "乐不思蜀", true)) == "skill"
			_enter_targeting_mode(sub)

		CardData.CardSubType.SUPPLY_SHORTAGE:
			# 兵粮寸断：只能对攻击距离 1 内的角色使用（与杀一致）
			var ss_targets = _get_attackable_targets(p)
			if ss_targets.is_empty():
				_update_debug("攻击距离 1 内没有可用的目标！")
				return
			_yes_ah_active = (await _ask_yes_ah(p, "兵粮寸断", true)) == "skill"
			_enter_targeting_mode(sub)

		CardData.CardSubType.BURNING_CAMP:
			# 火烧连营：只能对攻击距离 1 内的角色使用
			var bc_targets = _get_attackable_targets(p)
			if bc_targets.is_empty():
				_update_debug("攻击距离 1 内没有可用的目标！")
				return
			_yes_ah_active = (await _ask_yes_ah(p, "火烧连营", true)) == "skill"
			_enter_targeting_mode(sub)

		CardData.CardSubType.LIANNU, CardData.CardSubType.ZHUGE_LIANNU, CardData.CardSubType.QINGLONG_BLADE, CardData.CardSubType.ZHANGBA_SPEAR, CardData.CardSubType.CHIXIONG_SHUANGGU, CardData.CardSubType.ICE_SWORD, CardData.CardSubType.QINGGANG_SWORD, CardData.CardSubType.GUDING_BLADE, CardData.CardSubType.GUANSHI_AXE, CardData.CardSubType.QILING_BOW, CardData.CardSubType.POFENG_SPEAR, CardData.CardSubType.FANGTIAN_HALBERD, CardData.CardSubType.FATE_BLADE, CardData.CardSubType.GOU_LIAN_CLAW, CardData.CardSubType.BLOODTHIRSTY_BLADE, CardData.CardSubType.CALAMITY_SWORD, CardData.CardSubType.HEAL_STAFF, CardData.CardSubType.RAGING_AXE, CardData.CardSubType.SOUL_BLADE:
			# 装备武器（全场唯一：每种武器只有一张，装备过即永久占用）
			if equipment_pool.is_claimed(sub):
				_update_debug("【%s】全场仅此一张，已被其他角色装备过，无法再装备" % CardData.get_type_name(sub))
				return
			# 【苕】抢先明置（安普提·斯丢皮得）：暗置同类型装备时，可明置为该装备阻止本次装备
			if await _try_sao_preempt(p, sub, "weapon"):
				return
			if p.equipment.has("weapon"):
				var old_weapon = p.equipment["weapon"]
				if old_weapon == sub:
					_update_debug("你已经装备了【%s】" % CardData.get_type_name(sub))
					return
				var old_is_hidden = old_weapon == CardData.CardSubType.HIDDEN_EQUIPMENT
				# 已有武器：替换确认（玩家0交互 / AI 直接替换；暗置占位直接替换无需确认）
				if p.seat_index == 0 and not old_is_hidden:
					var ok = await _show_weapon_replace_confirm(old_weapon, sub)
					if not ok:
						_update_debug("取消替换武器，手牌未消耗")
						return
				p.hand.pop_back()
				if old_is_hidden:
					p.hidden_equip_slot = ""  # 暗置武器被替换（占位无实际牌可弃）
				else:
					deck.discard(CardBase.create(old_weapon))
				equipment_pool.claim(sub)
				p.equipment["weapon"] = sub
				p.hand_limit_bonus = 0  # 换武器：破风枪手牌上限加成清零（旧破风枪失去 / 新破风枪重新开始）
				if sub == CardData.CardSubType.SOUL_BLADE:
					p.soul_blade_track_target = null  # 摄魂刀：重新装备时重置激活计数跟踪
					p.soul_blade_track_count = 0
				_update_debug("%s 弃置了原武器【%s】，装备了【%s】" % [p.player_name, CardData.get_type_name(old_weapon), CardData.get_type_name(sub)])
				_sync_all_ui()
				_reset_play_countdown_if_p0()
				return
			p.hand.pop_back()
			equipment_pool.claim(sub)
			p.equipment["weapon"] = sub
			p.hand_limit_bonus = 0  # 新武器从 0 开始（破风枪加成归属当前武器）
			if sub == CardData.CardSubType.SOUL_BLADE:
				p.soul_blade_track_target = null  # 摄魂刀：装备时重置激活计数跟踪
				p.soul_blade_track_count = 0
			_update_debug("%s 装备了【%s】" % [p.player_name, CardData.get_type_name(sub)])
			_sync_all_ui()
			_reset_play_countdown_if_p0()

		CardData.CardSubType.RENWANG_DUN, CardData.CardSubType.BAIHUA_SKIRT, CardData.CardSubType.QIXING_PAO, CardData.CardSubType.SILVER_LION, CardData.CardSubType.SHENGGUANG_BAIYI, CardData.CardSubType.BAGUA_ZHEN, CardData.CardSubType.TENGJIA, CardData.CardSubType.ZHANQI, CardData.CardSubType.LIEHUO_SHIELD, CardData.CardSubType.QINGGANG_SHIELD, CardData.CardSubType.THORN_ARMOR, CardData.CardSubType.CALAMITY_ROBE, CardData.CardSubType.SAGE_PROTECTION:
			# 装备防具（全场唯一：每种防具一局只有一张，装备过即永久占用）
			if equipment_pool.is_claimed(sub):
				_update_debug("【%s】全场仅此一张，已被其他角色装备过，无法再装备" % CardData.get_type_name(sub))
				return
			# 【苕】抢先明置（安普提·斯丢皮得）：暗置同类型装备时，可明置为该装备阻止本次装备
			if await _try_sao_preempt(p, sub, "armor"):
				return
			if p.equipment.has("armor"):
				var old_armor = p.equipment["armor"]
				if old_armor == sub:
					_update_debug("你已经装备了【%s】" % CardData.get_type_name(sub))
					return
				var old_is_hidden = old_armor == CardData.CardSubType.HIDDEN_EQUIPMENT
				# 已有防具：替换确认（玩家0交互 / AI 直接替换；暗置占位直接替换无需确认）
				if p.seat_index == 0 and not old_is_hidden:
					var ok = await _show_weapon_replace_confirm(old_armor, sub)
					if not ok:
						_update_debug("取消替换防具，手牌未消耗")
						return
				p.hand.pop_back()
				if old_is_hidden:
					p.hidden_equip_slot = ""  # 暗置防具被替换（占位无实际牌可弃）
				else:
					deck.discard(CardBase.create(old_armor))
				equipment_pool.claim(sub)
				p.equipment["armor"] = sub
				# 【白银狮子】：替换（失去）装备区里的白银狮子时回复 1 点体力
				if old_armor == CardData.CardSubType.SILVER_LION:
					p.heal(1)
					_update_debug("%s 失去【白银狮子】，回复 1 点体力（%d/%d）" % [p.player_name, p.hp, p.max_hp])
				# 【贤者的加护】：贤者标记跟随装备移动（替换失去时清空）
				if old_armor == CardData.CardSubType.SAGE_PROTECTION:
					p.sage_tokens = 0
					p.sage_activated = false
					_update_debug("%s 失去【贤者的加护】，贤者标记随之清空" % p.player_name)
				_update_debug("%s 弃置了原防具【%s】，装备了【%s】" % [p.player_name, CardData.get_type_name(old_armor), CardData.get_type_name(sub)])
				_sync_all_ui()
				_reset_play_countdown_if_p0()
				return
			p.hand.pop_back()
			equipment_pool.claim(sub)
			p.equipment["armor"] = sub
			_update_debug("%s 装备了【%s】" % [p.player_name, CardData.get_type_name(sub)])
			_sync_all_ui()
			_reset_play_countdown_if_p0()

		CardData.CardSubType.MOUNT_PLUS, CardData.CardSubType.MOUNT_MINUS, CardData.CardSubType.MULE_PLUS, CardData.CardSubType.MULE_MINUS:
			# 装备坐骑：有空槽自动装入；槽满（4/4）可选择顶掉任意一匹
			# 【苕】抢先明置（安普提·斯丢皮得）：暗置同类型装备时，可明置为该装备阻止本次装备
			if await _try_sao_preempt(p, sub, "mount"):
				return
			var target_slot: String = ""
			if p.has_free_mount_slot():
				p.hand.pop_back()
				p.equip_mount(sub)
				_update_debug("%s 装备了【%s】（坐骑 +%d 匹 -%d 匹，共 %d/4）" % [
					p.player_name, CardData.get_type_name(sub), p.mount_plus, p.mount_minus, p.mount_count()
				])
				_sync_all_ui()
				_reset_play_countdown_if_p0()
				return

			# 槽满：选择顶掉任意一匹
			if p.seat_index == 0:
				target_slot = await _show_mount_replace_picker(p)
				if target_slot == "cancel":
					_update_debug("取消替换坐骑，手牌未消耗")
					return
			else:
				# AI 随机顶掉一匹
				var slots = p.get_mount_slots()
				target_slot = slots[randi() % slots.size()]

			p.hand.pop_back()
			var old_sub = p.equipment[target_slot]
			p.replace_mount(target_slot, sub)
			if target_slot == p.hidden_equip_slot:
				p.hidden_equip_slot = ""  # 暗置坐骑被顶掉
			_update_debug("%s 用【%s】顶掉了%s的【%s】（坐骑 +%d 匹 -%d 匹，共 %d/4）" % [
				p.player_name, CardData.get_type_name(sub), Player.EQUIP_SLOT_NAMES[target_slot],
				CardData.get_type_name(old_sub), p.mount_plus, p.mount_minus, p.mount_count()
			])
			_sync_all_ui()
			_reset_play_countdown_if_p0()

		_:
			_update_debug("%s 使用了【%s】（效果待实现）" % [p.player_name, CardData.get_type_name(sub)])
			p.hand.pop_back()
			deck.discard(CardBase.create(sub))
			_sync_all_ui()
			_reset_play_countdown_if_p0()

# ============================
#  AOE 锦囊（南蛮入侵 / 万箭齐发）
# ============================

func _play_aoe(required_sub: CardData.CardSubType, card_name: String, required_name: String):
	var p = players[turn_manager.current_player_idx]

	# 消耗手牌
	var card_sub: CardData.CardSubType
	if required_sub == CardData.CardSubType.STRIKE:
		card_sub = CardData.CardSubType.BARBARIAN_INVASION
	else:
		card_sub = CardData.CardSubType.VOLLEY_OF_ARROWS
	if not await _consume_trick(p, card_sub):
		return
	_sync_all_ui()
	turn_manager.use_card("aoe")
	_reset_play_countdown_if_p0()

	_update_debug("%s 使用了【%s】，所有人需出【%s】或受到 1 点伤害" % [p.player_name, card_name, required_name])

	# 从当前玩家座位顺时针依次结算
	var start_seat = p.seat_index
	for i in range(1, player_count):
		var target_seat = (start_seat + i) % player_count
		var target = players[target_seat]
		if not target.is_alive():
			continue
		# 胜负已分（如目标为主公/最后一名反贼阵亡）：不再结算后续目标
		if _game_over:
			break

		# 【仁王盾】：南蛮入侵和万箭齐发对你无效（锁定技；判定在无懈询问之前，青釭剑只对杀生效不例外）
		if target.get_armor() == CardData.CardSubType.RENWANG_DUN:
			_update_debug("%s 的【仁王盾】使【%s】对你无效！" % [target.player_name, card_name])
			continue
		# 【觉醒】选择3：不能成为【南蛮入侵】和【万箭齐发】的目标（目标层面免疫，跳过结算）
		if _awake_blocks(target, 3):
			_update_debug("%s 的【觉醒】：不能成为【%s】的目标！" % [target.player_name, card_name])
			continue

		# 【下跪】：下跪状态不会成为任何效果的目标 → 跳过响应与伤害
		if _is_kneeling(target):
			_update_debug("%s 处于【下跪】状态，【%s】对其无效" % [target.player_name, card_name])
			continue

		# 无懈可击：效果即将对目标生效前，询问所有角色
		var nullified = await _ask_nullification_chain("%s的【%s】即将对 %s 生效，是否打出一张【无懈可击】？" % [p.player_name, card_name, target.player_name])
		if nullified:
			_update_debug("【%s】对 %s 的效果被【无懈可击】抵消" % [card_name, target.player_name])
			continue

		var responded = false
		if target_seat == 0 and target.hand_size() > 0:
			# 玩家 0 需要交互
			responded = await _show_aoe_prompt(card_name, required_name)
		else:
			# AI 玩家直接受伤害
			pass

		if responded:
			target.hand.pop_back()
			# 【八卦阵】：使用/打出【闪】时摸一张牌（万箭齐发路径）
			if required_sub == CardData.CardSubType.DODGE:
				_try_bagua_draw(target)
			_update_debug("%s 出【%s】响应【%s】" % [target.player_name, required_name, card_name])
		else:
			_update_debug("%s 未能出【%s】响应【%s】" % [target.player_name, required_name, card_name])
			await _deal_damage(p, target, 1, EffectChain.DamageType.PHYSICAL)

	_sync_all_ui()

func _show_aoe_prompt(card_name: String, required_name: String) -> bool:
	# 测试钩子：跳过 UI 直接返回
	if _aoe_override.is_valid():
		return _aoe_override.call()

	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = "【%s】！请出【%s】响应，\n否则将受到 1 点伤害" % [card_name, required_name]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(500, 60)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	var respond_btn = Button.new()
	respond_btn.text = "出【%s】" % required_name
	respond_btn.custom_minimum_size = Vector2(160, 44)
	hbox.add_child(respond_btn)

	var skip_btn = Button.new()
	skip_btn.text = "放弃（受伤害）"
	skip_btn.custom_minimum_size = Vector2(160, 44)
	hbox.add_child(skip_btn)

	var result = [false]
	respond_btn.pressed.connect(func():
		result[0] = true
		overlay.queue_free()
		_response_ready.emit()
	, CONNECT_ONE_SHOT)
	skip_btn.pressed.connect(func():
		result[0] = false
		overlay.queue_free()
		_response_ready.emit()
	, CONNECT_ONE_SHOT)

	_start_response_countdown(overlay, players[0].player_name, func(): _response_ready.emit())
	await _response_ready
	_stop_countdown()
	return result[0]

# ============================
#  桃园结义
# ============================

func _play_peach_garden():
	var p = players[turn_manager.current_player_idx]

	if not await _consume_trick(p, CardData.CardSubType.PEACH_GARDEN):
		return
	_sync_all_ui()
	turn_manager.use_card("peach_garden")
	_reset_play_countdown_if_p0()

	_update_debug("%s 使用了【桃园结义】，所有角色回复 1 点体力" % p.player_name)

	# 从使用者开始顺时针依次结算（与南蛮/万箭方向一致）
	var start_seat = p.seat_index
	for i in range(player_count):
		var seat = (start_seat + i) % player_count
		var target = players[seat]
		if not target.is_alive():
			continue
		# 【下跪】：下跪状态不会成为任何效果的目标
		if _is_kneeling(target):
			_update_debug("%s 处于【下跪】状态，【桃园结义】对其无效" % target.player_name)
			continue
		# 无懈可击：效果即将对目标生效前
		var nullified = await _ask_nullification_chain("%s的【桃园结义】即将对 %s 生效，是否打出一张【无懈可击】？" % [p.player_name, target.player_name])
		if nullified:
			_update_debug("【桃园结义】对 %s 的效果被【无懈可击】抵消" % target.player_name)
			continue
		if target.hp >= target.max_hp:
			_update_debug("%s 体力已满，【桃园结义】对其无效" % target.player_name)
			continue
		target.heal(1)
		_update_debug("%s 回复 1 点体力（%d/%d）" % [target.player_name, target.hp, target.max_hp])

	_sync_all_ui()

# ============================
#  五谷丰登
# ============================

func _play_harvest():
	var p = players[turn_manager.current_player_idx]

	if not await _consume_trick(p, CardData.CardSubType.HARVEST):
		return
	_sync_all_ui()
	turn_manager.use_card("harvest")
	_reset_play_countdown_if_p0()

	_update_debug("%s 使用了【五谷丰登】！" % p.player_name)
	_update_debug("每名角色摸「已损失体力值」数量的牌（体力上限 - 当前体力），最多 3 张")

	# 从使用者开始顺时针依次结算（与桃园结义方向一致）
	var start_seat = p.seat_index
	for i in range(player_count):
		var seat = (start_seat + i) % player_count
		var target = players[seat]
		if not target.is_alive():
			_update_debug("%s 已阵亡，跳过" % target.player_name)
			continue

		# 【下跪】：下跪状态不会成为任何效果的目标
		if _is_kneeling(target):
			_update_debug("%s 处于【下跪】状态，【五谷丰登】对其无效" % target.player_name)
			continue

		# 无懈可击：效果即将对目标生效前
		var nullified = await _ask_nullification_chain("%s的【五谷丰登】即将对 %s 生效，是否打出一张【无懈可击】？" % [p.player_name, target.player_name])
		if nullified:
			_update_debug("【五谷丰登】对 %s 的效果被【无懈可击】抵消" % target.player_name)
			continue

		var lost = target.max_hp - target.hp
		if lost <= 0:
			_update_debug("%s 体力已满，摸 0 张" % target.player_name)
			continue

		var draw_count = mini(lost, 3)
		_draw_blank_cards(target, draw_count)
		_update_debug("%s 已损失 %d 点体力，摸 %d 张牌（手牌 %d 张）" % [target.player_name, lost, draw_count, target.hand_size()])

	_sync_all_ui()

# ============================
#  卸甲归田
# ============================

func _play_disarm():
	var p = players[turn_manager.current_player_idx]
	if not turn_manager.can_use("disarm"):
		_update_debug("本回合已使用【卸甲归田】")
		return

	if not await _consume_trick(p, CardData.CardSubType.DISARM):
		return
	turn_manager.use_card("disarm")
	_sync_all_ui()
	_reset_play_countdown_if_p0()

	_update_debug("%s 使用了【卸甲归田】！" % p.player_name)
	_update_debug("所有有装备的角色弃置所有装备牌，之后摸相同数量的牌")

	# 从使用者开始顺时针依次结算（与桃园结义/五谷丰登方向一致）
	var start_seat = p.seat_index
	for i in range(player_count):
		var seat = (start_seat + i) % player_count
		var target = players[seat]
		if not target.is_alive():
			_update_debug("%s 已阵亡，跳过" % target.player_name)
			continue

		# 【下跪】：下跪状态不会成为任何效果的目标
		if _is_kneeling(target):
			_update_debug("%s 处于【下跪】状态，【卸甲归田】对其无效" % target.player_name)
			continue

		# 无懈可击：效果即将对目标生效前
		var nullified = await _ask_nullification_chain("%s的【卸甲归田】即将对 %s 生效，是否打出一张【无懈可击】？" % [p.player_name, target.player_name])
		if nullified:
			_update_debug("【卸甲归田】对 %s 的效果被【无懈可击】抵消" % target.player_name)
			continue

		var slots = target.get_equip_slots()
		if slots.is_empty():
			_update_debug("%s 没有装备，跳过" % target.player_name)
			continue

		var removed_count = 0
		for slot in slots:
			# 【烈火盾】：可流失 1 点体力代替失去这件装备
			if await _maybe_liehuo_save(target):
				continue
			target.remove_equipment(slot)
			removed_count += 1
		if removed_count > 0:
			_draw_blank_cards(target, removed_count)
		_update_debug("%s 弃置 %d 件装备，摸 %d 张牌（手牌 %d 张）" % [target.player_name, removed_count, removed_count, target.hand_size()])

	_sync_all_ui()

# ============================
#  过河拆桥 / 顺手牵羊
# ============================

# is_snatch = true → 顺手牵羊（获取），false → 过河拆桥（弃置）
func _play_steal_card(attacker: Player, target: Player, is_snatch: bool):
	var card_name = "顺手牵羊" if is_snatch else "过河拆桥"
	var action = "获取" if is_snatch else "弃置"

	# 目标任何区域都没有牌 → 不能使用
	if not target.has_any_card():
		_update_debug("目标没有任何可%s的牌，无法使用【%s】" % [action, card_name])
		return

	# 选择牌的区域：使用者是玩家 0 时交互，否则 AI 随机
	var zone: String
	if attacker.seat_index == 0:
		zone = await _show_zone_picker(action, target)
	else:
		zone = _pick_random_zone(target)

	if zone == "cancel":
		_update_debug("取消使用【%s】" % card_name)
		return

	# 确认后消耗手牌
	var sub = CardData.CardSubType.SNATCH if is_snatch else CardData.CardSubType.DISMANTLE
	if not await _consume_trick(attacker, sub):
		return
	turn_manager.use_card("steal")
	_reset_play_countdown_if_p0()
	_update_debug("%s 对 %s 使用【%s】" % [attacker.player_name, target.player_name, card_name])

	# 无懈可击：效果即将对目标生效前
	var nullified = await _ask_nullification_chain("%s的【%s】即将对 %s 生效，是否打出一张【无懈可击】？" % [attacker.player_name, card_name, target.player_name])
	if nullified:
		_update_debug("【%s】对 %s 的效果被【无懈可击】抵消" % [card_name, target.player_name])
		return

	match zone:
		"hand":
			await _steal_hand(attacker, target, is_snatch, card_name)
		"equip":
			await _steal_equip(attacker, target, is_snatch, card_name)
		"judgment":
			await _steal_judgment(attacker, target, is_snatch, card_name)

	_sync_all_ui()

# 手牌：目标 -1；顺手牵羊时自己 +1
func _steal_hand(attacker: Player, target: Player, is_snatch: bool, card_name: String):
	if target.hand_size() <= 0:
		_update_debug("目标没有手牌")
		return
	# 【烈火盾】：可流失 1 点体力代替失去这张手牌
	if await _maybe_liehuo_save(target):
		_update_debug("%s 的【烈火盾】保住了这张手牌！" % target.player_name)
		return
	# 等待失牌替代期间牌区可能改变，不能从已清空的牌区生成一张假牌。
	if target.is_dead() or target.hand.is_empty():
		return
	var taken: CardBase = target.hand.pop_back()
	if is_snatch:
		# 任意牌仍为 null；具体牌保持同一资源、类型和来源元数据。
		attacker.hand.append(taken)
		_update_debug("%s 获得 %s 的 1 张手牌（自己手牌 %d 张）" % [attacker.player_name, target.player_name, attacker.hand_size()])
	else:
		if taken != null:
			deck.discard(taken)
		_update_debug("%s 弃置了 %s 的 1 张手牌（目标剩 %d 张）" % [attacker.player_name, target.player_name, target.hand_size()])

# 装备：目标失去该装备；顺手牵羊时放入自己「已确定的牌」
func _steal_equip(attacker: Player, target: Player, is_snatch: bool, card_name: String):
	var slots = target.get_equip_slots()
	if slots.is_empty():
		_update_debug("目标没有装备牌")
		return

	var slot: String
	if attacker.seat_index == 0:
		slot = await _show_equip_picker(target, slots)
		if slot == "cancel":
			_update_debug("取消选择装备，【%s】未生效（牌已消耗）" % card_name)
			return
	else:
		slot = slots[randi() % slots.size()]

	if not target.equipment.has(slot):
		return
	var sub = target.equipment[slot]
	# 【烈火盾】：可流失 1 点体力代替失去这件装备
	if await _maybe_liehuo_save(target):
		_update_debug("%s 的【烈火盾】保住了【%s】！" % [target.player_name, CardData.get_type_name(sub)])
		return
	if target.is_dead() or target.equipment.get(slot, -1) != sub:
		return
	# 【贤者的加护】标记跟随装备：被顺手牵羊时标记/激活状态一并转移给新持有者（被拆/卸甲进弃牌堆则清空）
	var sage_transfer := false
	var sage_tokens_save := 0
	var sage_activated_save := false
	if sub == CardData.CardSubType.SAGE_PROTECTION:
		sage_transfer = true
		sage_tokens_save = target.sage_tokens
		sage_activated_save = target.sage_activated
	target.remove_equipment(slot)
	if is_snatch:
		attacker.determined_cards.append(CardBase.create(sub))
		if sage_transfer:
			attacker.sage_tokens = sage_tokens_save
			attacker.sage_activated = sage_activated_save
			_update_debug("%s 获得 %s 的【%s】（贤者标记 %d 一并转移）" % [attacker.player_name, target.player_name, CardData.get_type_name(sub), sage_tokens_save])
		else:
			_update_debug("%s 获得 %s 的【%s】，已加入你的「已确定的牌」" % [attacker.player_name, target.player_name, CardData.get_type_name(sub)])
	else:
		# 装备区目前只存类型，因此沿用死亡弃牌的资源重建约定；暗置占位不造实体。
		if sub != CardData.CardSubType.HIDDEN_EQUIPMENT:
			deck.discard(CardBase.create(sub))
		_update_debug("%s 弃置了 %s 的【%s】" % [attacker.player_name, target.player_name, CardData.get_type_name(sub)])

# 判定牌：目标失去；顺手牵羊时放入自己「已确定的牌」
func _steal_judgment(attacker: Player, target: Player, is_snatch: bool, card_name: String):
	if target.judgment_cards.is_empty():
		_update_debug("目标没有判定牌")
		return
	# 【烈火盾】：可流失 1 点体力代替失去这张判定牌
	if await _maybe_liehuo_save(target):
		_update_debug("%s 的【烈火盾】保住了判定牌！" % target.player_name)
		return
	if target.is_dead() or target.judgment_cards.is_empty():
		return
	var card = target.judgment_cards.pop_back()
	if is_snatch:
		attacker.determined_cards.append(card)
		_update_debug("%s 获得 %s 的判定牌【%s】，已加入你的「已确定的牌」" % [attacker.player_name, target.player_name, card.card_name])
	else:
		deck.discard(card)
		_update_debug("%s 弃置了 %s 的判定牌【%s】" % [attacker.player_name, target.player_name, card.card_name])

# AI 随机选一个目标有牌的区域
func _pick_random_zone(target: Player) -> String:
	var zones: Array[String] = []
	if target.hand_size() > 0:
		zones.append("hand")
	if not target.get_equip_slots().is_empty():
		zones.append("equip")
	if not target.judgment_cards.is_empty():
		zones.append("judgment")
	if zones.is_empty():
		return "cancel"
	return zones[randi() % zones.size()]

# 选择牌区域弹窗（手牌/装备牌/判定牌）——锚点布局，窗口缩放自动居中
func _show_zone_picker(action: String, target: Player) -> String:
	# 测试钩子：跳过 UI 直接返回区域名
	if _zone_pick_override.is_valid():
		return _zone_pick_override.call()

	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = "选择%s %s 的牌：" % [action, target.player_name]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(500, 60)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	var hand_btn = Button.new()
	hand_btn.text = "手牌（%d 张）" % target.hand_size()
	hand_btn.custom_minimum_size = Vector2(160, 44)
	hand_btn.disabled = target.hand_size() <= 0
	hand_btn.pressed.connect(func():
		overlay.queue_free()
		_zone_pick_result.emit("hand")
	, CONNECT_ONE_SHOT)
	hbox.add_child(hand_btn)

	var equip_btn = Button.new()
	equip_btn.text = "装备牌（%d 件）" % target.get_equip_slots().size()
	equip_btn.custom_minimum_size = Vector2(160, 44)
	equip_btn.disabled = target.get_equip_slots().is_empty()
	equip_btn.pressed.connect(func():
		overlay.queue_free()
		_zone_pick_result.emit("equip")
	, CONNECT_ONE_SHOT)
	hbox.add_child(equip_btn)

	var judgment_btn = Button.new()
	judgment_btn.text = "判定牌（%d 张）" % target.judgment_cards.size()
	judgment_btn.custom_minimum_size = Vector2(160, 44)
	judgment_btn.disabled = target.judgment_cards.is_empty()
	judgment_btn.pressed.connect(func():
		overlay.queue_free()
		_zone_pick_result.emit("judgment")
	, CONNECT_ONE_SHOT)
	hbox.add_child(judgment_btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(160, 44)
	cancel_btn.modulate = Color(0.7, 0.7, 0.7)
	cancel_btn.pressed.connect(func():
		overlay.queue_free()
		_zone_pick_result.emit("cancel")
	, CONNECT_ONE_SHOT)
	vbox.add_child(cancel_btn)

	var result = await _zone_pick_result
	return result

# 选择具体装备弹窗——锚点布局，窗口缩放自动居中
func _show_equip_picker(target: Player, slots: Array[String], title: String = "选择要处理的装备：") -> String:
	# 测试钩子：跳过 UI 直接返回槽位
	if _equip_pick_override.is_valid():
		return _equip_pick_override.call()
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(500, 60)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	for slot in slots:
		var btn = Button.new()
		var sub = target.equipment[slot]
		btn.text = "%s：%s" % [Player.EQUIP_SLOT_NAMES[slot], CardData.get_type_name(sub)]
		btn.custom_minimum_size = Vector2(160, 44)
		btn.pressed.connect(_emit_equip_pick.bind(overlay, slot), CONNECT_ONE_SHOT)
		hbox.add_child(btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(160, 44)
	cancel_btn.modulate = Color(0.7, 0.7, 0.7)
	cancel_btn.pressed.connect(func():
		overlay.queue_free()
		_equip_pick_result.emit("cancel")
	, CONNECT_ONE_SHOT)
	vbox.add_child(cancel_btn)

	var result = await _equip_pick_result
	return result

func _emit_equip_pick(overlay: ColorRect, slot: String):
	overlay.queue_free()
	_equip_pick_result.emit(slot)

# 坐骑槽满时：选择要顶掉的马（锚点居中弹窗）
func _show_mount_replace_picker(p: Player) -> String:
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = "坐骑槽位已满（4/4）\n选择要顶掉的马："
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(500, 60)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	for slot in p.get_mount_slots():
		var btn = Button.new()
		btn.text = "%s：%s" % [Player.EQUIP_SLOT_NAMES[slot], CardData.get_type_name(p.equipment[slot])]
		btn.custom_minimum_size = Vector2(160, 44)
		btn.pressed.connect(_emit_mount_replace.bind(overlay, slot), CONNECT_ONE_SHOT)
		hbox.add_child(btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(160, 44)
	cancel_btn.modulate = Color(0.7, 0.7, 0.7)
	cancel_btn.pressed.connect(func():
		overlay.queue_free()
		_mount_replace_result.emit("cancel")
	, CONNECT_ONE_SHOT)
	vbox.add_child(cancel_btn)

	var result = await _mount_replace_result
	return result

func _emit_mount_replace(overlay: ColorRect, slot: String):
	overlay.queue_free()
	_mount_replace_result.emit(slot)

# 已有武器时替换确认弹窗（锚点居中）
func _show_weapon_replace_confirm(old_weapon: CardData.CardSubType, new_weapon: CardData.CardSubType) -> bool:
	# 测试钩子：跳过 UI 直接返回
	if _weapon_replace_override.is_valid():
		return _weapon_replace_override.call()

	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = "你已装备【%s】\n是否替换为【%s】？（原装备将进入弃牌堆）" % [
		CardData.get_type_name(old_weapon), CardData.get_type_name(new_weapon)
	]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(500, 60)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	var yes_btn = Button.new()
	yes_btn.text = "替换"
	yes_btn.custom_minimum_size = Vector2(160, 44)
	yes_btn.pressed.connect(func():
		overlay.queue_free()
		_weapon_replace_result.emit(true)
	, CONNECT_ONE_SHOT)
	hbox.add_child(yes_btn)

	var no_btn = Button.new()
	no_btn.text = "取消"
	no_btn.custom_minimum_size = Vector2(160, 44)
	no_btn.modulate = Color(0.7, 0.7, 0.7)
	no_btn.pressed.connect(func():
		overlay.queue_free()
		_weapon_replace_result.emit(false)
	, CONNECT_ONE_SHOT)
	hbox.add_child(no_btn)

	var result = await _weapon_replace_result
	return result

# 丈八蛇矛：杀命中后、扣血前询问流失体力数（X≤3），合并伤害。
# 返回流失的体力数（0 = 放弃）；AI 不主动流失
func _ask_zhangba_extra(p: Player) -> int:
	# 测试钩子
	if _zhangba_override.is_valid():
		return _zhangba_override.call()

	# AI 不主动流失
	if p.seat_index != 0:
		return 0

	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = "你的【杀】已命中，尚未结算伤害。\n【丈八蛇矛】：可流失 X 点体力（X至多为3），\n使本次伤害增加 X 点"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(600, 80)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(hbox)

	for x in [0, 1, 2, 3]:
		var btn = Button.new()
		if x == 0:
			btn.text = "放弃"
		else:
			btn.text = "流失 %d 点" % x
		btn.custom_minimum_size = Vector2(120, 44)
		btn.pressed.connect(_emit_zhangba_pick.bind(overlay, x), CONNECT_ONE_SHOT)
		hbox.add_child(btn)

	var result = await _zhangba_result
	return result

func _emit_zhangba_pick(overlay: ColorRect, x: int):
	overlay.queue_free()
	_zhangba_result.emit(x)

# ============================
#  雌雄双股剑
# ============================

signal _chixiong_activate_result(result: bool)
signal _chixiong_target_result(discard: bool)

# 使用者（玩家0）确认是否发动雌雄双股剑；返回 true = 发动
func _ask_chixiong_activate(target_name: String) -> bool:
	# 测试钩子
	if _chixiong_activate_override.is_valid():
		return _chixiong_activate_override.call()

	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = "【雌雄双股剑】：%s 为异性角色\n是否发动？令其选择弃置一张手牌，或令你摸一张牌" % target_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(600, 80)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	var yes_btn = Button.new()
	yes_btn.text = "发动"
	yes_btn.custom_minimum_size = Vector2(160, 44)
	yes_btn.pressed.connect(func():
		overlay.queue_free()
		_chixiong_activate_result.emit(true)
	, CONNECT_ONE_SHOT)
	hbox.add_child(yes_btn)

	var no_btn = Button.new()
	no_btn.text = "不发动"
	no_btn.custom_minimum_size = Vector2(160, 44)
	no_btn.modulate = Color(0.7, 0.7, 0.7)
	no_btn.pressed.connect(func():
		overlay.queue_free()
		_chixiong_activate_result.emit(false)
	, CONNECT_ONE_SHOT)
	hbox.add_child(no_btn)

	var result = await _chixiong_activate_result
	return result

# 结算雌雄双股剑：目标选择「弃置一张手牌」或「令使用者摸一张牌」
# 目标没有手牌时只能选择令使用者摸一张牌（原版规则）
func _resolve_chixiong(p: Player, target: Player):
	_update_debug("%s 发动【雌雄双股剑】，令 %s 选择：弃置一张手牌 / 令 %s 摸一张牌" % [p.player_name, target.player_name, p.player_name])

	if target.hand_size() <= 0:
		_draw_blank_cards(p, 1)
		_update_debug("%s 没有手牌，只能选择令 %s 摸一张牌（手牌 %d 张）" % [target.player_name, p.player_name, p.hand_size()])
		_sync_all_ui()
		return

	var discard = false
	if _chixiong_target_override.is_valid():
		discard = _chixiong_target_override.call()
	elif target.seat_index == 0:
		discard = await _show_chixiong_target_prompt(p.player_name)
	else:
		# AI 目标：50% 概率弃一张手牌
		discard = randi() % 2 == 0

	if discard:
		# 【烈火盾】：可流失 1 点体力代替弃置这张手牌
		if await _maybe_liehuo_save(target):
			_update_debug("%s 的【烈火盾】保住了手牌！" % target.player_name)
		else:
			target.hand.pop_back()
			_update_debug("%s 选择弃置一张手牌（剩余 %d 张）" % [target.player_name, target.hand_size()])
	else:
		_draw_blank_cards(p, 1)
		_update_debug("%s 选择令 %s 摸一张牌（手牌 %d 张）" % [target.player_name, p.player_name, p.hand_size()])
	_sync_all_ui()

# 目标（玩家0）选择：弃一张手牌 / 令使用者摸牌；返回 true = 弃牌
func _show_chixiong_target_prompt(attacker_name: String) -> bool:
	# 测试钩子
	if _chixiong_target_override.is_valid():
		return _chixiong_target_override.call()

	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = "你被【雌雄双股剑】指定！\n请选择一项："
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(600, 60)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	var discard_btn = Button.new()
	discard_btn.text = "弃置一张手牌"
	discard_btn.custom_minimum_size = Vector2(220, 44)
	discard_btn.pressed.connect(func():
		overlay.queue_free()
		_chixiong_target_result.emit(true)
	, CONNECT_ONE_SHOT)
	hbox.add_child(discard_btn)

	var draw_btn = Button.new()
	draw_btn.text = "令 %s 摸一张牌" % attacker_name
	draw_btn.custom_minimum_size = Vector2(220, 44)
	draw_btn.pressed.connect(func():
		overlay.queue_free()
		_chixiong_target_result.emit(false)
	, CONNECT_ONE_SHOT)
	hbox.add_child(draw_btn)

	var result = await _chixiong_target_result
	return result

# ============================
#  寒冰剑
# ============================

signal _ice_sword_result(result: bool)

# 寒冰剑：杀将要造成伤害时询问，发动则防止伤害、弃两张手牌。
func _ask_ice_sword(target_name: String) -> bool:
	# 测试钩子
	if _ice_sword_override.is_valid():
		return _ice_sword_override.call()

	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = "【寒冰剑】：你的【杀】对 %s 造成了伤害！\n是否防止此伤害，改为依次弃置其两张手牌？" % target_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(600, 80)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	var yes_btn = Button.new()
	yes_btn.text = "发动"
	yes_btn.custom_minimum_size = Vector2(160, 44)
	yes_btn.pressed.connect(func():
		overlay.queue_free()
		_ice_sword_result.emit(true)
	, CONNECT_ONE_SHOT)
	hbox.add_child(yes_btn)

	var no_btn = Button.new()
	no_btn.text = "不发动"
	no_btn.custom_minimum_size = Vector2(160, 44)
	no_btn.modulate = Color(0.7, 0.7, 0.7)
	no_btn.pressed.connect(func():
		overlay.queue_free()
		_ice_sword_result.emit(false)
	, CONNECT_ONE_SHOT)
	hbox.add_child(no_btn)

	var result = await _ice_sword_result
	return result

# ============================
#  贯石斧
# ============================

signal _guanshi_result(result: bool)

# 贯石斧：杀被闪抵消后确认是否发动（玩家0）；返回 true = 发动（弃一张坐骑牌强制命中）
func _ask_guanshi(target_name: String) -> bool:
	# 测试钩子
	if _guanshi_override.is_valid():
		return _guanshi_override.call()

	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = "【贯石斧】：你对 %s 的【杀】被【闪】抵消！\n是否弃置一张坐骑牌，令此【杀】依然对其造成伤害？" % target_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(600, 80)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	var yes_btn = Button.new()
	yes_btn.text = "发动（弃一张坐骑）"
	yes_btn.custom_minimum_size = Vector2(200, 44)
	yes_btn.pressed.connect(func():
		overlay.queue_free()
		_guanshi_result.emit(true)
	, CONNECT_ONE_SHOT)
	hbox.add_child(yes_btn)

	var no_btn = Button.new()
	no_btn.text = "不发动"
	no_btn.custom_minimum_size = Vector2(200, 44)
	no_btn.modulate = Color(0.7, 0.7, 0.7)
	no_btn.pressed.connect(func():
		overlay.queue_free()
		_guanshi_result.emit(false)
	, CONNECT_ONE_SHOT)
	hbox.add_child(no_btn)

	var result = await _guanshi_result
	return result

# 贯石斧：选择弃置哪张坐骑牌（锚点居中弹窗；已确认发动，必须弃一匹，无取消）
func _show_mount_discard_picker(p: Player) -> String:
	# 测试钩子：返回要弃置的坐骑槽位
	if _guanshi_mount_override.is_valid():
		return _guanshi_mount_override.call()

	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = "【贯石斧】发动：\n请选择弃置一张坐骑牌"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(500, 60)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	for slot in p.get_mount_slots():
		var btn = Button.new()
		btn.text = "%s：%s" % [Player.EQUIP_SLOT_NAMES[slot], CardData.get_type_name(p.equipment[slot])]
		btn.custom_minimum_size = Vector2(160, 44)
		btn.pressed.connect(_emit_mount_replace.bind(overlay, slot), CONNECT_ONE_SHOT)
		hbox.add_child(btn)

	var result = await _mount_replace_result
	return result

# ============================
#  铁索连环
# ============================

func _enter_iron_chain_mode():
	_is_iron_chain_targeting = true
	_iron_chain_targets.clear()

	_play_btn.visible = false
	_end_play_btn.visible = false
	_cancel_target_btn.visible = true

	_update_debug("请点击 1-2 名角色（可含自己）作为【铁索连环】目标")

# 点击角色头像（铁索连环模式）
func _on_iron_chain_target_click(target: Player):
	if not target.is_alive():
		_update_debug("目标已阵亡")
		return
	# 【下跪】：下跪状态不会成为任何效果的目标（铁索连环同样生效）
	if _is_kneeling(target):
		_update_debug("%s 处于【下跪】状态，不能成为目标！" % target.player_name)
		return
	if _iron_chain_targets.has(target):
		_update_debug("该角色已在目标中")
		return

	_iron_chain_targets.append(target)

	if _iron_chain_targets.size() == 1:
		# 问是否继续选第二名
		var more = await _show_more_target_confirm(target.player_name)
		if more:
			_update_debug("已选择 %s，请再点击第二名角色" % target.player_name)
			return

	# 单目标（否）或已选满两名 → 执行
	await _execute_iron_chain(_iron_chain_targets)
	_is_iron_chain_targeting = false
	_iron_chain_targets.clear()
	_cancel_target_btn.visible = false
	_play_btn.visible = true
	_end_play_btn.visible = true

# 是否继续选第二名目标的确认
func _show_more_target_confirm(target_name: String) -> bool:
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = "已选择 %s\n是否继续选择第二名目标？" % target_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(500, 60)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	var yes_btn = Button.new()
	yes_btn.text = "继续选择"
	yes_btn.custom_minimum_size = Vector2(160, 44)
	yes_btn.pressed.connect(func():
		overlay.queue_free()
		_iron_chain_cfm_result.emit(true)
	, CONNECT_ONE_SHOT)
	hbox.add_child(yes_btn)

	var no_btn = Button.new()
	no_btn.text = "只选 1 名"
	no_btn.custom_minimum_size = Vector2(160, 44)
	no_btn.pressed.connect(func():
		overlay.queue_free()
		_iron_chain_cfm_result.emit(false)
	, CONNECT_ONE_SHOT)
	hbox.add_child(no_btn)

	var result = await _iron_chain_cfm_result
	return result

# 执行铁索连环：对每个目标切换连环状态
func _execute_iron_chain(targets: Array[Player]):
	var p = players[turn_manager.current_player_idx]
	# 铁索连环：选完目标执行时重置每步倒计时
	_reset_play_countdown_if_p0()

	if not await _consume_trick(p, CardData.CardSubType.IRON_CHAIN):
		return
	_sync_all_ui()

	var names = []
	for t in targets:
		names.append(t.player_name)
	_update_debug("%s 使用了【铁索连环】，目标：%s" % [p.player_name, "、".join(names)])

	for t in targets:
		# 无懈可击：效果即将对目标生效前
		var nullified = await _ask_nullification_chain("%s的【铁索连环】即将对 %s 生效，是否打出一张【无懈可击】？" % [p.player_name, t.player_name])
		if nullified:
			_update_debug("【铁索连环】对 %s 的效果被【无懈可击】抵消" % t.player_name)
			continue
		t.chained = not t.chained
		var state = "进入连环状态" if t.chained else "退出连环状态"
		_update_debug("%s %s" % [t.player_name, state])

	_sync_all_ui()

# 铁索连环传导：属性伤害传导给其它连环角色，之后所有人退出连环
func _resolve_chain_propagation(source: Player, damaged: Player, amount: int, element: EffectChain.DamageType, from_strike: bool = false):
	if element == EffectChain.DamageType.PHYSICAL or not damaged.chained:
		return
	var linked: Array[Player] = []
	for i in range(1, player_count):
		var other = players[(damaged.seat_index + i) % player_count]
		if other != damaged and other.is_alive() and other.chained:
			linked.append(other)
	_update_debug("%s 受到属性伤害，触发【铁索连环】！" % damaged.player_name)
	# 先解除本次连环，反伤等嵌套伤害不会重入同一传导。
	damaged.chained = false
	for other in linked:
		other.chained = false
	for other in linked:
		if _game_over:
			break
		if not other.is_alive() or _is_kneeling(other):
			continue
		var chain = _new_damage_chain(source, other, null, amount, element)
		chain.skip_targeting = true
		chain.skip_response = true
		chain.damage.is_chain = true
		chain.damage.from_strike = from_strike
		chain.damage.sacrifice_offered = true
		await chain.start()
		await _finish_damage_chain(chain)
	_sync_all_ui()

func _play_duel(attacker: Player, target: Player):
	# 【决斗】距离限制 2（含马修正，兜底防直调）；【霸王】（杰基·斯特朗）你的决斗无距离限制
	if attacker.general_name != "杰基·斯特朗" and attacker.attack_distance_to(target) > 2:
		_update_debug("%s 距离 %s 为 %d，超出决斗距离 2，无法发起【决斗】！" % [attacker.player_name, target.player_name, attacker.attack_distance_to(target)])
		return
	# 【战旗】：你不能成为【决斗】的目标（目标选择已拒绝，这里兜底防直调）
	if target.get_armor() == CardData.CardSubType.ZHANQI:
		_update_debug("%s 的【战旗】：不能成为【决斗】的目标！" % target.player_name)
		return
	# 【觉醒】选择2：不能成为【决斗】的目标（兜底防直调）
	if _awake_blocks(target, 2):
		_update_debug("%s 的【觉醒】：不能成为【决斗】的目标！" % target.player_name)
		return
	_update_debug("%s 对 %s 发起【决斗】！" % [attacker.player_name, target.player_name])

	# 无懈可击：决斗即将对目标生效前
	var nullified = await _ask_nullification_chain("%s的【决斗】即将对 %s 生效，是否打出一张【无懈可击】？" % [attacker.player_name, target.player_name])
	if nullified:
		_update_debug("【决斗】的效果被【无懈可击】抵消")
		return

	# 【霸王】（杰基·斯特朗）：与杰基进行决斗的其他角色总是先响应，且每次响应需依次打出两张【杀】
	var jacqui: Player = null
	if attacker.general_name == "杰基·斯特朗":
		jacqui = attacker
	elif target.general_name == "杰基·斯特朗":
		jacqui = target

	var current: Player
	var other: Player
	if jacqui != null:
		current = target if jacqui == attacker else attacker  # 非杰基方先响应
		other = jacqui
		_update_debug("【霸王】生效：%s 先响应此【决斗】，且每次响应需依次打出两张【杀】" % current.player_name)
	else:
		current = target  # 先由目标出杀
		other = attacker

	while true:
		# 【霸王】：非杰基方每次响应需打出两张杀（杰基本人只需一张）
		var needs_two = jacqui != null and current != jacqui
		var has_card = current.hand_size() > 0
		var can_respond = false

		if current.seat_index == 0 and has_card:
			# 玩家 0 需要交互
			can_respond = await _show_duel_prompt(needs_two)
		else:
			# AI 无法响应
			can_respond = false

		if can_respond:
			current.hand.pop_back()
			_update_debug("%s 出【杀】响应【决斗】" % current.player_name)
			# 【霸王】：对方还需打出第二张杀
			if needs_two:
				if current.hand_size() <= 0:
					# 没有第二张杀 → 响应失败 → 受伤害
					_update_debug("%s 无法再出【杀】，在【决斗】中失败" % current.player_name)
					await _deal_damage(other, current, 1 + _rage_bonus(other), EffectChain.DamageType.PHYSICAL)
					break
				var cont = false
				if current.seat_index == 0:
					cont = await _show_duel_second_strike_prompt()
				else:
					cont = false  # AI 不会继续响应（本游戏 AI 不响应决斗）
				if cont:
					current.hand.pop_back()
					_update_debug("%s 再出【杀】响应【决斗】（【霸王】需两张）" % current.player_name)
				else:
					_update_debug("%s 放弃继续响应，在【决斗】中失败" % current.player_name)
					await _deal_damage(other, current, 1 + _rage_bonus(other), EffectChain.DamageType.PHYSICAL)
					break
			# 交换攻守
			var tmp = current
			current = other
			other = tmp
		else:
			# 无法出杀 → 受伤害（伤害来源 = 决斗对手；【暴怒】布鲁斯·萨维奇作为伤害来源时附加已损失体力值伤害）
			_update_debug("%s 在【决斗】中无法出【杀】" % current.player_name)
			await _deal_damage(other, current, 1 + _rage_bonus(other), EffectChain.DamageType.PHYSICAL)
			break

	_sync_all_ui()

# 决斗响应弹窗（玩家0）：needs_two = 【霸王】下对方需依次打出两张杀
func _show_duel_prompt(needs_two: bool = false) -> bool:
	if _duel_respond_override.is_valid():
		return _duel_respond_override.call()
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	if needs_two:
		label.text = "【决斗】！请出【杀】响应（【霸王】：需依次打出两张【杀】），\n否则受到 1 点伤害"
	else:
		label.text = "【决斗】！请出【杀】响应，\n否则受到 1 点伤害"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(500, 60)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	var respond_btn = Button.new()
	respond_btn.text = "出【杀】"
	respond_btn.custom_minimum_size = Vector2(160, 44)
	hbox.add_child(respond_btn)

	var skip_btn = Button.new()
	skip_btn.text = "放弃（受伤害）"
	skip_btn.custom_minimum_size = Vector2(160, 44)
	hbox.add_child(skip_btn)

	var result = [false]
	respond_btn.pressed.connect(func():
		result[0] = true
		overlay.queue_free()
		_response_ready.emit()
	, CONNECT_ONE_SHOT)
	skip_btn.pressed.connect(func():
		result[0] = false
		overlay.queue_free()
		_response_ready.emit()
	, CONNECT_ONE_SHOT)

	_start_response_countdown(overlay, players[0].player_name, func(): _response_ready.emit())
	await _response_ready
	_stop_countdown()
	return result[0]

# 【霸王】第二张杀询问（玩家0）：打出第一张杀后，询问是否继续响应
func _show_duel_second_strike_prompt() -> bool:
	if _duel_second_override.is_valid():
		return _duel_second_override.call()
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = "由于【霸王】技能你需要再打出 1 张【杀】，是否继续响应？\n（放弃则受到 1 点伤害）"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(500, 60)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	var cont_btn = Button.new()
	cont_btn.text = "继续响应"
	cont_btn.custom_minimum_size = Vector2(160, 44)
	hbox.add_child(cont_btn)

	var give_btn = Button.new()
	give_btn.text = "放弃（受伤害）"
	give_btn.custom_minimum_size = Vector2(160, 44)
	hbox.add_child(give_btn)

	var result = [false]
	cont_btn.pressed.connect(func():
		result[0] = true
		overlay.queue_free()
		_response_ready.emit()
	, CONNECT_ONE_SHOT)
	give_btn.pressed.connect(func():
		result[0] = false
		overlay.queue_free()
		_response_ready.emit()
	, CONNECT_ONE_SHOT)

	_start_response_countdown(overlay, players[0].player_name, func(): _response_ready.emit())
	await _response_ready
	_stop_countdown()
	return result[0]

# ============================
#  火烧连营
# ============================

# 火烧连营伤害结算：中心角色 → 左侧（下家 seat+1）→ 右侧（上家 seat-1），各受 amount 点火焰伤害
# 每个受伤者独立濒死检查 + 铁索传导（火焰伤害）
func _resolve_burning_camp_damage(source: Player, center: Player, amount: int):
	var left = players[(center.seat_index + 1) % player_count]
	var right = players[(center.seat_index - 1 + player_count) % player_count]

	var victims = [center, left, right]
	var victim_names = [center.player_name, left.player_name, right.player_name]
	_update_debug("火焰蔓延：%s（顺序：%s）" % [victim_names[0], "、".join(victim_names)])

	for victim in victims:
		if not victim.is_alive():
			continue
		# 胜负已分：不再结算后续伤害
		if _game_over:
			break
		await _deal_damage(source, victim, amount, EffectChain.DamageType.FIRE)

	_sync_all_ui()

# 在目标判定区生成一张火烧连营（判定区已有火烧连营则不重复，防止无限蔓延）
func _spawn_burning_camp(target: Player, source_seat: int):
	if not target.is_alive():
		return
	for c in target.judgment_cards:
		if c.sub_type == CardData.CardSubType.BURNING_CAMP:
			return
	var card = CardBase.create(CardData.CardSubType.BURNING_CAMP)
	card.source_seat = source_seat
	target.judgment_cards.append(card)
	_update_debug("%s 的判定区生成了一张【火烧连营】" % target.player_name)

# ============================
#  无懈可击
# ============================

# 无懈可击链式询问：任何锦囊/判定生效前调用
# desc = 第一轮提示文本。返回 true = 效果最终被无懈可击抵消
# 规则：有人打出无懈 → 再问所有人是否反无懈 → 交替直到无人响应
func _ask_nullification_chain(desc: String) -> bool:
	var pending: bool = false        # 当前是否有一张生效中的无懈
	var round_desc: String = desc
	while true:
		var actor_name = await _ask_nullification_round(round_desc)
		if actor_name == "":
			return pending
		pending = not pending
		round_desc = "%s打出了1张【无懈可击】，是否打出一张【无懈可击】？" % actor_name
	return false

# 询问一轮：按座位顺序询问所有存活角色，返回打出无懈的玩家名（无人打出返回 ""）
func _ask_nullification_round(desc: String) -> String:
	for i in range(player_count):
		var p = players[i]
		if not p.is_alive():
			continue
		# 【下跪】：无法使用或打出任何牌 → 不询问
		if _is_kneeling(p):
			continue
		var played = "skip"
		if p.seat_index == 0:
			played = await _show_nullification_prompt(desc, p)
		else:
			# AI 暂不主动响应无懈
			played = "skip"
		if played != "skip":
			# 【是~啊~】（安普提·斯丢皮得）：确认使用无懈可击后询问是否发动（发动流失体力不消耗手牌；无手牌时取消 = 视为没有打出）
			var yes_ah = played
			if yes_ah == "card":
				yes_ah = await _ask_yes_ah(p, "无懈可击", p.hand_size() > 0)
			if yes_ah == "cancel":
				_update_debug("%s 取消了打出【无懈可击】" % p.player_name)
				_sync_all_ui()
				return ""
			if yes_ah == "skill":
				if not await _pay_yes_ah_cost(p):
					_sync_all_ui()
					return ""
			else:
				p.hand.pop_back()
				deck.discard(CardBase.create(CardData.CardSubType.NULLIFICATION))
			_update_debug("%s 打出了【无懈可击】" % p.player_name)
			_sync_all_ui()
			# 【苕】任意玩家行动后询问是否明置
			await _maybe_ask_reveal()
			return p.player_name
	return ""

# 玩家0的无懈响应弹窗（锚点居中）：返回 "card"（打出无懈，消耗手牌）/ "skill"（发动【是~啊~】打出，无手牌时）/ "skip"（放弃）
func _show_nullification_prompt(desc: String, p: Player) -> String:
	var has_hand = p.hand_size() > 0
	var is_yes_ah = p.general_name == "安普提·斯丢皮得"
	# 测试钩子：只决定「是否愿意出」；无手牌时仅安普提可通过【是~啊~】打出
	if _nullify_override.is_valid():
		if not _nullify_override.call():
			return "skip"
		return "card" if has_hand else ("skill" if is_yes_ah else "skip")

	if not has_hand and not is_yes_ah:
		return "skip"

	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = desc
	if not has_hand:
		label.text += "\n（无手牌，可发动【是~啊~】流失 1 点体力视为打出）"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(600, 80)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	var nullify_btn = Button.new()
	nullify_btn.text = "打出【无懈可击】" if has_hand else "发动【是~啊~】打出"
	nullify_btn.custom_minimum_size = Vector2(180, 44)
	hbox.add_child(nullify_btn)

	var skip_btn = Button.new()
	skip_btn.text = "放弃" if has_hand else "取消"
	skip_btn.custom_minimum_size = Vector2(180, 44)
	skip_btn.modulate = Color(0.7, 0.7, 0.7)
	hbox.add_child(skip_btn)

	var result = ["skip"]
	nullify_btn.pressed.connect(func():
		result[0] = "card" if has_hand else "skill"
		overlay.queue_free()
		_response_ready.emit()
	, CONNECT_ONE_SHOT)
	skip_btn.pressed.connect(func():
		result[0] = "skip"
		overlay.queue_free()
		_response_ready.emit()
	, CONNECT_ONE_SHOT)

	_start_response_countdown(overlay, players[0].player_name, func(): _response_ready.emit())
	await _response_ready
	_stop_countdown()
	return result[0]

# ---- 效果链回调 ----

signal _response_ready
signal _zone_pick_result(zone: String)
signal _equip_pick_result(slot: String)
signal _iron_chain_cfm_result(result: bool)
signal _mount_replace_result(slot: String)
signal _weapon_replace_result(result: bool)
signal _zhangba_result(value: int)
signal _rps_pick_result(choice: int)
signal _calamity_target_result(target: Player)
# 灾厄袍转移目标选择结果（独立 signal，避免与灾厄剑并发干扰）
signal _calamity_robe_target_result(target: Player)
# 劣马转移目标选择结果（-1/+1 各自独立，避免并发干扰）
signal _minus_mule_target_result(target: Player)
signal _plus_mule_target_result(target: Player)

# 【八卦阵】：你每使用或打出一张【闪】时，摸一张牌（锁定技；装备者判定）
func _try_bagua_draw(p: Player):
	if p == null or not p.is_alive():
		return
	if p.get_armor() != CardData.CardSubType.BAGUA_ZHEN:
		return
	_draw_blank_cards(p, 1)
	_update_debug("%s 发动【八卦阵】：使用【闪】，摸一张牌（手牌 %d 张）" % [p.player_name, p.hand_size()])
	_sync_all_ui()

# 【烈火盾】：当你要失去一张牌时，可流失 1 点体力代替（牌保留不失去）
# 返回 true = 已支付体力，牌不失去；false = 正常失去
func _maybe_liehuo_save(p: Player) -> bool:
	if p == null or not p.is_alive():
		return false
	if p.get_armor() != CardData.CardSubType.LIEHUO_SHIELD:
		return false
	var use = await _ask_liehuo(p)
	if not use:
		return false
	p.hp -= 1  # 流失体力（不算受到伤害，不触发防具/舍己为人等）
	_update_debug("%s 发动【烈火盾】：流失 1 点体力，代替失去一张牌（%d/%d）" % [p.player_name, p.hp, p.max_hp])
	_sync_all_ui()
	# 流失导致濒死 → 先处理（与丈八蛇矛一致）
	if p.is_dying():
		await _check_dying(p)
		if p.is_dying():
			_handle_death(p, null)  # 流失致死无击杀者
	return true

# 询问是否发动烈火盾：玩家0弹窗，AI 默认不发动
func _ask_liehuo(p: Player) -> bool:
	if _liehuo_override.is_valid():
		return _liehuo_override.call()
	if p.seat_index == 0:
		return await _show_liehuo_prompt()
	return false  # AI 暂不主动发动

# 玩家0的【烈火盾】响应弹窗（锚点居中）
func _show_liehuo_prompt() -> bool:
	# 测试钩子：跳过 UI 直接返回
	if _liehuo_override.is_valid():
		return _liehuo_override.call()

	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = "【烈火盾】！你将失去一张牌\n是否流失 1 点体力代替？"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(600, 80)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	var pay_btn = Button.new()
	pay_btn.text = "流失 1 点体力代替"
	pay_btn.custom_minimum_size = Vector2(180, 44)
	hbox.add_child(pay_btn)

	var lose_btn = Button.new()
	lose_btn.text = "失去这张牌"
	lose_btn.custom_minimum_size = Vector2(180, 44)
	lose_btn.modulate = Color(0.7, 0.7, 0.7)
	hbox.add_child(lose_btn)

	var result = [false]
	pay_btn.pressed.connect(func():
		result[0] = true
		overlay.queue_free()
		_response_ready.emit()
	, CONNECT_ONE_SHOT)
	lose_btn.pressed.connect(func():
		result[0] = false
		overlay.queue_free()
		_response_ready.emit()
	, CONNECT_ONE_SHOT)

	await _response_ready
	return result[0]

func _on_chain_response_check(chain: EffectChain, responder: Player, expected_sub: CardData.CardSubType, attacker: Player) -> bool:
	if expected_sub != CardData.CardSubType.DODGE:
		return false
	if HandPayment.find_index(responder.hand, expected_sub) < 0:
		return false
	# 【下跪】：无法使用或打出任何牌 → 不能出闪
	if _is_kneeling(responder):
		return false

	var responder_idx = -1
	for i in players.size():
		if players[i] == responder:
			responder_idx = i
			break
	if responder_idx < 0:
		return false

	_play_btn.visible = false
	_end_play_btn.visible = false
	_cancel_target_btn.visible = false
	_confirm_target_btn.visible = false
	turn_manager.start_waiting("dodge_for_strike", responder_idx)

	var dodged = false
	if _dodge_override.is_valid():
		# 测试钩子：模拟响应者打出【闪】（对任意响应者生效，含 AI）
		dodged = _dodge_override.call()
	elif responder_idx == 0:
		dodged = await _show_dodge_prompt(attacker.player_name if attacker != null else "已失去来源的效果", "杀")
	else:
		dodged = false

	turn_manager.end_waiting()

	if turn_manager.current_player_idx == 0:
		_play_btn.visible = true
		_end_play_btn.visible = true
		_sync_all_ui()

	if dodged:
		# 弹窗返回后重新验证；没有合法闪时按未响应处理，不扣除其他类型。
		if not responder.is_alive() or _is_kneeling(responder):
			return false
		var used_dodge = HandPayment.take(responder.hand, expected_sub)
		if used_dodge == null:
			return false
		deck.discard(used_dodge)
		# 【八卦阵】：使用/打出【闪】时摸一张牌（杀→闪路径）
		if expected_sub == CardData.CardSubType.DODGE:
			_try_bagua_draw(responder)
		_sync_all_ui()
		return true
	return false

func _show_dodge_prompt(attacker_name: String, card_name: String) -> bool:
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = "%s 对你使用了【%s】\n是否出【闪】响应？" % [attacker_name, card_name]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(500, 60)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	var dodge_btn = Button.new()
	dodge_btn.text = "出【闪】"
	dodge_btn.custom_minimum_size = Vector2(160, 44)
	hbox.add_child(dodge_btn)

	var skip_btn = Button.new()
	skip_btn.text = "不响应"
	skip_btn.custom_minimum_size = Vector2(160, 44)
	hbox.add_child(skip_btn)

	var result = [false]
	dodge_btn.pressed.connect(func():
		result[0] = true
		overlay.queue_free()
		_response_ready.emit()
	, CONNECT_ONE_SHOT)
	skip_btn.pressed.connect(func():
		result[0] = false
		overlay.queue_free()
		_response_ready.emit()
	, CONNECT_ONE_SHOT)

	_start_response_countdown(overlay, players[0].player_name, func(): _response_ready.emit())
	await _response_ready
	_stop_countdown()
	return result[0]

signal _target_cfm_result(result: bool)

# 选择目标后的确认弹窗
func _show_target_confirm(attacker_name: String, target_name: String, sub: CardData.CardSubType) -> bool:
	# 测试钩子：跳过 UI 直接返回
	if _target_confirm_override.is_valid():
		return _target_confirm_override.call()

	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = "是否对 %s 打出一张【%s】？" % [target_name, CardData.get_type_name(sub)]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(500, 60)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	var yes_btn = Button.new()
	yes_btn.text = "是"
	yes_btn.custom_minimum_size = Vector2(160, 44)
	hbox.add_child(yes_btn)

	var no_btn = Button.new()
	no_btn.text = "否"
	no_btn.custom_minimum_size = Vector2(160, 44)
	hbox.add_child(no_btn)

	yes_btn.pressed.connect(func():
		overlay.queue_free()
		_target_cfm_result.emit(true)
	, CONNECT_ONE_SHOT)
	no_btn.pressed.connect(func():
		overlay.queue_free()
		_target_cfm_result.emit(false)
	, CONNECT_ONE_SHOT)

	var result = await _target_cfm_result
	return result

func _on_chain_trigger(chain: EffectChain, event_name: String, subject: Player, source: Player, data: Dictionary) -> bool:
	var record = chain.damage
	if event_name == "on_being_targeted":
		if not record.sacrifice_offered:
			record.sacrifice_offered = true
			var substitute = await _maybe_sacrifice(source, subject, chain.effect_value, chain.damage_element)
			if substitute != null:
				chain.target_player = substitute
				_update_debug("%s 打出【舍己为人】，成为【杀】的新目标，可正常出闪" % substitute.player_name)
				return false # EffectChain 会为新目标重新发出“成为目标”事件。
		return not await _prepare_strike_target(source, subject, chain.ignore_target_restrictions)

	if event_name == "before_deal_damage":
		if record.source_modifiers_applied:
			return false
		record.source_modifiers_applied = true
		# 非杀伤害保留原有代受入口；传导不重复代受或源侧数值修正。
		if not record.from_strike and not record.is_chain and not record.sacrifice_offered:
			record.sacrifice_offered = true
			var substitute = await _maybe_sacrifice(subject, chain.target_player, chain.effect_value, chain.damage_element)
			if substitute != null:
				chain.target_player = substitute
		var actual = chain.target_player
		if subject == null or record.is_chain:
			return false
		var weapon = subject.get_weapon()
		var weapon_enabled = actual.get_armor() != CardData.CardSubType.QINGGANG_SHIELD
		if record.from_strike and weapon_enabled:
			if weapon == CardData.CardSubType.ICE_SWORD and actual.hand_size() >= 2:
				var use_ice = subject.seat_index != 0 or await _ask_ice_sword(actual.player_name)
				if use_ice:
					for i in range(2):
						deck.discard(actual.hand.pop_back())
					_update_debug("%s 发动【寒冰剑】：防止本次伤害，弃置 %s 两张手牌" % [subject.player_name, actual.player_name])
					_sync_all_ui()
					return true
			if weapon == CardData.CardSubType.ZHANGBA_SPEAR:
				var extra = clampi(await _ask_zhangba_extra(subject), 0, 3)
				if extra > 0:
					var rage_before = _rage_bonus(subject)
					subject.hp -= extra
					_update_debug("%s 流失 %d 点体力（发动【丈八蛇矛】，尚未造成伤害）" % [subject.player_name, extra])
					if subject.is_dying():
						await _check_dying(subject)
						if subject.is_dying():
							_handle_death(subject, null)
					# 原始基础值已经含暴怒；只更新差额，不能重复加整个已损失体力。
					var rage_delta = _rage_bonus(subject) - rage_before if not subject.is_dead() else 0
					data["value"] += extra + rage_delta
			if weapon == CardData.CardSubType.GUDING_BLADE and actual.hand_size() == 0:
				data["value"] += 1
		if weapon_enabled and weapon == CardData.CardSubType.CALAMITY_SWORD:
			data["value"] = maxi(data["value"] - 1, 0)

	if event_name == "before_take_damage":
		if record.target_modifiers_applied:
			return false
		record.target_modifiers_applied = true
		if subject == null or subject.is_dead():
			return true
		if await _try_paixiong_block(subject, source):
			data["value"] = 0
			return true
		var ignore_armor = record.from_strike and not record.is_chain and source != null \
			and source.get_weapon() == CardData.CardSubType.QINGGANG_SWORD
		var armor = subject.get_armor()
		if not ignore_armor:
			if (armor == CardData.CardSubType.QIXING_PAO and chain.damage_element != EffectChain.DamageType.PHYSICAL) \
					or (armor == CardData.CardSubType.BAIHUA_SKIRT and subject.hp == 1):
				data["value"] = 0
				return true
			if armor == CardData.CardSubType.SILVER_LION or (record.from_strike and armor == CardData.CardSubType.ZHANQI):
				data["value"] = mini(data["value"], 1)
			if armor == CardData.CardSubType.CALAMITY_ROBE and chain.damage_element == EffectChain.DamageType.FIRE:
				data["value"] += 1
		if await _try_fate_blade_save(subject, data["value"]):
			data["value"] = 0
			return true

	if event_name == "damage_applied":
		_update_debug("%s 受到 %d 点伤害" % [subject.player_name, data["damage"]])
		_sync_all_ui()
		if subject.is_dying():
			await _check_dying(subject)
			await rule_scheduler.checkpoint(chain, "before_death")
			if subject.is_dying():
				_handle_death(subject, source)
		# before_death checkpoint 也可能救回目标；重查被普通救援延后的终局。
		_check_win_condition(null, null)
		return false

	if event_name == "after_deal_damage" and subject != null and subject.is_alive():
		_trigger_pofeng(subject, data["damage"])
		await _try_gou_lian_claw(subject, chain.target_player)
		await _try_bloodthirsty(subject, chain.target_player, data["damage"])
		_update_soul_blade_count(subject, chain.target_player, data["damage"])
		if record.from_strike and not record.is_chain:
			await _try_soul_blade(subject, chain.target_player)
		await _try_kaiwen_deal(subject, chain.target_player, data["damage"])

	if event_name == "after_take_damage" and subject != null and subject.is_alive():
		await _try_thorn_counter(subject, source, data["damage"])
		await _try_kaiwen_receive(subject, source, data["damage"])
	return false
func _try_thorn_counter(victim: Player, source: Player, amount: int):
	if source == null or victim == null or source == victim:
		return
	if not victim.is_alive() or not source.is_alive():
		return
	if victim.get_armor() != CardData.CardSubType.THORN_ARMOR:
		return
	for i in amount:
		if not victim.is_alive() or not source.is_alive():
			break
		var r = await _do_ping_dian_once(victim, source)
		if r == RPS_WIN:
			_update_debug("%s 的【荆棘战甲】拼点获胜，对 %s 造成 1 点伤害！" % [victim.player_name, source.player_name])
			await _deal_damage(victim, source, 1, EffectChain.DamageType.PHYSICAL)
	_sync_all_ui()

# ============================
#  【你个壊货】（凯文·罗本）
# ============================

# 受到伤害时：victim 是凯文，与伤害来源 source 拼点，赢摸两张
func _try_kaiwen_receive(victim: Player, source: Player, amount: int):
	await _try_kaiwen_ping(victim, source, amount, true)

# 造成伤害时：source 是凯文，与受伤目标 victim 拼点，赢摸两张
func _try_kaiwen_deal(source: Player, victim: Player, amount: int):
	await _try_kaiwen_ping(victim, source, amount, false)

# 核心：可选发动（玩家0弹窗 / AI 默认发动），按伤害点数逐点触发，赢摸两张
# is_receive = true 表示凯文是受伤方（victim），false 表示凯文是伤害来源（source）
func _try_kaiwen_ping(victim: Player, source: Player, amount: int, is_receive: bool):
	var kaiwen: Player = victim if is_receive else source
	var opponent: Player = source if is_receive else victim
	if kaiwen == null or opponent == null or kaiwen == opponent:
		return
	if kaiwen.general_name != "凯文·罗本":
		return
	if not kaiwen.is_alive() or not opponent.is_alive():
		return
	for i in amount:
		if not kaiwen.is_alive() or not opponent.is_alive():
			break
		# 伤害效果先展示（日志 + 体力变化），稍作停顿再询问是否发动
		await get_tree().create_timer(0.8).timeout
		var use = await _ask_kaiwen(kaiwen, opponent, is_receive)
		if not use:
			continue
		# 拼点结果（出拳 + 胜负，按胜负着色）由 _do_ping_dian_once 输出，这里不再补日志覆盖它
		var r = await _do_ping_dian_once(kaiwen, opponent)
		if r == RPS_WIN:
			_draw_blank_cards(kaiwen, 2)
	_sync_all_ui()

# 询问是否发动【你个壊货】：玩家0弹窗，AI 默认发动（摸牌收益）
func _ask_kaiwen(kaiwen: Player, opponent: Player, is_receive: bool) -> bool:
	if _kaiwen_override.is_valid():
		return _kaiwen_override.call()
	if kaiwen.seat_index == 0:
		return await _show_kaiwen_prompt(opponent.player_name, is_receive)
	return true

func _show_kaiwen_prompt(opponent_name: String, is_receive: bool) -> bool:
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	if is_receive:
		label.text = "%s 对你造成了伤害\n是否发动【你个壊货】与其拼点？\n（赢则摸两张牌）" % opponent_name
	else:
		label.text = "你对 %s 造成了伤害\n是否发动【你个壊货】与其拼点？\n（赢则摸两张牌）" % opponent_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(500, 80)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	var use_btn = Button.new()
	use_btn.text = "发动拼点"
	use_btn.custom_minimum_size = Vector2(160, 44)
	hbox.add_child(use_btn)

	var skip_btn = Button.new()
	skip_btn.text = "不发动"
	skip_btn.custom_minimum_size = Vector2(160, 44)
	skip_btn.modulate = Color(0.7, 0.7, 0.7)
	hbox.add_child(skip_btn)

	var result = [false]
	use_btn.pressed.connect(func():
		result[0] = true
		overlay.queue_free()
		_response_ready.emit()
	, CONNECT_ONE_SHOT)
	skip_btn.pressed.connect(func():
		result[0] = false
		overlay.queue_free()
		_response_ready.emit()
	, CONNECT_ONE_SHOT)

	_start_response_countdown(overlay, players[0].player_name, func(): _response_ready.emit())
	await _response_ready
	_stop_countdown()
	return result[0]

# 所有伤害统一走这里：
#   ① 询问【舍己为人】（其他玩家可代替受伤者承受等量同属性伤害）
#   ② 施加伤害
#   ③ 濒死检查
#   ④ 属性伤害且实际受伤者处于连环状态 → 铁索传导（传导伤害本身不再拦截/二次传导）
# source 可为 null（边界情况），此时不触发铁索传导
# 返回实际受伤者
func _deal_damage(source: Player, target: Player, amount: int, element: EffectChain.DamageType) -> Player:
	if target == null or target.is_dead() or amount <= 0:
		return target
	var chain = _new_damage_chain(source, target, null, amount, element)
	chain.skip_targeting = true
	chain.skip_response = true
	await chain.start()
	await _finish_damage_chain(chain)
	if chain.damage.committed:
		await _try_calamity_transfer(chain.source_player)
	await _maybe_ask_reveal()
	return chain.target_player

func _trigger_pofeng(source: Player, amount: int):
	if source == null or amount <= 0:
		return
	if source.get_weapon() != CardData.CardSubType.POFENG_SPEAR:
		return
	source.hand_limit_bonus += amount
	_update_debug("%s 发动【破风枪】：造成 %d 点伤害，手牌上限 +%d（当前上限 %d）" % [source.player_name, amount, amount, source.hand_limit()])
	_sync_all_ui()

# ============================
#  【命运之刃】保命判定
# ============================

# 目标将要受到致命伤害（伤害 ≥ 当前体力）且装备【命运之刃】时，可弃置此武器防止本次伤害
# 返回 true = 已弃置命运之刃并防止本次伤害（调用方应跳过伤害施加）
func _try_fate_blade_save(victim: Player, amount: int) -> bool:
	if victim == null or not victim.is_alive():
		return false
	if victim.get_weapon() != CardData.CardSubType.FATE_BLADE:
		return false
	if amount < victim.hp:
		return false  # 非致命伤害，不触发

	var use = await _ask_fate_blade(victim)
	if not use:
		return false

	# 弃置命运之刃（进入弃牌堆）；装备占用永久保留（唯一性规则）
	victim.remove_equipment("weapon")
	deck.discard(CardBase.create(CardData.CardSubType.FATE_BLADE))
	_update_debug("%s 弃置【命运之刃】，防止了 %d 点致命伤害！" % [victim.player_name, amount])
	_sync_all_ui()
	return true

# 询问是否发动命运之刃：玩家0弹窗，AI 默认发动（保命）
func _ask_fate_blade(victim: Player) -> bool:
	if victim.seat_index == 0:
		return await _show_fate_blade_prompt(victim)
	return true  # AI 默认发动

# 玩家0的【命运之刃】响应弹窗（锚点居中）
func _show_fate_blade_prompt(victim: Player) -> bool:
	# 测试钩子：只决定「是否弃置」，没装备照样弃不了
	if _fate_blade_override.is_valid():
		return _fate_blade_override.call()

	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = "你将受到致命伤害！\n是否弃置【命运之刃】防止本次伤害？"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(600, 80)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	var use_btn = Button.new()
	use_btn.text = "弃置【命运之刃】"
	use_btn.custom_minimum_size = Vector2(180, 44)
	hbox.add_child(use_btn)

	var skip_btn = Button.new()
	skip_btn.text = "放弃"
	skip_btn.custom_minimum_size = Vector2(180, 44)
	skip_btn.modulate = Color(0.7, 0.7, 0.7)
	hbox.add_child(skip_btn)

	var result = [false]
	use_btn.pressed.connect(func():
		result[0] = true
		overlay.queue_free()
		_response_ready.emit()
	, CONNECT_ONE_SHOT)
	skip_btn.pressed.connect(func():
		result[0] = false
		overlay.queue_free()
		_response_ready.emit()
	, CONNECT_ONE_SHOT)

	await _response_ready
	return result[0]

# ============================
#  【勾镰爪】获得坐骑
# ============================

# 对一名角色造成伤害后，可获得其装备区里的一张坐骑牌（进入自己「已确定的牌」区）
# 时机与破风枪一致（伤害施加后立即触发，濒死结算前）；目标已濒死（体力≤0）或与自己相同（舍己为人自转移）不触发
func _try_gou_lian_claw(source: Player, victim: Player):
	if source == null or victim == null or source == victim:
		return
	if not source.is_alive() or not victim.is_alive():
		return
	if source.get_weapon() != CardData.CardSubType.GOU_LIAN_CLAW:
		return
	# 【青釭盾】：目标无视使用效果者的武器
	if victim.get_armor() == CardData.CardSubType.QINGGANG_SHIELD:
		_update_debug("%s 的【青釭盾】无视了 %s 的【勾镰爪】！" % [victim.player_name, source.player_name])
		return
	var slots = victim.get_mount_slots()
	if slots.is_empty():
		return

	var slot: String
	if source.seat_index == 0:
		slot = await _ask_gou_lian_slot(victim, slots)
		if slot == "" or slot == "cancel":
			_update_debug("%s 放弃发动【勾镰爪】" % source.player_name)
			return
	else:
		# AI 默认发动，随机选一匹
		slot = slots[randi() % slots.size()]

	var sub = victim.equipment[slot]
	victim.remove_equipment(slot)
	var card = CardBase.create(sub)
	source.determined_cards.append(card)
	_update_debug("%s 发动【勾镰爪】：获得 %s 的坐骑【%s】（已确定的牌 %d 张）" % [
		source.player_name, victim.player_name, CardData.get_type_name(sub), source.determined_cards.size()
	])
	_sync_all_ui()

# 玩家0选择要获得的坐骑（可取消）：复用装备选择弹窗
func _ask_gou_lian_slot(victim: Player, slots: Array[String]) -> String:
	# 测试钩子：直接返回槽位或 "cancel"
	if _gou_lian_slot_override.is_valid():
		return _gou_lian_slot_override.call()
	return await _show_equip_picker(victim, slots, "你造成了伤害\n选择要获得的坐骑（可取消）：")

# ============================
#  猜拳拼点（石头/剪刀/布）
# ============================

# 猜拳判定：a 对 b，返回 a 视角结果（RPS_WIN / RPS_DRAW / RPS_LOSE）
func _rps_result(a: int, b: int) -> int:
	if a == b:
		return RPS_DRAW
	if (a == RPS_ROCK and b == RPS_SCISSORS) \
			or (a == RPS_SCISSORS and b == RPS_PAPER) \
			or (a == RPS_PAPER and b == RPS_ROCK):
		return RPS_WIN
	return RPS_LOSE

# 出拳：玩家0弹窗，AI 随机；测试钩子可指定任意玩家
func _rps_choice(p: Player, other_name: String) -> int:
	if _rps_override.is_valid():
		return _rps_override.call(p)
	if p.seat_index == 0:
		return await _show_rps_prompt(p, other_name)
	return randi() % 3

# 玩家0的猜拳弹窗（石头/剪刀/布，锚点居中）
func _show_rps_prompt(p: Player, other_name: String) -> int:
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = "【拼点】你 VS %s\n请出拳：" % other_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(500, 60)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	var choices = [
		["石头", RPS_ROCK],
		["剪刀", RPS_SCISSORS],
		["布", RPS_PAPER],
	]
	for c in choices:
		var btn = Button.new()
		btn.text = c[0]
		btn.custom_minimum_size = Vector2(140, 44)
		btn.pressed.connect(_emit_rps_pick.bind(overlay, c[1]), CONNECT_ONE_SHOT)
		hbox.add_child(btn)

	_start_response_countdown(overlay, players[0].player_name, func(): _rps_pick_result.emit(RPS_PAPER))
	var result = await _rps_pick_result
	_stop_countdown()
	return result

func _emit_rps_pick(overlay: ColorRect, choice: int):
	overlay.queue_free()
	_rps_pick_result.emit(choice)

# 进行一次拼点（猜拳一轮）：返回发起者视角结果（RPS_WIN / RPS_DRAW / RPS_LOSE）
# 结果只在实时日志显示（上一行），不覆盖中间提示句（当前进行）——所有拼点统一行为
func _do_ping_dian_once(challenger: Player, opponent: Player) -> int:
	var a = await _rps_choice(challenger, opponent.player_name)
	var b = await _rps_choice(opponent, challenger.player_name)
	var r = _rps_result(a, b)
	# 猜拳常量：石头=0 / 布=1 / 剪刀=2（与按钮映射一致，勿把 names 写成 剪刀/布 顺序）
	var names = ["石头", "布", "剪刀"]
	var r_name = "平局"
	var result_color = Color(0.85, 0.85, 0.85)
	if r == RPS_WIN:
		r_name = "%s 胜" % challenger.player_name
		result_color = Color(0.4, 1, 0.4)
	elif r == RPS_LOSE:
		r_name = "%s 胜" % opponent.player_name
		result_color = Color(1, 0.4, 0.4)
	var result_msg = "【拼点】%s 出【%s】，%s 出【%s】——%s" % [challenger.player_name, names[a], opponent.player_name, names[b], r_name]
	# 实时日志（带色，5 秒）：拼点结果只显示在上一行，不覆盖中间提示句
	_update_debug(result_msg, result_color)
	return r

# 进行拼点（平局后继续，直到分出胜负）：返回发起者视角结果（RPS_WIN / RPS_LOSE）
func _do_ping_dian(challenger: Player, opponent: Player) -> int:
	var r = await _do_ping_dian_once(challenger, opponent)
	while r == RPS_DRAW:
		_update_debug("平局，继续拼点！")
		r = await _do_ping_dian_once(challenger, opponent)
	return r

# ============================
#  【是~啊~】锦囊白嫖（安普提·斯丢皮得）
# ============================

# 使用锦囊牌时询问是否发动【是~啊~】：
# has_hand = 当前是否有手牌可消耗；返回 "skill"（发动，流失体力不消耗手牌）/ "card"（不发动，照常消耗）/ "cancel"（取消，视为没有打出）
func _ask_yes_ah(p: Player, card_name: String, has_hand: bool) -> String:
	if p.general_name != "安普提·斯丢皮得" or not p.is_alive():
		return "card" if has_hand else "cancel"
	if _yes_ah_override.is_valid():
		return _yes_ah_override.call()
	if p.seat_index != 0:
		return "card" if has_hand else "cancel"  # AI 暂不发动
	return await _show_yes_ah_prompt(card_name, has_hand)

# 玩家0 的【是~啊~】询问弹窗（复用通用选择弹窗）
func _show_yes_ah_prompt(card_name: String, has_hand: bool) -> String:
	var idx = await _show_choice_popup("是否发动【是~啊~】？\n（流失 1 点体力，视为使用了一张【%s】，不消耗手牌）" % card_name, ["发动【是~啊~】", "不发动（消耗手牌）" if has_hand else "取消（视为没有打出）"])
	if idx == 0:
		return "skill"
	if idx == 1 and has_hand:
		return "card"
	return "cancel"

# 支付【是~啊~】代价：流失 1 点体力（直接减，不算受到伤害）；流失致死先走濒死检查
# 返回 false = 流失后未救回（本次锦囊/响应视为没有打出，调用方应中止）
func _pay_yes_ah_cost(p: Player) -> bool:
	if p == null or not p.is_alive():
		return false
	p.hp -= 1
	_update_debug("%s 发动【是~啊~】：流失 1 点体力（%d/%d）" % [p.player_name, p.hp, p.max_hp])
	if p.is_dying():
		await _check_dying(p)
		if p.is_dying():
			_handle_death(p, null)  # 流失致死无击杀者
	return p.is_alive()

# 取得本次使用的锦囊资源，不决定其去向。延时锦囊直接入判定区，不能同时进弃牌堆。
func _take_trick_card(p: Player, sub: CardData.CardSubType) -> CardBase:
	if _yes_ah_active:
		_yes_ah_active = false
		if not await _pay_yes_ah_cost(p):
			return null
		return CardBase.create(sub)
	var card = HandPayment.take(p.hand, sub)
	if card == null:
		_update_debug("没有可用的【%s】或任意牌，未支付费用" % CardData.get_type_name(sub))
	return card

# 即时锦囊消耗入口：支付成功才记入弃牌；技能视为使用沿用原有不生成实体弃牌的约定。
func _consume_trick(p: Player, sub: CardData.CardSubType) -> bool:
	var virtual_use := _yes_ah_active
	var card = await _take_trick_card(p, sub)
	if card == null:
		return false
	if not virtual_use:
		deck.discard(card)
	return true

# ============================
#  【苕】暗置装备（安普提·斯丢皮得）
# ============================

# 点击技能【苕】：未暗置 → 选类型暗置；已暗置 → 明置 / 替换 / 取消
func _on_sao_skill_clicked(p: Player) -> void:
	if p.general_name != "安普提·斯丢皮得":
		return
	if p.seat_index != 0:
		_update_debug("只能对自己使用【苕】")
		return
	if p.has_hidden_equip():
		var idx: int
		if _sao_menu_override.is_valid():
			idx = _sao_menu_override.call()
		else:
			idx = await _show_choice_popup("你已暗置了一件装备\n要做什么？", ["明置装备", "替换暗置类型"])
		if idx == 0:
			await _do_sao_reveal(p)
		elif idx == 1:
			await _do_sao_hide(p, true)
		return
	await _do_sao_hide(p, false)

# 暗置：选类型 → 检查槽位 → 放置占位（replace = 替换已有暗置）
func _do_sao_hide(p: Player, replace: bool) -> void:
	var etype: String
	if _sao_type_override.is_valid():
		var ov = _sao_type_override.call()
		if ov == "cancel":
			return
		etype = ov
	else:
		var idx = await _show_choice_popup("选择暗置的装备类型：", ["武器", "防具", "马"])
		if idx < 0:
			return
		etype = ["weapon", "armor", "mount"][idx]
	match etype:
		"weapon":
			if p.equipment.has("weapon") and p.hidden_equip_slot != "weapon":
				_update_debug("武器槽已有装备，无法暗置武器")
				return
		"armor":
			if p.equipment.has("armor") and p.hidden_equip_slot != "armor":
				_update_debug("防具槽已有装备，无法暗置防具")
				return
		"mount":
			if not p.has_free_mount_slot() and p.get_hidden_equip_type() != "mount":
				_update_debug("坐骑槽位已满，无法暗置坐骑")
				return
		_:
			return
	# 替换旧暗置（先卸下占位，空出槽位）
	if p.has_hidden_equip():
		p.remove_equipment(p.hidden_equip_slot)
	var slot: String
	var type_name: String
	match etype:
		"weapon":
			slot = "weapon"
			type_name = "武器"
		"armor":
			slot = "armor"
			type_name = "防具"
		_:
			slot = p.get_free_mount_slot()
			type_name = "坐骑"
	p.equipment[slot] = CardData.CardSubType.HIDDEN_EQUIPMENT
	p.hidden_equip_slot = slot
	_update_debug("%s 发动【苕】：暗置了一件%s——你装备了一件装备" % [p.player_name, type_name])
	_sync_all_ui()
	_refresh_detail_popup()

# 明置：选择具体装备（未被装备过的武器/防具；马全部可选）
func _do_sao_reveal(p: Player) -> void:
	if not p.has_hidden_equip():
		return
	var etype = p.get_hidden_equip_type()
	var options: Array[int] = []
	match etype:
		"weapon":
			for sub in SAO_WEAPON_SUBS:
				if not equipment_pool.is_claimed(sub):
					options.append(sub)
		"armor":
			for sub in SAO_ARMOR_SUBS:
				if not equipment_pool.is_claimed(sub):
					options.append(sub)
		"mount":
			for sub in SAO_MOUNT_SUBS:
				options.append(sub)
	if options.is_empty():
		_show_toast("该类型的所有装备都已被打出过，无法明置")
		return
	var chosen: int = -1
	if _sao_reveal_sub_override.is_valid():
		chosen = _sao_reveal_sub_override.call()
		if chosen < 0:
			return
		if not options.has(chosen):
			return
	else:
		if p.seat_index != 0:
			return
		var texts: Array = []
		for sub in options:
			texts.append(CardData.get_type_name(sub))
		var idx = await _show_sao_reveal_picker(texts)
		if idx < 0:
			return
		chosen = options[idx]
	_reveal_hidden_as(p, chosen)

# 执行明置：占位变为具体装备（武器/防具进唯一性占用；坐骑按类型计数）
func _reveal_hidden_as(p: Player, sub: CardData.CardSubType):
	var slot = p.hidden_equip_slot
	if slot == "":
		return
	p.equipment[slot] = sub
	p.hidden_equip_slot = ""
	if sub == CardData.CardSubType.MOUNT_PLUS:
		p.mount_plus += 1
	elif sub == CardData.CardSubType.MOUNT_MINUS:
		p.mount_minus += 1
	elif sub == CardData.CardSubType.MULE_PLUS or sub == CardData.CardSubType.MULE_MINUS:
		pass  # 劣马：无个人计数、无唯一性
	else:
		equipment_pool.claim(sub)
	_update_debug("%s 明置了暗置装备：装备了【%s】" % [p.player_name, CardData.get_type_name(sub)])
	_sync_all_ui()
	_refresh_detail_popup()

# 【苕】抢先明置：玩家0 有同类型暗置装备时，可明置为该装备阻止对方装备（对方手牌未消耗）
# 返回 true = 抢先成功（调用方应中止本次装备流程）；type_key = "weapon" / "armor" / "mount"
func _try_sao_preempt(equipper: Player, sub: CardData.CardSubType, type_key: String) -> bool:
	var owner = players[0]
	if owner.general_name != "安普提·斯丢皮得" or not owner.is_alive():
		return false
	if not owner.has_hidden_equip():
		return false
	if owner.get_hidden_equip_type() != type_key:
		return false
	var type_name = "武器" if type_key == "weapon" else ("防具" if type_key == "armor" else "坐骑")
	if _sao_reveal_override.is_valid():
		if not _sao_reveal_override.call():
			return false
	else:
		if owner.seat_index != 0:
			return false
		var yes = await _show_sao_preempt_prompt(equipper, sub, type_name)
		if not yes:
			return false
	_reveal_hidden_as(owner, sub)
	_update_debug("%s 抢先明置暗置%s为【%s】，%s 无法装备，消耗的手牌已退回！" % [owner.player_name, type_name, CardData.get_type_name(sub), equipper.player_name])
	_sync_all_ui()
	return true

# 抢先明置确认弹窗（玩家0）
func _show_sao_preempt_prompt(equipper: Player, sub: CardData.CardSubType, type_name: String) -> bool:
	var idx = await _show_choice_popup("%s 装备了【%s】\n你是否明置已装备%s为【%s】？" % [equipper.player_name, CardData.get_type_name(sub), type_name, CardData.get_type_name(sub)], ["明置并阻止", "不阻止"])
	return idx == 0

# 【苕】明置时机：任意玩家行动后询问是否明置（同一个行动窗口内最多一次）
func _maybe_ask_reveal() -> void:
	if not _reveal_ask_pending:
		return
	_reveal_ask_pending = false
	var owner = players[0]
	if owner.general_name != "安普提·斯丢皮得" or not owner.is_alive():
		return
	if not owner.has_hidden_equip():
		return
	if _sao_reveal_override.is_valid():
		if _sao_reveal_override.call():
			await _do_sao_reveal(owner)
		return
	if owner.seat_index != 0:
		return
	var yes = await _show_reveal_opportunity_prompt(owner)
	if yes:
		await _do_sao_reveal(owner)

# 明置时机确认弹窗（玩家0）
func _show_reveal_opportunity_prompt(owner: Player) -> bool:
	var idx = await _show_choice_popup("你暗置了一件装备\n是否现在明置？", ["明置", "暂不明置"])
	return idx == 0

# ============================
#  通用弹窗（按钮选择）
# ============================

# 通用按钮选择弹窗（锚点居中）：返回选中索引，取消返回 -1
func _show_choice_popup(title: String, buttons: Array) -> int:
	if buttons.is_empty():
		return -1
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(540, 60)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 14)
	vbox.add_child(hbox)

	for i in buttons.size():
		var btn = Button.new()
		btn.text = buttons[i]
		btn.custom_minimum_size = Vector2(190, 44)
		btn.pressed.connect(_emit_choice_pick.bind(overlay, i), CONNECT_ONE_SHOT)
		hbox.add_child(btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(190, 44)
	cancel_btn.modulate = Color(0.7, 0.7, 0.7)
	cancel_btn.pressed.connect(_emit_choice_pick.bind(overlay, -1), CONNECT_ONE_SHOT)
	vbox.add_child(cancel_btn)

	_start_response_countdown(overlay, players[0].player_name, func(): _choice_pick_result.emit(-1))
	var r = await _choice_pick_result
	_stop_countdown()
	return r

func _emit_choice_pick(overlay: ColorRect, idx: int):
	overlay.queue_free()
	_choice_pick_result.emit(idx)

# 明置具体装备选择弹窗（网格布局，装备多）：返回选中索引，取消返回 -1
func _show_sao_reveal_picker(texts: Array) -> int:
	if texts.is_empty():
		return -1
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = "选择明置为哪件装备："
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.custom_minimum_size = Vector2(540, 40)
	vbox.add_child(label)

	var grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(grid)

	for i in texts.size():
		var btn = Button.new()
		btn.text = texts[i]
		btn.custom_minimum_size = Vector2(150, 40)
		btn.pressed.connect(_emit_choice_pick.bind(overlay, i), CONNECT_ONE_SHOT)
		grid.add_child(btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(190, 40)
	cancel_btn.modulate = Color(0.7, 0.7, 0.7)
	cancel_btn.pressed.connect(_emit_choice_pick.bind(overlay, -1), CONNECT_ONE_SHOT)
	vbox.add_child(cancel_btn)

	_start_response_countdown(overlay, players[0].player_name, func(): _choice_pick_result.emit(-1))
	var r = await _choice_pick_result
	_stop_countdown()
	return r

# ============================
#  【装傻】濒死拼点（安普提·斯丢皮得，锁定技）
# ============================

# 将要死亡时与场上所有存活玩家各拼点一次；赢超过一半（严格大于半数）则回复至 1 点体力
func _try_zhuangsha(dying: Player) -> void:
	var opponents: Array[Player] = []
	for pl in players:
		if pl != dying and pl.is_alive():
			opponents.append(pl)
	if opponents.is_empty():
		return
	_update_debug("%s 发动【装傻】：与场上所有存活玩家拼点！" % dying.player_name)
	var wins := 0
	for opp in opponents:
		var r = await _do_ping_dian_once(dying, opp)
		if r == RPS_WIN:
			wins += 1
	if wins * 2 > opponents.size():
		dying.hp = 1
		_update_debug("%s 【装傻】拼点胜 %d/%d，回复至 1 点体力！（%d/%d）" % [dying.player_name, wins, opponents.size(), dying.hp, dying.max_hp])
	else:
		_update_debug("%s 【装傻】拼点胜 %d/%d，未能回复…" % [dying.player_name, wins, opponents.size()])
	_sync_all_ui()

# ============================
#  【觉醒】史蒂芬·彼特先斯（觉醒技：满足条件立即自动发动）
# ============================

# 觉醒技判定：是否禁用了对应效果（kind: 1=杀目标 2=决斗目标 3=南蛮万箭目标）
func _awake_blocks(p: Player, kind: int) -> bool:
	return p.general_name == "史蒂芬·彼特先斯" and p.awoken and p.awake_choice == kind

# 觉醒触发检查：手牌为 0 且未觉醒 → 立即觉醒（觉醒技；由 _sync_all_ui 与 hand_updated 驱动）
func _check_awaken_trigger():
	if players.is_empty():
		return
	var p = players[0]
	if not p.is_alive() or p.general_name != "史蒂芬·彼特先斯" or p.awoken or p.hand_size() > 0:
		return
	p.awoken = true  # 先标记，防止 _do_awaken 内部再 sync 时重入
	call_deferred("_do_awaken", p)

# 手牌变化监听（add_to_hand / remove_from_hand 路径的补充触发）
func _on_hand_updated(p: Player):
	if p == players[0]:
		_check_awaken_trigger()

# 觉醒：失去一点体力上限 → 摸两张牌 → 三选一
func _do_awaken(p: Player):
	p.awoken = true
	p.max_hp -= 1
	p.hp = mini(p.hp, p.max_hp)
	_update_debug("%s 觉醒！失去 1 点体力上限（上限 %d，体力 %d/%d），摸两张牌" % [p.player_name, p.max_hp, p.hp, p.max_hp])
	_draw_blank_cards(p, 2)
	var choice: int
	if _awaken_pick_override.is_valid():
		choice = _awaken_pick_override.call()
	else:
		choice = await _show_awaken_pick()
	p.awake_choice = choice
	var desc = "1.不能成为【杀】的目标" if choice == 1 else ("2.不能成为【决斗】的目标" if choice == 2 else "3.不能成为【南蛮入侵】和【万箭齐发】的目标")
	_update_debug("%s 选择觉醒效果：%s" % [p.player_name, desc])
	_sync_all_ui()

# 觉醒三选一弹窗（玩家0）：返回 1 / 2 / 3
func _show_awaken_pick() -> int:
	var idx = await _show_choice_popup("【觉醒】选择一项永久效果：", ["不能成为【杀】的目标", "不能成为【决斗】的目标", "不能成为【南蛮入侵】和【万箭齐发】的目标"])
	if idx < 0:
		idx = 1  # 取消默认选 1
	return idx + 1

# ============================
#  【拍胸脯】史蒂芬·彼特先斯：将要受到伤害时，可发动；发动则伤害来源需弃一张手牌才能造成伤害
# ============================

# 返回 true = 伤害被防止（来源没有手牌可弃）；false = 伤害照常（未发动或来源弃牌）
func _try_paixiong_block(victim: Player, source: Player) -> bool:
	if victim.general_name != "史蒂芬·彼特先斯" or not victim.is_alive():
		return false
	if source == null:
		# 无伤害来源（闪电/火烧连营）：没有来源可弃牌 → 不能发动
		return false
	if source == victim:
		# 来源是自己（舍己为人自转移等）：无需弃牌，伤害照常
		return false
	if _paixiong_override.is_valid():
		if not _paixiong_override.call():
			return false
	else:
		if victim.seat_index != 0:
			return false  # AI 暂不发动
		var use = await _show_paixiong_prompt(source.player_name)
		if not use:
			return false
	# 发动：来源需弃一张手牌
	if source.hand_size() > 0:
		source.hand.pop_back()
		_update_debug("%s 发动【拍胸脯】！%s 弃置一张手牌（剩余 %d 张），伤害照常结算" % [victim.player_name, source.player_name, source.hand_size()])
		_sync_all_ui()
		return false
	_update_debug("%s 发动【拍胸脯】！%s 没有手牌，本次伤害被防止！" % [victim.player_name, source.player_name])
	_sync_all_ui()
	return true

# 玩家0 的【拍胸脯】发动确认弹窗
func _show_paixiong_prompt(source_name: String) -> bool:
	var idx = await _show_choice_popup("你将受到伤害！\n是否发动【拍胸脯】？（发动后 %s 需弃置一张手牌才能造成伤害）" % source_name, ["发动【拍胸脯】", "不发动"])
	return idx == 0

# ============================
#  【装逼】史蒂芬·彼特先斯：出牌阶段选任意数量其他角色，各弃一张手牌后依次拼点
# ============================

# 详情弹窗技能点击：进入目标选择模式（与【下跪】/【苕】一致的发动方式）
func _on_zhuangbi_skill_clicked(p: Player) -> void:
	if _zhuangbi_blocked_this_phase:
		_show_toast("【装逼】胜负各半，本出牌阶段不能再次发动")
		return
	if p != players[0] or p.seat_index != 0:
		_update_debug("只能对自己使用【装逼】")
		return
	if p.general_name != "史蒂芬·彼特先斯":
		return
	if turn_manager.current_phase != TurnManager.Phase.PLAY:
		_show_toast("【装逼】只能在你的出牌阶段发动")
		return
	if p.hand_size() <= 0:
		_show_toast("【装逼】发动条件：你至少有一张手牌")
		return
	# 至少有一个可选目标（存活且有手牌的其他角色）
	var any = false
	for pl in players:
		if pl != p and pl.is_alive() and pl.hand_size() > 0 and not _is_kneeling(pl):
			any = true
			break
	if not any:
		_show_toast("没有可选择的角色（需要对方也有手牌）")
		return
	_start_zhuangbi_mode()

func _start_zhuangbi_mode():
	_is_zhuangbi_targeting = true
	_zhuangbi_targets.clear()
	_play_btn.visible = false
	_end_play_btn.visible = false
	_cancel_target_btn.visible = true
	_confirm_target_btn.visible = true
	_confirm_target_btn.disabled = true
	_confirm_target_btn.text = "确认装逼（0 名目标）"
	# 关闭详情弹窗，避免挡住头像选择
	for child in _detail_popup_root.get_children():
		child.queue_free()
	_detail_popup_root.visible = false
	_update_debug("【装逼】：请点击角色头像选择目标（可多选，点已选角色取消），选好后点击「确认装逼」")

func _exit_zhuangbi_mode():
	_is_zhuangbi_targeting = false
	_zhuangbi_targets.clear()
	_cancel_target_btn.visible = false
	_confirm_target_btn.visible = false
	_play_btn.visible = true
	_end_play_btn.visible = true

# 装逼目标点击：toggle 加入/移除（不能选自己；目标须存活且有手牌）
func _on_zhuangbi_target_click(target: Player):
	var p = players[0]
	if target == p:
		_update_debug("不能选择自己作为目标")
		return
	if not target.is_alive():
		_update_debug("目标已阵亡")
		return
	# 【下跪】：下跪状态不会成为任何效果的目标
	if _is_kneeling(target):
		_update_debug("%s 处于【下跪】状态，不能成为目标！" % target.player_name)
		return
	if target.hand_size() <= 0:
		_update_debug("%s 没有手牌，不能选择" % target.player_name)
		return
	if _zhuangbi_targets.has(target):
		_zhuangbi_targets.erase(target)
		_update_debug("已取消选择 %s（当前 %d 名目标）" % [target.player_name, _zhuangbi_targets.size()])
	else:
		_zhuangbi_targets.append(target)
		_update_debug("已选择 %s（当前 %d 名目标）" % [target.player_name, _zhuangbi_targets.size()])
	_confirm_target_btn.text = "确认装逼（%d 名目标）" % _zhuangbi_targets.size()
	_confirm_target_btn.disabled = _zhuangbi_targets.is_empty()

# 确认装逼：执行
func _on_confirm_zhuangbi():
	if _zhuangbi_targets.is_empty():
		return
	var targets = _zhuangbi_targets.duplicate()
	_exit_zhuangbi_mode()
	await _execute_zhuangbi(targets)

# 执行装逼：双方各弃一张手牌 → 依次拼点 → 判定结果
func _execute_zhuangbi(targets: Array[Player]) -> void:
	if _zhuangbi_blocked_this_phase:
		_update_debug("【装逼】本出牌阶段不能再次发动")
		return
	var p = players[0]
	if p.general_name != "史蒂芬·彼特先斯" or not p.is_alive():
		return
	# 过滤：当前无手牌的目标剔除（选择时已保证，执行时防变化）
	var valid: Array[Player] = []
	for t in targets:
		if t.is_alive() and t.hand_size() > 0:
			valid.append(t)
	if valid.is_empty():
		_update_debug("没有有效目标，【装逼】未发动")
		return
	# 自己弃一张手牌（没手牌则技能无法发动）
	if p.hand_size() <= 0:
		_update_debug("你没有手牌，【装逼】未发动")
		return
	p.hand.pop_back()
	_update_debug("%s 发动【装逼】！弃置一张手牌（剩余 %d 张）" % [p.player_name, p.hand_size()])
	for t in valid:
		t.hand.pop_back()
	_update_debug("各目标弃置一张手牌，依次与 %s 拼点！" % p.player_name)
	_sync_all_ui()

	# 依次拼点（进行拼点：平局后继续，直到分出胜负）
	var wins := 0
	var losses := 0
	var losers: Array[Player] = []  # 输给 p 的目标
	for t in valid:
		var r = await _do_ping_dian(p, t)
		if r == RPS_WIN:
			wins += 1
			losers.append(t)
		else:
			losses += 1

	var n = valid.size()
	if wins == losses:
		_zhuangbi_blocked_this_phase = true
		_update_debug("【装逼】胜负各半：既不成功也不失败，不造成伤害；本出牌阶段不能再发动")
		_sync_all_ui()
		return
	# 输了一半以上 → 立即进入弃牌阶段
	if losses * 2 > n:
		_update_debug("%s 拼点输 %d/%d（一半以上），立即进入弃牌阶段！" % [p.player_name, losses, n])
		_enter_discard_from_zhuangbi()
		return
	# 胜负各半已单独处理；成功才允许再次主动发动。
	_update_debug("%s 拼点赢 %d/%d！输给你的角色受到 1 点伤害！" % [p.player_name, wins, n])
	for t in losers:
		if not t.is_alive():
			continue
		if _game_over:
			break
		await _deal_damage(p, t, 1, EffectChain.DamageType.PHYSICAL)
		if not p.is_alive():
			break  # 自己已死（如荆棘反伤），不再继续
	# 赢了一半及以上 → 可以再次使用此技能
	if p.is_alive() and turn_manager.current_phase == TurnManager.Phase.PLAY:
		var again = false
		if _zhuangbi_again_override.is_valid():
			again = _zhuangbi_again_override.call()
		else:
			again = await _show_zhuangbi_again_prompt()
		if again:
			_start_zhuangbi_mode()  # 重新进入选择模式

# 装逼输局：立即进入弃牌阶段（清理选择状态）
func _enter_discard_from_zhuangbi():
	_is_zhuangbi_targeting = false
	_zhuangbi_targets.clear()
	_is_campus_targeting = false
	_play_btn.visible = false
	_end_play_btn.visible = false
	_cancel_target_btn.visible = false
	_confirm_target_btn.visible = false
	turn_manager.advance_phase()  # PLAY → DISCARD

# 赢局后询问是否再次使用装逼（玩家0弹窗）
func _show_zhuangbi_again_prompt() -> bool:
	var idx = await _show_choice_popup("你赢了一半及以上！\n是否再次使用【装逼】？", ["再次装逼", "就此收手"])
	return idx == 0

# ============================
#  【校园霸主】杰基·斯特朗：出牌阶段选一名有手牌的角色，各弃一张手牌后拼点，赢者对输者造成 1 点伤害
# ============================

# 详情弹窗技能点击：进入目标选择模式（与【装逼】等主动技能一致）
func _on_campus_skill_clicked(p: Player) -> void:
	if p != players[0] or p.seat_index != 0:
		_update_debug("只能对自己使用【校园霸主】")
		return
	if p.general_name != "杰基·斯特朗":
		return
	if turn_manager.current_phase != TurnManager.Phase.PLAY:
		_show_toast("【校园霸主】只能在你的出牌阶段发动")
		return
	if p.hand_size() <= 0:
		_show_toast("【校园霸主】发动条件：你至少有一张手牌")
		return
	# 至少有一个可选目标（存活且有手牌的其他角色）
	var any = false
	for pl in players:
		if pl != p and pl.is_alive() and pl.hand_size() > 0 and not _is_kneeling(pl):
			any = true
			break
	if not any:
		_show_toast("没有可选择的角色（需要对方也有手牌）")
		return
	_start_campus_mode()

func _start_campus_mode():
	_is_campus_targeting = true
	_play_btn.visible = false
	_end_play_btn.visible = false
	_cancel_target_btn.visible = true
	# 关闭详情弹窗，避免挡住头像选择
	for child in _detail_popup_root.get_children():
		child.queue_free()
	_detail_popup_root.visible = false
	_update_debug("【校园霸主】：请点击一名有手牌的角色（双方各弃一张手牌后拼点，赢者对输者造成 1 点伤害）")

# 校园霸主目标点击：单选，点击即执行（不能选自己；目标须存活且有手牌）
func _on_campus_target_click(target: Player):
	var p = players[0]
	if target == p:
		_update_debug("不能选择自己作为目标")
		return
	if not target.is_alive():
		_update_debug("目标已阵亡")
		return
	# 【下跪】：下跪状态不会成为任何效果的目标
	if _is_kneeling(target):
		_update_debug("%s 处于【下跪】状态，不能成为目标！" % target.player_name)
		return
	if target.hand_size() <= 0:
		_update_debug("%s 没有手牌，不能选择" % target.player_name)
		return
	_is_campus_targeting = false
	_cancel_target_btn.visible = false
	await _execute_campus_dominator(p, target)
	_play_btn.visible = true
	_end_play_btn.visible = true
	_sync_all_ui()

# 执行校园霸主：双方各弃一张手牌 → 进行拼点（平局继续直到分出胜负）→ 赢者对输者造成 1 点伤害
func _execute_campus_dominator(p: Player, target: Player) -> void:
	if p.general_name != "杰基·斯特朗" or not p.is_alive():
		return
	if not target.is_alive() or target.hand_size() <= 0:
		_update_debug("目标没有手牌，【校园霸主】未发动")
		return
	if p.hand_size() <= 0:
		_update_debug("你没有手牌，【校园霸主】未发动")
		return
	p.hand.pop_back()
	target.hand.pop_back()
	_update_debug("%s 发动【校园霸主】！你与 %s 各弃置一张手牌，进行拼点！" % [p.player_name, target.player_name])
	_sync_all_ui()

	# 进行拼点（平局继续直到分出胜负）
	var r = await _do_ping_dian(p, target)
	if r == RPS_WIN:
		_update_debug("%s 赢得拼点！对 %s 造成 1 点伤害！" % [p.player_name, target.player_name])
		await _deal_damage(p, target, 1, EffectChain.DamageType.PHYSICAL)
	else:
		_update_debug("%s 拼点失败，%s 赢得拼点！对你造成 1 点伤害！" % [p.player_name, target.player_name])
		await _deal_damage(target, p, 1, EffectChain.DamageType.PHYSICAL)
	_sync_all_ui()



# ============================
#  【神速】（比尔·盖伊）：回合开始阶段二选一
# ============================

# 回合开始询问：是否发动（玩家0弹窗 / 测试钩子；AI 暂不主动发动）
func _maybe_shensu(p: Player) -> void:
	var activate := false
	if _shensu_override.is_valid():
		activate = _shensu_override.call()
	elif p.seat_index == 0:
		activate = await _show_shensu_activate_prompt()
	if not activate:
		return
	# 二选一：选项1（判定区有牌才能选）/ 选项2
	var option := 0
	if _shensu_option_override.is_valid():
		option = _shensu_option_override.call()
	elif p.seat_index == 0:
		option = await _show_shensu_option_prompt(p)
	if option == 1:
		# 选项1 兜底：判定区必须有牌才能发动（无牌时相当于未选）
		if p.judgment_cards.is_empty():
			_update_debug("判定区无牌，【神速】选项1 无法发动")
			_sync_all_ui()
			return
		# 选项1：跳过判定阶段 + 视为对一名其他角色打出一张无距离限制的【杀】
		var target: Player = null
		if _shensu_target_override.is_valid():
			target = _shensu_target_override.call()
		else:
			target = await _pick_shensu_strike_target(p)
		if target == null:
			_update_debug("未选择【神速】杀目标，取消发动（判定阶段照常）")
			_sync_all_ui()
			return
		turn_manager.skip_judge_phase = true
		_update_debug("%s 发动【神速】选项1：跳过判定阶段，对 %s 视为打出一张无距离限制的【杀】！" % [p.player_name, target.player_name])
		await _execute_shensu_strike(p, target)
	elif option == 2:
		p.shensu_penalty += 1
		p.shensu_used_this_turn = true
		turn_manager.skip_play_discard_phase = true
		_update_debug("%s 发动【神速】选项2：跳过出牌和弃牌阶段，摸牌减益叠加（累计欠 %d 张）" % [p.player_name, p.shensu_penalty])
	_sync_all_ui()

# 神速发动确认弹窗（玩家0）
func _show_shensu_activate_prompt() -> bool:
	var idx = await _show_choice_popup("现在是回合开始阶段\n是否发动【神速】技能？", ["发动【神速】", "不发动"])
	return idx == 0

# 神速选项弹窗：返回 1/2（0=取消）；判定区无牌时选项1 不可选
func _show_shensu_option_prompt(p: Player) -> int:
	var buttons: Array = ["2.跳过出牌和弃牌阶段（下回合摸牌减益）"]
	if not p.judgment_cards.is_empty():
		buttons.insert(0, "1.跳过判定阶段，视为打出一张无距离限制的【杀】")
	else:
		_update_debug("判定区无牌，【神速】选项1 不可用")
	var idx = await _show_choice_popup("请选择【神速】的一项", buttons)
	if idx < 0:
		return 0
	if p.judgment_cards.is_empty():
		return 2
	return 1 if idx == 0 else 2

# 神速杀目标选择（单选，点击即执行）：返回目标（null=取消）
func _pick_shensu_strike_target(p: Player) -> Player:
	_is_shensu_targeting = true
	_cancel_target_btn.visible = true
	_update_debug("【神速】：请点击一名其他角色（视为无距离限制的【杀】）")
	_refresh_status_line()
	var target: Player = await _shensu_pick_result
	_is_shensu_targeting = false
	_cancel_target_btn.visible = false
	return target

# 神速杀目标点击（分发器在 _on_player_panel_click）
func _on_shensu_target_click(target: Player):
	var p = players[turn_manager.current_player_idx]  # 使用者 = 当前回合玩家
	if target == p:
		_update_debug("不能选择自己作为目标")
		return
	if not target.is_alive():
		_update_debug("目标已阵亡")
		return
	if _is_kneeling(target):
		_update_debug("%s 处于【下跪】状态，不能成为目标！" % target.player_name)
		return
	# 杀的目标免疫与正常杀一致（藤甲/裸奔/觉醒1）
	if target.get_armor() == CardData.CardSubType.TENGJIA or _is_bare_running(target) or _awake_blocks(target, 1):
		_update_debug("%s 不能成为【杀】的目标！" % target.player_name)
		return
	_is_shensu_targeting = false
	_cancel_target_btn.visible = false
	_shensu_pick_result.emit(target)

# 神速杀：视为使用普通【杀】（无距离限制）；不耗手牌、不占杀次数；酒/武器/防具正常结算
func _execute_shensu_strike(p: Player, target: Player) -> void:
	if p.general_name != "比尔·盖伊" or not p.is_alive() or not target.is_alive():
		return
	var card = CardBase.create(CardData.CardSubType.STRIKE)
	var base_damage = 1
	# 【酒】：视为杀吃酒加成并消耗酒层数
	if p.wine_stacks > 0:
		base_damage += p.wine_stacks
		p.wine_stacks = 0
		_update_debug("%s 的【酒】加成：神速杀伤害 +%d" % [p.player_name, base_damage - 1])
	await _execute_single_strike(p, target, card, CardData.CardSubType.STRIKE, EffectChain.DamageType.PHYSICAL, base_damage)
	_sync_all_ui()

# ============================
#  【Gay】（比尔·盖伊）：出牌阶段限一次，弃 X 张手牌令双方各回复 X 点
# ============================

# 详情弹窗技能按钮 → 【Gay】发动入口
func _on_gay_skill_clicked(p: Player) -> void:
	if p != players[0] or p.seat_index != 0:
		_update_debug("只能对自己使用【Gay】")
		return
	if p.general_name != "比尔·盖伊":
		return
	if turn_manager.current_phase != TurnManager.Phase.PLAY:
		_update_debug("【Gay】只能在出牌阶段发动")
		return
	if _gay_used:
		_update_debug("【Gay】每回合限一次，本回合已使用")
		return
	if p.hand_size() <= 0:
		_update_debug("你没有手牌，无法发动【Gay】")
		return
	var has_target := false
	for pl in players:
		if pl != p and pl.is_alive() and pl.gender == p.gender and pl.hp < pl.max_hp and not _is_kneeling(pl):
			has_target = true
			break
	if not has_target:
		_update_debug("没有已受伤的同性角色可以作为【Gay】目标")
		return
	# 关闭详情弹窗，避免挡住头像选择
	for child in _detail_popup_root.get_children():
		child.queue_free()
	_detail_popup_root.visible = false
	_is_gay_targeting = true
	_play_btn.visible = false
	_end_play_btn.visible = false
	_cancel_target_btn.visible = true
	_update_debug("【Gay】：请点击一名已受伤的同性角色（弃 X 张手牌，双方各回复 X 点体力）")

# Gay 目标点击（分发器在 _on_player_panel_click）：校验后弹 X 选择
func _on_gay_target_click(target: Player):
	var p = players[0]
	if target == p:
		_update_debug("不能选择自己作为目标")
		return
	if not target.is_alive():
		_update_debug("目标已阵亡")
		return
	if target.gender != p.gender:
		_update_debug("%s 与你不是同性，不能选择" % target.player_name)
		return
	if target.hp >= target.max_hp:
		_update_debug("%s 未受伤（体力满），不能选择" % target.player_name)
		return
	if _is_kneeling(target):
		_update_debug("%s 处于【下跪】状态，不能成为目标！" % target.player_name)
		return
	_is_gay_targeting = false
	_cancel_target_btn.visible = false
	await _execute_gay(p, target)
	_play_btn.visible = true
	_end_play_btn.visible = true
	_sync_all_ui()

# 执行【Gay】：弃 X 张手牌，双方各回复 X 点体力（X ≤ 双方体力上限最小值，且 ≤ 手牌数）
func _execute_gay(p: Player, target: Player) -> void:
	if p.general_name != "比尔·盖伊" or not p.is_alive() or not target.is_alive():
		return
	if _gay_used:
		return
	var max_x = mini(p.max_hp, target.max_hp)
	max_x = mini(max_x, p.hand_size())
	if max_x <= 0:
		_update_debug("没有可弃的手牌，【Gay】未发动")
		return
	var x := 0
	if _gay_x_override.is_valid():
		x = _gay_x_override.call()
	elif p.seat_index == 0:
		x = await _show_gay_x_picker(max_x)
	if x <= 0 or x > max_x:
		_update_debug("取消【Gay】")
		_sync_all_ui()
		return
	_gay_used = true
	# 弃 X 张手牌（从手牌尾部弃）
	for i in x:
		p.hand.pop_back()
	var p_before = p.hp
	var t_before = target.hp
	p.heal(x)
	target.heal(x)
	_update_debug("%s 发动【Gay】：弃置 %d 张手牌，与 %s 各回复 %d 点体力（%d/%d → %d/%d；%d/%d → %d/%d）" % [p.player_name, x, target.player_name, x, p_before, p.max_hp, p.hp, p.max_hp, t_before, target.max_hp, target.hp, target.max_hp])
	_sync_all_ui()

# X 选择弹窗（玩家0）：返回 1..max_x（取消返回 0）
func _show_gay_x_picker(max_x: int) -> int:
	var buttons: Array = []
	for i in range(1, max_x + 1):
		buttons.append("弃置 %d 张，各回复 %d 点" % [i, i])
	var idx = await _show_choice_popup("【Gay】：弃置 X 张手牌（X ≤ %d），双方各回复 X 点体力" % max_x, buttons)
	if idx < 0:
		return 0
	return idx + 1

# ============================
#  【烂忠厚】麦克斯·欧尼斯特：出牌阶段限一次，弃 X 张牌交换两名角色的 X 个装备区域
#  X = 选择的区域类别数（武器/防具/坐骑各最多一次）；坐骑可跨槽位交换（A的坐骑1 ↔ B的坐骑2）
#  规则：某一方区域为空或为暗置装备 → 装备直接归还，不交换；坐骑只能选有装备的槽位
# ============================

# 详情弹窗技能点击：进入两名角色选择模式（与【装逼】等主动技能一致）
func _on_lanzhonghou_skill_clicked(p: Player) -> void:
	if p != players[0] or p.seat_index != 0:
		_update_debug("只能对自己使用【烂忠厚】")
		return
	if p.general_name != "麦克斯·欧尼斯特":
		return
	if turn_manager.current_phase != TurnManager.Phase.PLAY:
		_show_toast("【烂忠厚】只能在你的出牌阶段发动")
		return
	if _lanzhonghou_used:
		_show_toast("本回合已使用过【烂忠厚】")
		return
	if p.hand_size() <= 0:
		_show_toast("【烂忠厚】发动条件：至少有一张手牌（弃 X 张牌）")
		return
	_start_lanzhonghou_mode()

func _start_lanzhonghou_mode():
	_is_lanzhonghou_targeting = true
	_lanzhonghou_selected.clear()
	_lanzhonghou_pending.clear()
	_play_btn.visible = false
	_end_play_btn.visible = false
	_cancel_target_btn.visible = true
	# 关闭详情弹窗，避免挡住头像选择
	for child in _detail_popup_root.get_children():
		child.queue_free()
	_detail_popup_root.visible = false
	_update_debug("【烂忠厚】：请点击两名角色（可含自己）的头像，选择交换装备的角色（当前 0/2）")

# 烂忠厚角色选择：点击头像 toggle（选满 2 名进入区域选择）
func _on_lanzhonghou_target_click(target: Player):
	if not target.is_alive():
		_update_debug("目标已阵亡")
		return
	# 【下跪】：下跪状态不会成为任何效果的目标
	if _is_kneeling(target):
		_update_debug("%s 处于【下跪】状态，不能选择！" % target.player_name)
		return
	if _lanzhonghou_selected.has(target):
		_lanzhonghou_selected.erase(target)
		_update_debug("已取消选择 %s（当前 %d/2）" % [target.player_name, _lanzhonghou_selected.size()])
		return
	if _lanzhonghou_selected.size() >= 2:
		_update_debug("已选满 2 名角色，请点击「取消选择」重新选择")
		return
	_lanzhonghou_selected.append(target)
	_update_debug("已选择 %s（当前 %d/2）" % [target.player_name, _lanzhonghou_selected.size()])
	if _lanzhonghou_selected.size() == 2:
		var a = _lanzhonghou_selected[0]
		var b = _lanzhonghou_selected[1]
		_is_lanzhonghou_targeting = false
		_cancel_target_btn.visible = false
		await _run_lanzhonghou(a, b)
		_play_btn.visible = true
		_end_play_btn.visible = true
		_sync_all_ui()

# 区域选择循环：武器/防具/坐骑 各最多一次；「完成交换」后弃 X 张牌并统一执行交换
func _run_lanzhonghou(a: Player, b: Player) -> void:
	var p = players[0]
	if p.general_name != "麦克斯·欧尼斯特" or not p.is_alive():
		return
	# X = 交换区域对数：武器/防具各最多 1 对，坐骑最多 4 对（每名角色 4 个坐骑槽）→ 上限 6 对，弃 X 张牌
	var max_pick = mini(6, p.hand_size())
	_lanzhonghou_pending.clear()
	while true:
		var zone = await _ask_lanzhonghou_zone(a, b, _lanzhonghou_pending, max_pick)
		if zone == "cancel":
			_lanzhonghou_pending.clear()
			_update_debug("取消【烂忠厚】，未消耗手牌")
			return
		if zone == "done":
			break
		match zone:
			"weapon", "armor":
				_lanzhonghou_pending.append({"zone": zone, "a": a, "slot_a": zone, "b": b, "slot_b": zone, "ok": true})
			"mount":
				# 坐骑最多 4 对（防御：UI 已禁用，直调时也拦）
				if _lanzhonghou_count(_lanzhonghou_pending, "mount") >= 4:
					_update_debug("坐骑区域最多选择 4 对")
					continue
				# 双方各自未使用的坐骑槽（排除暗置）
				var used_a := {}
				var used_b := {}
				for entry in _lanzhonghou_pending:
					if entry.zone == "mount":
						used_a[entry.slot_a] = true
						used_b[entry.slot_b] = true
				var slots_a: Array[String] = []
				for s in a.get_mount_slots():
					if a.equipment[s] != CardData.CardSubType.HIDDEN_EQUIPMENT and not used_a.has(s):
						slots_a.append(s)
				var slots_b: Array[String] = []
				for s in b.get_mount_slots():
					if b.equipment[s] != CardData.CardSubType.HIDDEN_EQUIPMENT and not used_b.has(s):
						slots_b.append(s)
				if slots_a.is_empty() or slots_b.is_empty():
					_update_debug("坐骑区域：一方没有可交换的坐骑，装备直接归还，不交换")
					_lanzhonghou_pending.append({"zone": "mount", "a": a, "slot_a": "", "b": b, "slot_b": "", "ok": false})
					continue
				var pair_no = _lanzhonghou_count(_lanzhonghou_pending, "mount") + 1
				var slot_a = await _ask_lanzhonghou_mount_slot(a, slots_a, "选择 %s 要交换的坐骑（第 %d 对坐骑）：" % [a.player_name, pair_no])
				if slot_a == "cancel":
					continue
				var slot_b = await _ask_lanzhonghou_mount_slot(b, slots_b, "选择 %s 要交换的坐骑（第 %d 对坐骑）：" % [b.player_name, pair_no])
				if slot_b == "cancel":
					continue
				_lanzhonghou_pending.append({"zone": "mount", "a": a, "slot_a": slot_a, "b": b, "slot_b": slot_b, "ok": true})
	var x = _lanzhonghou_pending.size()
	if x <= 0:
		_update_debug("没有选择任何区域，取消【烂忠厚】")
		return
	# 弃 X 张牌
	for i in x:
		p.hand.pop_back()
	# 统一执行交换
	var swapped = 0
	for entry in _lanzhonghou_pending:
		if not entry.ok:
			var zone_name = "武器" if entry.zone == "weapon" else ("护甲" if entry.zone == "armor" else "坐骑")
			_update_debug("%s 区域：一方没有装备（或为暗置装备），装备直接归还，不交换" % zone_name)
			continue
		if _swap_equip_slot(entry.a, entry.slot_a, entry.b, entry.slot_b):
			swapped += 1
	_update_debug("%s 发动【烂忠厚】：弃置 %d 张手牌，交换了 %s 与 %s 的 %d 个装备区域" % [p.player_name, x, a.player_name, b.player_name, swapped])
	_lanzhonghou_used = true
	_lanzhonghou_pending.clear()
	_sync_all_ui()

# 已选择的某区域类别数量（weapon/armor 最多 1，mount 最多 4）
func _lanzhonghou_count(picked: Array, zone: String) -> int:
	var n := 0
	for entry in picked:
		if entry.zone == zone:
			n += 1
	return n

# 是否已选择过该区域类别
func _lanzhonghou_zone_picked(picked: Array, zone: String) -> bool:
	return _lanzhonghou_count(picked, zone) > 0

# 该角色是否还有未使用（未被选入交换）的可交换坐骑槽（排除暗置）
func _lanzhonghou_has_swappable_mount(p: Player, picked: Array = [], is_a: bool = true) -> bool:
	var used := {}
	for entry in picked:
		if entry.zone == "mount":
			used[entry.slot_a if is_a else entry.slot_b] = true
	for s in p.get_mount_slots():
		if p.equipment[s] != CardData.CardSubType.HIDDEN_EQUIPMENT and not used.has(s):
			return true
	return false

# 区域选择弹窗：武器/防具/坐骑（各最多一次）+ 完成交换 + 取消（锚点居中）
func _ask_lanzhonghou_zone(a: Player, b: Player, picked: Array, max_pick: int) -> String:
	if _lanzhonghou_zone_override.is_valid():
		return _lanzhonghou_zone_override.call()

	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = "交换 %s 与 %s 的装备区域（已选 %d 对，共弃 %d 张牌）\n武器/防具各 1 对，坐骑最多 4 对（可跨槽位）：" % [a.player_name, b.player_name, picked.size(), picked.size()]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(560, 60)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 14)
	vbox.add_child(hbox)

	var weapon_btn = Button.new()
	weapon_btn.text = "武器"
	weapon_btn.custom_minimum_size = Vector2(120, 44)
	weapon_btn.disabled = _lanzhonghou_zone_picked(picked, "weapon") or picked.size() >= max_pick
	weapon_btn.pressed.connect(func():
		overlay.queue_free()
		_lanzhonghou_zone_result.emit("weapon")
	, CONNECT_ONE_SHOT)
	hbox.add_child(weapon_btn)

	var armor_btn = Button.new()
	armor_btn.text = "防具"
	armor_btn.custom_minimum_size = Vector2(120, 44)
	armor_btn.disabled = _lanzhonghou_zone_picked(picked, "armor") or picked.size() >= max_pick
	armor_btn.pressed.connect(func():
		overlay.queue_free()
		_lanzhonghou_zone_result.emit("armor")
	, CONNECT_ONE_SHOT)
	hbox.add_child(armor_btn)

	var mount_btn = Button.new()
	mount_btn.text = "坐骑"
	mount_btn.custom_minimum_size = Vector2(120, 44)
	mount_btn.disabled = _lanzhonghou_count(picked, "mount") >= 4 or picked.size() >= max_pick \
			or not _lanzhonghou_has_swappable_mount(a, picked, true) or not _lanzhonghou_has_swappable_mount(b, picked, false)
	mount_btn.pressed.connect(func():
		overlay.queue_free()
		_lanzhonghou_zone_result.emit("mount")
	, CONNECT_ONE_SHOT)
	hbox.add_child(mount_btn)

	var done_btn = Button.new()
	done_btn.text = "完成交换（弃 %d 张牌）" % picked.size()
	done_btn.custom_minimum_size = Vector2(180, 44)
	done_btn.disabled = picked.is_empty()
	done_btn.pressed.connect(func():
		overlay.queue_free()
		_lanzhonghou_zone_result.emit("done")
	, CONNECT_ONE_SHOT)
	hbox.add_child(done_btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(120, 44)
	cancel_btn.modulate = Color(0.7, 0.7, 0.7)
	cancel_btn.pressed.connect(func():
		overlay.queue_free()
		_lanzhonghou_zone_result.emit("cancel")
	, CONNECT_ONE_SHOT)
	vbox.add_child(cancel_btn)

	var r = await _lanzhonghou_zone_result
	return r

# 坐骑槽选择弹窗：返回槽位或 "cancel"（锚点居中；只列有装备的槽位）
func _ask_lanzhonghou_mount_slot(target: Player, slots: Array[String], title: String) -> String:
	if _lanzhonghou_mount_override.is_valid():
		return _lanzhonghou_mount_override.call(target, slots)

	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(540, 40)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 14)
	vbox.add_child(hbox)

	for slot in slots:
		var btn = Button.new()
		btn.text = "%s：%s" % [Player.EQUIP_SLOT_NAMES[slot], CardData.get_type_name(target.equipment[slot])]
		btn.custom_minimum_size = Vector2(140, 44)
		btn.pressed.connect(_emit_lanzhonghou_mount.bind(overlay, slot), CONNECT_ONE_SHOT)
		hbox.add_child(btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(140, 44)
	cancel_btn.modulate = Color(0.7, 0.7, 0.7)
	cancel_btn.pressed.connect(func():
		overlay.queue_free()
		_lanzhonghou_mount_result.emit("cancel")
	, CONNECT_ONE_SHOT)
	vbox.add_child(cancel_btn)

	var r = await _lanzhonghou_mount_result
	return r

func _emit_lanzhonghou_mount(overlay: ColorRect, slot: String):
	overlay.queue_free()
	_lanzhonghou_mount_result.emit(slot)

# 交换两名角色指定槽位的装备（武器/防具同槽位；坐骑可跨槽位）
# 规则：任一侧槽位无装备或为暗置装备 → 不交换（装备直接归还），返回 false
# 轻量装卸：不触发白银狮子回血（交换不算失去）；破风枪加成清零/重置；摄魂刀跟踪重置；贤者标记跟随装备转移
func _swap_equip_slot(pA: Player, slot_a: String, pB: Player, slot_b: String) -> bool:
	if not pA.equipment.has(slot_a) or not pB.equipment.has(slot_b):
		return false
	var subA = pA.equipment[slot_a]
	var subB = pB.equipment[slot_b]
	if subA == CardData.CardSubType.HIDDEN_EQUIPMENT or subB == CardData.CardSubType.HIDDEN_EQUIPMENT:
		return false  # 暗置装备不参与交换（装备直接归还）
	# 贤者的加护：贤者标记跟随装备转移
	var sage_a = {"t": 0, "a": false}
	var sage_b = {"t": 0, "a": false}
	if subA == CardData.CardSubType.SAGE_PROTECTION:
		sage_a = {"t": pA.sage_tokens, "a": pA.sage_activated}
	if subB == CardData.CardSubType.SAGE_PROTECTION:
		sage_b = {"t": pB.sage_tokens, "a": pB.sage_activated}
	_detach_equip(pA, slot_a, subA)
	_detach_equip(pB, slot_b, subB)
	_apply_equip_to_slot(pA, slot_a, subB)
	_apply_equip_to_slot(pB, slot_b, subA)
	if subA == CardData.CardSubType.SAGE_PROTECTION:
		pB.sage_tokens = sage_a.t
		pB.sage_activated = sage_a.a
	if subB == CardData.CardSubType.SAGE_PROTECTION:
		pA.sage_tokens = sage_b.t
		pA.sage_activated = sage_b.a
	_update_debug("交换了 %s 的【%s】与 %s 的【%s】" % [pA.player_name, CardData.get_type_name(subA), pB.player_name, CardData.get_type_name(subB)])
	return true

# 轻量卸下装备（不触发白银狮子回血）：坐骑计数-1；破风枪加成清零；摄魂刀跟踪清空；贤者标记清空
func _detach_equip(p: Player, slot: String, sub: CardData.CardSubType):
	p.equipment.erase(slot)
	match sub:
		CardData.CardSubType.MOUNT_PLUS:
			p.mount_plus = maxi(p.mount_plus - 1, 0)
		CardData.CardSubType.MOUNT_MINUS:
			p.mount_minus = maxi(p.mount_minus - 1, 0)
		CardData.CardSubType.POFENG_SPEAR:
			p.hand_limit_bonus = 0  # 失去破风枪：手牌上限加成清零
		CardData.CardSubType.SOUL_BLADE:
			p.soul_blade_track_target = null
			p.soul_blade_track_count = 0
		CardData.CardSubType.SAGE_PROTECTION:
			p.sage_tokens = 0
			p.sage_activated = false

# 装备到指定槽位（坐骑计数+1；破风枪加成归零重新累计；摄魂刀重置跟踪）
func _apply_equip_to_slot(p: Player, slot: String, sub: CardData.CardSubType):
	p.equipment[slot] = sub
	match sub:
		CardData.CardSubType.MOUNT_PLUS:
			p.mount_plus += 1
		CardData.CardSubType.MOUNT_MINUS:
			p.mount_minus += 1
		CardData.CardSubType.POFENG_SPEAR:
			p.hand_limit_bonus = 0
		CardData.CardSubType.SOUL_BLADE:
			p.soul_blade_track_target = null
			p.soul_blade_track_count = 0



# ============================
#  【没用】麦克斯·欧尼斯特：回合开始阶段摸一张牌，跳过自己的一个阶段，令其他角色立刻获得对应阶段
#  选项1（判定）：目标立刻判定，其乐不思蜀/兵粮寸断失效（闪电/火烧连营正常生效）
#  选项2（摸牌）：目标立刻摸 2 张；选项3（出牌）：目标立刻获得出牌阶段（AI 不出牌，立即结束）
# ============================

# 回合开始阶段询问：是否发动 + 三选一 + 选择目标（由 _do_start 调用）
func _maybe_meiyong(p: Player) -> void:
	if p.general_name != "麦克斯·欧尼斯特" or not p.is_alive():
		return
	# AI 暂不主动发动（与全游戏 AI 行为一致；测试钩子可强制）
	if p.seat_index != 0 and not _meiyong_override.is_valid():
		return
	# 是否发动（玩家0弹窗 / 测试钩子）
	var activate := false
	if _meiyong_override.is_valid():
		activate = _meiyong_override.call()
	else:
		activate = await _show_meiyong_activate_prompt()
	if not activate:
		return
	# 摸一张牌
	_draw_blank_cards(p, 1)
	_update_debug("%s 发动【没用】！摸了 1 张牌（手牌 %d 张），选择跳过一个阶段" % [p.player_name, p.hand_size()])
	# 三选一（取消 → 收回已摸的牌）
	var option := -1
	if _meiyong_option_override.is_valid():
		option = _meiyong_option_override.call()
	else:
		option = await _show_meiyong_option_prompt()
	if option < 0 or option > 2:
		p.hand.pop_back()
		_update_debug("取消【没用】（已摸的牌收回）")
		return
	match option:
		0:
			var target0 = await _pick_meiyong_target(0, p)
			if target0 == null:
				_update_debug("没有可选的判定目标，【没用】未生效（已摸的牌保留）")
				return
			turn_manager.granted_judge_target_idx = target0.seat_index
			_update_debug("%s 跳过自己的判定阶段！%s 立刻进行判定阶段（其乐不思蜀/兵粮寸断失效，闪电/火烧连营正常生效）" % [p.player_name, target0.player_name])
		1:
			var target1 = await _pick_meiyong_target(1, p)
			if target1 == null:
				_update_debug("没有可选的摸牌目标，【没用】未生效（已摸的牌保留）")
				return
			turn_manager.granted_draw_target_idx = target1.seat_index
			_update_debug("%s 跳过自己的摸牌阶段！%s 立刻获得一个摸牌阶段" % [p.player_name, target1.player_name])
		2:
			var target2 = await _pick_meiyong_target(2, p)
			if target2 == null:
				_update_debug("没有可选的出牌目标，【没用】未生效（已摸的牌保留）")
				return
			turn_manager.granted_play_target_idx = target2.seat_index
			_update_debug("%s 跳过自己的出牌阶段！%s 立刻获得一个出牌阶段" % [p.player_name, target2.player_name])
	_sync_all_ui()

# 选择目标：option 0 = 除自己外判定区有牌的角色；1/2 = 除自己外任意存活角色（下跪除外）
func _pick_meiyong_target(option: int, p: Player) -> Player:
	if _meiyong_target_override.is_valid():
		return _meiyong_target_override.call()
	var candidates: Array[Player] = []
	for pl in players:
		if pl == p or not pl.is_alive() or _is_kneeling(pl):
			continue
		if option == 0 and pl.judgment_cards.is_empty():
			continue
		candidates.append(pl)
	if candidates.is_empty():
		return null
	_is_meiyong_targeting = true
	_meiyong_option = option
	_cancel_target_btn.visible = true
	_update_debug("【没用】：请点击一名角色的头像（%s）" % ("判定区有牌的角色" if option == 0 else "任意其他角色"))
	var target = await _meiyong_pick_result
	return target

# 没用目标点击：单选，点击即生效
func _on_meiyong_target_click(target: Player):
	var p = players[turn_manager.current_player_idx]
	if target == p:
		_update_debug("不能选择自己作为目标")
		return
	if not target.is_alive():
		_update_debug("目标已阵亡")
		return
	# 【下跪】：下跪状态不会成为任何效果的目标
	if _is_kneeling(target):
		_update_debug("%s 处于【下跪】状态，不能成为目标！" % target.player_name)
		return
	if _meiyong_option == 0 and target.judgment_cards.is_empty():
		_update_debug("%s 判定区没有牌，不能选择" % target.player_name)
		return
	_is_meiyong_targeting = false
	_cancel_target_btn.visible = false
	_meiyong_pick_result.emit(target)

# 是否发动【没用】（玩家0弹窗）
func _show_meiyong_activate_prompt() -> bool:
	var idx = await _show_choice_popup("是否发动【没用】？\n（摸一张牌，然后跳过你的判定/摸牌/出牌阶段之一，令一名其他角色立刻获得对应阶段）", ["发动", "不发动"])
	return idx == 0

# 三选一（玩家0弹窗）：返回 0/1/2，-1 = 取消
func _show_meiyong_option_prompt() -> int:
	var idx = await _show_choice_popup("选择【没用】的效果：", [
		"1.跳过判定阶段，令一名判定区有牌的角色立刻判定",
		"2.跳过摸牌阶段，令一名角色立刻摸牌",
		"3.跳过出牌阶段，令一名角色立刻出牌",
	])
	return idx



# ============================
#  【噬血之刃】拼点回血
# ============================

# 每当你造成一点伤害后，你可以与受到伤害的角色进行一次拼点，若你赢则回复 1 点体力
# 按伤害点数逐点触发（酒杀 2 点 = 拼点 2 次）；每一伤害点独立询问是否发动
# 实际受伤者可能被舍己为人改写；目标已濒死（体力≤0）不拼点；舍己为人自转移（source==victim）不拼点；铁索传导不触发
func _try_bloodthirsty(source: Player, victim: Player, amount: int):
	if source == null or victim == null or source == victim:
		return
	if not source.is_alive() or not victim.is_alive():
		return
	if source.get_weapon() != CardData.CardSubType.BLOODTHIRSTY_BLADE:
		return
	# 【青釭盾】：目标无视使用效果者的武器
	if victim.get_armor() == CardData.CardSubType.QINGGANG_SHIELD:
		_update_debug("%s 的【青釭盾】无视了 %s 的【噬血之刃】！" % [victim.player_name, source.player_name])
		return
	for i in amount:
		if not source.is_alive() or not victim.is_alive():
			break
		# 可选择是否发动（每一点伤害独立询问）
		var use = await _ask_bloodthirsty(source, victim)
		if not use:
			continue
		var r = await _do_ping_dian_once(source, victim)
		if r == RPS_WIN:
			source.heal(1)
			_update_debug("%s 赢得拼点，回复 1 点体力（%d/%d）" % [source.player_name, source.hp, source.max_hp])
	_sync_all_ui()

# 是否发动噬血之刃：玩家0弹窗，AI 不满血才发动
func _ask_bloodthirsty(source: Player, victim: Player) -> bool:
	if _bloodthirsty_override.is_valid():
		return _bloodthirsty_override.call()
	if source.seat_index == 0:
		return await _show_bloodthirsty_prompt(source, victim)
	return source.hp < source.max_hp

# 玩家0的噬血之刃发动确认弹窗（锚点居中）
func _show_bloodthirsty_prompt(source: Player, victim: Player) -> bool:
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = "你对 %s 造成了伤害\n是否发动【噬血之刃】与之拼点？\n（若你赢则回复 1 点体力）" % victim.player_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(600, 90)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	var use_btn = Button.new()
	use_btn.text = "拼点"
	use_btn.custom_minimum_size = Vector2(160, 44)
	hbox.add_child(use_btn)

	var skip_btn = Button.new()
	skip_btn.text = "放弃"
	skip_btn.custom_minimum_size = Vector2(160, 44)
	skip_btn.modulate = Color(0.7, 0.7, 0.7)
	hbox.add_child(skip_btn)

	var result = [false]
	use_btn.pressed.connect(func():
		result[0] = true
		overlay.queue_free()
		_response_ready.emit()
	, CONNECT_ONE_SHOT)
	skip_btn.pressed.connect(func():
		result[0] = false
		overlay.queue_free()
		_response_ready.emit()
	, CONNECT_ONE_SHOT)

	await _response_ready
	return result[0]

# ============================
#  【灾厄剑】伤害-1 + 转移
# ============================

# 【灾厄剑】锁定被动：你造成的所有伤害-1（最低 0；减至 0 = 未造成伤害，不触发任何效果）
func _calamity_adjust(source: Player, target: Player, amount: int) -> int:
	# 【青釭盾】：成为效果目标时无视使用效果者的武器（灾厄剑的减伤不生效，全额伤害）
	if target != null and target.get_armor() == CardData.CardSubType.QINGGANG_SHIELD:
		return amount
	if source != null and source.get_weapon() == CardData.CardSubType.CALAMITY_SWORD and amount > 0:
		return maxi(amount - 1, 0)
	return amount

# 【灾厄剑】转移：造成一次伤害后，可将本装备移至一名其他角色的装备区
# 目标已有武器则替换（旧武器进弃牌堆）；EquipmentPool 占用永久保留（不解除）
func _try_calamity_transfer(source: Player):
	if source == null or not source.is_alive():
		return
	if source.get_weapon() != CardData.CardSubType.CALAMITY_SWORD:
		return
	var target = await _ask_calamity_target(source)
	if target == null:
		_update_debug("%s 放弃转移【灾厄剑】" % source.player_name)
		return
	if target == source or not target.is_alive():
		return
	# 目标武器槽：已有武器则替换（旧武器进弃牌堆）
	if target.equipment.has("weapon"):
		var old = target.equipment["weapon"]
		target.remove_equipment("weapon")
		deck.discard(CardBase.create(old))
	source.remove_equipment("weapon")
	target.equipment["weapon"] = CardData.CardSubType.CALAMITY_SWORD
	_update_debug("%s 将【灾厄剑】移至 %s 的装备区（%s 造成的伤害-1）" % [source.player_name, target.player_name, target.player_name])
	_sync_all_ui()

# 选择灾厄剑转移目标：玩家0弹窗，AI 默认发动随机选一名其他存活角色
func _ask_calamity_target(source: Player) -> Player:
	if _calamity_target_override.is_valid():
		var r = _calamity_target_override.call()
		if r is String and r == "cancel":
			return null
		return r
	if source.seat_index == 0:
		return await _show_calamity_target_picker(source)
	var alive_others: Array[Player] = []
	for p in players:
		if p != source and p.is_alive():
			alive_others.append(p)
	if alive_others.is_empty():
		return null
	return alive_others[randi() % alive_others.size()]

# 玩家0的灾厄剑转移目标弹窗（其他存活角色按钮 + 取消，锚点居中）
func _show_calamity_target_picker(source: Player) -> Player:
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = "你造成了伤害！\n是否将【灾厄剑】移至一名其他角色的装备区？"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(600, 80)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	for p in players:
		if p == source or not p.is_alive():
			continue
		var btn = Button.new()
		btn.text = p.player_name
		btn.custom_minimum_size = Vector2(140, 44)
		btn.pressed.connect(_emit_calamity_target.bind(overlay, p), CONNECT_ONE_SHOT)
		hbox.add_child(btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(140, 44)
	cancel_btn.modulate = Color(0.7, 0.7, 0.7)
	cancel_btn.pressed.connect(func():
		overlay.queue_free()
		_calamity_target_result.emit(null)
	, CONNECT_ONE_SHOT)
	vbox.add_child(cancel_btn)

	var result = await _calamity_target_result
	return result

func _emit_calamity_target(overlay: ColorRect, target: Player):
	overlay.queue_free()
	_calamity_target_result.emit(target)

# ============================
#  【灾厄袍】受伤后转移
# ============================

# 灾厄袍：当你受到一次伤害后，可将本装备移至一名其他角色的装备区
# 目标已有防具则替换（旧防具进弃牌堆）；EquipmentPool 占用永久保留（不解除）
func _try_calamity_robe_transfer(victim: Player):
	if victim == null or not victim.is_alive():
		return
	if victim.get_armor() != CardData.CardSubType.CALAMITY_ROBE:
		return
	var target = await _ask_calamity_robe_target(victim)
	if target == null:
		_update_debug("%s 放弃转移【灾厄袍】" % victim.player_name)
		return
	if target == victim or not target.is_alive():
		return
	# 目标防具槽：已有防具则替换（旧防具进弃牌堆）
	if target.equipment.has("armor"):
		var old = target.equipment["armor"]
		target.remove_equipment("armor")
		deck.discard(CardBase.create(old))
	victim.remove_equipment("armor")
	target.equipment["armor"] = CardData.CardSubType.CALAMITY_ROBE
	_update_debug("%s 将【灾厄袍】移至 %s 的装备区（%s 受到的火焰伤害+1）" % [victim.player_name, target.player_name, target.player_name])
	_sync_all_ui()

# 选择灾厄袍转移目标：玩家0弹窗，AI 默认发动随机选一名其他存活角色
func _ask_calamity_robe_target(victim: Player) -> Player:
	if _calamity_robe_target_override.is_valid():
		var r = _calamity_robe_target_override.call()
		if r is String and r == "cancel":
			return null
		return r
	if victim.seat_index == 0:
		return await _show_calamity_robe_target_picker(victim)
	var alive_others: Array[Player] = []
	for p in players:
		if p != victim and p.is_alive():
			alive_others.append(p)
	if alive_others.is_empty():
		return null
	return alive_others[randi() % alive_others.size()]

# 玩家0的灾厄袍转移目标弹窗（其他存活角色按钮 + 取消，锚点居中）
func _show_calamity_robe_target_picker(victim: Player) -> Player:
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = "你受到了伤害！\n是否将【灾厄袍】移至一名其他角色的装备区？"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(600, 80)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	for p in players:
		if p == victim or not p.is_alive():
			continue
		var btn = Button.new()
		btn.text = p.player_name
		btn.custom_minimum_size = Vector2(140, 44)
		btn.pressed.connect(_emit_calamity_robe_target.bind(overlay, p), CONNECT_ONE_SHOT)
		hbox.add_child(btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(140, 44)
	cancel_btn.modulate = Color(0.7, 0.7, 0.7)
	cancel_btn.pressed.connect(func():
		overlay.queue_free()
		_calamity_robe_target_result.emit(null)
	, CONNECT_ONE_SHOT)
	vbox.add_child(cancel_btn)

	var result = await _calamity_robe_target_result
	return result

func _emit_calamity_robe_target(overlay: ColorRect, target: Player):
	overlay.queue_free()
	_calamity_robe_target_result.emit(target)

# ============================
#  【劣马】转移（灾厄剑/灾厄袍式）
# ============================

# -1劣马：你受到伤害后，可移动一匹 -1劣马至一名其他角色的装备区（灾厄袍式时机；甩掉让自己更容易被打的劣马）
func _try_minus_mule_transfer(source: Player):
	await _try_mule_transfer(source, CardData.CardSubType.MULE_MINUS, true)

# +1劣马：与 -1 劣马一致，受到伤害后可转移。
func _try_plus_mule_transfer(source: Player):
	await _try_mule_transfer(source, CardData.CardSubType.MULE_PLUS, false)

# 劣马转移核心：持有者可选把一匹劣马移至其他角色的坐骑槽（空槽自动装；满槽顶替第一匹）
func _try_mule_transfer(p: Player, mule_sub: CardData.CardSubType, is_minus: bool):
	if p == null or not p.is_alive():
		return
	var has = p.has_mule_minus() if is_minus else p.has_mule_plus()
	if not has:
		return
	var target = await _ask_mule_target(p, is_minus)
	if target == null or target == p or not target.is_alive():
		return
	# 源移除一匹劣马
	for s in Player.MOUNT_SLOTS:
		if p.equipment.get(s, -1) == mule_sub:
			p.equipment.erase(s)
			break
	# 目标放入坐骑槽
	_place_mount_for(target, mule_sub)
	var mule_name = "-1劣马" if is_minus else "+1劣马"
	_update_debug("%s 将一匹【%s】移至 %s 的装备区" % [p.player_name, mule_name, target.player_name])
	_sync_all_ui()

# 选择劣马转移目标：玩家0弹窗，AI 默认发动随机选一名其他存活角色
func _ask_mule_target(p: Player, is_minus: bool) -> Player:
	var override_var = _minus_mule_target_override if is_minus else _plus_mule_target_override
	if override_var.is_valid():
		var r = override_var.call()
		if r is String and r == "cancel":
			return null
		return r
	if p.seat_index == 0:
		return await _show_mule_target_picker(p, is_minus)
	var alive_others: Array[Player] = []
	for pl in players:
		if pl != p and pl.is_alive():
			alive_others.append(pl)
	if alive_others.is_empty():
		return null
	return alive_others[randi() % alive_others.size()]

# 玩家0的劣马转移目标弹窗（其他存活角色按钮 + 取消，锚点居中）
func _show_mule_target_picker(p: Player, is_minus: bool) -> Player:
	var mule_name = "-1劣马" if is_minus else "+1劣马"
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = "是否将一匹【%s】移至一名其他角色的装备区？" % mule_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(600, 80)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	for pl in players:
		if pl == p or not pl.is_alive():
			continue
		var btn = Button.new()
		btn.text = pl.player_name
		btn.custom_minimum_size = Vector2(140, 44)
		if is_minus:
			btn.pressed.connect(_emit_minus_mule_target.bind(overlay, pl), CONNECT_ONE_SHOT)
		else:
			btn.pressed.connect(_emit_plus_mule_target.bind(overlay, pl), CONNECT_ONE_SHOT)
		hbox.add_child(btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(140, 44)
	cancel_btn.modulate = Color(0.7, 0.7, 0.7)
	if is_minus:
		cancel_btn.pressed.connect(func():
			overlay.queue_free()
			_minus_mule_target_result.emit(null)
		, CONNECT_ONE_SHOT)
	else:
		cancel_btn.pressed.connect(func():
			overlay.queue_free()
			_plus_mule_target_result.emit(null)
		, CONNECT_ONE_SHOT)
	vbox.add_child(cancel_btn)

	var result: Player
	if is_minus:
		result = await _minus_mule_target_result
	else:
		result = await _plus_mule_target_result
	return result

func _emit_minus_mule_target(overlay: ColorRect, target: Player):
	overlay.queue_free()
	_minus_mule_target_result.emit(target)

func _emit_plus_mule_target(overlay: ColorRect, target: Player):
	overlay.queue_free()
	_plus_mule_target_result.emit(target)

# 将指定坐骑放入目标坐骑槽（空槽自动装；满槽顶替第一匹）
func _place_mount_for(target: Player, sub: CardData.CardSubType) -> bool:
	if target.equip_mount(sub):
		return true
	var slots = target.get_mount_slots()
	if slots.is_empty():
		return false
	target.replace_mount(slots[0], sub)
	return true

# ============================
#  【摄魂刀】激活 + 拼点翻面
# ============================

# 激活计数：对同一名玩家连续且累计造成伤害（换目标则重新计数；已激活不再计）
func _update_soul_blade_count(source: Player, victim: Player, amount: int):
	if source == null or victim == null or amount <= 0:
		return
	if source.get_weapon() != CardData.CardSubType.SOUL_BLADE:
		return
	if source.soul_blade_activated:
		return
	if source.soul_blade_track_target != victim:
		# 换了目标：连续计数中断，重新累计
		source.soul_blade_track_target = victim
		source.soul_blade_track_count = 0
	source.soul_blade_track_count += amount
	if source.soul_blade_track_count >= 3:
		source.soul_blade_activated = true
		_update_debug("【摄魂刀】激活！%s 对 %s 连续累计造成 3 点伤害" % [source.player_name, victim.player_name])

# 使用杀对目标造成伤害后：与目标进行两次拼点（平局继续模式）
# 全赢 → 直接翻面；赢一输一 → 可弃 2 张手牌翻面；全输 → 可弃 4 张手牌翻面
func _try_soul_blade(source: Player, victim: Player):
	if source == null or victim == null or source == victim:
		return
	if not source.is_alive() or not victim.is_alive():
		return
	if source.get_weapon() != CardData.CardSubType.SOUL_BLADE:
		return
	# 【青釭盾】：目标无视使用效果者的武器
	if victim.get_armor() == CardData.CardSubType.QINGGANG_SHIELD:
		_update_debug("%s 的【青釭盾】无视了 %s 的【摄魂刀】！" % [victim.player_name, source.player_name])
		return
	if not source.soul_blade_activated:
		return

	# 是否发动拼点（玩家0弹窗 / AI 默认发动）
	if source.seat_index == 0:
		if not await _ask_soul_blade_activate(victim.player_name):
			return

	# 进行两次拼点（每次平局继续直到分出胜负）
	var r1 = await _do_ping_dian(source, victim)
	var r2 = await _do_ping_dian(source, victim)
	var wins = 0
	if r1 == RPS_WIN:
		wins += 1
	if r2 == RPS_WIN:
		wins += 1

	if wins == 2:
		_update_debug("%s 拼点全赢！" % source.player_name)
		_flip_character(victim)
		return

	# 赢一输一弃 2 张；全输弃 4 张（可选；手牌不足无法发动）
	var need = 2 if wins == 1 else 4
	if source.hand_size() < need:
		_update_debug("%s 手牌不足 %d 张，无法弃牌令 %s 翻面" % [source.player_name, need, victim.player_name])
		return
	if source.seat_index == 0:
		if not await _ask_soul_blade_discard(victim.player_name, need):
			return
	# 弃 need 张手牌（手牌即资源，直接移除）
	for i in need:
		source.hand.pop_back()
	_update_debug("%s 弃置 %d 张手牌，令 %s 武将牌翻面" % [source.player_name, need, victim.player_name])
	_sync_all_ui()
	_flip_character(victim)

# 翻面 = 状态切换：正面↔反面；反面角色下个回合开始前自动翻回并跳过回合
func _flip_character(p: Player):
	p.facedown = not p.facedown
	if p.facedown:
		_update_debug("%s 武将牌翻面（反面）：其下个回合将被跳过" % p.player_name)
	else:
		_update_debug("%s 武将牌翻回正面" % p.player_name)
	_sync_all_ui()

# 玩家0是否发动摄魂刀拼点
func _ask_soul_blade_activate(victim_name: String) -> bool:
	if _soul_blade_activate_override.is_valid():
		return _soul_blade_activate_override.call()
	return await _show_soul_blade_activate_prompt(victim_name)

func _show_soul_blade_activate_prompt(victim_name: String) -> bool:
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = "【摄魂刀】已激活！\n是否与 %s 进行两次拼点？（全赢直接令其翻面，否则可弃手牌令其翻面）" % victim_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(640, 90)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	var use_btn = Button.new()
	use_btn.text = "拼点"
	use_btn.custom_minimum_size = Vector2(160, 44)
	hbox.add_child(use_btn)

	var skip_btn = Button.new()
	skip_btn.text = "放弃"
	skip_btn.custom_minimum_size = Vector2(160, 44)
	skip_btn.modulate = Color(0.7, 0.7, 0.7)
	hbox.add_child(skip_btn)

	var result = [false]
	use_btn.pressed.connect(func():
		result[0] = true
		overlay.queue_free()
		_response_ready.emit()
	, CONNECT_ONE_SHOT)
	skip_btn.pressed.connect(func():
		result[0] = false
		overlay.queue_free()
		_response_ready.emit()
	, CONNECT_ONE_SHOT)

	await _response_ready
	return result[0]

# 玩家0是否弃 need 张手牌令目标翻面
func _ask_soul_blade_discard(victim_name: String, need: int) -> bool:
	if _soul_blade_discard_override.is_valid():
		return _soul_blade_discard_override.call()
	return await _show_soul_blade_discard_prompt(victim_name, need)

func _show_soul_blade_discard_prompt(victim_name: String, need: int) -> bool:
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = "拼点未全赢\n是否弃置 %d 张手牌，令 %s 武将牌翻面？" % [need, victim_name]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(600, 80)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	var use_btn = Button.new()
	use_btn.text = "弃 %d 张" % need
	use_btn.custom_minimum_size = Vector2(160, 44)
	hbox.add_child(use_btn)

	var skip_btn = Button.new()
	skip_btn.text = "放弃"
	skip_btn.custom_minimum_size = Vector2(160, 44)
	skip_btn.modulate = Color(0.7, 0.7, 0.7)
	hbox.add_child(skip_btn)

	var result = [false]
	use_btn.pressed.connect(func():
		result[0] = true
		overlay.queue_free()
		_response_ready.emit()
	, CONNECT_ONE_SHOT)
	skip_btn.pressed.connect(func():
		result[0] = false
		overlay.queue_free()
		_response_ready.emit()
	, CONNECT_ONE_SHOT)

	await _response_ready
	return result[0]

# 询问所有存活角色是否打出【舍己为人】代替 target 承受即将到来的伤害
# 返回打出者（null = 无人打出）
# 规则：受伤者本人不能使用；AI 暂不主动打出（与无懈一致）；玩家0有手牌时弹窗询问
func _maybe_sacrifice(_source: Player, target: Player, amount: int, _element: EffectChain.DamageType) -> Player:
	for i in range(player_count):
		var p = players[i]
		if p == target or not p.is_alive():
			continue
		# 【下跪】：无法使用或打出任何牌 → 不能打出舍己为人
		if _is_kneeling(p):
			continue

		var play = "skip"
		if p.seat_index == 0:
			play = await _show_sacrifice_prompt(target, amount)
		else:
			play = "skip"  # AI 暂不主动打出舍己为人

		if play != "skip":
			# 【是~啊~】（安普提·斯丢皮得）：确认使用舍己为人后询问是否发动（发动流失体力不消耗手牌；无手牌时取消 = 视为没有打出）
			var yes_ah = play
			if yes_ah == "card":
				yes_ah = await _ask_yes_ah(p, "舍己为人", p.hand_size() > 0)
			if yes_ah == "cancel":
				_update_debug("%s 取消了打出【舍己为人】" % p.player_name)
				_sync_all_ui()
				continue
			if yes_ah == "skill":
				if not await _pay_yes_ah_cost(p):
					_sync_all_ui()
					continue
			else:
				p.hand.pop_back()
				deck.discard(CardBase.create(CardData.CardSubType.SACRIFICE))
			_sync_all_ui()
			return p
	return null

# 玩家0的【舍己为人】响应弹窗（锚点居中）：返回 "card"（打出，消耗手牌）/ "skill"（发动【是~啊~】打出，无手牌时）/ "skip"（放弃）
func _show_sacrifice_prompt(target: Player, amount: int) -> String:
	var p = players[0]
	var has_hand = p.hand_size() > 0
	var is_yes_ah = p.general_name == "安普提·斯丢皮得"
	# 测试钩子：只决定「是否愿意打出」；无手牌时仅安普提可通过【是~啊~】打出
	if _sacrifice_override.is_valid():
		if not _sacrifice_override.call():
			return "skip"
		return "card" if has_hand else ("skill" if is_yes_ah else "skip")

	if not has_hand and not is_yes_ah:
		return "skip"

	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = "%s 将要受到 %d 点伤害\n是否打出【舍己为人】代替其承受？" % [target.player_name, amount]
	if not has_hand:
		label.text += "\n（无手牌，可发动【是~啊~】流失 1 点体力视为打出）"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(600, 80)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	var sacrifice_btn = Button.new()
	sacrifice_btn.text = "打出【舍己为人】" if has_hand else "发动【是~啊~】打出"
	sacrifice_btn.custom_minimum_size = Vector2(180, 44)
	hbox.add_child(sacrifice_btn)

	var skip_btn = Button.new()
	skip_btn.text = "放弃" if has_hand else "取消"
	skip_btn.custom_minimum_size = Vector2(180, 44)
	skip_btn.modulate = Color(0.7, 0.7, 0.7)
	hbox.add_child(skip_btn)

	var result = ["skip"]
	sacrifice_btn.pressed.connect(func():
		result[0] = "card" if has_hand else "skill"
		overlay.queue_free()
		_response_ready.emit()
	, CONNECT_ONE_SHOT)
	skip_btn.pressed.connect(func():
		result[0] = "skip"
		overlay.queue_free()
		_response_ready.emit()
	, CONNECT_ONE_SHOT)

	_start_response_countdown(overlay, players[0].player_name, func(): _response_ready.emit())
	await _response_ready
	_stop_countdown()
	return result[0]

# ============================
#  濒死结算
# ============================

# 【治疗权杖】：每个回合内（含其他玩家的回合），装备者使用的第一张桃额外回复 1 点体力
# 计数按玩家存（heal_staff_peach_used），回合开始时统一重置；出牌阶段用桃与濒死自救共用
func _heal_with_staff(p: Player) -> int:
	var amount = 1
	if p.get_weapon() == CardData.CardSubType.HEAL_STAFF and not p.heal_staff_peach_used:
		amount = 2
		p.heal_staff_peach_used = true
		_update_debug("%s 发动【治疗权杖】：本回合第一张【桃】额外回复 1 点体力" % p.player_name)
	p.heal(amount)
	return amount

# 濒死检查：当目标 hp ≤ 0 时，允许自救
# 阵亡管线（阶段划分，按朋友要求顺序）：
#   濒死结算（本函数）→ 自救【桃/酒】→ 阵亡效果·【装傻】（濒死拼点回血，阻止阵亡）→ 阵亡效果·【贤者的加护】（弃所有牌复原，阻止阵亡）
#   → 调用方判 is_dying()：仍濒死才进入 _handle_death（阵亡判定 → 阵亡效果·弃牌 → 翻开身份 → 击杀奖惩 → 胜负判定）
func _check_dying(dying: Player):
	if not dying.is_dying():
		return

	_update_debug("%s 进入濒死状态！" % dying.player_name)

	# 只有玩家 0（人类玩家）需要交互
	var dying_idx = -1
	for i in players.size():
		if players[i] == dying:
			dying_idx = i
			break

	if dying_idx < 0:
		return

	# 尝试自救：先允许使用桃或酒（朋友设定：贤者的加护在桃/酒自救之后才发动）
	if dying_idx == 0:
		while dying.is_dying():
			var hp_before = dying.hp
			await _show_dying_prompt(dying)
			if dying.hp <= hp_before:
				break # 放弃或没有可用救援牌；负体力时允许连续自救。
	else:
		# AI 玩家暂时不自救
		pass

	# 桃/酒自救后仍处于濒死 → 阵亡效果·【装傻】（安普提·斯丢皮得，锁定技）：与所有存活玩家拼点，赢超过一半回复至 1 点体力
	if dying.is_dying() and dying.general_name == "安普提·斯丢皮得":
		await _try_zhuangsha(dying)
		if dying.is_alive():
			_sync_all_ui()

	# 桃/酒自救/装傻后仍处于濒死 → 阵亡效果·【贤者的加护】（激活后）：即将死亡时可弃置所有牌，复原武将牌至游戏开始时的状态，摸四张牌
	if dying.is_dying() and dying.get_armor() == CardData.CardSubType.SAGE_PROTECTION and dying.sage_activated:
		var use_save = await _ask_sage_save(dying)
		if use_save:
			_do_sage_save(dying)
	# 普通嵌套救援中，先前的死亡可能因仍有濒死者而未判胜。
	# 救回后同样需要重查；未救回则由调用者确认死亡后重查。
	if dying.is_alive():
		_check_win_condition(null, null)

# ============================
#  阵亡处理管线（阶段1-5，按朋友要求顺序分开）
# ============================
# 调用时机：濒死结算（_check_dying）全部结束，角色体力仍 ≤ 0
#   阶段1 阵亡判定 —— 确认阵亡（体力 ≤ 0），防重复处理
#   阶段2 阵亡效果 —— 弃置所有手牌/装备/判定牌/已确定牌（未来死亡技能钩子在此插入）
#   阶段3 翻开身份 —— identity_revealed = true，UI 显示身份
#   阶段4 击杀奖惩 —— 杀死【反贼】：击杀者摸 3 张；主公杀死【忠臣】：主公弃置所有手牌和装备
#   阶段5 胜负判定 —— 五人标准身份局按已死亡/仍存活身份判定；不依赖凶手身份
func _handle_death(victim: Player, killer: Player):
	# ---- 阶段1 阵亡判定 ----
	if _dead_processed.has(victim):
		return
	if not victim.is_dying():
		return
	victim.mark_dead()
	_dead_processed.append(victim)
	_update_debug("%s 阵亡！" % victim.player_name)

	# ---- 阶段2 阵亡效果：弃置所有牌 ----
	_discard_all_cards(victim, true)
	_update_debug("%s 弃置了所有牌（手牌/装备/判定牌）" % victim.player_name)

	# ---- 阶段3 翻开身份 ----
	if victim.identity != "":
		victim.identity_revealed = true
		_update_debug("身份翻开：%s 是【%s】！" % [victim.player_name, victim.identity])
	_sync_all_ui()

	# ---- 阶段4 击杀奖惩（胜负未分时才执行；体力流失致死等无击杀者不触发）----
	if not _game_over and killer != null and killer.is_alive():
		if victim.identity == "反贼":
			_draw_blank_cards(killer, 3)
			_update_debug("奖惩：%s 击杀【反贼】%s，摸 3 张牌！（%d 张）" % [killer.player_name, victim.player_name, killer.hand_size()])
		elif victim.identity == "忠臣" and killer.identity == "主公":
			_discard_all_cards(killer, false)
			_update_debug("奖惩：主公 %s 误杀忠臣 %s，弃置所有手牌和装备！（%d 张手牌）" % [killer.player_name, victim.player_name, killer.hand_size()])

	# ---- 阶段5 胜负判定 ----
	_check_win_condition(victim, killer)

# 弃置一名角色的所有牌（死亡弃置 / 主公杀忠臣惩罚共用）
# include_judgment = true 时连判定区/已确定牌一起弃（死亡用）；false 只弃手牌+装备（主公惩罚用）
func _discard_all_cards(p: Player, include_judgment: bool):
	for c in p.hand:
		if c != null:
			deck.discard(c)
	p.hand.clear()
	for slot in p.get_equip_slots():
		var sub = p.equipment[slot]
		# 暗置占位是假牌，不产生实体牌进弃牌堆
		if sub != CardData.CardSubType.HIDDEN_EQUIPMENT:
			deck.discard(CardBase.create(sub))
		p.remove_equipment(slot)
	if include_judgment:
		for c in p.judgment_cards:
			if c != null:
				deck.discard(c)
		p.judgment_cards.clear()
		for c in p.determined_cards:
			if c != null:
				deck.discard(c)
		p.determined_cards.clear()
		p.hidden_equip_slot = ""

# 五人标准身份局判胜；保留旧调用签名，但击杀者只影响奖惩，不决定胜方。
# 1V1、奸雄、特殊多人死亡时序仍由对应 QA 单独确认。
func _check_win_condition(_victim: Player, _killer: Player):
	if _game_over or player_count != 5:
		return
	var outcome = IdentityVictory.evaluate(players)
	if not outcome.is_empty():
		_finish_game(outcome["winner"], outcome["reason"])

# 结束游戏：置 _game_over 标志 + 发信号（弹窗显示胜方，回合不再推进）
func _finish_game(winner_identity: String, reason: String):
	if _game_over:
		return
	_game_over = true
	_update_debug("游戏结束！【%s】阵营获胜！（%s）" % [winner_identity, reason])
	game_over.emit(winner_identity)

# 游戏结束弹窗（锚点居中）：显示胜方 + 返回主菜单
func _on_game_over(winner_identity: String):
	if _game_over_overlay != null and is_instance_valid(_game_over_overlay):
		_game_over_overlay.queue_free()
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.75)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 300
	$UI.add_child(overlay)
	_game_over_overlay = overlay

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 24)
	overlay.add_child(vbox)

	var title = Label.new()
	var winner_text = {
		"主公": "主公阵营（主公与忠臣）",
		"反贼": "反贼阵营",
		"内奸": "内奸",
	}.get(winner_identity, winner_identity)
	title.text = "游戏结束！\n%s 获胜！" % winner_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	vbox.add_child(title)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hbox)

	var btn = Button.new()
	btn.text = "返回主菜单"
	btn.custom_minimum_size = Vector2(200, 52)
	btn.pressed.connect(func():
		get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn")
	)
	hbox.add_child(btn)

# 测试用：重置游戏结束状态（新一轮/新用例前调用），并解除阵亡管线重复处理记录
func reset_game_over_state():
	_game_over = false
	_dead_processed.clear()
	for p in players:
		p.reset_death_state()
	if _game_over_overlay != null and is_instance_valid(_game_over_overlay):
		_game_over_overlay.queue_free()
		_game_over_overlay = null

# 询问是否使用贤者的加护保命：玩家0弹窗，AI 默认使用（保命）
func _ask_sage_save(dying: Player) -> bool:
	if _sage_save_override.is_valid():
		return _sage_save_override.call()
	if dying.seat_index == 0:
		return await _show_sage_save_prompt()
	return true  # AI 默认使用

# 玩家0的贤者的加护保命弹窗（锚点居中）
func _show_sage_save_prompt() -> bool:
	var overlay = ColorRect.new()
	overlay.color = Color(0.2, 0.0, 0.3, 0.6)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = "你即将死亡！\n是否发动【贤者的加护】？\n（弃置所有牌，复原武将牌，摸四张牌）"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(600, 90)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	var use_btn = Button.new()
	use_btn.text = "发动【贤者的加护】"
	use_btn.custom_minimum_size = Vector2(200, 44)
	hbox.add_child(use_btn)

	var skip_btn = Button.new()
	skip_btn.text = "放弃"
	skip_btn.custom_minimum_size = Vector2(200, 44)
	skip_btn.modulate = Color(0.7, 0.7, 0.7)
	hbox.add_child(skip_btn)

	var result = [false]
	use_btn.pressed.connect(func():
		result[0] = true
		overlay.queue_free()
		_response_ready.emit()
	, CONNECT_ONE_SHOT)
	skip_btn.pressed.connect(func():
		result[0] = false
		overlay.queue_free()
		_response_ready.emit()
	, CONNECT_ONE_SHOT)

	_start_response_countdown(overlay, players[0].player_name, func(): _response_ready.emit())
	await _response_ready
	_stop_countdown()
	return result[0]

# 执行贤者的加护保命：弃置所有牌（手牌/装备/判定牌）→ 复原武将牌至游戏开始时的状态 → 摸四张牌
func _do_sage_save(p: Player):
	# 清理全部区域；不是把旧手牌/装备重新发回。
	_discard_all_cards(p, true)
	p.restore_game_start_state()
	p.chained = false
	p.wine_stacks = 0
	p.sage_tokens = 0
	p.sage_activated = false
	p.hand_limit_bonus = 0
	p.heal_staff_peach_used = false
	p.soul_blade_activated = false
	p.soul_blade_track_target = null
	p.soul_blade_track_count = 0
	p.mount_plus = 0
	p.mount_minus = 0
	p.hidden_equip_slot = ""
	# 一次恢复完再发牌，避免中间的零手牌状态重触发觉醒。
	_draw_blank_cards(p, 4)
	_update_debug("%s 发动【贤者的加护】：弃置所有牌，复原武将牌，摸四张牌！（%d/%d，手牌 %d 张）" % [p.player_name, p.hp, p.max_hp, p.hand_size()])
	_sync_all_ui()

func _show_dying_prompt(dying: Player):
	# 测试钩子：直接模拟用【桃】自救（有桃才有效）
	if _dying_peach_override.is_valid():
		if _dying_peach_override.call():
			for i in dying.hand.size():
				var c = dying.hand[i]
				if c != null and c.sub_type == CardData.CardSubType.PEACH:
					dying.hand.remove_at(i)
					deck.discard(CardBase.create(CardData.CardSubType.PEACH))
					var healed = _heal_with_staff(dying)
					_update_debug("%s 使用【桃】自救，回复 %d 点体力（%d/%d）" % [dying.player_name, healed, dying.hp, dying.max_hp])
					break
			_sync_all_ui()
		return

	# 检查手牌中是否有桃或酒
	var has_peach = false
	var has_wine = false
	for c in dying.hand:
		if c == null:
			continue
		if c.sub_type == CardData.CardSubType.PEACH:
			has_peach = true
		if c.sub_type == CardData.CardSubType.WINE:
			has_wine = true

	if not has_peach and not has_wine:
		_update_debug("%s 没有【桃】或【酒】，无法自救…" % dying.player_name)
		return

	var overlay = ColorRect.new()
	overlay.color = Color(0.3, 0.0, 0.0, 0.6)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = "你已进入濒死状态！"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.4))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(500, 60)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	var saved = [false]

	if has_peach:
		var peach_btn = Button.new()
		peach_btn.text = "使用【桃】"
		peach_btn.custom_minimum_size = Vector2(160, 44)
		peach_btn.pressed.connect(func():
			saved[0] = true
			# 移除一张桃
			var found = false
			for i in dying.hand.size():
				var c = dying.hand[i]
				if c != null and c.sub_type == CardData.CardSubType.PEACH:
					dying.hand.remove_at(i)
					found = true
					break
			if found:
				deck.discard(CardBase.create(CardData.CardSubType.PEACH))
				var healed = _heal_with_staff(dying)
				_update_debug("%s 使用【桃】自救，回复 %d 点体力（%d/%d）" % [dying.player_name, healed, dying.hp, dying.max_hp])
			overlay.queue_free()
			_sync_all_ui()
			_response_ready.emit()
		, CONNECT_ONE_SHOT)
		hbox.add_child(peach_btn)

	if has_wine:
		var wine_btn = Button.new()
		wine_btn.text = "使用【酒】"
		wine_btn.custom_minimum_size = Vector2(160, 44)
		wine_btn.pressed.connect(func():
			saved[0] = true
			# 移除一张酒
			var found = false
			for i in dying.hand.size():
				var c = dying.hand[i]
				if c != null and c.sub_type == CardData.CardSubType.WINE:
					dying.hand.remove_at(i)
					found = true
					break
			if found:
				deck.discard(CardBase.create(CardData.CardSubType.WINE))
				dying.heal(1)
				_update_debug("%s 使用【酒】自救，回复 1 点体力（%d/%d）" % [dying.player_name, dying.hp, dying.max_hp])
			overlay.queue_free()
			_sync_all_ui()
			_response_ready.emit()
		, CONNECT_ONE_SHOT)
		hbox.add_child(wine_btn)

	# 放弃按钮（独立一行，居中）
	var skip_btn = Button.new()
	skip_btn.text = "放弃"
	skip_btn.custom_minimum_size = Vector2(160, 44)
	skip_btn.modulate = Color(0.6, 0.6, 0.6)
	skip_btn.pressed.connect(func():
		overlay.queue_free()
		_response_ready.emit()
	, CONNECT_ONE_SHOT)
	vbox.add_child(skip_btn)

	_start_response_countdown(overlay, players[0].player_name, func(): _response_ready.emit())
	await _response_ready
	_stop_countdown()
	_sync_all_ui()

func end_play_phase():
	if turn_manager.current_phase == TurnManager.Phase.PLAY:
		_play_btn.visible = false
		_end_play_btn.visible = false
		_cancel_target_btn.visible = false
		_confirm_target_btn.visible = false
		_is_targeting = false
		_is_iron_chain_targeting = false
		_iron_chain_targets.clear()
		_is_multi_targeting = false
		_multi_targets.clear()
		_is_zhuangbi_targeting = false
		_zhuangbi_targets.clear()
		_is_campus_targeting = false
		_is_lanzhonghou_targeting = false
		_lanzhonghou_selected.clear()
		_lanzhonghou_pending.clear()
		_is_meiyong_targeting = false
		_yes_ah_active = false  # 【是~啊~】：结束出牌时清理未消费的激活标记
		turn_manager.advance_phase()

# ---- UI 回调 ----

func _on_play_btn_pressed():
	if turn_manager.current_phase != TurnManager.Phase.PLAY:
		return
	var p = players[turn_manager.current_player_idx]
	if p.hand_size() <= 0:
		_update_debug("没有手牌了")
		return

	var selector = _selector_scene.instantiate()
	selector.player = players[turn_manager.current_player_idx]
	$UI.add_child(selector)
	selector.confirmed.connect(_on_selector_confirmed)
	selector.cancelled.connect(_on_selector_cancelled)
	selector.determined_card_clicked.connect(_on_determined_card_clicked)

func _on_end_play_pressed():
	end_play_phase()

func _on_selector_confirmed(sub: CardData.CardSubType):
	_reveal_ask_pending = true
	await play_card(sub)
	# 【苕】任意玩家行动后询问是否明置
	await _maybe_ask_reveal()

func _on_selector_cancelled():
	_update_debug("取消出牌")

func _on_determined_card_clicked(card: CardBase):
	_update_debug("【%s】已确定在手，装备/判定系统开发中，暂不能使用" % card.card_name)

# ============================
#  玩家面板点击 → 目标选择 or 详情
# ============================

func _on_player_panel_click(event: InputEvent, panel: Control):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var player: Player = panel.get_meta("player")
		if not player:
			return

		# 方天画戟多目标模式：点击头像 toggle 目标
		if _is_multi_targeting:
			_on_multi_target_click(player)
			return

		# 【装逼】目标选择：点击头像 toggle
		if _is_zhuangbi_targeting:
			_on_zhuangbi_target_click(player)
			return

		# 【校园霸主】目标选择：点击头像选目标（单选，点击即执行）
		if _is_campus_targeting:
			_on_campus_target_click(player)
			return

		# 【神速】选项1 杀目标选择：点击头像选目标（单选，点击即执行）
		if _is_shensu_targeting:
			_on_shensu_target_click(player)
			return

		# 【Gay】回复目标选择：点击头像选目标（单选）
		if _is_gay_targeting:
			_on_gay_target_click(player)
			return

		# 【烂忠厚】角色选择：点击头像选择/取消（选满 2 名进入区域选择）
		if _is_lanzhonghou_targeting:
			_on_lanzhonghou_target_click(player)
			return

		# 【没用】目标选择：点击头像选目标（单选）
		if _is_meiyong_targeting:
			_on_meiyong_target_click(player)
			return

		# 【贤者的加护】拼点目标选择：点击头像选拼点对象
		if _is_sage_targeting:
			_on_sage_target_click(player)
			return

		# 铁索连环选择模式：点击角色头像选目标（可含自己）
		if _is_iron_chain_targeting:
			_on_iron_chain_target_click(player)
			return

		# 目标选择模式：点击头像选目标
		if _is_targeting:
			_on_target_click(player)
			return

		# 普通模式：打开详情
		_open_player_detail(player)

# 目标选择模式下的点击处理
func _on_target_click(target: Player):
	var attacker = players[turn_manager.current_player_idx]

	if target == attacker:
		_update_debug("不能选择自己作为目标")
		return

	if not target.is_alive():
		_update_debug("目标已阵亡")
		return

	# 【下跪】：下跪状态不会成为任何效果的目标
	if _is_kneeling(target):
		_update_debug("%s 处于【下跪】状态，不能成为目标！" % target.player_name)
		return

	# 【藤甲】：你不能成为【杀】的目标（判定在距离检查之前，青釭剑不例外）
	var is_strike_target = _targeting_card_sub == CardData.CardSubType.STRIKE \
			or _targeting_card_sub == CardData.CardSubType.FIRE_STRIKE \
			or _targeting_card_sub == CardData.CardSubType.THUNDER_STRIKE
	if is_strike_target and target.get_armor() == CardData.CardSubType.TENGJIA:
		_update_debug("%s 的【藤甲】：不能成为【杀】的目标！" % target.player_name)
		return
	# 【觉醒】选择1：不能成为【杀】的目标（目标选择层面免疫，青釭剑不例外）
	if is_strike_target and _awake_blocks(target, 1):
		_update_debug("%s 的【觉醒】：不能成为【杀】的目标！" % target.player_name)
		return
	# 【裸奔】：凯文·罗本装备区无装备时不能成为【杀】的目标（判定在距离检查之前）
	if is_strike_target and _is_bare_running(target):
		_update_debug("%s 的【裸奔】：装备区没有装备，不能成为【杀】的目标！" % target.player_name)
		return

	# 【战旗】：你不能成为【决斗】的目标
	if _targeting_card_sub == CardData.CardSubType.DUEL and target.get_armor() == CardData.CardSubType.ZHANQI:
		_update_debug("%s 的【战旗】：不能成为【决斗】的目标！" % target.player_name)
		return
	# 【觉醒】选择2：不能成为【决斗】的目标
	if _targeting_card_sub == CardData.CardSubType.DUEL and _awake_blocks(target, 2):
		_update_debug("%s 的【觉醒】：不能成为【决斗】的目标！" % target.player_name)
		return

	# 检查攻击距离（过河拆桥/乐不思蜀不受距离限制；麒麟弓杀无距离限制；兵粮限距离1由目标列表保证；决斗限距离2）
	var no_distance_sub_types = [
		CardData.CardSubType.DISMANTLE,
		CardData.CardSubType.INDULGENCE,
	]
	var qiling_bow = is_strike_target and attacker.get_weapon() == CardData.CardSubType.QILING_BOW
	# 【决斗】距离限制 2（含马修正）：与杀的距离规则一致，只是上限为 2
	var duel_in_range = _targeting_card_sub == CardData.CardSubType.DUEL and attacker.attack_distance_to(target) <= 2
	# 【霸王】（杰基·斯特朗）：你的【决斗】无距离限制
	var jacqui_duel_free = _targeting_card_sub == CardData.CardSubType.DUEL and attacker.general_name == "杰基·斯特朗"
	if not no_distance_sub_types.has(_targeting_card_sub) and not qiling_bow and not duel_in_range and not jacqui_duel_free and not attacker.can_attack(target):
		var dist = attacker.attack_distance_to(target)
		if _targeting_card_sub == CardData.CardSubType.DUEL:
			_update_debug("%s 距离 %s 为 %d，超出决斗距离 2！请选择其他目标" % [attacker.player_name, target.player_name, dist])
		else:
			_update_debug("%s 距离 %s 为 %d，超出攻击距离 1！请选择其他目标" % [attacker.player_name, target.player_name, dist])
		return

	# 目标有效 → 确认弹窗
	var confirmed = await _show_target_confirm(attacker.player_name, target.player_name, _targeting_card_sub)
	if not confirmed:
		_update_debug("取消对 %s 出牌" % target.player_name)
		return  # 继续目标选择模式

	# 确认 → 执行
	_is_targeting = false
	_cancel_target_btn.visible = false
	_reveal_ask_pending = true
	await execute_card_on_target(target, _targeting_card_sub)
	_targeting_card_sub = -1
	# 【苕】任意玩家行动后询问是否明置
	await _maybe_ask_reveal()
	# 恢复出牌按钮
	_play_btn.visible = true
	_end_play_btn.visible = true

# ============================
#  详情弹窗
# ============================

func _open_player_detail(player: Player):
	for child in _detail_popup_root.get_children():
		child.queue_free()

	_detail_popup_root.visible = true
	var popup = PlayerDetailPopup.create(_detail_popup_root, player, player.wine_stacks)
	popup.equip_clicked.connect(_on_detail_equip_clicked.bind(player))
	popup.skill_clicked.connect(_on_detail_skill_clicked.bind(player))
	popup.tree_exited.connect(_on_detail_popup_closed)

func _on_detail_popup_closed():
	if _detail_popup_root.get_child_count() == 0:
		_detail_popup_root.visible = false

# ============================
#  【下跪】限定技（布鲁斯·萨维奇）
# ============================

# 详情弹窗技能点击：目前有【下跪】（布鲁斯·萨维奇）/【苕】（安普提·斯丢皮得）/【装逼】（史蒂芬·彼特先斯）/【校园霸主】（杰基·斯特朗）可交互
func _on_detail_skill_clicked(skill_key: String, owner_player: Player):
	if skill_key == "苕":
		await _on_sao_skill_clicked(owner_player)
		return
	if skill_key == "装逼":
		await _on_zhuangbi_skill_clicked(owner_player)
		return
	if skill_key == "校园霸主":
		await _on_campus_skill_clicked(owner_player)
		return
	if skill_key == "Gay":
		await _on_gay_skill_clicked(owner_player)
		return
	if skill_key == "烂忠厚":
		await _on_lanzhonghou_skill_clicked(owner_player)
		return
	if skill_key != "下跪":
		return
	var p = players[0]
	if owner_player != p or p.seat_index != 0:
		_update_debug("只能对自己使用【下跪】")
		return
	if p.general_name != "布鲁斯·萨维奇":
		return

	# 限定技已使用（当前未下跪）→ 技能灰色，点击提示
	if p.kneel_used and not p.kneeling:
		_show_toast("限定技已使用")
		return

	# 下跪状态中 → 询问是否解除（任意时刻）
	if p.kneeling:
		var cancel = await _show_kneel_confirm("是否解除【下跪】状态？", "解除", "保持")
		if cancel:
			p.kneeling = false
			_update_debug("%s 解除了【下跪】状态" % p.player_name)
			_sync_all_ui()
			_refresh_detail_popup()
		return

	# 未使用：检查发动条件（回合外 + 没有手牌 + 已经受伤）
	if not _kneel_conditions_met(p):
		if turn_manager.current_player_idx == p.seat_index:
			_show_toast("【下跪】只能在你的回合外发动")
		elif p.hand_size() > 0:
			_show_toast("【下跪】发动条件：没有手牌")
		else:
			_show_toast("【下跪】发动条件：已经受伤（体力小于上限）")
		return
	var ok = await _show_kneel_confirm("是否发动【下跪】？\n（下跪状态：不会成为任何效果的目标，无法使用或打出任何牌，手牌上限固定为 5）", "发动", "取消")
	if ok:
		p.kneeling = true
		p.kneel_used = true
		_update_debug("%s 发动【下跪】！进入下跪状态（不会成为任何效果的目标，无法使用或打出任何牌，手牌上限固定为 5）" % p.player_name)
		_sync_all_ui()
		_refresh_detail_popup()

# 【下跪】确认弹窗（发动 / 解除）：返回 true = 确认
func _show_kneel_confirm(question: String, yes_text: String, no_text: String) -> bool:
	if _kneel_override.is_valid():
		return _kneel_override.call()

	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	$UI.add_child(overlay)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var label = Label.new()
	label.text = question
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(600, 80)
	vbox.add_child(label)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	var yes_btn = Button.new()
	yes_btn.text = yes_text
	yes_btn.custom_minimum_size = Vector2(160, 44)
	hbox.add_child(yes_btn)

	var no_btn = Button.new()
	no_btn.text = no_text
	no_btn.custom_minimum_size = Vector2(160, 44)
	no_btn.modulate = Color(0.7, 0.7, 0.7)
	hbox.add_child(no_btn)

	var result = [false]
	yes_btn.pressed.connect(func():
		result[0] = true
		overlay.queue_free()
		_kneel_cfm_result.emit(true)
	, CONNECT_ONE_SHOT)
	no_btn.pressed.connect(func():
		result[0] = false
		overlay.queue_free()
		_kneel_cfm_result.emit(false)
	, CONNECT_ONE_SHOT)

	var res = await _kneel_cfm_result
	return res

# 刷新详情弹窗（下跪发动/解除后技能颜色、状态区更新）
func _refresh_detail_popup():
	if _detail_popup_root.get_child_count() > 0:
		var popup = _detail_popup_root.get_child(0)
		if popup is PlayerDetailPopup:
			popup.refresh()

# 短提示（居中浮层，2 秒后淡出）：限定技已使用 / 发动条件不满足等
func _show_toast(msg: String):
	if _toast_label == null:
		_toast_label = Label.new()
		_toast_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_toast_label.add_theme_font_size_override("font_size", 22)
		_toast_label.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
		_toast_label.z_index = 200
		_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		$UI.add_child(_toast_label)
	_toast_label.text = msg
	_toast_label.modulate = Color(1, 1, 1, 1)
	_toast_remaining = 2.0

# ============================
#  UI 同步
# ============================

func _sync_all_ui():
	# 【觉醒】（史蒂芬·彼特先斯）：手牌为 0 时立即自动觉醒（觉醒技）
	_check_awaken_trigger()
	_update_player_panel(_self_info_panel, players[0])

	for i in range(4):
		var seat = i + 1
		if seat < players.size() and i < _other_player_panels.size():
			_update_player_panel(_other_player_panels[i], players[seat])

	var my_turn = (turn_manager.current_player_idx == 0)
	if my_turn and turn_manager.current_phase == TurnManager.Phase.PLAY:
		_play_btn.disabled = (players[0].hand_size() <= 0 or _is_kneeling(players[0]))
	else:
		_play_btn.disabled = true

func _process(delta: float):
	# 倒计时：先扣每步 30 秒，耗尽后扣整局储备；储备也耗尽才超时
	if _countdown_active:
		_step_remaining -= delta
		if _step_remaining <= 0.0:
			_bank_remaining += _step_remaining
			_step_remaining = 0.0
			if _bank_remaining <= 0.0:
				_countdown_active = false
				_countdown_label.text = ""
				var cb = _countdown_on_timeout
				_countdown_on_timeout = Callable()
				if cb.is_valid():
					cb.call()
				return
		_update_countdown_label()
	# 实时日志 5 秒后消失
	if _log_remaining > 0.0:
		_log_remaining -= delta
		if _log_remaining <= 0.0:
			_log_label.text = ""
	# 短提示淡出
	if _toast_remaining > 0.0:
		_toast_remaining -= delta
		if _toast_remaining <= 0.0 and _toast_label != null:
			_toast_label.modulate = Color(1, 1, 1, 0)

# ============================
#  倒计时 / 提示句 / 实时日志
# ============================

# 中间提示句：只显示当前正在倒计时的内容（阶段 / 等待谁响应）
func _set_status_line(msg: String):
	_debug_label.text = msg
	_debug_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))

# 根据当前回合状态刷新提示句（并启动/停止对应倒计时）
func _refresh_status_line():
	var pid = turn_manager.current_player_idx
	if pid >= players.size():
		return
	var pname = players[pid].player_name
	_halt_countdown()
	match turn_manager.current_phase:
		TurnManager.Phase.PLAY:
			if pid == 0:
				_start_play_countdown()
			else:
				_set_status_line("%s 出牌阶段" % pname)
		TurnManager.Phase.DISCARD:
			_set_status_line("%s 弃牌阶段" % pname)
		TurnManager.Phase.END:
			_set_status_line("%s 回合结束" % pname)
		_:
			_set_status_line("%s 回合" % pname)

# 出牌阶段倒计时：每次成功出牌重置每步 30 秒（整局储备不重置），超时自动结束出牌
func _start_play_countdown():
	_halt_countdown()
	_set_status_line("%s 出牌阶段" % players[0].player_name)
	_step_remaining = STEP_SECONDS
	_countdown_active = true
	_countdown_on_timeout = func(): end_play_phase()
	_update_countdown_label()

# 响应弹窗倒计时：超时自动放弃（关闭弹窗并发出对应信号）
func _start_response_countdown(overlay: Control, who: String, on_timeout: Callable):
	_halt_countdown()
	_set_status_line("等待 %s 响应" % who)
	_step_remaining = STEP_SECONDS
	_countdown_active = true
	_countdown_on_timeout = func():
		overlay.queue_free()
		on_timeout.call()
	_update_countdown_label()

# 出牌阶段成功打出一张牌后重置每步倒计时（仅玩家0出牌阶段且倒计时运行中）
func _reset_play_countdown_if_p0():
	if turn_manager.current_player_idx == 0 and turn_manager.current_phase == TurnManager.Phase.PLAY and _countdown_active:
		_start_play_countdown()

# 停止倒计时并恢复阶段提示（响应结束后回到当前阶段状态）
func _stop_countdown():
	_halt_countdown()
	_refresh_status_line()

func _halt_countdown():
	_countdown_active = false
	_countdown_on_timeout = Callable()
	_step_remaining = 0.0
	_countdown_label.text = ""

func _update_countdown_label():
	# 显示总剩余 = 本步 + 整局储备
	var total = _step_remaining + _bank_remaining
	var secs = ceili(total)
	_countdown_label.text = "⏳ %d 秒" % secs
	if secs <= 10 or _bank_remaining <= 5.0:
		_countdown_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	else:
		_countdown_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.5))

func _update_debug(msg: String, color: Color = Color(1, 1, 1, 0.55)):
	# 实时日志：显示在提示句上方，5 秒后消失或被新内容替换（可传颜色：拼点结果按胜负着色）
	_log_label.text = msg
	_log_label.add_theme_color_override("font_color", color)
	_log_remaining = 5.0
	print("[Game] ", msg)
