extends SceneTree
## Run with --headless --path . --script res://debug/dev_assistance/verify_dev_assistance.gd
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
	_check(handler.contexts.size() == 2, "Visual and experiment menus registered")
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
	_check(scene.player.process_mode == Node.PROCESS_MODE_DISABLED, "Opening tools suspends player input")
	handler.set_tools_visible(false)
	_check(scene.player.process_mode == Node.PROCESS_MODE_INHERIT, "Closing tools resumes player")
	scene._reset_camera()
	handler.set_tools_visible(true)
	var toggle := InputEventKey.new()
	toggle.keycode = KEY_F9
	toggle.pressed = true
	Input.parse_input_event(toggle)
	await process_frame
	_check(not handler.tools_visible, "F9 input closes tools")
	toggle.pressed = false
	Input.parse_input_event(toggle)
	handler.set_tools_visible(true)
	# A generic target verifies that the addon does not depend on the visual scene.
	var target := Node3D.new()
	scene.add_child(target)
	handler.register_context("test.target", "Alvo de teste", null, target, [
		{"property": "visible", "label": "Visível", "description": "Teste de ciclo de vida."}])
	handler.contexts["test.target"].fields[0].pinned = true
	_check(handler.contexts.size() == 3, "Register unrelated target")
	target.queue_free()
	await process_frame
	_check(not handler.contexts.has("test.target"), "Remove menu and watches on target exit")
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
