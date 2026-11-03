extends Node3D
## Isolated ENet/LAN sandbox. Nothing here is an autoload or used by the main scene.

const PLAYER := preload("res://debug/multiplayer_player.tscn")
const SCENE_PATH := "res://debug/multiplayer_debug.tscn"
const MAX_PLAYERS := 4

@export_range(1024, 65535) var default_port := 7000
@export_range(2.0, 30.0, 0.5) var connection_timeout := 8.0

@onready var players: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $Spawner
@onready var overview: Camera3D = $Overview

var address_field: LineEdit
var port_field: SpinBox
var status_label: Label
var peers_label: Label
var host_button: Button
var join_button: Button
var quick_button: Button
var disconnect_button: Button
var timeout: Timer
var slots: Dictionary = {}
var connected := false


func _ready() -> void:
	get_window().size = Vector2i(1000, 700)
	get_window().title = "Sense Overdrive | Multiplayer debug"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	spawner.spawn_function = _spawn_player
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected_to_server)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_disconnected)
	players.child_entered_tree.connect(_refresh_peers.unbind(1))
	players.child_exiting_tree.connect(_refresh_peers.unbind(1))
	timeout = Timer.new()
	timeout.one_shot = true
	add_child(timeout)
	timeout.timeout.connect(_connection_failed)
	_build_ui()
	_build_landmarks()
	_read_arguments()


func start_host() -> bool:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(int(port_field.value), MAX_PLAYERS - 1)
	if error != OK:
		_set_status("Não foi possível criar a sala: %s. Tente outra porta." % error_string(error))
		return false
	multiplayer.multiplayer_peer = peer
	connected = true
	_set_active(true)
	get_window().title = "Sense Overdrive | HOST | porta %d" % int(port_field.value)
	_set_status("HOST ativo na porta %d. Aguardando jogadores." % int(port_field.value))
	_add_player(1)
	return true


func join_host() -> void:
	var address := address_field.text.strip_edges()
	if address.is_empty():
		_set_status("Preencha o IP do host. No mesmo PC, use 127.0.0.1.")
		return
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, int(port_field.value))
	if error != OK:
		_set_status("Não foi possível conectar: %s." % error_string(error))
		return
	multiplayer.multiplayer_peer = peer
	_set_active(true)
	_set_status("Conectando a %s:%d..." % [address, int(port_field.value)])
	timeout.start(connection_timeout)


func disconnect_session(message := "Desconectado. Você pode criar ou entrar em outra sala.") -> void:
	timeout.stop()
	connected = false
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	for player in players.get_children():
		players.remove_child(player)
		player.queue_free()
	slots.clear()
	overview.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_active(false)
	_set_status(message)
	get_window().title = "Sense Overdrive | Multiplayer debug"
	_refresh_peers()


func test_two_windows() -> void:
	if not start_host():
		return
	var arguments := PackedStringArray([
		"--path", ProjectSettings.globalize_path("res://"), SCENE_PATH,
		"--", "--mp-join=127.0.0.1", "--mp-port=%d" % int(port_field.value),
	])
	var pid := OS.create_instance(arguments)
	if pid == -1:
		_set_status("Sala criada. Abra outra instância com F6 e use Entrar (127.0.0.1).")
	else:
		_set_status("HOST ativo. Segunda janela aberta; aguarde a conexão. Use Alt+Tab para alternar.")


func _add_player(peer_id: int) -> void:
	var slot := 0
	while slot in slots.values():
		slot += 1
	slots[peer_id] = slot
	spawner.spawn({"peer_id": peer_id, "slot": slot})
	_refresh_peers()


func _spawn_player(data: Dictionary) -> Node:
	var player := PLAYER.instantiate()
	player.name = str(data.peer_id)
	player.set_multiplayer_authority(int(data.peer_id))
	var slot := int(data.slot)
	player.position = Vector3((slot % 2) * 4.0 - 2.0, 0.1, floori(slot / 2.0) * 4.0)
	player.spawn_position = player.position
	return player


func _peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		_add_player(peer_id)


func _peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server():
		var player := players.get_node_or_null(str(peer_id))
		if player != null:
			player.queue_free()
		slots.erase(peer_id)
	_refresh_peers()


func _connected_to_server() -> void:
	timeout.stop()
	connected = true
	get_window().title = "Sense Overdrive | CLIENTE %d" % multiplayer.get_unique_id()
	_set_status("Conectado a %s:%d. Clique na arena para jogar." % [address_field.text, int(port_field.value)])
	_refresh_peers()


func _connection_failed() -> void:
	disconnect_session("Falha na conexão. Confira IP, porta e se o host está aberto; tente novamente.")


func _server_disconnected() -> void:
	disconnect_session("O host encerrou a sala. Você pode conectar novamente.")


func _reset_local_player() -> void:
	if connected:
		var player := players.get_node_or_null(str(multiplayer.get_unique_id()))
		if player != null:
			player.reset_to_spawn()


func _set_active(active: bool) -> void:
	host_button.disabled = active
	join_button.disabled = active
	quick_button.disabled = active
	disconnect_button.disabled = not active
	address_field.editable = not active
	port_field.editable = not active


func _set_status(message: String) -> void:
	status_label.text = message
	print("[MultiplayerDebug] ", message)


func _refresh_peers() -> void:
	# Tree signals fire before a child has finished entering/leaving.
	_update_peers_label.call_deferred()


func _update_peers_label() -> void:
	var ids: Array[String] = []
	for player in players.get_children():
		if not player.is_queued_for_deletion():
			ids.append(str(player.name))
	peers_label.text = "Jogadores: %d/%d  |  IDs: %s" % [ids.size(), MAX_PLAYERS, ", ".join(ids)]


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size.x = 700
	layer.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	_label(column, "MULTIPLAYER LOCAL / LAN · DEBUG", 20)
	_label(column, "Mesmo PC: Testar 2 janelas. Em rede: Criar sala + Entrar pelo IP do host.")
	var row := HBoxContainer.new()
	column.add_child(row)
	_label(row, "IP:")
	address_field = LineEdit.new()
	address_field.text = "127.0.0.1"
	address_field.custom_minimum_size.x = 190
	row.add_child(address_field)
	_label(row, "Porta UDP:")
	port_field = SpinBox.new()
	port_field.min_value = 1024
	port_field.max_value = 65535
	port_field.value = default_port
	row.add_child(port_field)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	quick_button = _button(buttons, "Testar 2 janelas", test_two_windows)
	host_button = _button(buttons, "Criar sala", start_host)
	join_button = _button(buttons, "Entrar", join_host)
	disconnect_button = _button(buttons, "Desconectar", disconnect_session)
	_button(buttons, "Repor posição", _reset_local_player)
	status_label = _label(column, "Pronto. Teste isolado para até 4 jogadores.")
	status_label.custom_minimum_size.x = 690
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	peers_label = _label(column, "Jogadores: 0/4")
	_label(column, "Seu IP na rede: " + _lan_addresses())
	_label(column, "Clique na arena: capturar mouse · Esc: liberar · WASD/setas: mover · Shift: correr")
	_label(column, "Alt+Tab: trocar janela · Repor posição: voltar ao ponto inicial")
	_set_active(false)


func _label(parent: Node, text: String, size := 14) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _lan_addresses() -> String:
	var addresses: Array[String] = []
	for address in IP.get_local_addresses():
		if ":" not in address and not address.begins_with("127."):
			addresses.append(address)
	return ", ".join(addresses) if not addresses.is_empty() else "indisponível; mesmo PC: 127.0.0.1"


func _build_landmarks() -> void:
	# Simple scale/direction references, independent of imported level assets.
	for i in 4:
		var marker := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1, 3, 1)
		marker.mesh = mesh
		marker.position = Vector3(-8 if i % 2 == 0 else 8, 1.5, -8 if i < 2 else 8)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.25, 0.7, 0.85) if i < 2 else Color(0.9, 0.45, 0.2)
		marker.material_override = material
		add_child(marker)


func _read_arguments() -> void:
	var host_requested := false
	var join_address := ""
	for argument in OS.get_cmdline_user_args():
		if argument == "--mp-host":
			host_requested = true
		elif argument.begins_with("--mp-join="):
			join_address = argument.trim_prefix("--mp-join=")
		elif argument.begins_with("--mp-port="):
			port_field.value = argument.trim_prefix("--mp-port=").to_int()
	if host_requested:
		start_host()
	elif not join_address.is_empty():
		address_field.text = join_address
		join_host()


func _exit_tree() -> void:
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
