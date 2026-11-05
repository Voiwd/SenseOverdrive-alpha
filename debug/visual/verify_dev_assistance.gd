extends SceneTree
## Run with --headless --path . --script res://debug/visual/verify_dev_assistance.gd
## Omit --headless and pass -- --da-capture to save runtime screenshots in user://devassistance/.

const Handler := preload("res://addons/dev_assistance/context_handler.gd")
var checks := 0
var failed := false


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)


func _run() -> void:
	var scene := load("res://debug/visual/visual_debug.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var handler: DevAssistance = scene.ui
	_check(handler.contexts.size() == 3, "Visual, experiment and local player registered")
	_check(handler.set_parameter("visual.filters", "contrast", 99.0), "Set numeric parameter")
	_check(scene.post.contrast == 2.0, "Clamp upper bound")
	_check(not handler.set_parameter("visual.filters", "contrast", NAN), "Reject non-finite value")
	_check(not handler.set_parameter("visual.filters", "enabled", 1), "Reject wrong bool type")
	_check(not handler.set_parameter("visual.filters", "unknown", 1), "Reject unknown property")
	handler.reset_parameters("visual.filters")
	_check(scene.post.contrast == 1.0, "Restore initial value")
	# Keep this test isolated from the user's parameter presets.
	handler.preset_path = "user://devassistance/verification.cfg"
	handler.set("_presets", ConfigFile.new())
	handler.set_parameter("visual.filters", "contrast", 1.37)
	_check(handler.save_preset("visual.filters", "__verification__") == OK, "Persist preset")
	var disk_config := ConfigFile.new()
	_check(disk_config.load(handler.preset_path) == OK, "Read preset from disk")
	handler.set("_presets", disk_config)
	handler.set_parameter("visual.filters", "contrast", 0.5)
	_check(handler.load_preset("visual.filters", "__verification__"), "Load preset")
	_check(is_equal_approx(scene.post.contrast, 1.37), "Restore saved value")
	DirAccess.remove_absolute(handler.preset_path)
	handler.set("_presets", ConfigFile.new())
	scene.original_shadows = true
	_check(scene.light.directional_shadow_max_distance == 100.0, "Comparison setter applies immediately")
	scene._reset_experiment()
	_check(not scene.original_shadows and not scene.moving, "Reset experiment state")
	scene.player.position += Vector3(2, 0, 0)
	scene._reset_experiment()
	_check(scene.player.transform == scene._initial_player_transform, "Reset player position")
	handler.contexts["visual.filters"].fields[0].pinned = true
	scene._player_camera()
	_check(not handler.tools_visible, "Player mode closes tools")
	handler.set_tools_visible(true)
	_check(scene.player.process_mode == Node.PROCESS_MODE_INHERIT and not scene.player.input_enabled, "Opening tools blocks input but preserves simulation")
	scene.player.position.y += 2.0
	var elevated: float = scene.player.position.y
	for i in 12:
		await physics_frame
	_check(scene.player.position.y < elevated, "Gravity advances while tools are open")
	scene.moving = true
	var old_angle: float = scene.angle
	await process_frame
	await process_frame
	_check(scene.angle > old_angle and not paused, "Scene orbit advances with tools open")
	handler.set_tools_visible(false)
	_check(scene.player.process_mode == Node.PROCESS_MODE_INHERIT and scene.player.input_enabled, "Closing tools resumes player input")
	scene._reset_camera()
	handler.set_tools_visible(true)
	var editor_pause := InputEventKey.new()
	editor_pause.keycode = KEY_F9
	editor_pause.pressed = true
	Input.parse_input_event(editor_pause)
	await process_frame
	_check(handler.tools_visible, "F9 is not the tool shortcut")
	editor_pause.pressed = false
	Input.parse_input_event(editor_pause)
	var unmodified := InputEventKey.new()
	unmodified.keycode = KEY_D
	unmodified.pressed = true
	Input.parse_input_event(unmodified)
	await process_frame
	_check(handler.tools_visible, "D without modifiers does not toggle tools")
	unmodified.pressed = false
	Input.parse_input_event(unmodified)
	var toggle := InputEventKey.new()
	toggle.keycode = KEY_D
	toggle.ctrl_pressed = true
	toggle.alt_pressed = true
	toggle.pressed = true
	Input.parse_input_event(toggle)
	await process_frame
	_check(not handler.tools_visible, "Ctrl+Alt+D input closes tools")
	toggle.pressed = false
	Input.parse_input_event(toggle)
	handler.set_tools_visible(true)
	# A generic target verifies that the addon does not depend on the visual scene.
	var target := Node3D.new()
	scene.add_child(target)
	handler.register_context("test.target", "Alvo de teste", null, target, [
		{"property": "visible", "label": "Visível", "description": "Teste de ciclo de vida."}])
	handler.contexts["test.target"].fields[0].pinned = true
	_check(handler.contexts.size() == 4, "Register unrelated target")
	target.queue_free()
	await process_frame
	_check(not handler.contexts.has("test.target"), "Remove menu and watches on target exit")
	if DisplayServer.get_name() != "headless":
		await _verify_presentation(handler)
		await _verify_utilities(handler)
	if "--da-capture" in OS.get_cmdline_user_args():
		for dimensions in [Vector2i(1280, 720), Vector2i(800, 600), Vector2i(640, 360)]:
			root.size = dimensions
			for i in 15:
				await process_frame
			print("Dimensions ", dimensions, " root=", root.size, " io=", handler.gui.GetIO().DisplaySize, " visible=", root.get_visible_rect().size)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("user://devassistance/verify_%dx%d.png" % [dimensions.x, dimensions.y])
	print("[DevAssistance] %d checks; failed=%s" % [checks, failed])
	quit(1 if failed else 0)


func _mouse(position: Vector2, pressed: int = -1) -> void:
	if pressed < 0:
		Input.warp_mouse(position)
		var motion := InputEventMouseMotion.new()
		motion.position = position
		motion.global_position = position
		Input.parse_input_event(motion)
	else:
		var button := InputEventMouseButton.new()
		button.position = position
		button.global_position = position
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = pressed == 1
		Input.parse_input_event(button)
	for i in 3:
		await process_frame


func _verify_presentation(handler: DevAssistance) -> void:
	for i in 4:
		await process_frame
	var context: Dictionary = handler.contexts["visual.filters"]
	var origin: Vector2 = context.position
	var title := origin + Vector2(120, 12)
	await _mouse(title)
	await _mouse(title, 1)
	await _mouse(title + Vector2(110, 40))
	_check(context.destination.distance_to(origin + Vector2(110, 40)) < 2.0, "Title drag tracks cursor destination")
	_check(context.position.distance_to(origin) > 0.0 and context.position.distance_to(context.destination) > 0.0, "Panel interpolates during drag")
	await _mouse(title + Vector2(110, 40), 0)
	for i in 45:
		await process_frame
	_check(context.position.distance_to(context.destination) < 1.0, "Panel settles after release")
	# A deterministic pattern behind the tools makes the blur measurable, independent of room lighting.
	var pattern := CanvasLayer.new()
	pattern.layer = 126
	root.add_child(pattern)
	var swatch := ColorRect.new()
	pattern.add_child(swatch)
	swatch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; void fragment() { COLOR = vec4(vec3(step(0.5, fract(FRAGCOORD.x / 8.0))), 1.0); }"
	material.shader = shader
	swatch.material = material
	var old_blur := handler.background_blur
	handler.background_blur = 0.0
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var sharp := root.get_texture().get_image()
	handler.background_blur = 4.0
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var blurred := root.get_texture().get_image()
	var differences := 0
	for x in range(int(context.position.x) + 30, int(context.position.x) + 350):
		if sharp.get_pixel(x, 560) != blurred.get_pixel(x, 560):
			differences += 1
	_check(differences > 30, "Blur visibly changes the scene beneath panels")
	_check(sharp.get_pixel(1000, 650) == blurred.get_pixel(1000, 650), "Blur leaves the scene outside panels unchanged")
	handler.background_blur = old_blur
	pattern.queue_free()
	handler.suspended = true
	await process_frame
	await process_frame
	_check(not handler._glass.visible, "Benchmark suspension hides glass too")
	handler.suspended = false
	handler._layout_reset = true

func _verify_utilities(handler: DevAssistance) -> void:
	for ctx: Dictionary in handler.contexts.values():
		ctx.open[0] = false
	var browser: Dictionary = handler._utilities.scene_browser
	browser.open[0] = true
	handler._query[0] = "Character"
	for i in 8:
		await process_frame
	var result_pos: Vector2 = browser.position + Vector2(70, 127)
	await _mouse(result_pos)
	await _mouse(result_pos, 1)
	await _mouse(result_pos, 0)
	_check(handler.contexts["visual.player"].open[0] and not browser.open[0], "Browser searches target name and opens its Props")
	handler.contexts["visual.player"].open[0] = false
	browser.open[0] = false
	var field: Dictionary = handler.contexts["visual.player"].fields[0]
	field.pinned = true
	handler.contexts["visual.filters"].fields[0].pinned = false
	var wheel: Dictionary = handler._utilities.screen_space
	wheel.open[0] = true
	for i in 5:
		await process_frame
	var first: Vector2 = wheel.position + Vector2(170, 108)
	await _mouse(first)
	await _mouse(first, 1)
	await _mouse(first, 0)
	_check(not field.shown and field.pinned, "Radial toggle hides a 3D watch without removing its membership")
	wheel.open[0] = false
	handler._utilities.profiler.open[0] = true
	var orbit: Dictionary = handler.contexts["visual.experiment"].fields.back()
	orbit.pinned = true
	var before := Time.get_ticks_msec()
	current_scene.moving = not current_scene.moving
	await process_frame
	_check(orbit.fired_at >= before and orbit.fade_seconds > 0, "Orbit signal restarts its timed watch")
	handler._utilities.profiler.open[0] = false
