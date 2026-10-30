extends Node3D

const LIMBS := ["LeftArm", "RightArm", "LeftLeg", "RightLeg"]
const LABELS := ["Braço esquerdo", "Braço direito", "Perna esquerda", "Perna direita"]
const BODY_BONES := ["Root", "Torso", "Torso.001", "Neck", "Head", "Head.001", "Head.002"]
const BODY_LABELS := ["Pelve", "Tronco inferior", "Tronco superior", "Pescoço", "Cabeça", "Cabeça 2", "Cabeça 3"]
const JOINT_BONES := ["Arm.L", "Arm.R", "Leg.L", "Leg.R"]
const PROPERTIES := ["left_arm_ik", "right_arm_ik", "left_leg_ik", "right_leg_ik"]

@onready var controls: Node3D = $Rig/BodyControls
@onready var camera: Camera3D = $Camera
var selected := 0
var initial_positions: Dictionary = {}
var switches: Array[CheckButton] = []
var position_fields: Array[SpinBox] = []
var pole_fields: Array[SpinBox] = []
var status: Label
var limb_picker: OptionButton
var joint_handles: Array[Node3D] = []
var body_handles: Array[Node3D] = []
var body_picker: OptionButton
var body_fields: Array[SpinBox] = []
var pelvis_fields: Array[SpinBox] = []
var body_selected := 0
var dragging_fk := false
var drag_mouse_start := Vector2.ZERO
var drag_rotation_start := Vector3.ZERO
var dragging_marker: Node3D
var drag_plane: Plane
var drag_start_hit: Vector3
var drag_start_position: Vector3
var orbit_angle := 0.0
var orbit_height := 12.0
var camera_distance := 20.0
var orbiting := false
var camera_sliders: Dictionary = {}
var refreshing := false


func _ready() -> void:
	for limb in LIMBS:
		for kind in ["Target", "Pole"]:
			var marker := _marker(limb, kind)
			initial_positions[limb + kind] = marker.position
			_add_marker_visual(marker, kind == "Target")
	for i in LIMBS.size():
		var handle := Node3D.new()
		add_child(handle)
		_add_marker_visual(handle, false)
		joint_handles.append(handle)
	for i in BODY_BONES.size():
		var handle := Node3D.new()
		add_child(handle)
		_add_body_visual(handle)
		body_handles.append(handle)
	var skeleton: Skeleton3D = controls.skeleton
	skeleton.skeleton_updated.connect(_update_joint_handles)
	_update_joint_handles()
	_build_interface()
	_build_body_interface()
	_switch_body(0)
	_switch_limb(0)
	switches[0].button_pressed = true
	_update_camera()


func _marker(limb: String, kind: String) -> Node3D:
	return controls.get_node("IKTargets/" + limb + kind)


func _add_marker_visual(marker: Node3D, is_target: bool) -> void:
	var visual := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.20 if is_target else 0.14
	sphere.height = sphere.radius * 2.0
	visual.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.15, 0.75, 1.0) if is_target else Color(1.0, 0.62, 0.08)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	visual.material_override = material
	marker.add_child(visual)


func _add_body_visual(marker: Node3D) -> void:
	_add_marker_visual(marker, true)
	var visual := marker.get_child(0) as MeshInstance3D
	var material := visual.material_override as StandardMaterial3D
	material.albedo_color = Color(0.9, 0.3, 1.0)


func _build_interface() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(360, 0)
	layer.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)
	_add_label(column, "TESTE DE IK", 20)
	_add_label(column, "Arraste azul: alvo  •  laranja: dobra", 13)
	_add_label(column, "Arraste no plano da câmera; gire para mudar o eixo.", 13)
	var choose := OptionButton.new()
	limb_picker = choose
	choose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for label in LABELS: choose.add_item(label)
	choose.item_selected.connect(_switch_limb)
	column.add_child(choose)
	var switch_row := HBoxContainer.new()
	column.add_child(switch_row)
	for i in LIMBS.size():
		var toggle := CheckButton.new()
		toggle.text = ["BE", "BD", "PE", "PD"][i]
		toggle.tooltip_text = LABELS[i]
		toggle.toggled.connect(_set_enabled.bind(i))
		switch_row.add_child(toggle)
		switches.append(toggle)
	status = _add_label(column, "", 13)
	_add_label(column, "Posição do alvo", 15)
	position_fields = _add_vector_fields(column, "Target")
	_add_label(column, "Posição do polo", 15)
	pole_fields = _add_vector_fields(column, "Pole")
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	var reset_selected := Button.new()
	reset_selected.text = "Restaurar membro"
	reset_selected.pressed.connect(_reset_selected)
	buttons.add_child(reset_selected)
	var reset_all := Button.new()
	reset_all.text = "Restaurar tudo"
	reset_all.pressed.connect(_reset_all)
	buttons.add_child(reset_all)
	_add_label(column, "Câmera: arraste com o botão do meio", 15)
	_add_camera_slider(column, "Girar", -180.0, 180.0, orbit_angle, func(v): orbit_angle = v; _update_camera())
	_add_camera_slider(column, "Altura", -20.0, 70.0, orbit_height, func(v): orbit_height = v; _update_camera())
	_add_camera_slider(column, "Distância", 12.0, 35.0, camera_distance, func(v): camera_distance = v; _update_camera())


func _build_body_interface() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -310
	panel.offset_right = -12
	panel.offset_top = 12
	layer.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)
	_add_label(column, "CORPO / FK", 20)
	_add_label(column, "Arraste roxo: girar; pelve: mover", 13)
	body_picker = OptionButton.new()
	for label in BODY_LABELS: body_picker.add_item(label)
	body_picker.item_selected.connect(_switch_body)
	column.add_child(body_picker)
	_add_label(column, "Rotação local (graus)", 15)
	body_fields = _add_fk_fields(column, false)
	_add_label(column, "Posição da pelve", 15)
	pelvis_fields = _add_fk_fields(column, true)
	var reset := Button.new()
	reset.text = "Restaurar corpo"
	reset.pressed.connect(_reset_body)
	column.add_child(reset)


func _add_fk_fields(parent: Node, pelvis: bool) -> Array[SpinBox]:
	var fields: Array[SpinBox] = []
	var row := HBoxContainer.new()
	parent.add_child(row)
	for axis in 3:
		_add_label(row, ["X", "Y", "Z"][axis], 13)
		var field := SpinBox.new()
		field.min_value = -50 if pelvis else -180
		field.max_value = 50 if pelvis else 180
		field.step = 0.1 if pelvis else 1.0
		field.custom_minimum_size.x = 65
		field.value_changed.connect(_change_fk_axis.bind(pelvis, axis))
		row.add_child(field)
		fields.append(field)
	return fields


func _switch_body(index: int) -> void:
	body_selected = index
	_refresh_body_fields()


func _refresh_body_fields() -> void:
	refreshing = true
	var rotation: Vector3 = controls.fk_controls.get_node(BODY_BONES[body_selected]).rotation_degrees
	var position: Vector3 = controls.fk_controls.get_node("Root").position
	for axis in 3:
		body_fields[axis].value = rotation[axis]
		pelvis_fields[axis].value = position[axis]
	refreshing = false


func _change_fk_axis(value: float, pelvis: bool, axis: int) -> void:
	if refreshing: return
	controls.fk_enabled = true
	var control: Node3D = controls.fk_controls.get_node("Root" if pelvis else BODY_BONES[body_selected])
	if pelvis:
		var offset := control.position
		offset[axis] = value
		control.position = offset
	else:
		var angles := control.rotation_degrees
		angles[axis] = value
		control.rotation_degrees = angles


func _reset_body() -> void:
	for child in controls.fk_controls.get_children():
		child.rotation = Vector3.ZERO
	controls.fk_controls.get_node("Root").position = Vector3.ZERO
	controls.fk_enabled = true
	_refresh_body_fields()


func _add_label(parent: Node, value: String, size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label


func _add_vector_fields(parent: Node, kind: String) -> Array[SpinBox]:
	var fields: Array[SpinBox] = []
	var row := HBoxContainer.new()
	parent.add_child(row)
	for axis in 3:
		_add_label(row, ["X", "Y", "Z"][axis], 13)
		var field := SpinBox.new()
		field.min_value = -50.0
		field.max_value = 50.0
		field.step = 0.1
		field.custom_minimum_size.x = 80
		field.value_changed.connect(_change_axis.bind(kind, axis))
		row.add_child(field)
		fields.append(field)
	return fields


func _add_camera_slider(parent: Node, label: String, minimum: float, maximum: float, value: float, callback: Callable) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var title := _add_label(row, label, 13)
	title.custom_minimum_size.x = 65
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(callback)
	camera_sliders[label] = slider
	row.add_child(slider)


func _switch_limb(index: int) -> void:
	selected = index
	_refresh_fields()


func _set_enabled(enabled: bool, index: int) -> void:
	controls.set(PROPERTIES[index], enabled)
	_refresh_status()


func _refresh_status() -> void:
	if status:
		status.text = "Membro selecionado: " + ("IK ligado" if controls.get(PROPERTIES[selected]) else "IK desligado")


func _refresh_fields() -> void:
	refreshing = true
	for pair in [["Target", position_fields], ["Pole", pole_fields]]:
		var position: Vector3 = _marker(LIMBS[selected], pair[0]).position
		for axis in 3: pair[1][axis].value = position[axis]
	refreshing = false
	_refresh_status()


func _change_axis(value: float, kind: String, axis: int) -> void:
	if refreshing: return
	var marker := _marker(LIMBS[selected], kind)
	var position := marker.position
	position[axis] = value
	marker.position = position


func _reset_selected() -> void:
	for kind in ["Target", "Pole"]:
		_marker(LIMBS[selected], kind).position = initial_positions[LIMBS[selected] + kind]
	_refresh_fields()


func _reset_all() -> void:
	for limb in LIMBS:
		for kind in ["Target", "Pole"]:
			_marker(limb, kind).position = initial_positions[limb + kind]
	_refresh_fields()
	_reset_body()


func _update_camera() -> void:
	var yaw := deg_to_rad(orbit_angle)
	var pitch := deg_to_rad(orbit_height)
	var focus := Vector3(0, 5.5, 0)
	camera.position = focus + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * camera_distance
	camera.look_at(focus)


func _update_joint_handles() -> void:
	var skeleton: Skeleton3D = controls.skeleton
	for i in joint_handles.size():
		var bone := skeleton.find_bone(JOINT_BONES[i])
		joint_handles[i].global_position = skeleton.to_global(skeleton.get_bone_global_pose(bone).origin)
	for i in body_handles.size():
		var bone := skeleton.find_bone(BODY_BONES[i])
		body_handles[i].global_position = skeleton.to_global(skeleton.get_bone_global_pose(bone).origin)


func _input(event: InputEvent) -> void:
	# Release even if the pointer ends over the interface.
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging_marker = null
			dragging_fk = false
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			orbiting = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			orbiting = true
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and orbiting:
		orbit_angle = wrapf(orbit_angle - event.relative.x * 0.35, -180.0, 180.0)
		orbit_height = clampf(orbit_height + event.relative.y * 0.35, -20.0, 70.0)
		camera_sliders["Girar"].set_value_no_signal(orbit_angle)
		camera_sliders["Altura"].set_value_no_signal(orbit_height)
		_update_camera()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_drag(event.position)
		else:
			dragging_marker = null
	elif event is InputEventMouseMotion and dragging_fk:
		_drag_body(event.position)
	elif event is InputEventMouseMotion and dragging_marker:
		_drag_to(event.position)


func _begin_drag(mouse: Vector2) -> void:
	# Pick by screen distance, including the actual elbow/knee as a pole handle.
	var best_distance := 22.0
	var best_index := -1
	var best_kind := ""
	var best_position := Vector3.ZERO
	for i in LIMBS.size():
		for candidate in [[_marker(LIMBS[i], "Target"), "Target"], [joint_handles[i], "Pole"], [_marker(LIMBS[i], "Pole"), "Pole"]]:
			var point: Vector3 = candidate[0].global_position
			if camera.is_position_behind(point):
				continue
			var distance := camera.unproject_position(point).distance_to(mouse)
			if distance < best_distance:
				best_distance = distance
				best_index = i
				best_kind = candidate[1]
				best_position = point
	var body_index := -1
	for i in body_handles.size():
		var point := body_handles[i].global_position
		if camera.is_position_behind(point): continue
		var distance := camera.unproject_position(point).distance_to(mouse)
		if distance < best_distance:
			best_distance = distance
			body_index = i
	if body_index >= 0:
		body_picker.select(body_index)
		_switch_body(body_index)
		controls.fk_enabled = true
		dragging_fk = true
		drag_mouse_start = mouse
		var control: Node3D = controls.fk_controls.get_node(BODY_BONES[body_index])
		drag_rotation_start = control.rotation_degrees
		if body_index == 0:
			drag_plane = Plane(camera.global_basis.z, body_handles[body_index].global_position)
			var hit = drag_plane.intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
			if hit == null:
				dragging_fk = false
				return
			drag_start_hit = hit
			drag_start_position = control.position
		get_viewport().set_input_as_handled()
		return
	if best_index < 0:
		return
	limb_picker.select(best_index)
	_switch_limb(best_index)
	switches[best_index].button_pressed = true
	dragging_marker = _marker(LIMBS[best_index], best_kind)
	drag_plane = Plane(camera.global_basis.z, best_position)
	var hit = drag_plane.intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
	if hit == null:
		dragging_marker = null
		return
	drag_start_hit = hit
	drag_start_position = dragging_marker.global_position
	get_viewport().set_input_as_handled()


func _drag_to(mouse: Vector2) -> void:
	var hit = drag_plane.intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
	if hit != null:
		dragging_marker.global_position = drag_start_position + (hit - drag_start_hit)
		_refresh_fields()
		get_viewport().set_input_as_handled()


func _drag_body(mouse: Vector2) -> void:
	var control: Node3D = controls.fk_controls.get_node(BODY_BONES[body_selected])
	if body_selected == 0:
		var hit = drag_plane.intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
		if hit == null: return
		var skeleton: Skeleton3D = controls.skeleton
		var local_delta: Vector3 = skeleton.global_basis.inverse() * (hit - drag_start_hit)
		control.position = drag_start_position + local_delta
	else:
		var delta := mouse - drag_mouse_start
		control.rotation_degrees = drag_rotation_start + Vector3(delta.y * 0.5, delta.x * 0.5, 0)
	_refresh_body_fields()
	get_viewport().set_input_as_handled()
