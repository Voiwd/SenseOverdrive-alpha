extends CharacterBody3D
## Simple movement; the visual rig tilts while the collision stays upright.

@export_range(0.0, 20.0, 0.1) var walk_speed := 2.0
@export_range(0.0, 20.0, 0.1) var sprint_speed := 4.0
@export_range(0.0, 50.0, 0.1) var acceleration := 6.0
@export_range(0.0, 50.0, 0.1) var deceleration := 7.0
@export_range(0.0, 45.0, 0.5, "degrees") var lean_angle := 8.0
@export_range(0.1, 30.0, 0.1) var lean_speed := 8.0
@export_range(0.1, 30.0, 0.1) var turn_speed := 10.0

@export_range(0.0001, 0.02, 0.0001) var mouse_sensitivity := 0.003

@onready var visual: Node3D = $Visual
@onready var rig: Node3D = $Visual/Rig
@onready var camera_yaw: Node3D = $CameraYaw
@onready var camera_pitch: Node3D = $CameraYaw/CameraPitch
@onready var camera: Camera3D = $CameraYaw/CameraPitch/SpringArm3D/Camera3D


## Runtime gate for local commands. Physics, gravity and visual updates keep running.
var input_enabled := true


func _ready() -> void:
	$CameraYaw/CameraPitch/SpringArm3D.add_excluded_object(get_rid())
	if camera.is_current():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or not camera.is_current():
		return
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_yaw.rotate_y(-event.screen_relative.x * mouse_sensitivity)
		camera_pitch.rotation.x = clampf(camera_pitch.rotation.x - event.screen_relative.y * mouse_sensitivity, deg_to_rad(-70.0), deg_to_rad(70.0))


func _process(delta: float) -> void:
	# Yaw is independent of the visual parent's movement lean.
	rig.rotation.y = lerp_angle(rig.rotation.y, camera_yaw.rotation.y, 1.0 - exp(-turn_speed * delta))


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if input_enabled else Vector2.ZERO
	var direction := camera_yaw.global_basis * Vector3(input.x, 0.0, input.y)
	direction.y = 0.0
	direction = direction.limit_length(1.0)
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var target := direction * speed
	var rate := acceleration if input.length_squared() > 0.0 else deceleration
	var horizontal_velocity := Vector2(velocity.x, velocity.z)
	horizontal_velocity = horizontal_velocity.move_toward(Vector2(target.x, target.z), rate * delta)
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.y
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0
	move_and_slide()
	_update_lean(delta)

func _update_lean(delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var local_motion := global_basis.inverse() * horizontal
	local_motion.y = 0.0
	var amount := clampf(local_motion.length() / maxf(walk_speed, 0.001), 0.0, 1.0)
	var target := Quaternion.IDENTITY
	if amount > 0.001:
		var axis := Vector3.UP.cross(local_motion.normalized())
		target = Quaternion(axis, deg_to_rad(lean_angle) * amount)
	visual.quaternion = visual.quaternion.slerp(target, 1.0 - exp(-lean_speed * delta))
