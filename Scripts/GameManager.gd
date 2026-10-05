# ============================================================
# GameManager.gd — 游戏主控
# 五人局 + 攻击距离 + 点击头像选目标出牌
# ============================================================
class_name GameManager
extends Node

# 每次救援弹窗使用独立答复对象，避免与外层响应信号串线或重复点击。
class RescueAnswer extends RefCounted:
	signal answered(sub: int)
	var settled := false

	func submit(sub: int):
		if settled:
			return
		settled = true
		answered.emit(sub)

# 通用选择窗口的答复仅属于该窗口；失效不能冒充主动取消。
const CHOICE_INVALID: int = -2
var _choice_prompt_stack: Array[Dictionary] = []
var _countdown_generation: int = 0

signal game_started()
signal game_over(winner_identity: String)
signal card_action_committed(event: CardActionEvent)
var _card_action_serial: int = 0

@export var player_count: int = 5
@export var auto_start: bool = true

const MODE_CLASSIC_IDENTITY := "classic_identity"
const MODE_FREE_FOR_ALL := "free_for_all"

# 主菜单选中的武将（玩家0 使用），静态变量跨场景保留；直接加载游戏（测试）时默认凯文·罗本
static var selected_general: String = "凯文·罗本"
# 主菜单选中的对局人数（2/3 人乱斗、5 人标准），静态跨场景保留；直接加载默认 5 人
static var selected_players: int = 5
static var selected_mode: String = MODE_CLASSIC_IDENTITY
var game_mode: String = MODE_CLASSIC_IDENTITY
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
var _card_target_generation: int = 0
var _card_target_confirm_owner: int = -1
var _sao_opportunity_generation: int = 0
# 从「已确定的牌」点击进入出牌流程时，保留待支付的原资源；只在使用真正成立时移除。
var _pending_determined_card: CardBase = null

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
var yudaxi = YudaxiResolver.new()
var _sacrifice_override: Callable = Callable()
# 座位无关的舍己决策入口；默认AI策略仍在D03接入。
var _sacrifice_actor_override: Callable = Callable()
var ai_driver = DecisionDriver.new()
var _ai_running_revisions: Dictionary = {}
var _ai_hand_snapshot: HandSelection
var _ai_offered_actions: Array = []
var _ai_response_override: Callable = Callable()

# AOE 响应测试钩子（正常游戏不设置，南蛮/万箭）：返回 true = 玩家0打出响应牌
var _aoe_override: Callable = Callable()

# 烈火盾测试钩子（正常游戏不设置）：返回 true = 拆/顺目标失去1体力使该牌对自己无效
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

# 满坐骑槽替换选择测试钩子（正常游戏不设置）：返回槽位名或 "cancel"
var _mount_replace_override: Callable = Callable()

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
# 救援决策测试钩子：(出牌者, 濒死者, 合法牌型数组) -> 牌型或 -1（放弃）。
# 只替代决策，不绕过确认时的合法性和实际支付。
var _rescue_choice_override: Callable = Callable()

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
var _sao_reveal_slot_override: Callable = Callable()  # 测试：多张暗置时选择具体槽位
var _sao_transfer_declare_override: Callable = Callable()  # 测试钩子：暗置装备离区后由原持有者声明
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
# 尚未完成的濒死窗口：同一角色不重开，嵌套窗口全部结束后才检查终局。
var _dying_contexts: Dictionary = {}
# 跳过阵亡角色回合时的重入保护（next_turn 会同步触发 START 阶段回调）
var _skipping_dead: bool = false

# 【装逼】（史蒂芬·彼特先斯）：点击头像 → 详情弹窗 → 技能发动 + 目标选择模式
var _is_zhuangbi_targeting: bool = false
var _zhuangbi_blocked_this_phase: bool:
	get: return turn_manager.phase_skill_used("zhuangbi_blocked")
	set(value): turn_manager.set_phase_skill_used("zhuangbi_blocked", value)
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
var _campus_execution_generation: int = 0
var _campus_execution_owner: int = -1
# 【神速】（比尔·盖伊）：回合开始选项1 的杀目标选择中
var _is_shensu_targeting: bool = false
# 【Gay】（比尔·盖伊）：回复目标选择中
var _is_gay_targeting: bool = false
var _gay_execution_generation: int = 0
var _gay_execution_owner: int = -1
# 【Gay】按实际操作者与规则阶段登记，响应返回不刷新。
var _gay_used: bool:
	get: return turn_manager.phase_skill_used("gay")
	set(value): turn_manager.set_phase_skill_used("gay", value)
# 【觉醒】三选一测试钩子（正常游戏不设置）：返回 1 / 2 / 3（觉醒效果选择）
var _awaken_pick_override: Callable = Callable()

# 内部历史ID保持不变：lanzhonghou = 交换【没用】，meiyong = 赠送【烂忠厚】。
# ---- 【没用】（麦克斯·欧尼斯特）：出牌阶段限一次，弃 X 张牌交换两名角色的 X 个装备区域 ----
var _lanzhonghou_used: bool:
	get: return turn_manager.phase_skill_used("max_exchange")
	set(value): turn_manager.set_phase_skill_used("max_exchange", value)
var _is_lanzhonghou_targeting: bool = false         # 选择两名角色中
var _lanzhonghou_selected: Array[Player] = []       # 已选角色（0/1 个，选满 2 个进入区域选择）
var _lanzhonghou_pending: Array = []                # 待执行交换（确认后统一结算）：{a, slot_a, b, slot_b, ok}
# 测试钩子（正常游戏不设置）：
var _lanzhonghou_char_override: Callable = Callable()    # 返回 Array[Player] = [A, B]（两名角色）
var _lanzhonghou_zone_override: Callable = Callable()    # 返回 "weapon"/"armor"/"mount"/"done"/"cancel"（区域选择循环）
var _lanzhonghou_mount_override: Callable = Callable()   # 返回 {"a": 槽位, "b": 槽位} 或 "cancel"（坐骑槽选择）
var _lanzhonghou_hidden_first_override: Callable = Callable()  # 测试钩子：双暗置时返回 true 表示 A 先声明

# ---- 【烂忠厚】（麦克斯·欧尼斯特）：回合开始阶段摸一张牌并跳过自己的一个阶段 ----
var _is_meiyong_targeting: bool = false             # 选择目标中
var _meiyong_option: int = -1                       # 0=判定 / 1=摸牌 / 2=出牌
# 测试钩子（正常游戏不设置）：
var _meiyong_override: Callable = Callable()             # 返回 true = 发动【烂忠厚】
var _meiyong_option_override: Callable = Callable()      # 返回 0/1/2（三选一）
var _meiyong_target_override: Callable = Callable()      # 返回 Player（目标角色）

# 【烂忠厚】目标选择结果（返回 Player，null = 取消）
signal _meiyong_pick_result(target: Player)                       
signal _shensu_pick_result(target: Player)                       
# 【没用】区域选择结果（"weapon"/"armor"/"mount"/"done"/"cancel"）
signal _lanzhonghou_zone_result(zone: String)
# 【没用】坐骑槽选择结果（返回槽位，"cancel" = 取消）
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
var _hand_discard_override: Callable = Callable()

# 猜拳拼点（石头/剪刀/布）
const RPS_ROCK = 0
const RPS_PAPER = 1
const RPS_SCISSORS = 2
# 拼点结果（发起者视角）
const RPS_WIN = 1
const RPS_DRAW = 0
const RPS_LOSE = -1
const RPS_INVALID = -2 # 与石头0/布1/剪刀2及胜负1/0/-1均不同；只表示动作失效。

func _ready():
	# 主菜单选择的玩法与人数（当前入口：2/3 人乱斗、5 人标准身份局）。
	player_count = GameManager.selected_players
	game_mode = GameManager.selected_mode
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
	var is_current = (turn_manager.get_play_actor_idx() == player.seat_index)
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
	var assigned_generals: Array[String] = []
	if random_general:
		assigned_generals = GeneralData.draw_unique_random_generals(player_count)
		if assigned_generals.size() != player_count:
			_update_debug("可用武将不足，无法在不重复武将的条件下开始 %d 人局" % player_count)
			return
	_clear_pending_determined_card()
	# 身份分配：当前经典身份入口为五人标准；乱斗 2～10 人始终无身份。
	# random_identity = true 时身份牌洗牌随机分配（主公仍开局公开）
	var identities: Array = []
	if game_mode == MODE_CLASSIC_IDENTITY and player_count == 5:
		var full_identities = ["主公", "忠臣", "反贼", "反贼", "内奸"]
		identities = full_identities.duplicate()
		if random_identity:
			identities.shuffle()
	else:
		identities.resize(player_count)
		identities.fill("")

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
			p.general_name = assigned_generals[i]
		else:
			p.general_name = GameManager.selected_general if i == 0 else "稻草人"
		p.max_hp = GeneralData.get_max_hp(p.general_name, player_count)
		p.gender = GeneralData.get_gender(p.general_name)
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
			# 2 人乱斗：对方在正上方（玩家对面）；多人按四周布局
			var pos_node = _pos_top if player_count == 2 else _player_positions[i]
			var panel = _create_player_info_panel(pos_node, players[seat])
			_update_player_panel(panel, players[seat])
			_other_player_panels.append(panel)

	_sync_all_ui()
	_update_debug("—— 校园杀 %d 人局开始 ——" % player_count)
	for p in players:
		if GeneralData.get_implementation_status(p.general_name) == "metadata_only":
			_update_debug("%s 的武将【%s】技能尚未实装，仅按当前已实现的通用规则行动" % [p.player_name, p.general_name])
	if game_mode == MODE_CLASSIC_IDENTITY:
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
	# 当前效果已返回并请求推进时，最终死亡者不再获得摸牌/出牌/弃牌。
	# 不在伤害窗口中跳回合，以免吞掉当前判定/群体效果的后续结算。
	if new_phase in [TurnManager.Phase.DRAW, TurnManager.Phase.PLAY, TurnManager.Phase.DISCARD] \
			and players[pid].is_dead():
		turn_manager._change_phase(TurnManager.Phase.END)
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
	# 【烂忠厚】（麦克斯·欧尼斯特）：回合开始阶段可摸一张牌并选择跳过自己的一个阶段
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
			pl.consume_wine_bonus()

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
	# 【烂忠厚】（麦克斯·欧尼斯特）授予的判定阶段：跳过自己的判定，目标角色立刻进行判定阶段
	# （其乐不思蜀/兵粮寸断失效，闪电/火烧连营正常生效）
	if turn_manager.granted_judge_target_idx >= 0:
		var target = players[turn_manager.granted_judge_target_idx]
		turn_manager.granted_judge_target_idx = -1
		if target.is_alive():
			if not await _run_judgment(target, true):
				return
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

	if not await _run_judgment(p, false):
		return
	_sync_all_ui()
	turn_manager.advance_phase()

# 判定结算循环（抽取公用）：结算角色 p 判定区的全部延时锦囊（后放置的先判定）
# granted=true = 【烂忠厚】授予的判定阶段：乐不思蜀/兵粮寸断失效（不触发效果）；闪电/火烧连营正常生效
func _run_judgment(p: Player, granted: bool) -> bool:
	var revision = turn_manager.get_context_revision()
	if granted:
		_update_debug("%s 进行（授予的）判定阶段：判定区 %d 张牌（乐不思蜀/兵粮寸断失效）" % [p.player_name, p.judgment_cards.size()])
	else:
		_update_debug("%s 判定阶段：判定区 %d 张牌（后放置的先判定）" % [p.player_name, p.judgment_cards.size()])

	while not p.judgment_cards.is_empty() and p.is_alive():
		if _game_over or revision != turn_manager.get_context_revision():
			return false
		# 等待无懈期间原牌仍归判定区；失效不丢牌，也不恢复已被独立效果移走的牌。
		var card = p.judgment_cards.back()
		var nullified = NullificationOutcome.PASSED
		var needs_nullification = card.sub_type in [CardData.CardSubType.LIGHTNING, CardData.CardSubType.BURNING_CAMP] \
			or (not granted and card.sub_type in [CardData.CardSubType.INDULGENCE, CardData.CardSubType.SUPPLY_SHORTAGE])
		if needs_nullification:
			var valid = func(): return players.has(p) and p.is_alive() and not p.judgment_cards.is_empty() and p.judgment_cards.back() == card
			nullified = await _ask_nullification_chain_result("%s的【%s】即将生效，是否打出一张【无懈可击】？" % [p.player_name, card.card_name], valid)
			if nullified == NullificationOutcome.INVALIDATED:
				return false
		p.judgment_cards.pop_back()
		match card.sub_type:
			CardData.CardSubType.LIGHTNING:
				if nullified == NullificationOutcome.NULLIFIED:
					_update_debug("【闪电】的效果被【无懈可击】抵消")
				else:
					_update_debug("【闪电】判定：必定命中！即将对 %s 造成 3 点雷电伤害" % p.player_name)
					# 规则（朋友设定）：闪电造成的属性伤害无伤害来源（铁索传导随之为无来源）
					await _deal_damage(null, p, 3, EffectChain.DamageType.THUNDER)
			CardData.CardSubType.INDULGENCE:
				if granted:
					# 【烂忠厚】授予的判定阶段：乐不思蜀失效（不触发效果）
					_update_debug("【乐不思蜀】在授予的判定阶段失效，不触发效果")
				else:
					if nullified == NullificationOutcome.NULLIFIED:
						_update_debug("【乐不思蜀】的效果被【无懈可击】抵消")
					else:
						_update_debug("【乐不思蜀】判定：必定生效！%s 本回合跳过出牌阶段" % p.player_name)
						turn_manager.skip_play_phase = true
			CardData.CardSubType.SUPPLY_SHORTAGE:
				if granted:
					# 【烂忠厚】授予的判定阶段：兵粮寸断失效（不触发效果）
					_update_debug("【兵粮寸断】在授予的判定阶段失效，不触发效果")
				else:
					if nullified == NullificationOutcome.NULLIFIED:
						_update_debug("【兵粮寸断】的效果被【无懈可击】抵消")
					else:
						_update_debug("【兵粮寸断】判定：必定生效！%s 本回合摸牌阶段少摸一张" % p.player_name)
						turn_manager.supply_shortage_active = true
			CardData.CardSubType.BURNING_CAMP:
				if nullified == NullificationOutcome.NULLIFIED:
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
	return not _game_over and revision == turn_manager.get_context_revision()

func _do_draw(pid: int):
	var p = players[pid]
	# 【烂忠厚】（麦克斯·欧尼斯特）授予的摸牌阶段：跳过自己的摸牌，目标角色立刻获得一个摸牌阶段
	if turn_manager.granted_draw_target_idx >= 0:
		var target = players[turn_manager.granted_draw_target_idx]
		turn_manager.granted_draw_target_idx = -1
		if target.is_alive():
			_draw_blank_cards(target, 2)
			_update_debug("【烂忠厚】：%s 立刻获得一个摸牌阶段，摸了 2 张牌（手牌 %d 张）" % [target.player_name, target.hand_size()])
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
	# 【烂忠厚】（麦克斯·欧尼斯特）授予的出牌阶段：跳过自己的出牌，目标角色立刻获得一个出牌阶段
	if turn_manager.granted_play_target_idx >= 0:
		var target = players[turn_manager.granted_play_target_idx]
		turn_manager.granted_play_target_idx = -1
		turn_manager.skip_play_phase = false  # 自己已不出牌，乐不思蜀的跳过效果无意义（已判定消耗）
		if not target.is_alive():
			turn_manager.advance_phase()
			return
		turn_manager.play_actor_idx = target.seat_index
		p = target
		pid = target.seat_index
		_update_debug("【烂忠厚】：%s 立刻获得一个出牌阶段" % target.player_name)
	elif turn_manager.play_actor_idx >= 0:
		# 获赠阶段从响应返回时，授予索引已消费，仍恢复实际操作者。
		pid = turn_manager.get_play_actor_idx()
		p = players[pid]
	_play_btn.visible = (pid == 0)
	_end_play_btn.visible = (pid == 0)
	_sync_all_ui()
	_refresh_status_line()
	_update_debug("%s 出牌阶段 — 点击「出牌」选择牌型，或「结束出牌」" % p.player_name)
	if pid != 0:
		await _run_ai_play(p)

func _ai_observation(actor: Player) -> Dictionary:
	var view = PlayerObservation.capture(players, actor, turn_manager.current_phase,
		turn_manager.get_context_revision())
	view["mode"] = game_mode
	return view

# 决策只接收白名单值快照；合法选项是牌型，-1表示自愿放弃。
func _choose_ai_response(p: Player, kind: String, options: Array, context: Dictionary = {}) -> int:
	if options.is_empty():
		return -1
	var view = _ai_observation(p)
	view["response"] = context.duplicate(true)
	var selected = await _ai_response_override.call(view, kind, options.duplicate()) if _ai_response_override.is_valid() else ResponsePolicy.choose(view, kind, options)
	return selected if options.has(selected) else -1

# 规则查询同时供普通出牌和AI使用；策略不会另造次数、距离或支付规则。
func can_declare_basic(p: Player, sub: int) -> bool:
	if _game_over or not p.is_alive() or _is_kneeling(p) or not turn_manager.can_play_card() or not _has_play_card(p, sub):
		return false
	match sub:
		CardData.CardSubType.PEACH:
			return p.hp < p.max_hp
		CardData.CardSubType.WINE:
			return turn_manager.can_play_wine(p.get_weapon() == CardData.CardSubType.RAGING_AXE, p.seat_index)
		CardData.CardSubType.STRIKE, CardData.CardSubType.FIRE_STRIKE, CardData.CardSubType.THUNDER_STRIKE:
			return turn_manager.can_play_strike(p.strike_limit()) and not _get_strike_targets(p).is_empty()
	return false

const TARGET_TRICKS = [CardData.CardSubType.DUEL, CardData.CardSubType.SNATCH, CardData.CardSubType.DISMANTLE,
	CardData.CardSubType.INDULGENCE, CardData.CardSubType.SUPPLY_SHORTAGE, CardData.CardSubType.BURNING_CAMP,
	CardData.CardSubType.IRON_CHAIN]
const GLOBAL_TRICKS = [CardData.CardSubType.BARBARIAN_INVASION, CardData.CardSubType.VOLLEY_OF_ARROWS,
	CardData.CardSubType.PEACH_GARDEN, CardData.CardSubType.HARVEST, CardData.CardSubType.DISARM]

func get_trick_targets(p: Player, sub: int) -> Array[Player]:
	var result: Array[Player] = []
	for target in players:
		if not target.is_alive() or _is_kneeling(target) or (target == p and sub != CardData.CardSubType.IRON_CHAIN):
			continue
		if sub in [CardData.CardSubType.SNATCH, CardData.CardSubType.DISMANTLE] and not target.has_any_card():
			continue
		if sub in [CardData.CardSubType.SNATCH, CardData.CardSubType.SUPPLY_SHORTAGE, CardData.CardSubType.BURNING_CAMP] and p.attack_distance_to(target) > 1:
			continue
		if sub == CardData.CardSubType.DUEL and (not _get_duel_targets(p).has(target)
				or target.get_armor() == CardData.CardSubType.ZHANQI or _awake_blocks(target, 2)):
			continue
		result.append(target)
	return result

func can_declare_trick(p: Player, sub: int, virtual_payment: bool = false) -> bool:
	if _game_over or not p.is_alive() or _is_kneeling(p) or not turn_manager.can_play_card() or (not virtual_payment and not _has_play_card(p, sub)):
		return false
	if sub in TARGET_TRICKS and get_trick_targets(p, sub).is_empty():
		return false
	match sub:
		CardData.CardSubType.DUEL:
			return turn_manager.can_use("duel", 3 if p.general_name == "杰基·斯特朗" else 2)
		CardData.CardSubType.SNATCH, CardData.CardSubType.DISMANTLE:
			return turn_manager.can_use("steal")
		CardData.CardSubType.BARBARIAN_INVASION, CardData.CardSubType.VOLLEY_OF_ARROWS:
			return turn_manager.can_use("aoe")
		CardData.CardSubType.PEACH_GARDEN:
			return turn_manager.can_use("peach_garden")
		CardData.CardSubType.HARVEST:
			return turn_manager.can_use("harvest")
		CardData.CardSubType.DISARM:
			return turn_manager.can_use("disarm")
	return sub in TARGET_TRICKS

func _ai_play_candidates(observation: Dictionary) -> Array:
	_ai_offered_actions.clear()
	var seat = int(observation.actor)
	if seat < 0 or seat >= players.size() or seat != turn_manager.get_play_actor_idx() \
			or observation.revision != turn_manager.get_context_revision():
		return []
	var p = players[seat]
	_ai_hand_snapshot = HandSelection.new(p)
	if _game_over or not p.is_alive() or _is_kneeling(p) or not turn_manager.can_play_card():
		return []
	var choices: Array = []
	for sub in [CardData.CardSubType.PEACH, CardData.CardSubType.WINE,
			CardData.CardSubType.STRIKE, CardData.CardSubType.FIRE_STRIKE, CardData.CardSubType.THUNDER_STRIKE]:
		if not can_declare_basic(p, sub):
			continue
		if sub == CardData.CardSubType.PEACH:
			choices.append({"sub": sub, "target": -1, "priority": 100})
		elif sub == CardData.CardSubType.WINE:
			# 保守意愿：有余牌且本阶段还能出杀时才喝一层，规则仍允许战斧继续叠酒。
			if p.hand_size() >= 2 and p.wine_stacks == 0 and turn_manager.can_play_strike(p.strike_limit()) and not _get_strike_targets(p).is_empty():
				choices.append({"sub": sub, "target": -1, "priority": 110})
		else:
			for target in _get_strike_targets(p):
				choices.append({"sub": sub, "target": target.seat_index, "priority": 120 if p.wine_stacks > 0 else 80})
	for sub in TARGET_TRICKS + GLOBAL_TRICKS:
		if not can_declare_trick(p, sub):
			continue
		if sub in TARGET_TRICKS:
			for target in get_trick_targets(p, sub):
				# 延时同名已有时策略不重复放置；铁索保守只连未连环的其他角色。
				if sub == CardData.CardSubType.IRON_CHAIN and (target == p or target.chained):
					continue
				var duplicate = false
				for judgment in target.judgment_cards:
					if judgment.sub_type == sub:
						duplicate = true
				if not duplicate:
					choices.append({"sub": sub, "target": target.seat_index, "priority": 60})
		else:
			var useful = false
			for target in players:
				if not target.is_alive() or _is_kneeling(target):
					continue
				if sub in [CardData.CardSubType.PEACH_GARDEN, CardData.CardSubType.HARVEST]:
					useful = useful or target.hp < target.max_hp
				elif sub == CardData.CardSubType.DISARM:
					useful = useful or not target.equipment.is_empty()
				else:
					useful = useful or target != p
			if useful:
				choices.append({"sub": sub, "target": -1, "priority": 60})
	# 本批普通装备策略只填空槽；不反复替换装备/满槽坐骑消耗任意牌。
	for sub in CardSelector.EQUIP_WEAPON + CardSelector.EQUIP_ARMOR + CardSelector.EQUIP_MOUNT:
		if not _has_play_card(p, sub):
			continue
		var slot = "weapon" if CardSelector.EQUIP_WEAPON.has(sub) else "armor"
		if CardSelector.EQUIP_MOUNT.has(sub):
			if not p.has_free_mount_slot():
				continue
		elif p.equipment.has(slot) or not _can_play_equipment_instance(p, sub):
			continue
		choices.append({"sub": sub, "target": -1, "priority": 40})
	for action in choices:
		action["actor"] = seat
		action["revision"] = observation.revision
		action["phase"] = TurnManager.Phase.PLAY
		_ai_offered_actions.append(action)
	return _ai_offered_actions.duplicate(true)

func _execute_ai_action(action: Dictionary):
	if not _ai_offered_actions.has(action) or _ai_hand_snapshot == null:
		return
	var p = _ai_hand_snapshot.owner
	if _game_over or not p.is_alive() or not turn_manager.can_play_card() \
			or action.actor != turn_manager.get_play_actor_idx() or action.revision != turn_manager.get_context_revision() \
			or p.hand != _ai_hand_snapshot.hand or p.determined_cards != _ai_hand_snapshot.determined:
		return
	var sub = int(action.sub)
	if action.target >= 0:
		var target = players[action.target]
		if sub in TARGET_TRICKS:
			if not can_declare_trick(p, sub) or not get_trick_targets(p, sub).has(target):
				return
			if sub == CardData.CardSubType.IRON_CHAIN:
				await _execute_iron_chain([target])
			else:
				await execute_card_on_target(target, sub)
		elif can_declare_basic(p, sub) and _get_strike_targets(p).has(target):
			await execute_card_on_target(target, sub)
	else:
		await play_card(sub)

func _run_ai_play(actor: Player):
	var revision = turn_manager.get_context_revision()
	if _ai_running_revisions.has(revision):
		return
	_ai_running_revisions[revision] = true
	var valid = func():
		return not _game_over and actor.is_alive() and turn_manager.current_phase == TurnManager.Phase.PLAY \
			and turn_manager.get_play_actor_idx() == actor.seat_index \
			and turn_manager.get_context_revision() == revision
	# 让阶段调用栈返回；连续AI回合不会同步递归推进。
	await get_tree().process_frame
	var result = await ai_driver.run(func(): return _ai_observation(actor),
		_ai_play_candidates, _execute_ai_action, valid)
	_ai_running_revisions.erase(revision)
	if not _game_over and actor.is_dead() and turn_manager.get_context_revision() == revision \
			and turn_manager.current_phase == TurnManager.Phase.PLAY and turn_manager.get_play_actor_idx() == actor.seat_index:
		turn_manager.advance_phase()
		return
	if result.reason != "stale" and valid.call():
		_update_debug("%s 结束出牌阶段" % actor.player_name)
		turn_manager.advance_phase()

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
			# 牌区在等待中变化则重新选，不擅自改扣另一张，也不能跳过强制弃牌。
			while not _game_over and p.is_alive() and p.hand_size() > 0:
				if await _select_hand_discard(p, 1, true):
					break
		_sync_all_ui()
	if _game_over:
		return
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

# 固定座号的存活圆桌；濒死待救者仍占座位。
func ordinary_seat_distance(source: Player, target: Player) -> int:
	return LivingTable.distance(players, source, target)

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
	_card_target_generation += 1
	_is_targeting = true
	_targeting_card_sub = sub

	# 隐藏常规按钮，显示取消按钮
	_play_btn.visible = false
	_end_play_btn.visible = false
	_cancel_target_btn.visible = true

	_update_debug("请点击一名玩家头像，选择【%s】的目标（或点击「取消选择」）" % CardData.get_type_name(sub))

func _exit_targeting_mode():
	_card_target_generation += 1
	_is_targeting = false
	_targeting_card_sub = -1
	_cancel_target_btn.visible = false
	_play_btn.visible = true
	_end_play_btn.visible = true
	_update_debug("取消目标选择")

# 取消按钮统一处理（普通目标模式 / 铁索连环模式 / 方天画戟多目标模式）
func _on_cancel_target_pressed():
	_card_target_generation += 1
	# 【是~啊~】：取消目标选择则本张锦囊视为未发动（未流失体力、不消耗手牌）
	_yes_ah_active = false
	_clear_pending_determined_card()
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
		_update_debug("取消【没用】")
		return
	if _is_meiyong_targeting:
		_is_meiyong_targeting = false
		_cancel_target_btn.visible = false
		_meiyong_pick_result.emit(null)
		_update_debug("取消【烂忠厚】")
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
	var attacker = players[turn_manager.get_play_actor_idx()]

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
	_clear_pending_determined_card()

# ============================
#  【贤者的加护】激活拼点（入口：详情弹窗装备区点击）
# ============================

# 从详情弹窗发动：检查条件后进入拼点目标选择模式
func _on_detail_equip_clicked(sub: CardData.CardSubType, owner_player: Player):
	if sub != CardData.CardSubType.SAGE_PROTECTION:
		return
	var p = players[turn_manager.get_play_actor_idx()]
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
	var p = players[turn_manager.get_play_actor_idx()]
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
	var original = wearer.get_equipment_card("armor")
	var revision = turn_manager.get_context_revision()
	var valid = func():
		return not _game_over and revision == turn_manager.get_context_revision() \
			and wearer.is_alive() and target != wearer and target.is_alive() \
			and wearer.get_equipment_card("armor") == original \
			and wearer.get_armor() == CardData.CardSubType.SAGE_PROTECTION and not wearer.sage_activated
	if not await _select_hand_discard(wearer, 1, false, valid):
		return false
	_update_debug("%s 弃置一张手牌，与 %s 进行拼点（【贤者的加护】）" % [wearer.player_name, target.player_name])
	var r = await _do_ping_dian(wearer, target, valid)
	if r == RPS_INVALID or not valid.call():
		return false
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

func _has_play_card(p: Player, sub: CardData.CardSubType) -> bool:
	if _pending_determined_card != null:
		return _pending_determined_card.sub_type == sub and p.determined_cards.has(_pending_determined_card)
	return HandPayment.has_card(p, sub)

# 统一主动出牌支付：普通声明仍从 hand 取同类型/任意牌；点击已确定牌时只接受并移除该原对象。
func _take_play_card(p: Player, sub: CardData.CardSubType) -> CardBase:
	if _pending_determined_card == null:
		return HandPayment.take_card(p, sub)
	var selected := _pending_determined_card
	if selected.sub_type != sub or not p.determined_cards.has(selected):
		return null
	p.determined_cards.erase(selected)
	_pending_determined_card = null
	return selected

# 武器/防具替换的防御性回装凭据；任意牌失败后必须仍是任意牌。
func _equipment_payment_receipt(p: Player, sub: CardData.CardSubType) -> Dictionary:
	if _pending_determined_card != null:
		var index = p.determined_cards.find(_pending_determined_card)
		if index < 0 or _pending_determined_card.sub_type != sub:
			return {}
		return {"zone": p.determined_cards, "index": index, "blank": false, "pending": _pending_determined_card}
	var selected = HandPayment._find_player_card(p, sub, false)
	if selected.is_empty():
		return {}
	var zone: Array[CardBase] = selected.cards
	return {"zone": zone, "index": selected.index, "blank": zone[selected.index] == null, "pending": null}

# EQ-04：名称占用不妨碍未弃置的同一原牌再装备；任意牌或另一具体牌不能新造同名。
func _can_play_equipment_instance(p: Player, sub: CardData.CardSubType) -> bool:
	if not equipment_pool.is_claimed(sub):
		return true
	var receipt = _equipment_payment_receipt(p, sub)
	if receipt.is_empty() or receipt.blank:
		return false
	var zone: Array[CardBase] = receipt.zone
	var card: CardBase = zone[receipt.index]
	return equipment_pool.is_claimed_original(sub, card) and not deck._discard.has(card)

func _restore_equipment_payment(receipt: Dictionary, card: CardBase):
	var zone: Array[CardBase] = receipt.zone
	zone.insert(mini(receipt.index, zone.size()), null if receipt.blank else card)
	if receipt.pending != null:
		_pending_determined_card = receipt.pending

# 确认窗口返回后才检查原装备与行动，再取手牌；落位成功后才弃旧牌并登记新名。
func _replace_play_equipment_if_current(p: Player, slot: String, sub: CardData.CardSubType,
		old_sub: CardData.CardSubType, old_card: CardBase, context_revision: int) -> bool:
	if _game_over or not p.is_alive() or not turn_manager.can_play_card() \
			or turn_manager.get_play_actor_idx() != p.seat_index \
			or turn_manager.get_context_revision() != context_revision \
			or p.equipment.get(slot, -1) != old_sub or p.get_equipment_card(slot) != old_card \
			or not _can_play_equipment_instance(p, sub):
		return false
	var receipt = _equipment_payment_receipt(p, sub)
	if receipt.is_empty():
		return false
	var incoming = _take_play_card(p, sub)
	if incoming == null:
		return false
	var removed = p.remove_equipment(slot)
	if not p.equip_card_to_slot(slot, incoming):
		if old_sub == CardData.CardSubType.HIDDEN_EQUIPMENT:
			if removed != null:
				p.equip_hidden_card_to_slot(slot, removed)
			else:
				p.equipment[slot] = old_sub
		elif removed != null:
			p.equip_card_to_slot(slot, removed)
		_restore_equipment_payment(receipt, incoming)
		return false
	if removed != null:
		deck.discard(removed)
	_record_card_action(p, incoming)
	_claim_equipment_name(sub, incoming)
	return true

func _clear_pending_determined_card():
	_pending_determined_card = null

# 仅在具体规则入口确认使用/打出后调用，不能放进通用取牌/弃牌函数。
func _record_card_action(p: Player, card: CardBase, kind: CardActionEvent.Kind = CardActionEvent.Kind.USE,
		from_hand: bool = true, is_virtual: bool = false) -> CardActionEvent:
	_card_action_serial += 1
	var event = CardActionEvent.new(_card_action_serial, turn_manager, p, card, kind, from_hand, is_virtual)
	card_action_committed.emit(event)
	return event

func execute_card_on_target(target: Player, sub: CardData.CardSubType):
	var p = players[turn_manager.get_play_actor_idx()]
	var action_revision = turn_manager.get_context_revision()
	if sub in TARGET_TRICKS and (not can_declare_trick(p, sub, _yes_ah_active) or not get_trick_targets(p, sub).has(target)):
		return
	# 选完目标开始执行：玩家0出牌阶段重置每步倒计时
	_reset_play_countdown_if_p0()
	var card = CardBase.create(sub)

	match sub:
		CardData.CardSubType.STRIKE, CardData.CardSubType.FIRE_STRIKE, CardData.CardSubType.THUNDER_STRIKE:
			card = _take_play_card(p, sub)
			if card == null:
				_update_debug("没有可用的【%s】或任意牌，未使用杀" % CardData.get_type_name(sub))
				return
			turn_manager.use_strike()
			var base_damage = 1
			var wine_stacks = p.consume_wine_bonus()
			base_damage += wine_stacks
			# 【暴怒】锁定技（布鲁斯·萨维奇）：杀额外造成已损失体力值的伤害
			base_damage += _rage_bonus(p)
			# 已在计数、酒和青龙效果前支付物理手牌，保留原实例。
			deck.discard(card)
			_record_card_action(p, card)
			_record_strike_played(p)
			_sync_all_ui()

			var element = EffectChain.DamageType.PHYSICAL
			match sub:
				CardData.CardSubType.FIRE_STRIKE:
					element = EffectChain.DamageType.FIRE
				CardData.CardSubType.THUNDER_STRIKE:
					element = EffectChain.DamageType.THUNDER

			var dealt = await _execute_single_strike(p, target, card, sub, element, base_damage)
			if dealt is int and dealt == CHOICE_INVALID:
				return

			# 【灾厄剑】转移：本次杀的全部伤害处理完成后，可选择将灾厄剑移至其他角色
			if dealt:
				if _game_over or action_revision != turn_manager.get_context_revision():
					return
				if await _try_calamity_transfer(p) == CHOICE_INVALID:
					return

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
			var virtual_use = _yes_ah_active
			card = await _take_trick_card(p, sub)
			if card == null:
				return
			card.source_seat = p.seat_index
			target.judgment_cards.append(card)
			_record_card_action(p, card, CardActionEvent.Kind.USE, not virtual_use, virtual_use)
			_update_debug("%s 对 %s 使用了【%s】，已置入其判定区（下回合判定）" % [p.player_name, target.player_name, CardData.get_type_name(sub)])
			_sync_all_ui()


	_sync_all_ui()

# 单个目标的杀结算（防具 → 雌雄 → 响应 → 伤害）：单目标杀与【方天画戟】多目标杀共用
# 杀次数/手牌/酒 buff 已在调用方消耗
# 返回 true = 本次结算对目标造成了伤害（供【灾厄剑】转移判定：全部处理完成后再转移）
# 已提交伤害后的选择失效须通知多目标调用者；普通命中/闪仍为bool。
func _execute_single_strike(p: Player, target: Player, card: CardBase, sub: CardData.CardSubType, element: EffectChain.DamageType, base_damage: int, ignore_target_restrictions: bool = false) -> Variant:
	if target == null or not target.is_alive():
		return false
	# “无论是否合法”只越过选目标限制，不跳过响应和伤害防止。
	if not ignore_target_restrictions and (target.get_armor() == CardData.CardSubType.TENGJIA \
			or _awake_blocks(target, 1) or _is_bare_running(target) or _is_kneeling(target)):
		return false
	var chain = _new_damage_chain(p, target, card, base_damage, element)
	chain.ignore_target_restrictions = ignore_target_restrictions
	chain.response_callback = _on_chain_response_check
	var strike_revision = turn_manager.get_context_revision()
	var result = await chain.start()
	if result == EffectChain.ResponseResult.DODGED:
		var actual = chain.target_player
		_update_debug("%s → %s 被【闪】避" % [p.player_name, actual.player_name])
		if p.is_alive() and actual.is_alive() and p.get_weapon() == CardData.CardSubType.GUANSHI_AXE \
				and p.mount_count() > 0 and actual.get_armor() != CardData.CardSubType.QINGGANG_SHIELD:
			var original_weapon = p.get_equipment_card("weapon")
			var choice_valid = func():
				return not _game_over and strike_revision == turn_manager.get_context_revision() \
					and players.has(p) and p.is_alive() and players.has(actual) and actual.is_alive() \
					and chain.target_player == actual and p.get_weapon() == CardData.CardSubType.GUANSHI_AXE \
					and p.get_equipment_card("weapon") == original_weapon and p.mount_count() > 0 \
					and actual.get_armor() != CardData.CardSubType.QINGGANG_SHIELD
			if not choice_valid.call():
				return false
			var activate = 1 if p.seat_index != 0 else await _ask_guanshi(actual.player_name, choice_valid)
			# 原杀已被闪抵消；贯石未有效发动时没有可继续的余伤。
			if activate == CHOICE_INVALID or not choice_valid.call():
				return false
			if activate == 1:
				var slots = p.get_mount_slots()
				var originals: Dictionary = {}
				for candidate in slots:
					originals[candidate] = _guanshi_mount_card(p, candidate)
				var slot: String = await _show_mount_discard_picker(p, choice_valid) if p.seat_index == 0 else slots.pick_random()
				if not choice_valid.call() or not originals.has(slot) or originals[slot] == null \
						or _guanshi_mount_card(p, slot) != originals[slot]:
					return false
				var discarded_mount = p.remove_equipment(slot)
				if discarded_mount != null:
					deck.discard(discarded_mount)
				_update_debug("%s 发动【贯石斧】：此【杀】依然造成伤害" % p.player_name)
				var hit = _new_damage_chain(p, actual, card, base_damage, element)
				hit.damage.original_target = chain.damage.original_target
				hit.skip_response = true
				hit.skip_targeting = true # 同一张杀不重复目标/出闪，伤害窗口仍允许舍己。
				await hit.start()
				await _finish_damage_chain(hit)
				if hit.continuation_invalid:
					return CHOICE_INVALID
				return hit.damage.final_damage().committed
		return false
	await _finish_damage_chain(chain)
	if chain.continuation_invalid:
		return CHOICE_INVALID
	return chain.damage.final_damage().committed

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
		var ice_sword = p.remove_equipment("weapon")
		var fire_shield = target.remove_equipment("armor")
		if ice_sword != null:
			deck.discard(ice_sword)
		if fire_shield != null:
			deck.discard(fire_shield)
		_update_debug("%s 的【寒冰剑】与 %s 的【烈火盾】相撞，双双进入弃牌堆！" % [p.player_name, target.player_name])
		_sync_all_ui()

	# 【青釭盾】vs【青釭剑】：装备青釭剑者杀装备青釭盾者 → 双方分别弃置这两张装备，再进行之后的结算
	if p.get_weapon() == CardData.CardSubType.QINGGANG_SWORD and target.get_armor() == CardData.CardSubType.QINGGANG_SHIELD:
		var qinggang_sword = p.remove_equipment("weapon")
		var qinggang_shield = target.remove_equipment("armor")
		if qinggang_sword != null:
			deck.discard(qinggang_sword)
		if qinggang_shield != null:
			deck.discard(qinggang_shield)
		_update_debug("%s 的【青釭剑】与 %s 的【青釭盾】相撞，双双进入弃牌堆！" % [p.player_name, target.player_name])
		_sync_all_ui()

	# 雌雄双股剑：使用【杀】指定异性目标后，可令其选择：弃一张手牌 / 令你摸一张牌
	# 时机在目标响应（出闪）之前，先于伤害结算（与方天画戟互斥武器，正常不会同时触发）
	if target.is_alive() and p.get_weapon() == CardData.CardSubType.CHIXIONG_SHUANGGU and target.gender != p.gender \
			and target.get_armor() != CardData.CardSubType.QINGGANG_SHIELD:
		var original_weapon = p.get_equipment_card("weapon")
		var revision = turn_manager.get_context_revision()
		var hit_valid = func():
			return not _game_over and revision == turn_manager.get_context_revision() \
				and players.has(target) and target.is_alive()
		var choice_valid = func():
			return hit_valid.call() and players.has(p) and p.is_alive() \
				and p.get_weapon() == CardData.CardSubType.CHIXIONG_SHUANGGU \
				and p.get_equipment_card("weapon") == original_weapon and p.gender != target.gender \
				and target.get_armor() != CardData.CardSubType.QINGGANG_SHIELD
		var activate = 1
		if p.seat_index == 0:
			activate = await _ask_chixiong_activate(target.player_name, choice_valid)
		if not hit_valid.call():
			return false
		if p.is_dead():
			return true # TIME-04：已用杀余伤继续无源，不继续雌雄选择。
		if activate == CHOICE_INVALID or not choice_valid.call():
			return false
		if activate == 1:
			var resolved = await _resolve_chixiong(p, target, choice_valid)
			if not hit_valid.call():
				return false
			if p.is_dead():
				return true # TIME-04：目标选择期间来源死亡，不吞掉剩余无源伤害。
			if not resolved or not choice_valid.call():
				return false

	return true

# 【方天画戟】多目标杀：一次打出、逐目标结算。

func execute_multi_strike(targets: Array[Player], sub: CardData.CardSubType):
	var action_revision = turn_manager.get_context_revision()
	if targets.is_empty():
		return
	# 方天画戟多目标：选完目标确认出牌后重置每步倒计时
	_reset_play_countdown_if_p0()
	var p = players[turn_manager.get_play_actor_idx()]
	var card = _take_play_card(p, sub)
	if card == null:
		_update_debug("没有可用的【%s】或任意牌，未使用多目标杀" % CardData.get_type_name(sub))
		return

	turn_manager.use_strike()
	var base_damage = 1
	var wine_stacks = p.consume_wine_bonus()
	base_damage += wine_stacks
	# 【暴怒】锁定技（布鲁斯·萨维奇）：杀额外造成已损失体力值的伤害
	base_damage += _rage_bonus(p)
	deck.discard(card)
	_record_card_action(p, card)
	_record_strike_played(p)
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
		var dealt = await _execute_single_strike(p, target, card, sub, element, base_damage)
		if dealt is int and dealt == CHOICE_INVALID:
			return
		if dealt:
			dealt_any = true

	# 【灾厄剑】转移：全部目标的伤害都处理完成后，再选择是否转移（双武器假想下语义正确）
	if dealt_any:
		if _game_over or action_revision != turn_manager.get_context_revision():
			return
		if await _try_calamity_transfer(p) == CHOICE_INVALID:
			return

	_sync_all_ui()

# 杀、普通伤害与传导共用同一条伤害链。
func _new_damage_chain(source: Player, target: Player, card: CardBase, amount: int, element: EffectChain.DamageType) -> EffectChain:
	var chain = EffectChain.new(source, target, card, EffectChain.EffectType.DAMAGE, amount)
	chain.damage_element = element
	chain.scheduler = rule_scheduler
	chain.trigger_callback = _on_chain_trigger
	chain.completion_callback = _resolve_transferred_damage
	return chain

# TIME-02/C04-Q1：原记录先结束，继承来源/渠道/属性和数值，来源修正不重放。
func _resolve_transferred_damage(original: EffectChain) -> void:
	var record = original.damage
	if record.transfer_target == null or _game_over or record.transfer_target.is_dead():
		return
	record.refresh_source()
	var next = _new_damage_chain(record.source, record.transfer_target, record.card,
		record.transfer_amount, record.element)
	next.skip_targeting = true
	next.skip_response = true
	next.damage.from_strike = record.from_strike
	next.damage.is_chain = record.is_chain
	next.damage.source_modifiers_applied = true
	record.transferred_damage = next.damage
	record.events.append("damage_transferred")
	await next.start()
	await _finish_damage_chain(next)
	if next.continuation_invalid:
		original.continuation_invalid = true

# 伤害提交及濒死/死亡已经完成；此处不再补扣体力或重新套用武器修正。
func _finish_damage_chain(chain: EffectChain):
	if _game_over or chain.continuation_invalid or not chain.damage.committed:
		return
	var revision = turn_manager.get_context_revision()
	var actual = chain.target_player
	var source = chain.source_player
	if not chain.damage.is_chain and actual.chained and chain.damage_element != EffectChain.DamageType.PHYSICAL:
		if await _resolve_chain_propagation(source, actual, chain.effect_value, chain.damage_element, chain.damage.from_strike) == CHOICE_INVALID:
			chain.continuation_invalid = true
	if _game_over or chain.continuation_invalid or revision != turn_manager.get_context_revision():
		chain.continuation_invalid = true
		return
	if await _try_calamity_robe_transfer(actual) == CHOICE_INVALID:
		chain.continuation_invalid = true
		return
	if await _try_minus_mule_transfer(actual) == CHOICE_INVALID:
		chain.continuation_invalid = true
		return
	if await _try_plus_mule_transfer(actual) == CHOICE_INVALID:
		chain.continuation_invalid = true
		return
	_sync_all_ui()

func play_card(sub: CardData.CardSubType):
	var p = players[turn_manager.get_play_actor_idx()]

	# 【下跪】：无法使用或打出任何牌
	if _is_kneeling(p):
		_update_debug("%s 处于【下跪】状态，无法使用或打出任何牌（可点击头像→技能解除）" % p.player_name)
		return

	if not turn_manager.can_play_card():
		_update_debug("当前不能出牌")
		return
	if p.hand_size() <= 0 and p.determined_cards.is_empty() and _pending_determined_card == null:
		_update_debug("没有手牌了")
		return
	if _pending_determined_card != null and not _has_play_card(p, sub):
		_update_debug("所选的【%s】已不在已确定牌区，未使用其他手牌代替" % CardData.get_type_name(sub))
		return
	if sub in [CardData.CardSubType.PEACH, CardData.CardSubType.WINE, CardData.CardSubType.STRIKE,
			CardData.CardSubType.FIRE_STRIKE, CardData.CardSubType.THUNDER_STRIKE] and not can_declare_basic(p, sub):
		_update_debug("当前不能使用【%s】：检查牌源、次数、体力及合法目标" % CardData.get_type_name(sub))
		return
	if (sub in TARGET_TRICKS or sub in GLOBAL_TRICKS) and not can_declare_trick(p, sub, p.general_name == "安普提·斯丢皮得"):
		_update_debug("当前不能使用【%s】：检查牌源、次数与合法目标" % CardData.get_type_name(sub))
		return
	# 每张牌从干净状态开始（【是~啊~】激活标记：选锦囊时设置，消耗锦囊时消费；取消/中止路径由下次出牌重置）
	_yes_ah_active = false

	match sub:
		CardData.CardSubType.STRIKE, CardData.CardSubType.FIRE_STRIKE, CardData.CardSubType.THUNDER_STRIKE:
			if not _has_play_card(p, sub):
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
			if not turn_manager.can_play_wine(p.get_weapon() == CardData.CardSubType.RAGING_AXE, p.seat_index):
				_update_debug("本回合已使用过【酒】")
				return
			var used_wine = _take_play_card(p, sub)
			if used_wine == null:
				_update_debug("没有可用的【酒】或任意牌")
				return
			turn_manager.use_card("wine")
			_record_card_action(p, used_wine)
			p.wine_stacks += 1
			if p.get_weapon() == CardData.CardSubType.RAGING_AXE:
				p.raging_wine_stacks += 1
			deck.discard(used_wine)
			_update_debug("%s 使用了【酒】（当前 %d 层，下一张【杀】伤害+%d）" % [p.player_name, p.wine_stacks, p.wine_stacks])
			_sync_all_ui()
			_reset_play_countdown_if_p0()

		CardData.CardSubType.PEACH:
			if p.hp >= p.max_hp:
				_update_debug("体力已满")
				return
			var used_peach = _take_play_card(p, sub)
			if used_peach == null:
				_update_debug("没有可用的【桃】或任意牌")
				return
			_record_card_action(p, used_peach)
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
			var virtual_use = _yes_ah_active
			var card = await _take_trick_card(p, sub)
			if card == null:
				return
			card.source_seat = p.seat_index
			p.judgment_cards.append(card)
			_record_card_action(p, card, CardActionEvent.Kind.USE, not virtual_use, virtual_use)
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
			if not _can_play_equipment_instance(p, sub):
				_update_debug("【%s】名称已占用；只能再装备未弃置的同一原牌" % CardData.get_type_name(sub))
				return
			# 【苕】抢先明置（安普提·斯丢皮得）：暗置同类型装备时，可明置为该装备阻止本次装备
			if not equipment_pool.is_claimed(sub):
				if await _try_sao_preempt(p, sub, "weapon"):
					return
			if not _can_play_equipment_instance(p, sub):
				return
			if p.equipment.has("weapon"):
				var old_weapon = p.equipment["weapon"]
				if old_weapon == sub:
					_update_debug("你已经装备了【%s】" % CardData.get_type_name(sub))
					return
				var old_weapon_card = p.get_equipment_card("weapon")
				var weapon_context = turn_manager.get_context_revision()
				var old_is_hidden = old_weapon == CardData.CardSubType.HIDDEN_EQUIPMENT
				# 已有武器：替换确认（玩家0交互 / AI 直接替换；暗置占位直接替换无需确认）
				if p.seat_index == 0 and not old_is_hidden:
					var valid = func():
						return _can_use_play_skill(p) and weapon_context == turn_manager.get_context_revision() \
							and p.get_equipment_card("weapon") == old_weapon_card and p.get_weapon() == old_weapon
					var ok = await _show_weapon_replace_confirm(old_weapon, sub, valid)
					if ok != 1:
						_update_debug("替换武器确认已失效，手牌未消耗" if ok == CHOICE_INVALID else "取消替换武器，手牌未消耗")
						return
				if not _replace_play_equipment_if_current(p, "weapon", sub, old_weapon, old_weapon_card, weapon_context):
					_update_debug("武器替换已失效或所选牌不在手中，未替换")
					return
				_update_debug("%s 弃置了原武器【%s】，装备了【%s】" % [p.player_name, CardData.get_type_name(old_weapon), CardData.get_type_name(sub)])
				_sync_all_ui()
				_reset_play_countdown_if_p0()
				return
			var receipt = _equipment_payment_receipt(p, sub)
			if receipt.is_empty():
				return
			var equipped_card = _take_play_card(p, sub)
			if equipped_card == null:
				_update_debug("所选装备已不在牌区，取消装备")
				return
			if not p.equip_card_to_slot("weapon", equipped_card):
				_restore_equipment_payment(receipt, equipped_card)
				return
			_record_card_action(p, equipped_card)
			_claim_equipment_name(sub, equipped_card)
			_update_debug("%s 装备了【%s】" % [p.player_name, CardData.get_type_name(sub)])
			_sync_all_ui()
			_reset_play_countdown_if_p0()

		CardData.CardSubType.RENWANG_DUN, CardData.CardSubType.BAIHUA_SKIRT, CardData.CardSubType.QIXING_PAO, CardData.CardSubType.SILVER_LION, CardData.CardSubType.SHENGGUANG_BAIYI, CardData.CardSubType.BAGUA_ZHEN, CardData.CardSubType.TENGJIA, CardData.CardSubType.ZHANQI, CardData.CardSubType.LIEHUO_SHIELD, CardData.CardSubType.QINGGANG_SHIELD, CardData.CardSubType.THORN_ARMOR, CardData.CardSubType.CALAMITY_ROBE, CardData.CardSubType.SAGE_PROTECTION:
			# 装备防具（全场唯一：每种防具一局只有一张，装备过即永久占用）
			if not _can_play_equipment_instance(p, sub):
				_update_debug("【%s】名称已占用；只能再装备未弃置的同一原牌" % CardData.get_type_name(sub))
				return
			# 【苕】抢先明置（安普提·斯丢皮得）：暗置同类型装备时，可明置为该装备阻止本次装备
			if not equipment_pool.is_claimed(sub):
				if await _try_sao_preempt(p, sub, "armor"):
					return
			if not _can_play_equipment_instance(p, sub):
				return
			if p.equipment.has("armor"):
				var old_armor = p.equipment["armor"]
				if old_armor == sub:
					_update_debug("你已经装备了【%s】" % CardData.get_type_name(sub))
					return
				var old_armor_card = p.get_equipment_card("armor")
				var armor_context = turn_manager.get_context_revision()
				var old_is_hidden = old_armor == CardData.CardSubType.HIDDEN_EQUIPMENT
				# 已有防具：替换确认（玩家0交互 / AI 直接替换；暗置占位直接替换无需确认）
				if p.seat_index == 0 and not old_is_hidden:
					var valid = func():
						return _can_use_play_skill(p) and armor_context == turn_manager.get_context_revision() \
							and p.get_equipment_card("armor") == old_armor_card and p.get_armor() == old_armor
					var ok = await _show_weapon_replace_confirm(old_armor, sub, valid)
					if ok != 1:
						_update_debug("替换防具确认已失效，手牌未消耗" if ok == CHOICE_INVALID else "取消替换防具，手牌未消耗")
						return
				if not _replace_play_equipment_if_current(p, "armor", sub, old_armor, old_armor_card, armor_context):
					_update_debug("防具替换已失效或所选牌不在手中，未替换")
					return
				_update_debug("%s 弃置了原防具【%s】，装备了【%s】" % [p.player_name, CardData.get_type_name(old_armor), CardData.get_type_name(sub)])
				_sync_all_ui()
				_reset_play_countdown_if_p0()
				return
			var receipt = _equipment_payment_receipt(p, sub)
			if receipt.is_empty():
				return
			var equipped_card = _take_play_card(p, sub)
			if equipped_card == null:
				_update_debug("所选装备已不在牌区，取消装备")
				return
			if not p.equip_card_to_slot("armor", equipped_card):
				_restore_equipment_payment(receipt, equipped_card)
				return
			_record_card_action(p, equipped_card)
			_claim_equipment_name(sub, equipped_card)
			_update_debug("%s 装备了【%s】" % [p.player_name, CardData.get_type_name(sub)])
			_sync_all_ui()
			_reset_play_countdown_if_p0()

		CardData.CardSubType.MOUNT_PLUS, CardData.CardSubType.MOUNT_MINUS, CardData.CardSubType.MULE_PLUS, CardData.CardSubType.MULE_MINUS:
			# 装备坐骑：有空槽自动装入；槽满（4/4）可选择顶掉任意一匹
			# C-S3/E-04：普通坐骑及两种劣马均不打开抢先阻止窗口。
			var target_slot: String = ""
			if p.has_free_mount_slot():
				var receipt = _equipment_payment_receipt(p, sub)
				if receipt.is_empty():
					return
				var equipped_card = _take_play_card(p, sub)
				if equipped_card == null:
					_update_debug("所选装备已不在牌区，取消装备")
					return
				if not p.equip_mount_card(equipped_card):
					_restore_equipment_payment(receipt, equipped_card)
					return
				_record_card_action(p, equipped_card)
				_update_debug("%s 装备了【%s】（坐骑 +%d 匹 -%d 匹，共 %d/4）" % [
					p.player_name, CardData.get_type_name(sub), p.mount_plus, p.mount_minus, p.mount_count()
				])
				_sync_all_ui()
				_reset_play_countdown_if_p0()
				return

			# 槽满：选择顶掉任意一匹
			var mount_snapshot := {}
			for slot in p.get_mount_slots():
				mount_snapshot[slot] = {"sub": p.equipment[slot], "card": p.get_equipment_card(slot)}
			var play_context = turn_manager.get_context_revision()
			if p.seat_index == 0:
				var valid = func(): return _can_use_play_skill(p) and play_context == turn_manager.get_context_revision()
				target_slot = await _show_mount_replace_picker(p, valid)
				if target_slot == "cancel":
					_update_debug("取消替换坐骑，手牌未消耗")
					return
			else:
				# AI 随机顶掉一匹
				var slots = p.get_mount_slots()
				target_slot = slots[ai_driver.rng.randi_range(0, slots.size() - 1)]

			# 选槽期间若行动或所选原牌过期，不先扣手牌，也不顶掉后来换上的马。
			if _game_over or not p.is_alive() or not turn_manager.can_play_card() \
					or turn_manager.get_play_actor_idx() != p.seat_index \
					or turn_manager.get_context_revision() != play_context \
					or not Player.MOUNT_SLOTS.has(target_slot) or not mount_snapshot.has(target_slot) \
					or not p.equipment.has(target_slot):
				return
			var selected_mount: Dictionary = mount_snapshot[target_slot]
			if p.equipment[target_slot] != selected_mount.sub \
					or p.get_equipment_card(target_slot) != selected_mount.card:
				return
			# 支付失败的兜底需还到原手牌区，并保持任意牌未具体化。
			var pending_card = _pending_determined_card
			var payment_zone: Array[CardBase] = p.determined_cards
			var payment_index := -1
			if pending_card != null:
				payment_index = payment_zone.find(pending_card)
			else:
				var payment = HandPayment._find_player_card(p, sub, false)
				if not payment.is_empty():
					payment_zone = payment.cards
					payment_index = payment.index
			if payment_index < 0:
				return
			var was_blank = payment_zone[payment_index] == null
			var equipped_card = _take_play_card(p, sub)
			if equipped_card == null:
				_update_debug("所选装备已不在牌区，取消装备")
				return
			var old_sub = p.equipment[target_slot]
			var result = p.replace_mount_card_result(target_slot, equipped_card)
			if not result.success:
				payment_zone.insert(mini(payment_index, payment_zone.size()), null if was_blank else equipped_card)
				if pending_card != null:
					_pending_determined_card = pending_card
				_update_debug("坐骑替换失败，原牌已退回手牌区")
				_sync_all_ui()
				return
			if result.replaced_card != null:
				deck.discard(result.replaced_card)
			_record_card_action(p, equipped_card)
			_update_debug("%s 用【%s】顶掉了%s的【%s】（坐骑 +%d 匹 -%d 匹，共 %d/4）" % [
				p.player_name, CardData.get_type_name(sub), Player.EQUIP_SLOT_NAMES[target_slot],
				CardData.get_type_name(old_sub), p.mount_plus, p.mount_minus, p.mount_count()
			])
			_sync_all_ui()
			_reset_play_countdown_if_p0()

		_:
			_update_debug("%s 使用了【%s】（效果待实现）" % [p.player_name, CardData.get_type_name(sub)])
			var used_card = _take_play_card(p, sub)
			if used_card == null:
				_update_debug("所选牌已不在牌区，取消使用")
				return
			deck.discard(used_card)
			_sync_all_ui()
			_reset_play_countdown_if_p0()

# ============================
#  AOE 锦囊（南蛮入侵 / 万箭齐发）
# ============================

func _play_aoe(required_sub: CardData.CardSubType, card_name: String, required_name: String):
	var response_revision = turn_manager.get_context_revision()
	var p = players[turn_manager.get_play_actor_idx()]

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
		if _game_over or response_revision != turn_manager.get_context_revision():
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
		var nullified = await _ask_nullification_chain_result("%s的【%s】即将对 %s 生效，是否打出一张【无懈可击】？" % [p.player_name, card_name, target.player_name])
		if nullified == NullificationOutcome.INVALIDATED:
			break
		if nullified == NullificationOutcome.NULLIFIED:
			_update_debug("【%s】对 %s 的效果被【无懈可击】抵消" % [card_name, target.player_name])
			continue

		var responded = await _ask_basic_card_response_result(target, required_sub, _show_aoe_prompt.bind(card_name, required_name))
		if _game_over or response_revision != turn_manager.get_context_revision():
			break
		if not target.is_alive() or _is_kneeling(target):
			continue

		if responded == BasicResponseOutcome.INVALIDATED:
			break
		if responded == BasicResponseOutcome.PAID:
			_update_debug("%s 出【%s】响应【%s】" % [target.player_name, required_name, card_name])
		else:
			_update_debug("%s 未能出【%s】响应【%s】" % [target.player_name, required_name, card_name])
			await _deal_damage(p, target, 1, EffectChain.DamageType.PHYSICAL)

	_sync_all_ui()

# 杀/决斗/AOE共用物理响应，不消耗主动杀次数和酒，也不创建新出牌阶段。
enum BasicResponseOutcome { DECLINED, PAID, INVALIDATED }

# 保留bool兼容入口；实际伤害链须解释失效，不能把失效当主动放弃。
func _ask_basic_card_response(p: Player, expected: CardData.CardSubType, prompt: Callable, decision: Callable = Callable()) -> bool:
	return await _ask_basic_card_response_result(p, expected, prompt, decision) == BasicResponseOutcome.PAID

func _ask_basic_card_response_result(p: Player, expected: CardData.CardSubType, prompt: Callable, decision: Callable = Callable()) -> BasicResponseOutcome:
	if _game_over or not p.is_alive() or _is_kneeling(p):
		return BasicResponseOutcome.INVALIDATED
	if not HandPayment.has_response(p, expected):
		return BasicResponseOutcome.DECLINED
	var revision = turn_manager.get_context_revision()
	var snapshot = HandSelection.new(p)
	var accepted: bool
	if decision.is_valid():
		accepted = await decision.call()
	elif p.seat_index == 0:
		var answer = await prompt.call()
		if typeof(answer) == TYPE_INT and answer == CHOICE_INVALID:
			return BasicResponseOutcome.INVALIDATED
		accepted = bool(answer)
	else:
		accepted = await _choose_ai_response(p, "basic", [expected]) == expected
	if not accepted:
		return BasicResponseOutcome.DECLINED
	if _game_over or not p.is_alive() or _is_kneeling(p) or revision != turn_manager.get_context_revision():
		return BasicResponseOutcome.INVALIDATED
	# 原响应牌失效/无法支付仍是未能响应；不借新接口改变既有伤害结算。
	if p.hand != snapshot.hand or p.determined_cards != snapshot.determined:
		return BasicResponseOutcome.DECLINED
	var used_card = HandPayment.take_player_response(p, expected)
	if used_card == null:
		return BasicResponseOutcome.DECLINED
	deck.discard(used_card)
	_record_card_action(p, used_card, CardActionEvent.Kind.RESPONSE)
	if expected == CardData.CardSubType.STRIKE:
		_record_strike_played(p)
	if expected == CardData.CardSubType.DODGE:
		_try_bagua_draw(p)
	_sync_all_ui()
	return BasicResponseOutcome.PAID

func _show_aoe_prompt(card_name: String, required_name: String) -> int:
	# 测试钩子：跳过 UI 直接返回
	if _aoe_override.is_valid():
		return 1 if _aoe_override.call() else 0

	if _game_over:
		return CHOICE_INVALID
	var answer = ChoicePromptAnswer.new()
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

	respond_btn.pressed.connect(answer.submit.bind(1), CONNECT_ONE_SHOT)
	skip_btn.pressed.connect(answer.submit.bind(0), CONNECT_ONE_SHOT)
	var result = await _wait_choice_prompt(overlay, answer)
	return 0 if result == -1 else result

# ============================
#  桃园结义
# ============================

func _play_peach_garden():
	var revision = turn_manager.get_context_revision()
	var p = players[turn_manager.get_play_actor_idx()]

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
		var nullified = await _ask_nullification_chain_result("%s的【桃园结义】即将对 %s 生效，是否打出一张【无懈可击】？" % [p.player_name, target.player_name])
		if nullified == NullificationOutcome.INVALIDATED or _game_over or revision != turn_manager.get_context_revision():
			break
		if not target.is_alive() or _is_kneeling(target):
			continue
		if nullified == NullificationOutcome.NULLIFIED:
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
	var revision = turn_manager.get_context_revision()
	var p = players[turn_manager.get_play_actor_idx()]

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
		var nullified = await _ask_nullification_chain_result("%s的【五谷丰登】即将对 %s 生效，是否打出一张【无懈可击】？" % [p.player_name, target.player_name])
		if nullified == NullificationOutcome.INVALIDATED or _game_over or revision != turn_manager.get_context_revision():
			break
		if not target.is_alive() or _is_kneeling(target):
			continue
		if nullified == NullificationOutcome.NULLIFIED:
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
	var revision = turn_manager.get_context_revision()
	var p = players[turn_manager.get_play_actor_idx()]
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
		var nullified = await _ask_nullification_chain_result("%s的【卸甲归田】即将对 %s 生效，是否打出一张【无懈可击】？" % [p.player_name, target.player_name])
		if nullified == NullificationOutcome.INVALIDATED or _game_over or revision != turn_manager.get_context_revision():
			break
		if not target.is_alive() or _is_kneeling(target):
			continue
		if nullified == NullificationOutcome.NULLIFIED:
			_update_debug("【卸甲归田】对 %s 的效果被【无懈可击】抵消" % target.player_name)
			continue

		var slots = target.get_equip_slots()
		if slots.is_empty():
			_update_debug("%s 没有装备，跳过" % target.player_name)
			continue

		var removed_count = 0
		for slot in slots:
			var offered_card = _equipment_resource_for_pick(target, slot)
			if offered_card == null:
				continue
			if _game_over or target.is_dead() or _equipment_resource_for_pick(target, slot) != offered_card:
				continue
			var removed_card = target.remove_equipment(slot)
			if removed_card == offered_card:
				deck.discard(removed_card)
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
	var revision = turn_manager.get_context_revision()
	var valid = func():
		return not _game_over and revision == turn_manager.get_context_revision() \
			and players.has(attacker) and players.has(target) \
			and target.is_alive() and not _is_kneeling(target)
	if not valid.call():
		return

	# 目标任何区域都没有牌 → 不能使用
	if not target.has_any_card():
		_update_debug("目标没有任何可%s的牌，无法使用【%s】" % [action, card_name])
		return

	# 选择牌的区域：使用者是玩家 0 时交互，否则 AI 随机
	var zone: String
	if attacker.seat_index == 0:
		zone = await _show_zone_picker(action, target, valid)
	else:
		zone = _pick_random_zone(target)

	if zone == "cancel":
		_update_debug("取消使用【%s】" % card_name)
		return

	if not valid.call() or zone not in ["hand", "equip", "judgment"]:
		return
	if (zone == "hand" and target.hand_size() == 0) \
			or (zone == "equip" and target.get_equip_slots().is_empty()) \
			or (zone == "judgment" and target.judgment_cards.is_empty()):
		return

	# 确认后消耗手牌
	var sub = CardData.CardSubType.SNATCH if is_snatch else CardData.CardSubType.DISMANTLE
	if not await _consume_trick(attacker, sub):
		return
	turn_manager.use_card("steal")
	_reset_play_countdown_if_p0()
	_update_debug("%s 对 %s 使用【%s】" % [attacker.player_name, target.player_name, card_name])

	# 成为目标时先处理烈火盾；无效后不选装备、不移动任何目标牌。
	var shield_result = await _try_liehuo_nullify_result(target, sub, valid)
	if shield_result != LiehuoOutcome.NOT_USED:
		return
	if not valid.call():
		return

	# 无懈可击：效果即将对目标生效前
	var nullified = await _ask_nullification_chain_result("%s的【%s】即将对 %s 生效，是否打出一张【无懈可击】？" % [attacker.player_name, card_name, target.player_name], valid)
	if nullified == NullificationOutcome.INVALIDATED:
		return
	if nullified == NullificationOutcome.NULLIFIED:
		_update_debug("【%s】对 %s 的效果被【无懈可击】抵消" % [card_name, target.player_name])
		return

	if not valid.call():
		return
	match zone:
		"hand":
			await _steal_hand(attacker, target, is_snatch, card_name)
		"equip":
			await _steal_equip(attacker, target, is_snatch, card_name, valid)
		"judgment":
			await _steal_judgment(attacker, target, is_snatch, card_name)

	_sync_all_ui()

# 手牌：目标 -1；顺手牵羊时自己 +1
func _steal_hand(attacker: Player, target: Player, is_snatch: bool, card_name: String):
	if target.hand_size() <= 0:
		_update_debug("目标没有手牌")
		return
	# 不从空牌区生成任意牌；盾仅在拆/顺成为目标的公共入口询问。
	if target.is_dead() or target.hand_size() == 0:
		return
	var taken: CardBase = target.take_hand_cards(1)[0]
	if is_snatch:
		# 任意牌仍为 null；具体牌保持同一资源、类型和来源元数据。
		attacker.hand.append(taken)
		_update_debug("%s 获得 %s 的 1 张手牌（自己手牌 %d 张）" % [attacker.player_name, target.player_name, attacker.hand_size()])
	else:
		if taken != null:
			deck.discard(taken)
		_update_debug("%s 弃置了 %s 的 1 张手牌（目标剩 %d 张）" % [attacker.player_name, target.player_name, target.hand_size()])

# 装备：目标失去该装备；顺手牵羊时放入自己「已确定的牌」
func _equipment_resource_for_pick(p: Player, slot: String) -> CardBase:
	if p.equipment.get(slot, -1) == CardData.CardSubType.HIDDEN_EQUIPMENT:
		return p.get_hidden_equipment_card(slot)
	return p.get_equipment_card(slot)

func _steal_equip(attacker: Player, target: Player, is_snatch: bool, card_name: String, allowed: Callable = Callable()):
	var slots = target.get_equip_slots()
	if slots.is_empty():
		_update_debug("目标没有装备牌")
		return
	# 选槽弹窗可能等待其他动作；记录当时各槽实体，而不是仅记类型。
	var offered_cards := {}
	for offered_slot in slots:
		offered_cards[offered_slot] = _equipment_resource_for_pick(target, offered_slot)
	var revision = turn_manager.get_context_revision()
	var valid = func():
		return not _game_over and revision == turn_manager.get_context_revision() \
			and players.has(attacker) and players.has(target) and target.is_alive() \
			and (not allowed.is_valid() or allowed.call())

	var slot: String
	if attacker.seat_index == 0:
		slot = await _show_equip_picker(target, slots, "选择要处理的装备：", valid)
		if slot == "cancel":
			_update_debug("取消选择装备，【%s】未生效（牌已消耗）" % card_name)
			return
	else:
		slot = slots[ai_driver.rng.randi_range(0, slots.size() - 1)]

	if not valid.call() or not slots.has(slot) or not target.equipment.has(slot):
		return
	var selected_card: CardBase = offered_cards.get(slot, null)
	if selected_card != null and _equipment_resource_for_pick(target, slot) != selected_card:
		return
	var sub = target.equipment[slot]
	if _game_over or target.is_dead() or target.equipment.get(slot, -1) != sub \
			or (selected_card != null and _equipment_resource_for_pick(target, slot) != selected_card):
		return
	# 持久状态由原牌在卸下/装备时保存恢复；入手不授予佩戴效果。
	var equipment_card = target.remove_equipment(slot)
	if equipment_card == null:
		return
	if is_snatch:
		attacker.determined_cards.append(equipment_card)
		if sub == CardData.CardSubType.HIDDEN_EQUIPMENT:
			await _declare_stolen_hidden_equipment(target, attacker, equipment_card, valid)
		_update_debug("%s 获得 %s 的【%s】，已加入你的「已确定的牌」" % [attacker.player_name, target.player_name, CardData.get_type_name(sub)])
	else:
		deck.discard(equipment_card)
		_update_debug("%s 弃置了 %s 的【%s】" % [attacker.player_name, target.player_name, CardData.get_type_name(sub)])

# C-S4c：同类最后一个武器／防具名称被声明后，任何牌区该类暗置牌立即暗置入弃牌堆。
func _claim_equipment_name(sub: CardData.CardSubType, card: CardBase = null) -> void:
	if not equipment_pool.claim(sub, card):
		return
	var category = CardData.get_equipment_slot_type(sub)
	if category == "weapon" or category == "armor":
		_discard_exhausted_hidden_category(category)

func _discard_exhausted_hidden_category(category: String) -> void:
	if category != "weapon" and category != "armor":
		return
	var names = SAO_WEAPON_SUBS if category == "weapon" else SAO_ARMOR_SUBS
	for sub in names:
		if not equipment_pool.is_claimed(sub):
			return
	var removed := 0
	for p in players:
		for slot in p.get_equip_slots():
			var equipped_hidden = p.get_hidden_equipment_card(slot)
			if equipped_hidden != null and equipped_hidden.hidden_category == category:
				p.remove_equipment(slot)
				deck.discard(equipped_hidden)
				removed += 1
		for cards in [p.hand, p.determined_cards, p.judgment_cards]:
			for i in range(cards.size() - 1, -1, -1):
				var zone_card: CardBase = cards[i]
				if zone_card != null and zone_card.sub_type == CardData.CardSubType.HIDDEN_EQUIPMENT \
						and zone_card.hidden_category == category:
					cards.remove_at(i)
					if _pending_determined_card == zone_card:
						_pending_determined_card = null
					deck.discard(zone_card)
					removed += 1
	if removed > 0:
		_update_debug("同类装备名称已全部声明，%d 张暗置%s进入弃牌堆" % [removed, "武器" if category == "weapon" else "防具"])
		_sync_all_ui()
		_refresh_detail_popup()

# EQ-04：已占用名称只允许由同一张未弃置的具体原牌再次声明；任意暗置牌不能造第二张。
func _can_declare_hidden_name(card: CardBase, sub: CardData.CardSubType) -> bool:
	if not equipment_pool.is_claimed(sub):
		return true
	return card.hidden_original_sub_type == sub \
		and equipment_pool.is_claimed_original(sub, card) and not deck._discard.has(card)

# E-03：暗置装备被顺走后，原持有者声明；同类名称耗尽改按C-S4c立即弃置。
func _hidden_declaration_options(card: CardBase) -> Array[int]:
	var options: Array[int] = []
	match card.hidden_category:
		"weapon":
			for sub in SAO_WEAPON_SUBS:
				if _can_declare_hidden_name(card, sub):
					options.append(sub)
		"armor":
			for sub in SAO_ARMOR_SUBS:
				if _can_declare_hidden_name(card, sub):
					options.append(sub)
		"mount":
			options.append_array(SAO_MOUNT_SUBS)
	if card.hidden_original_sub_type >= 0:
		for i in range(options.size() - 1, -1, -1):
			if options[i] != card.hidden_original_sub_type:
				options.remove_at(i)
	return options

func _default_stolen_hidden_sub(card: CardBase, options: Array[int]) -> int:
	if options.is_empty():
		return -1
	# 已具体化的原牌不能因取消/超时重新命名。
	if card.hidden_original_sub_type >= 0:
		return options[0]
	match card.hidden_category:
		"weapon":
			if options.has(CardData.CardSubType.CALAMITY_SWORD):
				return CardData.CardSubType.CALAMITY_SWORD
		"armor":
			if options.has(CardData.CardSubType.CALAMITY_ROBE):
				return CardData.CardSubType.CALAMITY_ROBE
		"mount":
			var mules: Array[int] = []
			for sub in [CardData.CardSubType.MULE_MINUS, CardData.CardSubType.MULE_PLUS]:
				if options.has(sub):
					mules.append(sub)
			if not mules.is_empty():
				return mules[randi() % mules.size()]
	return options[randi() % options.size()]

func _declare_stolen_hidden_equipment(original_holder: Player, recipient: Player, card: CardBase,
		allowed: Callable = Callable()) -> void:
	if card == null or card.sub_type != CardData.CardSubType.HIDDEN_EQUIPMENT \
			or not recipient.determined_cards.has(card) or (allowed.is_valid() and not allowed.call()):
		return
	var options = _hidden_declaration_options(card)
	if options.is_empty():
		_update_debug("暗置装备无可声明名称，仍保持暗置")
		return
	var chosen: int = -1
	if _sao_transfer_declare_override.is_valid():
		chosen = _sao_transfer_declare_override.call()
	elif original_holder.seat_index == 0:
		var names: Array = []
		for sub in options:
			names.append(CardData.get_type_name(sub))
		var idx = await _show_sao_reveal_picker(names, allowed)
		if allowed.is_valid() and idx == CHOICE_INVALID:
			return
		if idx >= 0 and idx < options.size():
			chosen = options[idx]
	else:
		# AI 的确定性声明策略；不改变人类玩家的名称选择。
		chosen = options[0]
	if allowed.is_valid() and (chosen == CHOICE_INVALID or not allowed.call()):
		return
	if chosen < 0:
		chosen = _default_stolen_hidden_sub(card, options)
	if _game_over or card.sub_type != CardData.CardSubType.HIDDEN_EQUIPMENT \
			or not recipient.determined_cards.has(card) \
			or not options.has(chosen) or not _hidden_declaration_options(card).has(chosen):
		return
	card.sub_type = chosen
	card.card_name = CardData.get_type_name(chosen)
	card.description = CardData.CARD_DESCRIPTIONS.get(chosen, "")
	card.hidden_category = ""
	card.hidden_original_sub_type = -1
	if chosen != CardData.CardSubType.MOUNT_PLUS and chosen != CardData.CardSubType.MOUNT_MINUS \
			and chosen != CardData.CardSubType.MULE_PLUS and chosen != CardData.CardSubType.MULE_MINUS:
		_claim_equipment_name(chosen, card)
	_update_debug("%s 声明被顺走的暗置装备为【%s】" % [original_holder.player_name, card.card_name])

# 【没用】交换时先完成原牌移动，再由原持有者声明；与顺走共用合法名称和取消默认。
func _declare_exchanged_hidden_equipment(original_holder: Player, recipient: Player,
		slot: String, card: CardBase) -> void:
	if card == null or card.sub_type != CardData.CardSubType.HIDDEN_EQUIPMENT \
			or recipient.get_hidden_equipment_card(slot) != card:
		return
	var options = _hidden_declaration_options(card)
	if options.is_empty():
		_update_debug("交换后的暗置装备无可声明名称，仍保持暗置")
		return
	var chosen: int = -1
	if _sao_transfer_declare_override.is_valid():
		chosen = _sao_transfer_declare_override.call()
	elif original_holder.seat_index == 0:
		var names: Array = []
		for sub in options:
			names.append(CardData.get_type_name(sub))
		var idx = await _show_sao_reveal_picker(names)
		if idx >= 0 and idx < options.size():
			chosen = options[idx]
	else:
		chosen = options[0]
	if chosen < 0:
		chosen = _default_stolen_hidden_sub(card, options)
	if _game_over or recipient.get_hidden_equipment_card(slot) != card \
			or not options.has(chosen) or not _hidden_declaration_options(card).has(chosen):
		return
	if _reveal_hidden_slot_as(recipient, slot, card, chosen):
		_update_debug("%s 声明交换离区的暗置装备为【%s】" % [original_holder.player_name, card.card_name])

# 判定牌：目标失去；顺手牵羊时放入自己「已确定的牌」
func _steal_judgment(attacker: Player, target: Player, is_snatch: bool, card_name: String):
	if target.judgment_cards.is_empty():
		_update_debug("目标没有判定牌")
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
	return zones[ai_driver.rng.randi_range(0, zones.size() - 1)]

# 选择牌区域弹窗（手牌/装备牌/判定牌）——锚点布局，窗口缩放自动居中
func _show_zone_picker(action: String, target: Player, allowed: Callable = Callable()) -> String:
	# 测试钩子：跳过 UI 直接返回区域名
	if _zone_pick_override.is_valid():
		return _zone_pick_override.call()
	var revision = turn_manager.get_context_revision()
	var valid = func():
		return not _game_over and revision == turn_manager.get_context_revision() \
			and players.has(target) and target.is_alive() \
			and (not allowed.is_valid() or allowed.call())
	if not valid.call(): return ""
	var answer = ChoicePromptAnswer.new()

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
	hand_btn.pressed.connect(func(): answer.submit(0), CONNECT_ONE_SHOT)
	hbox.add_child(hand_btn)

	var equip_btn = Button.new()
	equip_btn.text = "装备牌（%d 件）" % target.get_equip_slots().size()
	equip_btn.custom_minimum_size = Vector2(160, 44)
	equip_btn.disabled = target.get_equip_slots().is_empty()
	equip_btn.pressed.connect(func(): answer.submit(1), CONNECT_ONE_SHOT)
	hbox.add_child(equip_btn)

	var judgment_btn = Button.new()
	judgment_btn.text = "判定牌（%d 张）" % target.judgment_cards.size()
	judgment_btn.custom_minimum_size = Vector2(160, 44)
	judgment_btn.disabled = target.judgment_cards.is_empty()
	judgment_btn.pressed.connect(func(): answer.submit(2), CONNECT_ONE_SHOT)
	hbox.add_child(judgment_btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(160, 44)
	cancel_btn.modulate = Color(0.7, 0.7, 0.7)
	cancel_btn.pressed.connect(func(): answer.submit(-1), CONNECT_ONE_SHOT)
	vbox.add_child(cancel_btn)

	var result = await _wait_choice_prompt(overlay, answer, valid, false)
	if result == CHOICE_INVALID: return ""
	return ["hand", "equip", "judgment"][result] if result >= 0 and result < 3 else "cancel"

# 选择具体装备弹窗——锚点布局，窗口缩放自动居中
func _show_equip_picker(target: Player, slots: Array[String], title: String = "选择要处理的装备：", allowed: Callable = Callable()) -> String:
	# 测试钩子：跳过 UI 直接返回槽位
	if _equip_pick_override.is_valid():
		return _equip_pick_override.call()
	var revision = turn_manager.get_context_revision()
	var candidates = slots.duplicate()
	var originals: Dictionary = {}
	for slot in candidates: originals[slot] = _equipment_resource_for_pick(target, slot)
	var valid = func():
		return not _game_over and revision == turn_manager.get_context_revision() \
			and players.has(target) and target.is_alive() \
			and (not allowed.is_valid() or allowed.call())
	if not valid.call(): return ""
	var answer = ChoicePromptAnswer.new()
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

	for i in candidates.size():
		var slot = candidates[i]
		var btn = Button.new()
		var sub = target.equipment[slot]
		btn.text = "%s：%s" % [Player.EQUIP_SLOT_NAMES[slot], CardData.get_type_name(sub)]
		btn.custom_minimum_size = Vector2(160, 44)
		btn.pressed.connect(func(): answer.submit(i), CONNECT_ONE_SHOT)
		hbox.add_child(btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(160, 44)
	cancel_btn.modulate = Color(0.7, 0.7, 0.7)
	cancel_btn.pressed.connect(func(): answer.submit(-1), CONNECT_ONE_SHOT)
	vbox.add_child(cancel_btn)

	var result = await _wait_choice_prompt(overlay, answer, valid, false)
	if result == CHOICE_INVALID: return ""
	if result < 0: return "cancel"
	if result >= candidates.size(): return ""
	var chosen: String = candidates[result]
	if originals[chosen] == null or _equipment_resource_for_pick(target, chosen) != originals[chosen]: return ""
	return chosen

# 坐骑槽满时：选择要顶掉的马（锚点居中弹窗）
func _show_mount_replace_picker(p: Player, allowed: Callable = Callable()) -> String:
	if _mount_replace_override.is_valid():
		return _mount_replace_override.call()
	var revision = turn_manager.get_context_revision()
	var candidates = p.get_mount_slots()
	var originals: Dictionary = {}
	for slot in candidates: originals[slot] = _equipment_resource_for_pick(p, slot)
	var valid = func():
		return not _game_over and players.has(p) and p.is_alive() \
			and revision == turn_manager.get_context_revision() \
			and (not allowed.is_valid() or allowed.call())
	if not valid.call(): return ""
	var answer = ChoicePromptAnswer.new()
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

	for i in candidates.size():
		var slot = candidates[i]
		var btn = Button.new()
		btn.text = "%s：%s" % [Player.EQUIP_SLOT_NAMES[slot], CardData.get_type_name(p.equipment[slot])]
		btn.custom_minimum_size = Vector2(160, 44)
		btn.pressed.connect(func(): answer.submit(i), CONNECT_ONE_SHOT)
		hbox.add_child(btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(160, 44)
	cancel_btn.modulate = Color(0.7, 0.7, 0.7)
	cancel_btn.pressed.connect(func(): answer.submit(-1), CONNECT_ONE_SHOT)
	vbox.add_child(cancel_btn)

	var result = await _wait_choice_prompt(overlay, answer, valid, false)
	if result == CHOICE_INVALID: return ""
	if result < 0: return "cancel"
	if result >= candidates.size(): return ""
	var chosen: String = candidates[result]
	if originals[chosen] == null or _equipment_resource_for_pick(p, chosen) != originals[chosen]: return ""
	return chosen

# 已有武器时替换确认弹窗（锚点居中）
func _show_weapon_replace_confirm(old_weapon: CardData.CardSubType, new_weapon: CardData.CardSubType, allowed: Callable = Callable()) -> int:
	# 测试钩子：跳过 UI 直接返回
	if _weapon_replace_override.is_valid():
		var reply = await _weapon_replace_override.call()
		if typeof(reply) == TYPE_INT and reply == CHOICE_INVALID: return CHOICE_INVALID
		return 1 if reply else 0
	if _game_over or (allowed.is_valid() and not allowed.call()): return CHOICE_INVALID
	var answer = ChoicePromptAnswer.new()

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
	yes_btn.pressed.connect(func(): answer.submit(1), CONNECT_ONE_SHOT)
	hbox.add_child(yes_btn)

	var no_btn = Button.new()
	no_btn.text = "取消"
	no_btn.custom_minimum_size = Vector2(160, 44)
	no_btn.modulate = Color(0.7, 0.7, 0.7)
	no_btn.pressed.connect(func(): answer.submit(0), CONNECT_ONE_SHOT)
	hbox.add_child(no_btn)

	return await _wait_choice_prompt(overlay, answer, allowed, false)

# 丈八蛇矛：杀命中后、扣血前询问流失体力数（X≤3），合并伤害。
# 返回流失的体力数（0 = 放弃，CHOICE_INVALID = 等待失效）；AI 不主动流失。
func _ask_zhangba_extra(p: Player, allowed: Callable = Callable()) -> int:
	# 测试钩子
	if _zhangba_override.is_valid():
		return await _zhangba_override.call()

	# AI 不主动流失
	if p.seat_index != 0:
		return 0

	var answer = ChoicePromptAnswer.new()
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
		btn.pressed.connect(func(): answer.submit(x))
		hbox.add_child(btn)

	# 原丈八窗口没有计时；生命周期迁移不添加默认选项。
	return await _wait_choice_prompt(overlay, answer, allowed, false)

# ============================
#  雌雄双股剑
# ============================

signal _chixiong_activate_result(result: bool)
signal _chixiong_target_result(discard: bool)

# 使用者（玩家0）：1发动、0不发动、CHOICE_INVALID窗口失效；保留无倒计时。
func _ask_chixiong_activate(target_name: String, allowed: Callable = Callable()) -> int:
	# 测试钩子
	if _chixiong_activate_override.is_valid():
		var result = await _chixiong_activate_override.call()
		return CHOICE_INVALID if typeof(result) == TYPE_INT and result == CHOICE_INVALID else (1 if result else 0)
	var answer = ChoicePromptAnswer.new()

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
	yes_btn.pressed.connect(func(): answer.submit(1))
	hbox.add_child(yes_btn)

	var no_btn = Button.new()
	no_btn.text = "不发动"
	no_btn.custom_minimum_size = Vector2(160, 44)
	no_btn.modulate = Color(0.7, 0.7, 0.7)
	no_btn.pressed.connect(func(): answer.submit(0))
	hbox.add_child(no_btn)

	return await _wait_choice_prompt(overlay, answer, allowed, false)

# 结算雌雄双股剑：目标选择「弃置一张手牌」或「令使用者摸一张牌」
# 目标没有手牌时只能选择令使用者摸一张牌（原版规则）
func _resolve_chixiong(p: Player, target: Player, allowed: Callable = Callable()) -> bool:
	if _game_over or p == null or target == null or not p.is_alive() or not target.is_alive():
		return false
	var revision = turn_manager.get_context_revision()
	var valid = func():
		return not _game_over and players.has(p) and players.has(target) and p.is_alive() and target.is_alive() \
			and turn_manager.get_context_revision() == revision and (not allowed.is_valid() or allowed.call())
	if not valid.call():
		return false
	_update_debug("%s 发动【雌雄双股剑】，令 %s 选择：弃置一张手牌 / 令 %s 摸一张牌" % [p.player_name, target.player_name, p.player_name])

	if target.hand_size() <= 0:
		_draw_blank_cards(p, 1)
		_update_debug("%s 没有手牌，只能选择令 %s 摸一张牌（手牌 %d 张）" % [target.player_name, p.player_name, p.hand_size()])
		_sync_all_ui()
		return valid.call()

	var choice = 0
	if _chixiong_target_override.is_valid():
		var result = await _chixiong_target_override.call()
		choice = CHOICE_INVALID if typeof(result) == TYPE_INT and result == CHOICE_INVALID else (1 if result else 0)
	elif target.seat_index == 0:
		choice = await _show_chixiong_target_prompt(p.player_name, valid)
	else:
		# AI 目标：50% 概率弃一张手牌
		choice = 1 if randi() % 2 == 0 else 0

	if choice == CHOICE_INVALID or not valid.call():
		return false
	if choice == 1:
		# 已选择弃牌分支；烈火盾不替代雌雄失牌，快照失效重新选择。
		while valid.call() and target.hand_size() > 0:
			var outcome = await _select_hand_discard_result(target, 1, true, valid)
			if not valid.call():
				return false
			if outcome == HandDiscardOutcome.PAID:
				_update_debug("%s 选择弃置一张手牌（剩余 %d 张）" % [target.player_name, target.hand_size()])
				break
			if outcome in [HandDiscardOutcome.ACTION_INVALIDATED, HandDiscardOutcome.GAME_ENDED]:
				return false
			if outcome == HandDiscardOutcome.INSUFFICIENT_CARDS:
				break # 沿用已选弃牌期间手牌耗尽的处理，不改成摸牌分支。
	else:
		_draw_blank_cards(p, 1)
		_update_debug("%s 选择令 %s 摸一张牌（手牌 %d 张）" % [target.player_name, p.player_name, p.hand_size()])
	_sync_all_ui()
	return valid.call()

# 目标（玩家0）：1弃牌、0令使用者摸牌、CHOICE_INVALID失效；无倒计时。
func _show_chixiong_target_prompt(attacker_name: String, allowed: Callable = Callable()) -> int:
	# 测试钩子
	if _chixiong_target_override.is_valid():
		var result = await _chixiong_target_override.call()
		return CHOICE_INVALID if typeof(result) == TYPE_INT and result == CHOICE_INVALID else (1 if result else 0)
	var answer = ChoicePromptAnswer.new()

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
	discard_btn.pressed.connect(func(): answer.submit(1))
	hbox.add_child(discard_btn)

	var draw_btn = Button.new()
	draw_btn.text = "令 %s 摸一张牌" % attacker_name
	draw_btn.custom_minimum_size = Vector2(220, 44)
	draw_btn.pressed.connect(func(): answer.submit(0))
	hbox.add_child(draw_btn)

	return await _wait_choice_prompt(overlay, answer, allowed, false)

# ============================
#  寒冰剑
# ============================

signal _ice_sword_result(result: bool)

# 寒冰剑：杀将要造成伤害时询问，发动则防止伤害、弃两张手牌。
func _ask_ice_sword(target_name: String, allowed: Callable = Callable()) -> int:
	# 测试钩子
	if _ice_sword_override.is_valid():
		var result = await _ice_sword_override.call()
		return CHOICE_INVALID if typeof(result) == TYPE_INT and result == CHOICE_INVALID else (1 if result else 0)
	var answer = ChoicePromptAnswer.new()

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
	label.text = "【寒冰剑】：你的【杀】将对 %s 造成伤害！\n是否防止此伤害，改为依次弃置其两张手牌？" % target_name
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
	yes_btn.pressed.connect(func(): answer.submit(1))
	hbox.add_child(yes_btn)

	var no_btn = Button.new()
	no_btn.text = "不发动"
	no_btn.custom_minimum_size = Vector2(160, 44)
	no_btn.modulate = Color(0.7, 0.7, 0.7)
	no_btn.pressed.connect(func(): answer.submit(0))
	hbox.add_child(no_btn)

	return await _wait_choice_prompt(overlay, answer, allowed, false)

# ============================
#  贯石斧
# ============================

signal _guanshi_result(result: bool)

# 贯石斧：1发动、0不发动、CHOICE_INVALID失效；保留原无倒计时。
func _ask_guanshi(target_name: String, allowed: Callable = Callable()) -> int:
	# 测试钩子
	if _guanshi_override.is_valid():
		var result = await _guanshi_override.call()
		return CHOICE_INVALID if typeof(result) == TYPE_INT and result == CHOICE_INVALID else (1 if result else 0)
	var answer = ChoicePromptAnswer.new()

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
	yes_btn.pressed.connect(func(): answer.submit(1))
	hbox.add_child(yes_btn)

	var no_btn = Button.new()
	no_btn.text = "不发动"
	no_btn.custom_minimum_size = Vector2(200, 44)
	no_btn.modulate = Color(0.7, 0.7, 0.7)
	no_btn.pressed.connect(func(): answer.submit(0))
	hbox.add_child(no_btn)

	return await _wait_choice_prompt(overlay, answer, allowed, false)

# 贯石斧：选择弃置哪张坐骑牌（锚点居中弹窗；已确认发动，必须弃一匹，无取消）
func _guanshi_mount_card(p: Player, slot: String) -> CardBase:
	if not Player.MOUNT_SLOTS.has(slot):
		return null
	return p.get_hidden_equipment_card(slot) if p.equipment.get(slot, -1) == CardData.CardSubType.HIDDEN_EQUIPMENT else p.get_equipment_card(slot)

func _show_mount_discard_picker(p: Player, allowed: Callable = Callable()) -> String:
	var slots = p.get_mount_slots()
	var originals: Dictionary = {}
	for slot in slots:
		originals[slot] = _guanshi_mount_card(p, slot)
	var revision = turn_manager.get_context_revision()
	var valid = func():
		return not _game_over and players.has(p) and p.is_alive() \
			and revision == turn_manager.get_context_revision() \
			and (not allowed.is_valid() or allowed.call()) \
			and slots.any(func(slot): return originals[slot] != null and _guanshi_mount_card(p, slot) == originals[slot])
	if not valid.call():
		return ""
	# 测试钩子：返回要弃置的坐骑槽位
	if _guanshi_mount_override.is_valid():
		var selected = await _guanshi_mount_override.call()
		return selected if selected is String and valid.call() and originals.has(selected) \
			and originals[selected] != null and _guanshi_mount_card(p, selected) == originals[selected] else ""
	var answer = ChoicePromptAnswer.new()

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

	for index in slots.size():
		var slot = slots[index]
		var btn = Button.new()
		btn.text = "%s：%s" % [Player.EQUIP_SLOT_NAMES[slot], CardData.get_type_name(p.equipment[slot])]
		btn.custom_minimum_size = Vector2(160, 44)
		btn.pressed.connect(func(): answer.submit(index))
		hbox.add_child(btn)

	var result = await _wait_choice_prompt(overlay, answer, valid, false)
	if result < 0 or result >= slots.size() or not valid.call():
		return ""
	var selected = slots[result]
	return selected if originals[selected] != null and _guanshi_mount_card(p, selected) == originals[selected] else ""

# ============================
#  铁索连环
# ============================

func _enter_iron_chain_mode():
	_card_target_generation += 1
	_is_iron_chain_targeting = true
	_iron_chain_targets.clear()

	_play_btn.visible = false
	_end_play_btn.visible = false
	_cancel_target_btn.visible = true

	_update_debug("请点击 1-2 名角色（可含自己）作为【铁索连环】目标")

# 点击角色头像（铁索连环模式）
func _on_iron_chain_target_click(target: Player):
	if not _is_iron_chain_targeting or _card_target_confirm_owner == _card_target_generation:
		return
	var actor = players[0]
	if not _can_use_play_skill(actor) or not players.has(target): return
	var generation = _card_target_generation
	var revision = turn_manager.get_context_revision()
	var pending_card = _pending_determined_card
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
	var chosen = _iron_chain_targets.duplicate()
	var valid = func():
		return _can_use_play_skill(actor) and revision == turn_manager.get_context_revision() \
			and generation == _card_target_generation and _is_iron_chain_targeting \
			and _pending_determined_card == pending_card and _iron_chain_targets == chosen \
			and chosen.all(func(p): return players.has(p) and p.is_alive() and not _is_kneeling(p))

	if _iron_chain_targets.size() == 1:
		# 问是否继续选第二名
		_card_target_confirm_owner = generation
		var more = await _show_more_target_confirm(target.player_name, valid)
		if _card_target_confirm_owner == generation: _card_target_confirm_owner = -1
		if more == CHOICE_INVALID or not valid.call():
			_clear_invalid_card_targeting(generation)
			return
		if more == 1:
			_update_debug("已选择 %s，请再点击第二名角色" % target.player_name)
			return

	# 单目标（否）或已选满两名 → 执行
	if not valid.call():
		_clear_invalid_card_targeting(generation)
		return
	_is_iron_chain_targeting = false
	await _execute_iron_chain(chosen)
	if generation != _card_target_generation: return
	_clear_pending_determined_card()
	_is_iron_chain_targeting = false
	_iron_chain_targets.clear()
	_cancel_target_btn.visible = false
	_restore_play_skill_buttons()

# 是否继续选第二名目标的确认
func _show_more_target_confirm(target_name: String, allowed: Callable = Callable()) -> int:
	if _game_over or (allowed.is_valid() and not allowed.call()): return CHOICE_INVALID
	var answer = ChoicePromptAnswer.new()
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
	yes_btn.pressed.connect(func(): answer.submit(1), CONNECT_ONE_SHOT)
	hbox.add_child(yes_btn)

	var no_btn = Button.new()
	no_btn.text = "只选 1 名"
	no_btn.custom_minimum_size = Vector2(160, 44)
	no_btn.pressed.connect(func(): answer.submit(0), CONNECT_ONE_SHOT)
	hbox.add_child(no_btn)

	return await _wait_choice_prompt(overlay, answer, allowed, false)

# 执行铁索连环：对每个目标切换连环状态
func _execute_iron_chain(targets: Array[Player]):
	var p = players[turn_manager.get_play_actor_idx()]
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
		var nullified = await _ask_nullification_chain_result("%s的【铁索连环】即将对 %s 生效，是否打出一张【无懈可击】？" % [p.player_name, t.player_name])
		if nullified == NullificationOutcome.INVALIDATED:
			break
		if not t.is_alive() or _is_kneeling(t):
			continue
		if nullified == NullificationOutcome.NULLIFIED:
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
		await chain.start()
		await _finish_damage_chain(chain)
		if chain.continuation_invalid:
			return CHOICE_INVALID
	_sync_all_ui()

func _play_duel(attacker: Player, target: Player):
	var response_revision = turn_manager.get_context_revision()
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
	var nullified = await _ask_nullification_chain_result("%s的【决斗】即将对 %s 生效，是否打出一张【无懈可击】？" % [attacker.player_name, target.player_name])
	if nullified == NullificationOutcome.INVALIDATED:
		return
	if nullified == NullificationOutcome.NULLIFIED:
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
		if _game_over or response_revision != turn_manager.get_context_revision() or not current.is_alive() or not other.is_alive() or _is_kneeling(current) or _is_kneeling(other):
			break
		var needs_two = jacqui != null and current != jacqui
		var can_respond = await _ask_basic_card_response_result(current, CardData.CardSubType.STRIKE, _show_duel_prompt.bind(needs_two))
		if _game_over or response_revision != turn_manager.get_context_revision() or not current.is_alive() or not other.is_alive() or _is_kneeling(current) or _is_kneeling(other):
			break

		if can_respond == BasicResponseOutcome.INVALIDATED:
			break
		if can_respond == BasicResponseOutcome.PAID:
			_update_debug("%s 出【杀】响应【决斗】" % current.player_name)
			# 【霸王】：对方还需打出第二张杀
			if needs_two:
				if not HandPayment.has_response(current, CardData.CardSubType.STRIKE):
					# 没有第二张杀 → 响应失败 → 受伤害
					_update_debug("%s 无法再出【杀】，在【决斗】中失败" % current.player_name)
					await _deal_damage(other, current, 1 + _rage_bonus(other), EffectChain.DamageType.PHYSICAL)
					break
				var cont = await _ask_basic_card_response_result(current, CardData.CardSubType.STRIKE, _show_duel_second_strike_prompt)
				if _game_over or response_revision != turn_manager.get_context_revision() or not current.is_alive() or not other.is_alive() or _is_kneeling(current) or _is_kneeling(other):
					break
				if cont == BasicResponseOutcome.INVALIDATED:
					break
				if cont == BasicResponseOutcome.PAID:
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
func _show_duel_prompt(needs_two: bool = false) -> int:
	if _duel_respond_override.is_valid():
		return 1 if _duel_respond_override.call() else 0
	if _game_over:
		return CHOICE_INVALID
	var answer = ChoicePromptAnswer.new()
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

	respond_btn.pressed.connect(answer.submit.bind(1), CONNECT_ONE_SHOT)
	skip_btn.pressed.connect(answer.submit.bind(0), CONNECT_ONE_SHOT)
	var result = await _wait_choice_prompt(overlay, answer)
	return 0 if result == -1 else result

# 【霸王】第二张杀询问（玩家0）：打出第一张杀后，询问是否继续响应
func _show_duel_second_strike_prompt() -> int:
	if _duel_second_override.is_valid():
		return 1 if _duel_second_override.call() else 0
	if _game_over:
		return CHOICE_INVALID
	var answer = ChoicePromptAnswer.new()
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

	cont_btn.pressed.connect(answer.submit.bind(1), CONNECT_ONE_SHOT)
	give_btn.pressed.connect(answer.submit.bind(0), CONNECT_ONE_SHOT)
	var result = await _wait_choice_prompt(overlay, answer)
	return 0 if result == -1 else result

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
# desc = 第一轮提示文本。兼容入口只报告是否抵消；生产链使用显式结果。
# 规则：有人打出无懈 → 再问所有人是否反无懈 → 交替直到无人响应
enum NullificationOutcome { PASSED, NULLIFIED, INVALIDATED }

func _ask_nullification_chain(desc: String) -> bool:
	return await _ask_nullification_chain_result(desc) == NullificationOutcome.NULLIFIED

func _ask_nullification_chain_result(desc: String, allowed: Callable = Callable()) -> NullificationOutcome:
	var pending: bool = false        # 当前是否有一张生效中的无懈
	var round_desc: String = desc
	var revision = turn_manager.get_context_revision()
	while true:
		var reply = await _ask_nullification_round_result(round_desc, allowed)
		if reply.outcome == NullificationOutcome.INVALIDATED or _game_over or revision != turn_manager.get_context_revision():
			return NullificationOutcome.INVALIDATED
		if reply.outcome == NullificationOutcome.PASSED:
			return NullificationOutcome.NULLIFIED if pending else NullificationOutcome.PASSED
		pending = not pending
		round_desc = "%s打出了1张【无懈可击】，是否打出一张【无懈可击】？" % reply.actor_name
	return NullificationOutcome.INVALIDATED

# 询问一轮：按座位顺序询问所有存活角色，返回打出无懈的玩家名（无人打出返回 ""）
func _ask_nullification_round(desc: String) -> String:
	var reply = await _ask_nullification_round_result(desc)
	return reply.actor_name if reply.outcome == NullificationOutcome.NULLIFIED else ""

func _ask_nullification_round_result(desc: String, allowed: Callable = Callable()) -> Dictionary:
	var revision = turn_manager.get_context_revision()
	var valid = func():
		return not _game_over and revision == turn_manager.get_context_revision() \
			and (not allowed.is_valid() or allowed.call())
	for i in range(player_count):
		if not valid.call():
			return {"outcome": NullificationOutcome.INVALIDATED, "actor_name": ""}
		var p = players[i]
		if not p.is_alive():
			continue
		# 【下跪】：无法使用或打出任何牌 → 不询问
		if _is_kneeling(p):
			continue
		var snapshot = HandSelection.new(p)
		var played = "skip"
		if p.seat_index == 0:
			played = await _show_nullification_prompt(desc, p, valid)
		else:
			var options: Array = [CardData.CardSubType.NULLIFICATION] if HandPayment.has_card(p, CardData.CardSubType.NULLIFICATION) else []
			if await _choose_ai_response(p, "nullification", options, {"description": desc}) == CardData.CardSubType.NULLIFICATION:
				played = "card"
		if played == "invalidated" or not valid.call():
			return {"outcome": NullificationOutcome.INVALIDATED, "actor_name": ""}
		if played != "skip":
			if not p.is_alive() or _is_kneeling(p) or p.hand != snapshot.hand or p.determined_cards != snapshot.determined:
				continue
			# 【是~啊~】（安普提·斯丢皮得）：确认使用无懈可击后询问是否发动（发动流失体力不消耗手牌；无手牌时取消 = 视为没有打出）
			var yes_ah = played
			if yes_ah == "card":
				yes_ah = await _ask_yes_ah(p, "无懈可击", HandPayment.has_card(p, CardData.CardSubType.NULLIFICATION), true)
			if yes_ah == "invalidated" or not valid.call():
				return {"outcome": NullificationOutcome.INVALIDATED, "actor_name": ""}
			if not p.is_alive() or _is_kneeling(p) or p.hand != snapshot.hand or p.determined_cards != snapshot.determined:
				continue
			if yes_ah == "cancel":
				_update_debug("%s 取消了打出【无懈可击】" % p.player_name)
				_sync_all_ui()
				return {"outcome": NullificationOutcome.PASSED, "actor_name": ""}
			var action_card: CardBase
			if yes_ah == "skill":
				var paid = await _pay_yes_ah_cost(p)
				if not valid.call():
					return {"outcome": NullificationOutcome.INVALIDATED, "actor_name": ""}
				if not paid:
					_sync_all_ui()
					return {"outcome": NullificationOutcome.PASSED, "actor_name": ""}
				action_card = CardBase.create(CardData.CardSubType.NULLIFICATION)
			else:
				var used_card = HandPayment.take_card(p, CardData.CardSubType.NULLIFICATION)
				if used_card == null:
					continue
				deck.discard(used_card)
				action_card = used_card
			_record_card_action(p, action_card, CardActionEvent.Kind.USE, yes_ah != "skill", yes_ah == "skill")
			_update_debug("%s 打出了【无懈可击】" % p.player_name)
			_sync_all_ui()
			# 【苕】任意玩家行动后询问是否明置
			await _maybe_ask_reveal()
			if not valid.call():
				return {"outcome": NullificationOutcome.INVALIDATED, "actor_name": ""}
			return {"outcome": NullificationOutcome.NULLIFIED, "actor_name": p.player_name}
	return {"outcome": NullificationOutcome.PASSED, "actor_name": ""}

# 玩家0的无懈响应弹窗（锚点居中）：返回 "card"（打出无懈，消耗手牌）/ "skill"（发动【是~啊~】打出，无手牌时）/ "skip"（放弃）
func _show_nullification_prompt(desc: String, p: Player, allowed: Callable = Callable()) -> String:
	var has_hand = HandPayment.has_card(p, CardData.CardSubType.NULLIFICATION)
	var is_yes_ah = p.general_name == "安普提·斯丢皮得"
	# 测试钩子只决定意愿；无匹配牌时仅安普提可通过【是~啊~】打出。
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
		label.text += "\n（无可用的无懈或任意牌，可发动【是~啊~】流失 1 点体力视为打出）"
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

	var answer = ChoicePromptAnswer.new()
	nullify_btn.pressed.connect(answer.submit.bind(1))
	skip_btn.pressed.connect(answer.submit.bind(0))
	var result = await _wait_choice_prompt(overlay, answer, allowed)
	if result == CHOICE_INVALID:
		return "invalidated"
	return ("card" if has_hand else "skill") if result == 1 else "skip"

# ---- 效果链回调 ----

signal _response_ready
signal _zone_pick_result(zone: String)
signal _equip_pick_result(slot: String)
signal _iron_chain_cfm_result(result: bool)
signal _mount_replace_result(slot: String)
signal _weapon_replace_result(result: bool)
signal _zhangba_result(value: int)
signal _calamity_target_result(target: Player)
# 灾厄袍转移目标选择结果（独立 signal，避免与灾厄剑并发干扰）
signal _calamity_robe_target_result(target: Player)
# 劣马转移目标选择结果（-1/+1 各自独立，避免并发干扰）
signal _minus_mule_target_result(target: Player)
signal _plus_mule_target_result(target: Player)

# 在一次杀使用/打出已经成立后登记；多目标只调用一次，效果链不重复登记。
func _record_strike_played(p: Player):
	var first := turn_manager.record_strike_played(p.seat_index)
	if first and p.is_alive() and p.get_weapon() == CardData.CardSubType.QINGLONG_BLADE:
		_draw_blank_cards(p, 1)
		_update_debug("%s 发动【青龙偃月刀】：本回合首次使用或打出【杀】，摸一张牌（手牌 %d 张）" % [p.player_name, p.hand_size()])

# 【八卦阵】：你每使用或打出一张【闪】时，摸一张牌（锁定技；装备者判定）
func _try_bagua_draw(p: Player):
	if p == null or not p.is_alive():
		return
	if p.get_armor() != CardData.CardSubType.BAGUA_ZHEN:
		return
	_draw_blank_cards(p, 1)
	_update_debug("%s 发动【八卦阵】：使用【闪】，摸一张牌（手牌 %d 张）" % [p.player_name, p.hand_size()])
	_sync_all_ui()

# C-L1：只在成为拆/顺目标时失去1体力，令该次牌对自己无效。
# 返回true即本次牌已被防止；求救结果不恢复已被防止的牌效果。
enum LiehuoOutcome { NOT_USED, PREVENTED, INVALIDATED }

func _try_liehuo_nullify(p: Player, sub: CardData.CardSubType, allowed: Callable = Callable()) -> bool:
	return await _try_liehuo_nullify_result(p, sub, allowed) == LiehuoOutcome.PREVENTED

func _try_liehuo_nullify_result(p: Player, sub: CardData.CardSubType, allowed: Callable = Callable()) -> LiehuoOutcome:
	if sub not in [CardData.CardSubType.SNATCH, CardData.CardSubType.DISMANTLE] \
			or p == null or not p.is_alive() or p.get_armor() != CardData.CardSubType.LIEHUO_SHIELD:
		return LiehuoOutcome.NOT_USED
	var shield = p.get_equipment_card("armor")
	var revision = turn_manager.get_context_revision()
	var valid = func():
		return not _game_over and p.is_alive() and players.has(p) \
			and revision == turn_manager.get_context_revision() \
			and (not allowed.is_valid() or allowed.call())
	if not valid.call():
		return LiehuoOutcome.INVALIDATED
	var use = await _ask_liehuo(p, valid)
	if use == CHOICE_INVALID or not valid.call():
		return LiehuoOutcome.INVALIDATED
	# 原盾离区属于未能发动，不是取消整个拆/顺；保留C02既有行为。
	if use != 1 or p.get_equipment_card("armor") != shield:
		return LiehuoOutcome.NOT_USED
	p.hp -= 1
	_update_debug("%s 发动【烈火盾】：失去1点体力，【%s】对其无效（%d/%d）" % [p.player_name, CardData.get_type_name(sub), p.hp, p.max_hp])
	_sync_all_ui()
	if p.is_dying():
		await _resolve_dying(p, null, "liehuo")
	return LiehuoOutcome.PREVENTED

# 询问是否发动烈火盾：玩家0弹窗，AI 默认不发动
func _ask_liehuo(p: Player, allowed: Callable = Callable()) -> int:
	if _liehuo_override.is_valid():
		return 1 if await _liehuo_override.call() else 0
	if p.seat_index == 0:
		return await _show_liehuo_prompt(allowed)
	return 0  # AI 暂不主动发动

# 玩家0的【烈火盾】响应弹窗（锚点居中）
func _show_liehuo_prompt(allowed: Callable = Callable()) -> int:
	# 测试钩子：跳过 UI 直接返回
	if _liehuo_override.is_valid():
		return 1 if await _liehuo_override.call() else 0

	var answer = ChoicePromptAnswer.new()
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
	label.text = "【烈火盾】！你成为拆/顺的目标\n是否失去1点体力，使此牌对你无效？"
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
	pay_btn.text = "失去1点体力，令此牌无效"
	pay_btn.custom_minimum_size = Vector2(180, 44)
	hbox.add_child(pay_btn)

	var lose_btn = Button.new()
	lose_btn.text = "不发动，继续结算"
	lose_btn.custom_minimum_size = Vector2(180, 44)
	lose_btn.modulate = Color(0.7, 0.7, 0.7)
	hbox.add_child(lose_btn)

	pay_btn.pressed.connect(func(): answer.submit(1))
	lose_btn.pressed.connect(func(): answer.submit(0))
	# E03-Q2：响应超时不发动；关闭/过期仍明确失效。
	var result = await _wait_choice_prompt(overlay, answer, allowed)
	return 0 if result == -1 else result

func _on_chain_response_check(chain: EffectChain, responder: Player, expected_sub: CardData.CardSubType, attacker: Player) -> bool:
	if expected_sub != CardData.CardSubType.DODGE:
		return false
	var revision = turn_manager.get_context_revision()
	var prompt = _show_dodge_prompt.bind(attacker.player_name if attacker != null else "已失去来源的效果", "杀")
	var dodged = await _ask_basic_card_response_result(responder, expected_sub, prompt, _dodge_override)
	if dodged == BasicResponseOutcome.INVALIDATED or _game_over or revision != turn_manager.get_context_revision() or not responder.is_alive():
		chain.is_cancelled = true
		return false
	return dodged == BasicResponseOutcome.PAID

func _show_dodge_prompt(attacker_name: String, card_name: String) -> int:
	if _game_over:
		return CHOICE_INVALID
	var answer = ChoicePromptAnswer.new()
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

	dodge_btn.pressed.connect(answer.submit.bind(1), CONNECT_ONE_SHOT)
	skip_btn.pressed.connect(answer.submit.bind(0), CONNECT_ONE_SHOT)
	var result = await _wait_choice_prompt(overlay, answer)
	return 0 if result == -1 else result

signal _target_cfm_result(result: bool)

# 选择目标后的确认弹窗
func _show_target_confirm(attacker_name: String, target_name: String, sub: CardData.CardSubType, allowed: Callable = Callable()) -> int:
	# 测试钩子：跳过 UI 直接返回
	if _target_confirm_override.is_valid():
		var reply = await _target_confirm_override.call()
		if typeof(reply) == TYPE_INT and reply == CHOICE_INVALID: return CHOICE_INVALID
		return 1 if reply else 0
	if _game_over or (allowed.is_valid() and not allowed.call()): return CHOICE_INVALID
	var answer = ChoicePromptAnswer.new()

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

	yes_btn.pressed.connect(func(): answer.submit(1), CONNECT_ONE_SHOT)
	no_btn.pressed.connect(func(): answer.submit(0), CONNECT_ONE_SHOT)
	return await _wait_choice_prompt(overlay, answer, allowed, false)

func _on_chain_trigger(chain: EffectChain, event_name: String, subject: Player, source: Player, data: Dictionary) -> bool:
	var record = chain.damage
	if event_name == "on_being_targeted":
		return not await _prepare_strike_target(source, subject, chain.ignore_target_restrictions)

	if event_name == "before_deal_damage":
		if record.source_modifiers_applied:
			return false
		record.source_modifiers_applied = true
		var actual = chain.target_player
		if subject == null or record.is_chain:
			return false
		var weapon = subject.get_weapon()
		var weapon_enabled = actual.get_armor() != CardData.CardSubType.QINGGANG_SHIELD
		if record.from_strike and weapon_enabled:
			if weapon == CardData.CardSubType.ICE_SWORD and actual.hand_size() > 0:
				# E03e-6-Q1：不足两张时弃置全部现有手牌。
				var original_weapon = subject.get_equipment_card("weapon")
				var revision = turn_manager.get_context_revision()
				var hit_valid = func():
					return not _game_over and not chain.is_cancelled \
						and revision == turn_manager.get_context_revision() \
						and players.has(actual) and actual.is_alive() and chain.target_player == actual
				var choice_valid = func():
					return hit_valid.call() and players.has(subject) and subject.is_alive() \
						and record.source == subject and subject.get_weapon() == CardData.CardSubType.ICE_SWORD \
						and subject.get_equipment_card("weapon") == original_weapon \
						and actual.get_armor() != CardData.CardSubType.QINGGANG_SHIELD
				var chosen = 1 if subject.seat_index != 0 else await _ask_ice_sword(actual.player_name, choice_valid)
				if not hit_valid.call():
					chain.is_cancelled = true
					return true
				if subject.is_dead():
					record.refresh_source() # TIME-04：不发动寒冰，原伤害无源继续。
					return false
				if chosen == CHOICE_INVALID or not choice_valid.call():
					chain.is_cancelled = true
					return true
				var discard_count = mini(2, actual.hand_size())
				if chosen == 1 and discard_count > 0 and _discard_hand_cards(actual, discard_count):
					_update_debug("%s 发动【寒冰剑】：防止本次伤害，弃置 %s %d张手牌" % [subject.player_name, actual.player_name, discard_count])
					_sync_all_ui()
					return true
			if weapon == CardData.CardSubType.ZHANGBA_SPEAR:
				var original_weapon = subject.get_equipment_card("weapon")
				var revision = turn_manager.get_context_revision()
				var hit_valid = func():
					return not _game_over and not chain.is_cancelled \
						and revision == turn_manager.get_context_revision() \
						and players.has(actual) and actual.is_alive() and chain.target_player == actual
				var choice_valid = func():
					return hit_valid.call() and players.has(subject) and subject.is_alive() \
						and record.source == subject and subject.get_weapon() == CardData.CardSubType.ZHANGBA_SPEAR \
						and subject.get_equipment_card("weapon") == original_weapon \
						and actual.get_armor() != CardData.CardSubType.QINGGANG_SHIELD
				var chosen = await _ask_zhangba_extra(subject, choice_valid)
				if not hit_valid.call():
					chain.is_cancelled = true
					return true
				# TIME-04：等待中来源最终死亡，不能发动/支付丈八，原杀余伤无源继续。
				if subject.is_dead():
					record.refresh_source()
					return false
				if chosen < 0 or not choice_valid.call():
					chain.is_cancelled = true
					return true
				var extra = clampi(chosen, 0, 3)
				if extra > 0:
					var rage_before = _rage_bonus(subject)
					subject.hp -= extra
					_update_debug("%s 流失 %d 点体力（发动【丈八蛇矛】，尚未造成伤害）" % [subject.player_name, extra])
					if subject.is_dying():
						await _resolve_dying(subject, null, "zhangba", chain)
					# 已付费用不回滚；救援后来源死亡/武器离区不撤销已付加伤。
					if not hit_valid.call():
						chain.is_cancelled = true
						return true
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
		var paixiong = await _try_paixiong_block(subject, source)
		if paixiong == PaixiongOutcome.PREVENTED:
			data["value"] = 0
			return true
		if paixiong == PaixiongOutcome.INVALIDATED:
			chain.is_cancelled = true
			return true
		# 选择期间来源可能最终死亡；后续目标侧效果只能读取当前来源。
		record.refresh_source()
		source = record.source
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
		var fate_revision = turn_manager.get_context_revision()
		var fate_valid = func():
			return not _game_over and fate_revision == turn_manager.get_context_revision() \
				and players.has(subject) and subject.is_alive() and chain.target_player == subject
		var fate_reply = await _try_fate_blade_save(subject, data["value"], fate_valid)
		if fate_reply == CHOICE_INVALID:
			chain.is_cancelled = true
			return true
		if fate_reply == 1:
			data["value"] = 0
			return true
		record.refresh_source()
		source = record.source
		if data["value"] > 0 and not record.sacrifice_offered:
			record.sacrifice_offered = true
			var revision = turn_manager.get_context_revision()
			var valid = func():
				return not _game_over and revision == turn_manager.get_context_revision() \
					and subject.is_alive() and chain.target_player == subject
			var reply = await _maybe_sacrifice_result(source, subject, data["value"], chain.damage_element, valid)
			if reply.invalidated or not valid.call():
				chain.is_cancelled = true
				return true
			var substitute: Player = reply.player
			if substitute != null:
				record.transfer_target = substitute
				record.transfer_amount = data["value"]
				_update_debug("%s 使用【舍己为人】：防止 %s 的此次伤害，随后承受独立新伤害" % [substitute.player_name, subject.player_name])
				return true

	if event_name == "damage_applied":
		_update_debug("%s 受到 %d 点伤害" % [subject.player_name, data["damage"]])
		_sync_all_ui()
		if subject.is_dying():
			await _resolve_dying(subject, source, "damage", chain)
		# before_death checkpoint 也可能救回目标；重查被普通救援延后的终局。
		_check_win_condition(null, null)
		return false

	if event_name == "after_deal_damage" and subject != null and subject.is_alive():
		_trigger_pofeng(subject, data["damage"])
		var post_revision = turn_manager.get_context_revision()
		await _try_gou_lian_claw(subject, chain.target_player)
		if _game_over or post_revision != turn_manager.get_context_revision():
			chain.is_cancelled = true
			return true
		record.refresh_source()
		if subject.is_dead() or not chain.target_player.is_alive():
			return false
		var blood_result = await _try_bloodthirsty(subject, chain.target_player, data["damage"])
		if _game_over or post_revision != turn_manager.get_context_revision():
			chain.is_cancelled = true
			return true
		record.refresh_source()
		if blood_result == CHOICE_INVALID or subject.is_dead() or not chain.target_player.is_alive():
			return false
		# EQ-06：首次达到阈值的整次伤害只激活，从下一次伤害才按点发动。
		var soul_original = subject.get_equipment_card("weapon")
		var soul_was_active = subject.get_weapon() == CardData.CardSubType.SOUL_BLADE and subject.soul_blade_activated
		_update_soul_blade_count(subject, chain.target_player, data["damage"])
		if soul_was_active and record.from_strike and not record.is_chain:
			for point in data["damage"]:
				if _game_over or post_revision != turn_manager.get_context_revision() \
						or not players.has(subject) or not players.has(chain.target_player) \
						or not subject.is_alive() or not chain.target_player.is_alive() \
						or subject.get_equipment_card("weapon") != soul_original:
					chain.continuation_invalid = true
					return true
				if await _try_soul_blade(subject, chain.target_player) == CHOICE_INVALID:
					chain.continuation_invalid = true
					return true
		if await _try_kaiwen_deal(subject, chain.target_player, data["damage"]) == CHOICE_INVALID:
			chain.continuation_invalid = true
			return true

	if event_name == "after_take_damage" and subject != null and subject.is_alive():
		await _try_thorn_counter(subject, source, data["damage"])
		if await _try_kaiwen_receive(subject, source, data["damage"]) == CHOICE_INVALID:
			chain.continuation_invalid = true
			return true
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
func _try_kaiwen_receive(victim: Player, source: Player, amount: int) -> int:
	return await _try_kaiwen_ping(victim, source, amount, true)

# 造成伤害时：source 是凯文，与受伤目标 victim 拼点，赢摸两张
func _try_kaiwen_deal(source: Player, victim: Player, amount: int) -> int:
	return await _try_kaiwen_ping(victim, source, amount, false)

# 核心：可选发动（玩家0弹窗 / AI 默认发动），按伤害点数逐点触发，赢摸两张
# is_receive = true 表示凯文是受伤方（victim），false 表示凯文是伤害来源（source）
func _try_kaiwen_ping(victim: Player, source: Player, amount: int, is_receive: bool) -> int:
	var kaiwen: Player = victim if is_receive else source
	var opponent: Player = source if is_receive else victim
	if kaiwen == null or opponent == null or kaiwen == opponent:
		return 0
	if kaiwen.general_name != "凯文·罗本":
		return 0
	if not kaiwen.is_alive() or not opponent.is_alive():
		return 0
	var revision = turn_manager.get_context_revision()
	var valid = func():
		return not _game_over and revision == turn_manager.get_context_revision() \
			and players.has(kaiwen) and players.has(opponent) \
			and kaiwen.is_alive() and opponent.is_alive() and kaiwen.general_name == "凯文·罗本"
	for i in amount:
		if not valid.call():
			return CHOICE_INVALID
		# 伤害效果先展示（日志 + 体力变化），稍作停顿再询问是否发动
		if not _kaiwen_override.is_valid():
			await get_tree().create_timer(0.8).timeout
		if not valid.call():
			return CHOICE_INVALID
		var use = await _ask_kaiwen(kaiwen, opponent, is_receive, valid)
		if use == CHOICE_INVALID or not valid.call():
			return CHOICE_INVALID
		if use == 0:
			continue
		# 拼点结果（出拳 + 胜负，按胜负着色）由 _do_ping_dian_once 输出，这里不再补日志覆盖它
		var r = await _do_ping_dian(kaiwen, opponent, valid)
		if r == RPS_INVALID or not valid.call():
			return CHOICE_INVALID
		if r == RPS_WIN:
			_draw_blank_cards(kaiwen, 2)
	_sync_all_ui()
	return 0

# 询问是否发动【你个壊货】：玩家0弹窗，AI 默认发动（摸牌收益）
func _ask_kaiwen(kaiwen: Player, opponent: Player, is_receive: bool, allowed: Callable = Callable()) -> int:
	if _kaiwen_override.is_valid():
		var reply = await _kaiwen_override.call()
		return CHOICE_INVALID if typeof(reply) == TYPE_INT and reply == CHOICE_INVALID else (1 if reply else 0)
	if kaiwen.seat_index == 0:
		return await _show_kaiwen_prompt(opponent.player_name, is_receive, allowed)
	return 1

func _show_kaiwen_prompt(opponent_name: String, is_receive: bool, allowed: Callable = Callable()) -> int:
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

	var answer = ChoicePromptAnswer.new()
	use_btn.pressed.connect(func():
		answer.submit(1)
	, CONNECT_ONE_SHOT)
	skip_btn.pressed.connect(func():
		answer.submit(0)
	, CONNECT_ONE_SHOT)

	var result = await _wait_choice_prompt(overlay, answer, allowed)
	return CHOICE_INVALID if result == CHOICE_INVALID else (1 if result == 1 else 0)

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
	var revision = turn_manager.get_context_revision()
	chain.skip_targeting = true
	chain.skip_response = true
	await chain.start()
	await _finish_damage_chain(chain)
	if chain.continuation_invalid:
		return chain.damage.final_damage().target
	if chain.damage.final_damage().committed:
		if _game_over or revision != turn_manager.get_context_revision():
			return chain.damage.final_damage().target
		if await _try_calamity_transfer(chain.source_player) == CHOICE_INVALID:
			return chain.damage.final_damage().target
	await _maybe_ask_reveal()
	return chain.damage.final_damage().target

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
# 1=已付费用防止，0=未触发/自愿拒绝，CHOICE_INVALID=等待失效。
func _try_fate_blade_save(victim: Player, amount: int, allowed: Callable = Callable()) -> int:
	if victim == null or not victim.is_alive():
		return 0
	if victim.get_weapon() != CardData.CardSubType.FATE_BLADE:
		return 0
	if amount <= 0 or amount < victim.hp:
		return 0  # 非致命伤害，不触发
	var original_weapon = victim.get_equipment_card("weapon")
	var revision = turn_manager.get_context_revision()
	var valid = func():
		return not _game_over and revision == turn_manager.get_context_revision() \
			and players.has(victim) and victim.is_alive() and amount >= victim.hp \
			and victim.get_weapon() == CardData.CardSubType.FATE_BLADE \
			and original_weapon != null and victim.get_equipment_card("weapon") == original_weapon \
			and (not allowed.is_valid() or allowed.call())
	if not valid.call():
		return CHOICE_INVALID

	var use = await _ask_fate_blade(victim, valid)
	if use == CHOICE_INVALID or not valid.call():
		return CHOICE_INVALID
	if use != 1:
		return 0

	# 弃置命运之刃（进入弃牌堆）；装备占用永久保留（唯一性规则）
	var fate_blade = victim.remove_equipment("weapon")
	deck.discard(fate_blade)
	_update_debug("%s 弃置【命运之刃】，防止了 %d 点致命伤害！" % [victim.player_name, amount])
	_sync_all_ui()
	return 1

# 询问是否发动命运之刃：玩家0弹窗，AI 默认发动（保命）
func _ask_fate_blade(victim: Player, allowed: Callable = Callable()) -> int:
	if victim.seat_index == 0:
		return await _show_fate_blade_prompt(victim, allowed)
	return 1  # AI 默认发动

# 玩家0的【命运之刃】响应弹窗（锚点居中）
func _show_fate_blade_prompt(victim: Player, allowed: Callable = Callable()) -> int:
	# 测试钩子：只决定「是否弃置」，没装备照样弃不了
	if _fate_blade_override.is_valid():
		var reply = await _fate_blade_override.call()
		return CHOICE_INVALID if typeof(reply) == TYPE_INT and reply == CHOICE_INVALID else (1 if reply else 0)
	var answer = ChoicePromptAnswer.new()

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

	use_btn.pressed.connect(func(): answer.submit(1))
	skip_btn.pressed.connect(func(): answer.submit(0))
	return await _wait_choice_prompt(overlay, answer, allowed, false)

# ============================
#  【勾镰爪】获得坐骑
# ============================

# 对一名角色造成伤害后，可获得其装备区里的一张坐骑牌（进入自己「已确定的牌」区）
# 在普通伤害后触发；目标仍不能行动或与自己相同（舍己为人自转移）不触发。
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
	var original_weapon = source.get_equipment_card("weapon")
	var originals: Dictionary = {}
	for candidate in slots:
		originals[candidate] = _equipment_resource_for_pick(victim, candidate)
	var revision = turn_manager.get_context_revision()
	var valid = func():
		return not _game_over and revision == turn_manager.get_context_revision() \
			and players.has(source) and source.is_alive() and players.has(victim) and victim.is_alive() \
			and source.get_weapon() == CardData.CardSubType.GOU_LIAN_CLAW \
			and source.get_equipment_card("weapon") == original_weapon \
			and victim.get_armor() != CardData.CardSubType.QINGGANG_SHIELD

	var slot: String
	if source.seat_index == 0:
		slot = await _ask_gou_lian_slot(victim, slots, valid)
		if slot == "":
			return
		if slot == "cancel":
			_update_debug("%s 放弃发动【勾镰爪】" % source.player_name)
			return
	else:
		# AI 默认发动，随机选一匹
		slot = slots[ai_driver.rng.randi_range(0, slots.size() - 1)]

	if not valid.call() or not originals.has(slot) or originals[slot] == null \
			or _equipment_resource_for_pick(victim, slot) != originals[slot]:
		return
	var sub = victim.equipment[slot]
	var card = victim.remove_equipment(slot)
	if card == null:
		return
	source.determined_cards.append(card)
	if sub == CardData.CardSubType.HIDDEN_EQUIPMENT:
		# 已完成获得，再由原持有者声明；失效不撤销已经发生的移动。
		var declaration_valid = func():
			return not _game_over and revision == turn_manager.get_context_revision() \
				and players.has(source) and source.is_alive() and players.has(victim) and victim.is_alive() \
				and source.determined_cards.has(card) and card.sub_type == CardData.CardSubType.HIDDEN_EQUIPMENT
		await _declare_stolen_hidden_equipment(victim, source, card, declaration_valid)
		sub = card.sub_type
	_update_debug("%s 发动【勾镰爪】：获得 %s 的坐骑【%s】（已确定的牌 %d 张）" % [
		source.player_name, victim.player_name, CardData.get_type_name(sub), source.determined_cards.size()
	])
	_sync_all_ui()

# 玩家0选择坐骑：独立答复；cancel是主动放弃，空串是失效，沿用无计时。
func _ask_gou_lian_slot(victim: Player, slots: Array[String], allowed: Callable = Callable()) -> String:
	var candidates: Array[String] = []
	var originals: Dictionary = {}
	for slot in slots:
		if Player.MOUNT_SLOTS.has(slot):
			var card = _equipment_resource_for_pick(victim, slot)
			if card != null:
				candidates.append(slot)
				originals[slot] = card
	var revision = turn_manager.get_context_revision()
	var valid = func():
		return not _game_over and revision == turn_manager.get_context_revision() \
			and players.has(victim) and victim.is_alive() \
			and (not allowed.is_valid() or allowed.call()) \
			and candidates.any(func(slot): return _equipment_resource_for_pick(victim, slot) == originals[slot])
	if not valid.call():
		return ""
	# 测试钩子：直接返回槽位或 "cancel"
	if _gou_lian_slot_override.is_valid():
		var reply = await _gou_lian_slot_override.call()
		if not valid.call() or not reply is String:
			return ""
		return reply if reply == "cancel" or (originals.has(reply) and _equipment_resource_for_pick(victim, reply) == originals[reply]) else ""
	var answer = ChoicePromptAnswer.new()
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
	label.text = "你造成了伤害\n选择要获得的坐骑（可取消）："
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
	for index in candidates.size():
		var slot = candidates[index]
		var btn = Button.new()
		btn.text = "%s：%s" % [Player.EQUIP_SLOT_NAMES[slot], CardData.get_type_name(victim.equipment[slot])]
		btn.custom_minimum_size = Vector2(160, 44)
		btn.pressed.connect(func(): answer.submit(index))
		hbox.add_child(btn)
	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(160, 44)
	cancel_btn.modulate = Color(0.7, 0.7, 0.7)
	cancel_btn.pressed.connect(func(): answer.submit(-1))
	vbox.add_child(cancel_btn)
	var result = await _wait_choice_prompt(overlay, answer, valid, false)
	if result == CHOICE_INVALID or not valid.call():
		return ""
	if result == -1:
		return "cancel"
	if result < 0 or result >= candidates.size():
		return ""
	var selected = candidates[result]
	return selected if _equipment_resource_for_pick(victim, selected) == originals[selected] else ""

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
func _rps_choice(p: Player, other_name: String, allowed: Callable = Callable()) -> int:
	if _rps_override.is_valid():
		return _rps_override.call(p)
	if p.seat_index == 0:
		return await _show_rps_prompt(p, other_name, allowed)
	return randi() % 3

# 玩家0的猜拳弹窗（石头/剪刀/布，锚点居中）
func _show_rps_prompt(p: Player, other_name: String, allowed: Callable = Callable()) -> int:
	if _game_over or (allowed.is_valid() and not allowed.call()):
		return RPS_INVALID
	var answer = ChoicePromptAnswer.new()
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
		var gesture: int = c[1]
		btn.pressed.connect(func(): answer.submit(gesture), CONNECT_ONE_SHOT)
		hbox.add_child(btn)

	var result = await _wait_choice_prompt(overlay, answer, allowed)
	# 正常超时沿用布；关闭或上下文失效不能落到该默认。
	return RPS_PAPER if result == -1 else result

# 进行一次拼点（猜拳一轮）：返回发起者视角结果（RPS_WIN / RPS_DRAW / RPS_LOSE）
# 结果只在实时日志显示（上一行），不覆盖中间提示句（当前进行）——所有拼点统一行为
func _do_ping_dian_once(challenger: Player, opponent: Player, allowed: Callable = Callable()) -> int:
	if allowed.is_valid() and not allowed.call():
		return RPS_INVALID
	var a = await _rps_choice(challenger, opponent.player_name, allowed)
	if a == RPS_INVALID or (allowed.is_valid() and not allowed.call()):
		return RPS_INVALID
	var b = await _rps_choice(opponent, challenger.player_name, allowed)
	if b == RPS_INVALID or (allowed.is_valid() and not allowed.call()):
		return RPS_INVALID
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
func _do_ping_dian(challenger: Player, opponent: Player, allowed: Callable = Callable()) -> int:
	var r = await _do_ping_dian_once(challenger, opponent, allowed)
	while r == RPS_DRAW:
		_update_debug("平局，继续拼点！")
		r = await _do_ping_dian_once(challenger, opponent, allowed)
	return r

# 已支付费用不回滚；旧阶段/行动者或死去的目标不能继续拼点及其技能伤害。
func _paid_skill_rps_valid(actor: Player, target: Player, revision: int) -> bool:
	return not _game_over and revision == turn_manager.get_context_revision() \
		and turn_manager.current_phase == TurnManager.Phase.PLAY \
		and turn_manager.get_play_actor_idx() >= 0 and turn_manager.get_play_actor_idx() < players.size() \
		and players[turn_manager.get_play_actor_idx()] == actor \
		and actor.is_alive() and (target == null or (target.is_alive() and not _is_kneeling(target)))

# ============================
#  【是~啊~】锦囊白嫖（安普提·斯丢皮得）
# ============================

# 使用锦囊牌时询问是否发动【是~啊~】：
# has_hand = 当前是否有手牌可消耗；返回 "skill"（发动，流失体力不消耗手牌）/ "card"（不发动，照常消耗）/ "cancel"（取消，视为没有打出）
func _ask_yes_ah(p: Player, card_name: String, has_hand: bool, preserve_invalid: bool = false) -> String:
	# 明确点击了已确定牌时必须使用该原牌，不能改以技能虚拟使用并把原牌留在手中。
	if _pending_determined_card != null:
		return "card"
	if p.general_name != "安普提·斯丢皮得" or not p.is_alive():
		return "card" if has_hand else "cancel"
	if _yes_ah_override.is_valid():
		return _yes_ah_override.call()
	if p.seat_index != 0:
		return "card" if has_hand else "cancel"  # AI 暂不发动
	return await _show_yes_ah_prompt(card_name, has_hand, preserve_invalid)

# 玩家0 的【是~啊~】询问弹窗（复用通用选择弹窗）
func _show_yes_ah_prompt(card_name: String, has_hand: bool, preserve_invalid: bool = false) -> String:
	var idx = await _show_choice_popup("是否发动【是~啊~】？\n（流失 1 点体力，视为使用了一张【%s】，不消耗手牌）" % card_name, ["发动【是~啊~】", "不发动（消耗手牌）" if has_hand else "取消（视为没有打出）"])
	if preserve_invalid and idx == CHOICE_INVALID:
		return "invalidated"
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
		await _resolve_dying(p, null, "yes_ah") # 流失致死无击杀者
	return p.is_alive()

# 取得本次使用的锦囊资源，不决定其去向。延时锦囊直接入判定区，不能同时进弃牌堆。
func _take_trick_card(p: Player, sub: CardData.CardSubType) -> CardBase:
	if _yes_ah_active:
		_yes_ah_active = false
		var revision = turn_manager.get_context_revision()
		if not await _pay_yes_ah_cost(p):
			return null
		if _game_over or revision != turn_manager.get_context_revision():
			return null
		return CardBase.create(sub)
	var card = _take_play_card(p, sub)
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
	_record_card_action(p, card, CardActionEvent.Kind.USE, not virtual_use, virtual_use)
	return true

# ============================
#  【苕】暗置装备（安普提·斯丢皮得）
# ============================

# 点击技能【苕】：未暗置 → 选类型暗置；已暗置 → 明置 / 取消。
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
			idx = await _show_choice_popup("你已暗置了一件装备\n要做什么？", ["明置装备", "暂不明置"])
		if idx == 0:
			await _do_sao_reveal(p)
		return
	await _do_sao_hide(p, false)

# 暗置：选类型 → 检查槽位与手牌来源 → 支付一张 → 放置暗置资源。
func _do_sao_hide(p: Player, replace: bool) -> void:
	if not _can_use_play_skill(p):
		return
	# 已裁定放入哪类装备位便不能改为另一类；兼容旧调用参数但不允许替换。
	if replace or p.has_hidden_equip():
		_update_debug("已暗置的装备不能更换类别")
		return
	if p.hand_size() == 0:
		_update_debug("没有手牌，无法暗置装备")
		return
	var hide_context = turn_manager.get_context_revision()
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
	if _game_over or not p.is_alive() or not turn_manager.can_play_card() \
			or turn_manager.get_play_actor_idx() != p.seat_index \
			or turn_manager.get_context_revision() != hide_context or p.has_hidden_equip():
		return
	var source: CardBase = null
	var blank_index = p.hand.find(null)
	if blank_index >= 0:
		p.hand.remove_at(blank_index)
		source = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
	else:
		var matching: Array[CardBase] = []
		for card in p.hand + p.determined_cards:
			if card != null and CardData.get_equipment_slot_type(card.sub_type) == etype:
				matching.append(card)
		# 多张不同具体牌需要选原牌；当前入口没有选择窗口，不代玩家决定。
		if matching.size() != 1:
			_update_debug("没有唯一可选择的该类具体装备牌，未暗置")
			return
		source = matching[0]
		p.remove_from_hand(source)
		source.hidden_original_sub_type = source.sub_type
		source.sub_type = CardData.CardSubType.HIDDEN_EQUIPMENT
		source.card_name = CardData.get_type_name(CardData.CardSubType.HIDDEN_EQUIPMENT)
		source.description = ""
	source.hidden_category = etype
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
	p.equipment_cards[slot] = source
	p.hidden_equip_slot = slot
	p.hidden_equip_card = source
	_record_card_action(p, source)
	_discard_exhausted_hidden_category(etype)
	if p.get_hidden_equipment_card(slot) == source:
		_update_debug("%s 发动【苕】：暗置了一件%s——你装备了一件装备" % [p.player_name, type_name])
	_sync_all_ui()
	_refresh_detail_popup()

# 明置：选择具体装备（未被装备过的武器/防具；马全部可选）
func _do_sao_reveal(p: Player) -> void:
	if not p.has_hidden_equip():
		return
	var reveal_context = turn_manager.get_context_revision()
	var hidden_slots: Array[String] = []
	for slot in Player.EQUIP_SLOTS:
		if p.get_hidden_equipment_card(slot) != null:
			hidden_slots.append(slot)
	if hidden_slots.is_empty():
		return
	var hidden_sources: Array[CardBase] = []
	for slot in hidden_slots:
		hidden_sources.append(p.get_hidden_equipment_card(slot))
	var reveal_slot = hidden_slots[0]
	var selected_index: int = 0
	if hidden_slots.size() > 1:
		var selected: int = -1
		if _sao_reveal_slot_override.is_valid():
			selected = _sao_reveal_slot_override.call(hidden_slots.duplicate())
		elif p.seat_index == 0:
			var labels: Array = []
			for slot in hidden_slots:
				labels.append("武器位" if slot == "weapon" else ("防具位" if slot == "armor" else "坐骑位%s" % slot.trim_prefix("mount_")))
			selected = await _show_choice_popup("选择要明置的暗置装备槽位：", labels)
		if selected < 0 or selected >= hidden_slots.size():
			return
		selected_index = selected
		reveal_slot = hidden_slots[selected]
	var source = p.get_hidden_equipment_card(reveal_slot)
	if source == null or source != hidden_sources[selected_index]:
		return
	if _game_over or not p.is_alive() \
			or turn_manager.get_context_revision() != reveal_context:
		return
	var options = _hidden_declaration_options(source)
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
	if _game_over or not p.is_alive() \
			or turn_manager.get_context_revision() != reveal_context \
			or p.get_hidden_equipment_card(reveal_slot) != source:
		return
	_reveal_hidden_slot_as(p, reveal_slot, source, chosen)

# 执行明置：占位变为具体装备（武器/防具进唯一性占用；坐骑按类型计数）
func _reveal_hidden_as(p: Player, sub: CardData.CardSubType) -> bool:
	var slot = p.hidden_equip_slot
	var source = p.hidden_equip_card
	return _reveal_hidden_slot_as(p, slot, source, sub)

func _reveal_hidden_slot_as(p: Player, slot: String, source: CardBase,
		sub: CardData.CardSubType) -> bool:
	if slot == "" or source == null:
		return false
	if p.get_hidden_equipment_card(slot) != source:
		return false
	var slot_type = "mount" if Player.MOUNT_SLOTS.has(slot) else slot
	if CardData.get_equipment_slot_type(sub) != slot_type \
			or source.hidden_category != slot_type \
			or source.sub_type != CardData.CardSubType.HIDDEN_EQUIPMENT \
			or (source.hidden_original_sub_type >= 0 and source.hidden_original_sub_type != sub):
		return false
	if slot_type != "mount" and not _can_declare_hidden_name(source, sub):
		return false
	p.remove_equipment(slot)
	source.sub_type = sub
	source.card_name = CardData.get_type_name(sub)
	source.description = CardData.CARD_DESCRIPTIONS.get(sub, "")
	if not p.equip_card_to_slot(slot, source):
		source.sub_type = CardData.CardSubType.HIDDEN_EQUIPMENT
		source.card_name = CardData.get_type_name(source.sub_type)
		source.description = ""
		p.equip_hidden_card_to_slot(slot, source)
		return false
	source.hidden_category = ""
	source.hidden_original_sub_type = -1
	if sub != CardData.CardSubType.MOUNT_PLUS and sub != CardData.CardSubType.MOUNT_MINUS \
			and sub != CardData.CardSubType.MULE_PLUS and sub != CardData.CardSubType.MULE_MINUS:
		_claim_equipment_name(sub, source)
	_update_debug("%s 明置了暗置装备：装备了【%s】" % [p.player_name, CardData.get_type_name(sub)])
	_sync_all_ui()
	_refresh_detail_popup()
	return true

# C-S1～3：抢先只适用于其他角色尚未成功声明的唯一武器/防具。
# true 表示原装备动作应停止（已被抢先，或等待后动作失效）；从未先收取手牌。
func _try_sao_preempt(equipper: Player, sub: CardData.CardSubType, type_key: String) -> bool:
	if not ["weapon", "armor"].has(type_key) or equipment_pool.is_claimed(sub):
		return false
	var revision = turn_manager.get_context_revision()
	var snapshot = HandSelection.new(equipper)
	var pending = _pending_determined_card
	var old_equipment = _equipment_resource_for_pick(equipper, type_key)
	var action_valid = func():
		return not _game_over and players.has(equipper) and equipper.is_alive() and not _is_kneeling(equipper) \
			and turn_manager.can_play_card() and turn_manager.get_play_actor_idx() == equipper.seat_index \
			and turn_manager.get_context_revision() == revision \
			and equipper.hand == snapshot.hand and equipper.determined_cards == snapshot.determined \
			and _pending_determined_card == pending and _has_play_card(equipper, sub) \
			and _equipment_resource_for_pick(equipper, type_key) == old_equipment
	if not action_valid.call():
		return true
	for owner in players:
		if owner == equipper or owner.general_name != "安普提·斯丢皮得" or not owner.is_alive():
			continue
		var original = owner.get_hidden_equipment_card(type_key)
		if original == null or not _hidden_declaration_options(original).has(sub):
			continue
		var owner_valid = func():
			return players.has(owner) and owner.is_alive() and owner.general_name == "安普提·斯丢皮得" \
				and owner.get_hidden_equipment_card(type_key) == original \
				and not equipment_pool.is_claimed(sub) and _hidden_declaration_options(original).has(sub)
		var choice_valid = func(): return action_valid.call() and owner_valid.call()
		var accepted = 0
		if _sao_reveal_override.is_valid():
			var reply = await _sao_reveal_override.call()
			accepted = CHOICE_INVALID if typeof(reply) == TYPE_INT and reply == CHOICE_INVALID else (1 if reply else 0)
		elif owner.seat_index == 0:
			accepted = await _show_sao_preempt_prompt(equipper, sub, "武器" if type_key == "weapon" else "防具", choice_valid)
		# AI 暂保守不发动；D决策可接此入口，不能把角色是否可抢先硬编码为座位0。
		if not action_valid.call():
			return true
		# 原暗置/技能已不存在时不能抢先，原装备动作仍合法则继续；技术关闭不是主动拒绝。
		if not owner_valid.call():
			continue
		if accepted == CHOICE_INVALID: return true
		if accepted == 0:
			continue
		if _reveal_hidden_slot_as(owner, type_key, original, sub):
			_update_debug("%s 抢先明置【%s】，%s 本次未装备，手牌未消耗" % [owner.player_name, CardData.get_type_name(sub), equipper.player_name])
			return true
	return false

# 抢先明置确认弹窗（玩家0）
func _show_sao_preempt_prompt(equipper: Player, sub: CardData.CardSubType, type_name: String, allowed: Callable = Callable()) -> int:
	var idx = await _show_choice_popup("%s 声明将装备【%s】\n你是否将暗置%s明置为【%s】并阻止本次装备？" % [equipper.player_name, CardData.get_type_name(sub), type_name, CardData.get_type_name(sub)], ["明置并阻止", "不阻止"], allowed)
	if idx == CHOICE_INVALID: return CHOICE_INVALID
	return 1 if idx == 0 else 0

# 【苕】明置时机：任意玩家行动后询问是否明置（同一个行动窗口内最多一次）
func _maybe_ask_reveal() -> void:
	if _game_over or not _reveal_ask_pending:
		return
	_reveal_ask_pending = false
	var owner = players[0]
	if owner.general_name != "安普提·斯丢皮得" or not owner.is_alive():
		return
	if not owner.has_hidden_equip():
		return
	_sao_opportunity_generation += 1
	var generation = _sao_opportunity_generation
	var revision = turn_manager.get_context_revision()
	var originals: Dictionary = {}
	for slot in Player.EQUIP_SLOTS:
		var original = owner.get_hidden_equipment_card(slot)
		if original != null: originals[slot] = original
	var valid = func():
		return not _game_over and players.has(owner) and owner.is_alive() \
			and owner.general_name == "安普提·斯丢皮得" and generation == _sao_opportunity_generation \
			and revision == turn_manager.get_context_revision() \
			and originals.keys().all(func(slot): return owner.get_hidden_equipment_card(slot) == originals[slot])
	var accepted = 0
	if _sao_reveal_override.is_valid():
		var reply = await _sao_reveal_override.call()
		accepted = CHOICE_INVALID if typeof(reply) == TYPE_INT and reply == CHOICE_INVALID else (1 if reply else 0)
	else:
		accepted = await _show_reveal_opportunity_prompt(owner, valid)
	if accepted == 1 and valid.call():
		await _do_sao_reveal(owner)

# 明置时机确认弹窗（玩家0）
func _show_reveal_opportunity_prompt(owner: Player, allowed: Callable = Callable()) -> int:
	var idx = await _show_choice_popup("你暗置了一件装备\n是否现在明置？", ["明置", "暂不明置"], allowed)
	if idx == CHOICE_INVALID: return CHOICE_INVALID
	return 1 if idx == 0 else 0

# ============================
#  通用弹窗（按钮选择）
# ============================

# 维护局部等待与计时归属；结束旧窗口不会停止后来窗口的倒计时。
func _wait_choice_prompt(overlay: Control, answer: ChoicePromptAnswer, allowed: Callable = Callable(), timed: bool = true) -> int:
	var actor: Player = players[0]
	var actor_ref = weakref(actor)
	var window_ref = weakref(overlay)
	var revision = turn_manager.get_context_revision()
	answer.allowed = func():
		var current_actor = actor_ref.get_ref()
		var current_window = window_ref.get_ref()
		return not _game_over and current_actor != null and players.has(current_actor) \
			and players[0] == current_actor and not current_actor.is_dead() \
			and revision == turn_manager.get_context_revision() \
			and current_window != null and not current_window.is_queued_for_deletion() \
			and (not allowed.is_valid() or allowed.call())
	var stop = func(_winner): answer.submit(CHOICE_INVALID)
	# tree_exiting内不能立即恢复调用者，否则其下一窗口会在父节点忙时add_child。
	var close = func(): answer.submit.call_deferred(CHOICE_INVALID)
	var watch = func():
		if answer.allowed.is_valid() and not answer.allowed.call():
			answer.submit(CHOICE_INVALID)
	var tree = get_tree()
	game_over.connect(stop)
	tree.process_frame.connect(watch)
	overlay.tree_exiting.connect(close)
	if not _choice_prompt_stack.is_empty():
		var previous = _choice_prompt_stack.back()
		if previous.generation == _countdown_generation:
			previous.step = _step_remaining
	var pending = {"overlay": overlay, "answer": answer, "who": actor.player_name,
		"step": STEP_SECONDS, "generation": -1, "timed": timed}
	_choice_prompt_stack.append(pending)
	_start_choice_countdown(pending)
	var result: int = await answer.answered
	game_over.disconnect(stop)
	tree.process_frame.disconnect(watch)
	if is_instance_valid(overlay):
		overlay.tree_exiting.disconnect(close)
		if not overlay.is_queued_for_deletion():
			overlay.queue_free()
	_choice_prompt_stack.erase(pending)
	if pending.generation == _countdown_generation:
		if not _game_over and not _choice_prompt_stack.is_empty():
			_start_choice_countdown(_choice_prompt_stack.back())
		else:
			_stop_countdown()
	return result

func _start_choice_countdown(pending: Dictionary):
	# 超时是有效取消；先答复后由等待者销毁窗口，避免误判为外部关闭。
	_halt_countdown()
	_set_status_line("等待 %s 响应" % pending.who)
	pending.generation = _countdown_generation
	if not pending.timed:
		return
	_step_remaining = pending.step
	_countdown_active = true
	var generation = _countdown_generation
	pending.generation = generation
	_countdown_on_timeout = func():
		if generation == _countdown_generation:
			pending.answer.submit(-1)
	_update_countdown_label()

# 通用按钮选择弹窗（锚点居中）：返回选中索引，取消返回 -1
func _show_choice_popup(title: String, buttons: Array, allowed: Callable = Callable()) -> int:
	if _game_over:
		return CHOICE_INVALID
	if buttons.is_empty():
		return -1
	var answer = ChoicePromptAnswer.new()
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
		btn.pressed.connect(answer.submit.bind(i), CONNECT_ONE_SHOT)
		hbox.add_child(btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(190, 44)
	cancel_btn.modulate = Color(0.7, 0.7, 0.7)
	cancel_btn.pressed.connect(answer.submit.bind(-1), CONNECT_ONE_SHOT)
	vbox.add_child(cancel_btn)

	return await _wait_choice_prompt(overlay, answer, allowed)

# 明置具体装备选择弹窗（网格布局，装备多）：返回选中索引，取消返回 -1
func _show_sao_reveal_picker(texts: Array, allowed: Callable = Callable()) -> int:
	if _game_over:
		return CHOICE_INVALID
	if texts.is_empty():
		return -1
	var answer = ChoicePromptAnswer.new()
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
		btn.pressed.connect(answer.submit.bind(i), CONNECT_ONE_SHOT)
		grid.add_child(btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(190, 40)
	cancel_btn.modulate = Color(0.7, 0.7, 0.7)
	cancel_btn.pressed.connect(answer.submit.bind(-1), CONNECT_ONE_SHOT)
	vbox.add_child(cancel_btn)

	return await _wait_choice_prompt(overlay, answer, allowed)

# ============================
#  【装傻】濒死拼点（安普提·斯丢皮得，锁定技）
# ============================

# 将要死亡时与场上所有存活玩家各拼点一次；赢至少一半（向上取整）则回复至 1 点体力；每名对手只猜一次，平局不重猜
func _try_zhuangsha(dying: Player) -> void:
	var opponents: Array[Player] = []
	for pl in players:
		if pl != dying and pl.is_alive():
			opponents.append(pl)
	if opponents.is_empty():
		return
	_update_debug("%s 发动【装傻】：与场上所有存活玩家拼点！" % dying.player_name)
	var revision = turn_manager.get_context_revision()
	var wins := 0
	for opp in opponents:
		var valid = func():
			return not _game_over and revision == turn_manager.get_context_revision() \
				and dying.is_dying() and opp.is_alive()
		var r = await _do_ping_dian_once(dying, opp, valid)
		if r == RPS_INVALID or not valid.call():
			return
		if r == RPS_WIN:
			wins += 1
	if wins >= ceili(opponents.size() / 2.0):
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
	if _game_over:
		return
	for p in players:
		_check_player_awaken(p)

var _awaken_in_progress: Dictionary = {}

func _check_player_awaken(p: Player):
	if _game_over or not players.has(p) or not p.is_alive() or p.general_name != "史蒂芬·彼特先斯":
		return
	if p.awoken:
		if p.awake_choice != 0 or not p.awaken_effects_applied:
			return
	elif p.hand_size() == 0:
		p.awoken = true
	else:
		return
	if _awaken_in_progress.get(p, -1) == p.awakening_revision:
		return
	if p.seat_index == 0:
		call_deferred("_do_awaken", p, p.awakening_revision)
	else:
		_do_awaken(p, p.awakening_revision)

# 手牌变化监听（add_to_hand / remove_from_hand 路径的补充触发）
func _on_hand_updated(p: Player):
	_check_player_awaken(p)

# 觉醒：失去一点体力上限 → 摸两张牌 → 三选一
func _awaken_choice_pending(p: Player, revision: int) -> bool:
	return not _game_over and is_instance_valid(p) and players.has(p) and p.is_alive() \
		and p.general_name == "史蒂芬·彼特先斯" and p.awoken and p.awake_choice == 0 \
		and p.awakening_revision == revision

func _do_awaken(p: Player, expected_revision: int = -1):
	if not is_instance_valid(p):
		return
	var generation = p.awakening_revision
	if expected_revision >= 0 and expected_revision != generation:
		return
	if not _awaken_choice_pending(p, generation) or _awaken_in_progress.get(p, -1) == generation:
		return
	_awaken_in_progress[p] = generation
	if not p.awaken_effects_applied:
		# 先记已结算，摸牌及UI信号不能重入扣上限/摸牌。
		p.awaken_effects_applied = true
		p.max_hp -= 1
		p.hp = mini(p.hp, p.max_hp)
		_update_debug("%s 觉醒！失去 1 点体力上限（上限 %d，体力 %d/%d），摸两张牌" % [p.player_name, p.max_hp, p.hp, p.max_hp])
		_draw_blank_cards(p, 2)
	await _resolve_awaken_choice(p, generation)
	if _awaken_in_progress.get(p, -1) == generation:
		_awaken_in_progress.erase(p)
	# 人类必选窗口被销毁或阶段过期时，重新显示待选择项；不重做已结算效果。
	if _awaken_choice_pending(p, generation) and p.seat_index == 0:
		call_deferred("_do_awaken", p, generation)

func _resolve_awaken_choice(p: Player, generation: int):
	var revision = turn_manager.get_context_revision()
	var choice: int
	if _awaken_pick_override.is_valid():
		choice = await _awaken_pick_override.call()
	elif p.seat_index != 0:
		choice = await _choose_ai_response(p, "awaken", [1, 2, 3])
	else:
		var actor_ref = weakref(p)
		choice = await _show_awaken_pick(func(): return _awaken_choice_pending(actor_ref.get_ref(), generation))
	if not _awaken_choice_pending(p, generation) or revision != turn_manager.get_context_revision():
		return
	if choice == CHOICE_INVALID:
		return
	if choice not in [1, 2, 3]:
		choice = 1 # E03-Q1：默认不能成为杀目标。
	p.awake_choice = choice
	var desc = "1.不能成为【杀】的目标" if choice == 1 else ("2.不能成为【决斗】的目标" if choice == 2 else "3.不能成为【南蛮入侵】和【万箭齐发】的目标")
	_update_debug("%s 选择觉醒效果：%s" % [p.player_name, desc])
	_sync_all_ui()

# 觉醒三选一弹窗（玩家0）：返回 1 / 2 / 3
func _show_awaken_pick(allowed: Callable = Callable()) -> int:
	var idx = await _show_choice_popup("【觉醒】选择一项永久效果：", ["不能成为【杀】的目标", "不能成为【决斗】的目标", "不能成为【南蛮入侵】和【万箭齐发】的目标"], allowed)
	if idx == CHOICE_INVALID:
		return CHOICE_INVALID
	if idx < 0:
		idx = 0  # 取消/超时默认第1项：不能成为杀目标。
	return idx + 1

# ============================
#  【拍胸脯】史蒂芬·彼特先斯：将要受到伤害时，可发动；发动则伤害来源需弃一张手牌才能造成伤害
# ============================

# 失去来源但目标仍有效时伤害继续；动作过期与主动不弃必须分别处理。
enum PaixiongOutcome { NOT_USED, PAID, PREVENTED, INVALIDATED }

func _try_paixiong_block(victim: Player, source: Player) -> PaixiongOutcome:
	if victim.general_name != "史蒂芬·彼特先斯" or not victim.is_alive():
		return PaixiongOutcome.NOT_USED
	if source == null:
		# 无伤害来源（闪电/火烧连营）：没有来源可弃牌 → 不能发动
		return PaixiongOutcome.NOT_USED
	if source == victim:
		# 来源是自己（舍己为人自转移等）：无需弃牌，伤害照常
		return PaixiongOutcome.NOT_USED
	var action_revision = turn_manager.get_context_revision()
	var valid = func():
		return not _game_over and action_revision == turn_manager.get_context_revision() \
			and players.has(victim) and victim.is_alive() and victim.general_name == "史蒂芬·彼特先斯" \
			and players.has(source) and source.is_alive()
	var use = 0
	if _paixiong_override.is_valid():
		var reply = await _paixiong_override.call()
		use = CHOICE_INVALID if typeof(reply) == TYPE_INT and reply == CHOICE_INVALID else (1 if reply else 0)
	else:
		if victim.seat_index != 0:
			return PaixiongOutcome.NOT_USED  # AI 暂不发动
		use = await _show_paixiong_prompt(source.player_name, valid)
	if _game_over or not players.has(victim) or not victim.is_alive():
		return PaixiongOutcome.INVALIDATED
	if source.is_dead():
		return PaixiongOutcome.NOT_USED # 来源最终死亡，已使用杀余伤无源继续。
	if use == CHOICE_INVALID or not valid.call():
		return PaixiongOutcome.INVALIDATED
	if use == 0:
		return PaixiongOutcome.NOT_USED
	# 发动：来源可选择弃一张手牌使整次伤害照常结算，也可拒绝并防止整次伤害。
	while source.hand_size() > 0:
		if _game_over or not victim.is_alive():
			return PaixiongOutcome.INVALIDATED
		if source.is_dead():
			return PaixiongOutcome.NOT_USED
		if action_revision != turn_manager.get_context_revision():
			return PaixiongOutcome.INVALIDATED
		var result = await _select_hand_discard_result(source, 1, false, valid)
		if _game_over or not victim.is_alive():
			return PaixiongOutcome.INVALIDATED
		if result == HandDiscardOutcome.PAID:
			_update_debug("%s 发动【拍胸脯】！%s 弃置一张手牌（剩余 %d 张），整次伤害照常结算" % [victim.player_name, source.player_name, source.hand_size()])
			_sync_all_ui()
			return PaixiongOutcome.PAID
		if source.is_dead():
			return PaixiongOutcome.NOT_USED # TIME-04：剩余伤害由链条改为无来源。
		if action_revision != turn_manager.get_context_revision():
			return PaixiongOutcome.INVALIDATED
		if result == HandDiscardOutcome.ACTION_INVALIDATED or result == HandDiscardOutcome.GAME_ENDED:
			return PaixiongOutcome.INVALIDATED
		if result == HandDiscardOutcome.STALE_SELECTION:
			await get_tree().process_frame # 非空旧答复不是拒绝；重建当前选择。
			continue
		if result == HandDiscardOutcome.DECLINED:
			_update_debug("%s 发动【拍胸脯】！%s 选择不弃牌，本次伤害被防止！" % [victim.player_name, source.player_name])
			_sync_all_ui()
			return PaixiongOutcome.PREVENTED
		break # 牌在等待中耗尽，已无法支付。
	if _game_over or not victim.is_alive():
		return PaixiongOutcome.INVALIDATED
	if source.is_dead():
		return PaixiongOutcome.NOT_USED
	if action_revision != turn_manager.get_context_revision():
		return PaixiongOutcome.INVALIDATED
	_update_debug("%s 发动【拍胸脯】！%s 没有手牌，本次伤害被防止！" % [victim.player_name, source.player_name])
	_sync_all_ui()
	return PaixiongOutcome.PREVENTED

# 玩家0 的【拍胸脯】发动确认弹窗
func _show_paixiong_prompt(source_name: String, allowed: Callable = Callable()) -> int:
	var idx = await _show_choice_popup("你将受到伤害！\n是否发动【拍胸脯】？（发动后 %s 需弃置一张手牌才能造成伤害）" % source_name, ["发动【拍胸脯】", "不发动"], allowed)
	if idx == CHOICE_INVALID: return CHOICE_INVALID
	return 1 if idx == 0 else 0

# ============================
#  【装逼】史蒂芬·彼特先斯：出牌阶段选任意数量其他角色，各弃一张手牌后依次拼点
# ============================

# 详情弹窗技能点击：进入目标选择模式（与【下跪】/【苕】一致的发动方式）
# 出牌阶段技能归实际操作者，获赠阶段不要求其同时是回合主人。
var _play_skill_target_revision: int = -1

func _can_use_play_skill(p: Player) -> bool:
	return not _game_over and is_instance_valid(p) and players.has(p) and p.is_alive() \
		and turn_manager.can_play_card() and turn_manager.get_play_actor_idx() == p.seat_index \
		and not _is_kneeling(p)

func _play_skill_target_is_current() -> bool:
	if _can_use_play_skill(players[0]) and _play_skill_target_revision == turn_manager.get_context_revision():
		return true
	_is_zhuangbi_targeting = false
	_zhuangbi_targets.clear()
	_is_campus_targeting = false
	_is_gay_targeting = false
	_is_lanzhonghou_targeting = false
	_lanzhonghou_selected.clear()
	_cancel_target_btn.visible = false
	_confirm_target_btn.visible = false
	_restore_play_skill_buttons()
	return false

func _restore_play_skill_buttons():
	var allowed = _can_use_play_skill(players[0])
	_play_btn.visible = allowed
	_end_play_btn.visible = allowed

func _on_zhuangbi_skill_clicked(p: Player) -> void:
	if not _can_use_play_skill(p):
		return
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
	if not _can_use_play_skill(players[0]):
		return
	_play_skill_target_revision = turn_manager.get_context_revision()
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
	_restore_play_skill_buttons()

# 装逼目标点击：toggle 加入/移除（不能选自己；目标须存活且有手牌）
func _on_zhuangbi_target_click(target: Player):
	if not _is_zhuangbi_targeting or not _play_skill_target_is_current():
		return
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
	if not _is_zhuangbi_targeting or not _play_skill_target_is_current():
		return
	if _zhuangbi_targets.is_empty():
		return
	var targets = _zhuangbi_targets.duplicate()
	_exit_zhuangbi_mode()
	await _execute_zhuangbi(targets)

# 执行装逼：双方各弃一张手牌 → 依次拼点 → 判定结果
func _execute_zhuangbi(targets: Array[Player]) -> void:
	if not _can_use_play_skill(players[0]):
		return
	if _zhuangbi_blocked_this_phase:
		_update_debug("【装逼】本出牌阶段不能再次发动")
		return
	var p = players[0]
	if p.general_name != "史蒂芬·彼特先斯" or not p.is_alive():
		return
	var revision = turn_manager.get_context_revision()
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
	# 发动者确认目标后，自己与全部目标都必须支付；只能选择牌，不能拒绝。
	if not await _select_hand_discard(p, 1, true, func():
		return p.is_alive() and turn_manager.current_phase == TurnManager.Phase.PLAY):
		return
	# 选牌快照直接移除手牌，不经 hand_updated；本人的最后一张牌一旦支付，
	# 必须先完成强制觉醒的三选一，再继续其他目标支付或拼点。
	if p.hand_size() == 0 and not p.awoken:
		p.awoken = true
		await _do_awaken(p)
	if not _paid_skill_rps_valid(p, valid[0], revision):
		return
	_update_debug("%s 发动【装逼】！弃置一张手牌（剩余 %d 张）" % [p.player_name, p.hand_size()])
	for t in valid:
		if not await _select_hand_discard(t, 1, true, func():
			return p.is_alive() and t.is_alive() and turn_manager.current_phase == TurnManager.Phase.PLAY):
			return
		if not _paid_skill_rps_valid(p, t, revision):
			return
	_update_debug("各目标弃置一张手牌，依次与 %s 拼点！" % p.player_name)
	_sync_all_ui()

	# 依次拼点（进行拼点：平局后继续，直到分出胜负）
	var wins := 0
	var losses := 0
	var losers: Array[Player] = []  # 输给 p 的目标
	for t in valid:
		if not _paid_skill_rps_valid(p, null, revision):
			return
		# 已付费但在轮到出拳前最终死亡的目标不参与此次拼点；
		# 保留此前胜负，继续后续目标，费用不返还。
		if t.is_dead():
			continue
		if not _paid_skill_rps_valid(p, t, revision):
			return
		var r = await _do_ping_dian(p, t, func(): return _paid_skill_rps_valid(p, t, revision))
		if r == RPS_INVALID:
			return
		if r == RPS_WIN:
			wins += 1
			losers.append(t)
		else:
			losses += 1

	var n = wins + losses  # 已实际参与拼点的人数，不含跳过的死者
	if n == 0:
		return
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
	# 严格超过一半且成功结算后，才允许再次主动发动。
	var can_repeat = func():
		return _paid_skill_rps_valid(p, null, revision) and players.has(p) \
			and p.general_name == "史蒂芬·彼特先斯" and not _zhuangbi_blocked_this_phase
	if can_repeat.call():
		var again = 0
		if _zhuangbi_again_override.is_valid():
			var reply = await _zhuangbi_again_override.call()
			again = CHOICE_INVALID if typeof(reply) == TYPE_INT and reply == CHOICE_INVALID else (1 if reply else 0)
		else:
			again = await _show_zhuangbi_again_prompt(can_repeat)
		if again == 1 and can_repeat.call():
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
func _show_zhuangbi_again_prompt(allowed: Callable = Callable()) -> int:
	var idx = await _show_choice_popup("装逼成功！\n是否再次使用【装逼】？", ["再次装逼", "就此收手"], allowed)
	if idx == CHOICE_INVALID: return CHOICE_INVALID
	return 1 if idx == 0 else 0

# ============================
#  【校园霸主】杰基·斯特朗：出牌阶段选一名有手牌的角色，各弃一张手牌后拼点，赢者对输者造成 1 点伤害
# ============================

# 详情弹窗技能点击：进入目标选择模式（与【装逼】等主动技能一致）
func _on_campus_skill_clicked(p: Player) -> void:
	if not _can_use_play_skill(p):
		return
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
	if not _can_use_play_skill(players[0]):
		return
	_play_skill_target_revision = turn_manager.get_context_revision()
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
	if not _is_campus_targeting or not _play_skill_target_is_current():
		return
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
	_restore_play_skill_buttons()
	_sync_all_ui()

# 执行校园霸主：双方各弃一张手牌 → 进行拼点（平局继续直到分出胜负）→ 赢者对输者造成 1 点伤害
func _execute_campus_dominator(p: Player, target: Player) -> void:
	if _campus_execution_owner != -1:
		return
	_campus_execution_generation += 1
	var owner = _campus_execution_generation
	_campus_execution_owner = owner
	await _execute_campus_pending(p, target, owner)
	if _campus_execution_owner == owner:
		_campus_execution_owner = -1

func _execute_campus_pending(p: Player, target: Player, owner: int) -> void:
	if not _can_use_play_skill(p):
		return
	if p.general_name != "杰基·斯特朗" or not p.is_alive():
		return
	var revision = turn_manager.get_context_revision()
	var valid = func():
		return _campus_execution_owner == owner and _campus_execution_generation == owner \
			and players.has(p) and players.has(target) and target != p \
			and p.general_name == "杰基·斯特朗" and _paid_skill_rps_valid(p, target, revision)
	if not valid.call():
		return
	if not target.is_alive() or target.hand_size() <= 0:
		_update_debug("目标没有手牌，【校园霸主】未发动")
		return
	if p.hand_size() <= 0:
		_update_debug("你没有手牌，【校园霸主】未发动")
		return
	# 指定目标并确认发动后，双方都必须支付；只能选择牌，不能拒绝。
	if not await _select_hand_discard(p, 1, true, valid):
		return
	if not valid.call():
		return
	if not await _select_hand_discard(target, 1, true, valid):
		return
	if not valid.call():
		return
	_update_debug("%s 发动【校园霸主】！你与 %s 各弃置一张手牌，进行拼点！" % [p.player_name, target.player_name])
	_sync_all_ui()

	# 进行拼点（平局继续直到分出胜负）
	var r = await _do_ping_dian(p, target, valid)
	if r == RPS_INVALID or not valid.call():
		return
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
	_record_card_action(p, card, CardActionEvent.Kind.USE, false, true)
	_record_strike_played(p)
	var base_damage = 1
	# 【酒】：视为杀吃酒加成并消耗酒层数
	if p.wine_stacks > 0:
		base_damage += p.consume_wine_bonus()
		_update_debug("%s 的【酒】加成：神速杀伤害 +%d" % [p.player_name, base_damage - 1])
	await _execute_single_strike(p, target, card, CardData.CardSubType.STRIKE, EffectChain.DamageType.PHYSICAL, base_damage)
	_sync_all_ui()

# ============================
#  【Gay】（比尔·盖伊）：出牌阶段限一次，弃 X 张手牌令双方各回复 X 点
# ============================

# 详情弹窗技能按钮 → 【Gay】发动入口
func _on_gay_skill_clicked(p: Player) -> void:
	if not _can_use_play_skill(p):
		return
	if p != players[0] or p.seat_index != 0:
		_update_debug("只能对自己使用【Gay】")
		return
	if p.general_name != "比尔·盖伊":
		return
	if turn_manager.current_phase != TurnManager.Phase.PLAY:
		_update_debug("【Gay】只能在出牌阶段发动")
		return
	if _gay_used:
		_update_debug("【Gay】每出牌阶段限一次，本阶段已使用")
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
	_play_skill_target_revision = turn_manager.get_context_revision()
	_is_gay_targeting = true
	_play_btn.visible = false
	_end_play_btn.visible = false
	_cancel_target_btn.visible = true
	_update_debug("【Gay】：请点击一名已受伤的同性角色（弃 X 张手牌，双方各回复 X 点体力）")

# Gay 目标点击（分发器在 _on_player_panel_click）：校验后弹 X 选择
func _on_gay_target_click(target: Player):
	if not _is_gay_targeting or not _play_skill_target_is_current():
		return
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
	_restore_play_skill_buttons()
	_sync_all_ui()

# 执行【Gay】：弃 X 张手牌，双方各回复 X 点体力（X ≤ 双方体力上限最小值，且 ≤ 手牌数）
func _execute_gay(p: Player, target: Player) -> void:
	if _gay_execution_owner != -1:
		return
	_gay_execution_generation += 1
	var owner = _gay_execution_generation
	_gay_execution_owner = owner
	await _execute_gay_pending(p, target, owner)
	if _gay_execution_owner == owner:
		_gay_execution_owner = -1

func _execute_gay_pending(p: Player, target: Player, owner: int) -> void:
	if not _can_use_play_skill(p):
		return
	if p.general_name != "比尔·盖伊" or not p.is_alive() or not target.is_alive():
		return
	if _gay_used:
		return
	var revision = turn_manager.get_context_revision()
	var valid = func():
		return _gay_execution_owner == owner and _gay_execution_generation == owner \
			and _can_use_play_skill(p) and revision == turn_manager.get_context_revision() \
			and p.general_name == "比尔·盖伊" and players.has(target) and target != p \
			and target.is_alive() and target.gender == p.gender and target.hp < target.max_hp \
			and not _is_kneeling(target) and not _gay_used
	if not valid.call():
		return
	var max_x = mini(p.max_hp, target.max_hp)
	max_x = mini(max_x, p.hand_size())
	if max_x <= 0:
		_update_debug("没有可弃的手牌，【Gay】未发动")
		return
	var x := 0
	if _gay_x_override.is_valid():
		x = await _gay_x_override.call()
	elif p.seat_index == 0:
		x = await _show_gay_x_picker(max_x, valid)
	if x == CHOICE_INVALID or not valid.call():
		return
	if x <= 0 or x > max_x:
		_update_debug("取消【Gay】")
		_sync_all_ui()
		return
	# 弹窗返回后重新验证，数量不足不得部分支付或获得效果。
	if x > mini(p.max_hp, target.max_hp) or p.hand_size() < x:
		return
	if not await _select_hand_discard(p, x, false, func():
		return valid.call() and x <= mini(p.max_hp, target.max_hp)):
		return
	if not valid.call() or x > mini(p.max_hp, target.max_hp):
		return
	_gay_used = true
	var p_before = p.hp
	var t_before = target.hp
	p.heal(x)
	target.heal(x)
	_update_debug("%s 发动【Gay】：弃置 %d 张手牌，与 %s 各回复 %d 点体力（%d/%d → %d/%d；%d/%d → %d/%d）" % [p.player_name, x, target.player_name, x, p_before, p.max_hp, p.hp, p.max_hp, t_before, target.max_hp, target.hp, target.max_hp])
	_sync_all_ui()

# X 选择弹窗（玩家0）：返回 1..max_x（取消返回 0）
func _show_gay_x_picker(max_x: int, allowed: Callable = Callable()) -> int:
	var buttons: Array = []
	for i in range(1, max_x + 1):
		buttons.append("弃置 %d 张，各回复 %d 点" % [i, i])
	var idx = await _show_choice_popup("【Gay】：弃置 X 张手牌（X ≤ %d），双方各回复 X 点体力" % max_x, buttons, allowed)
	if idx == CHOICE_INVALID:
		return CHOICE_INVALID
	if idx < 0:
		return 0
	return idx + 1

# ============================
#  【没用】麦克斯·欧尼斯特：出牌阶段限一次，弃 X 张牌交换两名角色的 X 个装备区域
#  X = 选择的区域对数（武器/防具各最多一对、坐骑最多四对）；坐骑可跨槽位交换。
#  E05：空槽与暗置均可交换；暗置声明由原持有者完成。
# ============================

# 详情弹窗技能点击：进入两名角色选择模式（与【装逼】等主动技能一致）
func _on_lanzhonghou_skill_clicked(p: Player) -> void:
	if not _can_use_play_skill(p):
		return
	if p != players[0] or p.seat_index != 0:
		_update_debug("只能对自己使用【没用】")
		return
	if p.general_name != "麦克斯·欧尼斯特":
		return
	if turn_manager.current_phase != TurnManager.Phase.PLAY:
		_show_toast("【没用】只能在你的出牌阶段发动")
		return
	if _lanzhonghou_used:
		_show_toast("本出牌阶段已使用过【没用】")
		return
	if p.hand_size() <= 0:
		_show_toast("【没用】发动条件：至少有一张手牌（弃 X 张牌）")
		return
	_start_lanzhonghou_mode()

func _start_lanzhonghou_mode():
	if not _can_use_play_skill(players[0]):
		return
	_play_skill_target_revision = turn_manager.get_context_revision()
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
	_update_debug("【没用】：请点击两名角色（可含自己）的头像，选择交换装备的角色（当前 0/2）")

# 没用角色选择：点击头像 toggle（选满 2 名进入区域选择）
func _on_lanzhonghou_target_click(target: Player):
	if not _is_lanzhonghou_targeting or not _play_skill_target_is_current():
		return
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
		_restore_play_skill_buttons()
		_sync_all_ui()

# 区域选择循环：武器/防具/坐骑 各最多一次；「完成交换」后弃 X 张牌并统一执行交换
func _run_lanzhonghou(a: Player, b: Player) -> void:
	if not _can_use_play_skill(players[0]):
		return
	var p = players[0]
	if p.general_name != "麦克斯·欧尼斯特" or not p.is_alive():
		return
	var revision = turn_manager.get_context_revision()
	if _lanzhonghou_used:
		return
	# X = 交换区域对数：武器/防具各最多 1 对，坐骑最多 4 对（每名角色 4 个坐骑槽）→ 上限 6 对，弃 X 张牌
	var max_pick = mini(6, p.hand_size())
	_lanzhonghou_pending.clear()
	while true:
		var zone = await _ask_lanzhonghou_zone(a, b, _lanzhonghou_pending, max_pick)
		if _game_over or revision != turn_manager.get_context_revision():
			_lanzhonghou_pending.clear()
			return
		if zone == "cancel":
			_lanzhonghou_pending.clear()
			_update_debug("取消【没用】，未消耗手牌")
			return
		if zone == "done":
			break
		match zone:
			"weapon", "armor":
				if _lanzhonghou_zone_picked(_lanzhonghou_pending, zone) or (not a.equipment.has(zone) and not b.equipment.has(zone)):
					continue
				_lanzhonghou_pending.append({"zone": zone, "a": a, "slot_a": zone, "b": b, "slot_b": zone,
					"card_a": _equipment_resource_for_pick(a, zone), "card_b": _equipment_resource_for_pick(b, zone), "ok": true})
			"mount":
				# 坐骑最多 4 对（防御：UI 已禁用，直调时也拦）
				if _lanzhonghou_count(_lanzhonghou_pending, "mount") >= 4:
					_update_debug("坐骑区域最多选择 4 对")
					continue
				# 坐骑可移入空槽；双方选中的槽位不能同时为空。
				var used_a := {}
				var used_b := {}
				for entry in _lanzhonghou_pending:
					if entry.zone == "mount":
						used_a[entry.slot_a] = true
						used_b[entry.slot_b] = true
				var slots_a: Array[String] = []
				for s in Player.MOUNT_SLOTS:
					if not used_a.has(s):
						slots_a.append(s)
				var slots_b: Array[String] = []
				for s in Player.MOUNT_SLOTS:
					if not used_b.has(s):
						slots_b.append(s)
				if slots_a.is_empty() or slots_b.is_empty() or not _lanzhonghou_has_swappable_mount(a, _lanzhonghou_pending, true) and not _lanzhonghou_has_swappable_mount(b, _lanzhonghou_pending, false):
					continue
				var pair_no = _lanzhonghou_count(_lanzhonghou_pending, "mount") + 1
				var slot_a = await _ask_lanzhonghou_mount_slot(a, slots_a, "选择 %s 要交换的坐骑（第 %d 对坐骑）：" % [a.player_name, pair_no])
				if slot_a == "cancel" or not slots_a.has(slot_a):
					continue
				if not a.equipment.has(slot_a):
					for s in slots_b.duplicate():
						if not b.equipment.has(s):
							slots_b.erase(s)
				if slots_b.is_empty():
					continue
				var slot_b = await _ask_lanzhonghou_mount_slot(b, slots_b, "选择 %s 要交换的坐骑（第 %d 对坐骑）：" % [b.player_name, pair_no])
				if slot_b == "cancel" or not slots_b.has(slot_b):
					continue
				_lanzhonghou_pending.append({"zone": "mount", "a": a, "slot_a": slot_a, "b": b, "slot_b": slot_b,
					"card_a": _equipment_resource_for_pick(a, slot_a), "card_b": _equipment_resource_for_pick(b, slot_b), "ok": true})
	var x = _lanzhonghou_pending.size()
	if x <= 0:
		_update_debug("没有选择任何区域，取消【没用】")
		return
	for entry in _lanzhonghou_pending:
		if entry.has("card_a") and (_equipment_resource_for_pick(entry.a, entry.slot_a) != entry.card_a \
				or _equipment_resource_for_pick(entry.b, entry.slot_b) != entry.card_b):
			_lanzhonghou_pending.clear()
			return
		var hidden_a = entry.a.equipment.get(entry.slot_a, -1) == CardData.CardSubType.HIDDEN_EQUIPMENT
		var hidden_b = entry.b.equipment.get(entry.slot_b, -1) == CardData.CardSubType.HIDDEN_EQUIPMENT
		if (hidden_a or hidden_b) and (entry.zone == "mount" and hidden_a and hidden_b \
				or (hidden_a and entry.card_a == null) \
				or (hidden_b and entry.card_b == null)):
			_update_debug("所选暗置交换组合尚未支持，未支付费用")
			_lanzhonghou_pending.clear()
			return
	# 多次选择期间牌可能离手，必须一次完整支付才开始交换。
	var valid = func():
		return revision == turn_manager.get_context_revision() and a.is_alive() and b.is_alive() \
			and not _is_kneeling(a) and not _is_kneeling(b) and not _lanzhonghou_used
	if not await _select_hand_discard(p, x, false, valid):
		_lanzhonghou_pending.clear()
		return
	_lanzhonghou_used = true # 支付后立即记入当前阶段；后续暗置声明等待不能写进另一个阶段。
	# 统一执行交换
	var swapped = 0
	for entry in _lanzhonghou_pending:
		if not entry.ok:
			var zone_name = "武器" if entry.zone == "weapon" else ("护甲" if entry.zone == "armor" else "坐骑")
			_update_debug("%s 区域：一方没有装备（或为暗置装备），装备直接归还，不交换" % zone_name)
			continue
		if entry.has("card_a") and (_equipment_resource_for_pick(entry.a, entry.slot_a) != entry.card_a \
				or _equipment_resource_for_pick(entry.b, entry.slot_b) != entry.card_b):
			continue
		if _swap_equip_slot(entry.a, entry.slot_a, entry.b, entry.slot_b):
			swapped += 1
			var declarations: Array = []
			if entry.card_a != null and entry.card_a.sub_type == CardData.CardSubType.HIDDEN_EQUIPMENT:
				declarations.append([entry.a, entry.b, entry.slot_b, entry.card_a])
			if entry.card_b != null and entry.card_b.sub_type == CardData.CardSubType.HIDDEN_EQUIPMENT:
				declarations.append([entry.b, entry.a, entry.slot_a, entry.card_b])
			if declarations.size() == 2:
				var a_first = _lanzhonghou_hidden_first_override.call() if _lanzhonghou_hidden_first_override.is_valid() else randi() % 2 == 0
				if not a_first:
					declarations.reverse()
			for declaration in declarations:
				await _declare_exchanged_hidden_equipment(declaration[0], declaration[1], declaration[2], declaration[3])
	_update_debug("%s 发动【没用】：弃置 %d 张手牌，交换了 %s 与 %s 的 %d 个装备区域" % [p.player_name, x, a.player_name, b.player_name, swapped])
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

# 该角色是否还有未使用的坐骑（含暗置）；另一侧可选择空槽接牌。
func _lanzhonghou_has_swappable_mount(p: Player, picked: Array = [], is_a: bool = true) -> bool:
	var used := {}
	for entry in picked:
		if entry.zone == "mount":
			used[entry.slot_a if is_a else entry.slot_b] = true
	for s in p.get_mount_slots():
		if not used.has(s):
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
	weapon_btn.disabled = _lanzhonghou_zone_picked(picked, "weapon") or picked.size() >= max_pick \
			or (not a.equipment.has("weapon") and not b.equipment.has("weapon"))
	weapon_btn.pressed.connect(func():
		overlay.queue_free()
		_lanzhonghou_zone_result.emit("weapon")
	, CONNECT_ONE_SHOT)
	hbox.add_child(weapon_btn)

	var armor_btn = Button.new()
	armor_btn.text = "防具"
	armor_btn.custom_minimum_size = Vector2(120, 44)
	armor_btn.disabled = _lanzhonghou_zone_picked(picked, "armor") or picked.size() >= max_pick \
			or (not a.equipment.has("armor") and not b.equipment.has("armor"))
	armor_btn.pressed.connect(func():
		overlay.queue_free()
		_lanzhonghou_zone_result.emit("armor")
	, CONNECT_ONE_SHOT)
	hbox.add_child(armor_btn)

	var mount_btn = Button.new()
	mount_btn.text = "坐骑"
	mount_btn.custom_minimum_size = Vector2(120, 44)
	mount_btn.disabled = _lanzhonghou_count(picked, "mount") >= 4 or picked.size() >= max_pick \
			or (not _lanzhonghou_has_swappable_mount(a, picked, true) and not _lanzhonghou_has_swappable_mount(b, picked, false))
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

# 坐骑槽选择弹窗：返回槽位或 "cancel"（锚点居中；可选空槽）
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
		btn.text = "%s：%s" % [Player.EQUIP_SLOT_NAMES[slot], CardData.get_type_name(target.equipment[slot]) if target.equipment.has(slot) else "空槽"]
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
# 一侧空槽时移动原牌；暗置与明置武器／防具可先互换原牌，再由原持有者声明暗置牌。
# 双方明置时的旧轻量装卸仍待B04核对失去效果；暗置/明置和单边空槽按失去装备处理。
func _swap_equip_slot(pA: Player, slot_a: String, pB: Player, slot_b: String) -> bool:
	var has_a = pA.equipment.has(slot_a)
	var has_b = pB.equipment.has(slot_b)
	if not has_a and not has_b:
		return false
	var subA = pA.equipment.get(slot_a, -1)
	var subB = pB.equipment.get(slot_b, -1)
	if subA == CardData.CardSubType.HIDDEN_EQUIPMENT or subB == CardData.CardSubType.HIDDEN_EQUIPMENT:
		if has_a and has_b and subA == CardData.CardSubType.HIDDEN_EQUIPMENT and subB == subA:
			var hidden_a = pA.get_hidden_equipment_card(slot_a)
			var hidden_b = pB.get_hidden_equipment_card(slot_b)
			if hidden_a == null or hidden_b == null or hidden_a == hidden_b \
					or slot_a != slot_b or not ["weapon", "armor"].has(slot_a):
				return false
			pA.remove_equipment(slot_a)
			pB.remove_equipment(slot_b)
			if not pA.equip_hidden_card_to_slot(slot_a, hidden_b):
				pA.equip_hidden_card_to_slot(slot_a, hidden_a)
				pB.equip_hidden_card_to_slot(slot_b, hidden_b)
				return false
			if not pB.equip_hidden_card_to_slot(slot_b, hidden_a):
				pA.remove_equipment(slot_a)
				pA.equip_hidden_card_to_slot(slot_a, hidden_a)
				pB.equip_hidden_card_to_slot(slot_b, hidden_b)
				return false
			_update_debug("交换了 %s 与 %s 的两张暗置装备" % [pA.player_name, pB.player_name])
			return true
		if has_a and has_b and subA != subB:
			var exchange_hidden_owner = pA if subA == CardData.CardSubType.HIDDEN_EQUIPMENT else pB
			var exchange_hidden_slot = slot_a if subA == CardData.CardSubType.HIDDEN_EQUIPMENT else slot_b
			var exchange_visible_owner = pB if exchange_hidden_owner == pA else pA
			var exchange_visible_slot = slot_b if exchange_hidden_owner == pA else slot_a
			var exchange_hidden_card = exchange_hidden_owner.get_hidden_equipment_card(exchange_hidden_slot)
			var exchange_visible_card = exchange_visible_owner.get_equipment_card(exchange_visible_slot)
			if exchange_hidden_card == null or exchange_visible_card == null:
				return false
			exchange_hidden_owner.remove_equipment(exchange_hidden_slot)
			exchange_visible_owner.remove_equipment(exchange_visible_slot)
			if not exchange_hidden_owner.equip_card_to_slot(exchange_hidden_slot, exchange_visible_card):
				exchange_hidden_owner.equip_hidden_card_to_slot(exchange_hidden_slot, exchange_hidden_card)
				exchange_visible_owner.equip_card_to_slot(exchange_visible_slot, exchange_visible_card)
				return false
			if not exchange_visible_owner.equip_hidden_card_to_slot(exchange_visible_slot, exchange_hidden_card):
				exchange_hidden_owner.remove_equipment(exchange_hidden_slot)
				exchange_hidden_owner.equip_hidden_card_to_slot(exchange_hidden_slot, exchange_hidden_card)
				exchange_visible_owner.equip_card_to_slot(exchange_visible_slot, exchange_visible_card)
				return false
			_update_debug("交换了 %s 的暗置装备与 %s 的【%s】" % [exchange_hidden_owner.player_name, exchange_visible_owner.player_name, exchange_visible_card.card_name])
			return true
		if has_a == has_b:
			return false
		var hidden_source = pA if has_a else pB
		var hidden_slot = slot_a if has_a else slot_b
		var empty_dest = pB if has_a else pA
		var empty_slot = slot_b if has_a else slot_a
		if hidden_source.get_hidden_equipment_card(hidden_slot) == null:
			return false
		var hidden_card = hidden_source.remove_equipment(hidden_slot)
		if not empty_dest.equip_hidden_card_to_slot(empty_slot, hidden_card):
			hidden_source.equip_hidden_card_to_slot(hidden_slot, hidden_card)
			return false
		_update_debug("%s 的暗置装备交换至 %s 的空装备槽" % [hidden_source.player_name, empty_dest.player_name])
		return true
	if not has_a or not has_b:
		var source = pA if has_a else pB
		var source_slot = slot_a if has_a else slot_b
		var dest = pB if has_a else pA
		var dest_slot = slot_b if has_a else slot_a
		var moved = source.remove_equipment(source_slot)
		if moved == null:
			return false
		if not dest.equip_card_to_slot(dest_slot, moved):
			source.equip_card_to_slot(source_slot, moved)
			return false
		_update_debug("%s 的【%s】交换至 %s 的空装备槽" % [source.player_name, moved.card_name, dest.player_name])
		return true
	var card_a = pA.detach_equipment_quiet(slot_a)
	var card_b = pB.detach_equipment_quiet(slot_b)
	if card_a == null or card_b == null:
		# 前置检查后不应失败；若旧入口状态异常，尽量原位恢复，绝不凭类型造第二张牌。
		if card_a != null:
			pA.equip_card_to_slot(slot_a, card_a)
		if card_b != null:
			pB.equip_card_to_slot(slot_b, card_b)
		return false
	pA.equip_card_to_slot(slot_a, card_b)
	pB.equip_card_to_slot(slot_b, card_a)
	_update_debug("交换了 %s 的【%s】与 %s 的【%s】" % [pA.player_name, CardData.get_type_name(subA), pB.player_name, CardData.get_type_name(subB)])
	return true

# ============================
#  【烂忠厚】麦克斯·欧尼斯特：回合开始阶段摸一张牌，跳过自己的一个阶段，令其他角色立刻获得对应阶段
#  选项1（判定）：目标立刻判定，其乐不思蜀/兵粮寸断失效（闪电/火烧连营正常生效）
#  选项2（摸牌）：目标立刻摸 2 张；选项3（出牌）：目标立刻获得出牌阶段，AI使用共同决策入口。
# ============================

# 回合开始阶段询问：是否发动 + 三选一 + 选择目标（由 _do_start 调用）
func _maybe_meiyong(p: Player) -> void:
	if p.general_name != "麦克斯·欧尼斯特" or not p.is_alive():
		return
	# AI策略暂不主动发动此技能；获得的出牌阶段仍正常决策。
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
	_update_debug("%s 发动【烂忠厚】！摸了 1 张牌（手牌 %d 张），选择跳过一个阶段" % [p.player_name, p.hand_size()])
	# 三选一（取消 → 收回已摸的牌）
	var option := -1
	if _meiyong_option_override.is_valid():
		option = _meiyong_option_override.call()
	else:
		option = await _show_meiyong_option_prompt()
	if option < 0 or option > 2:
		p.hand.pop_back()
		_update_debug("取消【烂忠厚】（已摸的牌收回）")
		return
	match option:
		0:
			var target0 = await _pick_meiyong_target(0, p)
			if target0 == null:
				_update_debug("没有可选的判定目标，【烂忠厚】未生效（已摸的牌保留）")
				return
			turn_manager.granted_judge_target_idx = target0.seat_index
			_update_debug("%s 跳过自己的判定阶段！%s 立刻进行判定阶段（其乐不思蜀/兵粮寸断失效，闪电/火烧连营正常生效）" % [p.player_name, target0.player_name])
		1:
			var target1 = await _pick_meiyong_target(1, p)
			if target1 == null:
				_update_debug("没有可选的摸牌目标，【烂忠厚】未生效（已摸的牌保留）")
				return
			turn_manager.granted_draw_target_idx = target1.seat_index
			_update_debug("%s 跳过自己的摸牌阶段！%s 立刻获得一个摸牌阶段" % [p.player_name, target1.player_name])
		2:
			var target2 = await _pick_meiyong_target(2, p)
			if target2 == null:
				_update_debug("没有可选的出牌目标，【烂忠厚】未生效（已摸的牌保留）")
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
	_update_debug("【烂忠厚】：请点击一名角色的头像（%s）" % ("判定区有牌的角色" if option == 0 else "任意其他角色"))
	var target = await _meiyong_pick_result
	return target

# 烂忠厚目标点击：单选，点击即生效
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

# 是否发动【烂忠厚】（玩家0弹窗）
func _show_meiyong_activate_prompt() -> bool:
	var idx = await _show_choice_popup("是否发动【烂忠厚】？\n（摸一张牌，然后跳过你的判定/摸牌/出牌阶段之一，令一名其他角色立刻获得对应阶段）", ["发动", "不发动"])
	return idx == 0

# 三选一（玩家0弹窗）：返回 0/1/2，-1 = 取消
func _show_meiyong_option_prompt() -> int:
	var idx = await _show_choice_popup("选择【烂忠厚】的效果：", [
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
func _try_bloodthirsty(source: Player, victim: Player, amount: int) -> int:
	if source == null or victim == null or source == victim:
		return 0
	if not source.is_alive() or not victim.is_alive():
		return 0
	if source.get_weapon() != CardData.CardSubType.BLOODTHIRSTY_BLADE:
		return 0
	# 【青釭盾】：目标无视使用效果者的武器
	if victim.get_armor() == CardData.CardSubType.QINGGANG_SHIELD:
		_update_debug("%s 的【青釭盾】无视了 %s 的【噬血之刃】！" % [victim.player_name, source.player_name])
		return 0
	var original = source.get_equipment_card("weapon")
	var revision = turn_manager.get_context_revision()
	var valid = func():
		return not _game_over and revision == turn_manager.get_context_revision() \
			and players.has(source) and players.has(victim) \
			and source.is_alive() and victim.is_alive() and original != null \
			and source.get_equipment_card("weapon") == original \
			and victim.get_armor() != CardData.CardSubType.QINGGANG_SHIELD
	for i in amount:
		if not valid.call():
			return CHOICE_INVALID
		# 可选择是否发动（每一点伤害独立询问）
		var use = await _ask_bloodthirsty(source, victim, valid)
		if use == CHOICE_INVALID or not valid.call():
			return CHOICE_INVALID
		if use == 0:
			continue
		var r = await _do_ping_dian(source, victim, valid)
		if r == RPS_INVALID or not valid.call():
			return CHOICE_INVALID
		if r == RPS_WIN:
			source.heal(1)
			_update_debug("%s 赢得拼点，回复 1 点体力（%d/%d）" % [source.player_name, source.hp, source.max_hp])
	_sync_all_ui()
	return 0

# 是否发动噬血之刃：玩家0弹窗，AI 不满血才发动
func _ask_bloodthirsty(source: Player, victim: Player, allowed: Callable = Callable()) -> int:
	if _bloodthirsty_override.is_valid():
		var reply = await _bloodthirsty_override.call()
		if typeof(reply) == TYPE_INT and reply == CHOICE_INVALID:
			return CHOICE_INVALID
		return 1 if reply else 0
	if source.seat_index == 0:
		return await _show_bloodthirsty_prompt(source, victim, allowed)
	return 1 if source.hp < source.max_hp else 0

# 玩家0的噬血之刃发动确认弹窗（锚点居中）
func _show_bloodthirsty_prompt(source: Player, victim: Player, allowed: Callable = Callable()) -> int:
	if _game_over or (allowed.is_valid() and not allowed.call()):
		return CHOICE_INVALID
	var answer = ChoicePromptAnswer.new()
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

	use_btn.pressed.connect(func(): answer.submit(1), CONNECT_ONE_SHOT)
	skip_btn.pressed.connect(func(): answer.submit(0), CONNECT_ONE_SHOT)
	return await _wait_choice_prompt(overlay, answer, allowed, false)

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
func _try_calamity_transfer(source: Player) -> int:
	if _game_over or source == null or not source.is_alive():
		return 0
	if source.get_weapon() != CardData.CardSubType.CALAMITY_SWORD:
		return 0
	var original_card = source.get_equipment_card("weapon")
	if original_card == null:
		return 0
	var revision = turn_manager.get_context_revision()
	var valid = func():
		return not _game_over and revision == turn_manager.get_context_revision() \
			and players.has(source) and source.is_alive() \
			and source.get_equipment_card("weapon") == original_card
	var target = await _ask_calamity_target(source, valid)
	if (target is int and target == CHOICE_INVALID) or not valid.call():
		return CHOICE_INVALID
	if target == null:
		_update_debug("%s 放弃转移【灾厄剑】" % source.player_name)
		return 0
	if not target is Player or not players.has(target) or target == source or not target.is_alive():
		return CHOICE_INVALID
	# 等待目标选择期间若原剑离区或同槽换牌，不得先弃掉目标原装备。
	if source.equipment.get("weapon", -1) != CardData.CardSubType.CALAMITY_SWORD \
			or source.equipment_cards.get("weapon", null) != original_card:
		return CHOICE_INVALID
	# 目标武器槽：已有武器则替换（旧武器进弃牌堆）
	if target.equipment.has("weapon"):
		var old_card = target.remove_equipment("weapon")
		if old_card != null:
			deck.discard(old_card)
	var calamity_sword = source.remove_equipment("weapon")
	if calamity_sword == null:
		return CHOICE_INVALID
	target.equip_card_to_slot("weapon", calamity_sword)
	_update_debug("%s 将【灾厄剑】移至 %s 的装备区（%s 造成的伤害-1）" % [source.player_name, target.player_name, target.player_name])
	_sync_all_ui()
	return 0

# 选择灾厄剑转移目标：玩家0弹窗，AI 默认发动随机选一名其他存活角色
func _ask_calamity_target(source: Player, allowed: Callable = Callable()) -> Variant:
	if _calamity_target_override.is_valid():
		var r = await _calamity_target_override.call()
		if r is String and r == "cancel":
			return null
		return r
	if source.seat_index == 0:
		return await _show_calamity_target_picker(source, allowed)
	var alive_others: Array[Player] = []
	for p in players:
		if p != source and p.is_alive():
			alive_others.append(p)
	if alive_others.is_empty():
		return null
	return alive_others[randi() % alive_others.size()]

# 玩家0的灾厄剑转移目标弹窗（其他存活角色按钮 + 取消，锚点居中）
func _show_calamity_target_picker(source: Player, allowed: Callable = Callable()) -> Variant:
	if _game_over or (allowed.is_valid() and not allowed.call()):
		return CHOICE_INVALID
	var answer = ChoicePromptAnswer.new()
	var candidates: Array[Player] = []
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
		var index = candidates.size()
		candidates.append(p)
		btn.pressed.connect(func(): answer.submit(index), CONNECT_ONE_SHOT)
		hbox.add_child(btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(140, 44)
	cancel_btn.modulate = Color(0.7, 0.7, 0.7)
	cancel_btn.pressed.connect(func():
		answer.submit(-1)
	, CONNECT_ONE_SHOT)
	vbox.add_child(cancel_btn)

	var result = await _wait_choice_prompt(overlay, answer, allowed, false)
	if result == CHOICE_INVALID:
		return CHOICE_INVALID
	return candidates[result] if result >= 0 and result < candidates.size() else null

func _emit_calamity_target(overlay: ColorRect, target: Player):
	overlay.queue_free()
	_calamity_target_result.emit(target)

# ============================
#  【灾厄袍】受伤后转移
# ============================

# 灾厄袍：当你受到一次伤害后，可将本装备移至一名其他角色的装备区
# 目标已有防具则替换（旧防具进弃牌堆）；EquipmentPool 占用永久保留（不解除）
func _try_calamity_robe_transfer(victim: Player) -> int:
	if victim == null or not victim.is_alive():
		return 0
	if victim.get_armor() != CardData.CardSubType.CALAMITY_ROBE:
		return 0
	var original_card = victim.get_equipment_card("armor")
	if original_card == null:
		return 0
	var revision = turn_manager.get_context_revision()
	var allowed = func():
		return not _game_over and revision == turn_manager.get_context_revision() \
			and players.has(victim) and victim.is_alive() \
			and victim.get_armor() == CardData.CardSubType.CALAMITY_ROBE \
			and victim.get_equipment_card("armor") == original_card
	var target = await _ask_calamity_robe_target(victim, allowed)
	if target is int or not allowed.call():
		return CHOICE_INVALID
	if target == null:
		_update_debug("%s 放弃转移【灾厄袍】" % victim.player_name)
		return 0
	if not target is Player or not players.has(target) or target == victim or not target.is_alive():
		return CHOICE_INVALID
	# 目标防具槽：已有防具则替换（旧防具进弃牌堆）
	if target.equipment.has("armor"):
		var old_card = target.remove_equipment("armor")
		if old_card != null:
			deck.discard(old_card)
	var calamity_robe = victim.remove_equipment("armor")
	if calamity_robe == null:
		return CHOICE_INVALID
	target.equip_card_to_slot("armor", calamity_robe)
	_update_debug("%s 将【灾厄袍】移至 %s 的装备区（%s 受到的火焰伤害+1）" % [victim.player_name, target.player_name, target.player_name])
	_sync_all_ui()
	return 0

# 选择灾厄袍转移目标：玩家0弹窗，AI 默认发动随机选一名其他存活角色
func _ask_calamity_robe_target(victim: Player, allowed: Callable = Callable()) -> Variant:
	if _calamity_robe_target_override.is_valid():
		var r = _calamity_robe_target_override.call()
		if r is String and r == "cancel":
			return null
		return r
	if victim.seat_index == 0:
		return await _show_calamity_robe_target_picker(victim, allowed)
	var alive_others: Array[Player] = []
	for p in players:
		if p != victim and p.is_alive():
			alive_others.append(p)
	if alive_others.is_empty():
		return null
	return alive_others[randi() % alive_others.size()]

# 玩家0的灾厄袍转移目标弹窗（其他存活角色按钮 + 取消，锚点居中）
func _show_calamity_robe_target_picker(victim: Player, allowed: Callable = Callable()) -> Variant:
	var answer = ChoicePromptAnswer.new()
	var candidates: Array[Player] = []
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
		var index = candidates.size()
		candidates.append(p)
		btn.text = p.player_name
		btn.custom_minimum_size = Vector2(140, 44)
		btn.pressed.connect(func(): answer.submit(index), CONNECT_ONE_SHOT)
		hbox.add_child(btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(140, 44)
	cancel_btn.modulate = Color(0.7, 0.7, 0.7)
	cancel_btn.pressed.connect(func(): answer.submit(-1), CONNECT_ONE_SHOT)
	vbox.add_child(cancel_btn)

	var result = await _wait_choice_prompt(overlay, answer, allowed, false)
	if result == CHOICE_INVALID:
		return CHOICE_INVALID
	if result < 0:
		return null
	return candidates[result] if result < candidates.size() else CHOICE_INVALID

func _emit_calamity_robe_target(overlay: ColorRect, target: Player):
	overlay.queue_free()
	_calamity_robe_target_result.emit(target)

# ============================
#  【劣马】转移（灾厄剑/灾厄袍式）
# ============================

# -1劣马：你受到伤害后，可移动一匹 -1劣马至一名其他角色的装备区（灾厄袍式时机；甩掉让自己更容易被打的劣马）
func _try_minus_mule_transfer(source: Player) -> int:
	return await _try_mule_transfer(source, CardData.CardSubType.MULE_MINUS, true)

# +1劣马：与 -1 劣马一致，受到伤害后可转移。
func _try_plus_mule_transfer(source: Player) -> int:
	return await _try_mule_transfer(source, CardData.CardSubType.MULE_PLUS, false)

# 劣马转移核心：空槽直接装；满槽由转移者必须选择被顶掉的马。
func _try_mule_transfer(p: Player, mule_sub: CardData.CardSubType, is_minus: bool) -> int:
	if _game_over or p == null or not p.is_alive():
		return 0
	var source_slot := ""
	var original_card: CardBase = null
	for s in Player.MOUNT_SLOTS:
		if p.equipment.get(s, -1) == mule_sub:
			source_slot = s
			original_card = p.get_equipment_card(s)
			break
	if original_card == null:
		return 0
	var revision = turn_manager.get_context_revision()
	var allowed = func():
		return not _game_over and revision == turn_manager.get_context_revision() \
			and players.has(p) and p.is_alive() and p.equipment.get(source_slot, -1) == mule_sub \
			and p.get_equipment_card(source_slot) == original_card
	var target = await _ask_mule_target(p, is_minus, allowed)
	if target is int or not allowed.call():
		return CHOICE_INVALID
	if target == null:
		return 0
	if not target is Player or not players.has(target) or target == p or not target.is_alive():
		return CHOICE_INVALID
	var replace_slot := ""
	if target.mount_count() == Player.MOUNT_SLOTS.size():
		var originals: Dictionary = {}
		for slot in Player.MOUNT_SLOTS:
			originals[slot] = _equipment_resource_for_pick(target, slot)
		var replacement_valid = func():
			return allowed.call() and players.has(target) and target.is_alive() \
				and target.mount_count() == Player.MOUNT_SLOTS.size() \
				and Player.MOUNT_SLOTS.all(func(slot): return originals[slot] != null and _equipment_resource_for_pick(target, slot) == originals[slot])
		# 最新Q1：选择权属于转移者；AI沿用第一槽策略，非固定规则。
		replace_slot = await _show_mule_replace_picker(target, replacement_valid) if p.seat_index == 0 else target.get_mount_slots()[0]
		if not replacement_valid.call() or not originals.has(replace_slot):
			return CHOICE_INVALID
	var mule_card = p.remove_equipment(source_slot)
	if mule_card == null:
		return CHOICE_INVALID
	# 目标放入坐骑槽
	if not _place_mount_for(target, mule_card, replace_slot):
		# 落位失败时原槽仍为空；恢复同一对象而非另造一匹劣马。
		p.equip_card_to_slot(source_slot, mule_card)
		return CHOICE_INVALID
	var mule_name = "-1劣马" if is_minus else "+1劣马"
	_update_debug("%s 将一匹【%s】移至 %s 的装备区" % [p.player_name, mule_name, target.player_name])
	_sync_all_ui()
	return 0

# 选择劣马转移目标：玩家0弹窗，AI 默认发动随机选一名其他存活角色
func _ask_mule_target(p: Player, is_minus: bool, allowed: Callable = Callable()) -> Variant:
	var override_var = _minus_mule_target_override if is_minus else _plus_mule_target_override
	if override_var.is_valid():
		var r = override_var.call()
		if r is String and r == "cancel":
			return null
		return r
	if p.seat_index == 0:
		return await _show_mule_target_picker(p, is_minus, allowed)
	var alive_others: Array[Player] = []
	for pl in players:
		if pl != p and pl.is_alive():
			alive_others.append(pl)
	if alive_others.is_empty():
		return null
	return alive_others[randi() % alive_others.size()]

# 玩家0的劣马转移目标弹窗（其他存活角色按钮 + 取消，锚点居中）
func _show_mule_target_picker(p: Player, is_minus: bool, allowed: Callable = Callable()) -> Variant:
	var answer = ChoicePromptAnswer.new()
	var candidates: Array[Player] = []
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
		var index = candidates.size()
		candidates.append(pl)
		btn.text = pl.player_name
		btn.custom_minimum_size = Vector2(140, 44)
		btn.pressed.connect(func(): answer.submit(index), CONNECT_ONE_SHOT)
		hbox.add_child(btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(140, 44)
	cancel_btn.modulate = Color(0.7, 0.7, 0.7)
	cancel_btn.pressed.connect(func(): answer.submit(-1), CONNECT_ONE_SHOT)
	vbox.add_child(cancel_btn)

	var result = await _wait_choice_prompt(overlay, answer, allowed, false)
	if result == CHOICE_INVALID:
		return CHOICE_INVALID
	if result < 0:
		return null
	return candidates[result] if result < candidates.size() else CHOICE_INVALID

func _emit_minus_mule_target(overlay: ColorRect, target: Player):
	overlay.queue_free()
	_minus_mule_target_result.emit(target)

func _emit_plus_mule_target(overlay: ColorRect, target: Player):
	overlay.queue_free()
	_plus_mule_target_result.emit(target)

# 满四槽时由转移者强制选择：无倒计时、无取消，不发明超时默认。
func _show_mule_replace_picker(target: Player, allowed: Callable) -> String:
	if not allowed.call():
		return ""
	var answer = ChoicePromptAnswer.new()
	var slots = target.get_mount_slots()
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
	label.text = "转移劣马：%s 的坐骑槽已满，请选择顶掉其哪匹坐骑（必须选择）" % target.player_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(label)
	for index in slots.size():
		var slot = slots[index]
		var button = Button.new()
		button.text = "%s：%s" % [Player.EQUIP_SLOT_NAMES[slot], CardData.get_type_name(target.equipment[slot])]
		button.custom_minimum_size = Vector2(220, 44)
		button.pressed.connect(func(): answer.submit(index), CONNECT_ONE_SHOT)
		vbox.add_child(button)
	var selected = await _wait_choice_prompt(overlay, answer, allowed, false)
	return slots[selected] if selected >= 0 and selected < slots.size() and allowed.call() else ""

# 放入空槽或已由转移者选定的原槽；不在资源层自行决定顶掉哪匹。
func _place_mount_for(target: Player, card: CardBase, replace_slot: String = "") -> bool:
	if target.equip_mount_card(card):
		return true
	if not Player.MOUNT_SLOTS.has(replace_slot) or not target.equipment.has(replace_slot):
		return false
	var result = target.replace_mount_card_result(replace_slot, card)
	if result.success and result.replaced_card != null:
		deck.discard(result.replaced_card)
	return result.success

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
func _try_soul_blade(source: Player, victim: Player) -> int:
	if source == null or victim == null or source == victim:
		return 0
	if not source.is_alive() or not victim.is_alive():
		return 0
	if source.get_weapon() != CardData.CardSubType.SOUL_BLADE:
		return 0
	# 【青釭盾】：目标无视使用效果者的武器
	if victim.get_armor() == CardData.CardSubType.QINGGANG_SHIELD:
		_update_debug("%s 的【青釭盾】无视了 %s 的【摄魂刀】！" % [victim.player_name, source.player_name])
		return 0
	if not source.soul_blade_activated:
		return 0
	var original = source.get_equipment_card("weapon")
	var revision = turn_manager.get_context_revision()
	var valid = func():
		return not _game_over and revision == turn_manager.get_context_revision() \
			and players.has(source) and players.has(victim) and original != null \
			and source.is_alive() and victim.is_alive() \
			and source.get_equipment_card("weapon") == original \
			and source.get_weapon() == CardData.CardSubType.SOUL_BLADE \
			and source.soul_blade_activated and victim.get_armor() != CardData.CardSubType.QINGGANG_SHIELD

	# 是否发动拼点（玩家0弹窗 / AI 默认发动）
	if source.seat_index == 0:
		var activate = await _ask_soul_blade_activate(victim.player_name, valid)
		if activate == CHOICE_INVALID or not valid.call():
			return CHOICE_INVALID
		if activate == 0:
			return 0

	# 进行两次拼点（每次平局继续直到分出胜负）
	var r1 = await _do_ping_dian(source, victim, valid)
	if r1 == RPS_INVALID or not valid.call():
		return CHOICE_INVALID
	var r2 = await _do_ping_dian(source, victim, valid)
	if r2 == RPS_INVALID or not valid.call():
		return CHOICE_INVALID
	var wins = 0
	if r1 == RPS_WIN:
		wins += 1
	if r2 == RPS_WIN:
		wins += 1

	if wins == 2:
		_update_debug("%s 拼点全赢！" % source.player_name)
		_flip_character(victim)
		return 0

	# 赢一输一弃 2 张；全输弃 4 张（可选；手牌不足无法发动）
	var need = 2 if wins == 1 else 4
	if source.hand_size() < need:
		_update_debug("%s 手牌不足 %d 张，无法弃牌令 %s 翻面" % [source.player_name, need, victim.player_name])
		return 0
	if source.seat_index == 0:
		var discard_reply = await _ask_soul_blade_discard(victim.player_name, need, valid)
		if discard_reply == CHOICE_INVALID or not valid.call():
			return CHOICE_INVALID
		if discard_reply == 0:
			return 0
	var payment = await _select_hand_discard_result(source, need, false, valid)
	if payment != HandDiscardOutcome.PAID:
		if payment in [HandDiscardOutcome.ACTION_INVALIDATED, HandDiscardOutcome.GAME_ENDED, HandDiscardOutcome.STALE_SELECTION] or not valid.call():
			return CHOICE_INVALID
		return 0
	_update_debug("%s 弃置 %d 张手牌，令 %s 武将牌翻面" % [source.player_name, need, victim.player_name])
	_sync_all_ui()
	_flip_character(victim)
	return 0

# 翻面 = 状态切换：正面↔反面；反面角色下个回合开始前自动翻回并跳过回合
func _flip_character(p: Player):
	p.facedown = not p.facedown
	if p.facedown:
		_update_debug("%s 武将牌翻面（反面）：其下个回合将被跳过" % p.player_name)
	else:
		_update_debug("%s 武将牌翻回正面" % p.player_name)
	_sync_all_ui()

# 玩家0是否发动摄魂刀拼点
func _ask_soul_blade_activate(victim_name: String, allowed: Callable = Callable()) -> int:
	if _soul_blade_activate_override.is_valid():
		var reply = await _soul_blade_activate_override.call()
		if typeof(reply) == TYPE_INT and reply == CHOICE_INVALID:
			return CHOICE_INVALID
		return 1 if reply else 0
	return await _show_soul_blade_activate_prompt(victim_name, allowed)

func _show_soul_blade_activate_prompt(victim_name: String, allowed: Callable = Callable()) -> int:
	if _game_over or (allowed.is_valid() and not allowed.call()):
		return CHOICE_INVALID
	var answer = ChoicePromptAnswer.new()
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

	use_btn.pressed.connect(func(): answer.submit(1), CONNECT_ONE_SHOT)
	skip_btn.pressed.connect(func(): answer.submit(0), CONNECT_ONE_SHOT)
	return await _wait_choice_prompt(overlay, answer, allowed, false)

# 玩家0是否弃 need 张手牌令目标翻面
func _ask_soul_blade_discard(victim_name: String, need: int, allowed: Callable = Callable()) -> int:
	if _soul_blade_discard_override.is_valid():
		var reply = await _soul_blade_discard_override.call()
		if typeof(reply) == TYPE_INT and reply == CHOICE_INVALID:
			return CHOICE_INVALID
		return 1 if reply else 0
	return await _show_soul_blade_discard_prompt(victim_name, need, allowed)

func _show_soul_blade_discard_prompt(victim_name: String, need: int, allowed: Callable = Callable()) -> int:
	if _game_over or (allowed.is_valid() and not allowed.call()):
		return CHOICE_INVALID
	var answer = ChoicePromptAnswer.new()
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

	use_btn.pressed.connect(func(): answer.submit(1), CONNECT_ONE_SHOT)
	skip_btn.pressed.connect(func(): answer.submit(0), CONNECT_ONE_SHOT)
	return await _wait_choice_prompt(overlay, answer, allowed, false)

# 询问所有存活角色是否打出【舍己为人】代替 target 承受即将到来的伤害
# 返回打出者（null = 无人打出）
# 规则：受伤者本人不能使用；AI 暂不主动打出（与无懈一致）；玩家0有手牌时弹窗询问
func _maybe_sacrifice(_source: Player, target: Player, amount: int, _element: EffectChain.DamageType, allowed: Callable = Callable()) -> Player:
	var reply = await _maybe_sacrifice_result(_source, target, amount, _element, allowed)
	return null if reply.invalidated else reply.player

# 生产伤害链必须区分无人舍己与旧窗口失效，不能仅用null猜测。
func _maybe_sacrifice_result(_source: Player, target: Player, amount: int, _element: EffectChain.DamageType, allowed: Callable = Callable()) -> Dictionary:
	var revision = turn_manager.get_context_revision()
	var valid = func():
		return not _game_over and revision == turn_manager.get_context_revision() \
			and target.is_alive() and (not allowed.is_valid() or allowed.call())
	for i in range(player_count):
		if not valid.call():
			return {"invalidated": true, "player": null}
		var p = players[i]
		if p == target or not p.is_alive():
			continue
		# 【下跪】：无法使用或打出任何牌 → 不能打出舍己为人
		if _is_kneeling(p):
			continue

		var snapshot = HandSelection.new(p)
		var play = "skip"
		if _sacrifice_actor_override.is_valid():
			play = "card" if await _sacrifice_actor_override.call(p, target, amount) else "skip"
		elif p.seat_index == 0:
			play = await _show_sacrifice_prompt(target, amount, valid)
		else:
			var options: Array = [CardData.CardSubType.SACRIFICE] if HandPayment.has_card(p, CardData.CardSubType.SACRIFICE) else []
			if await _choose_ai_response(p, "sacrifice", options, {"target": target.seat_index, "amount": amount}) == CardData.CardSubType.SACRIFICE:
				play = "card"

		if play == "invalidated" or not valid.call():
			return {"invalidated": true, "player": null}
		if play != "skip":
			if not p.is_alive() or _is_kneeling(p) or p.hand != snapshot.hand or p.determined_cards != snapshot.determined:
				continue
			# 【是~啊~】（安普提·斯丢皮得）：确认使用舍己为人后询问是否发动（发动流失体力不消耗手牌；无手牌时取消 = 视为没有打出）
			var yes_ah = play
			if yes_ah == "card":
				yes_ah = await _ask_yes_ah(p, "舍己为人", HandPayment.has_card(p, CardData.CardSubType.SACRIFICE), true)
			if yes_ah == "invalidated" or not valid.call():
				return {"invalidated": true, "player": null}
			if not p.is_alive() or _is_kneeling(p) or p.hand != snapshot.hand or p.determined_cards != snapshot.determined:
				continue
			if yes_ah == "cancel":
				_update_debug("%s 取消了打出【舍己为人】" % p.player_name)
				_sync_all_ui()
				continue
			var action_card: CardBase
			if yes_ah == "skill":
				var paid = await _pay_yes_ah_cost(p)
				if not valid.call():
					return {"invalidated": true, "player": null}
				if not paid:
					_sync_all_ui()
					continue
				action_card = CardBase.create(CardData.CardSubType.SACRIFICE)
			else:
				var used_card = HandPayment.take_card(p, CardData.CardSubType.SACRIFICE)
				if used_card == null:
					continue
				deck.discard(used_card)
				action_card = used_card
			_sync_all_ui()
			if not valid.call() or not p.is_alive():
				return {"invalidated": true, "player": null} # 已支付的费用不回滚。
			_record_card_action(p, action_card, CardActionEvent.Kind.USE, yes_ah != "skill", yes_ah == "skill")
			if not valid.call():
				return {"invalidated": true, "player": null}
			return {"invalidated": false, "player": p}
	return {"invalidated": false, "player": null}

# 玩家0的【舍己为人】响应弹窗（锚点居中）：返回 "card"（打出，消耗手牌）/ "skill"（发动【是~啊~】打出，无手牌时）/ "skip"（放弃）
func _show_sacrifice_prompt(target: Player, amount: int, allowed: Callable = Callable()) -> String:
	var p = players[0]
	var has_hand = HandPayment.has_card(p, CardData.CardSubType.SACRIFICE)
	var is_yes_ah = p.general_name == "安普提·斯丢皮得"
	# 测试钩子只决定意愿；无匹配牌时仅安普提可通过【是~啊~】打出。
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
		label.text += "\n（无可用的舍己或任意牌，可发动【是~啊~】流失 1 点体力视为打出）"
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

	var answer = ChoicePromptAnswer.new()
	sacrifice_btn.pressed.connect(answer.submit.bind(1))
	skip_btn.pressed.connect(answer.submit.bind(0))
	var result = await _wait_choice_prompt(overlay, answer, allowed)
	if result == CHOICE_INVALID:
		return "invalidated"
	return ("card" if has_hand else "skill") if result == 1 else "skip"

# ============================
#  濒死结算
# ============================

# 【治疗权杖】：每个回合内（含其他玩家的回合），装备者使用的第一张桃额外回复 1 点体力
# 计数按玩家存（heal_staff_peach_used），回合开始时统一重置；出牌阶段用桃与濒死自救共用
func _heal_with_staff(p: Player, recipient: Player = null) -> int:
	if recipient == null:
		recipient = p
	var amount = 1
	if p.get_weapon() == CardData.CardSubType.HEAL_STAFF and not p.heal_staff_peach_used \
			and recipient.get_armor() != CardData.CardSubType.QINGGANG_SHIELD:
		amount = 2
		_update_debug("%s 发动【治疗权杖】：本回合第一张【桃】额外回复 1 点体力" % p.player_name)
	# 记录出桃者的首次使用；中途装备或解除目标青釭盾不能补触发。
	p.heal_staff_peach_used = true
	recipient.heal(amount)
	return amount

# 统一濒死入口：所有伤害/流失来源都先完成救援，再开放死亡前规则。
# 同一窗口的重入直接返回，不能等待自身；这不是重复请求的完成等待接口。
# before_death 的上下文为 DyingContext，原效果链在 context.effect_chain。
func _resolve_dying(victim: Player, killer: Player, cause: String, chain: EffectChain = null):
	if _game_over or victim == null or not players.has(victim) or not victim.is_dying():
		return
	if _dying_contexts.has(victim):
		return
	var context = DyingContext.new(victim, killer, cause, chain)
	_dying_contexts[victim] = context
	await _check_dying(victim)
	if not _game_over and victim.is_dying():
		context.stage = DyingContext.Stage.BEFORE_DEATH
		# 锁定规则先于普通检查点；里奥尚未加入选将表，完整武将仍待开发。
		if victim.general_name == "里奥·普利威尔":
			await yudaxi.resolve(victim, _yudaxi_targets, _settle_yudaxi_target,
				_draw_blank_cards, func(): return _game_over, _on_yudaxi_limit)
		if not _game_over and victim.is_dying() and not yudaxi.is_active():
			await rule_scheduler.checkpoint(context, "before_death")
	if not _game_over and victim.is_dying():
		context.stage = DyingContext.Stage.FINAL_DEATH
		_handle_death(victim, context.killer)
	context.stage = DyingContext.Stage.FINISHED
	_dying_contexts.erase(victim)
	_sync_all_ui()
	_check_win_condition(null, null)

# 暂行 S3：当前 players 仅为玩家角色，不把未来单位混入此名单。
# 沿当前空间/行动数组从发动者下家起算；排除正在等待死亡前规则的角色。
func _yudaxi_targets(owner: Player) -> Array[Player]:
	var targets: Array[Player] = []
	var start = players.find(owner)
	if start < 0:
		return targets
	for offset in range(1, players.size()):
		var target = players[(start + offset) % players.size()]
		if target.is_alive() and not _dying_contexts.has(target):
			targets.append(target)
	return targets

func _settle_yudaxi_target(target: Player):
	# 扣除体力没有伤害来源/击杀奖励，仍允许普通求救及既定保命技能。
	_sync_all_ui()
	await _resolve_dying(target, null, "yudaxi")

func _on_yudaxi_limit():
	# 终止悬挂的外层伤害链，不在平局后继续普通伤害后技能。
	for context in _dying_contexts.values():
		if context.effect_chain != null:
			context.effect_chain.is_cancelled = true
			context.effect_chain.response_result = EffectChain.ResponseResult.CANCELED
	_finish_game("平局", "预大习超过安全结算步数（%d）" % yudaxi.step_limit)

# 濒死救援子流程：不确认死亡；生产调用统一经过 _resolve_dying。
# 阵亡管线（阶段划分，按朋友要求顺序）：
#   濒死结算（本函数）→ 自救【桃/酒】→ 阵亡效果·【装傻】（濒死拼点回血，阻止阵亡）→ 阵亡效果·【贤者的加护】（弃所有牌复原，阻止阵亡）
#   → 调用方完成死亡前规则后判 is_dying()：仍濒死才进入 _handle_death（确认死亡 → 翻开身份 → 清牌 → 击杀奖惩 → 胜负判定）
func _check_dying(dying: Player):
	if not dying.is_dying():
		return

	_update_debug("%s 进入濒死状态！" % dying.player_name)

	if not players.has(dying):
		return

	# 经典基线：从当前回合角色开始轮询，含濒死本人；放弃后本窗口不回头。
	# 普通求救全部结束后，才进入既有装傻/贤者及死亡前规则。
	await _run_rescue_round(dying)
	if _game_over:
		return

	# 桃/酒自救后仍处于濒死 → 阵亡效果·【装傻】（安普提·斯丢皮得，锁定技）：与所有存活玩家拼点，赢至少一半（向上取整）回复至 1 点体力
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
# 调用时机：濒死结算（_check_dying）及死亡前规则全部结束，角色仍处于濒死状态
#   阶段1 阵亡判定 —— 确认阵亡（体力 ≤ 0），防重复处理
#   阶段2 翻开身份 —— identity_revealed = true，无身份则不公开
#   阶段3 清理牌区 —— 弃置所有手牌/装备/判定牌/已确定牌
#   阶段4 击杀奖惩 —— 杀死【反贼】：击杀者摸 3 张；主公杀死【忠臣】：主公弃置所有手牌和装备
#   阶段5 胜负判定 —— 五人标准身份局按已死亡/仍存活身份判定；不依赖凶手身份
func _handle_death(victim: Player, killer: Player):
	# ---- 阶段1 阵亡判定 ----
	# 活跃窗口由统一入口提交，规则回调不能绕过尚未结束的救援/死亡前规则。
	if _dying_contexts.has(victim) and _dying_contexts[victim].stage != DyingContext.Stage.FINAL_DEATH:
		return
	if _dead_processed.has(victim):
		return
	if not victim.is_dying():
		return
	victim.mark_dead()
	_dead_processed.append(victim)
	_update_debug("%s 阵亡！" % victim.player_name)

	# ---- 阶段2 翻开身份：清牌及失去装备效果必须能观察到已公开状态 ----
	if victim.identity != "":
		victim.identity_revealed = true
		_update_debug("身份翻开：%s 是【%s】！" % [victim.player_name, victim.identity])

	# ---- 阶段3 清理牌区：此时已最终死亡，白银狮子等不能将其救回 ----
	_discard_all_cards(victim, true)
	_update_debug("%s 弃置了所有牌（手牌/装备/判定牌）" % victim.player_name)
	_sync_all_ui()

	# ---- 阶段4 击杀奖惩（仅身份局；乱斗明确没有击杀奖励）----
	if game_mode == MODE_CLASSIC_IDENTITY and not _game_over and killer != null and killer.is_alive():
		if victim.identity == "反贼":
			_draw_blank_cards(killer, 3)
			_update_debug("奖惩：%s 击杀【反贼】%s，摸 3 张牌！（%d 张）" % [killer.player_name, victim.player_name, killer.hand_size()])
		elif victim.identity == "忠臣" and killer.identity == "主公":
			_discard_all_cards(killer, false)
			_update_debug("奖惩：主公 %s 误杀忠臣 %s，弃置所有手牌和装备！（%d 张手牌）" % [killer.player_name, victim.player_name, killer.hand_size()])

	# ---- 阶段5 胜负判定 ----
	_check_win_condition(victim, killer)

# 弃置一名角色的所有牌（死亡弃置 / 主公杀忠臣惩罚共用）
# include_judgment 只控制判定区；已确定牌属于手牌，死亡和主公惩罚均须弃置。
func _discard_all_cards(p: Player, include_judgment: bool):
	# 全清沿用区内原顺序；普通数量费用仍使用自动尾部选择策略。
	for cards in [p.hand, p.determined_cards]:
		for card in cards:
			if card != null:
				deck.discard(card)
		cards.clear()
	for slot in p.get_equip_slots():
		var equipment_card = p.remove_equipment(slot)
		# 暗置装备也有原牌资源；最终死亡/惩罚弃置时保持暗置，不凭空明置。
		if equipment_card != null:
			deck.discard(equipment_card)
	if include_judgment:
		for c in p.judgment_cards:
			if c != null:
				deck.discard(c)
		p.judgment_cards.clear()
		p.hidden_equip_slot = ""

# 弃牌/技能费用的公共记账，不调用烈火盾；盾只在拆/顺成为目标时询问。
# 不把任意牌占位制造为某种具体牌；具体牌则以原实例入弃牌堆一次。
func _discard_hand_cards(p: Player, count: int) -> bool:
	if p == null or count < 0 or p.hand_size() < count:
		return false
	if count == 0:
		return true
	for card in p.take_hand_cards(count):
		if card != null:
			deck.discard(card)
	return true

enum HandDiscardOutcome {
	PAID,
	DECLINED,
	STALE_SELECTION,
	ACTION_INVALIDATED,
	INSUFFICIENT_CARDS,
	GAME_ENDED,
}

# 兼容尚未迁移的调用者；不能用false推断玩家主动拒绝。
func _select_hand_discard(p: Player, count: int, mandatory: bool, allowed: Callable = Callable()) -> bool:
	var outcome = await _select_hand_discard_result(p, count, mandatory, allowed)
	return outcome == HandDiscardOutcome.PAID

func _select_hand_discard_result(p: Player, count: int, mandatory: bool, allowed: Callable = Callable()) -> HandDiscardOutcome:
	if p == null or count <= 0:
		return HandDiscardOutcome.ACTION_INVALIDATED
	var revision = turn_manager.get_context_revision()
	while true:
		if _game_over:
			return HandDiscardOutcome.GAME_ENDED
		if not p.is_alive() or revision != turn_manager.get_context_revision():
			return HandDiscardOutcome.ACTION_INVALIDATED
		if allowed.is_valid() and not allowed.call():
			return HandDiscardOutcome.ACTION_INVALIDATED
		if p.hand_size() < count:
			return HandDiscardOutcome.INSUFFICIENT_CARDS
		var snapshot = HandSelection.new(p)
		var indices: Array[int] = []
		if _hand_discard_override.is_valid():
			indices.assign(await _hand_discard_override.call(snapshot, count, mandatory))
		elif p.seat_index != 0:
			indices = snapshot.defaults(count)
		else:
			var prompt = HandDiscardPrompt.new()
			$UI.add_child(prompt)
			prompt.setup(snapshot, count, mandatory)
			var answer = ChoicePromptAnswer.new()
			var reply = {"indices": []}
			var valid = func():
				return not _game_over and players.has(p) and p.is_alive() \
					and revision == turn_manager.get_context_revision() \
					and (not allowed.is_valid() or allowed.call())
			prompt.answered.connect(func(chosen):
				reply.indices = chosen.duplicate()
				answer.submit(1), CONNECT_ONE_SHOT)
			var result = await _wait_choice_prompt(prompt, answer, valid)
			if result == CHOICE_INVALID:
				return HandDiscardOutcome.GAME_ENDED if _game_over else HandDiscardOutcome.ACTION_INVALIDATED
			if result == -1:
				indices.assign(snapshot.defaults(count) if mandatory else [])
			else:
				indices.assign(reply.indices)
		_refresh_status_line()
		if _game_over:
			return HandDiscardOutcome.GAME_ENDED
		if not p.is_alive() or revision != turn_manager.get_context_revision():
			return HandDiscardOutcome.ACTION_INVALIDATED
		if allowed.is_valid() and not allowed.call():
			return HandDiscardOutcome.ACTION_INVALIDATED
		if p.hand_size() < count:
			return HandDiscardOutcome.INSUFFICIENT_CARDS
		if not mandatory and indices.is_empty():
			return HandDiscardOutcome.DECLINED
		var paid = snapshot.take(indices, count)
		if paid.size() == count:
			for card in paid:
				if card != null:
					deck.discard(card)
			return HandDiscardOutcome.PAID
		if not mandatory:
			return HandDiscardOutcome.STALE_SELECTION # 非空无效答复不是主动拒绝。
		# 强制答复无效/快照过期不是拒绝支付；动作仍有效时按当前牌区重选。
		# 让出一帧以释放旧UI并处理终局，避免失效回调导致同步忙循环。
		await get_tree().process_frame
	return HandDiscardOutcome.ACTION_INVALIDATED

# 按显式模式分派判胜；击杀者只影响身份局奖惩，不决定胜方。
# 经典身份当前只支持五人标准；乱斗支持 2～10 人。奸雄与预大习特殊提交点继续隔离。
func _check_win_condition(_victim: Player, _killer: Player):
	# 任一统一濒死/死亡前上下文尚未提交时，身份局与乱斗都不得提前终局。
	if _game_over or not _dying_contexts.is_empty():
		return
	var outcome: Dictionary = {}
	if game_mode == MODE_CLASSIC_IDENTITY and player_count == 5:
		outcome = IdentityVictory.evaluate(players)
	elif game_mode == MODE_FREE_FOR_ALL:
		outcome = FreeForAllVictory.evaluate(players)
	if not outcome.is_empty():
		_finish_game(outcome["winner"], outcome["reason"])

# 结束游戏：置 _game_over 标志 + 发信号（弹窗显示胜方，回合不再推进）
func _finish_game(winner_identity: String, reason: String):
	if _game_over:
		return
	_game_over = true
	_halt_countdown()
	if winner_identity == "平局":
		_update_debug("游戏结束！平局（%s）" % reason)
	else:
		_update_debug("游戏结束！【%s】获胜！（%s）" % [winner_identity, reason])
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
	title.text = "游戏结束！\n平局" if winner_identity == "平局" else "游戏结束！\n%s 获胜！" % winner_text
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
	_campus_execution_generation += 1
	_campus_execution_owner = -1
	_gay_execution_generation += 1
	_gay_execution_owner = -1
	_game_over = false
	_clear_pending_determined_card()
	_dead_processed.clear()
	_dying_contexts.clear()
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
	p.consume_wine_bonus()
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

# 合法性与持牌情况是所有人共用的规则；是否愿意救援是另一个决策层。
func _rescue_options(rescuer: Player, dying: Player) -> Array[int]:
	var options: Array[int] = []
	if _game_over or rescuer == null or dying == null or not players.has(rescuer) or not players.has(dying):
		return options
	if not dying.is_dying() or _is_kneeling(dying) or _is_kneeling(rescuer):
		return options
	if rescuer != dying and not rescuer.is_alive():
		return options
	if _dying_contexts.has(dying) and _dying_contexts[dying].stage != DyingContext.Stage.RESCUE:
		return options
	for sub in [CardData.CardSubType.PEACH, CardData.CardSubType.WINE]:
		if sub == CardData.CardSubType.WINE and rescuer != dying:
			continue
		if HandPayment.has_card(rescuer, sub):
			options.append(sub)
	return options

# 自救/救他人共用支付入口；确认时重验，不因过期选择丢牌或凭空治疗。
func _use_rescue_card(rescuer: Player, dying: Player, sub: int) -> bool:
	if not _rescue_options(rescuer, dying).has(sub):
		return false
	var card = HandPayment.take_card(rescuer, sub)
	if card == null:
		return false
	deck.discard(card)
	_record_card_action(rescuer, card)
	var healed = 1
	if sub == CardData.CardSubType.PEACH:
		healed = _heal_with_staff(rescuer, dying)
	else:
		dying.heal(1)
	_update_debug("%s 对 %s 使用【%s】，回复 %d 点体力（%d/%d）" % [rescuer.player_name, dying.player_name, CardData.get_type_name(sub), healed, dying.hp, dying.max_hp])
	_sync_all_ui()
	return true

# 兼容既有自救按钮/用例；不再有另一套支付逻辑。
func _use_dying_card(dying: Player, sub: CardData.CardSubType) -> bool:
	return _use_rescue_card(dying, dying, sub)

func _run_rescue_round(dying: Player):
	if turn_manager == null or turn_manager.current_player_idx < 0 or turn_manager.current_player_idx >= players.size():
		return
	var order: Array[Player] = []
	for offset in players.size():
		order.append(players[(turn_manager.current_player_idx + offset) % players.size()])
	for rescuer in order:
		while dying.is_dying() and not _game_over:
			var sub = await _ask_rescue_card(rescuer, dying)
			var hp_before = dying.hp
			if not _use_rescue_card(rescuer, dying, sub) or dying.hp <= hp_before:
				break # 本人可连续出牌；拒绝/无牌/过期选择则轮到下一人。
		if not dying.is_dying() or _game_over:
			break

func _ask_rescue_card(rescuer: Player, dying: Player) -> int:
	var options = _rescue_options(rescuer, dying)
	if options.is_empty():
		return -1
	var revision = turn_manager.get_context_revision()
	var snapshot = HandSelection.new(rescuer)
	var selected: int
	if rescuer == dying and rescuer == players[0] and _dying_peach_override.is_valid():
		selected = CardData.CardSubType.PEACH if _dying_peach_override.call() else -1
	elif _rescue_choice_override.is_valid():
		selected = await _rescue_choice_override.call(rescuer, dying, options)
	elif rescuer != players[0]:
		selected = await _choose_ai_response(rescuer, "rescue", options, {"target": dying.seat_index})
	else:
		selected = await _show_rescue_prompt(rescuer, dying, options)
	if _game_over or revision != turn_manager.get_context_revision() \
			or rescuer.hand != snapshot.hand or rescuer.determined_cards != snapshot.determined:
		return -1
	return selected if _rescue_options(rescuer, dying).has(selected) else -1

# 保守 AI 策略，不是规则限制：自救；救公开同阵营者；不读取他人隐藏身份。
func _choose_ai_rescue(rescuer: Player, dying: Player, options: Array[int]) -> int:
	var view = _ai_observation(rescuer)
	view["response"] = {"target": dying.seat_index}
	return ResponsePolicy.choose(view, "rescue", options)

func _show_dying_prompt(dying: Player):
	var sub = await _ask_rescue_card(dying, dying)
	_use_rescue_card(dying, dying, sub)

func _show_rescue_prompt(rescuer: Player, dying: Player, options: Array[int]) -> int:
	var answer = RescueAnswer.new()
	var overlay = ColorRect.new()
	overlay.name = "RescuePrompt"
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
	label.text = "%s 处于濒死状态（体力 %d），是否使用牌救援？" % [dying.player_name, dying.hp]
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

	for sub in options:
		var button = Button.new()
		button.text = "使用【%s】" % CardData.get_type_name(sub)
		button.custom_minimum_size = Vector2(160, 44)
		button.pressed.connect(answer.submit.bind(sub))
		hbox.add_child(button)

	# 放弃按钮（独立一行，居中）
	var skip_btn = Button.new()
	skip_btn.text = "放弃"
	skip_btn.custom_minimum_size = Vector2(160, 44)
	skip_btn.modulate = Color(0.6, 0.6, 0.6)
	skip_btn.pressed.connect(answer.submit.bind(-1))
	vbox.add_child(skip_btn)

	_start_response_countdown(overlay, rescuer.player_name, answer.submit.bind(-1))
	var chosen_sub: int = await answer.answered
	_stop_countdown()
	if not overlay.is_queued_for_deletion():
		overlay.queue_free()
	return chosen_sub

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
		_clear_pending_determined_card()
		turn_manager.advance_phase()

# ---- UI 回调 ----

func _on_play_btn_pressed():
	if turn_manager.current_phase != TurnManager.Phase.PLAY:
		return
	var p = players[turn_manager.get_play_actor_idx()]
	if p.hand_size() <= 0 and p.determined_cards.is_empty():
		_update_debug("没有手牌了")
		return

	var selector = _selector_scene.instantiate()
	selector.player = players[turn_manager.get_play_actor_idx()]
	$UI.add_child(selector)
	selector.confirmed.connect(_on_selector_confirmed)
	selector.cancelled.connect(_on_selector_cancelled)
	selector.determined_card_clicked.connect(_on_determined_card_clicked)

func _on_end_play_pressed():
	end_play_phase()

func _on_selector_confirmed(sub: CardData.CardSubType):
	_clear_pending_determined_card()
	_reveal_ask_pending = true
	await play_card(sub)
	# 【苕】任意玩家行动后询问是否明置
	await _maybe_ask_reveal()

func _on_selector_cancelled():
	_update_debug("取消出牌")

func _on_determined_card_clicked(card: CardBase):
	if turn_manager.current_phase != TurnManager.Phase.PLAY:
		return
	var p = players[turn_manager.get_play_actor_idx()]
	if p.seat_index != 0 or not p.determined_cards.has(card):
		_update_debug("所选的已确定牌已不在当前玩家牌区")
		return
	_pending_determined_card = card
	_reveal_ask_pending = true
	await play_card(card.sub_type)
	# 目标选择期间继续保留原对象；即时牌、非法牌和完成结算均在这里收口残留状态。
	if not _is_targeting and not _is_multi_targeting and not _is_iron_chain_targeting:
		_clear_pending_determined_card()
	await _maybe_ask_reveal()

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

		# 【没用】角色选择：点击头像选择/取消（选满 2 名进入区域选择）
		if _is_lanzhonghou_targeting:
			_on_lanzhonghou_target_click(player)
			return

		# 【烂忠厚】目标选择：点击头像选目标（单选）
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
	if not _is_targeting or _card_target_confirm_owner == _card_target_generation: return
	if turn_manager.get_play_actor_idx() < 0 or turn_manager.get_play_actor_idx() >= players.size(): return
	var attacker = players[turn_manager.get_play_actor_idx()]
	if not _can_use_play_skill(attacker) or not players.has(target): return

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

	if _targeting_card_sub in TARGET_TRICKS and not get_trick_targets(attacker, _targeting_card_sub).has(target):
		return
	# 目标有效 → 确认弹窗
	var generation = _card_target_generation
	var revision = turn_manager.get_context_revision()
	var selected_sub = _targeting_card_sub
	var pending_card = _pending_determined_card
	var valid = func():
		return _can_use_play_skill(attacker) and generation == _card_target_generation \
			and revision == turn_manager.get_context_revision() and _is_targeting \
			and _targeting_card_sub == selected_sub and _pending_determined_card == pending_card \
			and players.has(target) and target.is_alive() and not _is_kneeling(target) \
			and (not is_strike_target or _get_strike_targets(attacker).has(target)) \
			and (selected_sub not in TARGET_TRICKS or get_trick_targets(attacker, selected_sub).has(target))
	_card_target_confirm_owner = generation
	var confirmed = await _show_target_confirm(attacker.player_name, target.player_name, selected_sub, valid)
	if _card_target_confirm_owner == generation: _card_target_confirm_owner = -1
	if confirmed == CHOICE_INVALID or not valid.call():
		_clear_invalid_card_targeting(generation)
		return
	if confirmed == 0:
		_update_debug("取消对 %s 出牌" % target.player_name)
		return  # 继续目标选择模式

	# 确认 → 执行
	_is_targeting = false
	_cancel_target_btn.visible = false
	_reveal_ask_pending = true
	await execute_card_on_target(target, selected_sub)
	if generation != _card_target_generation: return
	_clear_pending_determined_card()
	_targeting_card_sub = -1
	# 【苕】任意玩家行动后询问是否明置
	await _maybe_ask_reveal()
	# 恢复出牌按钮
	_restore_play_skill_buttons()

# 只清理本次失效选择；取消后已重开的新选择不受旧协程影响。
func _clear_invalid_card_targeting(generation: int):
	if generation != _card_target_generation: return
	_card_target_generation += 1
	_is_targeting = false
	_is_iron_chain_targeting = false
	_targeting_card_sub = -1
	_iron_chain_targets.clear()
	_clear_pending_determined_card()
	_cancel_target_btn.visible = false
	_restore_play_skill_buttons()

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
	if skill_key == "没用":
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

	var my_turn = (turn_manager.get_play_actor_idx() == 0)
	if my_turn and turn_manager.current_phase == TurnManager.Phase.PLAY:
		_play_btn.disabled = ((players[0].hand_size() <= 0 and players[0].determined_cards.is_empty()) or _is_kneeling(players[0]))
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
	if _game_over:
		_halt_countdown()
		_set_status_line("游戏已结束")
		return
	var pid = turn_manager.get_play_actor_idx()
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
	if turn_manager.get_play_actor_idx() == 0 and turn_manager.current_phase == TurnManager.Phase.PLAY and _countdown_active:
		_start_play_countdown()

# 停止倒计时并恢复阶段提示（响应结束后回到当前阶段状态）
func _stop_countdown():
	_halt_countdown()
	_refresh_status_line()

func _halt_countdown():
	_countdown_generation += 1
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
