extends CanvasLayer
## One instance per world viewport, owned by the scene, never by a player/camera.
## Layer 1 processes the 3D image. Put HUD/menu CanvasLayers at layer 10 or above.

@export var enabled := true:
	set(value):
		enabled = value
		_sync_settings()
@export var pixelization_enabled := true:
	set(value):
		pixelization_enabled = value
		_sync_settings()
## Reference vertical resolution; horizontal resolution follows the viewport aspect.
@export_range(90, 2160, 1) var virtual_height := 540:
	set(value):
		virtual_height = clampi(value, 90, 2160)
		_sync_settings()
@export var posterization_enabled := true:
	set(value):
		posterization_enabled = value
		_sync_settings()
@export_range(2, 256, 1) var color_levels := 32:
	set(value):
		color_levels = clampi(value, 2, 256)
		_sync_settings()
@export var contrast_enabled := true:
	set(value):
		contrast_enabled = value
		_sync_settings()
@export_range(0.0, 2.0, 0.01) var contrast := 1.0:
	set(value):
		contrast = clampf(value, 0.0, 2.0)
		_sync_settings()
@export var saturation_enabled := true:
	set(value):
		saturation_enabled = value
		_sync_settings()
@export_range(0.0, 2.0, 0.01) var saturation := 1.0:
	set(value):
		saturation = clampf(value, 0.0, 2.0)
		_sync_settings()

var _material: ShaderMaterial


func _ready() -> void:
	# Never share uniforms with another instance, including a SubViewport.
	_material = $Overlay.material.duplicate() as ShaderMaterial
	$Overlay.material = _material
	_sync_settings()


func _sync_settings() -> void:
	if _material == null:
		return
	$Overlay.visible = enabled
	for property in ["pixelization_enabled", "virtual_height", "posterization_enabled",
			"color_levels", "contrast_enabled", "contrast", "saturation_enabled", "saturation"]:
		_material.set_shader_parameter(property, get(property))
