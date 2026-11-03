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
@export_range(0.3, 1.0, 0.01) var panel_opacity := 0.86

const PRESET_PATH := "user://devassistance/presets.cfg"
# Dear ImGui flags, kept local so this script also parses without the extension in release.
const HEADER_FLAGS := 1 | 2 | 4 | 64 | 256 # NoTitleBar, NoResize, NoMove, AutoResize, NoSavedSettings.
const WATCH_FLAGS := 1 | 64 | 256 | 512 # NoTitleBar, AutoResize, NoSavedSettings, NoMouseInputs.
const FIRST_USE := 4

var contexts: Dictionary = {}
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
	var style: Object = gui.GetStyle()
	style.WindowRounding = 10.0
	style.FrameRounding = 5.0
	style.GrabRounding = 5.0
	style.TabRounding = 5.0
	style.WindowPadding = Vector2(18, 16)
	style.FramePadding = Vector2(10, 7)
	style.ItemSpacing = Vector2(10, 10)
	style.ItemInnerSpacing = Vector2(8, 6)
	style.ScrollbarSize = 14.0
	# Dear ImGui color indices: text, muted text, panel, border and interaction states.
	var colors: PackedColorArray = style._GetColors()
	for entry in [[0, Color("e7edf3")], [1, Color("9caebd")],
		[2, Color("121b25")], [5, Color("344451")],
		[7, Color("263847")], [8, Color("365367")], [9, Color("466c82")],
		[10, Color("182633")], [11, Color("233849")], [12, Color("182633")],
		[18, Color("8bd7cf")], [19, Color("70b6b2")], [20, Color("a2eee1")],
		[21, Color("263e4d")], [22, Color("3a5d6d")], [23, Color("507b87")],
		[24, Color("294451")], [25, Color("3a5d6d")], [26, Color("507b87")]]:
		colors[entry[0]] = entry[1]
	style._SetColors(colors)
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
		fields.append(field)
	contexts[id] = {"title": title, "icon": icon, "target": weakref(target),
		"fields": fields, "actions": actions, "position": Vector2.ZERO, "destination": Vector2.ZERO, "fade": 0.0, "open": [false], "preset_name": ["Meu preset"]}
	# Remove both the menu and its watches before its target leaves the scene.
	target.tree_exiting.connect(_target_exiting.bind(id, target.get_instance_id()), CONNECT_ONE_SHOT)


func _target_exiting(id: String, instance_id: int) -> void:
	if contexts.has(id):
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
	gui.SetNextWindowPos(Vector2(16, 16))
	gui.SetNextWindowBgAlpha(panel_opacity)
	gui.Begin("DevAssistance##header", [], HEADER_FLAGS)
	gui.Text("DEV ASSISTANCE")
	gui.TextDisabled("Experimento em execução")
	gui.Separator()
	var index := 0
	for id: String in contexts:
		var context: Dictionary = contexts[id]
		gui.BeginGroup()
		if context.open[0]:
			gui.PushStyleColor(21, Color("3a5d6d"))
		var clicked := false
		if context.icon != null:
			clicked = gui.ImageButton("menu_" + id, context.icon, Vector2(42, 36))
		else:
			clicked = gui.ButtonEx(context.title.left(2) + "##" + id, Vector2(62, 50))
		if context.open[0]:
			gui.PopStyleColor()
		if clicked:
			context.open[0] = not context.open[0]
		_tip("Abrir / recolher " + context.title)
		gui.Text(context.title)
		gui.EndGroup()
		if index % 2 == 0 and index + 1 < contexts.size():
			gui.SameLine()
		index += 1
	gui.Separator()
	if gui.SmallButton("Reorganizar painéis"):
		_layout_reset = true
	gui.TextDisabled(toggle_shortcut.get_as_text() if toggle_shortcut != null else "Sem atalho")
	gui.TextDisabled("%d FPS · %.1f ms" % [Engine.get_frames_per_second(), get_process_delta_time() * 1000.0])
	_glass_panel()
	gui.End()


func _glass_panel() -> void:
	if _glass_rects.size() >= 16:
		return
	var display: Vector2 = gui.GetIO().DisplaySize
	var pos: Vector2 = gui.GetWindowPos() / display
	var extent: Vector2 = gui.GetWindowSize() / display
	_glass_rects.append(Vector4(pos.x, pos.y, extent.x, extent.y))


func _draw_context(id: String, context: Dictionary, index: int) -> void:
	# ImGui uses window pixels; canvas_items may expose a differently scaled Godot viewport.
	var viewport_size: Vector2 = gui.GetIO().DisplaySize
	var desired := Vector2(minf(430, viewport_size.x - 32), minf(590, viewport_size.y - 32))
	gui.SetNextWindowSize(desired, 0 if _layout_reset else FIRST_USE)
	if _layout_reset or context.position == Vector2.ZERO:
		context.position = Vector2(240 + index * 450, 16).clamp(Vector2(16, 16), (viewport_size - desired).max(Vector2(16, 16)))
		context.destination = context.position
	context.fade = minf(1.0, context.fade + _delta * 8.0)
	gui.SetNextWindowPos(context.position)
	gui.SetNextWindowBgAlpha(panel_opacity * context.fade)
	var expanded: bool = gui.Begin(context.title + "###devassistance_" + id, context.open, 4 | 256)
	# Keep the whole window reachable, including its scrollbar, after resizing.
	var window_size: Vector2 = gui.GetWindowSize()
	var position: Vector2 = gui.GetWindowPos()
	var available := (viewport_size - Vector2(32, 32)).max(Vector2(100, 60))
	if expanded and (window_size.x > available.x or window_size.y > available.y):
		window_size = window_size.min(available)
		gui.SetWindowSize(window_size)
	var mouse: Vector2 = gui.GetMousePos()
	# Only the title bar starts a drag; sliders, tabs, close and collapse keep their input.
	if gui.IsWindowHovered() and gui.IsMouseClicked(0) and mouse.y < position.y + gui.GetFrameHeight() and mouse.x > position.x + 30 and mouse.x < position.x + window_size.x - 30:
		_drag_id = id
		_drag_offset = mouse - position
	if _drag_id == id:
		context.destination = mouse - _drag_offset
	var limit := (viewport_size - window_size).max(Vector2.ZERO)
	context.destination = context.destination.clamp(Vector2.ZERO, limit)
	context.position = context.position.lerp(context.destination, 1.0 if drag_response <= 0.0 else 1.0 - exp(-drag_response * _delta)).clamp(Vector2.ZERO, limit)
	gui.SetWindowPos(context.position)
	_glass_panel()
	if expanded:
		var target: Node = context.target.get_ref()
		gui.TextDisabled(str(target.name))
		_tip("Alvo: " + str(target.get_path()))
		if gui.BeginTabBar("context_tabs"):
			if gui.BeginTabItem("Ajustes"):
				for field: Dictionary in context.fields:
					_draw_field(id, target, field)
				gui.EndTabItem()
			if gui.BeginTabItem("Ações / presets"):
				_draw_actions(id, context)
				gui.EndTabItem()
			if gui.BeginTabItem("Frame time"):
				gui.TextWrapped("Tempo do frame em ms, amostrado a cada 0,1 s. Não é um profiler de CPU/GPU.")
				if not _frame_times.is_empty():
					gui.PlotLines("ms", _frame_times, _frame_times.size())
				gui.EndTabItem()
			gui.EndTabBar()
	gui.End()


func _draw_field(id: String, target: Node, field: Dictionary) -> void:
	gui.PushID(id + ":" + field.property)
	var value := [target.get(field.property)]
	var changed := false
	if field.type == TYPE_BOOL:
		changed = gui.Checkbox(field.label, value)
	else:
		gui.Text(field.label)
		_tip(field.description)
		gui.SetNextItemWidth(-1.0)
		if field.type == TYPE_INT:
			changed = gui.SliderInt("##value", value, int(field.min), int(field.max))
		else:
			changed = gui.SliderFloat("##value", value, float(field.min), float(field.max))
	_tip(field.description + "\nCtrl+clique no slider: digitar valor.")
	if changed:
		set_parameter(id, field.property, value[0])
	if gui.SmallButton("Fixado" if field.pinned else "Fixar"):
		field.pinned = not field.pinned
	_tip("Mostrar este valor mesmo com o menu oculto. Clique novamente para remover.")
	gui.SameLine()
	if gui.SmallButton("Restaurar"):
		set_parameter(id, field.property, field.initial)
	_tip("Recuperar o valor inicial deste parâmetro.")
	gui.Separator()
	gui.PopID()


func _tip(description: String) -> void:
	if gui.IsItemHovered():
		gui.SetTooltip(description)


func _draw_actions(id: String, context: Dictionary) -> void:
	for action: Dictionary in context.actions:
		if gui.Button(action.label):
			action.callback.call_deferred()
		_tip(action.description)
	gui.SeparatorText("Parâmetros")
	if gui.Button("Restaurar parâmetros iniciais"):
		reset_parameters(id)
	gui.InputText("Nome do preset", context.preset_name, 64)
	if gui.Button("Salvar / substituir preset"):
		save_preset(id, context.preset_name[0])
	for preset: String in _presets.get_section_keys(id) if _presets.has_section(id) else []:
		if gui.Button("Aplicar: " + preset):
			load_preset(id, preset)
	if not _message.is_empty():
		gui.TextWrapped(_message)
	gui.TextWrapped("Presets guardam parâmetros, não o estado completo da simulação.")


func _draw_watches() -> void:
	var lines: Array[String] = []
	for context: Dictionary in contexts.values():
		var target: Node = context.target.get_ref()
		if not is_instance_valid(target):
			continue
		for field: Dictionary in context.fields:
			if field.pinned:
				lines.append("%s / %s: %s" % [context.title, field.label, target.get(field.property)])
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
	for line: String in lines:
		gui.Text(line)
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
