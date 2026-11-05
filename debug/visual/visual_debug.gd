extends Node3D
## F6: direct A/B inspection, independent material/shadow comparisons and repeatable capture.

const BEFORE_SHADER := preload("res://debug/visual/reference/blocks_before_sen5.gdshader")
@onready var room: Node3D = $Room
@onready var post: CanvasLayer = $Room/WorldPostProcess
@onready var light: DirectionalLight3D = $Room/DirectionalLight3D
@onready var camera: Camera3D = $Camera
@onready var player: CharacterBody3D = $Room/Character
@onready var floor_mesh: MeshInstance3D = $Room/FloorBlock/MeshInstance3D
@onready var _initial_player_transform := player.transform
@onready var _initial_yaw: Vector3 = player.camera_yaw.rotation
@onready var _initial_pitch: Vector3 = player.camera_pitch.rotation
var original_material: ShaderMaterial
var corrected_material: ShaderMaterial
var original_shadows := false:
	set(value):
		original_shadows = value
		if is_node_ready():
			_apply_comparison()
var original_materials := false:
	set(value):
		original_materials = value
		if is_node_ready():
			_apply_comparison()
var moving := false
var angle := 0.0
var ui: DevAssistance
var player_view := false
var benchmarking := false


func _ready() -> void:
	if not OS.is_debug_build():
		set_process(false)
		set_process_unhandled_key_input(false)
		return
	get_window().title = "Sense Overdrive | DevAssistance / Visual"
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



func _unhandled_key_input(event: InputEvent) -> void:
	if benchmarking or not event.is_pressed() or event.is_echo():
		return
	if event.keycode == KEY_F1:
		post.enabled = not post.enabled
	elif event.keycode == KEY_F2:
		original_shadows = not original_shadows
	elif event.keycode == KEY_F3:
		original_materials = not original_materials
	elif event.keycode == KEY_F4:
		moving = not moving
	elif event.keycode == KEY_HOME:
		_reset_camera()


func _reset_camera() -> void:
	player_view = false
	angle = 0.0
	camera.make_current()
	_update_camera()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _update_camera() -> void:
	camera.position = Vector3(4, 3.5, 6).rotated(Vector3.UP, angle)
	camera.look_at(Vector3(0, 1, 0))


func _player_camera() -> void:
	player_view = true
	ui.set_tools_visible(false)
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _apply_comparison() -> void:
	floor_mesh.material_override = original_material if original_materials else corrected_material
	# Only this room's shadow range changes; atlas/filter/bias stay at engine defaults.
	light.directional_shadow_max_distance = 100.0 if original_shadows else 30.0


func _build_ui() -> void:
	ui = DevAssistance.new()
	ui.name = "DevAssistance"
	add_child(ui)
	ui.visibility_changed.connect(_tools_visibility_changed)
	ui.register_context("visual.filters", "Visual", preload("res://addons/dev_assistance/icons/figma/visual.svg"), post, [
		_field("enabled", "Filtro (F1)", "Liga ou desliga todo o pós-processamento."),
		_field("pixelization_enabled", "Pixelização", "Reduz a resolução virtual da imagem 3D."),
		_field("virtual_height", "Altura virtual", "Pixels verticais. Menos pixels produzem blocos maiores.", 90, 2160),
		_field("posterization_enabled", "Posterização", "Limita o número de níveis por canal de cor."),
		_field("color_levels", "Níveis RGB", "Níveis por canal. Menos níveis aumentam as faixas de cor.", 2, 256),
		_field("contrast_enabled", "Ajustar contraste", "Ativa o multiplicador de contraste."),
		_field("contrast", "Contraste", "1 é neutro; valores maiores acentuam diferenças de luminosidade.", 0, 2),
		_field("saturation_enabled", "Ajustar saturação", "Ativa o ajuste de intensidade das cores."),
		_field("saturation", "Saturação", "0 é cinza; 1 é neutro; acima de 1 intensifica as cores.", 0, 2),
	], [
		_action("Sem filtro", "Comparar o resultado com a imagem 3D sem filtro.", func(): post.enabled = false),
		_action("Filtro ativo", "Retomar o filtro com os parâmetros atuais.", func(): post.enabled = true),
	])
	ui.register_context("visual.experiment", "Experimento", preload("res://addons/dev_assistance/icons/figma/experiment.svg"), self, [
		_field("original_shadows", "Sombras originais (F2)", "Compara alcance original de 100 m com o corrigido de 30 m."),
		_field("original_materials", "Material original (F3)", "Alterna o material de referência e o material corrigido."),
		_field("moving", "Órbita (F4)", "Gira a câmera ao redor da sala durante a comparação."),
	], [
		_action("Reiniciar experimento", "Restaura parâmetros, comparações e câmera inicial.", _reset_experiment),
		_action("Câmera inicial (Home)", "Volta à vista de órbita e desativa o controle do personagem.", _reset_camera),
		_action("Controlar personagem", "Fecha as ferramentas e captura o mouse. Ctrl+Alt+D reabre sem pausar a simulação.", _player_camera),
		_action("Janela 1280 x 720", "Resolução de teste.", func(): get_window().size = Vector2i(1280, 720)),
		_action("Janela 1920 x 1080", "Resolução de teste.", func(): get_window().size = Vector2i(1920, 1080)),
		_action("Janela 800 x 600", "Verificar acesso aos controles em uma janela menor.", func(): get_window().size = Vector2i(800, 600)),
		_action("Medir e capturar A/B", "Oculta as ferramentas, desliga VSync e mede as comparações. Resultados: user://sen5/.", benchmark),
	])
	ui.contexts["visual.filters"].open[0] = true


func _field(property: String, label: String, description: String, minimum := 0.0, maximum := 1.0) -> Dictionary:
	return {"property": property, "label": label, "description": description, "min": minimum, "max": maximum}


func _action(label: String, description: String, callback: Callable) -> Dictionary:
	return {"label": label, "description": description, "callback": callback}


func _tools_visibility_changed(open: bool) -> void:
	if player_view:
		player.input_enabled = not open


func _reset_experiment() -> void:
	ui.reset_parameters("visual.filters")
	ui.reset_parameters("visual.experiment")
	player.transform = _initial_player_transform
	player.velocity = Vector3.ZERO
	player.camera_yaw.rotation = _initial_yaw
	player.camera_pitch.rotation = _initial_pitch
	player.visual.quaternion = Quaternion.IDENTITY
	player.rig.rotation = Vector3.ZERO
	_reset_camera()


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
	ui.suspended = true
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
	ui.suspended = false
	benchmarking = false
	print("[SEN5] Captures: ", ProjectSettings.globalize_path("user://sen5"))
	if "--visual-verify" in OS.get_cmdline_user_args():
		get_tree().quit()
