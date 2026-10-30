extends Node3D
## Optional rig controls. IK targets and poles are children of IKTargets.
## FK controls are local rotation offsets from the imported bone poses.

@export var walk_speed: float = 2.0
@export var run_speed: float = 4.0
@export var walk_stride_length: float = 1.25
@export var run_stride_length: float = 2.0
@export var blend_speed: float = 8.0

var movement_velocity: Vector3 = Vector3.ZERO
var gait_enabled: bool = true

@export var fk_enabled := false
@export var left_leg_ik := false
@export var right_leg_ik := false
@export var left_arm_ik := false
@export var right_arm_ik := false

@onready var skeleton: Skeleton3D = $"../Armature/Skeleton3D"
@onready var fk_controls: Node3D = $FKControls
@onready var targets: Node3D = $IKTargets

var _legs: Array[Dictionary] = []
var _phase: float = 0.0
var _blend: float = 0.0

var _rest_rotations: Array[Quaternion] = []
var _root_rest_position := Vector3.ZERO
var _solvers: Dictionary = {}
var _was_fk_enabled := false
var _was_gait_enabled := true


func _ready() -> void:
	_root_rest_position = skeleton.get_bone_pose_position(skeleton.find_bone("Root"))
	for bone in skeleton.get_bone_count():
		_rest_rotations.append(skeleton.get_bone_pose_rotation(bone))
	for side in ["L", "R"]:
		var thigh := skeleton.find_bone("Tight." + side)
		var shin := skeleton.find_bone("Leg." + side)
		var foot := skeleton.find_bone("Foot." + side)
		if thigh < 0 or shin < 0 or foot < 0:
			push_warning("Procedural gait: missing leg bones for " + side)
			set_physics_process(false)
			return
		_legs.append({
			"thigh": thigh, "shin": shin, "foot": foot,
			"thigh_rest": skeleton.get_bone_pose_rotation(thigh),
			"shin_rest": skeleton.get_bone_pose_rotation(shin),
			"foot_rest": skeleton.get_bone_pose_rotation(foot),
		})

	_create_solver("LeftLeg", "Tight.L", "Foot.L")
	_create_solver("RightLeg", "Tight.R", "Foot.R")
	_create_solver("LeftArm", "Shoulder.L", "Hand.L")
	_create_solver("RightArm", "Shoulder.R", "Hand.R")


func _create_solver(label: String, root_bone: String, tip_bone: String) -> void:
	var solver := SkeletonIK3D.new()
	solver.name = label + "IK"
	solver.root_bone = root_bone
	solver.tip_bone = tip_bone
	skeleton.add_child(solver)
	solver.target_node = solver.get_path_to(targets.get_node(label + "Target"))
	solver.override_tip_basis = false
	solver.use_magnet = true
	solver.max_iterations = 40
	_solvers[label] = solver


func _physics_process(delta: float) -> void:
	# The procedural gait and explicit FK/IK controls must not write the same legs.
	gait_enabled = not (fk_enabled or left_leg_ik or right_leg_ik)
	if _was_gait_enabled and not gait_enabled:
		for bone_name in ["Tight.L", "Leg.L", "Foot.L", "Tight.R", "Leg.R", "Foot.R"]:
			var bone := skeleton.find_bone(bone_name)
			if bone >= 0:
				skeleton.set_bone_pose_rotation(bone, _rest_rotations[bone])
	_was_gait_enabled = gait_enabled
	if fk_enabled:
		for control in fk_controls.get_children():
			var bone := skeleton.find_bone(control.name)
			if bone >= 0:
				skeleton.set_bone_pose_rotation(bone, _rest_rotations[bone] * control.quaternion)
		var root := skeleton.find_bone("Root")
		skeleton.set_bone_pose_position(root, _root_rest_position + fk_controls.get_node("Root").position)
	elif _was_fk_enabled:
		for bone in skeleton.get_bone_count():
			skeleton.set_bone_pose_rotation(bone, _rest_rotations[bone])
		skeleton.set_bone_pose_position(skeleton.find_bone("Root"), _root_rest_position)
	_was_fk_enabled = fk_enabled
	_update_solver("LeftLeg", left_leg_ik)
	_update_solver("RightLeg", right_leg_ik)
	_update_solver("LeftArm", left_arm_ik)
	_update_solver("RightArm", right_arm_ik)
	if gait_enabled:
		_update_gait(delta)


func _update_solver(label: String, enabled: bool) -> void:
	var solver: SkeletonIK3D = _solvers[label]
	if enabled:
		var pole: Node3D = targets.get_node(label + "Pole")
		solver.magnet = skeleton.to_local(pole.global_position)
		if not solver.is_running():
			solver.start()
	elif solver.is_running():
		solver.stop()


func _update_gait(delta: float) -> void:
	var speed := Vector2(movement_velocity.x, movement_velocity.z).length()
	var moving := speed > 0.05
	_blend = move_toward(_blend, 1.0 if moving else 0.0, blend_speed * delta)
	var run_amount := clampf((speed - walk_speed) / maxf(run_speed - walk_speed, 0.01), 0.0, 1.0)
	var stride := maxf(lerpf(walk_stride_length, run_stride_length, run_amount), 0.01)
	if moving:
		_phase = fposmod(_phase + speed / stride * TAU * delta, TAU)
	for i in _legs.size():
		_animate_leg(_legs[i], _phase + i * PI, run_amount)


func _animate_leg(leg: Dictionary, phase: float, run_amount: float) -> void:
	# The imported leg bones point down their local +Y axis. Local +X bends
	# the knee towards the rear; keep each adjustment relative to its rest pose.
	var swing := sin(phase)
	var lift := maxf(0.0, -swing)
	var thigh_angle := swing * lerpf(0.35, 0.60, run_amount) * _blend
	var shin_angle := lift * lerpf(0.65, 1.15, run_amount) * _blend
	var foot_angle := -(thigh_angle + shin_angle) * 0.7
	skeleton.set_bone_pose_rotation(leg.thigh, leg.thigh_rest * Quaternion(Vector3.RIGHT, thigh_angle))
	skeleton.set_bone_pose_rotation(leg.shin, leg.shin_rest * Quaternion(Vector3.RIGHT, shin_angle))
	skeleton.set_bone_pose_rotation(leg.foot, leg.foot_rest * Quaternion(Vector3.RIGHT, foot_angle))
