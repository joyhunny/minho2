extends SceneTree
## 입력 주입 테스트 — 진짜 터치/마우스 이벤트를 뷰포트에 흘려
## 조이스틱(이동)·공격버튼·패널 토글이 작동하는지 확인.
## 실행: Godot --headless --path . --script tools/input_test.gd
## (헤드리스 창은 작게 떠 stretch 가 좌표를 키우므로 push_input 은 in_local_coords=true 로
##  창→캔버스 변환을 건너뛰고 '캔버스(720x1280) 좌표' 로 바로 주입한다 = 실기기와 동일 좌표계.)

var GameState
var GameData
var fails: Array = []
var oks: Array = []
func _ok(m): oks.append(m); print("  OK  ", m)
func _fail(m): fails.append(m); push_error("FAIL: " + m); print("  XX  ", m)
func _chk(cond, ok_msg, fail_msg):
	if cond: _ok(ok_msg)
	else: _fail(fail_msg)

func _touch(idx, pos, pressed):
	var e := InputEventScreenTouch.new(); e.index = idx; e.position = pos; e.pressed = pressed
	root.push_input(e, true)
func _drag(idx, pos, rel):
	var e := InputEventScreenDrag.new(); e.index = idx; e.position = pos; e.relative = rel
	root.push_input(e, true)
func _mbtn(pos, pressed):
	var e := InputEventMouseButton.new(); e.button_index = MOUSE_BUTTON_LEFT; e.pressed = pressed; e.position = pos
	root.push_input(e, true)

func _count_blockers(node, acc):
	if node is Control:
		var c := node as Control
		if c.visible and c.mouse_filter == Control.MOUSE_FILTER_STOP:
			var r := c.get_global_rect()
			if r.size.x > 300 and r.size.y > 300:
				acc.append(c.get_path())
	for ch in node.get_children():
		_count_blockers(ch, acc)

func _initialize() -> void:
	await process_frame
	GameState = root.get_node("GameState")
	GameData = root.get_node("GameData")
	GameState.new_game(1)
	GameState.seen_intro = false

	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	if main._intro_active:
		main._end_intro()
	GameState.difficulty = 1
	if main.diff_panel and main.diff_panel.visible and main.diff_panel.has_method("_close"):
		main.diff_panel._close()
	paused = false
	await process_frame

	var vp = root.get_visible_rect().size
	print("뷰포트=%s JOY_MAX=%s" % [vp, main.JOY_MAX])

	# ── 0) 게임플레이 중 화면을 막는 STOP 컨트롤이 없어야 ──
	print("\n[0] 시작 시 화면-블로커 스캔")
	var blockers := []
	_count_blockers(main, blockers)
	_chk(blockers.is_empty(), "화면을 막는 큰 STOP 컨트롤 없음", "아직 막는 컨트롤 있음: %s" % str(blockers))

	# ── 1) 터치 조이스틱 + 이동 ──
	print("\n[1] 터치 조이스틱 + 이동")
	var start = Vector2(150, 900)
	_touch(0, start, true)
	await process_frame
	_chk(main.joy_active, "터치 down → 조이스틱 켜짐", "조이스틱 안 켜짐")
	_drag(0, start + Vector2(80, 0), Vector2(80, 0))
	await process_frame
	_chk(main.joy_vec.length() > 0.5, "드래그 → joy_vec=%s" % main.joy_vec, "joy_vec 안 변함 (%s)" % main.joy_vec)
	var p0 = main.player.global_position
	for i in 30: await physics_frame
	var moved = main.player.global_position.distance_to(p0)
	_chk(moved > 20.0, "플레이어 이동 %.0fpx" % moved, "플레이어 안 움직임 (%.1fpx)" % moved)
	_touch(0, start + Vector2(80, 0), false)
	await process_frame
	_chk(not main.joy_active, "터치 떼기 → 조이스틱 꺼짐", "조이스틱 안 꺼짐")

	# ── 2) 공격 버튼 ──
	print("\n[2] 공격 버튼")
	var btn = Vector2(vp.x - 110, vp.y - 130)
	main.atk_btn_pressed = false
	_touch(1, btn, true)
	await process_frame
	_chk(main.atk_btn_pressed, "공격버튼 터치 → pressed=true", "공격버튼 안 눌림")
	_touch(1, btn, false)
	await process_frame
	_chk(not main.atk_btn_pressed, "공격버튼 떼기 → false", "공격버튼 안 떼짐")
	main.atk_btn_pressed = false
	_mbtn(btn, true); await process_frame
	_chk(main.atk_btn_pressed, "공격버튼 마우스 → true", "공격버튼 마우스 안 눌림")
	_mbtn(btn, false); await process_frame

	# ── 3) STAT 패널 토글 ──
	print("\n[3] STAT 패널 토글")
	var stat_btn = main.stat_panel._btn_rect.get_center()
	_touch(2, stat_btn, true); await process_frame; _touch(2, stat_btn, false); await process_frame
	_chk(main.stat_panel.open, "STAT 버튼 → 패널 열림", "STAT 패널 안 열림")
	var b2 := []; _count_blockers(main, b2)
	_chk(not b2.is_empty(), "열렸을 때 모달(STOP) 작동", "열렸는데 모달 아님")
	_touch(2, Vector2(40, 600), true); await process_frame; _touch(2, Vector2(40, 600), false); await process_frame
	_chk(not main.stat_panel.open, "패널 밖 탭 → 닫힘", "패널 안 닫힘")
	_chk(main.stat_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "닫힘 후 IGNORE 복귀", "닫힘 후에도 STOP")
	_touch(3, Vector2(150, 900), true); await process_frame
	_drag(3, Vector2(240, 900), Vector2(90, 0)); await process_frame
	var p1 = main.player.global_position
	for i in 20: await physics_frame
	_chk(main.player.global_position.distance_to(p1) > 15.0, "닫은 뒤 이동 정상", "닫은 뒤 이동 안 됨")
	_touch(3, Vector2(240, 900), false); await process_frame

	# ── 4) 가방 패널 토글 ──
	print("\n[4] 가방 패널 토글")
	var bag_btn = main.inv_panel._btn_rect.get_center()
	_touch(4, bag_btn, true); await process_frame; _touch(4, bag_btn, false); await process_frame
	_chk(main.inv_panel.open, "가방 버튼 → 패널 열림 (paused=%s)" % paused, "가방 패널 안 열림")
	if main.inv_panel.open:
		main.inv_panel._close(); await process_frame
	_chk(not main.inv_panel.open and not paused, "가방 닫힘 → 일시정지 해제", "가방 닫힘/해제 실패")

	print("\n===== 결과: OK %d / FAIL %d =====" % [oks.size(), fails.size()])
	if fails.is_empty():
		print("ALL PASS")
	else:
		print("FAILS:")
		for f in fails: print("  - ", f)
	quit()
