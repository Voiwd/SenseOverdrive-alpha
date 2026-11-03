extends SceneTree
## GPU regression checks. Run with Godot --path . --script res://debug/verify_post_process.gd
## Requires a real renderer (do not use --headless).

const POST := preload("res://effects/world_post_process.tscn")
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
	else:
		print("[SEN5 PASS] ", message)


func _render(viewport: Viewport) -> Image:
	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _color_close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01


func _run() -> void:
	root.size = Vector2i(640, 480)
	var source := CanvasLayer.new()
	root.add_child(source)
	var swatch := ColorRect.new()
	swatch.color = Color(0.7, 0.3, 0.1)
	swatch.size = Vector2(640, 480)
	source.add_child(swatch)
	var post := POST.instantiate()
	root.add_child(post)
	post.enabled = false
	var hud := CanvasLayer.new()
	hud.layer = 10
	root.add_child(hud)
	var hud_swatch := ColorRect.new()
	hud_swatch.color = Color(0.1, 0.9, 0.4)
	hud_swatch.size = Vector2(53, 37)
	hud.add_child(hud_swatch)
	var baseline := await _render(root)
	post.pixelization_enabled = false
	post.posterization_enabled = false
	post.enabled = true
	var neutral := await _render(root)
	_check(_color_close(baseline.get_pixel(100, 100), neutral.get_pixel(100, 100)), "Neutral values preserve source color")
	post.saturation = 0.0
	var grayscale := await _render(root)
	var gray := grayscale.get_pixel(100, 100)
	_check(absf(gray.r - gray.g) < 0.01 and absf(gray.g - gray.b) < 0.01, "Runtime saturation 0 produces grayscale")
	_check(_color_close(grayscale.get_pixel(20, 20), baseline.get_pixel(20, 20)), "HUD above layer 1 stays unfiltered")
	# Locate the physical edge after the project's canvas stretch, rather than
	# assuming logical Control coordinates are physical window coordinates.
	var edge := 20
	while edge + 1 < baseline.get_width() and _color_close(baseline.get_pixel(edge + 1, 20), baseline.get_pixel(20, 20)):
		edge += 1
	_check(edge < baseline.get_width() - 1 and _color_close(grayscale.get_pixel(edge, 20), baseline.get_pixel(edge, 20))
		and not _color_close(grayscale.get_pixel(edge + 1, 20), baseline.get_pixel(edge, 20)), "HUD edge stays at physical pixel coordinates")
	post.saturation_enabled = false
	var isolated := await _render(root)
	_check(_color_close(isolated.get_pixel(100, 100), baseline.get_pixel(100, 100)), "Saturation switch bypasses runtime value")
	post.contrast = 0.0
	var flat := await _render(root)
	_check(_color_close(flat.get_pixel(100, 100), Color(0.5, 0.5, 0.5)), "Runtime contrast updates uniforms")
	post.contrast_enabled = false
	post.posterization_enabled = true
	post.color_levels = 2
	var poster := await _render(root)
	_check(_color_close(poster.get_pixel(100, 100), Color(1, 0, 0)), "Two posterization levels include 0 and 1")
	post.enabled = false
	var bypass := await _render(root)
	_check(_color_close(bypass.get_pixel(100, 100), baseline.get_pixel(100, 100)), "Master bypass restores original image")
	_check(post.get_node("Overlay").mouse_filter == Control.MOUSE_FILTER_IGNORE, "Overlay never captures input")
	# Real SubViewport isolation: changing the root's uniforms cannot affect another viewport.
	var other := SubViewport.new()
	other.size = Vector2i(160, 120)
	other.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(other)
	var other_source := CanvasLayer.new()
	other.add_child(other_source)
	var other_swatch := ColorRect.new()
	other_swatch.size = Vector2(160, 120)
	other_swatch.color = swatch.color
	other_source.add_child(other_swatch)
	var other_post := POST.instantiate()
	other_post.pixelization_enabled = false
	other_post.posterization_enabled = false
	other.add_child(other_post)
	post.enabled = true
	var other_image := await _render(other)
	_check(_color_close(other_image.get_pixel(80, 60), baseline.get_pixel(100, 100)), "Different viewport preserves independent parameters")
	_check(other_post.get_node("Overlay").material != post.get_node("Overlay").material, "Viewport materials are independent resources")
	# Use a continuous 2D color ramp as known input, then inspect actual rendered
	# pixels inside square sample cells at both 16:9 sizes and an arbitrary aspect.
	var ramp := ShaderMaterial.new()
	var ramp_shader := Shader.new()
	ramp_shader.code = "shader_type canvas_item; render_mode unshaded; void fragment() { COLOR = vec4(SCREEN_UV, 0.0, 1.0); }"
	ramp.shader = ramp_shader
	swatch.material = ramp
	swatch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	post.posterization_enabled = false
	post.pixelization_enabled = true
	post.virtual_height = 90
	for size in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1100, 800)]:
		root.size = size
		var pixels := await _render(root)
		var block := float(size.y) / 90.0
		var start := int(ceil(20 * block)) + 1
		var end := int(floor(21 * block)) - 2
		var sample := pixels.get_pixel(start, start)
		_check(pixels.get_size() == size and sample == pixels.get_pixel(end, start)
			and sample == pixels.get_pixel(start, end)
			and sample != pixels.get_pixel(start + int(ceil(block)), start)
			and sample != pixels.get_pixel(start, start + int(ceil(block))), "Square pixel cells after resizing to %s" % size)
	# Camera switching must not change the number of overlays, or reparent any camera.
	var room: Node3D = load("res://scenes/room.tscn").instantiate()
	root.add_child(room)
	var camera := Camera3D.new()
	room.add_child(camera)
	for i in 4:
		camera.make_current()
		room.get_node("Character/CameraYaw/CameraPitch/SpringArm3D/Camera3D").make_current()
	_check(room.find_children("WorldPostProcess", "CanvasLayer", true, false).size() == 1, "Camera switches keep exactly one room overlay")
	print("[SEN5] Failures: ", failures)
	quit(1 if failures else 0)
