extends Node2D
## Main — 메인 게임 루프. mino1 의 PlayScene 에 해당.
## S0: 2200x2200 월드 + 풀밭(타일) 배경 + 플레이어 추적 카메라 + 플레이어 + 가상 조이스틱.
## 적·전투·HUD 등은 다음 단계(S1~)에서 이 위에 쌓는다.

const FONT_PATH := "res://fonts/Jua-Regular.ttf"
const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const ENEMY_SCENE := preload("res://scenes/Enemy.tscn")
const FX_SCENE := preload("res://scenes/Fx.gd")
const HUD_SCRIPT := preload("res://ui/HUD.gd")
const LEVELUP_SCRIPT := preload("res://ui/LevelupPanel.gd")
const STAT_SCRIPT := preload("res://ui/StatPanel.gd")
const SKILLS_SCRIPT := preload("res://systems/Skills.gd")
const JOB_SCRIPT := preload("res://ui/JobPanel.gd")
const SKILL_TRAY_SCRIPT := preload("res://ui/SkillTray.gd")
const SKILL_MENU_SCRIPT := preload("res://ui/SkillMenu.gd")
const INVENTORY_SCRIPT := preload("res://systems/Inventory.gd")
const LOOT_SCRIPT := preload("res://systems/Loot.gd")
const INV_PANEL_SCRIPT := preload("res://ui/InventoryPanel.gd")
const COOK_HUD_SCRIPT := preload("res://ui/CookHUD.gd")
const TERRAIN_SCRIPT := preload("res://systems/Terrain.gd")
const BOSS_SCENE := preload("res://scenes/Boss.tscn")
const DIFFICULTY_SCRIPT := preload("res://ui/DifficultyPanel.gd")
const WORLDMAP_SCRIPT := preload("res://ui/WorldMapPanel.gd")
const COMPANION_SCRIPT := preload("res://scenes/Companion.gd")

const GRASS_TILE := 384       # mino1 grass_soft 타일 크기
const JOY_MAX := 62.0         # 조이스틱 최대 반경 (mino1 과 동일)
const JOY_RADIUS := 64.0      # 베이스 원 표시 반경

# ── 전투 코어 상수 (mino1 play.js) ─────────────────────────
const MAX_ENEMIES := 10        # 동시 최대 적 수
const SPAWN_INTERVAL := 1.4    # 스폰 간격(초)

var kfont: Font
var player: CharacterBody2D
var camera: Camera2D

# ── 전투/연출 상태 ─────────────────────────────────────────
var enemies: Array = []        # 살아있는 Enemy 노드들
var spawn_timer := 0.0
var time_scale := 1.0          # 히트스톱용 시간 배율 (1=정상, 0.08=정지에 가까움)
var hitstop_t := 0.0           # 남은 히트스톱 시간
var fx: Node2D = null          # Fx 레이어
var fx_text_layer: Node2D = null  # 데미지 숫자(월드 라벨) 부모
var float_texts: Array = []    # [{label, vel, life, t, wobble, base_x}]
var shake_t := 0.0            # 카메라 흔들림 남은 시간
var shake_amp := 0.0          # 흔들림 세기
var atk_btn_pressed := false   # 공격 버튼 눌림
var rng := RandomNumberGenerator.new()

# 가상 조이스틱 상태 (mino1: this.joy)
var joy_active := false
var joy_id := -1
var joy_base := Vector2.ZERO   # 처음 누른 화면 위치
var joy_knob := Vector2.ZERO   # 현재 손가락 위치(반경 제한)
var joy_vec := Vector2.ZERO    # -1~1 방향
var joy_layer: CanvasLayer
var joy_draw: Node2D

var info_label: Label

# ── 성장(S2): HUD·레벨업 선택창·스탯 분배창 ─────────────────
var hud: Control = null
var lvlup_panel = null            # LevelupPanel (레벨업 3택)
var stat_panel = null             # StatPanel (스탯 분배)
# 레벨업 스킬 선택 등에 쓰는 결정론 RNG (mino1 this._rng) — 시드 저장값 기준
var _core_rng: GameData.RNG = null

# ── 전직·스킬 (S3) ─────────────────────────────────────────
var skills: Node = null           # SkillSystem (스킬 엔진 — 투사체·메테오·장판·소환)
var job_panel = null              # JobPanel (전직 선택창)
var skill_tray = null             # SkillTray (우하단 스킬 버튼들)
var skill_menu = null             # SkillMenu (전직 스킬 메뉴)
var flash_node: Node2D = null     # 화면 전체 색 플래시 오버레이

# ── 장비·요리·골드 (S4) ─────────────────────────────────────
var inventory: Node = null        # InventorySystem (장착/해제/줍기/판매 단일 권한)
var loot: Node2D = null           # LootSystem (바닥 장비·날고기·그릴·요리, 월드 좌표)
var inv_panel = null              # InventoryPanel (가방 버튼 + 장비 창)
var cook_hud = null               # CookHUD (좌하단 고기 패널 + 먹기 버튼)
var food_buff_t := 0.0            # 고기 먹기 짧은 버프 남은 시간(S5/S6 버프 연동용 자리)

# ── 지역·보스·난이도 (S5) ───────────────────────────────────
var terrain: Node2D = null        # TerrainSystem (지역별 바위·독·버프 + 효과)
var boss: Node = null             # 현재 보스 노드 (없으면 null)
var boss_spawned := false         # 이 지역에서 보스가 이미 등장했나 (중복 방지)
var diff_panel = null             # DifficultyPanel (난이도 선택창)
var worldmap_panel = null         # WorldMapPanel (세계 지도)
var _chapter_clear_layer: CanvasLayer = null  # 챕터 클리어/지역 입장 배너(탭 대기)
var _banner_tap_action := ""      # "" | "to_worldmap" — 배너 탭 시 동작

# ── 연출·사운드 마감 (S6) ───────────────────────────────────
var companion: Node2D = null      # 동료 카피바라 (따라오기·힐·말풍선)
var intro_layer: CanvasLayer = null   # 인트로 스토리 오버레이
var story_layer: CanvasLayer = null   # 챕터 스토리 오버레이
# 이스터에그 상태 (mino1 _egg*)
var egg_tl_used := false          # 좌상단 +10 (1회)
var egg_used := false             # 좌하단 12연타 +12 (1회)
var egg_attack_count := 0
var egg_attack_timer := 0.0
var egg_prev_atk := false
var sound_btn_ctrl: Control = null


func _ready() -> void:
	if ResourceLoader.exists(FONT_PATH):
		kfont = load(FONT_PATH)
	rng.randomize()
	_core_rng = GameData.make_rng(GameState.seed_val)
	# 챕터는 보통 region+1 (저장값이 있으면 그것 — 난이도 스케일에 쓰임)
	if GameState.chapter < 1:
		GameState.chapter = GameState.region + 1

	_build_inventory()       # 인벤토리 시스템(순수 로직) — 다른 빌드보다 먼저(loot·패널·전직이 참조)
	_build_world()
	_build_player()
	_build_camera()
	_build_fx()
	_build_terrain()         # 지역별 바위·독·버프(월드 좌표) — fx 뒤, loot 앞
	_build_loot()            # 바닥 장비·날고기·그릴(월드 좌표) — fx·player 뒤
	_build_skills()
	_build_joystick()
	_build_attack_button()
	_build_growth_ui()
	_build_skill_ui()
	_build_inv_ui()          # 가방 버튼·장비 창 + 요리 HUD
	_build_region_ui()       # 난이도 선택창 + 세계 지도 + 처음부터 버튼
	_build_flash()
	_build_info()
	_build_companion()       # 동료 카피바라 (player 뒤)
	_build_mino_sig()        # mino 시그니처 워터마크 (우측)
	_build_sound_button()    # 소리 켜고/끄기 토글
	_build_overlay_ticker()  # 인트로/챕터 스토리 페이드 (일시정지 중에도 도는 ALWAYS 틱)

	# 보스 등장 플래그: 이 지역에서 아직 안 잡았으면 false (저장과 무관, 세션 단위)
	boss_spawned = false

	# BGM 시작 (음소거면 알아서 안 남)
	Audio.start_bgm()

	# ── 화면 흐름 (mino1): 인트로 → (난이도) → 게임 ──
	# 첫 실행(난이도 미선택)이면: 인트로 스토리를 보여주고, 끝나면 난이도 선택창.
	# 이미 진행 중(난이도 선택됨)이면 바로 게임.
	if GameState.difficulty < 0:
		_show_intro()        # 끝나면(_end_intro) 난이도 선택창을 띄움
	elif not GameState.seen_intro:
		# 난이도는 정해졌지만 이번 세션 인트로를 아직 안 봤으면 한 번 보여준다
		_show_intro()


# ── 성장 UI: HUD + 레벨업 선택창 + 스탯 분배창 (S2) ──────────
func _build_growth_ui() -> void:
	# HUD (항상 보이는 정보판)
	var hud_layer := CanvasLayer.new()
	hud_layer.name = "HudLayer"
	hud_layer.layer = 5
	add_child(hud_layer)
	hud = Control.new()
	hud.name = "HUD"
	hud.set_script(HUD_SCRIPT)
	hud.set("main", self)
	hud_layer.add_child(hud)

	# 스탯 분배창 (HUD 위, 레벨업창 아래)
	var stat_layer := CanvasLayer.new()
	stat_layer.name = "StatLayer"
	stat_layer.layer = 8
	add_child(stat_layer)
	stat_panel = Control.new()
	stat_panel.name = "StatPanel"
	stat_panel.set_script(STAT_SCRIPT)
	stat_panel.set("main", self)
	stat_layer.add_child(stat_panel)

	# 레벨업 선택창 (위, 게임 일시정지)
	var lvl_layer := CanvasLayer.new()
	lvl_layer.name = "LevelupLayer"
	lvl_layer.layer = 10
	lvl_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(lvl_layer)
	lvlup_panel = Control.new()
	lvlup_panel.name = "LevelupPanel"
	lvlup_panel.set_script(LEVELUP_SCRIPT)
	lvlup_panel.set("main", self)
	lvl_layer.add_child(lvlup_panel)

	# 전직 선택창 (제일 위 — 레벨업보다 먼저 뜸, 게임 일시정지)
	var job_layer := CanvasLayer.new()
	job_layer.name = "JobLayer"
	job_layer.layer = 11
	job_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(job_layer)
	job_panel = Control.new()
	job_panel.name = "JobPanel"
	job_panel.set_script(JOB_SCRIPT)
	job_panel.set("main", self)
	job_layer.add_child(job_panel)


# 레벨업 스킬 선택에 쓰는 결정론 RNG (mino1 this._rng) — LevelupPanel 이 호출
func core_rng() -> GameData.RNG:
	if _core_rng == null:
		_core_rng = GameData.make_rng(GameState.seed_val)
	return _core_rng


# ── 월드: 풀밭 타일 배경 (2200x2200) ────────────────────────
func _build_world() -> void:
	# 현재 지역 색조 (mino1: REGION_DEFS[region].ground_tint)
	var region_idx: int = clampi(GameState.region, 0, GameData.REGION_DEFS.size() - 1)
	var tint: Color = GameData.REGION_DEFS[region_idx]["ground_tint"]

	var bg := Sprite2D.new()
	bg.name = "Ground"
	bg.texture = _make_grass_tex()
	bg.region_enabled = true
	bg.region_rect = Rect2(0, 0, GameData.WORLD_W, GameData.WORLD_H)
	# region_rect 가 타일 텍스처를 반복(타일링)하게 하려면 texture_repeat 필요
	bg.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	bg.centered = false
	bg.position = Vector2.ZERO
	bg.modulate = tint
	bg.z_index = -100
	add_child(bg)

	# 월드 테두리(경계 시각화) — 어두운 선
	var border := Line2D.new()
	border.name = "WorldBorder"
	border.points = PackedVector2Array([
		Vector2(0, 0), Vector2(GameData.WORLD_W, 0),
		Vector2(GameData.WORLD_W, GameData.WORLD_H), Vector2(0, GameData.WORLD_H),
		Vector2(0, 0),
	])
	border.width = 6.0
	border.default_color = Color(0.10, 0.13, 0.08, 0.8)
	border.z_index = -90
	add_child(border)


func _build_player() -> void:
	player = PLAYER_SCENE.instantiate()
	player.main = self
	add_child(player)


# ── 이펙트 레이어 (파티클·임팩트·예고·슬래시 + 데미지 숫자) ──
func _build_fx() -> void:
	fx = Node2D.new()
	fx.name = "Fx"
	fx.set_script(FX_SCENE)
	fx.set("main", self)
	fx.z_index = 3000        # 적(y<=2200)보다 위 (z_index 최대 4096)
	add_child(fx)
	# 데미지 숫자(월드 라벨)는 적·파티클보다 위
	fx_text_layer = Node2D.new()
	fx_text_layer.name = "FloatTexts"
	fx_text_layer.z_index = 3500
	add_child(fx_text_layer)


# ── 스킬 엔진 (월드 좌표 Node2D — 투사체·메테오·장판·소환) ──
func _build_skills() -> void:
	skills = Node2D.new()
	skills.name = "Skills"
	skills.set_script(SKILLS_SCRIPT)
	skills.set("main", self)
	skills.z_index = 2900     # 적 위, Fx(3000) 아래 정도
	add_child(skills)


# ── 스킬 UI: 우하단 스킬 트레이 + 전직 스킬 메뉴 ─────────────
func _build_skill_ui() -> void:
	# 스킬 트레이 (버튼들) — 공격 버튼과 같은 레이어대(작업대)
	var tray_layer := CanvasLayer.new()
	tray_layer.name = "SkillTrayLayer"
	tray_layer.layer = 4
	add_child(tray_layer)
	skill_tray = Control.new()
	skill_tray.name = "SkillTray"
	skill_tray.set_script(SKILL_TRAY_SCRIPT)
	skill_tray.set("main", self)
	tray_layer.add_child(skill_tray)

	# 전직 스킬 메뉴 (패널 — 일시정지)
	var menu_layer := CanvasLayer.new()
	menu_layer.name = "SkillMenuLayer"
	menu_layer.layer = 9
	menu_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(menu_layer)
	skill_menu = Control.new()
	skill_menu.name = "SkillMenu"
	skill_menu.set_script(SKILL_MENU_SCRIPT)
	skill_menu.set("main", self)
	menu_layer.add_child(skill_menu)


# ── 인벤토리 시스템 (순수 로직 — 장착/해제/줍기/판매 단일 권한) ──
func _build_inventory() -> void:
	inventory = Node.new()
	inventory.name = "Inventory"
	inventory.set_script(INVENTORY_SCRIPT)
	inventory.set("main", self)
	add_child(inventory)


# ── 지형(지역별 바위·독·버프, 월드 좌표 Node2D) ─────────────
func _build_terrain() -> void:
	terrain = Node2D.new()
	terrain.name = "Terrain"
	terrain.set_script(TERRAIN_SCRIPT)
	terrain.set("main", self)
	terrain.z_index = -70   # 풀밭(-100) 위, 캐릭터/아이템 아래 (바닥에 깔린 지형)
	add_child(terrain)


# ── 루트(바닥 장비·날고기·그릴·요리, 월드 좌표 Node2D) ───────
func _build_loot() -> void:
	loot = Node2D.new()
	loot.name = "Loot"
	loot.set_script(LOOT_SCRIPT)
	loot.set("main", self)
	loot.z_index = 50   # 적(y기반)보다 위지만 Fx(3000) 아래 — 바닥 아이템 느낌
	add_child(loot)


# ── 지역 UI: 난이도 선택창 + 세계 지도 + 처음부터 버튼 (S5) ──
func _build_region_ui() -> void:
	# 난이도 선택창 (제일 위 — 일시정지)
	var diff_layer := CanvasLayer.new()
	diff_layer.name = "DifficultyLayer"
	diff_layer.layer = 13
	diff_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(diff_layer)
	diff_panel = Control.new()
	diff_panel.name = "DifficultyPanel"
	diff_panel.set_script(DIFFICULTY_SCRIPT)
	diff_panel.set("main", self)
	diff_layer.add_child(diff_panel)

	# 세계 지도 (난이도 아래, 일시정지)
	var map_layer := CanvasLayer.new()
	map_layer.name = "WorldMapLayer"
	map_layer.layer = 12
	map_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(map_layer)
	worldmap_panel = Control.new()
	worldmap_panel.name = "WorldMapPanel"
	worldmap_panel.set_script(WORLDMAP_SCRIPT)
	worldmap_panel.set("main", self)
	map_layer.add_child(worldmap_panel)

	# 우상단 '처음부터(↻)' 버튼 — 난이도부터 다시 (mino1 _restartBtn)
	_build_restart_button()


# ── 장비 창(가방 버튼) + 요리 HUD ───────────────────────────
func _build_inv_ui() -> void:
	# 가방 버튼 + 장비 창 (패널 열리면 일시정지 → ALWAYS 레이어)
	var inv_layer := CanvasLayer.new()
	inv_layer.name = "InvLayer"
	inv_layer.layer = 8   # 스탯창과 같은 대(둘 다 토글 패널)
	inv_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(inv_layer)
	inv_panel = Control.new()
	inv_panel.name = "InventoryPanel"
	inv_panel.set_script(INV_PANEL_SCRIPT)
	inv_panel.set("main", self)
	inv_layer.add_child(inv_panel)

	# 요리 HUD (좌하단 고기 패널 + 먹기 버튼) — 그리기 전용
	var cook_layer := CanvasLayer.new()
	cook_layer.name = "CookLayer"
	cook_layer.layer = 4   # 스킬 트레이와 같은 대(작업대 버튼들)
	add_child(cook_layer)
	cook_hud = Control.new()
	cook_hud.name = "CookHUD"
	cook_hud.set_script(COOK_HUD_SCRIPT)
	cook_hud.set("main", self)
	cook_layer.add_child(cook_hud)


# ── 처음부터(↻) 버튼 — 우상단, 가방·STAT 버튼 아래 (mino1 _restartBtn) ──
var restart_btn_ctrl: Control = null
func _build_restart_button() -> void:
	var layer := CanvasLayer.new()
	layer.name = "RestartLayer"
	layer.layer = 4   # 다른 작업대 버튼들과 같은 대
	add_child(layer)
	var ctrl := Control.new()
	ctrl.name = "RestartBtn"
	ctrl.anchor_left = 1.0
	ctrl.anchor_right = 1.0
	ctrl.offset_left = -76.0
	ctrl.offset_top = 108.0
	ctrl.offset_right = -12.0
	ctrl.offset_bottom = 152.0
	ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(ctrl)
	var dn := Node2D.new()
	dn.set_script(_make_restart_draw_script())
	dn.set("ctrl", ctrl)
	ctrl.add_child(dn)
	ctrl.gui_input.connect(_on_restart_input)
	restart_btn_ctrl = ctrl


func _on_restart_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventScreenTouch and event.pressed) or \
		(event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed)
	if not pressed:
		return
	# 다른 창이 떠 있으면 무시 (실수 방지)
	if get_tree().paused:
		return
	# 처음부터 = 진행 초기화 + 난이도부터 다시 (mino1 _newGame)
	GameState.new_game(GameState.difficulty if GameState.difficulty >= 0 else 1)
	if diff_panel:
		diff_panel.open()


func _make_restart_draw_script() -> GDScript:
	var src := """
extends Node2D
var ctrl
func _process(_d):
	queue_redraw()
func _draw():
	if ctrl == null:
		return
	var r = Rect2(0, 0, ctrl.size.x, ctrl.size.y)
	draw_rect(r, Color(0.18, 0.1, 0.12, 0.7), true)
	draw_rect(r, Color(0.75, 0.31, 0.31, 0.9), false, 2.0)
	var c = ctrl.size / 2.0
	var rad = min(ctrl.size.x, ctrl.size.y) * 0.28
	draw_arc(c, rad, -2.2, 2.2, 20, Color(1, 0.8, 0.8, 0.9), 3.0)
	# 화살촉
	var tip = c + Vector2(cos(2.2), sin(2.2)) * rad
	draw_circle(tip, 3.0, Color(1, 0.8, 0.8, 0.9))
"""
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


# ── 화면 전체 색 플래시 오버레이 (mino1 _flashGfx) ───────────
func _build_flash() -> void:
	var layer := CanvasLayer.new()
	layer.name = "FlashLayer"
	layer.layer = 7   # HUD·info 위, 스탯창 아래
	add_child(layer)
	flash_node = Node2D.new()
	flash_node.name = "Flash"
	flash_node.set_script(_make_flash_script())
	flash_node.set("main", self)
	layer.add_child(flash_node)


func _make_flash_script() -> GDScript:
	var src := """
extends Node2D
var main
func _process(_d):
	queue_redraw()
func _draw():
	if main == null or main.skills == null:
		return
	var a = main.skills.flash_alpha()
	if a > 0.001:
		var c = main.skills.flash_color
		var vp = get_viewport().get_visible_rect().size
		draw_rect(Rect2(0, 0, vp.x, vp.y), Color(c.r, c.g, c.b, a), true)
"""
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _build_camera() -> void:
	camera = Camera2D.new()
	camera.name = "Camera"
	# 플레이어를 부드럽게 따라간다 (mino1: startFollow lerp 0.14)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	# 카메라가 월드 밖을 안 보이게 경계 제한
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(GameData.WORLD_W)
	camera.limit_bottom = int(GameData.WORLD_H)
	player.add_child(camera)
	camera.make_current()


# ── 가상 조이스틱 (mino1: setupJoystick/drawJoystick) ────────
func _build_joystick() -> void:
	joy_layer = CanvasLayer.new()
	joy_layer.name = "JoyLayer"
	add_child(joy_layer)
	joy_draw = Node2D.new()
	joy_draw.name = "JoyDraw"
	joy_draw.set_script(_make_joy_draw_script())
	joy_draw.set("main", self)
	joy_layer.add_child(joy_draw)


# 조이스틱을 그리는 작은 Node2D 스크립트 (_draw 로 원 그림)
func _make_joy_draw_script() -> GDScript:
	var src := """
extends Node2D
var main
func _process(_d):
	queue_redraw()
func _draw():
	if main == null or not main.joy_active:
		return
	var base = main.joy_base
	var knob = main.joy_knob
	# 베이스 원 (반투명 검정)
	draw_circle(base, 64.0, Color(0, 0, 0, 0.22))
	draw_arc(base, 64.0, 0.0, TAU, 48, Color(1, 1, 1, 0.25), 2.0)
	# 노브 (연두)
	draw_circle(knob, 28.0, Color(0.81, 0.88, 0.69, 0.55))
"""
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _build_info() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UILayer"
	layer.layer = 6   # HUD(5) 위, 스탯창(8) 아래
	add_child(layer)
	# 화면 하단 가운데 — 짧은 안내/게임오버 메시지 (HUD 와 겹치지 않게)
	info_label = Label.new()
	if kfont:
		info_label.add_theme_font_override("font", kfont)
	info_label.add_theme_font_size_override("font_size", 24)
	info_label.add_theme_color_override("font_color", Color.WHITE)
	info_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	info_label.add_theme_constant_override("outline_size", 6)
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.anchor_left = 0.0
	info_label.anchor_right = 1.0
	info_label.anchor_top = 1.0
	info_label.anchor_bottom = 1.0
	info_label.offset_top = -240.0
	info_label.offset_bottom = -210.0
	info_label.text = "왼쪽=이동  ·  오른쪽 버튼=공격"
	layer.add_child(info_label)


# ── 공격 버튼 (오른쪽 아래, 터치) (mino1 공격 버튼) ──────────
var atk_btn: TouchScreenButton
func _build_attack_button() -> void:
	var layer := CanvasLayer.new()
	layer.name = "AtkLayer"
	add_child(layer)

	var ctrl := Control.new()
	ctrl.name = "AtkButton"
	ctrl.anchor_left = 1.0
	ctrl.anchor_top = 1.0
	ctrl.anchor_right = 1.0
	ctrl.anchor_bottom = 1.0
	ctrl.offset_left = -180.0
	ctrl.offset_top = -200.0
	ctrl.offset_right = -40.0
	ctrl.offset_bottom = -60.0
	ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(ctrl)

	# 원형 버튼 그림 (코드 Node2D _draw)
	var draw_node := Node2D.new()
	draw_node.set_script(_make_atk_draw_script())
	draw_node.set("ctrl", ctrl)
	ctrl.add_child(draw_node)

	ctrl.gui_input.connect(_on_atk_input)
	# 손가락이 버튼 밖으로 나가도 떼면 풀리게
	ctrl.mouse_exited.connect(func(): pass)
	atk_label_ctrl = ctrl


var atk_label_ctrl: Control
func _on_atk_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		atk_btn_pressed = event.pressed


func _make_atk_draw_script() -> GDScript:
	var src := """
extends Node2D
var ctrl
func _process(_d):
	queue_redraw()
func _draw():
	if ctrl == null:
		return
	var c = ctrl.size / 2.0
	var r = min(ctrl.size.x, ctrl.size.y) / 2.0
	draw_circle(c, r, Color(0.9, 0.35, 0.3, 0.55))
	draw_arc(c, r, 0.0, TAU, 40, Color(1, 1, 1, 0.5), 3.0)
	# 칼 모양 간단 표시 (대각선 두 선)
	draw_line(c + Vector2(-r*0.3, r*0.3), c + Vector2(r*0.3, -r*0.3), Color(1,1,1,0.85), 5.0)
"""
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


# ── 입력: 가상 조이스틱 ─────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	# 터치 + 마우스(데스크톱 테스트) 둘 다 처리
	if event is InputEventScreenTouch:
		_handle_touch(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_handle_drag(event.index, event.position)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_touch(-2, event.position, event.pressed)
	elif event is InputEventMouseMotion:
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_handle_drag(-2, event.position)


func _handle_touch(id: int, pos: Vector2, pressed: bool) -> void:
	var vp_w := get_viewport().get_visible_rect().size.x
	if pressed:
		# 스킬 버튼 먼저 검사 (mino1: 스킬 버튼 → 공격 → 이동 순) — 적중하면 소비
		if skill_tray and skill_tray.try_hit(pos):
			return
		# 먹기 버튼(좌하단) — 조이스틱보다 먼저 검사(이동으로 안 새게)
		if cook_hud and cook_hud.try_eat(pos):
			return
		# 화면 왼쪽 60% 에서만 조이스틱 시작 (mino1 과 동일)
		if not joy_active and pos.x < vp_w * 0.6:
			joy_active = true
			joy_id = id
			joy_base = pos
			joy_knob = pos
			joy_vec = Vector2.ZERO
	else:
		if id == joy_id:
			_release_joy()


func _handle_drag(id: int, pos: Vector2) -> void:
	if joy_active and id == joy_id:
		var d := pos - joy_base
		var mag := d.length()
		if mag > JOY_MAX:
			d = d / mag * JOY_MAX
		joy_knob = joy_base + d
		joy_vec = d / JOY_MAX


func _release_joy() -> void:
	joy_active = false
	joy_id = -1
	joy_vec = Vector2.ZERO


func _process(delta: float) -> void:
	# 조이스틱 방향을 플레이어에 전달
	if player:
		player.joy_vec = joy_vec if joy_active else Vector2.ZERO

	# ── 히트스톱: 시간 배율 (mino1 _hitstopT) ──
	if hitstop_t > 0.0:
		hitstop_t -= delta   # 히트스톱 타이머는 실시간으로 흐른다
		time_scale = 0.08
		if hitstop_t <= 0.0:
			hitstop_t = 0.0
			time_scale = 1.0
	else:
		time_scale = 1.0

	var dt := delta * time_scale

	# ── 지형 효과 (바위 밀어냄·독 피해·버프 존) ──
	if terrain:
		terrain.update(dt)

	# ── 스폰 ──
	_update_spawn(dt)

	# ── 전투 판정 (공격 입력 → 명중) ──
	_update_combat(dt)

	# ── 보스 등장 체크 (지역별 목표 킬 수, 1회만) (mino1) ──
	var boss_kill_trigger := 12 + GameState.chapter * 4
	if not boss_spawned and int(GameState.player.get("kills", 0)) >= boss_kill_trigger:
		boss_spawned = true
		_spawn_boss()

	# ── HP/MP 자동 회복 (난이도 regen) ──
	_update_regen(dt)

	# ── 고기 버프 타이머 (효과 연동은 S5/S6) ──
	if food_buff_t > 0.0:
		food_buff_t = maxf(0.0, food_buff_t - dt)

	# ── 스킬 갱신 (쿨다운·투사체·메테오·장판·소환·마나회복·플래시) ──
	if skills:
		skills.update(dt)

	# ── 데미지 숫자 갱신 ──
	_update_float_texts(dt)

	# ── 슬래시 이펙트: 플레이어 위치 따라 ──
	if player and player.slash_t > 0.0:
		fx.slash = {"pos": player.global_position, "face": player.face,
			"range": float(GameState.player.get("atkRange", 64)), "t": player.slash_t}

	# ── 카메라 흔들림 ──
	_update_shake(delta)

	# ── 이스터에그 (좌상단 +10 / 좌하단 12연타 +12) ──
	_update_easter_egg(dt)

	# 죽은 적 목록 정리
	for i in range(enemies.size() - 1, -1, -1):
		var e = enemies[i]
		if not is_instance_valid(e) or e.dead:
			enemies.remove_at(i)


# ── 스폰 타이머 (mino1 _updateSpawn) ───────────────────────
func _update_spawn(dt: float) -> void:
	spawn_timer -= dt
	if spawn_timer <= 0.0 and enemies.size() < MAX_ENEMIES:
		spawn_timer = SPAWN_INTERVAL
		_spawn_enemy()


# ── 적 한 마리 스폰 (mino1 _spawnEnemy) ────────────────────
func _spawn_enemy() -> void:
	var p: Dictionary = GameState.player
	var region_idx: int = clampi(GameState.region, 0, GameData.REGION_DEFS.size() - 1)
	var region_def: Dictionary = GameData.REGION_DEFS[region_idx]
	# 결정론 RNG 가 아니라 일반 RNG 사용(런타임 스폰; core 공식과 분리)
	var grng := GameData.make_rng(rng.randi())
	var type_key: String = GameData.pick_enemy_type(grng, int(p.get("lvl", 1)), region_def.get("enemies"))
	var def: Dictionary = GameData.ENEMY_DEFS[type_key]

	# 플레이어 주변 화면 밖 (mino1: 280~460px)
	var ang := rng.randf() * TAU
	var dist := 280.0 + rng.randf() * 180.0
	var ex := clampf(p["x"] + cos(ang) * dist, 40.0, GameData.WORLD_W - 40.0)
	var ey := clampf(p["y"] + sin(ang) * dist, 40.0, GameData.WORLD_H - 40.0)

	# 챕터·레벨·난이도 배율 (mino1 그대로). region 인덱스를 챕터로 사용(1부터).
	var chapter: int = region_idx + 1
	var chapter_mult: float = pow(1.25, chapter - 1)
	var lvl_mult: float = 1.0 + maxf(0.0, float(p.get("lvl", 1)) - 1.0) * 0.04
	var diff: Dictionary = GameData.DIFFICULTY_DEFS[clampi(GameState.difficulty, 0, GameData.DIFFICULTY_DEFS.size() - 1)]
	var scaled_hp: float = round(float(def["hp"]) * chapter_mult * float(diff["hp_mult"]))
	var scaled_dmg: float = round(float(def["dmg"]) * chapter_mult * lvl_mult * float(diff["dmg_mult"]))
	var scaled_xp: int = int(round(float(def["xp"]) * chapter_mult))
	var scaled_sp: float = round(float(def["sp"]) * pow(1.05, chapter - 1))

	# 엘리트 판정 (지역 elite_rate — 지형이 깔려 있으면 거기서 읽음)
	var elite_rate: float = terrain.region_elite_rate if terrain else float(region_def.get("elite_rate", 0.08))
	var is_elite: bool = rng.randf() < elite_rate

	var stats := {
		"hp": scaled_hp * 2.5 if is_elite else scaled_hp,
		"maxhp": scaled_hp * 2.5 if is_elite else scaled_hp,
		"sp": scaled_sp,
		"dmg": scaled_dmg * 1.5 if is_elite else scaled_dmg,
		"xp": scaled_xp * 2 if is_elite else scaled_xp,
		"gold_base": int(GameData.GOLD_DROP.get(type_key, 3)),
		"is_elite": is_elite,
	}

	var enemy = ENEMY_SCENE.instantiate()
	enemy.global_position = Vector2(ex, ey)
	enemy.setup(type_key, stats, player, self)
	add_child(enemy)
	enemies.append(enemy)


# ── 전투: 공격 입력 → 명중 판정 (mino1 _updateCombat) ──────
func _update_combat(dt: float) -> void:
	if player == null:
		return
	var p: Dictionary = GameState.player

	# 히트스톱 중엔 공격 판정 스킵 (mino1)
	if hitstop_t > 0.0:
		return

	var want := atk_btn_pressed or Input.is_key_pressed(KEY_SPACE)
	if not want or not player.can_attack():
		return

	# 공격 실행 (쿨다운·스윙·룽지·슬래시)
	player.start_attack()
	Audio.attack()   # 검 휘두름 소리 (mino1 MinoSound.attack)

	var atk_range := float(p.get("atkRange", 64))
	var atk_pow := float(p.get("atkPow", 11))
	var face: int = player.face
	var hit_count := 0

	for e in enemies:
		if not is_instance_valid(e) or e.dead or e.hp <= 0.0:
			continue
		var ddx: float = e.global_position.x - player.global_position.x
		var ddy: float = e.global_position.y - player.global_position.y
		var d := sqrt(ddx * ddx + ddy * ddy)
		# 범위 안 + 바라보는 방향 앞쪽 (mino1: ddx*face >= -16)
		if d < atk_range and ddx * face >= -16.0:
			var skills: Dictionary = p.get("skills", {})
			# 치명타 (critical 스킬 — 전직 보너스는 S3)
			var crit_chance := 0.15 * float(skills.get("critical", 0))
			# 전직 보너스 (도적 +30%, 닌자 +15%) (mino1)
			if p.get("job", null) == "rogue":
				crit_chance += 0.30
			if p.get("job2", null) == "ninja":
				crit_chance += 0.15
			var is_crit := crit_chance > 0.0 and rng.randf() < crit_chance
			var dmg := atk_pow
			# 크리스탈 버프: 공격력 +30% (mino1 _buffActive)
			if terrain and terrain.buff_active:
				dmg *= 1.3
			if is_crit:
				dmg *= 2.0
			dmg = round(dmg)

			e.take_hit(dmg, is_crit, player.global_position)
			fx.add_impact_hit(e.global_position, is_crit)
			spawn_float_text(e.global_position, str(int(dmg)), is_crit)
			if is_crit:
				Audio.crit()   # 치명타 소리 (mino1)
			else:
				Audio.hit()    # 타격 소리 (mino1)
			hit_count += 1

			# 생명 흡수 스킬 (mino1: 명중당 +1.5 × 스택)
			var drain := int(skills.get("life_drain", 0))
			if drain > 0:
				p["hp"] = minf(float(p.get("maxhp", 0)), float(p.get("hp", 0)) + 1.5 * drain)
			# 시너지: 치명타 + 공격가속 → 다음 공격 쿨다운 30% 감소 (mino1)
			if is_crit and int(skills.get("quick_strike", 0)) > 0:
				p["atkCD"] = maxf(0.0, float(p.get("atkCD", 0)) * 0.7)

	# ── 보스 피격 판정 (mino1 _updateCombat 의 보스 처리) ──
	if boss != null and is_instance_valid(boss) and not boss.dead:
		var bdx: float = boss.global_position.x - player.global_position.x
		var bdy: float = boss.global_position.y - player.global_position.y
		var bdist := sqrt(bdx * bdx + bdy * bdy)
		# 보스는 덩치가 커서 사거리 +80 (mino1)
		if bdist < atk_range + 80.0 and bdx * face >= -30.0:
			var bskills: Dictionary = p.get("skills", {})
			var bcrit := 0.15 * float(bskills.get("critical", 0))
			if p.get("job", null) == "rogue":
				bcrit += 0.30
			if p.get("job2", null) == "ninja":
				bcrit += 0.15
			var bis_crit := bcrit > 0.0 and rng.randf() < bcrit
			var bdmg := atk_pow
			if terrain and terrain.buff_active:
				bdmg *= 1.3
			if bis_crit:
				bdmg *= 2.0
			# 기절/빈틈 = 약점 추가타 (보스가 vulnerable 일 때)
			var vuln: float = boss.vuln_mult if boss.vulnerable else 1.0
			if vuln > 1.0:
				bdmg *= vuln
			bdmg = round(bdmg)
			boss.take_hit(bdmg)
			if bis_crit or vuln > 1.0:
				Audio.crit()
			else:
				Audio.hit()
			fx.add_impact_hit(boss.global_position + Vector2(0, -30), bis_crit or vuln > 1.0)
			spawn_float_text(boss.global_position + Vector2(0, -50), str(int(bdmg)), bis_crit or vuln > 1.0)
			if vuln > 1.0:
				spawn_float_text(boss.global_position + Vector2(0, -86), "약점!", true)
				fx.add_particles(boss.global_position + Vector2(0, -20), Color8(0xff, 0xf0, 0x4a), 8)
			# 생명 흡수도 보스에 적용
			var bdrain := int(bskills.get("life_drain", 0))
			if bdrain > 0:
				p["hp"] = minf(float(p.get("maxhp", 0)), float(p.get("hp", 0)) + 1.5 * bdrain)
			hit_count += 1

	# 히트스톱 (명중 시 0.04초) (mino1)
	if hit_count > 0:
		hitstop_t = 0.04
		# 손맛: 명중 순간 미세 카메라 흔들림
		add_shake(0.10, 3.5)


# ── HP/MP 자동 회복 (mino1 _updateRegen) ───────────────────
var _regen_timer := 0.0
func _update_regen(dt: float) -> void:
	var p: Dictionary = GameState.player
	_regen_timer += dt
	if _regen_timer >= 1.0:
		_regen_timer -= 1.0
		var diff: Dictionary = GameData.DIFFICULTY_DEFS[clampi(GameState.difficulty, 0, GameData.DIFFICULTY_DEFS.size() - 1)]
		var regen := float(diff.get("regen", 2))
		if regen > 0.0 and float(p["hp"]) < float(p["maxhp"]):
			p["hp"] = minf(float(p["maxhp"]), float(p["hp"]) + regen)
		if float(p["mp"]) < float(p["maxmp"]):
			p["mp"] = minf(float(p["maxmp"]), float(p["mp"]) + 2.0)


# ── 카메라 흔들림 ──────────────────────────────────────────
func add_shake(dur: float, amp: float) -> void:
	shake_t = maxf(shake_t, dur)
	shake_amp = maxf(shake_amp, amp)


func _update_shake(delta: float) -> void:
	if camera == null:
		return
	if shake_t > 0.0:
		shake_t -= delta
		var k := maxf(0.0, shake_t)
		var a := shake_amp * (k / 0.2 if k < 0.2 else 1.0)
		camera.offset = Vector2(rng.randf_range(-a, a), rng.randf_range(-a, a))
		if shake_t <= 0.0:
			shake_t = 0.0
			shake_amp = 0.0
			camera.offset = Vector2.ZERO
	else:
		camera.offset = Vector2.ZERO


# ════════════════════════════════════════════════════════════
#  적/플레이어가 호출하는 콜백 (FX·보상·예고)
# ════════════════════════════════════════════════════════════

func get_kfont() -> Font:
	return kfont


# ── 전직 조건 확인 (LevelupPanel 이 레벨업 카드보다 먼저 호출) ──
# 떠야 하면 JobPanel 을 띄우고 true 반환 (mino1 _checkJobUnlocks)
func check_job_unlock() -> bool:
	if job_panel:
		return job_panel.check_unlock()
	return false


# ── 스킬 피드백 텍스트 (mino1 _showSkillFeedback) — 우하단 잠깐 ──
func show_skill_feedback(msg: String, color: Color) -> void:
	var lbl := Label.new()
	if kfont:
		lbl.add_theme_font_override("font", kfont)
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.text = msg
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var vp := get_viewport().get_visible_rect().size
	lbl.size = Vector2(180, 28)
	lbl.position = Vector2(vp.x - 280.0, vp.y - 240.0)
	if info_label:
		info_label.get_parent().add_child(lbl)
	else:
		add_child(lbl)
	var tw := create_tween()
	tw.tween_property(lbl, "position:y", lbl.position.y - 30.0, 0.7)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.7)
	tw.tween_callback(func(): if is_instance_valid(lbl): lbl.queue_free())


# ── 화면 가운데 큰 메시지 (전직 완료 등) (mino1 _applyJob msgTxt) ──
func show_center_message(msg: String) -> void:
	var lbl := Label.new()
	if kfont:
		lbl.add_theme_font_override("font", kfont)
	lbl.add_theme_font_size_override("font_size", 34)
	lbl.add_theme_color_override("font_color", Color8(0xff, 0xdd, 0x44))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.text = msg
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var vp := get_viewport().get_visible_rect().size
	lbl.size = Vector2(vp.x, 60)
	lbl.position = Vector2(0, vp.y / 2.0 - 30.0)
	lbl.modulate.a = 0.0
	lbl.z_index = 100
	# 일시정지에도 보이게 ALWAYS 레이어에 얹는다 (전직 패널이 일시정지 중일 수 있음)
	var layer := CanvasLayer.new()
	layer.layer = 12
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	layer.add_child(lbl)
	var tw := get_tree().create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(lbl, "modulate:a", 1.0, 0.4)
	tw.parallel().tween_property(lbl, "position:y", lbl.position.y - 20.0, 0.4)
	tw.tween_interval(1.2)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.6)
	tw.parallel().tween_property(lbl, "position:y", lbl.position.y - 60.0, 0.6)
	tw.tween_callback(func(): if is_instance_valid(layer): layer.queue_free())


# ── 줍기 토스트 (무기 지급 등) (mino1 _showPickupToast) — 하단 안내 ──
func show_pickup_toast(msg: String) -> void:
	if info_label:
		info_label.text = msg


# ── 고기 상함/요리 알림 (mino1 _showMeatAlert) — CookHUD 가 잠깐 표시 ──
func show_meat_alert(msg: String) -> void:
	if cook_hud:
		cook_hud.show_alert(msg)


# ── 회복 텍스트 (고기 먹기 등) — 월드 라벨 띄우기 (mino1 _floatTexts heal) ──
func spawn_heal_text(world_pos: Vector2, value: String, color: Color) -> void:
	var lbl := Label.new()
	if kfont:
		lbl.add_theme_font_override("font", kfont)
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color8(0x1a, 0x1a, 0x1a))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.text = value
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = world_pos
	fx_text_layer.add_child(lbl)
	float_texts.append({"label": lbl, "vel": -55.0, "life": 0.8, "t": 0.0, "wobble": 0.0, "base_x": lbl.position.x})


# ── 고기 먹기 짧은 버프 신호 (mino1 _buffActive 4초) — 효과는 S5/S6 ──
func apply_food_buff(dur: float) -> void:
	food_buff_t = maxf(food_buff_t, dur)


# 소환 슬라임용 텍스처 (slime 스프라이트 재사용)
func _load_ally_tex() -> Texture2D:
	var path := "res://assets/sprites/slime.png"
	if ResourceLoader.exists(path):
		return load(path)
	return null


# 데미지 숫자 띄우기 (mino1 _spawnFloatText)
func spawn_float_text(world_pos: Vector2, value: String, is_crit: bool) -> void:
	var cap := 14
	if float_texts.size() >= cap:
		var oldest = float_texts.pop_front()
		if oldest and is_instance_valid(oldest.label):
			oldest.label.queue_free()

	var lbl := Label.new()
	if kfont:
		lbl.add_theme_font_override("font", kfont)
	lbl.add_theme_font_size_override("font_size", 34 if is_crit else 22)
	lbl.add_theme_color_override("font_color", Color8(0xff, 0xee, 0x00) if is_crit else Color.WHITE)
	lbl.add_theme_color_override("font_outline_color", Color8(0x1a, 0x1a, 0x1a))
	lbl.add_theme_constant_override("outline_size", 6 if is_crit else 4)
	lbl.text = value
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var off_x := (rng.randf() - 0.5) * 24.0
	lbl.position = Vector2(world_pos.x + off_x - 30.0, world_pos.y - 20.0)
	fx_text_layer.add_child(lbl)

	float_texts.append({
		"label": lbl,
		"vel": -130.0 if is_crit else -90.0,
		"life": 1.0 if is_crit else 0.75,
		"t": 0.0,
		"wobble": 5.0 if is_crit else 0.0,
		"base_x": lbl.position.x,
	})


# 데미지 숫자 갱신 (mino1 _updateFloatTexts: 중력+치명타 흔들림)
func _update_float_texts(dt: float) -> void:
	for i in range(float_texts.size() - 1, -1, -1):
		var f: Dictionary = float_texts[i]
		var lbl = f.label
		if not is_instance_valid(lbl):
			float_texts.remove_at(i)
			continue
		f.t += dt
		lbl.position.y += f.vel * dt
		f.vel += 220.0 * dt
		if f.wobble > 0.0:
			lbl.position.x = f.base_x + sin(f.t * 28.0) * f.wobble * maxf(0.0, 1.0 - f.t / f.life)
		var alpha := maxf(0.0, 1.0 - f.t / f.life)
		lbl.modulate.a = alpha
		if f.t >= f.life:
			lbl.queue_free()
			float_texts.remove_at(i)


# 임팩트 원 (적 사망 시 등) (mino1 _spawnImpact / death flash)
func spawn_impact(pos: Vector2, r: float, color: Color) -> void:
	if fx:
		fx.add_impact(pos, r, color)


# 예고선 (boar 돌진) — 적 AI 가 매 프레임 호출
func draw_telegraph_dash(origin: Vector2, dir: Vector2, prog: float) -> void:
	if fx:
		fx.telegraphs.append({"kind": "dash", "pos": origin, "dir": dir, "prog": prog})


# 예고 원 (croc 매복) — 적 AI 가 매 프레임 호출
func draw_telegraph_circle(center: Vector2, radius: float, alpha: float) -> void:
	if fx:
		fx.telegraphs.append({"kind": "circle", "pos": center, "r": radius, "alpha": alpha})


# ── 적 사망 보상 (mino1 _updateEnemies 의 deadList 처리) ─────
func on_enemy_died(enemy: Node, pos: Vector2) -> void:
	var is_elite: bool = enemy.is_elite
	# 처치 파티클
	var part_color := Color8(0xff, 0xdd, 0x22) if is_elite else Color8(0xff, 0xcf, 0x5c)
	fx.add_particles(pos, part_color, 35 if is_elite else 22)
	fx.add_particles(pos, Color8(0xff, 0x88, 0x44), 16 if is_elite else 10)

	Audio.kill()   # 처치 소리 (mino1 MinoSound.kill)
	GameState.player["kills"] = int(GameState.player.get("kills", 0)) + 1
	_gain_xp(enemy.xp)

	# 골드 드랍 (적 기본 + 엘리트 보너스)
	var base_gold: int = enemy.gold_base + int(floor(rng.randf() * 3.0))
	var gold_amt: int = int(round(base_gold * 3.5)) if is_elite else base_gold
	GameState.player["gold"] = int(GameState.player.get("gold", 0)) + gold_amt
	# 골드 텍스트 (노랑)
	_spawn_gold_text(pos, gold_amt, is_elite)

	# ── 장비 드랍 시도 (mino1 tryDrop) — 엘리트는 추가 1회(70% 고정) ──
	if loot:
		var drng := GameData.make_rng(rng.randi())
		var dropped = GameData.try_drop(drng, pos.x, pos.y, false)
		if dropped:
			loot.add_ground_item(dropped)
		if is_elite and rng.randf() < 0.70:
			var dropped2 = GameData.try_drop(drng, pos.x + 24.0, pos.y + 12.0, false)
			if dropped2:
				loot.add_ground_item(dropped2)

		# ── 날고기 드랍 시도 (~35%, 엘리트 ~60%) (mino1 meatChance) ──
		var meat_chance := 0.60 if is_elite else 0.35
		if rng.randf() < meat_chance:
			loot.add_raw_meat(pos.x, pos.y)


func _spawn_gold_text(pos: Vector2, amt: int, is_elite: bool) -> void:
	var lbl := Label.new()
	if kfont:
		lbl.add_theme_font_override("font", kfont)
	lbl.add_theme_font_size_override("font_size", 18 if is_elite else 13)
	lbl.add_theme_color_override("font_color", Color8(0xff, 0xdd, 0x22))
	lbl.add_theme_color_override("font_outline_color", Color8(0x4a, 0x30, 0x00))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.text = "+%dG" % amt
	lbl.position = Vector2(pos.x - 20.0 + (rng.randf() - 0.5) * 20.0, pos.y - 28.0)
	fx_text_layer.add_child(lbl)
	float_texts.append({"label": lbl, "vel": -60.0, "life": 0.8, "t": 0.0, "wobble": 0.0, "base_x": lbl.position.x})


# ── 경험치/레벨업 (mino1 _gainXP) — S2: 레벨업 시 3택 스킬 선택창 ──
func _gain_xp(amount: int) -> void:
	var p: Dictionary = GameState.player
	p["xp"] = int(p.get("xp", 0)) + maxi(1, int(round(amount * float(p.get("xpGainMult", 1.0)))))
	var leveled := 0
	while int(p.get("xpNext", 20)) > 0 and int(p["xp"]) >= int(p["xpNext"]):
		p["xp"] = int(p["xp"]) - int(p["xpNext"])
		p["lvl"] = int(p["lvl"]) + 1
		p["xpNext"] = int(round(int(p["xpNext"]) * 1.5))
		p["maxhp"] = float(p["maxhp"]) + 10.0
		p["atkPow"] = float(p["atkPow"]) + 2.0
		p["hp"] = p["maxhp"]      # 레벨업 시 전체 회복
		p["mp"] = p["maxmp"]
		p["statPoints"] = int(p.get("statPoints", 0)) + 3
		leveled += 1
	if leveled > 0:
		GameState.save_game()
		# 레벨업 손맛: 노란 파티클 + 흔들림
		fx.add_particles(player.global_position, Color8(0xff, 0xcf, 0x5c), 24)
		spawn_impact(player.global_position, 70.0, Color8(0xff, 0xcf, 0x5c))
		add_shake(0.15, 4.0)
		Audio.levelup()   # 레벨업 아르페지오 (mino1 MinoSound.levelup)
		# ★ 한 번에 여러 레벨이 올라도 스킬 선택창은 '하나씩' 큐로 (mino1 _pendingLvlups)
		if lvlup_panel:
			lvlup_panel.queue_levelup(leveled)


# ── 스킬 적용 (mino1 _applySkill) — LevelupPanel 이 카드 선택 시 호출 ──
func apply_skill(id: String) -> void:
	var p: Dictionary = GameState.player
	var skills: Dictionary = p.get("skills", {})
	skills[id] = int(skills.get(id, 0)) + 1
	p["skills"] = skills

	match id:
		"sword_mastery":
			p["atkPow"] = float(p.get("atkPow", 0)) + 5.0
		"quick_strike":
			p["atkSpeed"] = maxf(0.12, float(p.get("atkSpeed", 0.5)) * 0.8)
		"iron_wall":
			p["armor"] = float(p.get("armor", 0)) + 3.0
		"swift_wind":
			p["sp"] = minf(320.0, float(p.get("sp", 0)) + 22.0)
		"wide_slash":
			p["atkRange"] = float(p.get("atkRange", 64)) + 14.0
		"vitality":
			p["maxhp"] = float(p.get("maxhp", 0)) + 20.0
			p["hp"] = minf(float(p["maxhp"]), float(p.get("hp", 0)) + 20.0)
		# critical·life_drain 은 패시브 — 전투 판정에서 매번 읽는다(여기선 스택만 증가)
	GameState.save_game()


# ── 플레이어 피격 콜백 (mino1: hurt 사운드·흔들림·게임오버) ──
func on_player_hurt(real: float) -> void:
	add_shake(0.18, 6.0)
	Audio.hurt()   # 주인공 피격 소리 (mino1 MinoSound.hurt)
	var p: Dictionary = GameState.player
	if float(p["hp"]) <= 0.0:
		_on_game_over()


# ── 게임오버 (S1: 같은 자리에서 부활 — 완전한 게임오버 화면은 S5/S6) ──
func _on_game_over() -> void:
	# 적 전부 제거 + 풀 회복 + 짧은 무적 (임시 처리)
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()
	var p: Dictionary = GameState.player
	p["hp"] = p["maxhp"]
	p["inv"] = 2.0
	add_shake(0.4, 12.0)
	if info_label:
		info_label.text = "쓰러졌다! 잠시 무적 — 다시 싸우자"


# ════════════════════════════════════════════════════════════
#  S5: 지역·보스·난이도
# ════════════════════════════════════════════════════════════

# ── 고정 수치 피해 (보스 궁극기·독장판) — 난이도 배율 + 비율 방어 (mino1 _hazardDmg/_damagePlayer) ──
# 잡몹 피해는 스폰 때 이미 난이도가 반영돼 _incomingDmg(player.hurt)만 쓰지만,
# 보스·메테오·독장판은 "고정 raw" 라 여기서 dmgMult 를 곱하고 비율 방어를 적용한다.
func hazard_damage(raw: float, inv_dur: float, part_color: Color, prefix: String) -> void:
	var p: Dictionary = GameState.player
	if player and player.is_invincible():
		return
	var diff: Dictionary = GameData.DIFFICULTY_DEFS[clampi(GameState.difficulty, 0, GameData.DIFFICULTY_DEFS.size() - 1)]
	var dmg_mult := float(diff.get("dmg_mult", 1.0))
	var armor := float(p.get("armor", 0.0))
	var real := maxf(1.0, round(raw * dmg_mult * 70.0 / (70.0 + armor)))
	p["hp"] = maxf(0.0, float(p["hp"]) - real)
	if inv_dur > 0.0:
		p["inv"] = maxf(float(p.get("inv", 0.0)), inv_dur)
	# 피해 숫자 (독은 ☠ 접두)
	var label := ("%s %d" % [prefix, int(real)]) if prefix != "" else str(int(real))
	if prefix != "":
		spawn_heal_text(player.global_position, label, part_color)
	else:
		spawn_float_text(player.global_position, label, false)
	if part_color != Color.WHITE:
		fx.add_particles(player.global_position, part_color, 5)
	add_shake(0.16, 5.5)
	Audio.hurt()   # 보스 궁극기·독장판 피해 소리 (mino1)
	if float(p["hp"]) <= 0.0:
		_on_game_over()


# ── 이동 배율 (지역 진흙 + 크리스탈 버프) (mino1 spMult) — Player 가 읽음 ──
func player_move_mult() -> float:
	var mult := 1.0
	if terrain:
		mult *= terrain.region_move_mult
		if terrain.buff_active:
			mult *= 1.25
	return mult


# ── 보스 등장 (mino1 _spawnBoss) — 현재 지역이 지정한 보스 1종 ──
func _spawn_boss() -> void:
	if boss != null and is_instance_valid(boss):
		return
	var region_idx: int = clampi(GameState.region, 0, GameData.REGION_DEFS.size() - 1)
	var region_def: Dictionary = GameData.REGION_DEFS[region_idx]
	var boss_type: String = region_def.get("boss", "elephant")
	var chapter: int = GameState.chapter
	var p: Dictionary = GameState.player
	boss = BOSS_SCENE.instantiate()
	boss.global_position = Vector2(p["x"], p["y"] - 200.0)
	boss.setup(boss_type, chapter, player, self)
	add_child(boss)


# ── 보스 처치 보상 (Boss._die 가 호출) — 전설급 드랍 + 골드 + 챕터 클리어 ──
func on_boss_died(pos: Vector2) -> void:
	var p: Dictionary = GameState.player
	Audio.win()   # 승리 팡파레 (mino1 MinoSound.win)
	# 전설급 보장 드랍 (mino1 tryDrop is_boss=true → rarity>=2)
	if loot:
		var drng := GameData.make_rng(rng.randi())
		var dropped = GameData.try_drop(drng, pos.x, pos.y, true)
		if dropped:
			loot.add_ground_item(dropped)
	# 보스 골드 (mino1: 80 + 0~39)
	var boss_gold: int = 80 + int(floor(rng.randf() * 40.0))
	p["gold"] = int(p.get("gold", 0)) + boss_gold
	_spawn_gold_text(pos + Vector2(0, -60), boss_gold, true)
	# 남은 잡몹도 정리 (평온한 전환)
	for e in enemies:
		if is_instance_valid(e):
			fx.add_particles(e.global_position, Color8(0x9f, 0xe3, 0xa8), 8)
			e.queue_free()
	enemies.clear()
	boss = null
	GameState.save_game()
	# 챕터 클리어 → (탭) → 다음 지역 해금 + 세계 지도
	_show_chapter_clear()


# ── 난이도 선택 직후 (DifficultyPanel 이 호출) — 세계 지도로 ──
func on_difficulty_picked() -> void:
	# 첫 진입이면 지역 0 으로 바로 들어가게 세계 지도를 띄운다
	if worldmap_panel:
		worldmap_panel.open()


# ── 세계 지도에서 선택한 지역 입장 (mino1 _enterRegion) ──────
func enter_region(idx: int) -> void:
	var region: int = clampi(idx, 0, GameData.REGION_DEFS.size() - 1)
	GameState.region = region
	GameState.chapter = region + 1   # 난이도 스케일 재사용
	var def: Dictionary = GameData.REGION_DEFS[region]
	# 배경색 전환
	_retint_ground(def.get("ground_tint", Color.WHITE))
	# 지형 재생성 (지역별 바위·독·버프·이동배율·엘리트율)
	if terrain:
		terrain.init_zones()
	# 적·보스 리셋
	boss_spawned = false
	if boss != null and is_instance_valid(boss):
		boss.queue_free()
	boss = null
	GameState.player["kills"] = 0
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()
	# 플레이어를 지역 중앙으로
	var cx := GameData.WORLD_W / 2.0
	var cy := GameData.WORLD_H / 2.0
	player.global_position = Vector2(cx, cy)
	GameState.player["x"] = cx
	GameState.player["y"] = cy
	spawn_timer = 0.0
	GameState.save_game()
	# 1장(들판)은 지역 이름 배너, 2장 이상 새 지역은 짧은 챕터 스토리(입장 톤).
	# 챕터 스토리 문구는 '도착했다·앞으로 나아간다' 톤이라 안 잡은 보스를 잡았다고
	# 말하지 않는다(서사 역전 방지). 보스 처치 회고는 챕터 클리어 패널이 맡는다.
	if region >= 1:
		_show_chapter_story(region + 1)
	else:
		_show_region_enter_banner(def)


# ── 풀밭 색조 재적용 (지역 전환) ────────────────────────────
func _retint_ground(tint: Color) -> void:
	var ground := get_node_or_null("Ground")
	if ground:
		ground.modulate = tint


# ── 챕터 클리어 배너 (mino1 _showChapterClearPanel) — 탭 → 세계 지도 ──
func _show_chapter_clear() -> void:
	# 다음 지역 해금
	var next := mini(GameState.region + 1, GameData.REGION_DEFS.size() - 1)
	GameState.max_region = maxi(GameState.max_region, next)
	GameState.save_game()
	var p: Dictionary = GameState.player
	_clear_banner()
	_chapter_clear_layer = CanvasLayer.new()
	_chapter_clear_layer.layer = 14
	_chapter_clear_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_chapter_clear_layer)
	get_tree().paused = true
	var lines := [
		["제%d장 클리어!" % GameState.chapter, 28, Color8(0xff, 0xcf, 0x5c), 0.30],
		["보스를 쓰러뜨렸다.", 16, Color8(0xcb, 0xe0, 0xcb), 0.40],
		["Lv %d · 총 처치 %d" % [int(p.get("lvl", 1)), int(p.get("kills", 0))], 18, Color8(0x9f, 0xe3, 0xa8), 0.46],
		["다음 지역이 열렸다!", 15, Color8(0xff, 0x99, 0x66), 0.54],
		["(화면을 탭하면 세계 지도로)", 14, Color8(0x88, 0x99, 0x88), 0.66],
	]
	_build_banner_labels(lines, true)
	_banner_tap_action = "to_worldmap"


# ── 지역 입장 배너 (mino1 _showRegionEnterBanner) — 탭 → 닫고 시작 ──
func _show_region_enter_banner(def: Dictionary) -> void:
	_clear_banner()
	_chapter_clear_layer = CanvasLayer.new()
	_chapter_clear_layer.layer = 14
	_chapter_clear_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_chapter_clear_layer)
	get_tree().paused = true
	var lines := [
		["%s %s" % [def.get("icon", ""), def.get("name", "")], 26, Color8(0xff, 0xe9, 0xa8), 0.42],
		[str(def.get("desc", "")), 14, Color8(0xcc, 0xcc, 0xcc), 0.50],
		["(화면을 탭하면 시작)", 14, Color8(0x88, 0x88, 0x88), 0.66],
	]
	_build_banner_labels(lines, false)
	_banner_tap_action = "close"


func _build_banner_labels(lines: Array, dim: bool) -> void:
	var vp := get_viewport().get_visible_rect().size
	# 어두운 오버레이 (Node2D _draw)
	var ov := Node2D.new()
	var alpha := 0.90 if dim else 0.70
	ov.set_script(_make_banner_overlay_script(alpha))
	_chapter_clear_layer.add_child(ov)
	for ld in lines:
		var lbl := Label.new()
		if kfont:
			lbl.add_theme_font_override("font", kfont)
		lbl.add_theme_font_size_override("font_size", int(ld[1]))
		lbl.add_theme_color_override("font_color", ld[2])
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		lbl.add_theme_constant_override("outline_size", 4)
		lbl.text = str(ld[0])
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.size = Vector2(vp.x * 0.84, 40)
		lbl.position = Vector2(vp.x * 0.08, vp.y * float(ld[3]))
		_chapter_clear_layer.add_child(lbl)
	# 탭 입력 처리 Control (전체 덮기)
	var tap := Control.new()
	tap.anchor_right = 1.0
	tap.anchor_bottom = 1.0
	tap.mouse_filter = Control.MOUSE_FILTER_STOP
	tap.gui_input.connect(_on_banner_tap)
	_chapter_clear_layer.add_child(tap)


func _on_banner_tap(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventScreenTouch and event.pressed) or \
		(event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed)
	if not pressed:
		return
	var action := _banner_tap_action
	_clear_banner()
	get_tree().paused = false
	if action == "to_worldmap":
		if worldmap_panel:
			worldmap_panel.open()
	# action == "close" → 그냥 닫고 전투 시작


func _clear_banner() -> void:
	if _chapter_clear_layer and is_instance_valid(_chapter_clear_layer):
		_chapter_clear_layer.queue_free()
	_chapter_clear_layer = null
	_banner_tap_action = ""


func _make_banner_overlay_script(alpha: float) -> GDScript:
	var src := """
extends Node2D
var ov_alpha = %f
func _draw():
	var vp = get_viewport().get_visible_rect().size
	draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0.0, 0.06, 0.04, ov_alpha), true)
""" % alpha
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


# ════════════════════════════════════════════════════════════
#  S6: 연출·사운드 마감
# ════════════════════════════════════════════════════════════

# ── 인트로/스토리 페이드 틱 (일시정지 중에도 도는 ALWAYS 노드) ──
# 인트로·챕터 스토리는 게임을 일시정지하므로 Main._process 가 안 돈다.
# 이 작은 노드를 PROCESS_MODE_ALWAYS 로 두고 매 프레임 Main 의 페이드 갱신을 호출.
func _build_overlay_ticker() -> void:
	var ticker := Node.new()
	ticker.name = "OverlayTicker"
	ticker.set_script(_make_overlay_ticker_script())
	ticker.set("main", self)
	ticker.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ticker)


func _make_overlay_ticker_script() -> GDScript:
	var src := """
extends Node
var main
func _process(d):
	if main == null:
		return
	main._update_intro(d)
	main._update_chapter_story(d)
"""
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


# ── 동료 카피바라 (mino1 _capybara) ─────────────────────────
func _build_companion() -> void:
	companion = Node2D.new()
	companion.name = "Companion"
	companion.set_script(COMPANION_SCRIPT)
	companion.set("main", self)
	add_child(companion)


# ── mino 시그니처 워터마크 (mino1 _addMinoSig) — 화면 우측 하단 ──
func _build_mino_sig() -> void:
	var layer := CanvasLayer.new()
	layer.name = "MinoSigLayer"
	layer.layer = 3   # HUD 아래(은은하게)
	add_child(layer)
	var lbl := Label.new()
	if kfont:
		lbl.add_theme_font_override("font", kfont)
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", Color8(0xe7, 0xc8, 0x78))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.text = "mino"
	lbl.modulate.a = 0.45
	lbl.rotation = -0.06
	# 우측 하단(공격 버튼 위쪽 빈 공간)
	lbl.anchor_left = 1.0
	lbl.anchor_right = 1.0
	lbl.anchor_top = 1.0
	lbl.anchor_bottom = 1.0
	lbl.offset_left = -110.0
	lbl.offset_top = -300.0
	lbl.offset_right = -16.0
	lbl.offset_bottom = -268.0
	layer.add_child(lbl)


# ── 소리 켜고/끄기 토글 버튼 (우상단, 처음부터 버튼 아래) ──────
func _build_sound_button() -> void:
	var layer := CanvasLayer.new()
	layer.name = "SoundBtnLayer"
	layer.layer = 4
	add_child(layer)
	var ctrl := Control.new()
	ctrl.name = "SoundBtn"
	ctrl.anchor_left = 1.0
	ctrl.anchor_right = 1.0
	ctrl.offset_left = -76.0
	ctrl.offset_top = 158.0    # 처음부터(↻, y=108~152) 버튼 아래
	ctrl.offset_right = -12.0
	ctrl.offset_bottom = 202.0
	ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(ctrl)
	var dn := Node2D.new()
	dn.set_script(_make_sound_draw_script())
	dn.set("ctrl", ctrl)
	ctrl.add_child(dn)
	ctrl.gui_input.connect(_on_sound_input)
	sound_btn_ctrl = ctrl


func _on_sound_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventScreenTouch and event.pressed) or \
		(event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed)
	if not pressed:
		return
	Audio.toggle()
	if not Audio.is_muted():
		Audio.ui_tap()
		Audio.start_bgm()


func _make_sound_draw_script() -> GDScript:
	var src := """
extends Node2D
var ctrl
func _process(_d):
	queue_redraw()
func _draw():
	if ctrl == null:
		return
	var r = Rect2(0, 0, ctrl.size.x, ctrl.size.y)
	draw_rect(r, Color(0.1, 0.14, 0.12, 0.7), true)
	draw_rect(r, Color(0.5, 0.7, 0.55, 0.85), false, 2.0)
	var c = ctrl.size / 2.0
	var muted = Audio.is_muted()
	# 스피커 모양 (작은 사각 + 삼각)
	var sp = Color(0.85, 1.0, 0.9, 0.9) if not muted else Color(0.7, 0.7, 0.7, 0.7)
	draw_rect(Rect2(c.x - 12, c.y - 5, 7, 10), sp, true)
	var tri = PackedVector2Array([Vector2(c.x - 5, c.y - 9), Vector2(c.x + 3, c.y - 14), Vector2(c.x + 3, c.y + 14), Vector2(c.x - 5, c.y + 9)])
	draw_colored_polygon(tri, sp)
	if muted:
		# X 표시 (음소거)
		draw_line(Vector2(c.x + 8, c.y - 8), Vector2(c.x + 18, c.y + 8), Color(1, 0.5, 0.5, 0.9), 2.5)
		draw_line(Vector2(c.x + 18, c.y - 8), Vector2(c.x + 8, c.y + 8), Color(1, 0.5, 0.5, 0.9), 2.5)
	else:
		# 음파 호 2개
		draw_arc(Vector2(c.x + 6, c.y), 8.0, -0.7, 0.7, 8, sp, 2.0)
		draw_arc(Vector2(c.x + 6, c.y), 13.0, -0.7, 0.7, 8, sp, 2.0)
"""
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


# ── 인트로 스토리 화면 (mino1 _showIntro) ────────────────────
var _intro_active := false
var _intro_t := 0.0
var _intro_lines: Array = []     # Label 들
var _intro_tap_label: Label = null
var _intro_sig: Label = null

func _show_intro() -> void:
	if _intro_active:
		return
	_intro_active = true
	_intro_t = 0.0
	_intro_lines = []
	get_tree().paused = true
	intro_layer = CanvasLayer.new()
	intro_layer.name = "IntroLayer"
	intro_layer.layer = 20
	intro_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(intro_layer)
	# 어두운 오버레이
	var ov := Node2D.new()
	ov.set_script(_make_banner_overlay_script(0.82))
	intro_layer.add_child(ov)
	var vp := get_viewport().get_visible_rect().size
	# mino 시그니처 (상단, 손글씨 사인 느낌)
	_intro_sig = _intro_label("mino", int(vp.x * 0.13), Color8(0xf0, 0xd8, 0x78), true)
	_intro_sig.position = Vector2(0, vp.y * 0.14 - 30.0)
	_intro_sig.rotation = -0.07
	_intro_sig.modulate.a = 0.0
	intro_layer.add_child(_intro_sig)
	var sig_tw := get_tree().create_tween()
	sig_tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	sig_tw.tween_interval(0.4)
	sig_tw.tween_property(_intro_sig, "modulate:a", 0.88, 0.9)
	# 스토리 4줄
	var lines := [
		"지구는 오염에 잠식됐다.",
		"동물들은 변이체가 되었고, 그 정점엔 오염의 군주가 있다.",
		"마지막 희망인 그대여 —",
		"군주를 쓰러뜨리고 지구를 정화하라.",
	]
	for i in lines.size():
		var sz := 19 if i == 3 else 16
		var col := Color8(0xe8, 0xc8, 0x7a) if i == 3 else Color8(0xcc, 0xcc, 0xcc)
		var lbl := _intro_label(lines[i], sz, col, i == 3)
		lbl.position = Vector2(0, vp.y / 2.0 - 70.0 + i * 44.0)
		lbl.modulate.a = 0.0
		intro_layer.add_child(lbl)
		_intro_lines.append(lbl)
	# "탭하여 시작"
	_intro_tap_label = _intro_label("탭하여 시작", 15, Color8(0x88, 0x88, 0x88), false)
	_intro_tap_label.position = Vector2(0, vp.y - 70.0)
	_intro_tap_label.modulate.a = 0.0
	intro_layer.add_child(_intro_tap_label)
	# 탭으로 스킵
	var tap := Control.new()
	tap.anchor_right = 1.0
	tap.anchor_bottom = 1.0
	tap.mouse_filter = Control.MOUSE_FILTER_STOP
	tap.gui_input.connect(_on_intro_tap)
	intro_layer.add_child(tap)


# 가운데 정렬 인트로 라벨 만들기
func _intro_label(txt: String, sz: int, col: Color, bold: bool) -> Label:
	var lbl := Label.new()
	if kfont:
		lbl.add_theme_font_override("font", kfont)
	lbl.add_theme_font_size_override("font_size", sz)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 4 if bold else 3)
	lbl.text = txt
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var vp := get_viewport().get_visible_rect().size
	lbl.size = Vector2(vp.x, 40)
	return lbl


func _on_intro_tap(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventScreenTouch and event.pressed) or \
		(event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed)
	if pressed:
		_end_intro()


func _update_intro(delta: float) -> void:
	if not _intro_active:
		return
	_intro_t += delta   # 일시정지 중이라 실시간 delta (ALWAYS 처리)
	var phase_dur := 1.0
	var fade_dur := 0.6
	for i in _intro_lines.size():
		var lbl: Label = _intro_lines[i]
		if not is_instance_valid(lbl):
			continue
		var elapsed := _intro_t - i * phase_dur
		lbl.modulate.a = 0.0 if elapsed <= 0.0 else minf(1.0, elapsed / fade_dur)
	var all_shown := _intro_t >= (_intro_lines.size() - 1) * phase_dur + fade_dur
	if all_shown and _intro_tap_label and is_instance_valid(_intro_tap_label):
		_intro_tap_label.modulate.a = 0.55 + 0.45 * absf(sin(_intro_t * 2.2))
	if _intro_t >= 5.5:
		_end_intro()


func _end_intro() -> void:
	if not _intro_active:
		return
	_intro_active = false
	GameState.seen_intro = true
	get_tree().paused = false
	if intro_layer and is_instance_valid(intro_layer):
		# 페이드아웃 후 제거
		var tw := create_tween()
		var lyr := intro_layer
		for c in lyr.get_children():
			if c is CanvasItem:
				tw.parallel().tween_property(c, "modulate:a", 0.0, 0.4)
		tw.tween_callback(func(): if is_instance_valid(lyr): lyr.queue_free())
	intro_layer = null
	_intro_lines = []
	_intro_tap_label = null
	_intro_sig = null
	# 인트로 다음 = 난이도 미선택이면 난이도 선택창
	if GameState.difficulty < 0 and diff_panel:
		diff_panel.open()


# ── 챕터 스토리 (mino1 _showChapterStory) — 지역 입장/전환 시 짧게 ──
var _story_active := false
var _story_t := 0.0
var _story_lines: Array = []
var _story_tap_label: Label = null

func _show_chapter_story(chapter: int) -> void:
	if _story_active:
		return
	_story_active = true
	_story_t = 0.0
	_story_lines = []
	get_tree().paused = true
	story_layer = CanvasLayer.new()
	story_layer.name = "StoryLayer"
	story_layer.layer = 20
	story_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(story_layer)
	var ov := Node2D.new()
	ov.set_script(_make_banner_overlay_script(0.88))
	story_layer.add_child(ov)
	var vp := get_viewport().get_visible_rect().size
	# 지역 *입장* 시점의 짧은 스토리 — '도착했다'는 전제로 *앞으로* 나아가는 톤.
	# (보스를 잡았다는 회고 톤은 입장에선 쓰지 않는다 — 아직 안 잡았으니 서사 역전.
	#  '쓰러뜨렸다' 류는 보스 처치 후 챕터 클리어 패널이 따로 말한다.)
	# chapter = region+1 로 들어오므로 region 인덱스로 환산해 지역별 문구를 고른다.
	var region_idx := clampi(chapter - 1, 0, GameData.REGION_DEFS.size() - 1)
	var rdef: Dictionary = GameData.REGION_DEFS[region_idx]
	var region_name: String = rdef.get("name", "")
	var line1 := ""
	var line2 := ""
	match region_idx:
		1:
			line1 = "오염이 더 짙은 곳, %s 에 들어선다." % region_name
			line2 = "변이체들의 기운이 무겁다 — 정신을 바짝."
		2:
			line1 = "무너진 %s. 군주의 그림자가 어른거린다." % region_name
			line2 = "여기를 지나야 끝에 닿는다."
		3:
			line1 = "마지막 땅, %s 의 문이 열렸다." % region_name
			line2 = "오염의 군주가 저 안에서 기다린다."
		_:
			line1 = "%s 에 발을 들인다." % region_name
			line2 = "정화의 여정은 계속된다."
	var data := [
		["— 제%d장 —" % chapter, 22, Color8(0xff, 0xcf, 0x5c), -80.0, true],
		[line1, 16, Color8(0xcc, 0xcc, 0xcc), -30.0, false],
		[line2, 15, Color8(0xaa, 0xaa, 0xaa), 10.0, false],
	]
	for d in data:
		var lbl := _intro_label(str(d[0]), int(d[1]), d[2], bool(d[4]))
		lbl.position = Vector2(0, vp.y / 2.0 + float(d[3]))
		lbl.modulate.a = 0.0
		story_layer.add_child(lbl)
		_story_lines.append(lbl)
	_story_tap_label = _intro_label("탭하여 시작", 14, Color8(0x88, 0x88, 0x88), false)
	_story_tap_label.position = Vector2(0, vp.y - 70.0)
	_story_tap_label.modulate.a = 0.0
	story_layer.add_child(_story_tap_label)
	var tap := Control.new()
	tap.anchor_right = 1.0
	tap.anchor_bottom = 1.0
	tap.mouse_filter = Control.MOUSE_FILTER_STOP
	tap.gui_input.connect(_on_story_tap)
	story_layer.add_child(tap)


func _on_story_tap(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventScreenTouch and event.pressed) or \
		(event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed)
	if pressed:
		_end_chapter_story()


func _update_chapter_story(delta: float) -> void:
	if not _story_active:
		return
	_story_t += delta
	var phase_dur := 0.9
	var fade_dur := 0.55
	for i in _story_lines.size():
		var lbl: Label = _story_lines[i]
		if not is_instance_valid(lbl):
			continue
		var elapsed := _story_t - i * phase_dur
		lbl.modulate.a = 0.0 if elapsed <= 0.0 else minf(1.0, elapsed / fade_dur)
	var all_shown := _story_t >= (_story_lines.size() - 1) * phase_dur + fade_dur
	if all_shown and _story_tap_label and is_instance_valid(_story_tap_label):
		_story_tap_label.modulate.a = 0.55 + 0.45 * absf(sin(_story_t * 2.2))
	if _story_t >= 4.5:
		_end_chapter_story()


func _end_chapter_story() -> void:
	if not _story_active:
		return
	_story_active = false
	get_tree().paused = false
	if story_layer and is_instance_valid(story_layer):
		var tw := create_tween()
		var lyr := story_layer
		for c in lyr.get_children():
			if c is CanvasItem:
				tw.parallel().tween_property(c, "modulate:a", 0.0, 0.4)
		tw.tween_callback(func(): if is_instance_valid(lyr): lyr.queue_free())
	story_layer = null
	_story_lines = []
	_story_tap_label = null


# ── 이스터에그 (mino1 _updateEasterEgg) ─────────────────────
func _update_easter_egg(dt: float) -> void:
	var p: Dictionary = GameState.player
	# 좌상단 구석 → +10 레벨 (1회)
	if not egg_tl_used and float(p.get("x", 0)) < 200.0 and float(p.get("y", 0)) < 200.0:
		egg_tl_used = true
		_grant_bonus_levels(10, "★ 비밀의 봉우리! +10 ★")
		check_job_unlock()
		return
	if egg_used:
		return
	# 좌하단 구석 영역에서 공격 12연타 → +12 레벨
	var in_corner := float(p.get("x", 0)) < 400.0 and float(p.get("y", 0)) > GameData.WORLD_H - 400.0
	var atk_active := atk_btn_pressed or Input.is_key_pressed(KEY_SPACE)
	if atk_active and not egg_prev_atk:
		if in_corner:
			egg_attack_count += 1
			egg_attack_timer = 2.0
	egg_prev_atk = atk_active
	if egg_attack_timer > 0.0:
		egg_attack_timer -= dt
		if egg_attack_timer <= 0.0:
			egg_attack_count = 0
	if egg_attack_count >= 12 and in_corner and not egg_used:
		egg_used = true
		egg_attack_count = 0
		_grant_bonus_levels(12, "★ 비밀 발견! +12 ★")
		check_job_unlock()


# 보너스 레벨 지급 + 화려한 연출 (mino1 _grantBonusLevels)
func _grant_bonus_levels(add_levels: int, title: String) -> void:
	var p: Dictionary = GameState.player
	for k in add_levels:
		p["lvl"] = int(p.get("lvl", 1)) + 1
		p["xp"] = 0
		p["xpNext"] = int(round(int(p.get("xpNext", 20)) * 1.5))
		p["maxhp"] = float(p.get("maxhp", 0)) + 10.0
		p["atkPow"] = float(p.get("atkPow", 0)) + 2.0
		p["hp"] = p["maxhp"]
		p["mp"] = p["maxmp"]
		p["statPoints"] = int(p.get("statPoints", 0)) + 3
	# 흰 섬광 + 파티클 (skills 의 플래시 재사용)
	if skills:
		skills.trigger_flash(Color8(0xff, 0xff, 0xff), 0.85)
	for i in 5:
		fx.add_particles(player.global_position, Color8(0xff, 0xdd, 0x22), 20)
		fx.add_particles(player.global_position, Color8(0xff, 0x88, 0x00), 12)
	add_shake(0.3, 8.0)
	show_center_message("%s\nLv %d!" % [title, int(p.get("lvl", 1))])
	Audio.levelup()
	GameState.save_game()


# ── 풀밭 텍스처 생성 (mino1: grass_soft, 오염된 땅) ───────────
func _make_grass_tex() -> ImageTexture:
	var s := GRASS_TILE
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	# 베이스: 어두운 녹갈색 (오염된 흙)
	img.fill(Color8(0x2e, 0x3d, 0x1f))

	var rng := GameData.make_rng(99)
	# 레이어 1: 큰 오염 음영 패치 (갈색·이끼)
	var base_tones := [Color8(0x3a, 0x4a, 0x22), Color8(0x28, 0x32, 0x1a),
		Color8(0x3f, 0x4d, 0x25), Color8(0x24, 0x30, 0x16), Color8(0x33, 0x42, 0x28)]
	for i in 80:
		_blob(img, rng, base_tones[i % base_tones.size()], 0.22, 18.0, 55.0, s)
	# 레이어 2: 보라/독성 오염 얼룩
	var tox_tones := [Color8(0x5a, 0x1e, 0x7a), Color8(0x6b, 0x2d, 0x8c),
		Color8(0x45, 0x15, 0x60), Color8(0x7a, 0x3a, 0x9a)]
	for i in 40:
		_blob(img, rng, tox_tones[i % tox_tones.size()], 0.11, 10.0, 32.0, s)
	# 레이어 3: 건조한 황갈색 흙 패치
	for i in 50:
		_blob(img, rng, Color8(0x5c, 0x4a, 0x2a), 0.10, 8.0, 24.0, s)
	# 레이어 4: 밝기 변화 (노이즈 느낌)
	for i in 60:
		_blob(img, rng, Color8(0x4a, 0x5c, 0x2a), 0.07, 4.0, 12.0, s)

	return ImageTexture.create_from_image(img)


# 원형 얼룩 하나를 알파 블렌딩으로 찍는다 (mino1 fillCircle 대응)
func _blob(img: Image, rng: GameData.RNG, col: Color, alpha: float, rmin: float, rmax: float, s: int) -> void:
	var cx := rng.range_f(0.0, float(s))
	var cy := rng.range_f(0.0, float(s))
	var rad := rng.range_f(rmin, rmax)
	var r2 := rad * rad
	var x0 := maxi(0, int(cx - rad))
	var x1 := mini(s - 1, int(cx + rad))
	var y0 := maxi(0, int(cy - rad))
	var y1 := mini(s - 1, int(cy + rad))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := x - cx
			var dy := y - cy
			if dx * dx + dy * dy <= r2:
				var dst := img.get_pixel(x, y)
				img.set_pixel(x, y, dst.lerp(col, alpha))
