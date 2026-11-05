extends Node
## Isolated UI fixture, not a LocalPlayer/Network implementation. Open its scene with F6.

## Demonstration slider, in m/s. Does not change a game character.
@export_range(0, 10, 0.01) var speed := 5.0
## Demonstration slider, in m/s². Does not change project gravity.
@export_range(0, 15, 0.01) var gravity := 9.8
## Demonstration switch. Does not enable input on a game character.
@export var local_input := false

var ui: DevAssistance
var _elapsed := 0.0


func _ready() -> void:
	get_window().size = Vector2i(900, 680)
	get_window().title = "DevAssistance · Figma / demonstração de interface"
	ui = DevAssistance.new()
	ui.name = "DevAssistance"
	add_child(ui)
	ui.preset_path = "user://devassistance/design_preview.cfg"
	ui.set("_presets", ConfigFile.new())
	ui.get("_presets").load(ui.preset_path)
	ui.register_context("preview.player", "LocalPlayer", load(DevAssistance.FigmaSkin.ICON_PATH + "player.svg"), self, [
		{"property": "speed", "label": "Velocidade", "description": "Valor fictício para comparar o controle ao Figma.", "min": 0.0, "max": 10.0, "unit": "m/s", "group": "Movimento"},
		{"property": "gravity", "label": "Gravidade", "description": "Valor fictício para comparar o controle ao Figma.", "min": 0.0, "max": 15.0, "unit": "m/s²", "group": "Movimento"},
		{"property": "local_input", "label": "Comandos locais", "description": "Chave de demonstração; não controla um personagem real.", "caption": "Suspensos com o painel aberto", "group": "Movimento"},
	])
	ui.contexts["preview.player"].heading_icon = load(DevAssistance.FigmaSkin.ICON_PATH + "player_heading.svg")
	ui.contexts["preview.player"].groups = ["Movimento", "Sistemas"]
	ui.contexts["preview.player"].open[0] = true
	for entry in [["Visual", "visual"], ["Experimento", "experiment"], ["Profiler", "profiler"],
		["SceneBrowser", "scene_browser"], ["ScreenSpace", "screen_space"], ["Network", "network"], ["Navigator", "navigator"]]:
		ui.register_context("preview." + entry[1], entry[0], load(DevAssistance.FigmaSkin.ICON_PATH + entry[1] + ".svg"), self, [], [
			{"label": "Apenas demonstração de layout", "description": "Este contexto não implementa um sistema do jogo.", "callback": func(): pass},
		])
	var background := ColorRect.new()
	background.color = Color("1d1d1d")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var label := Label.new()
	label.name = "PreviewNotice"
	label.position = Vector2(550, 28)
	label.text = "DEMONSTRAÇÃO VISUAL\nValores fictícios · F6 nesta cena\n\nCtrl+Alt+D: ocultar / abrir\nArraste o cabeçalho e o painel\nDuplo clique no cabeçalho: reorganizar\n\nTeste real: visual_debug.tscn"
	add_child(label)


func _process(delta: float) -> void:
	_elapsed += delta
	$PreviewNotice.modulate.a = 0.7 + sin(_elapsed * 2.0) * 0.2
