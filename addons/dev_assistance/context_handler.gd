@icon("res://addons/dev_assistance/icons/experiment.svg")
class_name DevAssistance
extends Node
## Add this node to an experiment and register its live targets in _ready().
## No game-specific paths or classes belong in this runtime component.

signal visibility_changed(open: bool)

## Shortcut for opening/closing tools. Ctrl+Alt+D avoids the editor's F9 pause shortcut.
## Edit its key/modifiers in the Inspector; the header follows changes at runtime.
@export var toggle_shortcut: Shortcut = _default_shortcut()
## Whether the tools start open. Changes during execution use set_tools_visible().
@export var start_open := true

## Arraste: resposta por segundo. Maior acompanha o cursor mais rápido; 0 remove a suavização.
@export_range(0.0, 40.0, 0.5) var drag_response := 18.0
## Desfoque do fundo em níveis de mipmap (0–5). Zero mantém o fundo nítido.
@export_range(0.0, 5.0, 0.1) var background_blur := 2.5
## Opacidade dos painéis (0–1). Maior melhora o contraste e oculta mais a cena.
@export_range(0.3, 1.0, 0.01) var panel_opacity := 0.96

const PRESET_PATH := "user://devassistance/presets.cfg"
# Dear ImGui flags, kept local so this script also parses without the extension in release.
const PANEL_FLAGS := 1 | 2 | 4 | 8 | 256 # NoTitleBar, NoResize, NoMove, NoScrollbar, NoSavedSettings.
const FigmaSkin := preload("res://addons/dev_assistance/figma_skin.gd")
const WATCH_FLAGS := 1 | 64 | 256 | 512 # NoTitleBar, AutoResize, NoSavedSettings, NoMouseInputs.

var contexts: Dictionary = {}
var _utilities: Dictionary = {}
var _query := [""]
var _wheel_page := 0
var tools_visible := false
var suspended := false
var gui: Object
var _old_mouse := Input.MOUSE_MODE_VISIBLE
var _presets := ConfigFile.new()
var _message := ""
var _layout_reset := true
var _frame_times: Array = []
var _sample_time := 0.0
var preset_path := PRESET_PATH
var _glass: CanvasLayer
var _glass_material: ShaderMaterial
var _glass_rects: Array[Vector4] = []
var _drag_id := ""
var _drag_offset := Vector2.ZERO
var _delta := 0.0
var _opening := true
var _watch_size := Vector2.ZERO
var _skin: FigmaSkin
var _header := {"position": Vector2(24, 16), "destination": Vector2(24, 16)}
var _header_height := 116.0


static func _default_shortcut() -> Shortcut:
	var key := InputEventKey.new()
	key.keycode = KEY_D
	key.ctrl_pressed = true
	key.alt_pressed = true
	var shortcut := Shortcut.new()
	shortcut.events = [key]
	return shortcut


func _ready() -> void:
	if not OS.is_debug_build():
		set_process(false)
		set_process_input(false)
		return
	if not Engine.has_singleton("ImGuiAPI"):
		push_warning("DevAssistance requires imgui-godot; tools are disabled.")
		set_process(false)
		set_process_input(false)
		return
	gui = Engine.get_singleton("ImGuiAPI")
	_skin = FigmaSkin.new(gui)
	_skin.configure()
	for tool in [["scene_browser", "Scene Browser"], ["screen_space", "ScreenSpace"], ["profiler", "Profiler"]]:
		_utilities[tool[0]] = {"title": tool[1], "icon": load(FigmaSkin.ICON_PATH + tool[0] + ".svg"),
			"position": Vector2.ZERO, "destination": Vector2.ZERO, "fade": 0.0, "open": [false], "collapsed": false}
	_glass = CanvasLayer.new()
	_glass.layer = 127 # Immediately below the configured ImGui layer (128).
	add_child(_glass)
	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_glass.add_child(copy)
	var glass := ColorRect.new()
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glass_material = ShaderMaterial.new()
	_glass_material.shader = preload("res://addons/dev_assistance/glass.gdshader")
	glass.material = _glass_material
	_glass.add_child(glass)
	_presets.load(preset_path)
	set_tools_visible(start_open)


## Controls: {property, label, description, min, max}; supported properties: bool/int/float.
## Actions: {label, description, callback}. IDs must be stable for saved parameter presets.
func register_context(id: String, title: String, icon: Texture2D, target: Node,
		controls: Array, actions: Array = []) -> void:
	if not OS.is_debug_build():
		return
	assert(not id.is_empty() and is_instance_valid(target))
	var fields: Array = []
	for control: Dictionary in controls:
		var field := control.duplicate()
		var key := StringName(field.property)
		var value: Variant = target.get(key)
		assert(typeof(value) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT], "Unsupported property: " + key)
		field["initial"] = value
		field["type"] = typeof(value)
		field["pinned"] = false
		field["shown"] = true
		field["fired_at"] = -1
		if field.has("anchor"):
			field.anchor = weakref(field.anchor)
		fields.append(field)
	contexts[id] = {"title": title, "icon": icon, "target": weakref(target),
		"fields": fields, "actions": actions, "position": Vector2.ZERO, "destination": Vector2.ZERO, "fade": 0.0, "open": [false], "preset_name": ["Meu preset"], "preset": "Padrão", "tab": "", "collapsed": false}
	# One connection per target, even when several contexts share that target.
	var cleanup := _target_exiting.bind(target.get_instance_id())
	if not target.tree_exiting.is_connected(cleanup):
		target.tree_exiting.connect(cleanup, CONNECT_ONE_SHOT)


func _target_exiting(instance_id: int) -> void:
	for id: String in contexts.keys():
		var target: Node = contexts[id].target.get_ref()
		if target == null or target.get_instance_id() == instance_id:
			contexts.erase(id)


func set_tools_visible(value: bool) -> void:
	if not OS.is_debug_build() or gui == null:
		return
	if tools_visible == value:
		return
	tools_visible = value
	if value:
		_opening = true
		_old_mouse = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = _old_mouse
	if _glass != null:
		_glass.visible = false
	visibility_changed.emit(value)


func _exit_tree() -> void:
	if tools_visible:
		Input.mouse_mode = _old_mouse


func _input(event: InputEvent) -> void:
	if gui == null or suspended:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and toggle_shortcut != null and toggle_shortcut.matches_event(event):
		set_tools_visible(not tools_visible)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _glass != null:
		_glass.visible = not suspended
	if gui == null or suspended:
		return
	_delta = delta
	_skin.refresh_fonts()
	_glass_rects.clear()
	if not gui.IsMouseDown(0):
		_drag_id = ""
	_sample_time += delta
	if _sample_time >= 0.1:
		_frame_times.append(delta * 1000.0)
		if _frame_times.size() > 120:
			_frame_times.pop_front()
		_sample_time = 0.0
	if tools_visible:
		_draw_header()
		var index := 0
		for id: String in contexts.keys():
			var context: Dictionary = contexts[id]
			if not is_instance_valid(context.target.get_ref()):
				contexts.erase(id)
				continue
			if not context.open[0] or _opening:
				context.fade = 0.0
			if context.open[0]:
				_draw_context(id, context, index)
			index += 1
		for tool: String in _utilities:
			if _utilities[tool].open[0]:
				_draw_context(tool, _utilities[tool], index)
			index += 1
		_layout_reset = false
		_opening = false
	_draw_watches()
	_glass.visible = not _glass_rects.is_empty()
	_glass_material.set_shader_parameter("panel_count", _glass_rects.size())
	var padded := _glass_rects.duplicate()
	padded.resize(16)
	_glass_material.set_shader_parameter("panels", PackedVector4Array(padded))
	_glass_material.set_shader_parameter("blur_lod", background_blur)


func _draw_header() -> void:
	_header_height = 68.0 + ceilf(maxi(1, contexts.size() + _utilities.size()) / 4.0) * 48.0
	var size := Vector2(356, _header_height)
	if _layout_reset:
		_header.position = Vector2(24, 16)
		_header.destination = _header.position
	_move_panel("##header", _header, size)
	_skin.shadow(_header.position, size, 1.0)
	gui.SetNextWindowPos(_header.position)
	gui.SetNextWindowSize(size)
	gui.SetNextWindowBgAlpha(panel_opacity)
	gui.Begin("DevAssistance##header", [], PANEL_FLAGS)
	_skin.hit("drag_header", Vector2(8, 5), Vector2(195, 34), "Arraste para mover. Duplo clique reorganiza os painéis.")
	_start_drag("##header", _header)
	if gui.IsItemHovered() and gui.IsMouseDoubleClicked(0):
		_layout_reset = true
		_drag_id = ""
		_header.position = Vector2(24, 16)
		_header.destination = _header.position
		for context: Dictionary in contexts.values() + _utilities.values():
			context.position = Vector2.ZERO
	_skin.icon(Vector2(11, 11), _skin.icons.drag)
	_skin.text(Vector2(37, 12), "DevAsis", 16, FigmaSkin.TEXT, 1)
	_skin.box(Vector2(212, 12), Vector2(101, 22), FigmaSkin.SURFACE)
	var shortcut := toggle_shortcut.get_as_text() if toggle_shortcut != null else "Sem atalho"
	_skin.text(Vector2(221, 17), shortcut, 10, FigmaSkin.MUTED, 2)
	if _skin.icon_button("hide", Vector2(324, 15), "hide", "Ocultar ferramentas · " + shortcut):
		set_tools_visible(false)
	_skin.box(Vector2(13, 45), Vector2(328, 1), FigmaSkin.BORDER, 0)
	var index := 0
	for collection: Dictionary in [contexts, _utilities]:
		for id: String in collection:
			var context: Dictionary = collection[id]
			var at := Vector2(13 + index % 4 * 84, 57 + index / 4 * 48)
			if _skin.hit("menu_" + id, at, Vector2(76, 42), "Abrir / recolher " + context.title):
				context.open[0] = not context.open[0]
			_skin.box(at, Vector2(76, 42), FigmaSkin.ACTIVE if context.open[0] else (FigmaSkin.SURFACE.lightened(0.08) if gui.IsItemHovered() else Color("202532")), 8, Color("8c77b6") if context.open[0] else Color.TRANSPARENT)
			if context.icon != null:
				_skin.icon(at + (Vector2(76, 42) - context.icon.get_size()) * 0.5, context.icon)
			else:
				_skin.text(at + Vector2(23, 13), context.title.left(3), 12)
			if context.open[0]:
				_skin.box(at + Vector2(34, 36), Vector2(8, 2), FigmaSkin.ACCENT, 1)
			index += 1
	_glass_panel()
	gui.End()


func _start_drag(id: String, state: Dictionary) -> void:
	if gui.IsItemActivated():
		_drag_id = id
		_drag_offset = gui.GetMousePos() - state.position


func _move_panel(id: String, state: Dictionary, size: Vector2) -> void:
	if _drag_id == id:
		state.destination = gui.GetMousePos() - _drag_offset
	var limit: Vector2 = (gui.GetIO().DisplaySize - size).max(Vector2.ZERO)
	state.destination = state.destination.clamp(Vector2.ZERO, limit)
	state.position = state.position.lerp(state.destination, 1.0 if drag_response <= 0.0 else 1.0 - exp(-drag_response * _delta)).clamp(Vector2.ZERO, limit)


func _glass_panel() -> void:
	if _glass_rects.size() >= 16:
		return
	var display: Vector2 = gui.GetIO().DisplaySize
	var pos: Vector2 = gui.GetWindowPos() / display
	var extent: Vector2 = gui.GetWindowSize() / display
	_glass_rects.append(Vector4(pos.x, pos.y, extent.x, extent.y))


func _draw_context(id: String, context: Dictionary, index: int) -> void:
	var viewport_size: Vector2 = gui.GetIO().DisplaySize
	var desired := Vector2(356, minf(376, viewport_size.y - 32))
	if context.collapsed:
		desired.y = 66
	var resized: bool = context.get("display", viewport_size) != viewport_size
	context["display"] = viewport_size
	if _layout_reset or context.position == Vector2.ZERO or (resized and viewport_size.y < 544):
		var initial := Vector2(24 + index * 376, _header_height + 36)
		if viewport_size.y < initial.y + desired.y + 16:
			initial = Vector2(viewport_size.x - desired.x - 16, 16)
		context.position = initial.clamp(Vector2(16, 16), (viewport_size - desired).max(Vector2(16, 16)))
		context.destination = context.position
	context.fade = minf(1.0, context.fade + _delta * 8.0)
	_move_panel(id, context, desired)
	_skin.shadow(context.position, desired, context.fade)
	gui.SetNextWindowPos(context.position)
	gui.SetNextWindowSize(desired)
	gui.SetNextWindowBgAlpha(panel_opacity * context.fade)
	if context.get("focus_next", false):
		gui.SetNextWindowFocus()
		context.focus_next = false
	gui.Begin(context.title + ("###props_" if context.has("target") else "###tool_") + id, [], PANEL_FLAGS)
	_glass_panel()
	var target: Node = context.target.get_ref() if context.has("target") else null
	_skin.hit("drag", Vector2(8, 4), Vector2(270, 55), "Arraste para mover " + context.title)
	_start_drag(id, context)
	_skin.icon(Vector2(17, 18), context.get("heading_icon", context.icon))
	_skin.text(Vector2(46, 17), context.title, 17, FigmaSkin.TEXT, 1)
	_skin.text(Vector2(46, 41), str(target.name) if target else "DevAsis", 11, FigmaSkin.MUTED, 2)
	if target and _skin.icon_button("watch", Vector2(290, 19), "pin", "Fixar / remover todos os parâmetros nas observações", _all_pinned(context)):
		var pin := not _all_pinned(context)
		for field: Dictionary in context.fields:
			field.pinned = pin
			field.shown = true
	if _skin.icon_button("collapse", Vector2(323, 19), "collapse", "Expandir" if context.collapsed else "Recolher"):
		context.collapsed = not context.collapsed
	if not context.collapsed:
		_skin.box(Vector2(15, 66), Vector2(324, 1), FigmaSkin.BORDER, 0)
		if target == null:
			gui.SetCursorPos(Vector2(16, 80))
			gui.BeginChild("utility", desired - Vector2(32, 96))
			match id:
				"scene_browser": _draw_browser()
				"screen_space": _draw_wheel()
				"profiler":
					gui.Text("FPS: %d" % Engine.get_frames_per_second())
					gui.Text("Frame: %.2f ms" % (_delta * 1000.0))
					gui.Text("Memória estática: %.1f MiB" % (OS.get_static_memory_usage() / 1048576.0))
					if not _frame_times.is_empty():
						gui.PlotLinesEx("##ms", _frame_times, _frame_times.size(), 0, "Frame time (ms)", 0, maxf(33.3, _frame_times.max()), Vector2(300, 64))
			gui.EndChild()
			gui.End()
			return
		var groups: Array[String] = []
		groups.assign(context.get("groups", []))
		if groups.is_empty():
			for field: Dictionary in context.fields:
				if field.type != TYPE_BOOL and not field.has("group"):
					groups.append("Ajustes")
					break
		for field: Dictionary in context.fields:
			var group: String = field.get("group", "Sistemas" if field.type == TYPE_BOOL else "Ajustes")
			if not groups.has(group):
				groups.append(group)
		if groups.is_empty():
			groups.append("Ajustes")
		groups.append("Ações")
		if context.tab.is_empty():
			context.tab = groups[0]
		# Scrollable tabs preserve access when a generic context registers many groups.
		gui.SetCursorPos(Vector2(17, 76))
		gui.BeginChild("tabs", Vector2(322, 32), 0, 2048)
		var tab_x := 0.0
		for tab: String in groups:
			var width: float = maxf(79.0, gui.CalcTextSize(tab).x + 10.0)
			if _skin.hit("tab_" + tab, Vector2(tab_x, 0), Vector2(width, 28)):
				context.tab = tab
			_skin.text(Vector2(tab_x, 4), tab, 12, FigmaSkin.ACCENT if context.tab == tab else FigmaSkin.MUTED, 1 if context.tab == tab else 0)
			if context.tab == tab:
				_skin.box(Vector2(tab_x, 27), Vector2(width, 2), FigmaSkin.ACCENT, 0)
			tab_x += width + 25
		gui.EndChild()
		gui.SetCursorPos(Vector2(17, 117))
		gui.BeginChild("content", Vector2(332, desired.y - 176))
		if context.tab == "Ações":
			_draw_actions(id, context)

		else:
			var row := 0
			for field: Dictionary in context.fields:
				if field.get("group", "Sistemas" if field.type == TYPE_BOOL else "Ajustes") == context.tab:
					_draw_field(id, target, field, row * 67.0)
					row += 1
			gui.SetCursorPos(Vector2(0, row * 67.0))
			gui.Dummy(Vector2(1, 1))
		gui.EndChild()
		_draw_footer(id, context, desired.y)
	gui.End()


func _all_pinned(context: Dictionary) -> bool:
	if context.fields.is_empty():
		return false
	for field: Dictionary in context.fields:
		if not field.pinned:
			return false
	return true


func _draw_field(id: String, target: Node, field: Dictionary, y: float) -> void:
	gui.PushID(id + ":" + field.property)
	var value := [target.get(field.property)]
	if field.type == TYPE_BOOL:
		_skin.text(Vector2(0, y + 12), field.label)
		var caption: String = field.get("caption", field.description)
		# Full descriptions remain available on hover; keep each row a predictable height.
		if caption.length() > 43:
			caption = caption.left(40) + "…"
		_skin.text(Vector2(0, y + 34), caption, 11, FigmaSkin.MUTED)
		if _skin.hit("toggle", Vector2(281, y + 10), Vector2(44, 29), field.description):
			set_parameter(id, field.property, not value[0])
		_skin.box(Vector2(286, y + 15), Vector2(34, 19), FigmaSkin.ACCENT if value[0] else Color("3a4255"), 10)
		_skin.circle(Vector2(308 if value[0] else 295, y + 24.5), 6.5, Color("151923") if value[0] else Color("bec6d6"))
	else:
		_skin.text(Vector2(0, y + 5), field.label)
		gui.SetCursorPos(Vector2(195, y))
		gui.SetNextItemWidth(103)
		if _skin.fonts.size() >= 3:
			gui.PushFont(_skin.fonts[2])
		var fmt := "%.0f" if field.type == TYPE_INT else "%.2f"
		if field.has("unit"):
			fmt += " " + field.unit.replace("%", "%%")
		if gui.InputDoubleEx("##number", value, 0, 0, fmt):
			set_parameter(id, field.property, value[0])
		_tip(field.description)
		if _skin.fonts.size() >= 3:
			gui.PopFont()
		if _skin.icon_button("reset", Vector2(308, y + 6), "reset", "Restaurar valor inicial"):
			set_parameter(id, field.property, field.initial)
		_skin.hit("slider", Vector2(0, y + 29), Vector2(298, 22), field.description + "\nClique no número para digitar.")
		var fraction := inverse_lerp(float(field.min), float(field.max), float(target.get(field.property))) if field.max != field.min else 0.0
		if gui.IsItemActive() and gui.IsMouseDown(0):
			fraction = clampf((gui.GetMousePos().x - gui.GetWindowPos().x) / 298.0, 0, 1)
			set_parameter(id, field.property, lerpf(field.min, field.max, fraction))
		elif gui.IsItemFocused():
			var direction := int(Input.is_physical_key_pressed(KEY_RIGHT)) - int(Input.is_physical_key_pressed(KEY_LEFT))
			if direction != 0:
				set_parameter(id, field.property, float(value[0]) + direction * maxf(1.0 if field.type == TYPE_INT else 0.01, (field.max - field.min) * _delta * 0.25))
		_skin.box(Vector2(0, y + 39), Vector2(298, 3), Color("3a4255"), 2)
		_skin.box(Vector2(0, y + 39), Vector2(298 * fraction, 3), FigmaSkin.ACCENT, 2)
		_skin.circle(Vector2(298 * fraction, y + 40.5), 6.5, FigmaSkin.ACCENT)
	# Per-field tools live on the label, leaving the Figma slider and switch uncluttered.
	if _skin.hit("label", Vector2(0, y), Vector2(188, 28), field.description + "\nClique para fixar/remover das observações. Botão direito para opções."):
		field.pinned = not field.pinned
		field.shown = true
	if gui.IsItemHovered() and gui.IsMouseClicked(1):
		gui.OpenPopup("field_options")
	if _skin.begin_popup("field_options"):
		if gui.Selectable("Remover do ScreenSpace" if field.pinned else "Marcar para ScreenSpace"):
			field.pinned = not field.pinned
			field.shown = true
		if gui.Selectable("Restaurar valor inicial"):
			set_parameter(id, field.property, field.initial)
		if field.pinned and gui.Selectable("Ocultar observação" if field.shown else "Mostrar observação"):
			field.shown = not field.shown
		gui.EndPopup()
	if field.pinned:
		_skin.circle(Vector2(184, y + 12), 2, FigmaSkin.ACCENT)
	gui.PopID()


func _draw_footer(id: String, context: Dictionary, height: float) -> void:
	var y := height - 45.0
	_skin.box(Vector2(15, height - 59), Vector2(324, 1), FigmaSkin.BORDER, 0)
	if _skin.button("presets", Vector2(17, y), Vector2(195, 29), "Preset: " + String(context.preset).left(21)):
		gui.OpenPopup("preset_list")
	_skin.icon(Vector2(183, y + 6), _skin.icons.chevron)
	if _skin.begin_popup("preset_list"):
		if gui.Selectable("Padrão"):
			reset_parameters(id)
			context.preset = "Padrão"
		for preset: String in _presets.get_section_keys(id) if _presets.has_section(id) else []:
			if gui.Selectable(preset):
				load_preset(id, preset)
				context.preset = preset
		gui.EndPopup()
	if _skin.button("save", Vector2(224, y), Vector2(113, 29), "Salvar preset", true):
		gui.OpenPopup("save_preset")
	if _skin.begin_popup("save_preset"):
		gui.Text("Nome do preset")
		gui.SetNextItemWidth(240)
		if gui.IsWindowAppearing():
			gui.SetKeyboardFocusHere()
		gui.InputText("##name", context.preset_name, 64)
		if gui.Button("Salvar / substituir"):
			if save_preset(id, context.preset_name[0]) == OK:
				context.preset = context.preset_name[0].strip_edges()
				gui.CloseCurrentPopup()
		if not _message.is_empty():
			gui.TextWrapped(_message)
		gui.EndPopup()


func _tip(description: String) -> void:
	if gui.IsItemHovered():
		_skin.tooltip(description)


func _draw_actions(id: String, context: Dictionary) -> void:
	for action: Dictionary in context.actions:
		if gui.Button(action.label):
			action.callback.call_deferred()
		_tip(action.description)
	gui.SeparatorText("Parâmetros")
	if gui.Button("Restaurar parâmetros iniciais"):
		reset_parameters(id)
	gui.TextWrapped("Presets de parâmetros estão no rodapé. Não salvam o estado completo da simulação.")


func _draw_browser() -> void:
	gui.SetNextItemWidth(300)
	gui.InputTextWithHint("##Buscar", "Buscar objeto ou contexto…", _query, 128)
	_tip("Buscar por objeto, contexto ou caminho")
	var count := 0
	for id: String in contexts:
		var ctx: Dictionary = contexts[id]
		var target: Node = ctx.target.get_ref()
		if not is_instance_valid(target) or not target.is_inside_tree():
			continue
		var path := str(target.get_path())
		var label := "%s · %s" % [target.name, ctx.title]
		if not (label + path + id).containsn(str(_query[0]).strip_edges()):
			continue
		count += 1
		if gui.Selectable(label + "###result_" + id):
			ctx.open[0] = true
			ctx.collapsed = false
			ctx.focus_next = true
			_utilities.scene_browser.open[0] = false
		_tip(path)
	if count == 0:
		gui.TextWrapped("Nenhum alvo registrado corresponde à busca.")


func _draw_wheel() -> void:
	var items: Array = []
	for ctx: Dictionary in contexts.values():
		for field: Dictionary in ctx.fields:
			if field.pinned:
				items.append([ctx.title, field])
	if items.is_empty():
		gui.TextWrapped("Clique no nome de um parâmetro para adicioná-lo ao ScreenSpace.")
		return
	var pages := ceili(items.size() / 6.0)
	_wheel_page = clampi(_wheel_page, 0, pages - 1)
	var first := 6 * _wheel_page
	var count := mini(6, items.size() - first)
	var selected := ""
	for offset in count:
		var field: Dictionary = items[first + offset][1]
		var at := Vector2(154, 97) + Vector2.UP.rotated(TAU * offset / count) * Vector2(112, 69)
		var label := "%s / %s" % [items[first + offset][0], field.label]
		if _skin.hit("watch_%d" % offset, at - Vector2(48, 15), Vector2(96, 30), label):
			field.shown = not field.shown
		if gui.IsItemHovered() or gui.IsItemFocused():
			selected = label
		_skin.box(at - Vector2(48, 15), Vector2(96, 30), FigmaSkin.ACTIVE if field.shown else FigmaSkin.SURFACE, 12)
		var caption := str(field.label)
		if caption.length() > 12:
			caption = caption.left(11) + "…"
		_skin.text(at - Vector2(42, 7), caption, 11, FigmaSkin.ACCENT if field.shown else FigmaSkin.MUTED)
	gui.SetCursorPos(Vector2(0, 198))
	gui.TextWrapped(selected if selected else "Selecione um valor para mostrar ou ocultar.")
	if pages > 1 and gui.Button("Página %d/%d  >" % [_wheel_page + 1, pages]):
		_wheel_page = (_wheel_page + 1) % pages


## Call from a game signal to show a registered FireSignal watch for its fade duration.
func fire_watch(id: String, property: String) -> void:
	if contexts.has(id):
		for field: Dictionary in contexts[id].fields:
			if field.property == property:
				field.fired_at = Time.get_ticks_msec()


func _draw_watches() -> void:
	var lines: Array[String] = []
	var alphas: Array[float] = []
	var anchor_rows := {}
	for context: Dictionary in contexts.values():
		var target: Node = context.target.get_ref()
		if not is_instance_valid(target):
			continue
		for field: Dictionary in context.fields:
			if not field.pinned or not field.shown:
				continue
			var line := "%s / %s: %s" % [context.title, field.label, target.get(field.property)]
			var opacity := 1.0
			if field.has("fade_seconds"):
				opacity = 1.0 - (Time.get_ticks_msec() - int(field.fired_at)) / (1000.0 * maxf(0.01, field.fade_seconds))
				if field.fired_at < 0 or opacity <= 0:
					continue
			if field.has("anchor"):
				var anchor: Node3D = field.anchor.get_ref()
				if not is_instance_valid(anchor) or not anchor.is_inside_tree() or anchor.get_viewport() != get_viewport():
					continue
				var cam := get_viewport().get_camera_3d()
				if not cam or not cam.is_position_in_frustum(anchor.global_position):
					continue
				var pos := cam.unproject_position(anchor.global_position) / get_viewport().get_visible_rect().size * Vector2(gui.GetIO().DisplaySize)
				pos.y += anchor_rows.get(anchor, 0) * gui.GetTextLineHeightWithSpacing()
				anchor_rows[anchor] = anchor_rows.get(anchor, 0) + 1
				gui.SetNextWindowPos(pos)
				gui.SetNextWindowBgAlpha(panel_opacity * opacity)
				gui.Begin("###anchor_%d_%s_%s" % [target.get_instance_id(), context.title, field.property], [], WATCH_FLAGS)
				gui.TextColored(Color(1, 1, 1, opacity), line)
				gui.End()
			else:
				lines.append(line)
				alphas.append(opacity)
	if lines.is_empty():
		return
	var window_size: Vector2 = gui.GetIO().DisplaySize
	var text_width := 0.0
	for line: String in lines:
		text_width = maxf(text_width, gui.CalcTextSize(line).x)
	var estimated := Vector2(text_width + 36, lines.size() * gui.GetTextLineHeightWithSpacing() + 32)
	var extent := _watch_size if _watch_size != Vector2.ZERO else estimated
	gui.SetNextWindowPos((window_size - extent - Vector2(12, 12)).max(Vector2.ZERO))
	gui.SetNextWindowBgAlpha(panel_opacity)
	gui.Begin("Observações##devassistance", [], WATCH_FLAGS)
	for i in lines.size():
		gui.TextColored(Color(1, 1, 1, alphas[i]), lines[i])
	# Use measured padding on the next frame, before ImGui emits the window's vertices.
	_watch_size = gui.GetWindowSize()
	_glass_panel()
	gui.End()


## Applies the same bounds for widgets, tests and persisted presets.
func set_parameter(id: String, property: String, value: Variant) -> bool:
	if not contexts.has(id):
		return false
	var context: Dictionary = contexts[id]
	var target: Node = context.target.get_ref()
	if not is_instance_valid(target):
		return false
	for field: Dictionary in context.fields:
		if field.property != property:
			continue
		if field.type == TYPE_BOOL:
			if typeof(value) != TYPE_BOOL:
				return false
		else:
			if not typeof(value) in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
				return false
			value = clampf(float(value), field.min, field.max)
			if field.type == TYPE_INT:
				value = int(round(value))
		target.set(property, value)
		return true
	return false


func reset_parameters(id: String) -> void:
	if not contexts.has(id):
		return
	for field: Dictionary in contexts[id].fields:
		set_parameter(id, field.property, field.initial)


func save_preset(id: String, preset_name: String) -> Error:
	if not contexts.has(id):
		return ERR_DOES_NOT_EXIST
	if preset_name.strip_edges().is_empty():
		_message = "Informe um nome para o preset."
		return ERR_INVALID_PARAMETER
	var context: Dictionary = contexts[id]
	var target: Node = context.target.get_ref()
	if not is_instance_valid(target):
		return ERR_DOES_NOT_EXIST
	var values: Dictionary = {}
	for field: Dictionary in context.fields:
		values[field.property] = target.get(field.property)
	_presets.set_value(id, preset_name.strip_edges(), values)
	DirAccess.make_dir_recursive_absolute(preset_path.get_base_dir())
	var error := _presets.save(preset_path)
	_message = "Preset salvo." if error == OK else "Falha ao salvar: " + error_string(error)
	return error


func load_preset(id: String, preset_name: String) -> bool:
	if not contexts.has(id):
		return false
	var values: Variant = _presets.get_value(id, preset_name, null)
	if not values is Dictionary:
		return false
	for property: String in values:
		set_parameter(id, property, values[property])
	_message = "Preset aplicado: " + preset_name
	return true
