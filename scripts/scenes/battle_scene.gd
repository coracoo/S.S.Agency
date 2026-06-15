extends Node2D

class OverlayLayer:
	extends Node2D
	var battle: Node = null

	func _draw() -> void:
		if battle != null:
			battle._draw_overlay()

class CardArtLayer:
	extends Control
	var card_id: String = ""
	var accent := Color(0.7, 0.6, 0.3, 1.0)
	var glow := Color(1.0, 0.84, 0.47, 1.0)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w = size.x
		var h = size.y
		draw_rect(Rect2(Vector2.ZERO, size), Color(accent.r * 0.18, accent.g * 0.18, accent.b * 0.18, 0.20), true)
		for i in range(3):
			var y = 10.0 + i * 16.0
			draw_line(Vector2(8, y), Vector2(w - 8, y + 9), Color(accent.r, accent.g, accent.b, 0.10), 1.0)
		match card_id:
			"rinne_slash":
				_draw_blade(Vector2(16, h - 12), Vector2(w - 12, 12), 3.0)
				draw_arc(Vector2(w * 0.48, h * 0.48), 22, -1.1, 0.9, 24, Color(0.72, 0.90, 1.0, 0.62), 2.0)
			"rinne_cleave":
				_draw_blade(Vector2(12, h - 10), Vector2(w - 10, 14), 4.0)
				_draw_blade(Vector2(w - 14, h - 12), Vector2(14, 14), 2.5)
				draw_line(Vector2(10, h * 0.5), Vector2(w - 10, h * 0.5), Color(glow.r, glow.g, glow.b, 0.55), 2.0)
			"mint_shot":
				draw_line(Vector2(10, h * 0.55), Vector2(w - 10, h * 0.30), Color(0.75, 1.0, 0.70, 0.78), 3.0)
				draw_circle(Vector2(w - 14, h * 0.30), 5, glow)
				_draw_leaf(Vector2(20, h * 0.35), 12.0)
			"mint_snipe":
				var c = Vector2(w * 0.52, h * 0.45)
				for r in [10.0, 20.0, 28.0]:
					draw_arc(c, r, 0, TAU, 40, Color(0.70, 1.0, 0.80, 0.55), 1.5)
				draw_line(Vector2(c.x - 30, c.y), Vector2(c.x + 30, c.y), glow, 1.5)
				draw_line(Vector2(c.x, c.y - 30), Vector2(c.x, c.y + 30), glow, 1.5)
			"homura_flare":
				var c = Vector2(w * 0.5, h * 0.50)
				for i in range(10):
					var a = TAU * float(i) / 10.0
					draw_line(c, c + Vector2(cos(a), sin(a)) * (18 + (i % 2) * 10), Color(1.0, 0.35, 0.10, 0.72), 2.0)
				draw_circle(c, 13, Color(1.0, 0.72, 0.18, 0.78))
			"homura_ignite":
				_draw_flame(Vector2(w * 0.50, h * 0.52), 30.0)
				draw_line(Vector2(w * 0.30, h * 0.74), Vector2(w * 0.70, h * 0.70), Color(1.0, 0.84, 0.42, 0.62), 2.0)
			"zhongkui_fist":
				var c = Vector2(w * 0.50, h * 0.50)
				draw_circle(c, 20, Color(0.72, 0.36, 0.20, 0.66))
				for i in range(4):
					draw_circle(c + Vector2(-15 + i * 10, -14), 6, Color(0.96, 0.76, 0.46, 0.70))
				draw_rect(Rect2(c + Vector2(-16, -2), Vector2(32, 18)), Color(0.52, 0.22, 0.14, 0.70), true)
			"zhongkui_capture":
				for i in range(4):
					var x = 14 + i * 13
					draw_arc(Vector2(x, h * 0.48), 10, -0.9, 2.2, 18, Color(0.76, 0.90, 1.0, 0.68), 2.2)
				draw_line(Vector2(9, h * 0.60), Vector2(w - 9, h * 0.36), glow, 2.0)
			"zhongkui_judge":
				draw_rect(Rect2(Vector2(w * 0.40, h * 0.18), Vector2(18, 36)), Color(0.82, 0.62, 0.28, 0.78), true)
				draw_rect(Rect2(Vector2(w * 0.24, h * 0.48), Vector2(42, 15)), Color(0.55, 0.20, 0.16, 0.78), true)
				draw_line(Vector2(w * 0.50, h * 0.64), Vector2(w * 0.66, h * 0.86), glow, 3.0)
			"item_ignite":
				draw_rect(Rect2(Vector2(w * 0.46, h * 0.36), Vector2(9, 36)), Color(0.72, 0.42, 0.18, 0.78), true)
				_draw_flame(Vector2(w * 0.50, h * 0.30), 18.0)
			"item_water_splash":
				for i in range(5):
					var c2 = Vector2(16 + i * 10, h * 0.45 + sin(i) * 12)
					draw_circle(c2, 5 + i % 2, Color(0.42, 0.78, 1.0, 0.72))
				draw_arc(Vector2(w * 0.50, h * 0.64), 26, 3.3, 6.1, 30, Color(0.50, 0.85, 1.0, 0.62), 2.0)
			"item_throw_rice":
				draw_rect(Rect2(Vector2(w * 0.30, h * 0.42), Vector2(30, 25)), Color(0.84, 0.76, 0.48, 0.70), true)
				for i in range(15):
					draw_circle(Vector2(10 + (i * 11) % int(w - 18), 18 + (i * 17) % int(h - 30)), 1.8, Color(1.0, 0.95, 0.70, 0.85))
			"item_place_talisman":
				var paper = PackedVector2Array([Vector2(w * 0.38, 10), Vector2(w * 0.65, 15), Vector2(w * 0.58, h - 10), Vector2(w * 0.32, h - 16)])
				draw_colored_polygon(paper, Color(0.95, 0.82, 0.45, 0.76))
				draw_line(Vector2(w * 0.38, h * 0.40), Vector2(w * 0.60, h * 0.46), Color(0.80, 0.10, 0.08, 0.85), 2.0)
				draw_line(Vector2(w * 0.40, h * 0.58), Vector2(w * 0.56, h * 0.64), Color(0.80, 0.10, 0.08, 0.85), 2.0)
			"item_ring_chime":
				var c3 = Vector2(w * 0.50, h * 0.52)
				draw_arc(c3, 18, PI, TAU, 24, Color(0.95, 0.72, 0.25, 0.84), 4.0)
				draw_circle(c3 + Vector2(0, 12), 5, glow)
				draw_arc(c3, 30, -0.5, 0.5, 16, Color(1.0, 0.88, 0.36, 0.38), 2.0)
				draw_arc(c3, 38, -0.5, 0.5, 16, Color(1.0, 0.88, 0.36, 0.24), 1.5)
			"env_push_strike":
				draw_rect(Rect2(Vector2(12, h * 0.44), Vector2(28, 18)), Color(0.74, 0.82, 0.95, 0.58), true)
				draw_polygon(PackedVector2Array([Vector2(w - 10, h * 0.53), Vector2(w - 30, h * 0.34), Vector2(w - 30, h * 0.72)]), PackedColorArray([glow, glow, glow]))
				draw_line(Vector2(18, h * 0.53), Vector2(w - 24, h * 0.53), glow, 4.0)
			_:
				draw_circle(Vector2(w * 0.5, h * 0.5), 22, Color(accent.r, accent.g, accent.b, 0.50))

	func _draw_blade(a: Vector2, b: Vector2, width: float) -> void:
		draw_line(a, b, Color(0.92, 0.95, 1.0, 0.82), width)
		draw_line(a + Vector2(3, 1), b + Vector2(3, 1), Color(accent.r, accent.g, accent.b, 0.42), 1.4)

	func _draw_leaf(c: Vector2, r: float) -> void:
		draw_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r * 0.7, 0)]), PackedColorArray([Color(0.55, 1.0, 0.55, 0.7), Color(0.45, 0.85, 0.42, 0.7), Color(0.28, 0.62, 0.32, 0.7), Color(0.42, 0.8, 0.38, 0.7)]))

	func _draw_flame(c: Vector2, r: float) -> void:
		draw_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.48, -r * 0.10), c + Vector2(r * 0.28, r * 0.55), c + Vector2(-r * 0.36, r * 0.50), c + Vector2(-r * 0.52, -r * 0.05)]), PackedColorArray([Color(1.0, 0.85, 0.24, 0.85), Color(1.0, 0.32, 0.08, 0.82), Color(0.80, 0.05, 0.04, 0.74), Color(1.0, 0.45, 0.08, 0.78), Color(1.0, 0.24, 0.06, 0.76)]))

const TILE_W = 128
const TILE_H = 64
const NoiseSystemScript = preload("res://scripts/core/noise_system.gd")
const SpiritSystemScript = preload("res://scripts/core/spirit_system.gd")

const UI_BG := Color(0.045, 0.060, 0.078, 0.58)
const UI_BG_DEEP := Color(0.040, 0.052, 0.070, 0.66)
const UI_GOLD_DARK := Color(0.36, 0.31, 0.19, 0.75)
const UI_GOLD := Color(0.70, 0.59, 0.31, 0.78)
const UI_GOLD_BRIGHT := Color(1.0, 0.84, 0.47, 1.0)
const UI_TEXT := Color(0.94, 0.94, 0.96, 1.0)
const UI_TEXT_WARM := Color(0.88, 0.85, 0.82, 1.0)
const UI_TEXT_MUTED := Color(0.69, 0.66, 0.72, 1.0)
const UI_HP := Color(0.86, 0.24, 0.24, 1.0)
const UI_MP := Color(0.24, 0.55, 0.86, 1.0)
const UI_AP := Color(0.31, 0.78, 0.31, 1.0)

var _portrait_tex: Texture2D = null
var _portrait_atlas: AtlasTexture = null
var _portrait_textures: Dictionary = {}
var _portrait_icon_textures: Dictionary = {}
var _sprite_sheets: Dictionary = {}
var _bg_texture: Texture2D = null
var _ui_textures: Dictionary = {}
var _card_face_textures: Dictionary = {}

const UI_TEXTURE_FILES := {
	"bottom_hand": "res://assets/ui/generated/ui_bottom_hand_panel.png",
	"status_panel": "res://assets/ui/generated/ui_status_panel.png",
	"info_panel": "res://assets/ui/generated/ui_info_panel.png",
	"card_frame": "res://assets/ui/generated/ui_card_frame.png",
	"tab_button": "res://assets/ui/generated/ui_tab_button_frame.png",
	"diamond_button": "res://assets/ui/generated/ui_diamond_button.png",
	"top_button": "res://assets/ui/generated/ui_top_button_frame.png",
	"skill_icon_slash": "res://assets/ui/generated/skill_icon_slash.png",
	"skill_icon_soul": "res://assets/ui/generated/skill_icon_soul.png",
	"skill_icon_talisman": "res://assets/ui/generated/skill_icon_talisman.png",
	"skill_icon_bell": "res://assets/ui/generated/skill_icon_bell.png",
	"skill_icon_fire": "res://assets/ui/generated/skill_icon_fire.png",
	"skill_icon_rice": "res://assets/ui/generated/skill_icon_rice.png",
	"skill_icon_water": "res://assets/ui/generated/skill_icon_water.png",
	"skill_icon_bind": "res://assets/ui/generated/skill_icon_bind.png",
	"action_wait": "res://assets/ui/generated/actions/action_wait.png",
	"action_spell": "res://assets/ui/generated/actions/action_spell.png",
	"action_item": "res://assets/ui/generated/actions/action_item.png",
	"card_frame_v2": "res://assets/ui/mockup_v2/card_slot_frame.png",
	"action_mode_v2": "res://assets/ui/mockup_v2/action_mode_frame.png",
	"wait_button_v2": "res://assets/ui/mockup_v2/wait_button_frame.png",
}

const UI_PATCH_MARGINS := {
	"bottom_hand": Vector4i(100, 78, 100, 78),
	"status_panel": Vector4i(58, 88, 58, 88),
	"info_panel": Vector4i(58, 78, 58, 82),
	"card_frame": Vector4i(58, 78, 58, 82),
	"tab_button": Vector4i(76, 32, 76, 32),
	"diamond_button": Vector4i(72, 72, 72, 72),
	"top_button": Vector4i(34, 34, 34, 34),
	"card_frame_v2": Vector4i(20, 26, 20, 26),
	"action_mode_v2": Vector4i(38, 28, 38, 28),
	"wait_button_v2": Vector4i(42, 42, 42, 42),
}

const CHINESE_FONT_REGULAR := "res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf"
const CHINESE_FONT_MEDIUM := "res://assets/fonts/Alibaba-PuHuiTi-Medium.ttf"
const CHINESE_FONT_BOLD := "res://assets/fonts/Alibaba-PuHuiTi-Bold.ttf"

const CARD_ICON_BY_ID := {
	"rinne_slash": "skill_icon_slash",
	"rinne_cleave": "skill_icon_slash",
	"mint_shot": "skill_icon_slash",
	"mint_snipe": "skill_icon_slash",
	"homura_flare": "skill_icon_fire",
	"homura_ignite": "skill_icon_fire",
	"zhongkui_fist": "skill_icon_soul",
	"zhongkui_capture": "skill_icon_bind",
	"zhongkui_judge": "skill_icon_soul",
	"item_ignite": "skill_icon_fire",
	"item_water_splash": "skill_icon_water",
	"item_throw_rice": "skill_icon_rice",
	"item_place_talisman": "skill_icon_talisman",
	"item_ring_chime": "skill_icon_bell",
	"env_push_strike": "skill_icon_slash",
}
const ACTION_SLOT_COUNT := 4

var state: GameState
var turn_manager: TurnManager
var ai: AIController
var hovered_tile: Vector2i = Vector2i(-1, -1)
var reachable_tiles: Array = []
var target_tiles: Array = []
var damage_tiles: Array = []
var unit_sprites: Dictionary = {}
var enemy_acting: bool = false
var _battle_theme: Theme = null
var _noise_waves: Array = []

# Camera
var _camera: Camera2D
var _zoom_level: float = 1.0  # Fixed-scale camera. Keep this close to 1.0 to avoid magnifying map art.
var _cam_base_zoom: float = 1.48
const DEFAULT_ZOOM_LEVEL := 1.16
var _cam_offset: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _drag_threshold: float = 6.0
var _drag_start: Vector2 = Vector2.ZERO
var _drag_offset_start: Vector2 = Vector2.ZERO
var _click_pos: Vector2 = Vector2.ZERO
var _click_time: int = 0

# Rotation: 0=normal, 1=90CW, 2=180, 3=270CW
var _rotation: int = 0

# Isometric grid origin (top vertex of diamond)
var _grid_origin: Vector2 = Vector2.ZERO

var _turn_order_bar: HBoxContainer = null
var _turn_order_panel: Panel = null
var _turn_order_title: Label = null
var _card_tooltip: Panel = null
var _hover_info_panel: Panel = null
var _hover_info_label: Label = null
var _party_bar: HBoxContainer = null
var _skill_desc_panel: Panel = null
var _objective_panel: Panel = null
var _objective_round_label: Label = null
var _side_status_panel: VBoxContainer = null
var _side_danger_button: Button = null
var _side_speed_button: Button = null
var _top_system_bar: HBoxContainer = null
var _hover_range_tiles: Array = []
var _card_panel_pool: Array = []
var _inventory_panel_pool: Array = []
const INVENTORY_SLOTS: int = 4
const _SPELL_MODE: int = 0
const _ITEM_MODE: int = 1
var _panel_mode: int = _SPELL_MODE

var terrain_system: TerrainSystem = null
var interaction_system: InteractionSystem = null
var noise_system: RefCounted = null
var spirit_system: RefCounted = null

var _spirit_dots: Array = []
var _spirit_label: Label = null

var _interaction_menu: Control = null

var _tile_textures: Dictionary = {}
var _effect_textures: Dictionary = {}
var _object_textures: Dictionary = {}
var _map_bg_path: String = ""
var _ambient_redraw_accum: float = 0.0
var _has_ambient_map_animation: bool = false
var _overlay_layer: Node2D = null
var _enemy_intents: Array = []
var _enemy_turn_plan: Dictionary = {}
var _danger_range_enabled: bool = false
var _battle_speed_index: int = 0
var _battle_speed_scale: float = 1.0
const BATTLE_SPEED_VALUES := [1.0, 1.5, 2.0]

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# Load and apply Chinese font theme to the HUD so all UI controls inherit it.
	_battle_theme = load("res://assets/ui/themes/battle_theme.tres")
	if _battle_theme != null and has_node("HUD"):
		$HUD.theme = _battle_theme
		print("Applied battle_theme with Chinese font")
	else:
		push_warning("Failed to load battle_theme.tres or HUD node missing")
	_load_generated_ui_textures()
	_load_generated_card_faces()

	# Use imported textures so these assets remain available in exported builds.
	_portrait_tex = _load_image_texture("res://assets/zhongkui.png")
	if _portrait_tex != null:
		_portrait_atlas = AtlasTexture.new()
		_portrait_atlas.atlas = _portrait_tex
		_portrait_atlas.region = Rect2(480, 30, 580, 940)
		print("Portrait loaded OK, size: ", _portrait_tex.get_size())
	else:
		print("FAILED to load portrait")
	# Load all character sprite sheets
	var sprite_dir = DirAccess.open("res://assets/sprites")
	if sprite_dir != null:
		for file_name in sprite_dir.get_files():
			if file_name.ends_with("_idle.png"):
				var sid = file_name.replace("_idle.png", "")
				var sprite_tex = _load_image_texture("res://assets/sprites/" + file_name)
				if sprite_tex != null:
					_sprite_sheets[sid] = sprite_tex
	var hires_sprite_dir = DirAccess.open("res://assets/sprites/hires")
	if hires_sprite_dir != null:
		for file_name in hires_sprite_dir.get_files():
			if file_name.ends_with("_idle.png"):
				var sid = file_name.replace("_idle.png", "")
				var sprite_tex = _load_image_texture("res://assets/sprites/hires/" + file_name)
				if sprite_tex != null:
					_sprite_sheets[sid] = sprite_tex
	print("Loaded ", _sprite_sheets.size(), " sprite sheets")
	var portrait_files = {
		"rinne": "res://assets/portraits/ui/rinne_portrait_96.png",
		"mint": "res://assets/portraits/ui/mint_portrait_96.png",
		"homura": "res://assets/portraits/ui/homura_portrait_96.png",
		"zhongkui": "res://assets/portraits/ui/zhongkui_portrait_96.png",
	}
	for pid in portrait_files:
		var ptex = _load_image_texture(portrait_files[pid])
		if ptex != null:
			_portrait_textures[pid] = ptex
	var portrait_icon_files = {
		"rinne": "res://assets/portraits/ui/rinne_portrait_32.png",
		"mint": "res://assets/portraits/ui/mint_portrait_32.png",
		"homura": "res://assets/portraits/ui/homura_portrait_32.png",
		"zhongkui": "res://assets/portraits/ui/zhongkui_portrait_32.png",
	}
	for pid in portrait_icon_files:
		var icon_tex = _load_image_texture(portrait_icon_files[pid])
		if icon_tex != null:
			_portrait_icon_textures[pid] = icon_tex
	var portrait_icon_dir = DirAccess.open("res://assets/portraits/ui")
	if portrait_icon_dir != null:
		for file_name in portrait_icon_dir.get_files():
			if file_name.ends_with("_portrait_32.png"):
				var icon_id = file_name.replace("_portrait_32.png", "")
				var icon_tex = _load_image_texture("res://assets/portraits/ui/" + file_name)
				if icon_tex != null:
					_portrait_icon_textures[icon_id] = icon_tex
	# Load generated isometric tile textures. v2 tile/object assets are 4-frame vertical sheets.
	var tile_files = {
		"stone": "floor_stone_tile.png",
		"wall": "wall_dark.png",
		"wood": "planks_wood.png",
		"oil": "oil_dark.png",
		"elevated": "elevated_stairs.png",
		"sand": "sand_yellow.png",
		"grass": "grass_green.png",
		"forest": "forest_tree.png",
		"bush": "bush_green.png",
		"water": "water_blue.png",
		"rice": "rice_bag_beige.png",
		"seal": "seal_red.png",
		"curse": "curse_purple.png",
		"trap": "trap_hole.png",
		"void": "void_purple.png",
	}
	for terrain_id in tile_files:
		var tile_tex = _load_v2_frame_texture("res://assets/tiles/v2/" + tile_files[terrain_id])
		if tile_tex != null:
			_tile_textures[terrain_id] = tile_tex
	var effect_files = {
		"fire": "res://assets/tiles/generated_v4/effect_fire.png",
		"water_spread": "res://assets/tiles/generated_v4/effect_water.png",
		"explosion": "res://assets/tiles/generated_v4/effect_explosion.png",
		"curse_zone": "res://assets/tiles/generated_v4/effect_curse.png",
		"talisman": "res://assets/tiles/generated_v4/effect_talisman.png",
		"rice": "res://assets/tiles/generated_v4/effect_rice.png",
	}
	for effect_id in effect_files:
		var effect_tex = _load_image_texture(effect_files[effect_id])
		if effect_tex != null:
			_effect_textures[effect_id] = effect_tex
	var obj_files = {
		"brazier": "res://assets/tiles/generated_v4/object_brazier.png",
		"water_barrel": "res://assets/tiles/generated_v4/object_water_barrel.png",
		"rice_bag": "res://assets/tiles/generated_v4/object_rice_bag.png",
		"bell": "res://assets/tiles/generated_v4/object_bell.png",
		"door": "res://assets/tiles/generated_v4/object_door.png",
		"coffin": "res://assets/tiles/generated_v4/object_coffin.png",
		"explosive_barrel": "res://assets/tiles/generated_v4/object_explosive_barrel.png",
		"barrel": "res://assets/tiles/generated_v4/object_explosive_barrel.png",
		"crate": "res://assets/tiles/v2/crate_wood.png",
		"column": "res://assets/tiles/v2/column_stone.png",
	}
	for obj_id in obj_files:
		var object_path = str(obj_files[obj_id])
		var obj_tex = _load_image_texture(object_path) if object_path.contains("/generated_v") else _load_v2_frame_texture(object_path)
		if obj_tex != null:
			_object_textures[obj_id] = obj_tex
	print("Loaded ", _tile_textures.size(), " tile textures, ", _effect_textures.size(), " effect textures, ", _object_textures.size(), " object textures")

	state = GameState.new()
	state.init_battle(state.player_spawn_defs, state.enemy_spawn_defs)
	_load_map_background()
	_refresh_ambient_animation_flag()
	_init_camera()
	_init_overlay_layer()

	turn_manager = TurnManager.new(state)
	ai = AIController.new(state.map, state.all_units)

	# Terrain and interaction systems
	var rules_data = _load_json("res://data/rules.json")
	terrain_system = TerrainSystem.new(rules_data, state.map.effects_data, state.map.objects_data)
	interaction_system = InteractionSystem.new(state, state.map.objects_data)
	noise_system = NoiseSystemScript.new(state)
	spirit_system = SpiritSystemScript.new(state)
	spirit_system.track_enemies(state.enemies)
	spirit_system.density_changed.connect(_on_spirit_density_changed)
	spirit_system.tier_changed.connect(_on_spirit_tier_changed)
	_build_spirit_bar()

	# Listen for terrain damage events
	EventBus.on("unit:terrain_damage", _on_terrain_damage)
	EventBus.on("noise:propagated", _on_noise_propagated)
	EventBus.on("effect:added", _on_effect_added_visual)

	# Connect signals
	state.turn_start.connect(_on_turn_start)
	state.unit_moved.connect(_on_unit_moved)
	state.unit_damaged.connect(_on_unit_damaged)
	state.unit_healed.connect(_on_unit_healed)
	state.unit_died.connect(_on_unit_died)
	state.energy_changed.connect(_on_energy_changed)
	state.hand_changed.connect(_on_hand_changed)
	state.card_played.connect(_on_card_played)
	state.battle_won.connect(_on_battle_won)
	state.battle_lost.connect(_on_battle_lost)

	_style_battle_ui()

	_apply_button_frame($HUD/SwitchBtn)
	_setup_hover_info_panel()
	_update_tab_button_colors()
	$BottomUI/CardArea.visible = true
	$BottomUI/ItemArea.visible = false
	refresh_card_ui()

	_queue_scene_redraw()
	refresh_units()
	_refresh_turn_order_bar("player")
	turn_manager.start_player_turn()
	_refresh_active_stats_panel()
	_refresh_default_terrain_info()

func _init_overlay_layer() -> void:
	_overlay_layer = OverlayLayer.new()
	_overlay_layer.battle = self
	_overlay_layer.z_index = 50
	add_child(_overlay_layer)

func _queue_overlay_redraw() -> void:
	if _overlay_layer != null:
		_overlay_layer.queue_redraw()

func _queue_scene_redraw() -> void:
	queue_redraw()
	_queue_overlay_redraw()

func _load_generated_ui_textures() -> void:
	_ui_textures.clear()
	for key in UI_TEXTURE_FILES:
		var tex = _load_image_texture(UI_TEXTURE_FILES[key])
		if tex != null:
			_ui_textures[key] = tex

func _load_generated_card_faces() -> void:
	_card_face_textures.clear()
	var card_face_dir = DirAccess.open("res://assets/ui/generated/cards")
	if card_face_dir == null:
		return
	for file_name in card_face_dir.get_files():
		if not file_name.ends_with(".png"):
			continue
		if file_name.ends_with("_source.png"):
			continue
		var card_id = file_name.replace(".png", "")
		var tex = _load_image_texture("res://assets/ui/generated/cards/" + file_name)
		if tex != null:
			_card_face_textures[card_id] = tex

func _load_image_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var loaded = load(path)
		if loaded is Texture2D:
			return loaded
	var img = Image.new()
	if img.load(path) != OK:
		return null
	return ImageTexture.create_from_image(img)

func _load_v2_frame_texture(path: String) -> Texture2D:
	var base = _load_image_texture(path)
	if base == null:
		return null
	var atlas = AtlasTexture.new()
	atlas.atlas = base
	atlas.region = Rect2(0, 0, base.get_width(), minf(base.get_height(), base.get_width() * 0.5))
	return atlas

func _load_map_background() -> void:
	_bg_texture = null
	_map_bg_path = ""
	if state != null and state.map != null:
		_map_bg_path = str(state.map.bg_image)
	if _map_bg_path == "":
		_map_bg_path = "res://assets/generated/temple_courtyard_bg_clean_v1.png"
	_bg_texture = _load_image_texture(_map_bg_path)
	if _bg_texture == null:
		_map_bg_path = "res://assets/兰寺.png"
		_bg_texture = _load_image_texture(_map_bg_path)
	if _bg_texture != null:
		print("Background loaded: ", _map_bg_path, " size: ", Vector2i(_bg_texture.get_width(), _bg_texture.get_height()))

func _has_courtyard_background() -> bool:
	return _bg_texture != null and _map_bg_path.get_file().begins_with("temple_courtyard_bg")

func _make_clear_panel_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(0, 0, 0, 0)
	style.set_border_width_all(0)
	style.set_corner_radius_all(0)
	return style

func _add_generated_backdrop(parent: Control, texture_key: String, rect_size: Vector2, tint: Color = Color.WHITE) -> Control:
	if not _ui_textures.has(texture_key):
		return null
	var bg = NinePatchRect.new()
	bg.name = "GeneratedBackdrop"
	bg.texture = _ui_textures[texture_key]
	var margins: Vector4i = UI_PATCH_MARGINS.get(texture_key, Vector4i(32, 32, 32, 32))
	bg.patch_margin_left = margins.x
	bg.patch_margin_top = margins.y
	bg.patch_margin_right = margins.z
	bg.patch_margin_bottom = margins.w
	bg.position = Vector2.ZERO
	bg.size = rect_size
	bg.modulate = tint
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	parent.move_child(bg, 0)
	return bg

func _apply_button_frame(button: Button, texture_key: String = "tab_button") -> void:
	if texture_key == "top_button":
		var normal_top = _make_clear_panel_style()
		var hover_top = _make_clean_button_style(Color(0.06, 0.05, 0.08, 0.45), Color(UI_GOLD.r, UI_GOLD.g, UI_GOLD.b, 0.35))
		var pressed_top = _make_clean_button_style(Color(0.04, 0.035, 0.055, 0.55), UI_GOLD)
		button.add_theme_stylebox_override("normal", normal_top)
		button.add_theme_stylebox_override("hover", hover_top)
		button.add_theme_stylebox_override("pressed", pressed_top)
		button.add_theme_stylebox_override("focus", _make_clear_panel_style())
		button.add_theme_color_override("font_color", UI_TEXT_WARM)
		button.add_theme_color_override("font_hover_color", UI_GOLD_BRIGHT)
		button.add_theme_color_override("font_pressed_color", Color(1.0, 0.96, 0.7))
		return
	var normal = _make_clean_button_style(Color(0.060, 0.075, 0.098, 0.58), UI_GOLD)
	var hover = normal.duplicate()
	hover.bg_color = Color(0.080, 0.102, 0.132, 0.68)
	hover.border_color = UI_GOLD_BRIGHT
	hover.set_border_width_all(2)
	var pressed = normal.duplicate()
	pressed.bg_color = Color(0.090, 0.112, 0.142, 0.72)
	pressed.border_color = UI_GOLD_BRIGHT
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", _make_clear_panel_style())
	button.add_theme_color_override("font_color", UI_TEXT_WARM)
	button.add_theme_color_override("font_hover_color", UI_GOLD_BRIGHT)
	button.add_theme_color_override("font_pressed_color", Color(1.0, 0.96, 0.7))

func _configure_action_icon_button(button: Button, texture_key: String, caption: String, caption_right: bool) -> void:
	button.text = ""
	button.icon = null
	button.tooltip_text = caption
	button.add_theme_stylebox_override("normal", _make_clear_panel_style())
	button.add_theme_stylebox_override("hover", _make_clear_panel_style())
	button.add_theme_stylebox_override("pressed", _make_clear_panel_style())
	button.add_theme_stylebox_override("focus", _make_clear_panel_style())
	for child in button.get_children():
		child.queue_free()

	var backplate = NinePatchRect.new()
	backplate.name = "ActionBackplate"
	var frame_key = "action_mode_v2" if caption_right else "wait_button_v2"
	backplate.texture = _ui_textures.get(frame_key, null)
	var frame_margins: Vector4i = UI_PATCH_MARGINS.get(frame_key, Vector4i(32, 32, 32, 32))
	backplate.patch_margin_left = frame_margins.x
	backplate.patch_margin_top = frame_margins.y
	backplate.patch_margin_right = frame_margins.z
	backplate.patch_margin_bottom = frame_margins.w
	# Layout tuned to UI.md: tab buttons ~104x58, wait button is a 96x96 diamond.
	backplate.position = Vector2(-4, -4) if caption_right else Vector2(0, 0)
	backplate.size = Vector2(104, 58) if caption_right else Vector2(96, 96)
	backplate.modulate = Color(1.0, 1.0, 1.0, 0.90)
	backplate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(backplate)

	var glow = Panel.new()
	glow.name = "ActionGlow"
	glow.position = Vector2(8, 8) if caption_right else Vector2(16, 14)
	glow.size = Vector2(38, 36) if caption_right else Vector2(64, 56)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow_style = StyleBoxFlat.new()
	glow_style.bg_color = Color(0.12, 0.22, 0.25, 0.18)
	glow_style.border_color = Color(UI_GOLD.r, UI_GOLD.g, UI_GOLD.b, 0.18)
	glow_style.set_border_width_all(1)
	glow_style.set_corner_radius_all(8)
	glow.add_theme_stylebox_override("panel", glow_style)
	button.add_child(glow)

	var icon = TextureRect.new()
	icon.name = "ActionIcon"
	icon.texture = _ui_textures.get(texture_key, null)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if caption_right:
		icon.position = Vector2(0, 3)
		icon.size = Vector2(46, 46)
	else:
		icon.position = Vector2(24, 12)
		icon.size = Vector2(48, 48)
	button.add_child(icon)

	var caption_panel = Panel.new()
	caption_panel.name = "ActionCaption"
	caption_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var caption_style = StyleBoxFlat.new()
	caption_style.bg_color = Color(0.035, 0.055, 0.070, 0.78)
	caption_style.border_color = Color(UI_GOLD.r, UI_GOLD.g, UI_GOLD.b, 0.52)
	caption_style.set_border_width_all(1)
	caption_style.set_corner_radius_all(4)
	caption_panel.add_theme_stylebox_override("panel", caption_style)
	if caption_right:
		caption_panel.position = Vector2(48, 14)
		caption_panel.size = Vector2(48, 24)
	else:
		caption_panel.position = Vector2(19, 68)
		caption_panel.size = Vector2(58, 22)
	button.add_child(caption_panel)

	var caption_label = Label.new()
	caption_label.text = caption
	caption_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption_label.add_theme_font_size_override("font_size", 13)
	caption_label.add_theme_color_override("font_color", UI_TEXT_WARM)
	caption_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption_panel.add_child(caption_label)

func _make_ui_panel_style(border_color: Color = Color(0.82, 0.64, 0.22), bg_alpha: float = 0.88) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.052, 0.065, 0.082, minf(bg_alpha, 0.72))
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_top = 8
	style.content_margin_right = 10
	style.content_margin_bottom = 8
	return style

func _make_clean_panel_style(border_color: Color = UI_GOLD, bg_color: Color = UI_BG, radius: int = 6, border_width: int = 1) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.03, 0.05, 0.07, 0.22)
	style.shadow_size = 3
	style.content_margin_left = 12
	style.content_margin_top = 10
	style.content_margin_right = 12
	style.content_margin_bottom = 10
	return style

func _make_clean_button_style(bg_color: Color = Color(0.065, 0.075, 0.105, 0.62), border_color: Color = UI_GOLD) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.shadow_color = Color(0.03, 0.05, 0.07, 0.20)
	style.shadow_size = 2
	style.content_margin_left = 8
	style.content_margin_right = 8
	return style

func _make_hud_panel_style(border_color: Color = UI_GOLD, bg_alpha: float = 0.86, radius: int = 4, border_width: int = 1) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.058, 0.078, minf(bg_alpha, 0.72))
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.03, 0.05, 0.07, 0.24)
	style.shadow_size = 4
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func _make_slot_style(active: bool = false, accent: Color = UI_GOLD) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.060, 0.070, 0.092, 0.64)
	style.border_color = UI_GOLD_BRIGHT if active else accent
	style.set_border_width_all(2 if active else 1)
	style.set_corner_radius_all(4)
	style.shadow_color = Color(0.03, 0.05, 0.07, 0.22)
	style.shadow_size = 3
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style

func _make_card_style(active: bool, accent: Color, type_color: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(
		0.045 + type_color.r * 0.055,
		0.055 + type_color.g * 0.045,
		0.078 + type_color.b * 0.055,
		0.70 if active else 0.56
	)
	style.border_color = UI_GOLD_BRIGHT if active else Color(accent.r, accent.g, accent.b, 0.78)
	style.set_border_width_all(2 if active else 1)
	style.set_corner_radius_all(5)
	style.shadow_color = Color(0.02, 0.04, 0.06, 0.22)
	style.shadow_size = 3
	style.content_margin_left = 5
	style.content_margin_right = 5
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style

func _add_corner_marks(parent: Control, rect_size: Vector2, color: Color = UI_GOLD_BRIGHT) -> void:
	var len = 18.0
	var thick = 2.0
	var alpha_color = Color(color.r, color.g, color.b, 0.58)
	var positions = [
		[Vector2(7, 7), Vector2(len, thick)],
		[Vector2(7, 7), Vector2(thick, len)],
		[Vector2(rect_size.x - 7 - len, 7), Vector2(len, thick)],
		[Vector2(rect_size.x - 7 - thick, 7), Vector2(thick, len)],
		[Vector2(7, rect_size.y - 7 - thick), Vector2(len, thick)],
		[Vector2(7, rect_size.y - 7 - len), Vector2(thick, len)],
		[Vector2(rect_size.x - 7 - len, rect_size.y - 7 - thick), Vector2(len, thick)],
		[Vector2(rect_size.x - 7 - thick, rect_size.y - 7 - len), Vector2(thick, len)],
	]
	for item in positions:
		var mark = ColorRect.new()
		mark.position = item[0]
		mark.size = item[1]
		mark.color = alpha_color
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(mark)

func _add_separator(parent: Control, pos: Vector2, width: float) -> void:
	var line = ColorRect.new()
	line.position = pos
	line.size = Vector2(width, 1)
	line.color = Color(UI_GOLD.r, UI_GOLD.g, UI_GOLD.b, 0.35)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)

func _make_bar_style(color: Color, radius: int = 4) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0, 0, 0, 0)
	style.set_border_width_all(0)
	style.set_corner_radius_all(radius)
	return style

func _add_label(parent: Control, text: String, pos: Vector2, size: Vector2, font_size: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label = Label.new()
	label.text = text
	label.position = pos
	label.size = size
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _apply_chinese_font(control: Control, bold: bool = false) -> void:
	var font_path := CHINESE_FONT_BOLD if bold else CHINESE_FONT_REGULAR
	var font := load(font_path) as Font
	if font != null:
		control.add_theme_font_override("font", font)

func _unit_avatar_texture(unit: Unit, portrait_crop: bool = false) -> Texture2D:
	if unit == null:
		return null
	if portrait_crop and _portrait_textures.has(unit.template_id):
		return _portrait_textures[unit.template_id]
	if _sprite_sheets.has(unit.template_id):
		var base: Texture2D = _sprite_sheets[unit.template_id]
		var atlas = AtlasTexture.new()
		atlas.atlas = base
		var frame_w = maxf(1.0, base.get_width() / 4.0)
		var frame_h = maxf(1.0, base.get_height() / 4.0)
		if portrait_crop:
			atlas.region = Rect2(frame_w * 0.22, frame_h * 0.04, frame_w * 0.56, frame_h * 0.58)
		else:
			atlas.region = Rect2(0, 0, frame_w, frame_h)
		return atlas
	return _portrait_atlas

func _unit_order_icon_texture(unit: Unit) -> Texture2D:
	if unit != null and _portrait_icon_textures.has(unit.template_id):
		return _portrait_icon_textures[unit.template_id]
	return _unit_avatar_texture(unit, false)

func _add_stat_bar(parent: Control, label_text: String, value: float, max_value: float, color: Color, y: float, value_text: String) -> void:
	var icon = Label.new()
	icon.text = label_text
	icon.position = Vector2(0, y - 2)
	icon.size = Vector2(36, 18)
	icon.add_theme_font_size_override("font_size", 12)
	icon.add_theme_color_override("font_color", color)
	parent.add_child(icon)
	var bg = Panel.new()
	bg.position = Vector2(42, y + 2)
	bg.size = Vector2(132, 10)
	bg.add_theme_stylebox_override("panel", _make_bar_style(Color(color.r * 0.18, color.g * 0.18, color.b * 0.18, 0.82), 5))
	parent.add_child(bg)
	var fill = Panel.new()
	var ratio = clampf(value / maxf(max_value, 1.0), 0.0, 1.0)
	fill.size = Vector2(bg.size.x * ratio, bg.size.y)
	fill.add_theme_stylebox_override("panel", _make_bar_style(color, 5))
	bg.add_child(fill)
	_add_label(parent, value_text, Vector2(182, y - 2), Vector2(66, 18), 12, UI_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)

func _add_compact_stat_bar(parent: Control, label_text: String, value: float, max_value: float, color: Color, y: float, value_text: String) -> void:
	# Layout tuned for the 280x300 status panel spec: label 42px, bar 132px, value 60px.
	_add_label(parent, label_text, Vector2(0, y - 2), Vector2(42, 18), 12, color)
	var bg = Panel.new()
	bg.position = Vector2(46, y + 2)
	bg.size = Vector2(132, 10)
	bg.add_theme_stylebox_override("panel", _make_bar_style(Color(color.r * 0.18, color.g * 0.18, color.b * 0.18, 0.82), 5))
	parent.add_child(bg)
	var fill = Panel.new()
	var ratio = clampf(value / maxf(max_value, 1.0), 0.0, 1.0)
	fill.size = Vector2(bg.size.x * ratio, bg.size.y)
	fill.add_theme_stylebox_override("panel", _make_bar_style(color, 5))
	bg.add_child(fill)
	_add_label(parent, value_text, Vector2(184, y - 2), Vector2(60, 18), 12, UI_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)

func _style_battle_ui() -> void:
	$HUD/TurnLabel.visible = false
	$HUD/TurnCount.visible = false
	var hand_panel = $BottomUI/HandPanel
	hand_panel.offset_left = 680
	hand_panel.offset_top = 874
	hand_panel.offset_right = 1090
	hand_panel.offset_bottom = 1014
	hand_panel.size = Vector2(410, 140)
	hand_panel.add_theme_stylebox_override("panel", _make_clear_panel_style())
	hand_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card_area: Control = $BottomUI/CardArea
	var item_area: Control = $BottomUI/ItemArea
	card_area.offset_left = 706
	card_area.offset_top = 886
	card_area.offset_right = 1086
	card_area.offset_bottom = 1004
	item_area.offset_left = 706
	item_area.offset_top = 886
	item_area.offset_right = 1086
	item_area.offset_bottom = 1004
	$BottomUI/TabButtons.offset_left = 1206
	$BottomUI/TabButtons.offset_top = 886
	$BottomUI/TabButtons.offset_right = 1306
	$BottomUI/TabButtons.offset_bottom = 1004
	$BottomUI/TabButtons.add_theme_constant_override("separation", 10)
	card_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$BottomUI/TabButtons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$BottomUI/TabButtons/SpellBtn.custom_minimum_size = Vector2(100, 52)
	$BottomUI/TabButtons/ItemBtn.custom_minimum_size = Vector2(100, 52)
	_configure_action_icon_button($BottomUI/TabButtons/SpellBtn, "action_spell", "法术", true)
	_configure_action_icon_button($BottomUI/TabButtons/ItemBtn, "action_item", "道具", true)
	$HUD/APLabel.visible = false
	$HUD/SpiritBar.visible = false
	$HUD/SpiritLabel.visible = false
	# End turn / wait button: 96x96 diamond per UI.md.
	$HUD/EndTurnBtn.offset_left = 1102
	$HUD/EndTurnBtn.offset_top = 892
	$HUD/EndTurnBtn.offset_right = 1198
	$HUD/EndTurnBtn.offset_bottom = 988
	_configure_action_icon_button($HUD/EndTurnBtn, "action_wait", "待机", false)
	$HUD/SwitchBtn.visible = false
	_init_party_bar()
	_setup_reference_side_panels()

func _setup_reference_side_panels() -> void:
	if _objective_panel == null:
		_objective_panel = Panel.new()
		_objective_panel.position = Vector2(1250, 120)
		_objective_panel.size = Vector2(270, 120)
		_objective_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		_objective_panel.add_theme_stylebox_override("panel", _make_hud_panel_style(UI_GOLD, 0.58, 3, 1))
		$HUD.add_child(_objective_panel)
		_add_corner_marks(_objective_panel, _objective_panel.size, UI_GOLD)
		_add_label(_objective_panel, "胜利条件", Vector2(0, 14), Vector2(270, 22), 14, UI_GOLD_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)
		_add_label(_objective_panel, "击败所有敌人", Vector2(0, 54), Vector2(270, 22), 13, UI_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		_objective_round_label = _add_label(_objective_panel, "回合  1/15", Vector2(0, 88), Vector2(270, 22), 14, UI_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		_apply_chinese_font(_objective_round_label, true)
	if _side_status_panel == null:
		_side_status_panel = VBoxContainer.new()
		_side_status_panel.position = Vector2(1372, 340)
		_side_status_panel.size = Vector2(120, 104)
		_side_status_panel.add_theme_constant_override("separation", 8)
		_side_status_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		$HUD.add_child(_side_status_panel)
		_side_danger_button = _make_side_toggle_button()
		_side_danger_button.pressed.connect(_on_danger_range_pressed)
		_side_status_panel.add_child(_side_danger_button)
		_side_speed_button = _make_side_toggle_button()
		_side_speed_button.pressed.connect(_on_speed_button_pressed)
		_side_status_panel.add_child(_side_speed_button)
		_refresh_side_status_controls()
	if _top_system_bar == null:
		_top_system_bar = HBoxContainer.new()
		_top_system_bar.position = Vector2(1372, 16)
		_top_system_bar.size = Vector2(148, 56)
		_top_system_bar.add_theme_constant_override("separation", 8)
		_top_system_bar.mouse_filter = Control.MOUSE_FILTER_STOP
		$HUD.add_child(_top_system_bar)
		var top_buttons = [
			["⚙\n设置", Callable()],
			["↗\n自动", Callable()],
			["◆\n结束", Callable(self, "_on_end_turn_pressed")],
		]
		for entry in top_buttons:
			var btn = Button.new()
			btn.text = str(entry[0])
			btn.custom_minimum_size = Vector2(44, 56)
			btn.add_theme_font_size_override("font_size", 10)
			# Minimal frameless style per UI.md (icon + small text, no background panel).
			btn.add_theme_stylebox_override("normal", _make_clear_panel_style())
			btn.add_theme_stylebox_override("hover", _make_clean_button_style(Color(UI_GOLD.r, UI_GOLD.g, UI_GOLD.b, 0.12), UI_GOLD))
			btn.add_theme_stylebox_override("pressed", _make_clean_button_style(Color(UI_GOLD.r, UI_GOLD.g, UI_GOLD.b, 0.22), UI_GOLD_BRIGHT))
			btn.add_theme_stylebox_override("focus", _make_clear_panel_style())
			btn.add_theme_color_override("font_color", UI_TEXT_WARM)
			btn.add_theme_color_override("font_hover_color", UI_GOLD_BRIGHT)
			btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.96, 0.7))
			var cb: Callable = entry[1]
			if cb.is_valid():
				btn.pressed.connect(cb)
			_top_system_bar.add_child(btn)

func _make_side_toggle_button() -> Button:
	# Compact toggle row per UI.md spec (target: 36x18 toggle + text).
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(120, 32)
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", UI_TEXT_WARM)
	btn.add_theme_color_override("font_hover_color", UI_GOLD_BRIGHT)
	btn.add_theme_stylebox_override("normal", _make_clean_button_style(Color(0.052, 0.070, 0.090, 0.54), Color(UI_GOLD.r, UI_GOLD.g, UI_GOLD.b, 0.50)))
	btn.add_theme_stylebox_override("hover", _make_clean_button_style(Color(0.070, 0.095, 0.120, 0.68), UI_GOLD))
	btn.add_theme_stylebox_override("pressed", _make_clean_button_style(Color(0.090, 0.115, 0.140, 0.74), UI_GOLD_BRIGHT))
	return btn

func _refresh_side_status_controls() -> void:
	if _side_danger_button != null:
		_side_danger_button.text = "危险范围\n%s" % ("开" if _danger_range_enabled else "关")
	if _side_speed_button != null:
		_side_speed_button.text = "速度\nx%.1f" % _battle_speed_scale

func _on_danger_range_pressed() -> void:
	_danger_range_enabled = not _danger_range_enabled
	_refresh_side_status_controls()
	_queue_overlay_redraw()

func _on_speed_button_pressed() -> void:
	_battle_speed_index = (_battle_speed_index + 1) % BATTLE_SPEED_VALUES.size()
	_battle_speed_scale = float(BATTLE_SPEED_VALUES[_battle_speed_index])
	_refresh_side_status_controls()

func _battle_delay(base_seconds: float) -> float:
	return base_seconds / maxf(_battle_speed_scale, 0.1)

func _exit_tree() -> void:
	EventBus.off("unit:terrain_damage", _on_terrain_damage)
	EventBus.off("noise:propagated", _on_noise_propagated)
	EventBus.off("effect:added", _on_effect_added_visual)
	if ai != null and ai.has_method("dispose"):
		ai.dispose()
	if noise_system != null:
		noise_system.dispose()
	if spirit_system != null and spirit_system.has_method("dispose"):
		spirit_system.dispose()
	if terrain_system != null:
		EventBus.off("effect:added", terrain_system._on_effect_added)
		EventBus.off("object:pushed_over", terrain_system._on_object_pushed_over)

func _visual_dims() -> Vector2i:
	# Grid dimensions after rotation
	match _rotation:
		1, 3: return Vector2i(state.map.rows, state.map.cols)
		_: return Vector2i(state.map.cols, state.map.rows)

func _visual_coord(col: int, row: int) -> Vector2i:
	# Map grid (col, row) -> visual (vcol, vrow) based on rotation
	match _rotation:
		0: return Vector2i(col, row)
		1: return Vector2i(state.map.rows - 1 - row, col)
		2: return Vector2i(state.map.cols - 1 - col, state.map.rows - 1 - row)
		3: return Vector2i(row, state.map.cols - 1 - col)
	return Vector2i(col, row)

func _grid_from_visual(vcol: int, vrow: int) -> Vector2i:
	# Reverse: visual (vcol, vrow) -> grid (col, row)
	match _rotation:
		0: return Vector2i(vcol, vrow)
		1: return Vector2i(vrow, state.map.rows - 1 - vcol)
		2: return Vector2i(state.map.cols - 1 - vcol, state.map.rows - 1 - vrow)
		3: return Vector2i(state.map.cols - 1 - vrow, vcol)
	return Vector2i(vcol, vrow)

func _grid_facing_to_visual(grid_facing: Vector2i) -> Vector2i:
	match _rotation:
		0: return grid_facing
		1: return Vector2i(-grid_facing.y, grid_facing.x)
		2: return Vector2i(-grid_facing.x, -grid_facing.y)
		3: return Vector2i(grid_facing.y, -grid_facing.x)
	return grid_facing

func cart_to_iso(vcol: int, vrow: int) -> Vector2:
	return Vector2((vcol - vrow) * TILE_W * 0.5, (vcol + vrow) * TILE_H * 0.5)

func _tile_center(pos: Vector2i) -> Vector2:
	var vc = _visual_coord(pos.x, pos.y)
	return _grid_origin + cart_to_iso(vc.x, vc.y)

func screen_to_grid(screen_pos: Vector2) -> Vector2i:
	var z = _get_camera_zoom()
	var vp_center = get_viewport_rect().size * 0.5
	var world_pos = (screen_pos - vp_center) / z + _camera.position
	var local = world_pos - _grid_origin
	var vcol = (local.x / (TILE_W * 0.5) + local.y / (TILE_H * 0.5)) * 0.5
	var vrow = (local.y / (TILE_H * 0.5) - local.x / (TILE_W * 0.5)) * 0.5
	return _grid_from_visual(roundi(vcol), roundi(vrow))

func _init_camera() -> void:
	_camera = Camera2D.new()
	add_child(_camera)
	_camera.make_current()
	_grid_origin = Vector2.ZERO
	var dims = _visual_dims()
	var grid_w = (dims.x + dims.y) * TILE_W * 0.5
	var grid_h = (dims.x + dims.y) * TILE_H * 0.5 + 80
	var view_size = get_viewport_rect().size
	_cam_base_zoom = minf((view_size.x - 180.0) / grid_w, (view_size.y - 180.0) / grid_h)
	_zoom_level = DEFAULT_ZOOM_LEVEL
	var grid_center = cart_to_iso(dims.x * 0.5, dims.y * 0.5)
	_camera.position = grid_center
	var z = _get_camera_zoom()
	_camera.zoom = Vector2(z, z)

func _update_camera() -> void:
	if _camera == null:
		return
	var dims = _visual_dims()
	var grid_center = cart_to_iso(dims.x * 0.5, dims.y * 0.5)
	var z = _get_camera_zoom()
	var desired = _clamp_camera_position(grid_center + _cam_offset, z)
	_cam_offset = desired - grid_center
	_camera.position = desired
	_camera.zoom = Vector2(z, z)
	_queue_scene_redraw()

func _get_camera_zoom() -> float:
	return _cam_base_zoom * _zoom_level

func _clamp_camera_position(desired: Vector2, zoom: float) -> Vector2:
	var rect = _map_world_rect(6)
	var half_view = get_viewport_rect().size * 0.5 / zoom
	var result = desired
	if rect.size.x <= half_view.x * 2.0:
		result.x = rect.get_center().x
	else:
		result.x = clampf(result.x, rect.position.x + half_view.x, rect.end.x - half_view.x)
	if rect.size.y <= half_view.y * 2.0:
		result.y = rect.get_center().y
	else:
		result.y = clampf(result.y, rect.position.y + half_view.y, rect.end.y - half_view.y)
	return result

func _map_world_rect(padding: int = 0) -> Rect2:
	var dims = _visual_dims()
	var hw = TILE_W * 0.5
	var hh = TILE_H * 0.5
	var min_x = -(dims.y - 1 + padding) * hw - hw
	var max_x = (dims.x - 1 + padding) * hw + hw
	var min_y = -hh - padding * hh
	var max_y = (dims.x + dims.y - 2 + padding * 2) * hh + hh
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))

func _rotate_view(dir: int) -> void:
	_rotation = (_rotation + dir) % 4
	if _rotation < 0:
		_rotation += 4
	var dims = _visual_dims()
	var grid_w = (dims.x + dims.y) * TILE_W * 0.5
	var grid_h = (dims.x + dims.y) * TILE_H * 0.5 + 80
	var view_size = get_viewport_rect().size
	_cam_base_zoom = minf((view_size.x - 180.0) / grid_w, (view_size.y - 180.0) / grid_h)
	_zoom_level = DEFAULT_ZOOM_LEVEL
	_cam_offset = Vector2.ZERO
	_update_camera()
	refresh_units()

func _process(delta: float) -> void:
	var needs_overlay_redraw = false
	var needs_scene_redraw = false
	for i in range(_noise_waves.size() - 1, -1, -1):
		var wave = _noise_waves[i]
		wave["ttl"] = float(wave.get("ttl", 0.0)) - delta
		_noise_waves[i] = wave
		needs_overlay_redraw = true
		if float(wave.get("ttl", 0.0)) <= 0.0:
			_noise_waves.remove_at(i)
	if _has_ambient_map_animation:
		_ambient_redraw_accum += delta
		if _ambient_redraw_accum >= 0.083:
			_ambient_redraw_accum = 0.0
			needs_scene_redraw = true
	if state != null and not state.noise_events.is_empty():
		needs_overlay_redraw = true
	if needs_scene_redraw:
		_queue_scene_redraw()
	elif needs_overlay_redraw:
		_queue_overlay_redraw()

func _refresh_ambient_animation_flag() -> void:
	_has_ambient_map_animation = _has_animated_map_effects()

func _has_animated_map_effects() -> bool:
	if state == null or state.map == null:
		return false
	for row in range(state.map.rows):
		for col in range(state.map.cols):
			var terrain = state.map.get_terrain(col, row)
			if terrain == "water" or terrain == "oil" or terrain == "trap" or terrain == "void" or terrain == "curse":
				return true
			for eff in state.map.get_effects(col, row):
				if eff.type == "fire" or eff.type == "explosion":
					return true
	return false

func _draw_exterior_tiles(dims: Vector2i, hw: float, hh: float) -> void:
	if _has_courtyard_background():
		return
	var padding = 8
	for vrow in range(-padding, dims.y + padding):
		for vcol in range(-padding, dims.x + padding):
			if vcol >= 0 and vcol < dims.x and vrow >= 0 and vrow < dims.y:
				continue
			var s = _grid_origin + cart_to_iso(vcol, vrow)
			var pts = PackedVector2Array([
				s + Vector2(0, -hh),
				s + Vector2(hw, 0),
				s + Vector2(0, hh),
				s + Vector2(-hw, 0),
			])
			var edge_color = Color(0.24, 0.21, 0.17) if (vcol + vrow) % 2 == 0 else Color(0.19, 0.17, 0.14)
			draw_colored_polygon(pts, edge_color)
			draw_polyline(pts, Color(0.05, 0.04, 0.035, 0.45), 1.0)

func _draw_background_plate() -> void:
	if _bg_texture == null:
		return
	var map_rect = _map_world_rect()
	var tex_size = Vector2(_bg_texture.get_width(), _bg_texture.get_height())
	var draw_size = tex_size
	if _has_courtyard_background():
		var scale = map_rect.size.x / tex_size.x
		draw_size = tex_size * scale
	else:
		var target = _map_world_rect(8).grow(260)
		var scale_fit = maxf(target.size.x / tex_size.x, target.size.y / tex_size.y)
		draw_size = tex_size * scale_fit
	var rect = Rect2(map_rect.get_center() - draw_size * 0.5, draw_size)
	var tint = Color(1, 1, 1, 1.0) if _has_courtyard_background() else Color(1, 1, 1, 0.38)
	draw_texture_rect(_bg_texture, rect, false, tint)
	if not _has_courtyard_background():
		draw_rect(rect, Color(0.07, 0.06, 0.05, 0.16), false, 3.0)

func _draw() -> void:
	# Non-black fallback background; the playable map is surrounded by non-walkable edge tiles.
	draw_rect(_map_world_rect(10).grow(800), Color(0.10, 0.09, 0.08))
	_draw_background_plate()

	var dims = _visual_dims()
	var hw = TILE_W * 0.5
	var hh = TILE_H * 0.5
	var depth = 20
	var wall_extra = 12
	var using_painted_map = _has_courtyard_background()
	_draw_exterior_tiles(dims, hw, hh)

	# Tile colors (terrain types)
	var tile_top = {
		"grass": Color(0.30, 0.55, 0.25),
		"forest": Color(0.15, 0.42, 0.15),
		"bush": Color(0.25, 0.55, 0.28),
		"sand": Color(0.72, 0.65, 0.45),
		"wall": Color(0.50, 0.47, 0.42),
		"water": Color(0.15, 0.35, 0.55),
		"stone": Color(0.54, 0.51, 0.47),
		"oil": Color(0.29, 0.23, 0.13),
		"wood": Color(0.48, 0.35, 0.19),
		"rice": Color(0.91, 0.88, 0.75),
		"seal": Color(0.75, 0.25, 0.25),
		"curse": Color(0.38, 0.13, 0.38),
		"elevated": Color(0.60, 0.56, 0.44),
		"trap": Color(0.38, 0.06, 0.06),
		"void": Color(0.06, 0.06, 0.09),
	}
	var tile_left = {
		"grass": Color(0.20, 0.40, 0.17),
		"forest": Color(0.10, 0.30, 0.10),
		"bush": Color(0.17, 0.42, 0.19),
		"sand": Color(0.58, 0.52, 0.35),
		"wall": Color(0.38, 0.35, 0.30),
		"water": Color(0.10, 0.25, 0.42),
		"stone": Color(0.42, 0.39, 0.36),
		"oil": Color(0.20, 0.16, 0.09),
		"wood": Color(0.36, 0.26, 0.14),
		"rice": Color(0.72, 0.70, 0.60),
		"seal": Color(0.55, 0.18, 0.18),
		"curse": Color(0.25, 0.08, 0.25),
		"elevated": Color(0.46, 0.43, 0.34),
		"trap": Color(0.25, 0.04, 0.04),
		"void": Color(0.04, 0.04, 0.06),
	}
	var tile_right = {
		"grass": Color(0.16, 0.34, 0.13),
		"forest": Color(0.07, 0.22, 0.07),
		"bush": Color(0.13, 0.36, 0.15),
		"sand": Color(0.50, 0.44, 0.30),
		"wall": Color(0.32, 0.30, 0.26),
		"water": Color(0.07, 0.18, 0.35),
		"stone": Color(0.36, 0.34, 0.31),
		"oil": Color(0.16, 0.13, 0.07),
		"wood": Color(0.28, 0.20, 0.10),
		"rice": Color(0.60, 0.58, 0.50),
		"seal": Color(0.45, 0.15, 0.15),
		"curse": Color(0.18, 0.06, 0.18),
		"elevated": Color(0.38, 0.36, 0.28),
		"trap": Color(0.18, 0.03, 0.03),
		"void": Color(0.03, 0.03, 0.04),
	}

	# Draw tiles back-to-front (visual space)
	for vrow in range(dims.y):
		for vcol in range(dims.x):
			var grid = _grid_from_visual(vcol, vrow)
			var iso = cart_to_iso(vcol, vrow)
			var screen = _grid_origin + iso
			var terrain = state.map.get_terrain(grid.x, grid.y)
			if using_painted_map:
				var pts = PackedVector2Array([
					screen + Vector2(0, -hh),
					screen + Vector2(hw, 0),
					screen + Vector2(0, hh),
					screen + Vector2(-hw, 0),
				])
				var overlay_color = Color(0.08, 0.16, 0.18, 0.08)
				match terrain:
					"wall":
						overlay_color = Color(0.05, 0.04, 0.035, 0.18)
					"water":
						overlay_color = Color(0.12, 0.35, 0.58, 0.14)
					"oil":
						overlay_color = Color(0.34, 0.22, 0.04, 0.15)
					"trap", "void":
						overlay_color = Color(0.08, 0.01, 0.01, 0.24)
					"curse":
						overlay_color = Color(0.33, 0.04, 0.42, 0.16)
					"seal":
						overlay_color = Color(0.55, 0.08, 0.06, 0.14)
					"rice":
						overlay_color = Color(0.85, 0.76, 0.38, 0.13)
				if terrain != "stone" and terrain != "wood" and terrain != "grass" and terrain != "sand" and terrain != "elevated":
					overlay_color.a *= 0.48
					draw_colored_polygon(pts, overlay_color)
			elif _tile_textures.has(terrain):
				var tex = _tile_textures[terrain]
				var tex_w = 128.0
				var tex_h = tex.get_height() * tex_w / tex.get_width()
				var tex_x = screen.x - tex_w * 0.5
				var tex_y = screen.y + hh - tex_h
				draw_texture_rect(tex, Rect2(tex_x, tex_y, tex_w, tex_h), false)
			else:
				var d = depth
				var y_off = 0
				if terrain == "wall":
					d += wall_extra
					y_off = wall_extra
				var top_c = tile_top.get(terrain, tile_top.grass)
				var left_c = tile_left.get(terrain, tile_left.grass)
				var right_c = tile_right.get(terrain, tile_right.grass)
				var t = screen + Vector2(0, -hh - y_off)
				var r = screen + Vector2(hw, -y_off)
				var b = screen + Vector2(0, hh - y_off)
				var l = screen + Vector2(-hw, -y_off)
				# Left face
				var lp = PackedVector2Array([l, b, b + Vector2(0, d), l + Vector2(0, d)])
				draw_colored_polygon(lp, left_c)
				draw_polyline(lp, Color(0, 0, 0, 0.3), 1.0)
				# Right face
				var rp = PackedVector2Array([b, r, r + Vector2(0, d), b + Vector2(0, d)])
				draw_colored_polygon(rp, right_c)
				draw_polyline(rp, Color(0, 0, 0, 0.3), 1.0)
				# Top face
				var tp = PackedVector2Array([t, r, b, l])
				draw_colored_polygon(tp, top_c)
				draw_polyline(tp, Color(1, 1, 1, 0.055), 0.75)
	# Terrain decorations (water shimmer, trap holes, oil sheen, curse glow)
	var t_now = Time.get_ticks_msec() * 0.001
	var deco_alpha_scale = 0.42 if using_painted_map else 1.0
	for vrow_td in range(dims.y):
		for vcol_td in range(dims.x):
			var grid_td = _grid_from_visual(vcol_td, vrow_td)
			var iso_td = cart_to_iso(vcol_td, vrow_td)
			var s_td = _grid_origin + iso_td
			var terr_td = state.map.get_terrain(grid_td.x, grid_td.y)
			var diamond_td = PackedVector2Array([s_td + Vector2(0, -hh), s_td + Vector2(hw, 0), s_td + Vector2(0, hh), s_td + Vector2(-hw, 0)])
			match terr_td:
				"water":
					draw_colored_polygon(diamond_td, Color(0.15, 0.35, 0.65, 0.28 * deco_alpha_scale))
					var wave_off = sin(t_now * 2.0 + vcol_td * 1.5 + vrow_td * 1.2) * 3
					var w1 = PackedVector2Array([s_td + Vector2(-16, wave_off - 4), s_td + Vector2(16, wave_off - 4), s_td + Vector2(16, wave_off), s_td + Vector2(-16, wave_off)])
					draw_colored_polygon(w1, Color(0.3, 0.55, 0.85, 0.4 * deco_alpha_scale))
					var w2 = PackedVector2Array([s_td + Vector2(-8, 4 + wave_off * 0.5), s_td + Vector2(8, 4 + wave_off * 0.5), s_td + Vector2(8, 8 + wave_off * 0.5), s_td + Vector2(-8, 8 + wave_off * 0.5)])
					draw_colored_polygon(w2, Color(0.35, 0.6, 0.9, 0.3 * deco_alpha_scale))
				"oil":
					draw_colored_polygon(diamond_td, Color(0.15, 0.10, 0.03, 0.24 * deco_alpha_scale))
					var sheen = 0.2 + 0.1 * sin(t_now * 1.5 + grid_td.x * 2.0)
					var sheen_pts = PackedVector2Array([s_td + Vector2(-12, -4), s_td + Vector2(12, -4), s_td + Vector2(8, 0), s_td + Vector2(-8, 0)])
					draw_colored_polygon(sheen_pts, Color(0.6, 0.5, 0.2, sheen * deco_alpha_scale))
				"trap":
					draw_colored_polygon(diamond_td, Color(0.02, 0.02, 0.02, 0.32 * deco_alpha_scale))
					var pulse = 0.5 + 0.3 * sin(t_now * 3.0 + grid_td.x)
					var inner_td = PackedVector2Array([s_td + Vector2(0, -12), s_td + Vector2(18, 0), s_td + Vector2(0, 12), s_td + Vector2(-18, 0)])
					draw_colored_polygon(inner_td, Color(0.4, 0.0, 0.0, pulse * deco_alpha_scale))
					draw_polyline(inner_td, Color(0.6, 0.1, 0.1, 0.7 * deco_alpha_scale), 1.5)
				"void":
					draw_colored_polygon(diamond_td, Color(0.0, 0.0, 0.0, 0.40 * deco_alpha_scale))
					var rim = PackedVector2Array([s_td + Vector2(0, -18), s_td + Vector2(28, 0), s_td + Vector2(0, 18), s_td + Vector2(-28, 0)])
					var core = PackedVector2Array([s_td + Vector2(0, -9), s_td + Vector2(14, 0), s_td + Vector2(0, 9), s_td + Vector2(-14, 0)])
					draw_polyline(rim, Color(0.55, 0.12, 0.08, 0.9 * deco_alpha_scale), 3.0)
					draw_colored_polygon(core, Color(0.0, 0.0, 0.0, 1.0 * deco_alpha_scale))
					draw_polyline(core, Color(0.85, 0.3, 0.12, 0.75 * deco_alpha_scale), 1.5)
				"curse":
					var curse_pulse = 0.3 + 0.15 * sin(t_now * 2.5 + grid_td.y)
					draw_colored_polygon(diamond_td, Color(0.3, 0.0, 0.3, curse_pulse * 0.65 * deco_alpha_scale))
				"seal":
					draw_colored_polygon(diamond_td, Color(0.5, 0.15, 0.15, 0.22 * deco_alpha_scale))
					draw_polyline(diamond_td, Color(0.8, 0.2, 0.2, 0.6 * deco_alpha_scale), 1.5)
	# Effect overlays (animated fire, water spread, etc.)
	var effect_colors = {
		"fire": Color(1.0, 0.4, 0.1, 0.6),
		"water_spread": Color(0.2, 0.5, 0.9, 0.5),
		"rice": Color(0.9, 0.88, 0.7, 0.35),
		"ink_line": Color(0.1, 0.1, 0.1, 0.5),
		"talisman": Color(0.85, 0.75, 0.2, 0.4),
		"curse_zone": Color(0.5, 0.1, 0.5, 0.4),
		"explosion": Color(1.0, 0.6, 0.1, 0.65),
	}
	for vrow_e in range(dims.y):
		for vcol_e in range(dims.x):
			var grid_e = _grid_from_visual(vcol_e, vrow_e)
			var effects = state.map.get_effects(grid_e.x, grid_e.y)
			if effects.is_empty():
				continue
			var iso_e = cart_to_iso(vcol_e, vrow_e)
			var s_e = _grid_origin + iso_e
			for eff in effects:
				var ec = effect_colors.get(eff.type, Color(1, 1, 1, 0.2))
				var pts_e = PackedVector2Array([s_e + Vector2(0, -hh), s_e + Vector2(hw, 0), s_e + Vector2(0, hh), s_e + Vector2(-hw, 0)])
				if _effect_textures.has(eff.type):
					var effect_tex = _effect_textures[eff.type]
					var effect_w = 128.0
					var effect_h = effect_tex.get_height() * effect_w / effect_tex.get_width()
					var effect_alpha = 0.72 if using_painted_map else 0.88
					draw_texture_rect(effect_tex, Rect2(s_e.x - effect_w * 0.5, s_e.y + hh - effect_h, effect_w, effect_h), false, Color(1, 1, 1, effect_alpha))
				else:
					draw_colored_polygon(pts_e, ec)
				_draw_effect_badge(str(eff.type), s_e, t_now)
				if eff.type == "rice":
					for grain_i in range(12):
						var gx = sin(float(grain_i) * 1.7 + grid_e.x * 0.9) * 28.0
						var gy = cos(float(grain_i) * 1.3 + grid_e.y * 1.1) * 13.0
						draw_circle(s_e + Vector2(gx, gy), 2.0, Color(0.96, 0.93, 0.74, 0.60 if using_painted_map else 0.82))
				if eff.type == "fire":
					var flicker = sin(t_now * 8.0 + grid_e.x * 3.0 + grid_e.y * 5.0) * 0.3 + 0.5
					var flame_pts = PackedVector2Array([
						s_e + Vector2(0, -hh - 8 - flicker * 10),
						s_e + Vector2(10, -4),
						s_e + Vector2(6, 0),
						s_e + Vector2(-6, 0),
						s_e + Vector2(-10, -4),
					])
					draw_colored_polygon(flame_pts, Color(1.0, 0.7 * flicker, 0.1, 0.58 if using_painted_map else 0.7))
					var core_pts = PackedVector2Array([
						s_e + Vector2(0, -hh - 4 - flicker * 6),
						s_e + Vector2(5, -2),
						s_e + Vector2(3, 0),
						s_e + Vector2(-3, 0),
						s_e + Vector2(-5, -2),
					])
					draw_colored_polygon(core_pts, Color(1.0, 0.9, 0.3, 0.46 if using_painted_map else 0.6))
				if eff.type == "explosion":
					var ex_flicker = sin(t_now * 12.0 + grid_e.x) * 0.2 + 0.6
					var ex_pts = PackedVector2Array([
						s_e + Vector2(0, -hh - 12),
						s_e + Vector2(hw - 8, 0),
						s_e + Vector2(0, hh - 8),
						s_e + Vector2(-hw + 8, 0),
					])
					draw_colored_polygon(ex_pts, Color(1.0, 0.5, 0.0, ex_flicker * (0.78 if using_painted_map else 1.0)))

	# Object rendering
	var obj_colors = {
		"brazier": Color(1.0, 0.5, 0.1),
		"water_barrel": Color(0.2, 0.5, 0.9),
		"rice_bag": Color(0.9, 0.85, 0.5),
		"bell": Color(0.9, 0.75, 0.2),
		"door": Color(0.6, 0.45, 0.25),
		"coffin": Color(0.5, 0.3, 0.15),
		"explosive_barrel": Color(0.9, 0.2, 0.1),
	}
	for vrow_o in range(dims.y):
		for vcol_o in range(dims.x):
			var grid_o = _grid_from_visual(vcol_o, vrow_o)
			var obj_id = state.map.get_object(grid_o.x, grid_o.y)
			if obj_id == "":
				continue
			var iso_o = cart_to_iso(vcol_o, vrow_o)
			var s_o = _grid_origin + iso_o
			var obj_color = obj_colors.get(obj_id, Color.GRAY)
			_draw_object_ground_art(obj_id, s_o, obj_color, t_now)
			if _object_textures.has(obj_id):
				var tex = _object_textures[obj_id]
				var tex_w = 82.0
				match obj_id:
					"door":
						tex_w = 104.0
					"coffin":
						tex_w = 98.0
					"bell":
						tex_w = 74.0
				var tex_h = tex.get_height() * tex_w / tex.get_width()
				draw_texture_rect(tex, Rect2(s_o.x - tex_w * 0.5, s_o.y + hh - tex_h - 10, tex_w, tex_h), false)

func _draw_effect_badge(effect_type: String, center: Vector2, t_now: float) -> void:
	match effect_type:
		"water_spread":
			var wave = sin(t_now * 3.0) * 2.0
			draw_arc(center, 14 + wave, 0.0, TAU, 28, Color(0.45, 0.75, 1.0, 0.75), 2.0)
			draw_arc(center, 24 + wave, 0.0, TAU, 28, Color(0.3, 0.55, 0.9, 0.45), 1.5)
		"talisman":
			var paper = PackedVector2Array([
				center + Vector2(-9, -20),
				center + Vector2(9, -18),
				center + Vector2(7, 8),
				center + Vector2(-10, 7),
			])
			draw_colored_polygon(paper, Color(1.0, 0.88, 0.32, 0.95))
			draw_polyline(PackedVector2Array([paper[0], paper[1], paper[2], paper[3], paper[0]]), Color(0.55, 0.12, 0.08, 0.9), 1.5)
			draw_line(center + Vector2(-4, -10), center + Vector2(4, -8), Color(0.65, 0.05, 0.05, 0.9), 1.5)
			draw_line(center + Vector2(-3, -2), center + Vector2(3, 0), Color(0.65, 0.05, 0.05, 0.9), 1.5)
		"rice":
			var ring = PackedVector2Array([
				center + Vector2(0, -18),
				center + Vector2(26, 0),
				center + Vector2(0, 18),
				center + Vector2(-26, 0),
				center + Vector2(0, -18),
			])
			draw_polyline(ring, Color(0.98, 0.93, 0.62, 0.78), 2.0)
		"fire":
			draw_circle(center + Vector2(0, -22), 7.0, Color(1.0, 0.35, 0.08, 0.28))
		"explosion":
			draw_circle(center + Vector2(0, -16), 13.0, Color(1.0, 0.45, 0.0, 0.32))

func _draw_object_ground_art(obj_id: String, center: Vector2, obj_color: Color, t_now: float) -> void:
	var base_alpha = 0.08
	var base_pts = PackedVector2Array([
		center + Vector2(0, -13),
		center + Vector2(34, 0),
		center + Vector2(0, 13),
		center + Vector2(-34, 0),
	])
	draw_colored_polygon(base_pts, Color(0.06, 0.05, 0.04, 0.12))
	var ring_pts = PackedVector2Array([
		center + Vector2(0, -10),
		center + Vector2(28, 0),
		center + Vector2(0, 10),
		center + Vector2(-28, 0),
	])
	draw_colored_polygon(ring_pts, Color(obj_color.r, obj_color.g, obj_color.b, base_alpha))
	draw_polyline(ring_pts, Color(obj_color.r, obj_color.g, obj_color.b, 0.24), 1.3)
	match obj_id:
		"bell":
			var pad = PackedVector2Array([
				center + Vector2(0, -18),
				center + Vector2(42, 0),
				center + Vector2(0, 18),
				center + Vector2(-42, 0),
			])
			draw_colored_polygon(pad, Color(0.22, 0.13, 0.06, 0.28))
			draw_polyline(pad, Color(0.72, 0.54, 0.22, 0.45), 1.6)
			var pulse = 0.25 + 0.12 * sin(t_now * 4.0)
			draw_circle(center + Vector2(0, -2), 8.0, Color(1.0, 0.78, 0.22, pulse))
		"rice_bag":
			for grain_i in range(14):
				var gx = sin(float(grain_i) * 1.9) * 32.0
				var gy = cos(float(grain_i) * 1.4) * 11.0
				draw_circle(center + Vector2(gx, gy), 2.0, Color(0.96, 0.92, 0.70, 0.58))
		"brazier":
			draw_circle(center, 11.0, Color(1.0, 0.34, 0.05, 0.12))
func _draw_overlay() -> void:
	if state == null or state.map == null:
		return
	var hw = TILE_W * 0.5
	var hh = TILE_H * 0.5
	_draw_enemy_danger_range(hw, hh)
	for reach_pos in reachable_tiles:
		var vc_r = _visual_coord(reach_pos.x, reach_pos.y)
		var s_r = _grid_origin + cart_to_iso(vc_r.x, vc_r.y)
		var pts_r = PackedVector2Array([s_r + Vector2(0, -hh), s_r + Vector2(hw, 0), s_r + Vector2(0, hh), s_r + Vector2(-hw, 0)])
		_overlay_layer.draw_colored_polygon(pts_r, Color(0.18, 0.95, 0.45, 0.14))
		_overlay_layer.draw_polyline(PackedVector2Array([pts_r[0], pts_r[1], pts_r[2], pts_r[3], pts_r[0]]), Color(0.35, 1.0, 0.65, 0.30), 1.0)

	for target_pos_hl in target_tiles:
		var vc_t = _visual_coord(target_pos_hl.x, target_pos_hl.y)
		var s_t = _grid_origin + cart_to_iso(vc_t.x, vc_t.y)
		var pts_t = PackedVector2Array([s_t + Vector2(0, -hh), s_t + Vector2(hw, 0), s_t + Vector2(0, hh), s_t + Vector2(-hw, 0)])
		_overlay_layer.draw_colored_polygon(pts_t, Color(0.24, 0.56, 1.0, 0.17))
		_overlay_layer.draw_polyline(PackedVector2Array([pts_t[0], pts_t[1], pts_t[2], pts_t[3], pts_t[0]]), Color(0.50, 0.78, 1.0, 0.42), 1.3)

	for damage_pos_hl in damage_tiles:
		var vc_d = _visual_coord(damage_pos_hl.x, damage_pos_hl.y)
		var s_d = _grid_origin + cart_to_iso(vc_d.x, vc_d.y)
		var pts_d = PackedVector2Array([s_d + Vector2(0, -hh), s_d + Vector2(hw, 0), s_d + Vector2(0, hh), s_d + Vector2(-hw, 0)])
		_overlay_layer.draw_colored_polygon(pts_d, Color(1, 0.22, 0.18, 0.22))

	_draw_noise_fields(hw, hh)
	_draw_enemy_intents(hw, hh)

	for hpos in _hover_range_tiles:
		var vc_h = _visual_coord(hpos.x, hpos.y)
		var s_h = _grid_origin + cart_to_iso(vc_h.x, vc_h.y)
		var pts_h = PackedVector2Array([s_h + Vector2(0, -hh), s_h + Vector2(hw, 0), s_h + Vector2(0, hh), s_h + Vector2(-hw, 0)])
		_overlay_layer.draw_polyline(PackedVector2Array([pts_h[0], pts_h[1], pts_h[2], pts_h[3], pts_h[0]]), Color(1.0, 0.78, 0.18, 0.48), 1.6)

	if state.selected_unit:
		for n in state.map.get_neighbors(state.selected_unit.position):
			var nobj = state.map.get_object(n.x, n.y)
			if nobj != "":
				var odef_g = state.map.objects_data.get(nobj, {})
				if odef_g.get("interact", []).size() > 0:
					var vc_g = _visual_coord(n.x, n.y)
					var s_g = _grid_origin + cart_to_iso(vc_g.x, vc_g.y)
					var pts_g = PackedVector2Array([s_g + Vector2(0, -hh), s_g + Vector2(hw, 0), s_g + Vector2(0, hh), s_g + Vector2(-hw, 0)])
					_overlay_layer.draw_polyline(PackedVector2Array([pts_g[0], pts_g[1], pts_g[2], pts_g[3], pts_g[0]]), Color(1, 0.85, 0.3, 0.48), 1.5)

	if hovered_tile.x >= 0 and state.map.in_bounds(hovered_tile):
		var vc = _visual_coord(hovered_tile.x, hovered_tile.y)
		var s = _grid_origin + cart_to_iso(vc.x, vc.y)
		var pts = PackedVector2Array([s + Vector2(0, -hh), s + Vector2(hw, 0), s + Vector2(0, hh), s + Vector2(-hw, 0)])
		_overlay_layer.draw_colored_polygon(pts, Color(0.72, 0.90, 1.0, 0.10))
		_overlay_layer.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0.82, 0.96, 1.0, 0.40), 1.2)

	for wave in _noise_waves:
		var pos: Vector2i = wave.get("pos", Vector2i(-1, -1))
		if not state.map.in_bounds(pos):
			continue
		var vc_n = _visual_coord(pos.x, pos.y)
		var center = _grid_origin + cart_to_iso(vc_n.x, vc_n.y)
		var duration = float(wave.get("duration", 1.0))
		var progress = 1.0 - clampf(float(wave.get("ttl", 0.0)) / duration, 0.0, 1.0)
		var radius = lerpf(16.0, float(wave.get("volume", 3)) * 34.0, progress)
		var alpha = 0.75 * (1.0 - progress)
		var ring = PackedVector2Array([
			center + Vector2(0, -radius * 0.5),
			center + Vector2(radius, 0),
			center + Vector2(0, radius * 0.5),
			center + Vector2(-radius, 0),
			center + Vector2(0, -radius * 0.5),
		])
		_overlay_layer.draw_polyline(ring, Color(1.0, 0.75, 0.2, alpha), 3.0)

func _draw_noise_fields(hw: float, hh: float) -> void:
	if state == null or state.noise_events.is_empty():
		return
	var t_now = Time.get_ticks_msec() * 0.001
	var combined = {}
	for event in state.noise_events:
		var noise_map: Dictionary = event.get("noise_map", {})
		for pos in noise_map.keys():
			combined[pos] = maxi(int(combined.get(pos, 0)), int(noise_map[pos]))
	for pos in combined.keys():
		if not state.map.in_bounds(pos):
			continue
		var value = int(combined[pos])
		if value <= 0:
			continue
		var center = _tile_center(pos)
		var pts = PackedVector2Array([
			center + Vector2(0, -hh),
			center + Vector2(hw, 0),
			center + Vector2(0, hh),
			center + Vector2(-hw, 0),
		])
		var alpha = clampf(0.06 + value * 0.035, 0.08, 0.24)
		_overlay_layer.draw_colored_polygon(pts, Color(1.0, 0.68, 0.12, alpha))
		var closed_pts = PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]])
		_overlay_layer.draw_polyline(closed_pts, Color(1.0, 0.76, 0.2, clampf(alpha + 0.14, 0.18, 0.42)), 1.5)
	for event in state.noise_events:
		var origin: Vector2i = event.get("pos", Vector2i(-1, -1))
		if not state.map.in_bounds(origin):
			continue
		var age = state.turn_count - int(event.get("turn", state.turn_count))
		var remaining = maxi(1, int(event.get("duration", 1)) - age)
		var pulse = 0.5 + 0.5 * sin(t_now * 5.0)
		var center = _tile_center(origin) + Vector2(0, -18)
		_overlay_layer.draw_circle(center, 8.0 + pulse * 4.0, Color(1.0, 0.74, 0.16, 0.18))
		for i in range(remaining):
			_overlay_layer.draw_circle(center + Vector2(-6 + i * 6, -12), 2.8, Color(1.0, 0.9, 0.35, 0.9))

func _draw_enemy_intents(hw: float, hh: float) -> void:
	if _overlay_layer == null:
		return
	for intent in _enemy_intents:
		var kind = intent.get("type", "")
		if kind == "move":
			var path: Array = intent.get("path", [])
			if path.size() < 2:
				continue
			var intent_style = intent.get("intent_style", "move")
			var outer_color = Color(0.15, 0.85, 1.0, 0.9)
			var inner_color = Color(1.0, 0.95, 0.35, 0.95)
			if intent_style == "fear":
				outer_color = Color(0.78, 0.32, 1.0, 0.9)
				inner_color = Color(0.95, 0.74, 1.0, 0.95)
			elif intent_style == "search":
				outer_color = Color(1.0, 0.48, 0.08, 0.9)
				inner_color = Color(1.0, 0.82, 0.25, 0.95)
			elif intent_style == "rage":
				outer_color = Color(1.0, 0.1, 0.05, 0.9)
				inner_color = Color(1.0, 0.42, 0.18, 0.95)
			var points = PackedVector2Array()
			for step in path:
				points.append(_tile_center(step) + Vector2(0, -16))
			_overlay_layer.draw_polyline(points, outer_color, 5.0)
			_overlay_layer.draw_polyline(points, inner_color, 2.0)
			for i in range(points.size()):
				var radius = 4.0 if i < points.size() - 1 else 7.0
				_overlay_layer.draw_circle(points[i], radius, inner_color)
			_draw_overlay_arrow(points[points.size() - 2], points[points.size() - 1], inner_color, 2.0)
		elif kind == "attack":
			var from_pos: Vector2i = intent.get("from", Vector2i(-1, -1))
			var to_pos: Vector2i = intent.get("to", Vector2i(-1, -1))
			if not state.map.in_bounds(from_pos) or not state.map.in_bounds(to_pos):
				continue
			var behavior = intent.get("behavior", "melee")
			var attack_color = Color(1.0, 0.22, 0.12, 0.95)
			if behavior == "ranged":
				attack_color = Color(1.0, 0.56, 0.08, 0.95)
			elif behavior == "mage":
				attack_color = Color(0.78, 0.32, 1.0, 0.95)
			var start = _tile_center(from_pos) + Vector2(0, -42)
			var finish = _tile_center(to_pos) + Vector2(0, -34)
			_draw_overlay_arrow(start, finish, attack_color, 4.0)
			var target_center = _tile_center(to_pos)
			var target_pts = PackedVector2Array([
				target_center + Vector2(0, -hh * 0.92),
				target_center + Vector2(hw * 0.82, 0),
				target_center + Vector2(0, hh * 0.92),
				target_center + Vector2(-hw * 0.82, 0),
			])
			_overlay_layer.draw_colored_polygon(target_pts, Color(attack_color.r, attack_color.g, attack_color.b, 0.28))
			var target_line = PackedVector2Array([target_pts[0], target_pts[1], target_pts[2], target_pts[3], target_pts[0]])
			_overlay_layer.draw_polyline(target_line, attack_color, 3.0)

	# Draw inventory placement tiles (green)
	if not state.inventory_target_tiles.is_empty():
		for t in state.inventory_target_tiles:
			var vc = _visual_coord(t.x, t.y)
			var center = _grid_origin + cart_to_iso(vc.x, vc.y)
			var inv_pts = PackedVector2Array([
				center + Vector2(0, -hh * 0.88),
				center + Vector2(hw * 0.78, 0),
				center + Vector2(0, hh * 0.88),
				center + Vector2(-hw * 0.78, 0),
			])
			_overlay_layer.draw_colored_polygon(inv_pts, Color(0.2, 1.0, 0.5, 0.14))
			var inv_line = PackedVector2Array([inv_pts[0], inv_pts[1], inv_pts[2], inv_pts[3], inv_pts[0]])
			_overlay_layer.draw_polyline(inv_line, Color(0.2, 1.0, 0.5, 0.55), 1.8)

func _draw_enemy_danger_range(hw: float, hh: float) -> void:
	if not _danger_range_enabled or state == null or state.map == null or _overlay_layer == null:
		return
	var seen := {}
	for enemy in state.get_alive_units("enemy"):
		for pos in _enemy_threat_tiles(enemy):
			seen[pos] = true
	for pos in seen.keys():
		var vc = _visual_coord(pos.x, pos.y)
		var s = _grid_origin + cart_to_iso(vc.x, vc.y)
		var pts = PackedVector2Array([
			s + Vector2(0, -hh * 0.86),
			s + Vector2(hw * 0.76, 0),
			s + Vector2(0, hh * 0.86),
			s + Vector2(-hw * 0.76, 0),
		])
		_overlay_layer.draw_colored_polygon(pts, Color(1.0, 0.18, 0.14, 0.075))
		_overlay_layer.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(1.0, 0.30, 0.22, 0.18), 0.9)

func _draw_overlay_arrow(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	if _overlay_layer == null:
		return
	var delta = to - from
	if delta.length() < 1.0:
		return
	_overlay_layer.draw_line(from, to, color, width)
	var dir = delta.normalized()
	var side = Vector2(-dir.y, dir.x)
	var tip = PackedVector2Array([
		to,
		to - dir * 18.0 + side * 8.0,
		to - dir * 18.0 - side * 8.0,
	])
	_overlay_layer.draw_colored_polygon(tip, color)

func _input(event: InputEvent) -> void:
	if enemy_acting and event is InputEventMouseMotion:
		return
	if event is InputEventMouseButton:
		# The battle camera is fixed-scale; player input can only pan the view.
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			return
		if event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed:
			return
		# Left click: drag to pan, small movement = click select (handled on release)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_drag_start = event.position
				_drag_offset_start = _cam_offset
				_click_pos = event.position
				_click_time = Time.get_ticks_msec()
			else:
				_dragging = false
				var drag_dist = (event.position - _click_pos).length()
				if drag_dist < _drag_threshold and not _is_ui_click(_click_pos):
					var grid = screen_to_grid(_click_pos)
					if state.map.in_bounds(grid):
						on_tile_click(grid)
					else:
						clear_selection()
			return
		# Right click: cancel inventory/card selection
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if state.selected_inventory_index >= 0:
				state.selected_inventory_index = -1
				state.inventory_target_tiles = []
				_queue_overlay_redraw()
				if _panel_mode == _ITEM_MODE:
					refresh_inventory_ui()
				return

	if event is InputEventKey:
		if event.pressed:
			if event.keycode == KEY_Q or event.keycode == KEY_E:
				return

	if event is InputEventMouseMotion:
		if _dragging:
			_cam_offset = _drag_offset_start + (_drag_start - event.position)
			_update_camera()
			return
		var grid = screen_to_grid(event.position)
		if state.map.in_bounds(grid):
			hovered_tile = grid
			damage_tiles = _calc_damage_preview(grid)
			_update_hover_info(grid, event.position)
		else:
			hovered_tile = Vector2i(-1, -1)
			damage_tiles = []
			_hover_range_tiles = []
			if _hover_info_panel:
				_hover_info_panel.visible = false
		_queue_overlay_redraw()

	if enemy_acting:
		return

func _is_ui_click(click_pos: Vector2) -> bool:
	if _interaction_menu != null and is_instance_valid(_interaction_menu):
		var menu_rect = Rect2(_interaction_menu.global_position, _interaction_menu.size)
		if menu_rect.has_point(click_pos):
			return true
	var controls = [
		$BottomUI/HandPanel,
		$BottomUI/TabButtons,
		$BottomUI/CardArea if $BottomUI/CardArea.visible else null,
		$BottomUI/ItemArea if $BottomUI/ItemArea.visible else null,
		_stats_panel if _stats_panel != null else null,
		_skill_desc_panel if _skill_desc_panel != null and _skill_desc_panel.visible else null,
		_party_bar if _party_bar != null else null,
		_hover_info_panel if _hover_info_panel != null and _hover_info_panel.visible else null,
		_turn_order_panel if _turn_order_panel != null else null,
		_objective_panel if _objective_panel != null else null,
		_side_status_panel if _side_status_panel != null else null,
		_top_system_bar if _top_system_bar != null else null,
		$HUD/SwitchBtn if $HUD/SwitchBtn.visible else null,
	]
	for control in controls:
		if control == null:
			continue
		if Rect2(control.global_position, control.size).has_point(click_pos):
			return true
	var end_btn: Button = $HUD/EndTurnBtn
	var end_rect = Rect2(end_btn.global_position, end_btn.size)
	return end_rect.has_point(click_pos)

func _setup_hover_info_panel() -> void:
	_hover_info_panel = Panel.new()
	_hover_info_panel.visible = false
	_hover_info_panel.z_index = 1000
	_hover_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_info_panel.add_theme_stylebox_override("panel", _make_clean_panel_style(UI_GOLD, UI_BG, 6, 1))
	_hover_info_panel.size = Vector2(340, 154)
	_hover_info_panel.position = Vector2(1210, 820)
	$HUD.add_child(_hover_info_panel)

	_hover_info_label = Label.new()
	_hover_info_label.position = Vector2(14, 12)
	_hover_info_label.size = _hover_info_panel.size - Vector2(28, 24)
	_hover_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hover_info_label.add_theme_font_size_override("font_size", 13)
	_hover_info_label.add_theme_color_override("font_color", UI_TEXT_WARM)
	_hover_info_panel.add_child(_hover_info_label)

func _estimate_hover_text_lines(lines: Array, max_units_per_line: int = 46) -> int:
	var visual_lines = 0
	for raw_line in lines:
		var line = str(raw_line)
		var units = 0
		for index in range(line.length()):
			units += 2 if line.unicode_at(index) > 127 else 1
		visual_lines += maxi(1, ceili(float(units) / float(max_units_per_line)))
	return visual_lines

func _update_hover_info(pos: Vector2i, screen_pos: Vector2) -> void:
	if _hover_info_panel == null or _hover_info_label == null:
		return
	var lines = ["地形 / 物品"]
	var terrain = state.map.get_terrain(pos.x, pos.y)
	var tdef = state.map.terrains_data.get(terrain, {})
	lines.append("格子: (%d, %d)  %s" % [pos.x, pos.y, tdef.get("name", terrain)])
	lines.append("通行: " + ("可通行" if state.map.is_walkable(pos) else "不可通行"))
	var tags = state.map.get_tags(pos.x, pos.y).keys()
	if tags.size() > 0:
		lines.append("标签: " + ", ".join(tags))
	var noise_info = _get_noise_info_at(pos)
	if not noise_info.is_empty():
		lines.append("噪音: 强度%d  剩余%d回合" % [int(noise_info.get("value", 0)), int(noise_info.get("remaining", 1))])
	if state.map.has_tag(pos.x, pos.y, "lethal"):
		lines.append("危险: 推入或拉入会坠落死亡")
	var obj_id = state.map.get_object(pos.x, pos.y)
	_hover_range_tiles = []
	if obj_id != "":
		var odef = state.map.objects_data.get(obj_id, {})
		lines.append("物品: " + _object_display_name(obj_id))
		var action_names = []
		for action in odef.get("interact", []):
			action_names.append(_action_display_name(action))
		if not action_names.is_empty():
			lines.append("互动: " + " / ".join(action_names))
			_hover_range_tiles = state.map.get_neighbors(pos)
		if obj_id == "explosive_barrel":
			lines.append("提示: 可被点火或火焰技能引爆")
			lines.append("爆炸: 造成高伤害并点燃周围")
		elif obj_id == "coffin":
			lines.append("提示: 开启棺材会大幅提升灵气")
	var effects = state.map.get_effects(pos.x, pos.y)
	if not effects.is_empty():
		var eff_names = []
		for eff in effects:
			eff_names.append(_effect_display_name(str(eff.type)))
		lines.append("场地效果: " + ", ".join(eff_names))
		for eff in effects:
			lines.append("  " + _effect_rule_summary(str(eff.type), int(eff.get("duration", 0))))
	var occ_id = state.map.get_occupant_id(pos)
	if occ_id != "":
		var unit = state.get_unit_by_id(occ_id)
		if unit != null:
			lines.append("单位: %s  HP %d/%d" % [unit.name, unit.current_hp, unit.max_hp])
			if unit.traits.size() > 0:
				var trait_names = []
				for unit_trait in unit.traits:
					trait_names.append(str(unit_trait.get("name", unit_trait.get("id", ""))))
				lines.append("特性: " + " / ".join(trait_names))
			if unit.faction == "enemy":
				var behavior = _get_behavior(unit)
				var range_limit = _enemy_attack_range(unit)
				var profile = unit.ai_profile
				lines.append("敌人类型: " + _enemy_behavior_display_name(behavior))
				lines.append("威胁: 攻击范围 %d 格" % range_limit)
				var fear_tags = profile.get("fearTags", [])
				if not fear_tags.is_empty():
					lines.append("害怕: " + _display_tag_list(fear_tags))
				var hearing = int(profile.get("noiseHearing", 0))
				if hearing > 0:
					lines.append("听觉: %d 格，可被噪音诱导" % hearing)
				var preferred = profile.get("preferredTags", [])
				if not preferred.is_empty():
					lines.append("偏好: " + _display_tag_list(preferred))
				_hover_range_tiles = _enemy_threat_tiles(unit)
	_hover_info_label.text = "\n".join(lines)
	var viewport_size = get_viewport_rect().size
	var visual_lines = _estimate_hover_text_lines(lines)
	var panel_height = clampf(28.0 + visual_lines * 20.0, 112.0, viewport_size.y - 32.0)
	_hover_info_panel.size = Vector2(340, panel_height)
	for child in _hover_info_panel.get_children():
		if child is Control and child.name == "GeneratedBackdrop":
			child.size = _hover_info_panel.size
	_hover_info_label.size = _hover_info_panel.size - Vector2(28, 24)
	var panel_pos = screen_pos + Vector2(22, 18)
	if screen_pos == Vector2.ZERO:
		panel_pos = Vector2(viewport_size.x - _hover_info_panel.size.x - 28, viewport_size.y - _hover_info_panel.size.y - 150)
	if panel_pos.x + _hover_info_panel.size.x > viewport_size.x - 16:
		panel_pos.x = screen_pos.x - _hover_info_panel.size.x - 22
	if panel_pos.y + _hover_info_panel.size.y > viewport_size.y - 16:
		panel_pos.y = screen_pos.y - _hover_info_panel.size.y - 18
	panel_pos.x = clampf(panel_pos.x, 16.0, viewport_size.x - _hover_info_panel.size.x - 16.0)
	panel_pos.y = clampf(panel_pos.y, 16.0, viewport_size.y - _hover_info_panel.size.y - 16.0)
	_hover_info_panel.position = panel_pos
	_hover_info_panel.visible = true

func _refresh_default_terrain_info() -> void:
	if state == null or state.map == null:
		return
	var player = _get_active_player()
	if not player.is_empty():
		_update_hover_info(player.unit.position, Vector2.ZERO)

func _get_noise_info_at(pos: Vector2i) -> Dictionary:
	var best_value = 0
	var best_remaining = 0
	for event in state.noise_events:
		var noise_map: Dictionary = event.get("noise_map", {})
		var value = int(noise_map.get(pos, 0))
		if value <= best_value:
			continue
		var age = state.turn_count - int(event.get("turn", state.turn_count))
		var remaining = maxi(1, int(event.get("duration", 1)) - age)
		best_value = value
		best_remaining = remaining
	if best_value <= 0:
		return {}
	return {"value": best_value, "remaining": best_remaining}

func _display_tag_list(tags: Array) -> String:
	var names = []
	for tag in tags:
		names.append(_tag_display_name(str(tag)))
	return " / ".join(names)

func _tag_display_name(tag: String) -> String:
	return {
		"burning": "火焰",
		"light": "光",
		"seal_point": "封印点",
		"anti_spirit": "糯米/驱邪",
		"talisman": "符纸",
		"spirit_block": "墨线",
		"water": "水域",
		"wet": "水渍",
	}.get(tag, tag)

func _object_display_name(obj_id: String) -> String:
	return {
		"brazier": "火盆",
		"water_barrel": "水桶",
		"rice_bag": "米袋",
		"bell": "铃铛",
		"door": "门",
		"coffin": "棺材",
		"explosive_barrel": "炸药桶",
	}.get(obj_id, obj_id)

func _action_display_name(action: String) -> String:
	return {
		"push": "推",
		"push_over": "推倒",
		"ring": "敲响",
		"open": "开启",
		"close": "关闭",
		"ignite": "点燃",
	}.get(action, action)

func _enemy_behavior_display_name(behavior: String) -> String:
	return {
		"melee": "近战",
		"tank": "重装近战",
		"ranged": "远程",
		"mage": "法术",
	}.get(behavior, behavior)

func _calc_damage_preview(hover_pos: Vector2i) -> Array:
	if state.selected_unit == null:
		return []
	var card_data = _selected_action_card_data()
	if card_data.is_empty():
		return []
	if card_data.get("targetType", "") != "area_3x3":
		return []
	var is_valid = false
	for t in target_tiles:
		if t == hover_pos:
			is_valid = true
			break
	if not is_valid:
		return []
	var area_size = card_data.get("areaSize", 1)
	var result = []
	for dr in range(-area_size, area_size + 1):
		for dc in range(-area_size, area_size + 1):
			var np = hover_pos + Vector2i(dc, dr)
			if state.map.in_bounds(np):
				result.append(np)
	return result

func _selected_action_card_data() -> Dictionary:
	if state.selected_unit == null:
		return {}
	var player = state.get_player_for_unit(state.selected_unit.id)
	if player.is_empty():
		return {}
	if state.selected_card_index >= 0 and state.selected_card_index < player.hand.size:
		return player.hand.get_card(state.selected_card_index)
	if state.selected_inventory_index >= 0:
		var inv = player.get("inventory_ref", null)
		if inv == null:
			return {}
		var item = inv.get_item(state.selected_inventory_index)
		var card_id = str(item.get("card_id", ""))
		if card_id != "":
			return Card.get_card(card_id)
	return {}

func on_tile_click(pos: Vector2i) -> void:
	if state.current_turn != "player":
		return

	# Inventory placement targeting
	if state.selected_unit and state.selected_inventory_index >= 0:
		var is_target = false
		for t in state.inventory_target_tiles:
			if t == pos:
				is_target = true
				break
		if is_target:
			_use_selected_inventory_item(pos)
			return
		# Cancel inventory selection
		state.selected_inventory_index = -1
		state.inventory_target_tiles = []
		_queue_overlay_redraw()
		return

	# Card targeting
	if state.selected_unit and state.selected_card_index >= 0:
		var is_target = false
		for t in target_tiles:
			if t == pos:
				is_target = true
				break
		if is_target:
			play_selected_card(pos)
			return
		# Cancel card
		state.selected_card_index = -1
		target_tiles = []
		damage_tiles = []
		_queue_overlay_redraw()
		return

	# Click on player unit -> select
	var occ_id = state.map.get_occupant_id(pos)
	if occ_id != "":
		var unit = state.get_unit_by_id(occ_id)
		if unit and unit.faction == "player" and unit.is_alive:
			select_unit(unit)
			_show_stats_panel(unit)
			return
		if unit and unit.is_alive:
			clear_selection()
			_show_stats_panel(unit)
			return

	# Movement
	if state.selected_unit:
		var is_reachable = false
		for t in reachable_tiles:
			if t == pos:
				is_reachable = true
				break
		if is_reachable:
			move_unit(state.selected_unit, pos)
			return

		# Object interaction
		var obj_id = state.map.get_object(pos.x, pos.y)
		if obj_id != "":
			_handle_object_click(pos, obj_id)
			return

	clear_selection()

func select_unit(unit: Unit) -> void:
	if state.selected_card_index >= 0:
		return
	state.selected_unit = unit
	if unit.faction == "player":
		_show_stats_panel(unit)
		$BottomUI/CardArea.visible = _panel_mode == _SPELL_MODE
		$BottomUI/ItemArea.visible = _panel_mode == _ITEM_MODE
	if state.is_unit_skipped(unit.id):
		reachable_tiles = []
		_queue_overlay_redraw()
		state.emit_signal("hand_changed")
		return
	var player = state.get_player_for_unit(unit.id)
	if not player.is_empty() and unit.can_move:
		reachable_tiles = Pathfinding.get_reachable_tiles(state.map, unit.position, mini(unit.remaining_move, state.team_ap))
	else:
		reachable_tiles = []

	if not player.is_empty() and state.selected_card_index >= 0:
		var card_data = player.hand.get_card(state.selected_card_index)
		if not card_data.is_empty():
			target_tiles = CardResolver.get_valid_targets(card_data, unit, state.map, state.all_units)

	_queue_overlay_redraw()
	if _panel_mode == _ITEM_MODE:
		refresh_inventory_ui()
	state.emit_signal("hand_changed")

func clear_selection() -> void:
	state.selected_unit = null
	state.selected_card_index = -1
	state.selected_inventory_index = -1
	state.inventory_target_tiles = []
	reachable_tiles = []
	target_tiles = []
	damage_tiles = []
	if _stats_panel != null:
		_stats_panel.visible = false
	if _skill_desc_panel != null:
		_skill_desc_panel.visible = false
	$BottomUI/CardArea.visible = false
	$BottomUI/ItemArea.visible = false
	_hide_card_tooltip()
	_queue_overlay_redraw()
	_refresh_party_bar()
	refresh_card_ui()
	if _panel_mode == _ITEM_MODE:
		refresh_inventory_ui()

func move_unit(unit: Unit, pos: Vector2i) -> void:
	if state.is_unit_skipped(unit.id):
		return
	var path = Pathfinding.find_path(state.map, unit.position, pos)
	if path.size() < 2:
		return
	var move_cost = _path_move_cost(path)
	if move_cost <= 0 or move_cost > unit.remaining_move:
		return
	if not state.spend_ap(move_cost):
		return
	var from = unit.position
	state.map.set_occupant(from, null)
	unit.move_to(pos)
	unit.spend_move(move_cost)
	state.map.set_occupant(pos, unit.id)
	state.emit_signal("unit_moved", unit.id, from, pos)
	refresh_units()
	reachable_tiles = []
	_queue_overlay_redraw()

func _path_move_cost(path: Array) -> int:
	var total = 0
	for i in range(1, path.size()):
		total += state.map.get_move_cost(path[i])
	return total

func play_selected_card(pos: Vector2i) -> void:
	var unit = state.selected_unit
	if state.is_unit_skipped(unit.id):
		return
	var player = state.get_player_for_unit(unit.id)
	if player.is_empty():
		return
	var card_data = player.hand.get_card(state.selected_card_index)
	if card_data.is_empty():
		return
	if not turn_manager.can_play_card(int(card_data.get("cost", 1))):
		return

	var result = CardResolver.play_card(card_data, unit, pos, state.map, state.all_units, state)
	if result.success:
		turn_manager.play_card(player, state.selected_card_index)

		if result.get("dodged", false):
			var dodge_target = _find_unit_at(pos)
			if dodge_target:
				_show_floating_text(dodge_target, "MISS", Color(1, 1, 0.3))

		for affected in result.get("affected_units", []):
			if int(affected.get("damage", 0)) > 0:
				state.emit_signal("unit_damaged", affected.unit_id, int(affected.damage))

		for effect in result.effects:
			if effect.get("heal_amount", 0) > 0:
				var target = _find_unit_at(pos)
				if target:
					state.emit_signal("unit_healed", target.id, effect.heal_amount)

		if result.moved_unit:
			state.emit_signal("unit_moved", unit.id, result.moved_unit.from, result.moved_unit.to)


		if result.get("pulled_target") != null:
			var pt = result.pulled_target
			state.emit_signal("unit_moved", pt.unit_id, pt.from, pt.to)
		for kid in result.killed:
			state.emit_signal("unit_died", kid)

		# Counter-attack
		if card_data.get("cardType", "") == "attack":
			var target = _find_unit_at(pos)
			if target and target.is_alive and _is_adjacent(unit.position, target.position):
				if _try_dodge(unit):
					_show_floating_text(unit, "MISS", Color(1, 1, 0.3))
				else:
					var counter = _calc_damage(target, unit)
					unit.take_damage(counter)
					state.emit_signal("unit_damaged", unit.id, counter)
					if not unit.is_alive:
						state.map.set_occupant(unit.position, null)
						state.emit_signal("unit_died", unit.id)

		state.emit_signal("card_played", unit.id, card_data.id, result.get("targets", [pos]))

	state.selected_card_index = -1
	target_tiles = []
	damage_tiles = []
	refresh_units()
	_queue_scene_redraw()
	var battle_result = state.is_battle_over()
	if battle_result == "won":
		state.emit_signal("battle_won")
	elif battle_result == "lost":
		state.emit_signal("battle_lost")

func _on_end_turn_pressed() -> void:
	if state.current_turn != "player" or enemy_acting:
		return
	_release_gui_focus()
	turn_manager.end_player_turn()
	reachable_tiles = []
	target_tiles = []
	damage_tiles = []
	state.current_turn = "intent"
	state.emit_signal("turn_start", "intent")
	enemy_acting = true
	_prepare_enemy_turn_plan()
	_queue_overlay_redraw()
	if _emit_battle_result_if_over():
		return
	$EnemyTimer.start(_battle_delay(1.05))

func _on_spell_btn_pressed() -> void:
	_panel_mode = _SPELL_MODE
	_update_tab_button_colors()
	state.selected_card_index = -1
	state.selected_inventory_index = -1
	state.inventory_target_tiles = []
	target_tiles = []
	damage_tiles = []
	if state.selected_unit == null or state.selected_unit.faction != "player":
		$BottomUI/CardArea.visible = false
		$BottomUI/ItemArea.visible = false
		_queue_overlay_redraw()
		return
	$BottomUI/CardArea.visible = true
	$BottomUI/ItemArea.visible = false
	refresh_card_ui()
	_queue_overlay_redraw()

func _on_item_btn_pressed() -> void:
	_panel_mode = _ITEM_MODE
	_update_tab_button_colors()
	state.selected_card_index = -1
	state.selected_inventory_index = -1
	state.inventory_target_tiles = []
	target_tiles = []
	damage_tiles = []
	if state.selected_unit == null or state.selected_unit.faction != "player":
		$BottomUI/CardArea.visible = false
		$BottomUI/ItemArea.visible = false
		_queue_overlay_redraw()
		return
	$BottomUI/CardArea.visible = false
	$BottomUI/ItemArea.visible = true
	refresh_inventory_ui()
	_queue_overlay_redraw()

func _update_tab_button_colors() -> void:
	var spell_btn = $BottomUI/TabButtons/SpellBtn
	var item_btn = $BottomUI/TabButtons/ItemBtn
	if spell_btn == null or item_btn == null:
		return
	var active_color = Color(1.0, 1.0, 1.0, 1.0)
	var inactive_color = Color(0.56, 0.58, 0.62, 0.62)
	_apply_action_button_state(spell_btn, _panel_mode == _SPELL_MODE, active_color, inactive_color)
	_apply_action_button_state(item_btn, _panel_mode == _ITEM_MODE, active_color, inactive_color)

func _apply_action_button_state(button: Button, active: bool, active_color: Color, inactive_color: Color) -> void:
	var icon = button.get_node_or_null("ActionIcon")
	if icon != null:
		icon.modulate = active_color if active else inactive_color
	var backplate = button.get_node_or_null("ActionBackplate")
	if backplate != null:
		backplate.modulate = Color(1.0, 0.96, 0.78, 0.96) if active else Color(0.78, 0.82, 0.88, 0.72)
	var glow = button.get_node_or_null("ActionGlow")
	if glow != null:
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.18, 0.38, 0.40, 0.28) if active else Color(0.08, 0.10, 0.12, 0.14)
		style.border_color = Color(UI_GOLD_BRIGHT.r, UI_GOLD_BRIGHT.g, UI_GOLD_BRIGHT.b, 0.34 if active else 0.12)
		style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		glow.add_theme_stylebox_override("panel", style)
	var caption = button.get_node_or_null("ActionCaption")
	if caption != null:
		caption.modulate = Color(1, 1, 1, 1.0) if active else Color(1, 1, 1, 0.72)

func _on_enemy_timer_timeout() -> void:
	if state.current_turn == "intent":
		state.current_turn = "enemy"
		state.emit_signal("turn_start", "enemy")
	_execute_next_enemy()

var _enemy_queue: Array = []
var _enemy_turn_started: bool = false

func _prepare_enemy_turn_plan() -> void:
	_enemy_intents = []
	_enemy_queue = []
	_enemy_turn_plan = {}
	if state == null or state.map == null or ai == null:
		return
	_enemy_turn_started = true
	var active_enemies = []
	var alive = []
	for enemy in state.enemies:
		if not enemy.is_alive:
			continue
		alive.append(enemy)
	var ticks = StatusEffectManager.tick_statuses(alive, "turn_start")
	for tick in ticks:
		if tick.get("damage", 0) > 0:
			state.emit_signal("unit_damaged", tick.unit_id, tick.damage)
			var tick_unit = state.get_unit_by_id(tick.unit_id)
			if tick_unit != null and not tick_unit.is_alive:
				state.map.set_occupant(tick_unit.position, null)
				state.emit_signal("unit_died", tick_unit.id)
	for enemy in alive:
		if not enemy.is_alive:
			continue
		var skipped = false
		for tick in ticks:
			if tick.unit_id == enemy.id and tick.get("skipped_turn", false):
				skipped = true
				break
		if skipped:
			continue
		enemy.start_turn()
		active_enemies.append(enemy)
	var context = {
		"map": state.map,
		"players": state.get_alive_units("player"),
		"all_units": state.all_units,
		"noise_events": noise_system.get_recent_events(1) if noise_system != null else state.noise_events,
		"spirit_density": state.spirit_density,
		"turn": state.turn_count,
	}
	_enemy_turn_plan = ai.generate_turn_plan(active_enemies, context)
	_enemy_queue = ai.flatten_plan_actions(_enemy_turn_plan)
	_enemy_intents = ai.generate_intents(_enemy_turn_plan)
	refresh_units()

func _enemy_attack_range(enemy: Unit) -> int:
	return _enemy_attack_range_for_behavior(_get_behavior(enemy))

func _enemy_attack_range_for_behavior(behavior: String) -> int:
	match behavior:
		"ranged":
			return 4
		"mage":
			return 3
		_:
			return 1

func _enemy_threat_tiles(enemy: Unit) -> Array:
	var result = []
	var range_limit = _enemy_attack_range(enemy)
	for dy in range(-range_limit, range_limit + 1):
		var max_dx = range_limit - absi(dy)
		for dx in range(-max_dx, max_dx + 1):
			if dx == 0 and dy == 0:
				continue
			var pos = enemy.position + Vector2i(dx, dy)
			if state.map.in_bounds(pos):
				result.append(pos)
	return result

func _execute_next_enemy() -> void:
	if not _enemy_turn_started:
		_prepare_enemy_turn_plan()

	if _enemy_queue.is_empty():
		_finish_enemy_turn()
		return

	var action: Dictionary = _enemy_queue.pop_front()
	var enemy = state.get_unit_by_id(action.get("unit_id", ""))
	if enemy == null or not enemy.is_alive:
		_execute_next_enemy()
		return

	if action.type == "move" and action.get("target_pos", null) != null:
		var target_pos: Vector2i = action.get("target_pos", Vector2i(-1, -1))
		if not state.map.in_bounds(target_pos):
			_execute_next_enemy()
			return
		if state.map.is_occupied(target_pos):
			_execute_next_enemy()
			return
		var path: Array = action.get("path", [])
		if path.size() < 2 or path[0] != enemy.position or path[path.size() - 1] != target_pos:
			path = Pathfinding.find_path(state.map, enemy.position, target_pos)
		var move_cost = _path_move_cost(path)
		if path.size() < 2 or move_cost > enemy.remaining_move:
			_execute_next_enemy()
			return
		var from = enemy.position
		await _animate_enemy_move(enemy, path)
		state.emit_signal("unit_moved", enemy.id, from, target_pos)
		refresh_units()
		_consume_enemy_intent(enemy.id, "move")
		_queue_overlay_redraw()
		if _emit_battle_result_if_over():
			return

	if action.type == "attack":
		_enemy_attack_from_action(enemy, action)
		refresh_units()
		_consume_enemy_intent(enemy.id, "attack")
		_queue_overlay_redraw()
		if _emit_battle_result_if_over():
			return

	$EnemyTimer.start(_battle_delay(0.35))

func _animate_enemy_move(enemy: Unit, path: Array) -> void:
	if path.size() < 2:
		return
	var current: Vector2i = path[0]
	for i in range(1, path.size()):
		var next_pos: Vector2i = path[i]
		var step_dir = next_pos - current
		enemy.facing = step_dir
		_create_or_update_sprite(enemy)
		_queue_overlay_redraw()
		await _tween_unit_sprite_to(enemy, next_pos, _battle_delay(0.14))
		state.map.set_occupant(current, null)
		enemy.move_to(next_pos, step_dir)
		enemy.spend_move(state.map.get_move_cost(next_pos))
		state.map.set_occupant(next_pos, enemy.id)
		refresh_units()
		current = next_pos

func _tween_unit_sprite_to(unit: Unit, target_pos: Vector2i, duration: float) -> void:
	if not unit_sprites.has(unit.id) or not is_instance_valid(unit_sprites[unit.id]):
		return
	var sprite: Node2D = unit_sprites[unit.id]
	var target_screen = _tile_center(target_pos)
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(sprite, "position", target_screen, duration)
	await tween.finished

func _consume_enemy_intent(unit_id: String, intent_type: String) -> void:
	for i in range(_enemy_intents.size()):
		var intent = _enemy_intents[i]
		if intent.get("unit_id", "") == unit_id and intent.get("type", "") == intent_type:
			_enemy_intents.remove_at(i)
			return

func _enemy_attack_from_action(enemy: Unit, action: Dictionary) -> void:
	var target = state.get_unit_by_id(action.get("target_id", ""))
	if target == null or not target.is_alive or target.faction == "enemy":
		return
	var behavior = action.get("attack_kind", _get_behavior(enemy))
	if _manhattan(enemy.position, target.position) > _enemy_attack_range_for_behavior(behavior):
		return
	if behavior == "mage":
		StatusEffectManager.apply_status(target, "burn", 2)
		_do_enemy_damage(enemy, target, "magic")
		return
	_do_enemy_damage(enemy, target)
	if behavior != "ranged" and target.is_alive and _is_adjacent(enemy.position, target.position):
		var counter = _calc_damage(target, enemy)
		enemy.take_damage(counter)
		state.emit_signal("unit_damaged", enemy.id, counter)
		if not enemy.is_alive:
			state.map.set_occupant(enemy.position, null)
			state.emit_signal("unit_died", enemy.id)

func _enemy_attack(enemy: Unit) -> void:
	var behavior = _get_behavior(enemy)

	if behavior == "ranged":
		var targets = state.get_alive_units("player").filter(func(u): return _manhattan(u.position, enemy.position) <= 4)
		if targets.is_empty():
			return
		var target = targets.reduce(func(a, b): return a if a.current_hp < b.current_hp else b)
		_do_enemy_damage(enemy, target)
		return

	if behavior == "mage":
		var targets = state.get_alive_units("player").filter(func(u): return _manhattan(u.position, enemy.position) <= 3)
		if targets.is_empty():
			return
		var target = targets.reduce(func(a, b): return a if a.current_hp < b.current_hp else b)
		StatusEffectManager.apply_status(target, "burn", 2)
		_do_enemy_damage(enemy, target, "magic")
		return

	# Melee
	for neighbor in state.map.get_neighbors(enemy.position):
		var occ = state.map.get_occupant_id(neighbor)
		if occ == "":
			continue
		var target = state.get_unit_by_id(occ)
		if target == null or target.faction == "enemy" or not target.is_alive:
			continue
		_do_enemy_damage(enemy, target)
		# Counter
		if target.is_alive:
			var counter = _calc_damage(target, enemy)
			enemy.take_damage(counter)
			state.emit_signal("unit_damaged", enemy.id, counter)
			if not enemy.is_alive:
				state.map.set_occupant(enemy.position, null)
				state.emit_signal("unit_died", enemy.id)
		break

func _do_enemy_damage(enemy: Unit, target: Unit, dmg_type: String = "physical") -> void:
	if _try_dodge(target):
		_show_floating_text(target, "MISS", Color(1, 1, 0.3))
		return
	var damage = _calc_damage(enemy, target) if dmg_type == "physical" else maxi(1, enemy.stats.intelligence - int(target.stats.magic_resist * 0.3 * target.get_defense_modifier(enemy.position)))
	target.take_damage(damage)
	state.emit_signal("unit_damaged", target.id, damage)
	if not target.is_alive:
		state.map.set_occupant(target.position, null)
		state.emit_signal("unit_died", target.id)

func _emit_battle_result_if_over() -> bool:
	var result = state.is_battle_over()
	if result == "won":
		$EnemyTimer.stop()
		enemy_acting = false
		_enemy_intents = []
		_enemy_turn_plan = {}
		state.emit_signal("battle_won")
		return true
	if result == "lost":
		$EnemyTimer.stop()
		enemy_acting = false
		_enemy_intents = []
		_enemy_turn_plan = {}
		state.emit_signal("battle_lost")
		return true
	return false

func _finish_enemy_turn() -> void:
	# Tick turn_end for all
	var all = state.get_alive_units()
	var ticks = StatusEffectManager.tick_statuses(all, "turn_end")
	for tick in ticks:
		if tick.get("damage", 0) > 0:
			state.emit_signal("unit_damaged", tick.unit_id, tick.damage)
	refresh_units()

	_enemy_queue = []
	_enemy_intents = []
	_enemy_turn_plan = {}
	enemy_acting = false
	_enemy_turn_started = false
	$EnemyTimer.stop()

	var result = state.is_battle_over()
	if result == "won":
		state.emit_signal("battle_won")
		return
	if result == "lost":
		state.emit_signal("battle_lost")
		return

	# Environment turn: spread effects and tick durations
	state.current_turn = "environment"
	state.emit_signal("turn_start", "environment")
	if terrain_system:
		terrain_system.process_spread(state.map)
		state.map.tick_effects()
	refresh_units()
	_queue_scene_redraw()

	result = state.is_battle_over()
	if result == "won":
		state.emit_signal("battle_won")
		return
	if result == "lost":
		state.emit_signal("battle_lost")
		return

	state.current_turn = "spirit"
	state.emit_signal("turn_start", "spirit")
	if spirit_system != null:
		spirit_system.apply_turn_end_effect()
		spirit_system.modify_density(-1, "turn_tick")
	else:
		state.modify_spirit_density(-1)
	if _emit_battle_result_if_over():
		return

	turn_manager.start_player_turn()

func _get_behavior(enemy) -> String:
	var tid = enemy.template_id if enemy is Unit else str(enemy)
	if enemy is Unit:
		var configured = enemy.ai_profile.get("behavior", "")
		if configured != "":
			return configured
	if tid.find("archer") >= 0: return "ranged"
	if tid.find("knight") >= 0: return "tank"
	if tid.find("mage") >= 0: return "mage"
	if tid == "water_ghost": return "ranged"
	if tid == "red_lady": return "mage"
	if tid == "coffin_lord": return "tank"
	if tid == "jiangshi": return "tank"
	return "melee"

func _calc_damage(attacker: Unit, defender: Unit) -> int:
	return maxi(1, attacker.stats.strength - int(defender.stats.defense * 0.5 * defender.get_defense_modifier(attacker.position)))

func _try_dodge(defender: Unit) -> bool:
	var dodge = state.map.get_terrain_dodge(defender.position)
	if dodge <= 0:
		return false
	return randi() % 100 < dodge

func _is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) == 1

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing JSON file: " + path)
		return {}
	var data = JsonLoader.load_file(path)
	return data if data is Dictionary else {}

func _on_terrain_damage(data: Dictionary) -> void:
	var uid = data.get("unit_id", "")
	var dmg = int(data.get("damage", 0))
	if uid != "" and dmg > 0:
		var unit = state.get_unit_by_id(uid)
		if unit and unit.is_alive:
			unit.take_damage(dmg)
			state.emit_signal("unit_damaged", uid, dmg)
			_show_floating_text(unit, "-%d" % dmg, Color.ORANGE)
			if not unit.is_alive:
				state.map.set_occupant(unit.position, null)
				state.emit_signal("unit_died", uid)
			refresh_units()

func _on_noise_propagated(data: Dictionary) -> void:
	var pos: Vector2i = data.get("origin", data.get("pos", Vector2i(-1, -1)))
	var volume = int(data.get("volume", 3))
	if not state.map.in_bounds(pos):
		return
	_noise_waves.append({
		"pos": pos,
		"volume": volume,
		"ttl": 1.1,
		"duration": 1.1
	})
	var label = "噪音"
	match data.get("source_type", ""):
		"bell":
			label = "铃声"
		"push":
			label = "推撞声"
		"push_over":
			label = "倒地声"
		"explosion", "oil_ignite":
			label = "巨响"
	_show_floating_text_at(pos, label, Color(1.0, 0.75, 0.2))
	_queue_overlay_redraw()

func _on_effect_added_visual(data: Dictionary) -> void:
	var pos: Vector2i = data.get("pos", Vector2i(-1, -1))
	if state == null or state.map == null or not state.map.in_bounds(pos):
		return
	for eff in state.map.get_effects(pos.x, pos.y):
		if eff.type == "fire" or eff.type == "explosion":
			_has_ambient_map_animation = true
			break
	_queue_scene_redraw()

func _handle_object_click(pos: Vector2i, obj_id: String) -> void:
	if state.selected_unit == null:
		return
	if not interaction_system.can_reach(state.selected_unit, pos):
		_show_floating_text_at(pos, "需要相邻", Color(1.0, 0.55, 0.25))
		return
	if state.team_ap < 1:
		_show_floating_text_at(pos, "AP不足", Color(1.0, 0.3, 0.3))
		return
	var odef = state.map.objects_data.get(obj_id, {})
	var actions = odef.get("interact", [])
	_show_interaction_menu(pos, obj_id, actions)

func _show_interaction_menu(pos: Vector2i, obj_id: String, actions: Array) -> void:
	_cancel_interaction()
	_interaction_menu = VBoxContainer.new()
	var vc_m = _visual_coord(pos.x, pos.y)
	var screen_m = _grid_origin + cart_to_iso(vc_m.x, vc_m.y)
	var z = _get_camera_zoom()
	var vp_center = get_viewport_rect().size * 0.5
	var menu_screen = (screen_m - _camera.position) * z + vp_center
	var view_size = get_viewport_rect().size
	_interaction_menu.size = Vector2(120, 0)
	_interaction_menu.set_position(Vector2(
		clampf(menu_screen.x - 60, 8, view_size.x - _interaction_menu.size.x - 8),
		clampf(menu_screen.y - 60, 8, view_size.y - 120 - 8)
	))
	_interaction_menu.add_theme_constant_override("separation", 4)
	var panel_bg = StyleBoxFlat.new()
	panel_bg.bg_color = Color(0.08, 0.08, 0.16, 0.95)
	panel_bg.border_color = Color(0.9, 0.7, 0.2)
	panel_bg.set_border_width_all(2)
	panel_bg.set_corner_radius_all(4)
	_interaction_menu.add_theme_stylebox_override("panel", panel_bg)

	var action_labels = {
		"push": "推", "push_over": "推倒", "ring": "敲响",
		"open": "开启", "close": "关闭", "ignite": "点燃",
	}
	for action in actions:
		var btn = Button.new()
		btn.text = action_labels.get(action, action)
		btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
		var btn_style = StyleBoxFlat.new()
		btn_style.bg_color = Color(0.2, 0.15, 0.08)
		btn_style.set_corner_radius_all(3)
		btn.add_theme_stylebox_override("normal", btn_style)
		var a = action
		btn.pressed.connect(func(): _execute_interaction(pos, obj_id, a))
		_interaction_menu.add_child(btn)

	# Add pickup button for pushable objects if inventory not full
	var player = state.get_player_for_unit(state.selected_unit.id) if state.selected_unit else {}
	var inv = player.get("inventory_ref", null) if not player.is_empty() else null
	var odef = state.map.objects_data.get(obj_id, {})
	if inv != null and not inv.is_full() and odef.get("pushable", false):
		var pickup_btn = Button.new()
		pickup_btn.text = "拾取"
		pickup_btn.add_theme_font_size_override("font_size", 14)
		pickup_btn.add_theme_color_override("font_color", Color(0.3, 1, 0.5))
		var btn_style2 = StyleBoxFlat.new()
		btn_style2.bg_color = Color(0.08, 0.18, 0.08)
		btn_style2.set_corner_radius_all(3)
		pickup_btn.add_theme_stylebox_override("normal", btn_style2)
		pickup_btn.pressed.connect(func(): _execute_pickup(pos, obj_id))
		_interaction_menu.add_child(pickup_btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "x"
	cancel_btn.add_theme_font_size_override("font_size", 12)
	cancel_btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	cancel_btn.pressed.connect(_cancel_interaction)
	_interaction_menu.add_child(cancel_btn)

	_interaction_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	$HUD.add_child(_interaction_menu)

func _execute_interaction(pos: Vector2i, obj_id: String, action: String) -> void:
	_cancel_interaction_menu()
	if state.selected_unit == null:
		return
	if state.is_unit_skipped(state.selected_unit.id):
		return
	match action:
		"push":
			var push_dir = pos - state.selected_unit.position
			if interaction_system.push(state.selected_unit, push_dir):
				_show_floating_text_at(pos + push_dir, "推!", Color(1, 0.85, 0.3))
				refresh_units()
				_queue_scene_redraw()
				_emit_battle_result_if_over()
		"push_over":
			if interaction_system.push_over(state.selected_unit, pos):
				_show_floating_text_at(pos, "推倒!", Color(0.8, 0.7, 0.3))
				refresh_units()
				_queue_scene_redraw()
				_emit_battle_result_if_over()
		"ring", "open", "close", "ignite":
			if interaction_system.interact(state.selected_unit, pos, action):
				var text = "点燃!" if action == "ignite" else action
				_show_floating_text_at(pos, text, Color(0.5, 0.8, 1))
				refresh_units()
				_queue_scene_redraw()
				_emit_battle_result_if_over()

func _cancel_interaction() -> void:
	_cancel_interaction_menu()
	if state.selected_inventory_index >= 0:
		state.selected_inventory_index = -1
		state.inventory_target_tiles = []
		refresh_inventory_ui()
	_queue_overlay_redraw()

func _cancel_interaction_menu() -> void:
	if _interaction_menu and is_instance_valid(_interaction_menu):
		_interaction_menu.queue_free()
	_interaction_menu = null

func _show_floating_text_at(pos: Vector2i, text: String, color: Color) -> void:
	var vc = _visual_coord(pos.x, pos.y)
	var screen = _grid_origin + cart_to_iso(vc.x, vc.y)
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(90, 24)
	label.position = Vector2(screen.x - 45, screen.y - 50)
	label.z_index = 999
	_apply_chinese_font(label)
	add_child(label)
	var tween = create_tween()
	tween.tween_property(label, "position:y", label.position.y - 25, _battle_delay(0.7))
	tween.parallel().tween_property(label, "modulate:a", 0.0, _battle_delay(0.7))
	tween.tween_callback(label.queue_free)

func _find_unit_at(pos: Vector2i) -> Unit:
	for u in state.all_units:
		if u.position == pos and u.is_alive:
			return u
	return null

func _phase_display_name(who: String) -> String:
	var labels = {
		"player": "你的回合",
		"intent": "敌方意图",
		"enemy": "敌方回合",
		"environment": "环境处理",
		"spirit": "灵气流动",
	}
	return labels.get(who, who)

func _phase_display_color(who: String) -> Color:
	var colors = {
		"player": Color(0.267, 1, 0.533),
		"intent": Color(1.0, 0.75, 0.25),
		"enemy": Color(1, 0.267, 0.267),
		"environment": Color(0.35, 0.65, 1.0),
		"spirit": Color(0.75, 0.45, 1.0),
	}
	return colors.get(who, Color(1.0, 0.88, 0.46))

func _refresh_top_status_title(who: String = "") -> void:
	if _turn_order_title == null or state == null:
		return
	var phase = who if who != "" else state.current_turn
	var tier_label = spirit_system.get_tier_label() if spirit_system != null else ""
	_turn_order_title.text = "回合 %d · AP %d/%d · 灵气 %d/10 %s · %s" % [
		state.turn_count,
		state.team_ap,
		state.max_ap,
		state.spirit_density,
		tier_label,
		_phase_display_name(phase),
	]
	_turn_order_title.add_theme_color_override("font_color", _phase_display_color(phase))

# --- Signal handlers ---

func _on_turn_start(who: String) -> void:
	state.selected_card_index = -1
	reachable_tiles = []
	target_tiles = []
	damage_tiles = []
	if who == "player":
		_enemy_intents = []
		_enemy_turn_plan = {}
		_release_gui_focus()
	$HUD/TurnLabel.text = "-- %s --" % _phase_display_name(who)
	$HUD/TurnLabel.add_theme_color_override("font_color", _phase_display_color(who))
	$HUD/TurnLabel.add_theme_font_size_override("font_size", 18)
	_refresh_top_status_title(who)
	if _objective_round_label != null:
		_objective_round_label.text = "回合  %d/15" % state.turn_count
	$HUD/EndTurnBtn.disabled = (who != "player")
	$HUD/EndTurnBtn.modulate = Color(1, 1, 1, 1) if who == "player" else Color(1, 1, 1, 0.3)
	$HUD/TurnCount.text = "回合 %d  AP %d/%d  灵气 %d/10" % [state.turn_count, state.team_ap, state.max_ap, state.spirit_density]
	_refresh_spirit_bar()
	_refresh_turn_order_bar(who)
	_queue_overlay_redraw()

func _release_gui_focus() -> void:
	var focus_owner = get_viewport().gui_get_focus_owner()
	if focus_owner != null:
		focus_owner.release_focus()

func _on_unit_moved(unit_id: String, from: Vector2i, to: Vector2i) -> void:
	refresh_units()
	_queue_overlay_redraw()

func _on_unit_damaged(unit_id: String, damage: int) -> void:
	if damage <= 0:
		return
	var unit = state.get_unit_by_id(unit_id)
	if unit:
		_show_floating_text(unit, "-%d" % damage, Color.RED)
		_show_hit_effect(unit.position)
	refresh_units()

func _on_unit_healed(unit_id: String, amount: int) -> void:
	var unit = state.get_unit_by_id(unit_id)
	if unit:
		_show_floating_text(unit, "+%d" % amount, Color.GREEN)
	refresh_units()

func _on_unit_died(unit_id: String) -> void:
	var unit = state.get_unit_by_id(unit_id)
	if unit != null:
		state.map.set_occupant(unit.position, null)
	var sprite = unit_sprites.get(unit_id)
	if sprite:
		var tween = create_tween()
		tween.tween_property(sprite, "modulate:a", 0.0, 0.3)
		tween.tween_callback(sprite.queue_free)
		unit_sprites.erase(unit_id)
	if spirit_system != null:
		spirit_system.on_unit_died(unit_id)
	refresh_units()
	_refresh_turn_order_bar(state.current_turn)

func _on_energy_changed(current: int, max_val: int) -> void:
	$HUD/APLabel.text = "AP: %d/%d" % [current, max_val]
	_refresh_top_status_title()
	_refresh_active_stats_panel()

func _on_hand_changed() -> void:
	refresh_card_ui()
	if _panel_mode == _ITEM_MODE:
		refresh_inventory_ui()
	_refresh_active_stats_panel()

func _on_card_played(unit_id: String, card_id: String, targets: Array) -> void:
	_queue_overlay_redraw()

func _on_battle_won() -> void:
	_show_reward_screen()

func _on_battle_lost() -> void:
	_show_result("Defeat...", Color(0.667, 0.267, 0.267))

func _show_result(text: String, color: Color) -> void:
	enemy_acting = true
	var overlay = ColorRect.new()
	overlay.color = Color(0.035, 0.050, 0.070, 0.58)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	$HUD.add_child(overlay)

	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 48)
	label.add_theme_color_override("font_color", color)
	label.position = Vector2(540, 350)
	$HUD.add_child(label)

	var restart = Label.new()
	restart.text = "Click to restart"
	restart.add_theme_font_size_override("font_size", 14)
	restart.add_theme_color_override("font_color", Color(0.533, 0.533, 0.667))
	restart.position = Vector2(555, 410)
	$HUD.add_child(restart)

	overlay.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			get_tree().reload_current_scene()
	)


func _show_reward_screen() -> void:
	enemy_acting = true
	var overlay = ColorRect.new()
	overlay.color = Color(0.035, 0.050, 0.070, 0.68)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	$HUD.add_child(overlay)

	var title = Label.new()
	title.text = "战斗胜利！选择一张卡牌加入牌组"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.27, 1, 0.53))
	title.horizontal_alignment = 1
	title.position = Vector2(340, 150)
	title.size = Vector2(600, 40)
	$HUD.add_child(title)

	var all_ids = Card.get_all_ids().filter(func(cid): return Card.get_card(cid).get("cardType", "") != "item")
	var picked = _pick_reward_cards(all_ids, 3)
	var rw = 180
	var rh = 240
	var rspacing = 30
	var total_rw = picked.size() * rw + maxi(0, picked.size() - 1) * rspacing
	var start_rx = (1280 - total_rw) / 2

	for j in range(picked.size()):
		var card_id = picked[j]
		var card_data = Card.get_card(card_id)
		var rcard = Panel.new()
		var rstyle = StyleBoxFlat.new()
		var rarity_colors = {"common": Color(0.3, 0.3, 0.4), "uncommon": Color(0.15, 0.3, 0.2), "rare": Color(0.3, 0.2, 0.1)}
		rstyle.bg_color = rarity_colors.get(card_data.get("rarity", "common"), Color(0.2, 0.2, 0.3))
		rstyle.border_color = Color(0.5, 0.5, 0.8)
		rstyle.set_border_width_all(3)
		rstyle.set_corner_radius_all(8)
		rcard.add_theme_stylebox_override("panel", rstyle)
		rcard.custom_minimum_size = Vector2(rw, rh)
		rcard.size = Vector2(rw, rh)
		rcard.position = Vector2(start_rx + j * (rw + rspacing), 220)

		var rvbox = VBoxContainer.new()
		rvbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		rvbox.offset_left = 10
		rvbox.offset_top = 8
		rvbox.offset_right = -10
		rvbox.offset_bottom = -8
		rvbox.add_theme_constant_override("separation", 4)
		rcard.add_child(rvbox)

		var rn = Label.new()
		rn.text = str(card_data.get("name", "??"))
		rn.add_theme_font_size_override("font_size", 18)
		rn.add_theme_color_override("font_color", Color.WHITE)
		rvbox.add_child(rn)

		var rc = Label.new()
		rc.text = "费用: %d" % int(card_data.get("cost", 0))
		rc.add_theme_font_size_override("font_size", 13)
		rc.add_theme_color_override("font_color", Color(1, 0.87, 0.27))
		rvbox.add_child(rc)

		var rt = Label.new()
		var type_labels = {"attack": "攻击", "spell": "法术", "movement": "移动", "defense": "防御", "item": "道具"}
		rt.text = "%s | %s" % [type_labels.get(card_data.get("cardType", ""), ""), card_data.get("rarity", "common")]
		rt.add_theme_font_size_override("font_size", 11)
		rt.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
		rvbox.add_child(rt)

		var rd = Label.new()
		rd.text = str(card_data.get("description", ""))
		rd.add_theme_font_size_override("font_size", 12)
		rd.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
		rd.autowrap_mode = TextServer.AUTOWRAP_WORD
		rvbox.add_child(rd)

		var cid = card_id
		rcard.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed:
				_on_reward_card_selected(cid)
		)
		$HUD.add_child(rcard)


func _pick_reward_cards(pool: Array, count: int) -> Array:
	var result = []
	var available = pool.duplicate()
	for i in range(count):
		if available.is_empty():
			break
		var weights = []
		for cid in available:
			var r = Card.get_card(cid).get("rarity", "common")
			match r:
				"rare": weights.append(10)
				"uncommon": weights.append(30)
				_: weights.append(60)
		var total = 0
		for w in weights:
			total += w
		if total == 0:
			break
		var roll = randi() % total
		var cumulative = 0
		for j in range(available.size()):
			cumulative += weights[j]
			if roll < cumulative:
				result.append(available[j])
				available.remove_at(j)
				break
	return result


func _on_reward_card_selected(card_id: String) -> void:
	for p in state.players:
		if p.unit.is_alive:
			p.deck.add_card_to_pool(card_id)
	get_tree().reload_current_scene()


var _stats_panel: Panel = null

func _show_stats_panel(unit: Unit) -> void:
	if _stats_panel == null:
		_stats_panel = Panel.new()
		_stats_panel.anchor_left = 0.0
		_stats_panel.anchor_right = 0.0
		_stats_panel.anchor_top = 0.0
		_stats_panel.anchor_bottom = 0.0
		_stats_panel.offset_left = 16
		_stats_panel.offset_top = 16
		_stats_panel.offset_right = 296
		_stats_panel.offset_bottom = 316
		_stats_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		$HUD.add_child(_stats_panel)
	else:
		for child in _stats_panel.get_children():
			child.free()
	_stats_panel.visible = true
	# Target size per UI.md: 280x300 at (16,16).
	_stats_panel.size = Vector2(280, 300)
	_stats_panel.add_theme_stylebox_override("panel", _make_hud_panel_style(UI_GOLD, 0.54, 5, 1))
	_add_corner_marks(_stats_panel, _stats_panel.size, UI_GOLD)

	var avatar_frame = Panel.new()
	avatar_frame.position = Vector2(14, 14)
	avatar_frame.size = Vector2(72, 72)
	avatar_frame.clip_contents = true
	var avatar_style = _make_slot_style(true, UI_GOLD)
	avatar_style.bg_color = Color(0.06, 0.09, 0.11, 0.28)
	avatar_style.border_color = Color(UI_GOLD_BRIGHT.r, UI_GOLD_BRIGHT.g, UI_GOLD_BRIGHT.b, 0.72)
	avatar_frame.add_theme_stylebox_override("panel", avatar_style)
	_stats_panel.add_child(avatar_frame)
	var avatar = TextureRect.new()
	avatar.texture = _unit_avatar_texture(unit, true)
	avatar.position = Vector2(4, 4)
	avatar.size = Vector2(64, 64)
	avatar.stretch_mode = TextureRect.STRETCH_SCALE
	avatar.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar_frame.add_child(avatar)

	_add_label(_stats_panel, unit.name, Vector2(100, 18), Vector2(160, 22), 18, UI_TEXT)
	_add_label(_stats_panel, "Lv.%d" % maxi(1, int(unit.stats.speed) * 3 + int(unit.stats.strength)), Vector2(226, 22), Vector2(42, 16), 13, UI_GOLD_BRIGHT, HORIZONTAL_ALIGNMENT_RIGHT)
	var class_text = "队员" if unit.faction == "player" else "妖邪"
	if unit.traits.size() > 0:
		class_text = str(unit.traits[0].get("name", class_text))
	_add_label(_stats_panel, class_text, Vector2(100, 46), Vector2(170, 18), 12, UI_TEXT_MUTED)

	_add_separator(_stats_panel, Vector2(18, 68), 248)

	var bar_area = Control.new()
	bar_area.position = Vector2(18, 82)
	bar_area.size = Vector2(248, 80)
	_stats_panel.add_child(bar_area)
	_add_compact_stat_bar(bar_area, "生命", float(unit.current_hp), float(unit.max_hp), UI_HP, 0, "%d/%d" % [unit.current_hp, unit.max_hp])
	var ap_value = state.team_ap if unit.faction == "player" else unit.remaining_move
	var ap_max = state.max_ap if unit.faction == "player" else unit.move_range
	_add_compact_stat_bar(bar_area, "行动", float(ap_value), float(ap_max), UI_AP, 26, "%d/%d" % [ap_value, ap_max])
	_add_compact_stat_bar(bar_area, "移速", float(unit.remaining_move), float(unit.move_range), UI_MP, 52, "%d/%d" % [unit.remaining_move, unit.move_range])

	if unit.faction != "player":
		if _skill_desc_panel != null:
			_skill_desc_panel.visible = false
		return
	var card_data = _selected_action_card_data() if state.selected_unit == unit else {}
	if card_data.is_empty():
		var player = state.get_player_for_unit(unit.id)
		if not player.is_empty() and player.hand.size > 0:
			card_data = player.hand.get_card(0)
	var skill_name = str(card_data.get("name", "战场情报")) if not card_data.is_empty() else "战场情报"
	var skill_desc = str(card_data.get("description", "选择角色、技能或地图格子查看详情。")) if not card_data.is_empty() else "选择角色、技能或地图格子查看详情。"
	if _skill_desc_panel == null:
		_skill_desc_panel = Panel.new()
		_skill_desc_panel.position = Vector2(16, 322)
		_skill_desc_panel.size = Vector2(280, 110)
		_skill_desc_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		$HUD.add_child(_skill_desc_panel)
	else:
		for child in _skill_desc_panel.get_children():
			child.free()
	_skill_desc_panel.visible = true
	_skill_desc_panel.add_theme_stylebox_override("panel", _make_hud_panel_style(Color(UI_GOLD.r, UI_GOLD.g, UI_GOLD.b, 0.62), 0.50, 5, 1))
	_add_corner_marks(_skill_desc_panel, _skill_desc_panel.size, UI_GOLD)
	_add_label(_skill_desc_panel, skill_name, Vector2(18, 12), Vector2(248, 24), 14, UI_GOLD_BRIGHT)
	_add_separator(_skill_desc_panel, Vector2(18, 38), 248)
	var desc = _add_label(_skill_desc_panel, skill_desc, Vector2(18, 48), Vector2(248, 54), 12, UI_TEXT_MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.clip_text = true

func _hide_stats_panel() -> void:
	_refresh_active_stats_panel()

func _init_party_bar() -> void:
	if _party_bar != null:
		return
	_party_bar = HBoxContainer.new()
	_party_bar.position = Vector2(16, 890)
	_party_bar.size = Vector2(520, 110)
	_party_bar.add_theme_constant_override("separation", 12)
	_party_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	$HUD.add_child(_party_bar)

func _refresh_party_bar() -> void:
	if _party_bar == null or state == null:
		return
	for child in _party_bar.get_children():
		child.queue_free()
	for player in state.players:
		var unit: Unit = player.unit
		if unit == null:
			continue
		var selected = state.selected_unit != null and state.selected_unit.id == unit.id
		var slot = Panel.new()
		slot.custom_minimum_size = Vector2(92, 108)
		slot.clip_contents = true
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.add_theme_stylebox_override("panel", _make_slot_style(selected, UI_GOLD_DARK))
		slot.gui_input.connect(_on_party_slot_gui_input.bind(unit))
		_party_bar.add_child(slot)
		var avatar = TextureRect.new()
		avatar.texture = _unit_avatar_texture(unit, true)
		avatar.position = Vector2(4, 4)
		avatar.size = Vector2(84, 84)
		avatar.stretch_mode = TextureRect.STRETCH_SCALE
		avatar.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		avatar.modulate = Color(1, 1, 1, 1) if selected else Color(0.72, 0.72, 0.72, 1)
		slot.add_child(avatar)
		var hp_bg = ColorRect.new()
		hp_bg.position = Vector2(6, 88)
		hp_bg.size = Vector2(80, 4)
		hp_bg.color = Color(0.16, 0.04, 0.04, 0.85)
		slot.add_child(hp_bg)
		var hp = ColorRect.new()
		hp.size = Vector2(80.0 * clampf(float(unit.current_hp) / maxf(float(unit.max_hp), 1.0), 0.0, 1.0), 4)
		hp.color = UI_HP
		hp_bg.add_child(hp)
		var ap_bg = ColorRect.new()
		ap_bg.position = Vector2(6, 93)
		ap_bg.size = Vector2(80, 4)
		ap_bg.color = Color(0.04, 0.12, 0.04, 0.85)
		slot.add_child(ap_bg)
		var ap = ColorRect.new()
		ap.size = Vector2(80.0 * clampf(float(unit.remaining_move) / maxf(float(unit.move_range), 1.0), 0.0, 1.0), 4)
		ap.color = UI_AP
		ap_bg.add_child(ap)
		var name_label = _add_label(slot, unit.name.substr(0, min(3, unit.name.length())), Vector2(4, 98), Vector2(84, 12), 10, UI_TEXT_WARM, HORIZONTAL_ALIGNMENT_CENTER)
		name_label.clip_text = true

func _on_party_slot_gui_input(event: InputEvent, unit: Unit) -> void:
	if event is InputEventMouseButton and event.pressed:
		select_unit(unit)

func _refresh_active_stats_panel() -> void:
	if state == null:
		return
	var unit: Unit = null
	if state.selected_unit != null and state.selected_unit.is_alive:
		unit = state.selected_unit
	else:
		var player = _get_active_player()
		if not player.is_empty():
			unit = player.unit
	if unit != null:
		_show_stats_panel(unit)
	_refresh_party_bar()

# --- Rendering ---

func refresh_units() -> void:
	# Remove dead sprites
	for uid in unit_sprites.keys():
		var u = state.get_unit_by_id(uid)
		if u == null or not u.is_alive:
			var s = unit_sprites[uid]
			if is_instance_valid(s):
				s.queue_free()
			unit_sprites.erase(uid)

	for unit in state.all_units:
		if not unit.is_alive:
			continue
		_create_or_update_sprite(unit)
	_refresh_active_stats_panel()

func _create_or_update_sprite(unit: Unit) -> void:
	var vc = _visual_coord(unit.position.x, unit.position.y)
	var screen = _grid_origin + cart_to_iso(vc.x, vc.y)
	var is_player = unit.faction == "player"

	if unit_sprites.has(unit.id):
		var existing = unit_sprites[unit.id]
		if is_instance_valid(existing):
			existing.z_index = 100 + vc.x + vc.y
			_update_sprite(existing, unit, screen, is_player)
			return
	var container = Node2D.new()
	container.z_index = 100 + vc.x + vc.y
	_update_sprite(container, unit, screen, is_player)
	add_child(container)
	unit_sprites[unit.id] = container

func _unit_render_key(unit: Unit, is_player: bool) -> String:
	var status_parts = []
	for active in unit.status_effects:
		status_parts.append("%s:%s:%s" % [active.get("status_id", ""), active.get("duration", 0), active.get("value", 0)])
	return "|".join([
		unit.template_id,
		str(unit.facing),
		str(unit.current_hp),
		str(unit.max_hp),
		str(unit.shield),
		str(unit.remaining_move),
		str(state.team_ap if is_player else -1),
		",".join(status_parts),
	])

func _unit_initial(unit: Unit) -> String:
	if unit.name.length() == 0:
		return "?"
	return unit.name.substr(0, 1)

func _unit_hp_color(ratio: float) -> Color:
	if ratio > 0.5:
		return Color(0.32, 0.86, 0.38, 0.86)
	if ratio > 0.25:
		return Color(0.92, 0.76, 0.26, 0.88)
	return Color(0.90, 0.24, 0.22, 0.90)

func _add_unit_nameplate(container: Node2D, unit: Unit, y: float = -92.0) -> void:
	var width = clampf(36.0 + unit.name.length() * 11.0, 58.0, 82.0)
	var panel = Panel.new()
	panel.position = Vector2(-width * 0.5, y)
	panel.size = Vector2(width, 18)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style = StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 0.58)
	style.border_color = Color(0.02, 0.025, 0.030, 0.20)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	container.add_child(panel)
	var label = Label.new()
	label.text = unit.name
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.02, 0.025, 0.030, 0.88))
	_apply_chinese_font(label)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)

func _update_sprite(container: Node2D, unit: Unit, screen: Vector2, is_player: bool) -> void:
	var render_key = _unit_render_key(unit, is_player)
	container.position = screen
	if container.has_meta("render_key") and container.get_meta("render_key") == render_key and container.get_child_count() > 0:
		return
	container.set_meta("render_key", render_key)
	for child in container.get_children():
		child.free()
	# Try sprite sheet animation first
	var sheet = _sprite_sheets.get(unit.template_id, null)
	if sheet != null:
		var facing_row = 0
		match unit.facing:
			Vector2i.DOWN: facing_row = 0
			Vector2i.LEFT: facing_row = 1
			Vector2i.UP: facing_row = 2
			Vector2i.RIGHT: facing_row = 3
		var anim = AnimatedSprite2D.new()
		var frames = SpriteFrames.new()
		frames.add_animation("idle")
		frames.set_animation_speed("idle", 4.0)
		var frame_w = sheet.get_width() / 4.0
		var frame_h = sheet.get_height() / 4.0
		for fi in range(4):
			var tex = AtlasTexture.new()
			tex.atlas = sheet
			var crop_margin = 2.0 if unit.template_id == "coffin_lord" else 0.0
			tex.region = Rect2(
				fi * frame_w + crop_margin,
				facing_row * frame_h + crop_margin,
				frame_w - crop_margin * 2.0,
				frame_h - crop_margin * 2.0
			)
			frames.add_frame("idle", tex)
		var shadow = Polygon2D.new()
		shadow.polygon = PackedVector2Array([
			Vector2(0, -8), Vector2(25, 0),
			Vector2(0, 8), Vector2(-25, 0),
		])
		shadow.position = Vector2(0, 5)
		shadow.color = Color(0, 0, 0, 0.28)
		container.add_child(shadow)
		anim.sprite_frames = frames
		anim.play("idle")
		anim.position = Vector2(0, -TILE_H * 0.52)
		# Keep sprite scale at 1.0 for standard 64x64 sheets; only downscale oversized hires sheets.
		var sprite_scale = 1.0 if frame_w <= 80.0 else 0.68
		anim.scale = Vector2(sprite_scale, sprite_scale)
		container.add_child(anim)
		_add_unit_nameplate(container, unit, -94.0)
		# Facing arrow
		var v_facing = _grid_facing_to_visual(unit.facing)
		var adx = (v_facing.x - v_facing.y) * 8.0
		var ady = (v_facing.x + v_facing.y) * 4.0
		var arrow = Polygon2D.new()
		arrow.polygon = PackedVector2Array([Vector2(adx, ady-2), Vector2(adx*0.3-3, ady*0.5), Vector2(adx*0.3+3, ady*0.5)])
		arrow.color = Color(1, 1, 1, 0.5)
		container.add_child(arrow)
		# Faction base ring
		var _ov_color = Color(0.267, 0.667, 1) if is_player else Color(1, 0.267, 0.267)
		var _ov_base = Polygon2D.new()
		_ov_base.polygon = PackedVector2Array([
			Vector2(0, -6), Vector2(20, 0),
			Vector2(0, 6), Vector2(-20, 0),
		])
		_ov_base.position = Vector2(0, 2)
		_ov_base.color = Color(_ov_color.r, _ov_color.g, _ov_color.b, 0.3)
		container.add_child(_ov_base)

		# HP bar with border
		var _ov_ob = ColorRect.new()
		_ov_ob.size = Vector2(44, 6)
		_ov_ob.position = Vector2(-22, 30)
		_ov_ob.color = Color(0.03, 0.025, 0.02, 0.68)
		container.add_child(_ov_ob)
		var _ov_bg = ColorRect.new()
		_ov_bg.size = Vector2(42, 4)
		_ov_bg.position = Vector2(-21, 31)
		_ov_bg.color = Color(0.14, 0.12, 0.10, 0.72)
		container.add_child(_ov_bg)

		var _ov_ratio = float(unit.current_hp) / float(unit.max_hp)
		var _ov_bar = ColorRect.new()
		_ov_bar.size = Vector2(42 * _ov_ratio, 4)
		_ov_bar.position = Vector2(-21, 31)
		_ov_bar.color = _unit_hp_color(_ov_ratio)
		container.add_child(_ov_bar)
		# Status dots
		var _ov_sx = -unit.status_effects.size() * 5
		for _ov_st in unit.status_effects:
			var _ov_def = StatusEffectManager.get_status_def(_ov_st.status_id)
			if _ov_def.is_empty():
				continue
			var _ov_dot = ColorRect.new()
			_ov_dot.size = Vector2(6, 6)
			_ov_dot.position = Vector2(_ov_sx - 3, 50)
			_ov_dot.color = Color.from_string(_ov_def.get("color", "#ffffff"), Color.WHITE)
			container.add_child(_ov_dot)
			_ov_sx += 10

		if unit.shield > 0:
			var _ov_sl = Label.new()
			_ov_sl.text = "S%d" % unit.shield
			_ov_sl.add_theme_font_size_override("font_size", 8)
			_ov_sl.add_theme_color_override("font_color", Color(0.53, 0.73, 1))
			_ov_sl.position = Vector2(12, 30)
			container.add_child(_ov_sl)
		return

	# Fallback: polygon block rendering
	var c = unit.color
	var top_c = Color(minf(c.r * 1.2, 1.0), minf(c.g * 1.2, 1.0), minf(c.b * 1.2, 1.0), c.a)
	var left_c = Color(c.r * 0.6, c.g * 0.6, c.b * 0.6, c.a)
	var right_c = Color(c.r * 0.4, c.g * 0.4, c.b * 0.4, c.a)
	var bw = 22.0
	var bh = 11.0
	var bd = 37.0
	var by = -(bh + bd)

	var top_face = Polygon2D.new()
	top_face.polygon = PackedVector2Array([
		Vector2(0, by - bh), Vector2(bw, by),
		Vector2(0, by + bh), Vector2(-bw, by),
	])
	top_face.color = top_c
	container.add_child(top_face)

	var left_face = Polygon2D.new()
	left_face.polygon = PackedVector2Array([
		Vector2(-bw, by), Vector2(0, by + bh),
		Vector2(0, by + bh + bd), Vector2(-bw, by + bd),
	])
	left_face.color = left_c
	container.add_child(left_face)

	var right_face = Polygon2D.new()
	right_face.polygon = PackedVector2Array([
		Vector2(0, by + bh), Vector2(bw, by),
		Vector2(bw, by + bd), Vector2(0, by + bh + bd),
	])
	right_face.color = right_c
	container.add_child(right_face)

	var hy = by - 16.0
	var hbw = 11.0
	var hbh = 5.5
	var hbd = 12.0
	var head_top = Polygon2D.new()
	head_top.polygon = PackedVector2Array([
		Vector2(0, hy - hbh), Vector2(hbw, hy),
		Vector2(0, hy + hbh), Vector2(-hbw, hy),
	])
	head_top.color = Color(minf(c.r * 1.2, 1.0), minf(c.g * 1.2, 1.0), minf(c.b * 1.2, 1.0), c.a)
	container.add_child(head_top)

	var head_left = Polygon2D.new()
	head_left.polygon = PackedVector2Array([
		Vector2(-hbw, hy), Vector2(0, hy + hbh),
		Vector2(0, hy + hbh + hbd), Vector2(-hbw, hy + hbd),
	])
	head_left.color = Color(c.r * 0.65, c.g * 0.65, c.b * 0.65, c.a)
	container.add_child(head_left)

	var head_right = Polygon2D.new()
	head_right.polygon = PackedVector2Array([
		Vector2(0, hy + hbh), Vector2(hbw, hy),
		Vector2(hbw, hy + hbd), Vector2(0, hy + hbh + hbd),
	])
	head_right.color = Color(c.r * 0.45, c.g * 0.45, c.b * 0.45, c.a)
	container.add_child(head_right)

	var ring_color = Color(0.267, 0.667, 1) if is_player else Color(1, 0.267, 0.267)
	var ring = Polygon2D.new()
	ring.polygon = PackedVector2Array([
		Vector2(0, hy - hbh - 2), Vector2(9, hy - 2),
		Vector2(0, hy + hbh - 2), Vector2(-9, hy - 2),
	])
	ring.color = Color(ring_color.r, ring_color.g, ring_color.b, 0.6)
	container.add_child(ring)

	_add_unit_nameplate(container, unit, hy - 34.0)

	var hp_bar_bg = ColorRect.new()
	hp_bar_bg.size = Vector2(30, 4)
	hp_bar_bg.position = Vector2(-15, by - bh - 8)
	hp_bar_bg.color = Color(0.12, 0.10, 0.08, 0.72)
	container.add_child(hp_bar_bg)

	var hp_ratio = float(unit.current_hp) / float(unit.max_hp)
	var hp_bar = ColorRect.new()
	hp_bar.size = Vector2(30 * hp_ratio, 4)
	hp_bar.position = Vector2(-15, by - bh - 8)
	hp_bar.color = _unit_hp_color(hp_ratio)
	container.add_child(hp_bar)

	var label = Label.new()
	label.text = "友" if is_player else "敌"
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Color(0.533, 0.8, 1) if is_player else Color(1, 0.533, 0.533))
	label.position = Vector2(-4, by + bh + bd + 2)
	container.add_child(label)

	if is_player:
		var ap_label = Label.new()
		ap_label.text = str(state.team_ap)
		ap_label.add_theme_font_size_override("font_size", 9)
		ap_label.add_theme_color_override("font_color", Color(1, 0.87, 0.27))
		ap_label.position = Vector2(10, by + 2)
		container.add_child(ap_label)

		var move_label = Label.new()
		move_label.text = str(unit.remaining_move)
		move_label.add_theme_font_size_override("font_size", 8)
		move_label.add_theme_color_override("font_color", Color(0.53, 1, 0.53) if unit.can_move else Color(0.4, 0.4, 0.53))
		move_label.position = Vector2(-14, by + 2)
		container.add_child(move_label)

	if unit.shield > 0:
		var shield_poly = Polygon2D.new()
		shield_poly.polygon = PackedVector2Array([
			Vector2(0, hy - hbh - 4), Vector2(12, hy - 4),
			Vector2(0, hy + hbh - 4), Vector2(-12, hy - 4),
		])
		shield_poly.color = Color(0.267, 0.533, 1, 0.35)
		container.add_child(shield_poly)
		var shield_num = Label.new()
		shield_num.text = str(unit.shield)
		shield_num.add_theme_font_size_override("font_size", 8)
		shield_num.add_theme_color_override("font_color", Color(0.53, 0.73, 1))
		shield_num.position = Vector2(-4, hy - hbh - 12)
		container.add_child(shield_num)

	var sx = -unit.status_effects.size() * 5
	for active in unit.status_effects:
		var def = StatusEffectManager.get_status_def(active.status_id)
		if def.is_empty():
			continue
		var dot = ColorRect.new()
		dot.size = Vector2(6, 6)
		dot.position = Vector2(sx - 3, by + bh + bd + 12)
		dot.color = Color.from_string(def.get("color", "#ffffff"), Color.WHITE)
		container.add_child(dot)
		sx += 10

func _show_floating_text(unit: Unit, text: String, color: Color) -> void:
	var vc = _visual_coord(unit.position.x, unit.position.y)
	var screen = _grid_origin + cart_to_iso(vc.x, vc.y)
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(80, 24)
	label.position = Vector2(screen.x - 40, screen.y - 40)
	label.z_index = 999
	add_child(label)
	var tween = create_tween()
	tween.tween_property(label, "position:y", label.position.y - 30, _battle_delay(0.8))
	tween.parallel().tween_property(label, "modulate:a", 0.0, _battle_delay(0.8))
	tween.tween_callback(label.queue_free)

func _show_hit_effect(pos: Vector2i) -> void:
	var vc = _visual_coord(pos.x, pos.y)
	var screen = _grid_origin + cart_to_iso(vc.x, vc.y)
	var flash = Polygon2D.new()
	flash.polygon = PackedVector2Array([
		Vector2(0, -18), Vector2(24, 0),
		Vector2(0, 18), Vector2(-24, 0),
	])
	flash.position = Vector2(screen.x, screen.y - 20)
	flash.color = Color(1, 1, 1, 0.6)
	flash.z_index = 998
	add_child(flash)
	var tween = create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, _battle_delay(0.3))
	tween.tween_callback(flash.queue_free)

func _get_card_panel(index: int) -> Panel:
	while _card_panel_pool.size() <= index:
		var panel = Panel.new()
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.gui_input.connect(_on_card_panel_gui_input.bind(panel))
		panel.mouse_entered.connect(_on_card_panel_mouse_entered.bind(panel))
		panel.mouse_exited.connect(_on_card_panel_mouse_exited.bind(panel))
		$BottomUI/CardArea.add_child(panel)
		_card_panel_pool.append(panel)
	return _card_panel_pool[index]

func _clear_card_panel(panel: Panel) -> void:
	for child in panel.get_children():
		child.queue_free()

func _on_card_panel_gui_input(event: InputEvent, panel: Panel) -> void:
	if event is InputEventMouseButton and event.pressed:
		var card_index = int(panel.get_meta("card_index", -1))
		if card_index >= 0:
			_on_card_clicked(card_index)

func _on_card_panel_mouse_entered(panel: Panel) -> void:
	var card_index = int(panel.get_meta("card_index", -1))
	if card_index >= 0:
		_on_card_hover(card_index, panel)

func _on_card_panel_mouse_exited(panel: Panel) -> void:
	_on_card_unhover(panel)

func _get_inventory_panel(index: int) -> Panel:
	while _inventory_panel_pool.size() <= index:
		var panel = Panel.new()
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.gui_input.connect(_on_inventory_panel_gui_input.bind(panel))
		$BottomUI/ItemArea.add_child(panel)
		_inventory_panel_pool.append(panel)
	return _inventory_panel_pool[index]

func _clear_inventory_panel(panel: Panel) -> void:
	for child in panel.get_children():
		child.queue_free()

func _add_empty_action_slot(panel: Panel, slot_size: Vector2) -> void:
	var empty_style = _make_card_style(false, Color(0.42, 0.44, 0.48, 0.50), Color(0.20, 0.22, 0.25))
	empty_style.bg_color = Color(0.070, 0.080, 0.092, 0.32)
	empty_style.border_color = Color(0.72, 0.75, 0.78, 0.22)
	panel.add_theme_stylebox_override("panel", empty_style)
	_add_generated_backdrop(panel, "card_frame_v2", slot_size, Color(0.68, 0.72, 0.76, 0.42))
	var well = Panel.new()
	well.position = Vector2(8, 13)
	well.size = Vector2(slot_size.x - 16, slot_size.y - 43)
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_theme_stylebox_override("panel", _make_clean_panel_style(Color(0.72, 0.75, 0.78, 0.14), Color(0.12, 0.13, 0.14, 0.18), 4, 0))
	panel.add_child(well)
	var label = Label.new()
	label.text = "空"
	label.position = Vector2(5, slot_size.y - 27)
	label.size = Vector2(slot_size.x - 10, 22)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.86, 0.88, 0.90, 0.42))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)

func _on_inventory_panel_gui_input(event: InputEvent, panel: Panel) -> void:
	if event is InputEventMouseButton and event.pressed:
		var slot_index = int(panel.get_meta("slot_index", -1))
		if slot_index >= 0:
			_select_inventory_slot(slot_index)

func _on_inventory_item_gui_input(event: InputEvent, panel: Panel, inv_index: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		_select_inventory_slot(inv_index)

func _on_inventory_item_mouse_entered(panel: Panel, inv_index: int) -> void:
	var player = _get_active_player()
	if player.is_empty():
		return
	var inv = player.get("inventory_ref", null)
	if inv == null:
		return
	var item = inv.get_item(inv_index)
	if item.is_empty():
		return
	var card_id = str(item.get("card_id", ""))
	if card_id != "":
		var card_data = Card.get_card(card_id)
		if not card_data.is_empty():
			_show_action_tooltip(card_data, panel, int(item.get("uses", 1)))
	else:
		_show_object_item_tooltip(item, panel)

func _on_inventory_item_mouse_exited(panel: Panel) -> void:
	_hide_card_tooltip()

func _select_inventory_slot(slot_index: int) -> void:
	if state.selected_unit == null:
		return
	var player = state.get_player_for_unit(state.selected_unit.id)
	if player.is_empty():
		return
	var inv = player.get("inventory_ref", null)
	if inv == null or slot_index >= inv.get_size():
		return
	var item = inv.get_item(slot_index)
	if item.is_empty():
		return
	state.selected_inventory_index = slot_index
	state.selected_card_index = -1
	var valid_tiles = []
	var card_id = str(item.get("card_id", ""))
	if card_id != "":
		var card_data = Card.get_card(card_id)
		if not card_data.is_empty() and state.team_ap >= int(card_data.get("cost", 1)):
			valid_tiles = CardResolver.get_valid_targets(card_data, state.selected_unit, state.map, state.all_units)
	else:
		for n in state.map.get_neighbors(state.selected_unit.position):
			if state.map.is_walkable(n) and not state.map.is_occupied(n) and state.map.get_object(n.x, n.y) == "":
				valid_tiles.append(n)
	state.inventory_target_tiles = valid_tiles
	target_tiles = []
	reachable_tiles = []
	_queue_overlay_redraw()
	refresh_inventory_ui()
	refresh_card_ui()
	_refresh_active_stats_panel()

func refresh_inventory_ui() -> void:
	var container = $BottomUI/ItemArea
	for child in container.get_children():
		child.queue_free()
	var player = _get_active_player()
	if player.is_empty():
		return
	var inv = player.get("inventory_ref", null)
	if inv == null:
		return
	var item_w = 82
	var item_h = 104
	var gap = 8
	var total_w = ACTION_SLOT_COUNT * item_w + maxi(0, ACTION_SLOT_COUNT - 1) * gap
	var container_w = maxf(container.size.x, float(total_w))
	var start_x = maxf(0.0, (container_w - total_w) * 0.5)
	for i in range(ACTION_SLOT_COUNT):
		var item = inv.get_item(i) if i < inv.get_size() else {}
		var obj_id = str(item.get("object_id", ""))
		var card_id = str(item.get("card_id", ""))
		var uses = int(item.get("uses", 1))
		var card_data = Card.get_card(card_id) if card_id != "" else {}
		var panel = Panel.new()
		panel.visible = true
		panel.set_meta("inv_index", i if not item.is_empty() else -1)
		panel.size = Vector2(item_w, item_h)
		panel.position = Vector2(start_x + i * (item_w + gap), 0)
		panel.pivot_offset = panel.size * 0.5
		panel.clip_contents = true
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		container.add_child(panel)
		if item.is_empty():
			_add_empty_action_slot(panel, panel.size)
			continue
		var item_color = Color(0.72, 0.55, 0.22)
		var style = _make_card_style(state.selected_inventory_index == i, UI_GOLD, item_color)
		if state.selected_inventory_index == i:
			style.bg_color = Color(0.11, 0.12, 0.14, 0.72)
		panel.add_theme_stylebox_override("panel", style)
		_add_generated_backdrop(panel, "card_frame_v2", panel.size, Color(1.0, 0.94, 0.78, 0.74))
		panel.gui_input.connect(_on_inventory_item_gui_input.bind(panel, i))
		panel.mouse_entered.connect(_on_inventory_item_mouse_entered.bind(panel, i))
		panel.mouse_exited.connect(_on_inventory_item_mouse_exited.bind(panel))
		var header = ColorRect.new()
		header.size = Vector2(item_w - 16, 3)
		header.position = Vector2(8, 7)
		header.color = Color(item_color.r, item_color.g, item_color.b, 0.58)
		header.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(header)
		var icon_well = Panel.new()
		icon_well.position = Vector2(8, 13)
		icon_well.size = Vector2(item_w - 16, 52)
		icon_well.clip_contents = true
		icon_well.add_theme_stylebox_override("panel", _make_clean_panel_style(Color(UI_GOLD.r, UI_GOLD.g, UI_GOLD.b, 0.22), Color(0.070, 0.085, 0.100, 0.28), 4, 0))
		icon_well.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(icon_well)
		if card_id != "":
			_add_card_face_art(icon_well, card_data, item_color, Vector2(3, 3), icon_well.size - Vector2(6, 6))
		elif _object_textures.has(obj_id):
			var tex = _object_textures[obj_id]
			var icon = TextureRect.new()
			icon.texture = tex
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.size = icon_well.size - Vector2(6, 6)
			icon.position = Vector2(3, 3)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon_well.add_child(icon)
		var name_bg = ColorRect.new()
		name_bg.position = Vector2(5, item_h - 28)
		name_bg.size = Vector2(item_w - 10, 22)
		name_bg.color = Color(0.075, 0.088, 0.105, 0.60)
		name_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(name_bg)
		var lbl = Label.new()
		lbl.text = str(card_data.get("name", "")) if card_id != "" else _object_display_name(obj_id)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.size = Vector2(item_w - 10, 22)
		lbl.position = Vector2(5, item_h - 28)
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", UI_TEXT_WARM)
		lbl.clip_text = true
		panel.add_child(lbl)
		if uses > 1:
			var uses_badge = Panel.new()
			uses_badge.position = Vector2(item_w - 32, 9)
			uses_badge.size = Vector2(28, 18)
			uses_badge.add_theme_stylebox_override("panel", _make_clean_button_style(Color(0.12, 0.10, 0.06, 0.62), UI_GOLD_BRIGHT))
			panel.add_child(uses_badge)
			var uses_lbl = Label.new()
			uses_lbl.text = "x%d" % uses
			uses_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			uses_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			uses_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
			uses_lbl.add_theme_font_size_override("font_size", 12)
			uses_lbl.add_theme_color_override("font_color", UI_GOLD_BRIGHT)
			uses_badge.add_child(uses_lbl)
		elif item.get("consumable", false):
			var consumable_lbl = Label.new()
			consumable_lbl.text = "消耗"
			consumable_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			consumable_lbl.size = Vector2(item_w, 14)
			consumable_lbl.position = Vector2(0, 4)
			consumable_lbl.add_theme_font_size_override("font_size", 9)
			consumable_lbl.add_theme_color_override("font_color", Color(0.65, 0.92, 0.72))
			panel.add_child(consumable_lbl)

func _place_inventory_item(target_pos: Vector2i) -> void:
	if state.selected_unit == null or state.selected_inventory_index < 0:
		return
	var player = state.get_player_for_unit(state.selected_unit.id)
	if player.is_empty():
		return
	var inv = player.get("inventory_ref", null)
	if inv == null:
		return
	var item = inv.get_item(state.selected_inventory_index)
	if item.is_empty():
		return
	var object_id = item.object_id
	if interaction_system.place_from_inventory(state.selected_unit, object_id, target_pos):
		if item.consumable:
			inv.consume_item_at(state.selected_inventory_index)
		state.selected_inventory_index = -1
		state.inventory_target_tiles = []
		refresh_inventory_ui()
		refresh_units()
		_queue_scene_redraw()

func _use_selected_inventory_item(target_pos: Vector2i) -> void:
	if state.selected_unit == null or state.selected_inventory_index < 0:
		return
	var player = state.get_player_for_unit(state.selected_unit.id)
	if player.is_empty():
		return
	var inv = player.get("inventory_ref", null)
	if inv == null:
		return
	var item = inv.get_item(state.selected_inventory_index)
	if item.is_empty():
		return
	var card_id = str(item.get("card_id", ""))
	if card_id != "":
		_play_inventory_card_item(target_pos, inv, card_id)
	else:
		_place_inventory_item(target_pos)

func _play_inventory_card_item(target_pos: Vector2i, inv: Inventory, card_id: String) -> void:
	var unit = state.selected_unit
	if unit == null or state.is_unit_skipped(unit.id):
		return
	var card_data = Card.get_card(card_id)
	if card_data.is_empty():
		return
	var cost = int(card_data.get("cost", 1))
	if not state.can_spend_ap(cost):
		return
	var result = CardResolver.play_card(card_data, unit, target_pos, state.map, state.all_units, state)
	if not result.get("success", false):
		return
	if not state.spend_ap(cost):
		return
	inv.consume_item_at(state.selected_inventory_index)
	if result.get("dodged", false):
		var dodge_target = _find_unit_at(target_pos)
		if dodge_target:
			_show_floating_text(dodge_target, "MISS", Color(1, 1, 0.3))
	for affected in result.get("affected_units", []):
		if int(affected.get("damage", 0)) > 0:
			state.emit_signal("unit_damaged", affected.unit_id, int(affected.damage))
	for effect in result.effects:
		if effect.get("heal_amount", 0) > 0:
			var target = _find_unit_at(target_pos)
			if target:
				state.emit_signal("unit_healed", target.id, effect.heal_amount)
	if result.moved_unit:
		state.emit_signal("unit_moved", unit.id, result.moved_unit.from, result.moved_unit.to)
	if result.get("pulled_target") != null:
		var pt = result.pulled_target
		state.emit_signal("unit_moved", pt.unit_id, pt.from, pt.to)
	for kid in result.killed:
		state.emit_signal("unit_died", kid)
	state.emit_signal("card_played", unit.id, card_id, result.get("targets", [target_pos]))
	state.selected_inventory_index = -1
	state.inventory_target_tiles = []
	target_tiles = []
	damage_tiles = []
	refresh_inventory_ui()
	refresh_units()
	_refresh_active_stats_panel()
	_queue_scene_redraw()
	var battle_result = state.is_battle_over()
	if battle_result == "won":
		state.emit_signal("battle_won")
	elif battle_result == "lost":
		state.emit_signal("battle_lost")

func _execute_pickup(pos: Vector2i, obj_id: String) -> void:
	_cancel_interaction_menu()
	if state.selected_unit == null:
		return
	if interaction_system.pickup(state.selected_unit, pos):
		var player = state.get_player_for_unit(state.selected_unit.id)
		if not player.is_empty():
			var inv = player.get("inventory_ref", null)
			if inv != null:
				var odef = state.map.objects_data.get(obj_id, {})
				var is_consumable = odef.get("consumable", false)
				inv.add_item(obj_id, is_consumable)
		_show_floating_text_at(pos, "拾取", Color(0.3, 1, 0.5))
		refresh_inventory_ui()
		refresh_units()
		_queue_scene_redraw()

func _card_icon_key(card_data: Dictionary) -> String:
	var card_id = str(card_data.get("id", ""))
	if CARD_ICON_BY_ID.has(card_id):
		return CARD_ICON_BY_ID[card_id]
	var card_type = str(card_data.get("cardType", ""))
	if card_type == "item":
		return "skill_icon_talisman"
	for eff in card_data.get("effects", []):
		var eff_type = str(eff.get("type", ""))
		if eff_type == "create_noise":
			return "skill_icon_bell"
		if eff_type == "add_terrain_effect":
			var effect_id = str(eff.get("effect", ""))
			if effect_id == "fire":
				return "skill_icon_fire"
			if effect_id == "water_spread":
				return "skill_icon_water"
			if effect_id == "rice":
				return "skill_icon_rice"
			if effect_id == "talisman":
				return "skill_icon_talisman"
		if eff_type == "pull" or eff_type == "push_unit":
			return "skill_icon_bind"
		if eff_type == "apply_status" and str(eff.get("statusId", "")) == "stun":
			return "skill_icon_soul"
	var dtype = ""
	for eff in card_data.get("effects", []):
		if str(eff.get("type", "")) == "deal_damage":
			dtype = str(eff.get("damageType", "physical"))
			break
	return "skill_icon_soul" if dtype == "magic" else "skill_icon_slash"

func _add_card_face_art(parent: Control, card_data: Dictionary, type_color: Color, pos: Vector2, art_size: Vector2) -> void:
	var card_id = str(card_data.get("id", ""))
	if _card_face_textures.has(card_id):
		var tex_rect = TextureRect.new()
		tex_rect.texture = _card_face_textures[card_id]
		tex_rect.position = pos
		tex_rect.size = art_size
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(tex_rect)
		return
	var art = CardArtLayer.new()
	art.card_id = card_id
	art.accent = type_color
	art.glow = UI_GOLD_BRIGHT
	art.position = pos
	art.size = art_size
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(art)

func refresh_card_ui() -> void:
	for panel in _card_panel_pool:
		if is_instance_valid(panel):
			panel.visible = false
	var player = _get_active_player()
	if player.is_empty():
		return
	var hand = player.hand
	var card_w = 82
	var card_h = 104
	var gap = 8
	var total_w = ACTION_SLOT_COUNT * card_w + maxi(0, ACTION_SLOT_COUNT - 1) * gap
	var container: Control = $BottomUI/CardArea
	var container_w = maxf(container.size.x, float(total_w))
	var start_x = maxf(0.0, (container_w - total_w) * 0.5)
	var type_colors = {"attack": Color(0.75, 0.25, 0.25), "spell": Color(0.4, 0.25, 0.75), "movement": Color(0.2, 0.6, 0.35), "defense": Color(0.25, 0.45, 0.75), "item": Color(0.72, 0.55, 0.22)}
	var rarity_border = {"common": UI_GOLD, "uncommon": Color(0.50, 0.78, 0.46, 0.9), "rare": UI_GOLD_BRIGHT}
	for i in range(ACTION_SLOT_COUNT):
		var card_data = hand.get_card(i) if i < hand.size else {}
		var card_type = card_data.get("cardType", "attack")
		var rarity = card_data.get("rarity", "common")
		var type_color = type_colors.get(card_type, Color(0.5, 0.5, 0.5))
		var panel = _get_card_panel(i)
		_clear_card_panel(panel)
		panel.visible = true
		panel.set_meta("card_index", i if not card_data.is_empty() else -1)
		panel.size = Vector2(card_w, card_h)
		panel.position = Vector2(start_x + i * (card_w + gap), 0)
		panel.pivot_offset = panel.size * 0.5
		panel.clip_contents = true
		if card_data.is_empty():
			_add_empty_action_slot(panel, panel.size)
			continue
		var bg = _make_card_style(i == state.selected_card_index, rarity_border.get(rarity, UI_GOLD), type_color)
		panel.add_theme_stylebox_override("panel", bg)
		_add_generated_backdrop(panel, "card_frame_v2", panel.size, Color(1.0, 0.95, 0.80, 0.88 if i == state.selected_card_index else 0.72))
		var header = ColorRect.new()
		header.size = Vector2(card_w - 16, 3)
		header.position = Vector2(8, 7)
		header.color = Color(type_color.r, type_color.g, type_color.b, 0.62)
		header.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(header)
		var icon_well = Panel.new()
		icon_well.position = Vector2(8, 13)
		icon_well.size = Vector2(card_w - 16, 52)
		icon_well.clip_contents = true
		icon_well.add_theme_stylebox_override("panel", _make_clean_panel_style(Color(type_color.r, type_color.g, type_color.b, 0.28), Color(0.070, 0.085, 0.105, 0.26), 4, 0))
		icon_well.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(icon_well)
		var cost_badge = Panel.new()
		cost_badge.position = Vector2(5, 9)
		cost_badge.size = Vector2(22, 18)
		cost_badge.add_theme_stylebox_override("panel", _make_clean_button_style(Color(0.12, 0.10, 0.06, 0.62), UI_GOLD_BRIGHT))
		panel.add_child(cost_badge)
		var cost_label = Label.new()
		cost_label.text = str(card_data.get("cost", 1))
		cost_label.add_theme_font_size_override("font_size", 12)
		cost_label.add_theme_color_override("font_color", UI_GOLD_BRIGHT)
		cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cost_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		cost_badge.add_child(cost_label)
		_add_card_face_art(icon_well, card_data, type_color, Vector2(3, 3), icon_well.size - Vector2(6, 6))
		var name_bg = ColorRect.new()
		name_bg.position = Vector2(5, card_h - 28)
		name_bg.size = Vector2(card_w - 10, 22)
		name_bg.color = Color(0.075, 0.088, 0.105, 0.60)
		name_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(name_bg)
		var name_label = Label.new()
		name_label.text = str(card_data.get("name", ""))
		name_label.add_theme_font_size_override("font_size", 11)
		name_label.add_theme_color_override("font_color", UI_TEXT_WARM)
		name_label.position = Vector2(5, card_h - 28)
		name_label.size = Vector2(card_w - 10, 22)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.clip_text = true
		panel.add_child(name_label)
		var discard_btn = Button.new()
		discard_btn.text = "x"
		discard_btn.add_theme_font_size_override("font_size", 9)
		discard_btn.position = Vector2(card_w - 19, 7)
		discard_btn.size = Vector2(16, 16)
		discard_btn.flat = true
		discard_btn.add_theme_color_override("font_color", Color(UI_TEXT_MUTED.r, UI_TEXT_MUTED.g, UI_TEXT_MUTED.b, 0.72))
		var d_idx = i
		discard_btn.pressed.connect(func(): _on_discard_card(d_idx))
		panel.add_child(discard_btn)


func _init_turn_order_bar() -> void:
	_turn_order_panel = Panel.new()
	_turn_order_panel.position = Vector2(520, 14)
	_turn_order_panel.size = Vector2(650, 58)
	_turn_order_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_order_panel.add_theme_stylebox_override("panel", _make_clean_panel_style(Color(UI_GOLD.r, UI_GOLD.g, UI_GOLD.b, 0.50), Color(0.050, 0.070, 0.090, 0.34), 6, 1))
	$HUD.add_child(_turn_order_panel)
	_turn_order_title = Label.new()
	_turn_order_title.position = Vector2(16, 4)
	_turn_order_title.size = Vector2(618, 18)
	_turn_order_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_order_title.add_theme_font_size_override("font_size", 12)
	_turn_order_title.add_theme_color_override("font_color", UI_GOLD_BRIGHT)
	_turn_order_panel.add_child(_turn_order_title)
	_turn_order_bar = HBoxContainer.new()
	_turn_order_bar.position = Vector2(12, 24)
	_turn_order_bar.size = Vector2(626, 30)
	_turn_order_bar.add_theme_constant_override("separation", 5)
	_turn_order_panel.add_child(_turn_order_bar)

func _refresh_turn_order_bar(current_turn: String) -> void:
	if _turn_order_bar == null:
		_init_turn_order_bar()
	for child in _turn_order_bar.get_children():
		child.get_parent().remove_child(child)
		child.free()
	var phase_names = {
		"player": "玩家",
		"intent": "预警",
		"enemy": "敌方",
		"environment": "环境",
		"spirit": "灵压",
	}
	var phase_icon = Panel.new()
	var phase_style = _make_clean_button_style(Color(0.070, 0.090, 0.120, 0.58), UI_GOLD_BRIGHT)
	phase_style.set_border_width_all(1)
	phase_icon.add_theme_stylebox_override("panel", phase_style)
	phase_icon.custom_minimum_size = Vector2(54, 30)
	phase_icon.size = Vector2(54, 30)
	var phase_label = Label.new()
	phase_label.text = phase_names.get(current_turn, current_turn)
	phase_label.add_theme_font_size_override("font_size", 12)
	phase_label.add_theme_color_override("font_color", UI_GOLD_BRIGHT)
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	phase_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	phase_icon.add_child(phase_label)
	_turn_order_bar.add_child(phase_icon)
	var units = state.get_alive_units()
	units.sort_custom(func(a: Unit, b: Unit): return a.stats.speed > b.stats.speed)
	var shown = 0
	for unit in units:
		if shown >= 10:
			break
		var slot = Panel.new()
		slot.custom_minimum_size = Vector2(34, 30)
		slot.size = Vector2(34, 30)
		slot.clip_contents = true
		var border = UI_GOLD
		if unit.faction == "player":
			border = Color(0.42, 0.86, 1.0, 0.92)
		elif unit.faction == "enemy":
			border = Color(1.0, 0.32, 0.28, 0.92)
		if state.selected_unit != null and state.selected_unit.id == unit.id:
			border = UI_GOLD_BRIGHT
		var slot_style = _make_clean_button_style(Color(0.060, 0.075, 0.098, 0.54), border)
		slot_style.set_border_width_all(2 if state.selected_unit != null and state.selected_unit.id == unit.id else 1)
		slot.add_theme_stylebox_override("panel", slot_style)
		var avatar = TextureRect.new()
		avatar.texture = _unit_order_icon_texture(unit)
		avatar.position = Vector2(1, 1)
		avatar.size = Vector2(32, 28)
		avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		avatar.stretch_mode = TextureRect.STRETCH_SCALE
		avatar.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(avatar)
		_turn_order_bar.add_child(slot)
		shown += 1

func _on_card_hover(index: int, panel: Control) -> void:
	var tween = create_tween()
	tween.tween_property(panel, "scale", Vector2(1.08, 1.08), _battle_delay(0.1))
	panel.z_index = 100
	_show_card_tooltip(index, panel)

func _on_card_unhover(panel: Control) -> void:
	var tween = create_tween()
	tween.tween_property(panel, "scale", Vector2(1.0, 1.0), _battle_delay(0.1))
	panel.z_index = 0
	_hide_card_tooltip()

func _show_card_tooltip(index: int, panel: Control) -> void:
	var player = _get_active_player()
	if player.is_empty():
		return
	if state.is_unit_skipped(player.unit.id):
		return
	var card_data = player.hand.get_card(index)
	if card_data.is_empty():
		return
	_show_action_tooltip(card_data, panel)

func _show_action_tooltip(card_data: Dictionary, panel: Control, uses: int = -1) -> void:
	if _card_tooltip == null:
		_card_tooltip = Panel.new()
		_card_tooltip.add_theme_stylebox_override("panel", _make_clean_panel_style(UI_GOLD, Color(0.050, 0.068, 0.088, 0.72), 6, 1))
		$BottomUI.add_child(_card_tooltip)
	for child in _card_tooltip.get_children():
		child.get_parent().remove_child(child)
		child.free()
	var tvbox = VBoxContainer.new()
	tvbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	tvbox.offset_left = 8
	tvbox.offset_top = 6
	tvbox.offset_right = -8
	tvbox.offset_bottom = -6
	tvbox.add_theme_constant_override("separation", 3)
	_card_tooltip.add_child(tvbox)
	var rarity_colors = {"common": Color(0.6, 0.6, 0.6), "uncommon": Color(0.2, 0.8, 0.4), "rare": Color(1, 0.7, 0.2)}
	var t_name = Label.new()
	t_name.text = str(card_data.get("name", "??"))
	t_name.add_theme_font_size_override("font_size", 16)
	t_name.add_theme_color_override("font_color", UI_GOLD_BRIGHT)
	tvbox.add_child(t_name)
	var t_cost = Label.new()
	t_cost.text = "费用: %d | %s | %s" % [int(card_data.get("cost", 0)), {"attack": "攻击", "spell": "法术", "movement": "移动", "defense": "防御", "item": "道具"}.get(card_data.get("cardType", ""), ""), card_data.get("rarity", "common")]
	if uses >= 0:
		t_cost.text += " | 剩余 %d" % uses
	t_cost.add_theme_font_size_override("font_size", 12)
	t_cost.add_theme_color_override("font_color", rarity_colors.get(card_data.get("rarity", "common"), UI_TEXT_MUTED))
	tvbox.add_child(t_cost)
	var t_desc = Label.new()
	t_desc.text = str(card_data.get("description", ""))
	t_desc.add_theme_font_size_override("font_size", 12)
	t_desc.add_theme_color_override("font_color", UI_TEXT_WARM)
	t_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	tvbox.add_child(t_desc)
	for rule_line in _card_rule_lines(card_data):
		var rl = Label.new()
		rl.text = rule_line
		rl.add_theme_font_size_override("font_size", 11)
		rl.add_theme_color_override("font_color", UI_GOLD_BRIGHT)
		rl.autowrap_mode = TextServer.AUTOWRAP_WORD
		tvbox.add_child(rl)
	_card_tooltip.custom_minimum_size = Vector2(250, 165)
	_card_tooltip.size = Vector2(250, 165)
	var card_pos = panel.global_position
	_card_tooltip.position = Vector2(card_pos.x - 50, card_pos.y - 175)
	_card_tooltip.visible = true

func _show_object_item_tooltip(item: Dictionary, panel: Control) -> void:
	if _card_tooltip == null:
		_card_tooltip = Panel.new()
		_card_tooltip.add_theme_stylebox_override("panel", _make_clean_panel_style(UI_GOLD, Color(0.050, 0.068, 0.088, 0.72), 6, 1))
		$BottomUI.add_child(_card_tooltip)
	for child in _card_tooltip.get_children():
		child.queue_free()
	var obj_id = str(item.get("object_id", ""))
	var tvbox = VBoxContainer.new()
	tvbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	tvbox.offset_left = 10
	tvbox.offset_top = 8
	tvbox.offset_right = -10
	tvbox.offset_bottom = -8
	tvbox.add_theme_constant_override("separation", 4)
	_card_tooltip.add_child(tvbox)
	var title = Label.new()
	title.text = _object_display_name(obj_id)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", UI_GOLD_BRIGHT)
	tvbox.add_child(title)
	var uses = Label.new()
	uses.text = "剩余: %d" % int(item.get("uses", 1))
	uses.add_theme_font_size_override("font_size", 12)
	uses.add_theme_color_override("font_color", UI_TEXT_MUTED)
	tvbox.add_child(uses)
	var rule = Label.new()
	rule.text = "放置到相邻空格；可继续作为地图物体互动。"
	rule.add_theme_font_size_override("font_size", 12)
	rule.add_theme_color_override("font_color", UI_TEXT_WARM)
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD
	tvbox.add_child(rule)
	_card_tooltip.size = Vector2(230, 110)
	var card_pos = panel.global_position
	_card_tooltip.position = Vector2(card_pos.x - 40, card_pos.y - 122)
	_card_tooltip.visible = true

func _card_rule_lines(card_data: Dictionary) -> Array:
	var lines = []
	var target_type = card_data.get("targetType", "")
	var target_names = {
		"self": "自己",
		"adjacent_enemy": "相邻敌人",
		"enemy_in_range": "范围内敌人",
		"enemy_or_tile_in_range": "范围内敌人或格子",
		"adjacent_empty": "相邻空格/物品",
		"tile_in_range": "范围内格子",
		"area_3x3": "3x3区域",
		"ally": "友方",
	}
	var target_line = "目标: " + target_names.get(target_type, target_type)
	if int(card_data.get("range", 0)) > 0:
		target_line += "  射程%d" % int(card_data.get("range", 0))
	lines.append(target_line)
	for effect in card_data.get("effects", []):
		match effect.get("type", ""):
			"deal_damage":
				lines.append("效果: 造成%d点%s伤害" % [int(effect.get("value", 0)), "魔法" if effect.get("damageType", "") == "magic" else "物理"])
			"apply_status":
				lines.append("效果: 施加%s %d回合" % [_status_display_name(effect.get("statusId", "")), int(effect.get("duration", 1))])
			"add_terrain_effect":
				lines.append("场地层: 添加%s，不替换底层地形" % _effect_display_name(effect.get("effect", "")))
			"create_noise":
				lines.append("噪音: 强度%d 持续%d回合" % [int(effect.get("volume", 0)), int(effect.get("duration", 1))])
			"push_unit":
				lines.append("位移: 推退%d格，可推入陷阱/深渊" % int(effect.get("distance", 1)))
			"pull":
				lines.append("位移: 拉近%d格，可拉入陷阱/封印区" % int(effect.get("distance", 1)))
	return lines

func _status_display_name(status_id: String) -> String:
	return {
		"burn": "燃烧",
		"stun": "眩晕",
		"freeze": "冰冻",
		"poison": "中毒",
		"taunt": "嘲讽",
	}.get(status_id, status_id)

func _effect_display_name(effect_id: String) -> String:
	return {
		"fire": "火焰",
		"water_spread": "水渍",
		"rice": "糯米",
		"talisman": "符纸",
		"ink_line": "墨线",
		"explosion": "爆炸",
	}.get(effect_id, effect_id)

func _effect_rule_summary(effect_id: String, duration: int = 0) -> String:
	var remaining = "持续%d回合；" % duration if duration > 0 and duration < 90 else ""
	match effect_id:
		"fire":
			return "%s火焰层：每次结算2伤害，只点燃可燃标签。" % remaining
		"water_spread":
			return "%s水渍层：灭火，并让可燃物变湿。" % remaining
		"rice":
			return "糯米层：不改变底层地形，提供驱邪/压制灵体标签。"
		"talisman":
			return "符纸层：不改变底层地形，作为封印组件，怪物会害怕。"
		"ink_line":
			return "墨线层：阻挡灵体移动。"
		"explosion":
			return "%s爆炸层：一次性高伤害并产生巨响。" % remaining
		_:
			return "%s%s层。" % [remaining, _effect_display_name(effect_id)]

func _hide_card_tooltip() -> void:
	if _card_tooltip:
		_card_tooltip.visible = false

func _get_active_player() -> Dictionary:
	if state.selected_unit:
		var p = state.get_player_for_unit(state.selected_unit.id)
		if not p.is_empty() and p.unit != null and p.unit.is_alive and not state.is_unit_skipped(p.unit.id):
			return p
	for p in state.players:
		if p.unit.is_alive and not state.is_unit_skipped(p.unit.id):
			return p
	return {}

# Card widget creation is now inline in refresh_card_ui

func _on_discard_card(index: int) -> void:
	if state.current_turn != "player":
		return
	var player = _get_active_player()
	if player.is_empty():
		return
	if index < 0 or index >= player.hand.size:
		return
	var card_id = player.hand.card_ids[index]
	var removed = player.hand.remove_card(index)
	if removed != "":
		player.deck.discard_one(removed)
		state.hand_changed.emit.call_deferred()

func _on_card_clicked(index: int) -> void:
	if state.current_turn != "player":
		return
	var player = _get_active_player()
	if player.is_empty():
		return
	if state.is_unit_skipped(player.unit.id):
		return
	if index < 0 or index >= player.hand.size:
		return
	var card_data = player.hand.get_card(index)
	if card_data.is_empty() or state.team_ap < int(card_data.get("cost", 1)):
		return

	state.selected_unit = player.unit
	state.selected_card_index = index

	# Show targets without triggering select_unit (which rebuilds card UI)
	target_tiles = CardResolver.get_valid_targets(card_data, player.unit, state.map, state.all_units)
	reachable_tiles = []
	_queue_overlay_redraw()
	refresh_card_ui()
	_refresh_active_stats_panel()

func _build_spirit_bar() -> void:
	var bar = $HUD/SpiritBar
	if bar == null:
		return
	_spirit_label = $HUD/SpiritLabel
	_spirit_dots.clear()
	for child in bar.get_children():
		child.queue_free()
	for i in range(10):
		var dot = ColorRect.new()
		dot.custom_minimum_size = Vector2(14, 14)
		dot.size = Vector2(14, 14)
		dot.color = Color(0.25, 0.22, 0.3, 0.6)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(dot)
		_spirit_dots.append(dot)
	_refresh_spirit_bar()

func _refresh_spirit_bar() -> void:
	if spirit_system == null:
		return
	var density = state.spirit_density
	var tier_color: Color = spirit_system.get_tier_color()
	for i in range(_spirit_dots.size()):
		var dot = _spirit_dots[i] as ColorRect
		if dot == null:
			continue
		if i < density:
			dot.color = tier_color
		else:
			dot.color = Color(0.18, 0.15, 0.22, 0.55)
	if _spirit_label != null:
		_spirit_label.text = "灵气 %d/10  %s" % [density, spirit_system.get_tier_label()]

func _on_spirit_density_changed(_new_d: int, _old_d: int, _tier: String, _source: String) -> void:
	_refresh_spirit_bar()
	_refresh_top_status_title()
	_queue_scene_redraw()

func _on_spirit_tier_changed(new_tier: String, _old_tier: String) -> void:
	_refresh_spirit_bar()
	_refresh_top_status_title()
	if new_tier == "hundred_ghosts":
		_show_floating_text_at_grid_center("百鬼夜行！", Color(0.75, 0.2, 1.0))
	elif new_tier == "rage":
		_show_floating_text_at_grid_center("灵体暴走！", Color(1.0, 0.25, 0.2))
	elif new_tier == "reinforced":
		_show_floating_text_at_grid_center("灵气强化 — 封印可激活", Color(1.0, 0.6, 0.2))

func _show_floating_text_at_grid_center(text: String, color: Color) -> void:
	var center = Vector2i(state.map.cols / 2, state.map.rows / 2)
	_show_floating_text_at(center, text, color)
