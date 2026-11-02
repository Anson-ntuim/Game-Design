extends Node
## 節拍指揮家：以音訊播放位置為準，提供整首歌共用的節拍時鐘。
## 關卡中所有跟著節奏動的東西都讀 song_beat，確保畫面與音樂同步。

signal beat(beat_index: int)
signal measure(measure_index: int)
signal section_changed(section_index: int)

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
var _base_rate: float = 1.0
var _slow_mul: float = 1.0
var _slow_beats_left: float = 0.0
## 0~1：配樂壓低音量的程度（休止區的休止拍）
var duck_target: float = 0.0
var _duck: float = 0.0
## 玩家校正的音訊延遲（秒）：耳機／網頁／藍牙常讓聲音比時鐘晚；正值＝聲音晚到，時鐘會往後挪去對齊
var user_offset: float = 0.0

var song_position: float:
	get:
		if not _running:
			return 0.0
		return _anchor_position + float(Time.get_ticks_usec() - _anchor_usec) / 1000000.0 * rate \
			- first_beat_offset - user_offset

## 目前聽到的速度
var current_bpm: float:
	get:
		return bpm * rate

var song_beat: float:
	get:
		return song_position / sec_per_beat

var _player: AudioStreamPlayer
var _stream_length: float = 0.0
var _loop_count: int = 0
var _last_raw_position: float = 0.0
var _output_latency: float = 0.0
var _start_usec: int = 0
var _anchor_position: float = 0.0
var _anchor_usec: int = 0
var _running: bool = false
## 網頁版回報的播放位置開頭會卡在 0 約一秒，之後一直比實際聲音晚；但 play() 當下就出聲，所以只靠計時器
var _clock_only: bool = OS.has_feature("web")


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
			_player.stream = stream
			_stream_length = stream.get_length()


func start() -> void:
	sec_per_beat = 60.0 / bpm
	_loop_count = 0
	_last_raw_position = 0.0
	current_beat = -1
	_start_usec = Time.get_ticks_usec()
	_anchor_position = -_output_latency if _clock_only else 0.0
	_anchor_usec = _start_usec
	_running = true
	_slow_mul = 1.0
	_slow_beats_left = 0.0
	set_rate(1.0)
	duck_target = 0.0
	_duck = 0.0
	_player.volume_db = 0.0
	if _player.stream:
		_player.play(0.0)


func set_rate(r: float) -> void:
	_base_rate = r
	_apply_rate()


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
	Engine.time_scale = rate


func stop() -> void:
	_running = false
	_player.stop()


func _process(_delta: float) -> void:
	if not _running:
		return
	var now := Time.get_ticks_usec()
	var real_dt := float(now - _anchor_usec) / 1000000.0
	_duck = move_toward(_duck, duck_target, real_dt * 10.0)
	_player.volume_db = linear_to_db(1.0 - 0.8 * _duck)
	var predicted := _anchor_position + real_dt * rate
	if not _clock_only:
		var measured := _measured_position(now)
		var error := measured - predicted
		if absf(error) > 0.08:
			predicted = measured
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
