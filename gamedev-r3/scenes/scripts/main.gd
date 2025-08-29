# main.gd — NON-PARALLAX background (Godot 4.x)
# Attach to your Main (Node2D). You place all art/positions in the editor.
extends Node2D

# ---------- TUNING ----------
@export var GRAVITY: float = 1800.0
@export var JUMP_VELOCITY: float = -640.0
@export var WORLD_SPEED: float = 320.0
@export var LIVES: int = 3
@export var SPAWN_MIN: float = 0.85
@export var SPAWN_MAX: float = 1.65
@export var PLAYER_STAND_HEIGHT: float = 60.0
@export var PLAYER_DUCK_HEIGHT: float = 34.0

# ---------- YOUR SCENES ----------
@export var TRASH_SCENE: PackedScene
@export var BIRD_SCENE: PackedScene

# ---------- REQUIRED PATHS (non-parallax) ----------
@export var BG1_PATH: NodePath               # Sprite2D (your pink city)
@export var BG2_PATH: NodePath               # Sprite2D (second copy; leave empty to auto-clone BG1)
@export var PLAYER_PATH: NodePath
@export var TRASH_Y_MARKER_PATH: NodePath
@export var BIRD_Y_MARKER_PATH: NodePath

# ---------- OPTIONAL UI ----------
@export var TIME_LABEL_PATH: NodePath
@export var HITS_LABEL_PATH: NodePath
@export var BIG_LABEL_PATH: NodePath

# ---------- RUNTIME ----------
var _bg1: Sprite2D
var _bg2: Sprite2D
var _bg_tile_w := 0.0

var _player: CharacterBody2D
var _player_sprite: Sprite2D
var _player_col: CollisionShape2D
var _player_vel := Vector2.ZERO
var _standing := true
var _current_h := 60.0

var _trash_y: Node2D
var _bird_y: Node2D

var _time_label: Label
var _hits_label: Label
var _big_label: Label

var _spawn_timer: Timer
var _obstacles: Array[Area2D] = []
var _time_alive := 0.0
var _hits := 0
var _game_over := false

func _ready() -> void:
	# --- backgrounds ---
	_bg1 = get_node_or_null(BG1_PATH) as Sprite2D
	_bg2 = get_node_or_null(BG2_PATH) as Sprite2D
	assert(_bg1, "Assign BG1_PATH (Sprite2D).")

	if _bg2 == null:
		_bg2 = _clone_bg(_bg1)
		add_child(_bg2)

	_bg_tile_w = _sprite_world_width(_bg1)
	_bg2.position.x = _bg1.position.x + _bg_tile_w

	# --- player & markers ---
	_player = get_node_or_null(PLAYER_PATH) as CharacterBody2D
	assert(_player, "Assign PLAYER_PATH.")
	_player_sprite = _player.get_node_or_null("Sprite2D") as Sprite2D
	_player_col = _player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	assert(_player_sprite and _player_col, "Player needs Sprite2D + CollisionShape2D (Rectangle).")

	_trash_y = get_node_or_null(TRASH_Y_MARKER_PATH) as Node2D
	_bird_y  = get_node_or_null(BIRD_Y_MARKER_PATH)  as Node2D
	assert(_trash_y and _bird_y, "Assign TrashY and BirdY markers.")

	_time_label = get_node_or_null(TIME_LABEL_PATH) as Label
	_hits_label = get_node_or_null(HITS_LABEL_PATH) as Label
	_big_label  = get_node_or_null(BIG_LABEL_PATH)  as Label
	if _big_label: _big_label.visible = false

	_current_h = PLAYER_STAND_HEIGHT
	_apply_duck(false)

	# spawner
	_spawn_timer = Timer.new()
	_spawn_timer.one_shot = true
	add_child(_spawn_timer)
	_spawn_timer.timeout.connect(_on_spawn_timer)
	_restart_spawn()

func _process(delta: float) -> void:
	if _game_over:
		if Input.is_physical_key_pressed(KEY_R):
			get_tree().reload_current_scene()
		return

	_time_alive += delta
	if _time_label: _time_label.text = "TIME  %.1fs" % _time_alive
	if _hits_label: _hits_label.text = "DANGER  %d / %d" % [_hits, LIVES]

	_scroll_background(delta)
	_move_obs(delta)
	_clean_obs()

func _physics_process(delta: float) -> void:
	if _game_over: return
	_handle_input()
	_player_vel.y += GRAVITY * delta
	_player.velocity = _player_vel
	_player.move_and_slide()

func _handle_input() -> void:
	var want_jump := Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_up")
	if want_jump and _player.is_on_floor() and _standing:
		_player_vel.y = JUMP_VELOCITY

	var ducking := Input.is_action_pressed("ui_down")
	if ducking == _standing:
		_standing = not ducking
		_apply_duck(ducking)

	if Input.is_physical_key_pressed(KEY_R):
		get_tree().reload_current_scene()

# ---------- BACKGROUND SCROLL (two Sprites loop) ----------
func _scroll_background(delta: float) -> void:
	var dx := WORLD_SPEED * delta
	_bg1.position.x -= dx
	_bg2.position.x -= dx

	if _bg1.global_position.x <= -_bg_tile_w:
		_bg1.global_position.x += 2.0 * _bg_tile_w
	if _bg2.global_position.x <= -_bg_tile_w:
		_bg2.global_position.x += 2.0 * _bg_tile_w

# ---------- SPAWNING ----------
func _on_spawn_timer() -> void:
	if _game_over: return
	_spawn_obstacle()
	_restart_spawn()

func _restart_spawn() -> void:
	_spawn_timer.start(randf_range(SPAWN_MIN, SPAWN_MAX))

func _spawn_obstacle() -> void:
	var make_bird := randi() % 2 == 0
	var scene := (BIRD_SCENE if make_bird else TRASH_SCENE)
	if scene == null: return
	var ob := scene.instantiate() as Area2D
	add_child(ob)
	var spawn_x := get_viewport_rect().size.x + 32.0
	var spawn_y := (_bird_y.global_position.y if make_bird else _trash_y.global_position.y)
	ob.global_position = Vector2(spawn_x, spawn_y)
	ob.body_entered.connect(func(b):
		if b == _player and not ob.has_meta("hit"):
			ob.set_meta("hit", true)
			ob.monitoring = false
			_on_hit()
	)
	_obstacles.push_back(ob)

func _move_obs(delta: float) -> void:
	var dx := WORLD_SPEED * delta
	for ob in _obstacles:
		if is_instance_valid(ob):
			ob.global_position.x -= dx

func _clean_obs() -> void:
	for i in range(_obstacles.size() - 1, -1, -1):
		var ob := _obstacles[i]
		if not is_instance_valid(ob) or ob.global_position.x < -120.0:
			if is_instance_valid(ob): ob.queue_free()
			_obstacles.remove_at(i)

# ---------- HITS / GAME OVER ----------
func _on_hit() -> void:
	if _game_over: return
	_hits += 1
	if _hits_label: _hits_label.text = "DANGER  %d / %d" % [_hits, LIVES]
	_flash_player()
	if _hits >= LIVES:
		_game_over = true
		if _big_label:
			_big_label.text = "GAME OVER\nTime: %.1fs\nPress R to Restart" % _time_alive
			_big_label.visible = true

func _flash_player() -> void:
	if not _player_sprite: return
	_player_sprite.modulate = Color(1, 0.3, 0.3)
	await get_tree().create_timer(0.12).timeout
	_player_sprite.modulate = Color(1, 1, 1)

# ---------- HELPERS ----------
func _apply_duck(is_ducking: bool) -> void:
	var target_h := PLAYER_DUCK_HEIGHT if is_ducking else PLAYER_STAND_HEIGHT
	if is_equal_approx(target_h, _current_h): return
	var rect := _player_col.shape as RectangleShape2D
	var old_h := _current_h
	var w := rect.size.x
	rect.size = Vector2(w, target_h)
	if _player.is_on_floor():
		_player.position.y += (old_h - target_h)
	if _player_sprite and _player_sprite.texture:
		var tw := _player_sprite.texture.get_width()
		var th := _player_sprite.texture.get_height()
		_player_sprite.scale = Vector2(w / max(1.0, tw), target_h / max(1.0, th))
	_current_h = target_h

func _sprite_world_width(s: Sprite2D) -> float:
	if s == null: return get_viewport_rect().size.x
	var tex_w := 0.0
	if s.region_enabled:
		tex_w = s.region_rect.size.x
	elif s.texture:
		tex_w = s.texture.get_width()
	else:
		tex_w = get_viewport_rect().size.x
	return tex_w * s.scale.x

func _clone_bg(src: Sprite2D) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = src.texture
	s.centered = src.centered
	s.region_enabled = src.region_enabled
	s.region_rect = src.region_rect
	s.scale = src.scale
	s.position = Vector2.ZERO
	return s
