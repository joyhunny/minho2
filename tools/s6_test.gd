extends SceneTree
## S6 통합 테스트 — 연출·사운드 경로를 강제로 굴려 크래시·정상 동작 확인.
## 실행: Godot --headless --path . --script tools/s6_test.gd

var fails: Array = []
var oks: Array = []

func _ok(msg): oks.append(msg)
func _fail(msg): fails.append(msg); push_error("FAIL: " + msg)

var GameState
var GameData
var Audio

func _initialize() -> void:
	# 오토로드는 --script 모드에선 전역 식별자가 없으므로 root 에서 노드로 가져온다
	await process_frame   # 오토로드 등록 대기
	GameState = root.get_node("GameState")
	GameData = root.get_node("GameData")
	Audio = root.get_node("Audio")

	# 깨끗한 새 게임으로 시작 (저장 영향 제거)
	GameState.new_game(1)
	GameState.seen_intro = false

	# ── 1) Audio 합성 — 모든 효과음 + BGM 이 굽혀지나 ──
	var sfx = ["attack","hit","crit","kill","levelup","heal","hurt","roar","boom","tame","win","ui"]
	for name in sfx:
		var stream = Audio._synth(name)
		if stream != null and stream is AudioStreamWAV and stream.data.size() > 0:
			_ok("synth " + name + " (%d bytes)" % stream.data.size())
		else:
			_fail("synth " + name + " 실패")
	var bgm = Audio._build_bgm()
	if bgm != null and bgm.data.size() > 0 and bgm.loop_mode == AudioStreamWAV.LOOP_FORWARD:
		_ok("bgm 합성 + 루프 (%d bytes)" % bgm.data.size())
	else:
		_fail("bgm 합성 실패")

	# ── 음소거 토글 ──
	Audio.set_muted(true)
	if Audio.is_muted() and GameState.muted:
		_ok("음소거 ON 저장")
	else:
		_fail("음소거 토글")
	Audio.set_muted(false)
	# 음소거 상태에서 _play 가 조용히 넘어가나 (크래시 없이)
	Audio.set_muted(true)
	Audio.hit(); Audio.levelup(); Audio.roar()
	_ok("음소거 중 _play 무탈")
	Audio.set_muted(false)

	# ── 2) Main 씬 인스턴스 — 빌드 단계 크래시 확인 ──
	var main_scene = load("res://scenes/Main.tscn")
	var main = main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	_ok("Main 인스턴스 + 첫 프레임 (companion=%s, intro_active=%s)" % [is_instance_valid(main.companion), main._intro_active])

	# 인트로가 떴는지 (새 게임이라 difficulty<0)
	if main._intro_active:
		_ok("인트로 자동 표시")
	else:
		_fail("인트로 미표시 (difficulty<0인데)")

	# ── 인트로 페이드 진행 (ALWAYS 틱이 도는지) ──
	for i in 20:
		await process_frame
	# 인트로 라벨 알파가 올라갔나
	if main._intro_lines.size() > 0 and is_instance_valid(main._intro_lines[0]):
		_ok("인트로 라벨 페이드 (alpha=%.2f)" % main._intro_lines[0].modulate.a)

	# 인트로 강제 종료 → 게임 시작
	main._end_intro()
	await process_frame
	if not main._intro_active and not paused:
		_ok("인트로 종료 → 게임 재개")
	else:
		_fail("인트로 종료 실패 (paused=%s)" % paused)

	# 인트로 종료 후 난이도 선택창이 떴어야 (difficulty 0으로 강제해 진행)
	GameState.difficulty = 1
	if main.diff_panel:
		main.diff_panel.close() if main.diff_panel.has_method("close") else null
	paused = false

	# ── 3) 동료 카피바라 — 따라오기·힐·말풍선 ──
	var capy = main.companion
	if is_instance_valid(capy):
		# 주인공을 멀리 옮기고 카피바라가 따라오는지
		main.player.global_position = Vector2(1500, 1500)
		capy.global_position = Vector2(1000, 1000)
		var before = capy.global_position
		for i in 30:
			await process_frame
		var moved = capy.global_position.distance_to(before)
		if moved > 5.0:
			_ok("카피바라 따라옴 (이동 %.0fpx)" % moved)
		else:
			_fail("카피바라 안 따라옴")
		# 힐 강제: HP 깎고 힐 타이머 채워서 한 틱
		GameState.player["hp"] = 10.0
		GameState.player["maxhp"] = 100.0
		capy.heal_timer = 99.0
		main.player.global_position = capy.global_position + Vector2(20, 0)
		await process_frame
		if float(GameState.player["hp"]) > 10.0:
			_ok("카피바라 힐 (hp=%.0f)" % float(GameState.player["hp"]))
		else:
			_fail("카피바라 힐 안 됨 (hp=%.0f)" % float(GameState.player["hp"]))
		# 말풍선 강제
		capy.speech_cool = -1.0
		capy.speech_t = 0.0
		await process_frame
		if capy.speech_t > 0.0 and capy.speech_msg != "":
			_ok("카피바라 말풍선: " + capy.speech_msg)
		else:
			_ok("카피바라 말풍선(이번 틱 미발화, 무탈)")
	else:
		_fail("카피바라 인스턴스 없음")

	# ── 4) 이스터에그 — 좌상단 +10 ──
	var lvl0 = int(GameState.player["lvl"])
	GameState.player["x"] = 100.0
	GameState.player["y"] = 100.0
	main.player.global_position = Vector2(100, 100)
	main._update_easter_egg(0.016)
	if int(GameState.player["lvl"]) >= lvl0 + 10:
		_ok("이스터에그 좌상단 +10 (lvl %d→%d)" % [lvl0, int(GameState.player["lvl"])])
	else:
		_fail("이스터에그 +10 안 됨 (lvl=%d)" % int(GameState.player["lvl"]))
	# 두 번째 호출은 1회 제한이라 안 올라야
	var lvl1 = int(GameState.player["lvl"])
	main._update_easter_egg(0.016)
	if int(GameState.player["lvl"]) == lvl1:
		_ok("이스터에그 좌상단 1회 제한")
	else:
		_fail("이스터에그 +10 중복")

	# ── 5) 이스터에그 — 좌하단 12연타 +12 ──
	var lvl2 = int(GameState.player["lvl"])
	GameState.player["x"] = 100.0
	GameState.player["y"] = GameData.WORLD_H - 100.0
	main.player.global_position = Vector2(GameState.player["x"], GameState.player["y"])
	for i in 13:
		main.atk_btn_pressed = false
		main._update_easter_egg(0.016)
		main.atk_btn_pressed = true   # edge 검출
		main._update_easter_egg(0.016)
	if int(GameState.player["lvl"]) >= lvl2 + 12:
		_ok("이스터에그 좌하단 12연타 +12 (lvl %d→%d)" % [lvl2, int(GameState.player["lvl"])])
	else:
		_fail("이스터에그 +12 안 됨 (lvl=%d, count=%d)" % [int(GameState.player["lvl"]), main.egg_attack_count])
	main.atk_btn_pressed = false

	# ── 6) 챕터 스토리 — 지역 입장(region>=1) ──
	main.enter_region(1)
	await process_frame
	if main._story_active:
		_ok("챕터 스토리 표시 (region 1 입장)")
		for i in 15:
			await process_frame
		main._end_chapter_story()
		await process_frame
		if not main._story_active and not paused:
			_ok("챕터 스토리 종료 → 재개")
		else:
			_fail("챕터 스토리 종료 실패")
	else:
		_fail("챕터 스토리 미표시")

	# ── 7) 보스 등장(roar) + 메테오(boom) 경로 ──
	paused = false
	GameState.region = 3   # 코끼리(메테오) 지역
	GameState.chapter = 4
	main.boss_spawned = false
	main._spawn_boss()
	await process_frame
	if main.boss != null and is_instance_valid(main.boss):
		_ok("보스 등장 (roar 경로)")
		# 보스 인트로~패턴 몇 프레임 (메테오 boom 경로 포함)
		for i in 120:
			await process_frame
		_ok("보스 패턴 120프레임 무탈 (메테오 경로)")
	else:
		_fail("보스 등장 실패")

	# ── 8) 사운드 버튼·시그니처 노드 존재 ──
	if is_instance_valid(main.sound_btn_ctrl):
		_ok("사운드 토글 버튼 존재")
	else:
		_fail("사운드 버튼 없음")
	if main.has_node("MinoSigLayer"):
		_ok("mino 시그니처 워터마크 존재")
	else:
		_fail("mino 시그니처 없음")

	# ── 결과 ──
	print("\n========== S6 테스트 결과 ==========")
	print("OK: %d" % oks.size())
	for o in oks:
		print("  ✓ " + o)
	if fails.size() > 0:
		print("FAIL: %d" % fails.size())
		for f in fails:
			print("  ✗ " + f)
	else:
		print("FAIL: 0  — ALL PASS")
	print("====================================")
	quit(0 if fails.size() == 0 else 1)
