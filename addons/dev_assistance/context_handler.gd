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
	gui.GetStyle().WindowRounding = 6.0
	gui.GetStyle().FrameRounding = 3.0
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
		"fields": fields, "actions": actions, "open": [false], "preset_name": ["Meu preset"]}
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
		_old_mouse = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = _old_mouse
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
	if gui == null or suspended:
		return
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
			if context.open[0]:
				_draw_context(id, context, index)
			index += 1
		_layout_reset = false
	_draw_watches()


func _draw_header() -> void:
	gui.SetNextWindowPos(Vector2(12, 12))
	gui.Begin("DevAssistance##header", [], HEADER_FLAGS)
	gui.Text("DevAssistance / " + (toggle_shortcut.get_as_text() if toggle_shortcut != null else "sem atalho"))
	var index := 0
	for id: String in contexts:
		var context: Dictionary = contexts[id]
		var clicked: bool
		if context.icon != null:
			clicked = gui.ImageButton("menu_" + id, context.icon, Vector2(24, 24))
		else:
			clicked = gui.Button(context.title + "##" + id)
		if clicked:
			context.open[0] = not context.open[0]
		_tip("Abrir/fechar ferramentas de " + context.title)
		if index % 2 == 0 and index + 1 < contexts.size():
			gui.SameLine()
		index += 1
	if gui.Button("Layout inicial"):
		_layout_reset = true
	gui.Text("%d FPS | %.1f ms" % [Engine.get_frames_per_second(), get_process_delta_time() * 1000.0])
	gui.End()


func _draw_context(id: String, context: Dictionary, index: int) -> void:
	# ImGui uses window pixels; canvas_items may expose a differently scaled Godot viewport.
	var viewport_size: Vector2 = gui.GetIO().DisplaySize
	var desired := Vector2(minf(410, viewport_size.x - 24), minf(560, viewport_size.y - 160))
	gui.SetNextWindowSize(desired, 0 if _layout_reset else FIRST_USE)
	gui.SetNextWindowPos(Vector2(12 + index * 36, 140 + index * 20), 0 if _layout_reset else FIRST_USE)
	var expanded: bool = gui.Begin(context.title + "###devassistance_" + id, context.open)
	# Keep the whole window reachable, including its scrollbar, after resizing.
	var window_size: Vector2 = gui.GetWindowSize()
	var position: Vector2 = gui.GetWindowPos()
	var available := (viewport_size - Vector2(24, 160)).max(Vector2(100, 60))
	if expanded and (window_size.x > available.x or window_size.y > available.y):
		window_size = window_size.min(available)
		gui.SetWindowSize(window_size)
	gui.SetWindowPos(position.clamp(Vector2.ZERO, (viewport_size - window_size).max(Vector2.ZERO)))
	if expanded:
		var target: Node = context.target.get_ref()
		gui.TextWrapped("Alvo: " + str(target.get_path()))
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
	var pinned := [field.pinned]
	if gui.Checkbox("Fixar na tela", pinned):
		field.pinned = pinned[0]
	gui.SameLine()
	if gui.SmallButton("Restaurar"):
		set_parameter(id, field.property, field.initial)
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
	gui.SetNextWindowPos(Vector2(maxf(12, window_size.x - text_width - 24),
		maxf(12, window_size.y - 20 - lines.size() * gui.GetTextLineHeightWithSpacing())))
	gui.SetNextWindowBgAlpha(0.92)
	gui.Begin("Observações##devassistance", [], WATCH_FLAGS)
	for line: String in lines:
		gui.Text(line)
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
