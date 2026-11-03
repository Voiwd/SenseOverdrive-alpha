extends Node3D
## F6: direct A/B inspection, independent material/shadow comparisons and repeatable capture.

const BEFORE_SHADER := preload("res://debug/reference/blocks_before_sen5.gdshader")
@onready var room: Node3D = $Room
@onready var post: CanvasLayer = $Room/WorldPostProcess
@onready var light: DirectionalLight3D = $Room/DirectionalLight3D
@onready var camera: Camera3D = $Camera
@onready var player: CharacterBody3D = $Room/Character
@onready var floor_mesh: MeshInstance3D = $Room/FloorBlock/MeshInstance3D
var original_material: ShaderMaterial
var corrected_material: ShaderMaterial
var original_shadows := false
var original_materials := false
var moving := false
var angle := 0.0
var ui: CanvasLayer
var column: VBoxContainer
var metrics: Label
var benchmarking := false
var switches: Dictionary = {}


func _ready() -> void:
	get_window().title = "Sense Overdrive | SEN-5 visual debug"
	get_window().size = Vector2i(1280, 720)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	corrected_material = floor_mesh.mesh.material
	original_material = corrected_material.duplicate() as ShaderMaterial
	original_material.shader = BEFORE_SHADER
	original_material.set_shader_parameter("roughness_value", 0.0)
	_apply_comparison()
	_build_samples()
	_build_ui()
	_reset_camera()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	if "--visual-verify" in OS.get_cmdline_user_args():
		benchmark.call_deferred()


func _process(delta: float) -> void:
	if moving:
		angle += delta * 0.25
		_update_camera()
	var rid := get_viewport().get_viewport_rid()
	metrics.text = "%d FPS | GPU %.2f ms\nViewport %s | grade virtual %.0f × %d" % [
		Engine.get_frames_per_second(), RenderingServer.viewport_get_measured_render_time_gpu(rid),
		get_viewport().get_visible_rect().size,
		post.virtual_height * get_viewport().get_visible_rect().size.aspect(), post.virtual_height]


func _unhandled_key_input(event: InputEvent) -> void:
	if benchmarking or not event.is_pressed() or event.is_echo():
		return
	if event.keycode == KEY_F1:
		switches["enabled"].button_pressed = not post.enabled
	elif event.keycode == KEY_F2:
		switches["original_shadows"].button_pressed = not original_shadows
	elif event.keycode == KEY_F3:
		switches["original_materials"].button_pressed = not original_materials
	elif event.keycode == KEY_F4:
		switches["moving"].button_pressed = not moving
	elif event.keycode == KEY_HOME:
		_reset_camera()


func _reset_camera() -> void:
	angle = 0.0
	camera.make_current()
	_update_camera()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _update_camera() -> void:
	camera.position = Vector3(4, 3.5, 6).rotated(Vector3.UP, angle)
	camera.look_at(Vector3(0, 1, 0))


func _player_camera() -> void:
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _apply_comparison() -> void:
	floor_mesh.material_override = original_material if original_materials else corrected_material
	# Only this room's shadow range changes; atlas/filter/bias stay at engine defaults.
	light.directional_shadow_max_distance = 100.0 if original_shadows else 30.0


func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -340
	panel.offset_right = -12
	panel.offset_top = 12
	panel.offset_bottom = -12
	ui.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)
	scroll.add_child(column)
	_label("SEN-5 · IMAGEM 3D / UI NÍTIDA")
	_label("F1: filtro · F2: sombras · F3: material\nF4: órbita · Home: câmera inicial")
	_toggle("enabled", "Pós-processamento (F1)", post.enabled, func(v: bool): post.enabled = v)
	_toggle("pixelization_enabled", "Pixelização", post.pixelization_enabled, func(v: bool): post.pixelization_enabled = v)
	_number("Resolução vertical virtual", 90, 2160, 1, post.virtual_height, func(v: float): post.virtual_height = int(v))
	_toggle("posterization_enabled", "Posterização", post.posterization_enabled, func(v: bool): post.posterization_enabled = v)
	_number("Níveis por canal RGB", 2, 256, 1, post.color_levels, func(v: float): post.color_levels = int(v))
	_toggle("contrast_enabled", "Contraste (1 = neutro)", post.contrast_enabled, func(v: bool): post.contrast_enabled = v)
	_number("Contraste", 0, 2, 0.01, post.contrast, func(v: float): post.contrast = v)
	_toggle("saturation_enabled", "Saturação (0 cinza / 1 neutro)", post.saturation_enabled, func(v: bool): post.saturation_enabled = v)
	_number("Saturação", 0, 2, 0.01, post.saturation, func(v: float): post.saturation = v)
	_toggle("original_shadows", "Sombras: original 100 m (F2)", false, func(v: bool):
		original_shadows = v
		_apply_comparison())
	_toggle("original_materials", "Material: original (F3)", false, func(v: bool):
		original_materials = v
		_apply_comparison())
	_toggle("moving", "Órbita em movimento (F4)", false, func(v: bool): moving = v)
	_button("Câmera inicial / sair do personagem", _reset_camera)
	_button("Câmera do personagem (Esc: mouse)", _player_camera)
	var sizes := HBoxContainer.new()
	column.add_child(sizes)
	for size in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1100, 800)]:
		var button := Button.new()
		button.text = "%d×%d" % [size.x, size.y]
		sizes.add_child(button)
		button.pressed.connect(func(): get_window().size = size)
	_button("Medir e capturar A/B (~1 min)", benchmark)
	_label("A medição oculta este painel e desliga VSync.\nResultado: user://sen5/ (CSV + PNG).\nLuz: Remote > Room/DirectionalLight3D.\nFiltro: Remote > Room/WorldPostProcess.")
	metrics = _label("")


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	column.add_child(label)
	return label


func _toggle(key: String, text: String, value: bool, action: Callable) -> void:
	var button := CheckButton.new()
	button.text = text
	button.button_pressed = value
	button.add_theme_font_size_override("font_size", 13)
	column.add_child(button)
	button.toggled.connect(action)
	switches[key] = button


func _number(text: String, minimum: float, maximum: float, step: float, value: float, action: Callable) -> void:
	var row := HBoxContainer.new()
	column.add_child(row)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var field := SpinBox.new()
	field.min_value = minimum
	field.max_value = maximum
	field.step = step
	field.value = value
	row.add_child(field)
	field.value_changed.connect(action)


func _button(text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	column.add_child(button)
	button.pressed.connect(action)


func _build_samples() -> void:
	for i in 7:
		var sample := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.25
		sphere.height = 0.5
		sample.mesh = sphere
		sample.position = Vector3(i - 3, 0.76, -2.5)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color.from_hsv(i / 7.0, 0.8, 0.8)
		material.roughness = 0.65
		sample.material_override = material
		add_child(sample)
	var gradient := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(4, 0.5)
	gradient.mesh = quad
	gradient.position = Vector3(0, 2.7, -2.5)
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded, cull_disabled; void fragment() { ALBEDO = vec3(UV.x); }"
	material.shader = shader
	gradient.material_override = material
	add_child(gradient)


func benchmark() -> void:
	if benchmarking:
		return
	benchmarking = true
	var old_size := get_window().size
	var old_vsync := DisplayServer.window_get_vsync_mode()
	var old_max_fps := Engine.max_fps
	var old_enabled: bool = post.enabled
	var old_shadow := original_shadows
	var old_material := original_materials
	var old_moving := moving
	var old_angle := angle
	var old_camera := get_viewport().get_camera_3d()
	var old_player_mode := player.process_mode
	var old_mouse := Input.mouse_mode
	player.process_mode = Node.PROCESS_MODE_DISABLED
	camera.make_current()
	ui.visible = false
	moving = false
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DirAccess.make_dir_recursive_absolute("user://sen5")
	var csv := FileAccess.open("user://sen5/measurements.csv", FileAccess.WRITE)
	csv.store_line("# Godot %s; %s; %s; %s" % [Engine.get_version_info().string,
		RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name(),
		RenderingServer.get_video_adapter_name()])
	csv.store_line("width,height,moving,mode,wall_ms,fps,gpu_ms")
	csv.store_line("# filter: virtual_height=%d; levels=%d; contrast=%.2f; saturation=%.2f" % [
		post.virtual_height, post.color_levels, post.contrast, post.saturation])
	csv.store_line("# enabled effects: pixels=%s; posterization=%s; contrast=%s; saturation=%s" % [
		post.pixelization_enabled, post.posterization_enabled, post.contrast_enabled, post.saturation_enabled])
	for size in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1100, 800)]:
		get_window().size = size
		for motion in [false, true]:
			for mode in ["before", "materials", "shadows", "filtered"]:
				original_materials = mode == "before"
				original_shadows = mode in ["before", "materials"]
				post.enabled = mode == "filtered"
				_apply_comparison()
				angle = 0
				_update_camera()
				for i in 120:
					await get_tree().process_frame
				var start := Time.get_ticks_usec()
				var gpu := 0.0
				for frame in 240:
					if motion:
						angle = frame / 240.0 * TAU
						_update_camera()
					await RenderingServer.frame_post_draw
					gpu += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
				var ms := (Time.get_ticks_usec() - start) / 240000.0
				csv.store_line("%d,%d,%s,%s,%.3f,%.1f,%.3f" % [size.x, size.y, motion, mode, ms, 1000.0 / ms, gpu / 240.0])
				csv.flush()
				print("[SEN5] ", size, " moving=", motion, " ", mode, " ms=", ms)
				# All modes capture the same angle, including the motion sequence's last frame.
				get_viewport().get_texture().get_image().save_png("user://sen5/%dx%d_%s_%s.png" % [size.x, size.y, motion, mode])
	csv.close()
	get_window().size = old_size
	DisplayServer.window_set_vsync_mode(old_vsync)
	Engine.max_fps = old_max_fps
	post.enabled = old_enabled
	original_shadows = old_shadow
	original_materials = old_material
	_apply_comparison()
	moving = old_moving
	angle = old_angle
	_update_camera()
	player.process_mode = old_player_mode
	old_camera.make_current()
	Input.mouse_mode = old_mouse
	ui.visible = true
	benchmarking = false
	print("[SEN5] Captures: ", ProjectSettings.globalize_path("user://sen5"))
	if "--visual-verify" in OS.get_cmdline_user_args():
		get_tree().quit()
