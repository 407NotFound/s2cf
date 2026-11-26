extends Node3D
# S2CF 原型：S2 风格场景 + FPS 手感（持枪/开镜/后坐力/换弹）
# 全程序化生成，不依赖外部资源；后续把 CF 的角色/动画塞进来即可。

const MAG_SIZE := 30
const RESERVE_MAX := 120
const FIRE_INTERVAL := 0.095
const DAMAGE := 25

var player: CharacterBody3D
var cam: Camera3D
var muzzle: Node3D
var world: Node3D
var hud: CanvasLayer
var ammo_label: Label
var hit_label: Label
var state_label: Label
var fire_btn: Control
var fire_rect := Rect2()

var yaw := 0.0
var pitch := 0.0
var vel_y := 0.0
var recoil := 0.0          # 当前后坐角
var recoil_vel := 0.0
var ammo := MAG_SIZE
var reserve := 90
var fire_cd := 0.0
var reload_t := 0.0
var reloading := false
var ads := false
var shake := 0.0

var move_touch := -1
var look_touch := -1
var move_delta := Vector2()
var look_last := Vector2()
var firing := false
var touch_mode := false

func _ready() -> void:
	touch_mode = DisplayServer.is_touchscreen_available() or OS.has_feature("web")
	_build_world()
	_build_player()
	_build_hud()
	if not touch_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# ---------------- 世界 ----------------
func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.16, 0.19, 0.24)
	mat.sky_horizon_color = Color(0.42, 0.36, 0.30)
	mat.ground_horizon_color = Color(0.24, 0.22, 0.20)
	sky.sky_material = mat
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.7
	e.fog_enabled = true
	e.fog_light_color = Color(0.35, 0.33, 0.31)
	e.fog_density = 0.012
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 38, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)

	world = Node3D.new()
	add_child(world)

	# 地面
	_box(Vector3(70, 1, 70), Vector3(0, -0.5, 0), Color(0.30, 0.29, 0.27))
	# 场地边框
	_box(Vector3(70, 6, 1), Vector3(0, 3, -35), Color(0.22, 0.21, 0.20))
	_box(Vector3(70, 6, 1), Vector3(0, 3, 35), Color(0.22, 0.21, 0.20))
	_box(Vector3(1, 6, 70), Vector3(-35, 3, 0), Color(0.22, 0.21, 0.20))
	_box(Vector3(1, 6, 70), Vector3(35, 3, 0), Color(0.22, 0.21, 0.20))
	# 掩体 / 建筑体块（S2 那种矮墙 + 箱体节奏）
	var rng := RandomNumberGenerator.new()
	rng.seed = 20251127
	for i in 18:
		var w := rng.randf_range(2.0, 7.0)
		var h := rng.randf_range(1.2, 4.5)
		var d := rng.randf_range(2.0, 7.0)
		var px := rng.randf_range(-28.0, 28.0)
		var pz := rng.randf_range(-28.0, 28.0)
		if Vector2(px, pz).length() < 7.0:
			continue
		var tint := rng.randf_range(0.22, 0.42)
		_box(Vector3(w, h, d), Vector3(px, h * 0.5, pz), Color(tint, tint * 0.96, tint * 0.88))
	# 远处高塔剪影
	for i in 6:
		var h2 := rng.randf_range(10.0, 26.0)
		_box(Vector3(6, h2, 6), Vector3(rng.randf_range(-60.0, 60.0), h2 * 0.5, rng.randf_range(-60.0, 60.0)), Color(0.14, 0.14, 0.16))

func _box(size: Vector3, pos: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	mi.material_override = m
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	world.add_child(body)

# ---------------- 玩家 ----------------
func _build_player() -> void:
	player = CharacterBody3D.new()
	player.position = Vector3(0, 0.9, 12)
	add_child(player)

	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	cs.shape = cap
	player.add_child(cs)

	cam = Camera3D.new()
	cam.position = Vector3(0, 0.62, 0)
	cam.fov = 82.0
	cam.current = true
	player.add_child(cam)

	muzzle = Node3D.new()
	muzzle.position = Vector3(0.22, -0.16, -0.55)
	cam.add_child(muzzle)

	# 简易枪模型（占位，后面换成 CF 的武器 mesh）
	var gun := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(0.09, 0.13, 0.62)
	gun.mesh = gb
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.10, 0.10, 0.11)
	gm.metallic = 0.7
	gm.roughness = 0.35
	gun.material_override = gm
	gun.position = Vector3(0.16, -0.13, -0.42)
	cam.add_child(gun)

# ---------------- HUD ----------------
func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)

	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(c)

	# 准星
	for spec in [[Vector2(-1, -9), Vector2(2, 8)], [Vector2(-1, 2), Vector2(2, 8)],
				 [Vector2(-9, -1), Vector2(8, 2)], [Vector2(2, -1), Vector2(8, 2)]]:
		var r := ColorRect.new()
		r.color = Color(1, 1, 1, 0.85)
		r.position = spec[0] + Vector2(640, 360) - Vector2(0, 0)
		r.size = spec[1]
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(r)

	ammo_label = Label.new()
	ammo_label.position = Vector2(1040, 620)
	ammo_label.add_theme_font_size_override("font_size", 34)
	ammo_label.text = "30 / 90"
	c.add_child(ammo_label)

	state_label = Label.new()
	state_label.position = Vector2(40, 40)
	state_label.add_theme_font_size_override("font_size", 18)
	state_label.text = "S2CF prototype"
	c.add_child(state_label)

	hit_label = Label.new()
	hit_label.position = Vector2(600, 250)
	hit_label.add_theme_font_size_override("font_size", 30)
	hit_label.text = ""
	c.add_child(hit_label)

	if touch_mode:
		fire_btn = Control.new()
		fire_btn.position = Vector2(1040, 470)
		fire_btn.size = Vector2(150, 150)
		fire_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(fire_btn)
		fire_rect = Rect2(fire_btn.position, fire_btn.size)
		var circle := ColorRect.new()
		circle.color = Color(0.9, 0.25, 0.2, 0.35)
		circle.size = fire_btn.size
		circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fire_btn.add_child(circle)
		var lbl := Label.new()
		lbl.text = "FIRE"
		lbl.position = Vector2(48, 58)
		lbl.add_theme_font_size_override("font_size", 22)
		fire_btn.add_child(lbl)

# ---------------- 输入 ----------------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not touch_mode:
		yaw -= event.relative.x * 0.0026
		pitch -= event.relative.y * 0.0022
		pitch = clamp(pitch, -1.35, 1.35)
	elif event is InputEventScreenTouch:
		if event.pressed:
			if touch_mode and fire_rect.has_point(event.position):
				firing = true
			elif event.position.x < 640 and move_touch == -1:
				move_touch = event.index
				move_delta = Vector2.ZERO
			elif look_touch == -1:
				look_touch = event.index
				look_last = event.position
		else:
			if event.index == move_touch:
				move_touch = -1
				move_delta = Vector2.ZERO
			if event.index == look_touch:
				look_touch = -1
			firing = false
	elif event is InputEventScreenDrag:
		if event.index == move_touch:
			move_delta = (event.position - Vector2(200, 500)) / 90.0
			move_delta = move_delta.limit_length(1.0)
		elif event.index == look_touch:
			yaw -= (event.position.x - look_last.x) * 0.0045
			pitch -= (event.position.y - look_last.y) * 0.004
			pitch = clamp(pitch, -1.35, 1.35)
			look_last = event.position
	elif event is InputEventKey and event.pressed and event.keycode == KEY_R:
		_start_reload()

func _read_move() -> Vector2:
	if touch_mode:
		return move_delta
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): v.y += 1
	if Input.is_key_pressed(KEY_S): v.y -= 1
	if Input.is_key_pressed(KEY_A): v.x -= 1
	if Input.is_key_pressed(KEY_D): v.x += 1
	return v.limit_length(1.0)

# ---------------- 主循环 ----------------
func _process(delta: float) -> void:
	if not touch_mode:
		ads = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		firing = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		if Input.is_key_pressed(KEY_SHIFT):
			pass

	# 视角
	player.rotation.y = yaw
	recoil_vel += -recoil * 26.0 * delta
	recoil_vel *= 0.86
	recoil += recoil_vel * delta
	cam.rotation.x = clamp(pitch + recoil, -1.5, 1.5)
	cam.fov = lerp(cam.fov, 55.0 if ads else 82.0, 1.0 - pow(0.001, delta))

	# 移动
	var dir := _read_move()
	var speed := 4.4 if ads else 6.2
	var wish := (player.global_basis * Vector3(dir.x, 0, -dir.y))
	player.velocity.x = lerp(player.velocity.x, wish.x * speed, 1.0 - pow(0.0005, delta))
	player.velocity.z = lerp(player.velocity.z, wish.z * speed, 1.0 - pow(0.0005, delta))
	if not player.is_on_floor():
		vel_y -= 22.0 * delta
	else:
		vel_y = 0.0
	player.velocity.y = vel_y
	player.move_and_slide()

	# 射击
	fire_cd -= delta
	if reloading:
		reload_t -= delta
		if reload_t <= 0.0:
			var need := MAG_SIZE - ammo
			var take: int = min(need, reserve)
			ammo += take
			reserve -= take
			reloading = false
			_update_ammo()
	elif firing and fire_cd <= 0.0 and ammo > 0:
		_shoot()
		fire_cd = FIRE_INTERVAL
	elif firing and ammo == 0:
		_start_reload()

	shake = max(0.0, shake - delta * 4.0)
	hit_label.modulate.a = max(0.0, hit_label.modulate.a - delta * 2.2)

func _shoot() -> void:
	ammo -= 1
	_update_ammo()
	recoil_vel += 0.055
	yaw += randf_range(-0.004, 0.004)
	shake = 1.0

	var from := cam.global_position
	var c := Vector2(640, 360)
	var to := from + (-cam.global_transform.basis.z) * 300.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		hit_label.text = "HIT"
		hit_label.modulate = Color(1, 0.85, 0.4)
		hit_label.modulate.a = 1.0

func _start_reload() -> void:
	if reloading or ammo == MAG_SIZE or reserve <= 0:
		return
	reloading = true
	reload_t = 1.9
	state_label.text = "RELOADING..."

func _update_ammo() -> void:
	ammo_label.text = "%d / %d" % [ammo, reserve]
