extends Node
## 使用者音樂留在本機／瀏覽器；分析草稿與已套用音樂分開，取消不改變現有歌曲。

signal progress(value: float, message: String)
signal analyzed(result: Dictionary)
signal failed(message: String)
signal active_changed

const MAX_BYTES := 32 * 1024 * 1024
const AUDIO_PATH := "user://custom_music.audio"
const SETTINGS_PATH := "user://custom_music.cfg"

var draft_stream: AudioStream
var draft_bytes := PackedByteArray()
var draft_name: String = ""
var draft_hash: String = ""
var draft_result: Dictionary = {}
var busy: bool = false
var _token: int = 0


func _ready() -> void:
	var settings := ConfigFile.new()
	if settings.load(SETTINGS_PATH) != OK or not bool(settings.get_value("active", "enabled", false)):
		return
	var name := String(settings.get_value("active", "name", ""))
	var bytes := FileAccess.get_file_as_bytes(AUDIO_PATH)
	if bytes.is_empty() or bytes.size() > MAX_BYTES or _fingerprint(bytes) != String(settings.get_value("active", "hash", "")):
		return
	var stream := decode(bytes, name)
	if stream:
		Conductor.set_music(stream, float(settings.get_value("active", "bpm", 120)),
			float(settings.get_value("active", "offset", 0)), name)


func import_path(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		failed.emit("讀不到這個音樂檔")
		return
	if file.get_length() > MAX_BYTES:
		failed.emit("音樂檔太大，請選擇 32 MB 以內的檔案")
		return
	var bytes := file.get_buffer(file.get_length())
	file.close()
	await import_bytes(bytes, path.get_file())


func import_bytes(bytes: PackedByteArray, name: String) -> void:
	cancel_analysis()
	var token := _token
	if bytes.is_empty() or bytes.size() > MAX_BYTES:
		failed.emit("請選擇 32 MB 以內的 WAV、MP3 或 OGG 音樂")
		return
	var stream := decode(bytes, name)
	if stream == null:
		failed.emit("無法讀取音訊，請使用 WAV、MP3 或 OGG Vorbis")
		return
	if stream.get_length() < 8.0:
		failed.emit("請選擇至少 8 秒的歌曲，節拍分析會比較穩定")
		return
	draft_stream = stream
	draft_bytes = bytes
	draft_name = name.get_file()
	draft_hash = _fingerprint(bytes)
	draft_result = {}
	busy = true
	var result := await BpmAnalyzer.analyze(stream, get_tree(),
		func(value: float, message: String) -> void: progress.emit(value, message),
		func() -> bool: return token != _token)
	if token != _token:
		return
	busy = false
	if result.has("cancelled"):
		return
	# 辨識失敗仍可試聽、手動輸入 BPM，不會讓不規則歌曲完全無法使用。
	if result.has("error"):
		result = {"bpm": 120.0, "offset": 0.0, "confidence": 0.0, "notice": result["error"], "candidates": []}
	var settings := ConfigFile.new()
	if settings.load(SETTINGS_PATH) == OK and settings.has_section(draft_hash):
		result["bpm"] = float(settings.get_value(draft_hash, "bpm", result["bpm"]))
		result["offset"] = float(settings.get_value(draft_hash, "offset", result["offset"]))
		result["notice"] = "已讀取這首歌上次保存的校正"
	draft_result = result
	analyzed.emit(result)


func cancel_analysis() -> void:
	_token += 1
	busy = false


func load_active_draft() -> void:
	if Conductor.custom_music and FileAccess.file_exists(AUDIO_PATH):
		await import_bytes(FileAccess.get_file_as_bytes(AUDIO_PATH), Conductor.track_name)


func apply_draft(bpm: float, offset: float) -> bool:
	if busy or draft_stream == null:
		return false
	bpm = clampf(bpm, 40.0, 240.0)
	offset = clampf(offset, 0.0, maxf(0.0, draft_stream.get_length() - 0.1))
	if draft_stream.get_length() - offset < 4.0 * 60.0 / bpm:
		failed.emit("第 1 拍後至少要保留一小節，請將第 1 拍位置往前調整")
		return false
	var file := FileAccess.open(AUDIO_PATH + ".tmp", FileAccess.WRITE)
	if file == null:
		failed.emit("無法保存音樂，請檢查儲存空間")
		return false
	file.store_buffer(draft_bytes)
	file.close()
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
	var active := {"enabled": true, "name": draft_name, "hash": draft_hash, "bpm": bpm, "offset": offset}
	for key in active:
		settings.set_value("active", key, active[key])
	settings.set_value(draft_hash, "bpm", bpm)
	settings.set_value(draft_hash, "offset", offset)
	if settings.save(SETTINGS_PATH + ".tmp") != OK:
		failed.emit("無法保存歌曲校正")
		return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(AUDIO_PATH + ".tmp"), ProjectSettings.globalize_path(AUDIO_PATH)) != OK \
		or DirAccess.rename_absolute(ProjectSettings.globalize_path(SETTINGS_PATH + ".tmp"), ProjectSettings.globalize_path(SETTINGS_PATH)) != OK:
		failed.emit("無法完成保存，請重新選擇音樂")
		return false
	Conductor.set_music(draft_stream, bpm, offset, draft_name)
	active_changed.emit()
	return true


func restore_builtin() -> void:
	cancel_analysis()
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
	settings.set_value("active", "enabled", false)
	settings.save(SETTINGS_PATH)
	Conductor.restore_builtin_music()
	active_changed.emit()


static func decode(bytes: PackedByteArray, name: String) -> AudioStream:
	if bytes.size() < 12:
		return null
	var extension := name.get_extension().to_lower()
	var magic := bytes.slice(0, 4).get_string_from_ascii()
	var stream: AudioStream
	if extension == "wav" and magic == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WAVE":
		stream = AudioStreamWAV.load_from_buffer(bytes)
	elif extension == "mp3" and (bytes.slice(0, 3).get_string_from_ascii() == "ID3" or (bytes[0] == 255 and (bytes[1] & 224) == 224)):
		stream = AudioStreamMP3.load_from_buffer(bytes)
	elif extension == "ogg" and magic == "OggS":
		stream = AudioStreamOggVorbis.load_from_buffer(bytes)
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
	elif stream:
		stream.set("loop", false)
	return stream


static func _fingerprint(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
