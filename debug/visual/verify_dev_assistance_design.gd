extends SceneTree
## Graphical interaction checks for the Figma fixture; never uses the user's presets.
## Godot --path . --script res://debug/visual/verify_dev_assistance_design.gd

var checks := 0
var failed := false


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)


func _frames(count := 5) -> void:
	for i in count:
		await process_frame


func _mouse(at: Vector2, pressed := -1) -> void:
	Input.warp_mouse(at)
	if pressed == -1:
		var event := InputEventMouseMotion.new()
		event.position = at
		event.global_position = at
		Input.parse_input_event(event)
	else:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed == 1
		Input.parse_input_event(event)
	await _frames()


func _click(at: Vector2) -> void:
	await _mouse(at)
	await _mouse(at, 1)
	await _mouse(at, 0)


func _key(code: Key, unicode := 0, ctrl := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.unicode = unicode
	event.ctrl_pressed = ctrl
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(2)
	event.pressed = false
	Input.parse_input_event(event)
	await _frames(2)


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This test requires the graphical renderer.")
		quit(1)
		return
	var scene: Node = load("res://debug/visual/dev_assistance_design_preview.tscn").instantiate()
	root.add_child(scene)
	await _frames(20)
	var handler: DevAssistance = scene.ui
	handler.preset_path = "user://devassistance/design_verification.cfg"
	handler.set("_presets", ConfigFile.new())
	var context: Dictionary = handler.contexts["preview.player"]
	var origin: Vector2 = context.position
	_check(handler.contexts.size() == 8, "Eight demonstration cards registered")
	_check(origin == Vector2(24, 200), "Figma panel placement")
	await _mouse(Vector2(850, 630))
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("user://devassistance")
	root.get_texture().get_image().save_png("user://devassistance/figma_preview.png")
	await _click(origin + Vector2(166, 157))
	_check(absf(scene.speed - 5.0) < 0.1, "Slider maps cursor to the value range")
	await _click(origin + Vector2(250, 130))
	await _key(KEY_A, 0, true)
	await _key(KEY_7, 55)
	await _key(KEY_ENTER)
	_check(is_equal_approx(scene.speed, 7.0), "Numeric input accepts typed value")
	await _click(origin + Vector2(332, 130))
	_check(is_equal_approx(scene.speed, 5.0), "Restore icon resets only that parameter")
	await _click(origin + Vector2(318, 275))
	_check(scene.local_input, "Switch changes its live target")
	await _click(origin + Vector2(60, 130))
	_check(context.fields[0].pinned, "Clicking label pins the value")
	await _click(origin + Vector2(299, 28))
	_check(handler._all_pinned(context), "Panel pin selects all values")
	await _click(origin + Vector2(299, 28))
	_check(not context.fields[0].pinned, "Panel pin clears watches")
	await _click(origin + Vector2(145, 85))
	_check(context.tab == "Sistemas", "Tab switches content")
	await _click(origin + Vector2(50, 85))
	_check(context.tab == "Movimento", "Movement tab restores controls")
	await _click(origin + Vector2(330, 28))
	_check(context.collapsed, "Collapse button folds content")
	await _click(origin + Vector2(330, 28))
	_check(not context.collapsed, "Collapse button expands content")
	# The dialog focuses its name field; Tab/Enter activates its native save button.
	context.preset_name[0] = "__design_check__"
	await _click(origin + Vector2(275, 345))
	await _key(KEY_TAB)
	await _key(KEY_ENTER)
	_check(FileAccess.file_exists(handler.preset_path) and context.preset == "__design_check__", "Save dialog persists the named preset by keyboard")
	await _click(origin + Vector2(318, 275))
	_check(not scene.local_input, "Switch can be turned off")
	await _click(origin + Vector2(70, 345))
	await _click(origin + Vector2(120, 390))
	_check(scene.local_input, "Preset dropdown restores the switch")
	await _click(Vector2(76, 94))
	_check(not context.open[0], "Toolbar card closes its context")
	await _click(Vector2(76, 94))
	_check(context.open[0], "Toolbar card reopens its context")
	var header_origin: Vector2 = handler._header.position
	await _mouse(header_origin + Vector2(120, 20))
	await _mouse(header_origin + Vector2(120, 20), 1)
	await _mouse(header_origin + Vector2(170, 40))
	await _mouse(header_origin + Vector2(170, 40), 0)
	await _frames(45)
	_check(handler._header.position.distance_to(header_origin + Vector2(50, 20)) < 1.0, "Toolbar drag interpolates and settles")
	await _click(handler._header.position + Vector2(332, 23))
	_check(not handler.tools_visible, "Header close hides the tools")
	DirAccess.remove_absolute(handler.preset_path)
	# All preview contexts share one target; leaving removes every registration cleanly.
	var target := Node3D.new()
	root.add_child(target)
	for id in ["first", "second"]:
		handler.register_context(id, id, null, target, [])
	target.queue_free()
	await _frames()
	_check(not handler.contexts.has("first") and not handler.contexts.has("second"), "Shared target removes all contexts")
	print("[DevAssistance Design] %d checks; failed=%s" % [checks, failed])
	quit(1 if failed else 0)

