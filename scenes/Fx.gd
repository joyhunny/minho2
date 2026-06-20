extends Node2D
## Fx — 전투 이펙트(파티클·임팩트 원·예고선·슬래시 호)를 월드 좌표에 직접 그린다.
## mino1 play.js 의 _partGfx·_impactGfx·_telegraphGfx·_slashGfx(Phaser Graphics) 대응.
## Main 이 데이터 배열을 채우고, 여기서 매 프레임 _draw 로 그린다(화면 좌표 변환 불필요 — 월드 노드).
##
## 데이터 형식:
##  particles : [{pos:Vector2, vel:Vector2, life:float, t:float, color:Color, size:float}]
##  impacts   : [{pos:Vector2, t:float, life:float, r:float, color:Color}]
##  telegraphs: 매 프레임 Main(적 AI)이 다시 채움 → _draw 후 비움
##  slash     : Main 이 플레이어 슬래시 타이머로 채움 (pos·face·alpha·range)

var particles: Array = []
var impacts: Array = []
var telegraphs: Array = []   # {kind:"dash"|"circle", ...}
var slash: Dictionary = {}    # {} 이면 안 그림

var main: Node = null


func _process(delta: float) -> void:
	var ts: float = main.time_scale if main else 1.0
	var dt := delta * ts

	# ── 파티클 갱신 (mino1 _updateParticles: 중력+감속) ──
	for i in range(particles.size() - 1, -1, -1):
		var pt: Dictionary = particles[i]
		pt.t += dt
		pt.pos += pt.vel * dt
		pt.vel.y += 120.0 * dt
		pt.vel.x *= pow(0.9, dt * 60.0)
		if pt.t >= pt.life:
			particles.remove_at(i)

	# ── 임팩트 원 갱신 (mino1 _updateImpactEffects) ──
	for i in range(impacts.size() - 1, -1, -1):
		var ef: Dictionary = impacts[i]
		ef.t += dt
		if ef.t >= ef.life:
			impacts.remove_at(i)

	# ── 슬래시 타이머 ──
	if not slash.is_empty():
		slash.t -= dt
		if slash.t <= 0.0:
			slash = {}

	queue_redraw()


func _draw() -> void:
	# ── 파티클 (사각형 파편) ──
	for pt in particles:
		var alpha: float = maxf(0.0, 1.0 - pt.t / pt.life)
		var c: Color = pt.color
		c.a = alpha
		var s: float = pt.size
		draw_rect(Rect2(pt.pos.x - s / 2.0, pt.pos.y - s / 2.0, s, s), c)

	# ── 임팩트 원 (흰 원 확산) ──
	for ef in impacts:
		var pct: float = ef.t / ef.life
		var alpha: float = maxf(0.0, 1.0 - pct)
		var r: float = ef.r * (0.3 + pct * 0.7)
		var col: Color = ef.color
		var fill: Color = col
		fill.a = alpha * 0.34
		draw_circle(ef.pos, r, fill)
		var line: Color = col
		line.a = alpha * 0.95
		var lw: float = 3.0 if r > 30.0 else 2.0
		draw_arc(ef.pos, r, 0.0, TAU, 40, line, lw)

	# ── 예고선/원 (boar 돌진·croc 매복) ──
	for tg in telegraphs:
		if tg.kind == "dash":
			var prog: float = tg.prog
			var origin: Vector2 = tg.pos
			var dir: Vector2 = tg.dir
			var dash_len := 200.0
			var tip: Vector2 = origin + dir * dash_len * prog
			var lc := Color(1.0, 0.13, 0.0, 0.7 * prog)
			draw_line(origin, tip, lc, 3.0)
			if prog > 0.5:
				var n := Vector2(-dir.y, dir.x) * 8.0
				var back := tip - dir * 16.0
				var tri := PackedVector2Array([tip, back + n, back - n])
				draw_colored_polygon(tri, Color(1.0, 0.13, 0.0, 0.8 * prog))
		elif tg.kind == "circle":
			var ic := Color(1.0, 0.2, 0.0, 0.9 * tg.alpha)
			draw_arc(tg.pos, tg.r, 0.0, TAU, 36, ic, 3.0)
			var fc := Color(1.0, 0.2, 0.0, 0.08 * tg.alpha)
			draw_circle(tg.pos, tg.r, fc)
		elif tg.kind == "boss_line":
			# 보스 돌진 예고선 (긴 굵은 선) — mino1 _telegraphGfx
			var origin2: Vector2 = tg.pos
			var dir2: Vector2 = tg.dir
			var line_len: float = tg.get("len", 280.0)
			var bc: Color = tg.get("color", Color(1.0, 0.67, 0.33))
			bc.a = tg.get("alpha", 0.8)
			draw_line(origin2, origin2 + dir2 * line_len, bc, 5.0)
	telegraphs.clear()   # 매 프레임 적 AI 가 다시 채운다

	# ── 슬래시 호 (3중 선) (mino1 _drawSlash) ──
	if not slash.is_empty():
		var alpha: float = maxf(0.0, slash.t / 0.22)
		var p: Vector2 = slash.pos
		var face: int = slash.face
		var r: float = slash.range * 0.75
		var start_a: float = -1.3 if face > 0 else PI - 0.7
		var end_a: float = 0.7 if face > 0 else PI + 1.3
		draw_arc(p, r, start_a, end_a, 24, Color(1, 1, 1, alpha * 0.25), 9.0)
		draw_arc(p, r, start_a, end_a, 24, Color(0.53, 0.87, 1.0, alpha * 0.95), 5.0)
		draw_arc(p, r, start_a, end_a, 24, Color(1, 1, 1, alpha), 2.0)


# ── Main/적이 호출하는 추가 헬퍼 ────────────────────────────
func add_particles(pos: Vector2, color: Color, count: int) -> void:
	var cap := 80
	var n: int = mini(count, cap)
	if particles.size() + n > cap:
		var excess: int = particles.size() + n - cap
		for _i in min(excess, particles.size()):
			particles.pop_front()
	for _i in n:
		var ang := randf() * TAU
		var spd := 80.0 + randf() * 180.0
		particles.append({
			"pos": pos,
			"vel": Vector2(cos(ang) * spd, sin(ang) * spd - 40.0),
			"life": 0.5 + randf() * 0.35,
			"t": 0.0,
			"color": color,
			"size": 4.0 + randf() * 6.0,
		})


func add_impact(pos: Vector2, r: float, color: Color) -> void:
	impacts.append({"pos": pos, "t": 0.0, "life": 0.2, "r": r, "color": color})


func add_impact_hit(pos: Vector2, is_crit: bool) -> void:
	# 타격 충격 (흰 원 + 밝은 파편) (mino1 _spawnImpact)
	var r := 40.0 if is_crit else 26.0
	impacts.append({"pos": pos, "t": 0.0, "life": 0.15, "r": r, "color": Color.WHITE})
	var n := 8 if is_crit else 5
	var frag_col := Color8(0xff, 0xee, 0x44) if is_crit else Color.WHITE
	for _i in n:
		var ang := randf() * TAU
		var spd := 50.0 + randf() * 100.0
		particles.append({
			"pos": pos,
			"vel": Vector2(cos(ang) * spd, sin(ang) * spd),
			"life": 0.18 + randf() * 0.12,
			"t": 0.0,
			"color": frag_col,
			"size": 3.0 + randf() * 4.0,
		})
