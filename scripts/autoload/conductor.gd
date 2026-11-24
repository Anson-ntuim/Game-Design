extends Node
## 節拍指揮家：以音訊播放位置為準，提供整首歌共用的節拍時鐘。
## 關卡中所有跟著節奏動的東西都讀 song_beat，確保畫面與音樂同步。

signal beat(beat_index: int)
signal measure(measure_index: int)
signal section_changed(section_index: int)

const REFERENCE_BPM := 120.0

@export var bpm: float = 120.0
@export var beats_per_measure: int = 4
@export var measures_per_section: int = 4
## 音樂檔中第一拍出現的秒數（換成自己的歌時要調整）
@export var first_beat_offset: float = 0.0
@export var music_path: String = "res://assets/music/beat_loop.wav"

var sec_per_beat: float = 0.5
var current_beat: int = -1
## 播放倍率（變速關）：音樂、音效、物理一起加快，像把錄音帶轉快。
## 拍子和物理的比例不變，所以關卡照 120 BPM 設計、驗證就好；song_position 是「歌曲裡的秒數」。
var rate: float = 1.0
var world_rate: float = 1.0
var custom_music: bool = false
var track_name: String = "內建音樂"
## 自訂音樂整首歌的節奏段落（疏／穩／密／爆／切分…），供對拍與 HUD 顯示
var rhythm_sections: Array = []
## 開：把歌曲 BPM 對齊到 REFERENCE_BPM，關卡手感接近原設計速度（歌曲變調變速）
var prefer_reference_tempo: bool = false
var _gameplay: bool = true
var _builtin_stream: AudioStream
var _custom_epoch: float = 0.0
var _custom_loop_start: float = 0.0
var _custom_loop_end: float = 0.0
var _seek_guard_until: int = 0
var _base_rate: float = 1.0
var _slow_mul: float = 1.0
var _slow_beats_left: float = 0.0
## 0~1：配樂壓低音量的程度（休止區的休止拍）
var duck_target: float = 0.0
var _duck: float = 0.0
## 玩家校正的音訊延遲（秒）：耳機／網頁／藍牙常讓聲音比時鐘晚；正值＝聲音晚到，時鐘會往後挪去對齊
var user_offset: float = 0.0

## 暫停中：時鐘停在暫停那一刻，音樂也暫停
var paused: bool = false

var song_position: float:
	get:
		if not _running:
			return 0.0
		if paused:
			return _anchor_position - first_beat_offset - user_offset * rate
		## 物理步裡用「物理時計」：一幀裡連跑兩步物理時（60Hz 螢幕、120 物理），兩步讀到的拍子才會差 1/120 秒，
		## 不會兩步同一拍、下一幀一口氣跳兩步（鞦韆、移動平台因此一頓一頓）
		if _phys_valid and Engine.is_in_physics_frame():
			return _phys_raw - first_beat_offset - user_offset * rate
		return _raw_position() - first_beat_offset - user_offset * rate

## 除錯用（F3 幀率列顯示）：時計和音樂實際位置差多少、最近的最大差距、被拉回來的次數
var stat_err_ms: float = 0.0
var stat_err_max: float = 0.0
var stat_snaps: int = 0

## 開始播音樂後等它真的出聲（播放位置 > 0）才開始走時計；最多等這麼久
const AUDIO_START_TIMEOUT_USEC := 600000
var _await_audio_until: int = 0

## 物理時計：每個物理步固定前進 delta × rate 秒，再慢慢對齊真實時鐘（差太多直接跳過去）
var _phys_raw: float = 0.0
var _phys_prev: float = 0.0
var _phys_valid: bool = false


func _raw_position() -> float:
	return _anchor_position + float(Time.get_ticks_usec() - _anchor_usec) / 1000000.0 * rate


func _physics_process(delta: float) -> void:
	if not _running or paused:
		_phys_valid = false
		return
	var real := _raw_position()
	if not _phys_valid:
		_phys_raw = real
		_phys_prev = real
		_phys_valid = true
		return
	_phys_prev = _phys_raw
	_phys_raw += delta * rate
	var err := real - _phys_raw
	if absf(err) > 0.1:
		_phys_raw = real
		_phys_prev = real
	else:
		_phys_raw += err * 0.05


## 除錯用：物理時計比真實時鐘快（正）或慢（負）幾 ms
func phys_lag_ms() -> float:
	return (_phys_raw - _raw_position()) * 1000.0 if _phys_valid else 0.0


## 畫面用的拍子：和角色一樣在前後兩個物理步之間插值（鞦韆座椅、繩子才會和抓著的角色完全對齊）
func visual_beat() -> float:
	if not _phys_valid or paused:
		return song_beat
	var raw := lerpf(_phys_prev, _phys_raw, Engine.get_physics_interpolation_fraction())
	return (raw - first_beat_offset - user_offset * rate) / sec_per_beat

## 目前聽到的速度
var current_bpm: float:
	get:
		return bpm * rate

var song_beat: float:
	get:
		return song_position / sec_per_beat

## 「聲音時計」：不扣玩家延遲設定的拍子。遊戲自己發出的節奏音效（節拍器、旗子倒數、音符／環的提示音……）
## 都要用這個觸發：音效和音樂經過同一段輸出延遲才到耳朵，用它觸發聽起來才會和音樂對齊。
## 畫面和按鍵判定照樣用 song_beat（已經扣掉延遲，對齊玩家聽到的時間）
var audio_beat: float:
	get:
		return song_beat + user_offset * rate / sec_per_beat

## 節奏提示音提早這麼多秒觸發：音效在畫面更新時才檢查、才送出，平均比音樂晚一點點（實測約 5 ms）
const CUE_LEAD_SEC := 0.005

## 「提示音時計」：遊戲發出的節奏提示音（旗子倒數、節拍器、音符／環的提示音、校正的鼓……）都用這個觸發。
## 音樂時鐘已經扣掉「輸出延遲」（現在混音的位置要再過這麼久才聽到）；音效現在送出，也要過同樣久才聽到，
## 所以提示音要再提早一個輸出延遲，才會和音樂同時到耳朵（網頁上這段常有幾十 ms；桌機回報 0）
var cue_beat: float:
	get:
		return audio_beat + (_output_latency + CUE_LEAD_SEC + _sfx_extra) * rate / sec_per_beat

## 網頁版的提示音額外提早量。以前網頁用「串流」播放（混音和畫面同一條執行緒，畫面一卡聲音就破），
## 新的音效要等下一段混音才開始，實測要再提早約 40～50 ms；現在改成瀏覽器直接播放（sample），沒有這段等待，所以先歸零。
## 測試關可以用 [ ／ ] 即時調整，調好的數字再寫回這裡
const WEB_SFX_EXTRA_SEC := 0.0
## 校正的鼓再多提早這麼多：人跟著單獨的鼓聲按，比跟著音樂按晚（實測約 70 ms），不補的話量出來的設定會讓判定偏早
const WEB_CALIB_EXTRA_SEC := 0.07
var _sfx_extra: float = WEB_SFX_EXTRA_SEC if OS.has_feature("web") else 0.0
var _calib_extra: float = WEB_CALIB_EXTRA_SEC if OS.has_feature("web") else 0.0

## 校正鼓聲用的時計：提示音時計（網頁上）再提早一點，抵銷「跟著單獨鼓聲按會偏晚」
var calib_cue_beat: float:
	get:
		return cue_beat + _calib_extra * rate / sec_per_beat

var _player: AudioStreamPlayer
var _stream_length: float = 0.0
var _loop_count: int = 0
var _last_raw_position: float = 0.0
var _output_latency: float = 0.0
var _start_usec: int = 0
var _anchor_position: float = 0.0
var _anchor_usec: int = 0
var _running: bool = false
## 只靠計時器、不對齊音樂播放位置。以前網頁版用瀏覽器直接播（sample 模式）時播放位置不準才這樣做；
## 現在網頁版改由 Godot 自己混音（stream 模式），播放位置可靠，所以和電腦版一樣對齊音樂
var _clock_only: bool = false


func _ready() -> void:
	process_priority = -100
	sec_per_beat = 60.0 / bpm
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_output_latency = AudioServer.get_output_latency()
	if ResourceLoader.exists(music_path):
		var stream := load(music_path) as AudioStream
		if stream:
			_enable_loop(stream)
			_builtin_stream = stream
			_player.stream = stream
			_stream_length = stream.get_length()


## from_beginning=false：沿用目前播放位置（過關進下一關／回選關時自訂音樂不要重頭）
func start(gameplay: bool = true, from_beginning: bool = true) -> void:
	_gameplay = gameplay
	_seek_guard_until = 0
	_configure_custom_loop()
	sec_per_beat = 60.0 / bpm
	_slow_mul = 1.0
	_slow_beats_left = 0.0
	duck_target = 0.0
	_duck = 0.0
	_player.volume_db = 0.0
	var keep := custom_music and not from_beginning and _player.stream != null \
		and _player.playing and _stream_length > 0.0
	if keep:
		var raw := _player.get_playback_position()
		_custom_epoch = 0.0
		## 對齊到目前聽到的位置，節拍時計不跳回 0
		var song_pos := raw
		if _custom_loop_end > _custom_loop_start and song_pos >= _custom_loop_end:
			song_pos = _custom_loop_start + fposmod(song_pos - _custom_loop_start, _custom_loop_end - _custom_loop_start)
		_loop_count = 0
		_last_raw_position = raw
		_start_usec = Time.get_ticks_usec()
		_anchor_position = song_pos - _output_latency * rate
		_anchor_usec = _start_usec
		_running = true
		current_beat = floori(song_beat) - 1
		## 位置接著播，倍率回到「正常／推薦」基準（避免上一關 2 倍速帶進下一關）
		set_rate(recommended_rate())
		return
	_custom_epoch = 0.0
	_loop_count = 0
	_last_raw_position = 0.0
	current_beat = -1
	_start_usec = Time.get_ticks_usec()
	_anchor_position = -_output_latency if _clock_only else 0.0
	_anchor_usec = _start_usec
	_running = true
	set_rate(recommended_rate())
	if _player.stream:
		_player.play(0.0)
		## 音樂真正開始出聲之前，節拍時計先停在起點等它（網頁版要等好幾十毫秒），
		## 不然一開始時計跑在音樂前面，第一面旗子的倒數聲會和音樂對不上
		_await_audio_until = _start_usec + AUDIO_START_TIMEOUT_USEC


func is_music_playing() -> bool:
	return _player != null and _player.playing


func set_rate(r: float) -> void:
	_base_rate = r
	_apply_rate()


## 讓世界速度接近 120 BPM 設計手感所需的播放倍率
func recommended_rate() -> float:
	if not prefer_reference_tempo or not custom_music:
		return 1.0
	return clampf(REFERENCE_BPM / maxf(bpm, 1.0), 0.5, 2.0)


## 目標「世界 BPM」（關卡設計速度）→ 實際 set_rate 值
func rate_for_world_bpm(world_bpm: float) -> float:
	var target := clampf(world_bpm, 40.0, 240.0)
	if prefer_reference_tempo and custom_music:
		return clampf(target / maxf(bpm, 1.0), 0.5, 2.0)
	return clampf(target / REFERENCE_BPM, 0.5, 2.0)


func set_prefer_reference_tempo(on: bool) -> void:
	prefer_reference_tempo = on
	if _running:
		set_rate(recommended_rate())


func apply_slow(factor: float, duration_beats: float) -> void:
	_slow_mul = clampf(factor, 0.35, 1.0)
	_slow_beats_left = maxf(_slow_beats_left, duration_beats)
	_apply_rate()


func _apply_rate() -> void:
	# 保持切速當下的歌曲位置連續，避免倍率改變時節拍突然跳動。
	if _running:
		var now := Time.get_ticks_usec()
		_anchor_position += float(now - _anchor_usec) / 1000000.0 * rate
		_anchor_usec = now
	rate = _base_rate * _slow_mul
	_player.pitch_scale = rate
	world_rate = bpm / REFERENCE_BPM * rate
	Engine.time_scale = world_rate if _gameplay else 1.0


func stop() -> void:
	_running = false
	_phys_valid = false
	paused = false
	_player.stop()


## 暫停／繼續：把目前位置記下來、音樂停住；繼續時從同一個位置接著走
func set_paused(on: bool) -> void:
	if on == paused or not _running:
		paused = on and _running
		return
	var now := Time.get_ticks_usec()
	if on:
		_anchor_position += float(now - _anchor_usec) / 1000000.0 * rate
	_anchor_usec = now
	paused = on
	_player.stream_paused = on
	if not on:
		_seek_guard_until = now + 150000


func _process(_delta: float) -> void:
	if not _running or paused:
		return
	var now := Time.get_ticks_usec()
	if _await_audio_until > 0:
		if not _clock_only and _player.playing and _player.get_playback_position() <= 0.0 and now < _await_audio_until:
			## 還沒出聲：時計停在原地
			_anchor_usec = now
			_phys_valid = false
			return
		_await_audio_until = 0
		_anchor_usec = now
		if not _clock_only and _player.playing:
			_anchor_position = _measured_position(now)
		_phys_valid = false
	var real_dt := float(now - _anchor_usec) / 1000000.0
	_duck = move_toward(_duck, duck_target, real_dt * 10.0)
	_player.volume_db = linear_to_db(1.0 - 0.8 * _duck)
	var predicted := _anchor_position + real_dt * rate
	if custom_music:
		# 在完整八拍（短曲用四拍）邊界接回第一拍，保留節拍連續性。
		var duration := _custom_loop_end - _custom_loop_start
		if duration > 0.0 and predicted - _custom_epoch >= _custom_loop_end:
			var skipped := maxi(1, floori((predicted - _custom_epoch - _custom_loop_start) / duration))
			_custom_epoch += skipped * duration
			_seek_guard_until = now + 150000
			var target := maxf(_custom_loop_start, predicted - _custom_epoch)
			if _player.playing:
				_player.seek(target)
			else:
				_player.play(target)
	if not _clock_only and now >= _seek_guard_until:
		var measured := _measured_position(now)
		## 漏偵測到一次循環（卡頓時播放位置一下跳回開頭）：節拍時計不能往回跳，
		## 否則等某一拍的東西（旗子 GO、重生）永遠等不到
		if not custom_music and _stream_length > 0.0 and measured < predicted - _stream_length * 0.5:
			_loop_count += 1
			measured += _stream_length
		var error := measured - predicted
		stat_err_ms = error * 1000.0
		stat_err_max = maxf(stat_err_max * 0.995, absf(stat_err_ms))
		if absf(error) > 0.08:
			predicted = measured
			stat_snaps += 1
		else:
			predicted += error * 0.1
	_anchor_position = predicted
	_anchor_usec = now
	_emit_beats()


func _measured_position(now_usec: int) -> float:
	if _player.stream == null or not _player.playing or _stream_length <= 0.0:
		return float(now_usec - _start_usec) / 1000000.0
	var raw := _player.get_playback_position() + AudioServer.get_time_since_last_mix() * rate
	if raw + 1.0 < _last_raw_position:
		_loop_count += 1
	_last_raw_position = raw
	if custom_music:
		return _custom_epoch + raw - _output_latency * rate
	return _loop_count * _stream_length + raw - _output_latency * rate


func _emit_beats() -> void:
	var beat_now := floori(song_beat)
	while current_beat < beat_now:
		current_beat += 1
		if current_beat < 0:
			continue
		if _slow_beats_left > 0.0:
			_slow_beats_left = maxf(0.0, _slow_beats_left - 1.0)
			if _slow_beats_left <= 0.0:
				_slow_mul = 1.0
				_apply_rate()
		beat.emit(current_beat)
		if current_beat % beats_per_measure == 0:
			var m := floori(float(current_beat) / beats_per_measure)
			measure.emit(m)
			if m % measures_per_section == 0:
				section_changed.emit(floori(float(m) / measures_per_section))


func set_music(stream: AudioStream, source_bpm: float, offset: float, name: String) -> void:
	stop()
	custom_music = true
	bpm = clampf(source_bpm, 40.0, 240.0)
	sec_per_beat = 60.0 / bpm
	first_beat_offset = clampf(offset, 0.0, maxf(stream.get_length() - 4.0 * sec_per_beat, 0.0))
	track_name = name
	_player.stream = stream
	_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	_stream_length = stream.get_length()
	_configure_custom_loop()


func restore_builtin_music() -> void:
	stop()
	custom_music = false
	bpm = REFERENCE_BPM
	sec_per_beat = 60.0 / bpm
	first_beat_offset = 0.0
	track_name = "內建音樂"
	rhythm_sections = []
	_player.stream = _builtin_stream
	_stream_length = _builtin_stream.get_length() if _builtin_stream else 0.0


## 依歌曲時間回傳目前節奏段落（沒有自訂分析時回空 Dictionary）
func rhythm_section_at(song_time: float = -1.0) -> Dictionary:
	if rhythm_sections.is_empty():
		return {}
	var t := song_position + first_beat_offset if song_time < 0.0 else song_time
	for s in rhythm_sections:
		var d: Dictionary = s
		if t >= float(d.get("start", 0.0)) and t < float(d.get("end", 0.0)):
			return d
	return rhythm_sections[rhythm_sections.size() - 1]


func _configure_custom_loop() -> void:
	if not custom_music:
		return
	_custom_loop_start = first_beat_offset
	var available := maxf(_stream_length - _custom_loop_start, sec_per_beat)
	var cycle := 8.0 if available >= sec_per_beat * 8.0 else 4.0
	var beats := maxf(1.0, floorf(available / (sec_per_beat * cycle)) * cycle)
	_custom_loop_end = minf(_stream_length, _custom_loop_start + beats * sec_per_beat)


func _enable_loop(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(round(wav.get_length() * wav.mix_rate))
	elif "loop" in stream:
		stream.set("loop", true)


## 目前拍子內的進度（0 = 剛好在拍點上，接近 1 = 快到下一拍）
func beat_fraction() -> float:
	var b := song_beat
	return b - floorf(b)


## 在拍點上為 1，之後快速衰減到 0，適合做閃爍、縮放等視覺脈衝
func pulse(sharpness: float = 8.0) -> float:
	return exp(-beat_fraction() * sharpness)


func section_index() -> int:
	return floori(song_beat / float(beats_per_measure * measures_per_section))
