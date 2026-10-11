class_name ActionHistoryPanel
extends VBoxContainer

# Counter is painted without participating in text/container measurement.
# Updating unread counts must not force the entire game UI to relayout.
class Counter extends Control:
	var text := "":
		set(value):
			if text == value: return
			text = value
			queue_redraw()
	func _draw() -> void:
		var font = get_theme_default_font()
		var width = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_string(font, Vector2(size.x - width, 16), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("86c8ff"))

var history: ActionHistory
var toggle: Button
var badge: Counter
var text_view: RichTextLabel
var content: PanelContainer
var follow := true
var unseen := 0
var _last_sequence := 0
var _render_pending := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	toggle = Button.new()
	toggle.text = "行动日志"
	toggle.custom_minimum_size.y = 40
	add_child(toggle)
	badge = Counter.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	badge.offset_left = -100
	badge.offset_right = -12
	badge.offset_top = -10
	badge.offset_bottom = 10
	toggle.add_child(badge)
	content = PanelContainer.new()
	content.visible = false
	add_child(content)
	toggle.pressed.connect(func():
		content.visible = not content.visible
		if content.visible:
			unseen = 0
			_changed())

func _build_content() -> void:
	if text_view != null: return
	var style = StyleBoxFlat.new()
	style.bg_color = Color("18212b")
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	content.add_theme_stylebox_override("panel", style)
	var box = VBoxContainer.new()
	content.add_child(box)
	var tools = HBoxContainer.new()
	box.add_child(tools)
	var note = Label.new()
	note.text = "最近%d条 · 仅含可见事件" % ActionHistory.LIMIT
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tools.add_child(note)
	var copy = Button.new()
	copy.text = "复制日志"
	copy.pressed.connect(func(): DisplayServer.clipboard_set(history.visible_text()) if history != null else null)
	tools.add_child(copy)
	text_view = RichTextLabel.new()
	text_view.custom_minimum_size = Vector2(0, 240)
	text_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_view.bbcode_enabled = false # Names and text cannot inject links/markup.
	text_view.selection_enabled = true
	text_view.add_theme_font_size_override("normal_font_size", 18)
	box.add_child(text_view)
	text_view.get_v_scroll_bar().value_changed.connect(func(value):
		if not _render_pending:
			var bar = text_view.get_v_scroll_bar()
			follow = value >= bar.max_value - bar.page - 2)

func bind(source: ActionHistory) -> void:
	if history != null and history.changed.is_connected(_changed): history.changed.disconnect(_changed)
	history = source
	history.changed.connect(_changed)
	_last_sequence = 0
	_changed()

func _changed() -> void:
	if history.sequence < _last_sequence or history.sequence == 0:
		follow = true
		unseen = 0
	elif not content.visible or not follow:
		unseen += history.sequence - _last_sequence
	_last_sequence = history.sequence
	_refresh_title()
	if not content.visible: return
	_build_content()
	if _render_pending: return
	_render_pending = true
	_render.call_deferred()

func _refresh_title() -> void:
	# Keep the Chinese button label stable: reshaping it on every event also
	# invalidates container layout, even when the expensive history is closed.
	var value = "+%d" % unseen if unseen > 0 else ""
	if badge.text != value: badge.text = value

func _render() -> void:
	if history == null: return
	var bar = text_view.get_v_scroll_bar()
	var previous = bar.value
	var rendered_sequence = history.sequence
	var rendered_match = history.match_key
	text_view.text = history.visible_text()
	await get_tree().process_frame
	if not is_inside_tree(): return
	bar.value = bar.max_value if follow else previous
	_render_pending = false
	if history.sequence != rendered_sequence or history.match_key != rendered_match: _changed()

func _exit_tree() -> void:
	if history != null and history.changed.is_connected(_changed): history.changed.disconnect(_changed)
