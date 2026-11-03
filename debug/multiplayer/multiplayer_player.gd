extends "res://characters/proto_character/character.gd"
## Only the owning peer reads input and simulates this debug character.
## The spawner assigns authority before this node enters the tree.

var spawn_position := Vector3.ZERO

@onready var body_controls: Node3D = $Visual/Rig/BodyControls


func _ready() -> void:
	camera.current = is_multiplayer_authority()
	super._ready()
	set_physics_process(is_multiplayer_authority())
	set_process_unhandled_input(is_multiplayer_authority())
	# Players collide with the arena, but cannot push another peer's simulation.
	collision_layer = 2
	collision_mask = 1
	var tag := Label3D.new()
	tag.text = "HOST" if get_multiplayer_authority() == 1 else "PEER %s" % name
	tag.position.y = 4.8
	tag.font_size = 40
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = Color(0.4, 0.9, 1.0) if get_multiplayer_authority() == 1 else Color(1.0, 0.65, 0.3)
	add_child(tag)
	# Keep menu access available immediately after connecting.
	if is_multiplayer_authority():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if is_multiplayer_authority():
		super._unhandled_input(event)


func _physics_process(delta: float) -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and get_window().has_focus():
		super._physics_process(delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, deceleration * delta)
		velocity.y = 0.0 if is_on_floor() else velocity.y + get_gravity().y * delta
		move_and_slide()
		_update_lean(delta)
	if position.y < -10.0:
		reset_to_spawn()


func _process(delta: float) -> void:
	super._process(delta)
	if not is_multiplayer_authority():
		_update_lean(delta)
	body_controls.movement_velocity = velocity


func reset_to_spawn() -> void:
	if is_multiplayer_authority():
		position = spawn_position
		velocity = Vector3.ZERO
