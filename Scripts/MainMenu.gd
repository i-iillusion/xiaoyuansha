# ============================================================
# MainMenu.gd — 开始界面 / 主菜单
# 流程：主菜单 → 开始游戏（单人/多人/设置/测试模式）→ 测试模式（选模式）
# 当前开放 2/3 人无身份乱斗与 5 人标准身份局测试入口。
# ============================================================
class_name MainMenu
extends Control

const GAME_SCENE = preload("res://Scenes/Game.tscn")

# 测试模式选将：true = 随机武将；false = 自选武将（身份仍由所选玩法决定）
static var random_mode: bool = true

var _tip_remaining: float = 0.0
# 待进入的对局人数与模式
var _pending_players: int = 5
var _pending_mode: String = GameManager.MODE_CLASSIC_IDENTITY

@onready var _page_title: Label = $Center/Box/PageTitle
@onready var _page: VBoxContainer = $Center/Box/Page
@onready var _tip: Label = $Tip

func _ready():
	_show_main()

func _process(delta: float):
	if _tip_remaining > 0.0:
		_tip_remaining -= delta
		if _tip_remaining <= 0.0:
			_tip.visible = false

# ---- 页面渲染 ----

func _clear():
	for c in _page.get_children():
		c.queue_free()

func _add_btn(text: String, cb: Callable, hint: String = "") -> Button:
	var btn = Button.new()
	btn.text = text + (("（%s）" % hint) if hint != "" else "")
	btn.custom_minimum_size = Vector2(300, 48)
	btn.add_theme_font_size_override("font_size", 18)
	btn.pressed.connect(cb)
	_page.add_child(btn)
	return btn

func _show_main():
	_clear()
	_page_title.text = ""
	_add_btn("开始游戏", _show_start)
	_add_btn("退出游戏", _quit)

func _show_start():
	_clear()
	_page_title.text = "选择模式"
	_add_btn("单人游戏", func(): _not_implemented("单人游戏"))
	_add_btn("多人游戏", func(): _not_implemented("多人游戏"))
	_add_btn("设置", func(): _not_implemented("设置"))
	_add_btn("测试模式", _show_test)
	_add_btn("← 返回", _show_main, "")

func _show_test():
	_clear()
	_page_title.text = "测试模式 · 选择人数"
	# 选将切换；身份始终由经典身份/无身份乱斗玩法决定。
	if random_mode:
		_add_btn("选将：随机武将（身份按玩法配置）", _toggle_mode)
	else:
		_add_btn("选将：自选武将（身份按玩法配置）", _toggle_mode)
	_add_btn("2人乱斗", func(): _start_test_game(2, GameManager.MODE_FREE_FOR_ALL))
	_add_btn("3人乱斗", func(): _start_test_game(3, GameManager.MODE_FREE_FOR_ALL))
	_add_btn("2V2", func(): _not_implemented("2V2"))
	_add_btn("5人标准", func(): _start_test_game(5, GameManager.MODE_CLASSIC_IDENTITY))
	_add_btn("6人奸雄", func(): _not_implemented("6人奸雄"))
	_add_btn("7人标准", func(): _not_implemented("7人标准"))
	_add_btn("8人奸雄", func(): _not_implemented("8人奸雄"))
	_add_btn("← 返回", _show_start, "")

# 切换随机武将 / 自选武将（重新渲染测试模式页）
func _toggle_mode():
	random_mode = not random_mode
	_show_test()

# 测试模式开始对局：随机模式直接进游戏；自选武将先进入武将选择页
func _start_test_game(players: int, mode: String):
	_pending_players = players
	_pending_mode = mode
	GameManager.selected_players = players
	GameManager.selected_mode = mode
	if random_mode:
		GameManager.random_identity = mode == GameManager.MODE_CLASSIC_IDENTITY
		GameManager.random_general = true
		_start_game_5p()
	else:
		GameManager.random_identity = false
		GameManager.random_general = false
		_show_general_select()

# 武将选择页（自选武将模式）：已实现武将全部可选
func _show_general_select():
	_clear()
	_page_title.text = "选择你的武将"
	_add_general_btn("稻草人")
	_add_general_btn("凯文·罗本")
	_add_general_btn("布鲁斯·萨维奇")
	_add_general_btn("安普提·斯丢皮得")
	_add_general_btn("史蒂芬·彼特先斯")
	_add_general_btn("杰基·斯特朗")
	_add_general_btn("麦克斯·欧尼斯特")
	_add_general_btn("比尔·盖伊")
	_add_btn("← 返回", _show_test, "")

func _add_general_btn(general_name: String):
	var data = GeneralData.GENERALS[general_name]
	var skills_text = "无技能"
	if not data["skills"].is_empty():
		skills_text = "\n".join(data["skills"])
	var btn = Button.new()
	btn.text = "%s %s — 体力 %d\n%s" % [data["avatar"], general_name, data["max_hp"], skills_text]
	btn.custom_minimum_size = Vector2(420, 96)
	btn.add_theme_font_size_override("font_size", 16)
	btn.pressed.connect(_select_general.bind(general_name))
	_page.add_child(btn)

func _select_general(general_name: String):
	GameManager.selected_general = general_name
	GameManager.selected_players = _pending_players
	GameManager.selected_mode = _pending_mode
	GameManager.random_identity = false  # 自选时经典身份固定；乱斗仍无身份。
	GameManager.random_general = false
	_show_tip("已选择 %s，进入对局…" % general_name)
	_start_game_5p()

# ---- 动作 ----

func _start_game_5p():
	# 5人标准：进入现有游戏场景（玩家0 = 你，其余 AI）
	get_tree().change_scene_to_packed(GAME_SCENE)

func _not_implemented(name: String):
	_show_tip("「%s」尚未实现" % name)

func _show_tip(msg: String):
	_tip.text = msg
	_tip.visible = true
	_tip_remaining = 2.5

func _quit():
	get_tree().quit()
