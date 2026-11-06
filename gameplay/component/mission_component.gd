extends Node3D
## A single mission component. The host serializes claims; peers follow the carrier locally.

## Distância máxima, em metros, entre o jogador e o componente para pegá-lo.
@export_range(0.2, 6.0, 0.1, "suffix:m") var pickup_range := 2.6
## Distância à frente do portador para procurar chão ao largar, em metros.
@export_range(0.2, 3.0, 0.1, "suffix:m") var drop_distance := 0.8
## Posição do núcleo em relação ao jogador enquanto carregado, em metros (−Z é frente).
@export var carry_offset := Vector3(0.20, 0.60, -0.34)
## Nó que contém os jogadores, nomeados pelo ID do participante.
@export var players_path: NodePath
## Personagem que usa E para pegar/largar no modo solo. Deixe vazio na arena de rede.
@export var solo_player_path: NodePath

@onready var players: Node3D = get_node_or_null(players_path)
@onready var solo_player: CharacterBody3D = get_node_or_null(solo_player_path)
@onready var home := global_position
var carrier_id := 0
var rest_position: Vector3


func _ready() -> void:
	rest_position = home
	if DisplayServer.get_name() != "headless":
		$Pulse.play()


func _process(_delta: float) -> void:
	if $Pulse.playing:
		var time: float = $Pulse.get_playback_position()
		var beat := _beat(time - 0.03) + 0.48 * _beat(time - 0.23)
		$Membrane.set_instance_shader_parameter("beat", beat)
		$CoreLight.light_energy = 0.55 + beat * 0.85
	if solo_player:
		$Prompt.visible = carrier_id == 1 or can_pick_up(1)
		$Prompt.text = "E · Largar" if carrier_id == 1 else "E · Pegar"
	if carrier_id == 0:
		return
	var player := _player(carrier_id)
	if player:
		global_position = player.global_position + player.camera_yaw.global_basis * carry_offset


func _beat(elapsed: float) -> float:
	return 0.0 if elapsed < 0.0 else minf(elapsed / 0.016, 1.0) * exp(-13.0 * elapsed)


func _player(peer_id: int) -> Node3D:
	if solo_player:
		return solo_player if peer_id == 1 else null
	if not players:
		return null
	return players.get_node_or_null(str(peer_id)) as Node3D


func _unhandled_key_input(event: InputEvent) -> void:
	if solo_player and event.keycode == KEY_E and event.is_pressed() and not event.is_echo():
		interact()


## Consultar na autoridade antes de aceitar um disparo manual.
func can_use_manual_weapon(peer_id: int) -> bool:
	return peer_id != carrier_id


func can_pick_up(peer_id: int) -> bool:
	var player := _player(peer_id)
	return carrier_id == 0 and player != null and player.global_position.distance_to(rest_position) <= pickup_range


func interact() -> void:
	var peer_id := multiplayer.get_unique_id()
	var dropping := carrier_id == peer_id
	if multiplayer.is_server():
		_interact(peer_id, dropping)
	else:
		request_interaction.rpc_id(1, dropping)


@rpc("any_peer", "call_remote", "reliable")
func request_interaction(dropping: bool) -> void:
	if multiplayer.is_server():
		_interact(multiplayer.get_remote_sender_id(), dropping)


func _interact(peer_id: int, dropping: bool) -> void:
	if dropping:
		force_drop(peer_id)
	elif can_pick_up(peer_id):
		_publish(peer_id, rest_position)


## Chamar no host antes de remover o portador ou aplicar os efeitos do Synth.
func force_drop(peer_id: int) -> void:
	if not multiplayer.is_server() or carrier_id == 0 or peer_id != carrier_id:
		return
	var player := _player(peer_id)
	var target := home
	if player:
		var forward_offset := Vector3(carry_offset.x, 0.0, -drop_distance)
		var ahead: Vector3 = player.global_position + player.camera_yaw.global_basis * forward_offset
		var ray := PhysicsRayQueryParameters3D.create(ahead + Vector3.UP, ahead + Vector3.DOWN * 4.0, 1)
		ray.exclude = [player.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty() and hit.normal.y > 0.7:
			target = hit.position + Vector3.UP * 0.33
	_publish(0, target)


func reset_component() -> void:
	if multiplayer.is_server():
		_publish(0, home)


func sync_to(peer_id: int) -> void:
	apply_state.rpc_id(peer_id, carrier_id, rest_position)


func _publish(new_carrier: int, ground: Vector3) -> void:
	apply_state(new_carrier, ground)
	if multiplayer.get_peers().size() > 0:
		apply_state.rpc(new_carrier, ground)


@rpc("authority", "call_remote", "reliable")
func apply_state(new_carrier: int, ground: Vector3) -> void:
	carrier_id = new_carrier
	rest_position = ground
	if carrier_id == 0:
		global_position = ground
