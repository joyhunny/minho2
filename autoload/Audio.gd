extends Node
## Audio — 효과음·BGM (mino1 sound.js 의 Godot 이식).
## mino1 은 음원 파일 0개로 Web Audio 로 소리를 '합성'했다(저작권 0·용량 0).
## 여기서도 똑같이 — 외부 파일 없이 GDScript 로 짧은 PCM 파형을 만들어
## AudioStreamWAV 로 굽는다. 그래서 다운로드·라이선스·인터넷 의존이 전혀 없다.
##
## 호출: Audio.hit() / Audio.levelup() / Audio.roar() ... (mino1 MinoSound.* 와 1:1)
## 토글: Audio.set_muted(true/false), Audio.toggle() — 소리 켜고 끄기.
##
## autoload 싱글톤이라 어디서든 Audio.xxx() 로 부른다. (mino1 window.MinoSound 대응)

const SR := 22050             # 샘플레이트(Hz). 효과음엔 충분, 용량 절약.
const TAU_F := 6.28318530718

var muted := false            # 소리 끄기
var _sfx_players: Array = []  # 효과음 재생용 풀(동시 여러 소리)
var _sfx_idx := 0
const SFX_VOICES := 8         # 동시 재생 가능한 효과음 수

var _bgm_player: AudioStreamPlayer = null
var _cache: Dictionary = {}   # 이름 → AudioStreamWAV (한 번 합성하면 재사용)


func _ready() -> void:
	# 저장된 음소거 설정 복원 (있으면)
	if "muted" in GameState and typeof(GameState.get("muted")) == TYPE_BOOL:
		muted = GameState.get("muted")
	# 효과음 재생기 풀 — 같은 순간 여러 소리가 안 잘리게
	for i in SFX_VOICES:
		var pl := AudioStreamPlayer.new()
		pl.bus = "Master"
		add_child(pl)
		_sfx_players.append(pl)
	# BGM 재생기 (루프)
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = "Master"
	_bgm_player.volume_db = -12.0
	add_child(_bgm_player)


# ════════════════════════════════════════════════════════════
#  공개 API — mino1 MinoSound.* 와 1:1
# ════════════════════════════════════════════════════════════
func attack() -> void: _play("attack")     # 검 휘두름
func hit() -> void: _play("hit")            # 타격
func crit() -> void: _play("crit")          # 치명타
func kill() -> void: _play("kill")          # 처치
func levelup() -> void: _play("levelup")    # 레벨업 아르페지오
func heal() -> void: _play("heal")          # 카피바라 치유
func hurt() -> void: _play("hurt")          # 주인공 피격
func roar() -> void: _play("roar")          # 보스 포효
func boom() -> void: _play("boom")          # 운석 폭발
func tame() -> void: _play("tame")          # 슬라임 길들임
func win() -> void: _play("win")            # 승리 팡파레
func ui_tap() -> void: _play("ui")          # UI 버튼 탭(mino1 엔 없던 추가)


# ── 소리 켜고/끄기 ──
func set_muted(v: bool) -> void:
	muted = v
	if "muted" in GameState:
		GameState.set("muted", v)
	if _bgm_player:
		_bgm_player.stream_paused = muted
		if not muted and not _bgm_player.playing and _bgm_player.stream != null:
			_bgm_player.play()


func toggle() -> void:
	set_muted(not muted)


func is_muted() -> bool:
	return muted


# ── BGM 시작/정지 (합성한 잔잔한 루프) ──
func start_bgm() -> void:
	if _bgm_player == null:
		return
	if _bgm_player.stream == null:
		_bgm_player.stream = _build_bgm()
	if muted:
		return
	if not _bgm_player.playing:
		_bgm_player.play()


func stop_bgm() -> void:
	if _bgm_player:
		_bgm_player.stop()


# ════════════════════════════════════════════════════════════
#  재생: 풀에서 비어 있는 재생기를 골라 굽힌 WAV 를 틀기
# ════════════════════════════════════════════════════════════
func _play(name: String) -> void:
	if muted:
		return
	var stream: AudioStreamWAV = _cache.get(name, null)
	if stream == null:
		stream = _synth(name)
		_cache[name] = stream
	if stream == null:
		return
	# 라운드로빈으로 재생기 선택 (가급적 안 쓰는 것)
	var pl: AudioStreamPlayer = _sfx_players[_sfx_idx]
	_sfx_idx = (_sfx_idx + 1) % _sfx_players.size()
	pl.stream = stream
	pl.play()


# ════════════════════════════════════════════════════════════
#  파형 합성 — mino1 sound.js 의 tone()/noise() 를 PCM 으로 옮김
# ════════════════════════════════════════════════════════════

# 부호화: 16비트 PCM 모노 PackedByteArray 로 샘플 배열을 굽는다.
func _bake(samples: PackedFloat32Array) -> AudioStreamWAV:
	var n := samples.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v := clampf(samples[i], -1.0, 1.0)
		var s := int(round(v * 32767.0))
		data.encode_s16(i * 2, s)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SR
	wav.stereo = false
	wav.data = data
	return wav


# 톤 1발 (주파수 슬라이드 + 게인 엔벨로프). mino1 tone() 대응.
# f0→f1 지수 슬라이드, 8ms 어택, dur 동안 지수 감쇠.
func _tone_into(buf: PackedFloat32Array, f0: float, f1: float, dur: float, wave: String, vol: float, delay: float) -> void:
	var start := int(delay * SR)
	var ln := int(dur * SR)
	var phase := 0.0
	for i in ln:
		var idx := start + i
		if idx < 0 or idx >= buf.size():
			continue
		var t := float(i) / float(SR)
		var frac := t / dur
		# 지수 주파수 슬라이드 (mino1 exponentialRampToValueAtTime)
		var f := f0
		if f1 > 0.0 and not is_equal_approx(f1, f0):
			f = f0 * pow(maxf(1.0, f1) / f0, frac)
		phase += TAU_F * f / float(SR)
		var s := _wave(wave, phase)
		# 엔벨로프: 8ms 어택 → 지수 감쇠
		var env := 1.0
		var atk := 0.008
		if t < atk:
			env = t / atk
		else:
			# vol→0.0001 까지 지수 감쇠 (mino1 과 같은 모양)
			env = pow(0.0001 / 1.0, (t - atk) / maxf(0.001, dur - atk))
		buf[idx] += s * vol * env


# 노이즈 버스트 (폭발·타격감). mino1 noise() 대응 (선형 페이드아웃 + 로우패스 근사).
func _noise_into(buf: PackedFloat32Array, dur: float, vol: float, lowpass: float, delay: float) -> void:
	var start := int(delay * SR)
	var ln := int(dur * SR)
	var prev := 0.0
	# 단순 1극 로우패스 계수 (lowpass Hz 가 작을수록 더 둔탁)
	var alpha := 1.0
	if lowpass > 0.0:
		var rc := 1.0 / (TAU_F * lowpass)
		var dt := 1.0 / float(SR)
		alpha = dt / (rc + dt)
	for i in ln:
		var idx := start + i
		if idx < 0 or idx >= buf.size():
			continue
		var white := randf() * 2.0 - 1.0
		var filtered := prev + alpha * (white - prev)
		prev = filtered
		var env := 1.0 - float(i) / float(ln)   # 선형 페이드아웃 (mino1)
		buf[idx] += filtered * vol * env


func _wave(kind: String, phase: float) -> float:
	var x := fmod(phase, TAU_F)
	match kind:
		"square":
			return 1.0 if sin(x) >= 0.0 else -1.0
		"sawtooth":
			return (x / TAU_F) * 2.0 - 1.0
		"triangle":
			var p := x / TAU_F
			return 4.0 * absf(p - 0.5) - 1.0
		_:  # sine
			return sin(x)


# 효과음 한 종류를 합성 (mino1 MinoSound return 객체와 1:1).
func _synth(name: String) -> AudioStreamWAV:
	match name:
		"attack":
			var b := _new_buf(0.16)
			_tone_into(b, 620, 280, 0.12, "square", 0.10, 0.0)
			return _bake(b)
		"hit":
			var b := _new_buf(0.12)
			_tone_into(b, 180, 90, 0.08, "square", 0.12, 0.0)
			_noise_into(b, 0.06, 0.10, 1200, 0.0)
			return _bake(b)
		"crit":
			var b := _new_buf(0.20)
			_tone_into(b, 900, 300, 0.16, "sawtooth", 0.14, 0.0)
			_noise_into(b, 0.08, 0.14, 2000, 0.0)
			return _bake(b)
		"kill":
			var b := _new_buf(0.16)
			_tone_into(b, 300, 520, 0.12, "triangle", 0.12, 0.0)
			return _bake(b)
		"levelup":
			var b := _new_buf(0.55)
			var notes := [523.0, 659.0, 784.0, 1047.0]
			for i in notes.size():
				_tone_into(b, notes[i], notes[i], 0.16, "square", 0.12, i * 0.09)
			return _bake(b)
		"heal":
			var b := _new_buf(0.26)
			_tone_into(b, 680, 920, 0.22, "sine", 0.10, 0.0)
			return _bake(b)
		"hurt":
			var b := _new_buf(0.22)
			_tone_into(b, 220, 110, 0.18, "sawtooth", 0.13, 0.0)
			return _bake(b)
		"roar":
			var b := _new_buf(0.7)
			_tone_into(b, 120, 60, 0.6, "sawtooth", 0.22, 0.0)
			_noise_into(b, 0.5, 0.16, 500, 0.0)
			return _bake(b)
		"boom":
			var b := _new_buf(0.45)
			_tone_into(b, 90, 40, 0.4, "square", 0.20, 0.0)
			_noise_into(b, 0.35, 0.22, 700, 0.0)
			return _bake(b)
		"tame":
			var b := _new_buf(0.4)
			var tn := [440.0, 660.0, 880.0]
			for i in tn.size():
				_tone_into(b, tn[i], tn[i], 0.14, "sine", 0.10, i * 0.07)
			return _bake(b)
		"win":
			var b := _new_buf(1.0)
			var wn := [523.0, 659.0, 784.0, 1047.0, 1319.0]
			for i in wn.size():
				_tone_into(b, wn[i], wn[i], 0.3, "square", 0.13, i * 0.14)
			return _bake(b)
		"ui":
			# UI 탭: 짧고 가벼운 클릭 (mino1엔 없던 추가)
			var b := _new_buf(0.08)
			_tone_into(b, 880, 660, 0.06, "sine", 0.08, 0.0)
			return _bake(b)
	return null


func _new_buf(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(dur * SR) + 1)
	b.fill(0.0)
	return b


# ════════════════════════════════════════════════════════════
#  BGM — 잔잔한 루프 (합성). 외부 음원 없이 16초 코드 루프.
# ════════════════════════════════════════════════════════════
# 느린 미니멀 아르페지오 + 베이스 패드. loop_mode 로 끊김 없이 반복.
func _build_bgm() -> AudioStreamWAV:
	var bar := 2.0                # 한 마디 길이(초)
	var bars := 8                 # 마디 수 → 16초 루프
	var dur := bar * bars
	var buf := _new_buf(dur)
	# 코드 진행 (Am - F - C - G 느낌, 부드럽게)
	# 각 마디의 근음(Hz) + 아르페지오 3음
	var roots := [220.0, 174.6, 130.8, 196.0, 220.0, 174.6, 130.8, 98.0]
	var arps := [
		[440.0, 523.0, 659.0],
		[349.0, 440.0, 523.0],
		[392.0, 523.0, 659.0],
		[392.0, 493.0, 587.0],
		[440.0, 523.0, 659.0],
		[349.0, 440.0, 523.0],
		[392.0, 523.0, 659.0],
		[293.0, 392.0, 493.0],
	]
	for bi in bars:
		var bstart := bi * bar
		# 베이스 패드 (낮은 사인, 길게)
		_tone_pad(buf, roots[bi], bar * 0.96, 0.06, bstart)
		_tone_pad(buf, roots[bi] * 2.0, bar * 0.96, 0.03, bstart)
		# 아르페지오 (마디 안에서 4번 또르륵)
		var notes: Array = arps[bi]
		for k in 4:
			var n: float = notes[k % notes.size()]
			_tone_into(buf, n, n, 0.32, "sine", 0.05, bstart + k * (bar / 4.0))
	var wav := _bake(buf)
	# 끊김 없이 반복
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = buf.size()
	return wav


# 패드용 부드러운 톤 (어택·릴리즈가 긴 사인) — BGM 베이스에 사용.
func _tone_pad(buf: PackedFloat32Array, f: float, dur: float, vol: float, delay: float) -> void:
	var start := int(delay * SR)
	var ln := int(dur * SR)
	var phase := 0.0
	var atk := 0.25
	var rel := 0.5
	for i in ln:
		var idx := start + i
		if idx < 0 or idx >= buf.size():
			continue
		var t := float(i) / float(SR)
		phase += TAU_F * f / float(SR)
		var s := sin(phase)
		var env := 1.0
		if t < atk:
			env = t / atk
		elif t > dur - rel:
			env = maxf(0.0, (dur - t) / rel)
		buf[idx] += s * vol * env
