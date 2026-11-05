extends RefCounted
## Presentation primitives for the selected Figma overlay. Coordinates are window pixels.
## Native ImGui items retain focus, keyboard navigation, clipping and input ownership.

const TEXT := Color("f0f2f8")
const MUTED := Color("a3adc1")
const ACCENT := Color("baa6ff")
const BORDER := Color("353d50")
const ACTIVE := Color("302744")
const SURFACE := Color("222836")
const ICON_PATH := "res://addons/dev_assistance/icons/figma/"

var gui: Object
var fonts: PackedInt64Array
var icons: Dictionary = {}


func _init(api: Object) -> void:
	gui = api
	for key in ["drag", "hide", "pin", "collapse", "reset", "chevron"]:
		icons[key] = load(ICON_PATH + key + ".svg")


func configure() -> void:
	gui.GetIO().ConfigFlags |= 1 # NavEnableKeyboard
	var style: Object = gui.GetStyle()
	style.WindowRounding = 14.0
	style.WindowPadding = Vector2.ZERO
	style.WindowBorderSize = 1.0
	style.FrameRounding = 6.0
	style.FrameBorderSize = 1.0
	style.PopupRounding = 8.0
	style.FramePadding = Vector2(8, 7)
	style.ItemSpacing = Vector2(8, 8)
	style.ScrollbarSize = 6.0
	style.ScrollbarRounding = 3.0
	var colors: PackedColorArray = style._GetColors()
	for entry in [[0, TEXT], [1, MUTED], [2, Color("151923")],
		[3, Color.TRANSPARENT], [4, Color("151923")], [5, BORDER],
		[7, Color("10131c")], [8, SURFACE], [9, ACTIVE],
		[14, Color.TRANSPARENT], [15, BORDER], [16, MUTED], [17, ACCENT],
		[18, ACCENT], [19, ACCENT], [20, ACCENT],
		[21, SURFACE], [22, Color("343044")], [23, ACTIVE],
		[24, ACTIVE], [25, Color("343044")], [26, ACTIVE]]:
		colors[entry[0]] = entry[1]
	style._SetColors(colors)


func refresh_fonts() -> void:
	# Fetch each frame: the extension rebuilds the atlas when its scale changes.
	fonts = Engine.get_singleton("ImGuiGD").GetFontPtrs()


func text(at: Vector2, value: String, size := 13.0, color := TEXT, font := 0) -> void:
	# stb_truetype sizes by ascent/descent; Figma uses em units (font hhea / unitsPerEm).
	var pointer: int = fonts[font] if fonts.size() > font else gui.GetFont()
	gui.ImDrawList_AddTextImFontPtr(gui.GetWindowDrawList(), pointer, size * (1.3 if font == 2 else 1.364),
		gui.GetWindowPos() + at - Vector2(0, size * 0.18) - Vector2(0, gui.GetScrollY()), color, value)


func box(at: Vector2, size: Vector2, color: Color, radius := 6.0, border := Color.TRANSPARENT) -> void:
	var p: Vector2 = gui.GetWindowPos() + at - Vector2(0, gui.GetScrollY())
	gui.ImDrawList_AddRectFilledEx(gui.GetWindowDrawList(), p, p + size, color, radius)
	if border.a > 0.0:
		gui.ImDrawList_AddRectEx(gui.GetWindowDrawList(), p, p + size, border, radius)


func circle(at: Vector2, radius: float, color: Color) -> void:
	gui.ImDrawList_AddCircleFilled(gui.GetWindowDrawList(),
		gui.GetWindowPos() + at - Vector2(0, gui.GetScrollY()), radius, color, 24)


func icon(at: Vector2, texture: Texture2D) -> void:
	if texture == null:
		return
	var p: Vector2 = gui.GetWindowPos() + at - Vector2(0, gui.GetScrollY())
	gui.ImDrawList_AddImage(gui.GetWindowDrawList(), texture, p, p + texture.get_size())


func hit(id: String, at: Vector2, size: Vector2, tooltip := "") -> bool:
	gui.SetCursorPos(at)
	var clicked: bool = gui.InvisibleButton(id, size, 8) # EnableNav
	if gui.IsItemHovered() and not tooltip.is_empty():
		self.tooltip(tooltip)
	return clicked


func icon_button(id: String, at: Vector2, key: String, tooltip: String, selected := false) -> bool:
	var tex: Texture2D = icons[key]
	var clicked := hit(id, at - Vector2(5, 5), tex.get_size() + Vector2(10, 10), tooltip)
	if gui.IsItemHovered() or gui.IsItemFocused() or selected:
		box(at - Vector2(4, 4), tex.get_size() + Vector2(8, 8), ACTIVE, 5)
	icon(at, tex)
	return clicked


func button(id: String, at: Vector2, size: Vector2, label: String, accent := false) -> bool:
	var clicked := hit(id, at, size)
	box(at, size, Color("343044") if gui.IsItemHovered() else (ACTIVE if accent else SURFACE), 7)
	text(at + Vector2(12, 7), label, 12, ACCENT if accent else TEXT, 1 if accent else 0)
	return clicked


func shadow(position: Vector2, size: Vector2, alpha: float) -> void:
	for spread in range(12, 0, -3):
		gui.ImDrawList_AddRectFilledEx(gui.GetBackgroundDrawList(),
			position + Vector2(-spread, 8 - spread), position + size + Vector2(spread, 8 + spread),
			Color(0, 0, 0, alpha * 0.035), 14.0 + spread)


func tooltip(description: String) -> void:
	gui.PushStyleVarImVec2(2, Vector2(8, 6))
	gui.SetTooltip(description)
	gui.PopStyleVar()


func begin_popup(id: String) -> bool:
	gui.PushStyleVarImVec2(2, Vector2(12, 10))
	var open: bool = gui.BeginPopup(id)
	gui.PopStyleVar()
	return open
