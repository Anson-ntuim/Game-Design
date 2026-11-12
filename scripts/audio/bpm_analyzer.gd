class_name BpmAnalyzer
extends RefCounted
## 離線解碼 → 低頻／全頻能量起音 → 自相關與倍頻評分 → 拍點相位。
## 整首歌分段偵測密度／動能，標出疏、穩、密、爆等多種節奏段落，不只單一 BPM。
## 每批讓回主迴圈，網頁單執行緒也能顯示進度、取消分析。

const ENVELOPE_HZ := 100.0
## 最長分析長度（秒）；夠涵蓋一般流行歌整首
const ANALYSIS_SECONDS := 480.0
## 每個節奏段落約幾個小節（4/4）
const SECTION_MEASURES := 4


static func analyze(stream: AudioStream, tree: SceneTree, progress: Callable, cancelled: Callable) -> Dictionary:
	var playback := stream.instantiate_playback()
	if playback == null:
		return {"error": "無法解碼這首音樂"}
	var mix_rate := AudioServer.get_mix_rate()
	var hop := maxi(1, roundi(mix_rate / ENVELOPE_HZ))
	var song_len := stream.get_length()
	var analyze_len := minf(song_len, ANALYSIS_SECONDS)
	var count := int(analyze_len * mix_rate / hop)
	var envelope := PackedFloat32Array()
	envelope.resize(count)
	var previous_low := 0.0
	var previous_full := 0.0
	var low := 0.0
	var maximum_energy := 0.0
	playback.start(0.0)
	for i in count:
		if i % 64 == 0:
			if cancelled.call():
				playback.stop()
				return {"cancelled": true}
			progress.call(0.7 * i / maxf(count, 1), "分析整首歌起音…")
			await tree.process_frame
		var frames := playback.mix_audio(1.0, hop)
		if frames.is_empty():
			envelope.resize(i)
			break
		var full_energy := 0.0
		var low_energy := 0.0
		for j in range(0, frames.size(), 4):
			var sample := (frames[j].x + frames[j].y) * 0.5
			low += 0.12 * (sample - low)
			full_energy += frames[j].length_squared()
			low_energy += low * low
		maximum_energy = maxf(maximum_energy, full_energy)
		var full_log := log(0.000001 + full_energy)
		var low_log := log(0.000001 + low_energy)
		envelope[i] = maxf(low_log - previous_low, 0.0) + 0.35 * maxf(full_log - previous_full, 0.0)
		previous_full = full_log
		previous_low = low_log
	playback.stop()
	if maximum_energy < 0.00001 or envelope.size() < 400:
		return {"error": "音樂太短或接近靜音，請選擇至少 8 秒、有清楚節拍的歌曲"}
	progress.call(0.72, "比對節奏與第一拍…")
	await tree.process_frame
	if cancelled.call():
		return {"cancelled": true}
	var result := detect(envelope, float(mix_rate) / hop)
	progress.call(0.9, "拆解整首歌節奏段落…")
	await tree.process_frame
	if cancelled.call():
		return {"cancelled": true}
	result["sections"] = _section_map(envelope, float(mix_rate) / hop, float(result["bpm"]), float(result["offset"]))
	result["song_length"] = song_len
	result["analyzed_length"] = analyze_len
	progress.call(1.0, "分析完成")
	return result


static func detect(input: PackedFloat32Array, hz: float = ENVELOPE_HZ) -> Dictionary:
	if input.size() < hz * 4:
		return {"error": "可分析的音樂太短"}
	var envelope := input.duplicate()
	var maximum := 0.0
	for value in envelope:
		maximum = maxf(maximum, value)
	if maximum <= 0.000001:
		return {"error": "找不到明顯節拍，可改用手動 BPM 與對拍校正"}
	var energy := 0.0
	var peaks: Array[int] = []
	for i in envelope.size():
		envelope[i] = maxf(0.0, envelope[i] / maximum - 0.06)
		energy += envelope[i] * envelope[i]
		if envelope[i] > 0.0:
			peaks.append(i)
	var correlations := PackedFloat32Array()
	var max_lag := ceili(hz * 60.0 / 50.0 * 3.0) + 2
	correlations.resize(max_lag + 1)
	for lag in range(1, max_lag + 1):
		var score := 0.0
		for i in peaks:
			if i + lag < envelope.size():
				score += envelope[i] * envelope[i + lag]
		correlations[lag] = score / maxf(energy, 0.000001)
	var scores: Array[Dictionary] = []
	for step in range(500, 2201):
		var bpm := step / 10.0
		var period := hz * 60.0 / bpm
		var raw := _correlation(correlations, period) + 0.5 * _correlation(correlations, period * 2.0) \
			+ 0.25 * _correlation(correlations, period * 3.0)
		# 只有近似同分時偏向常見拍速；保留半速／倍速候選供玩家校正。
		var preference := 1.0 - 0.035 * absf(log(bpm / 120.0))
		scores.append({"bpm": bpm, "score": raw * preference, "raw": raw})
	scores.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
	# 長時間拍點一致性可排除自相關的半速峰，亦修正非整數 BPM。
	var seeds: Array[float] = []
	for item: Dictionary in scores:
		var candidate := float(item["bpm"])
		var separate := true
		for seed in seeds:
			if absf(seed - candidate) < 5.0:
				separate = false
		if separate:
			seeds.append(candidate)
		if seeds.size() == 8:
			break
	var best: Dictionary = scores[0]
	var best_score := -1.0
	for seed in seeds:
		for delta in range(-10, 11):
			var candidate := seed + delta * 0.1
			var candidate_period := hz * 60.0 / candidate
			var coherence := 0.0
			for phase_index in range(0, ceili(candidate_period), 2):
				var aligned := 0.0
				for i in peaks:
					var distance := fposmod(i - float(phase_index) + candidate_period * 0.5, candidate_period) - candidate_period * 0.5
					if absf(distance) < 3.0:
						aligned += envelope[i] * envelope[i] * exp(-distance * distance / 3.0)
				coherence = maxf(coherence, aligned / maxf(energy, 0.000001))
			var raw := _correlation(correlations, candidate_period) + 0.5 * _correlation(correlations, candidate_period * 2) + 0.25 * _correlation(correlations, candidate_period * 3)
			var score := raw * (0.4 + 0.6 * coherence)
			if score > best_score:
				best_score = score
				best = {"bpm": candidate, "raw": raw}
	var bpm := snappedf(float(best["bpm"]), 0.1)
	var period := hz * 60.0 / bpm
	var phase := 0.0
	var phase_score := -1.0
	for offset in ceili(period):
		var score := 0.0
		for i in peaks:
			var distance := fposmod(i - float(offset) + period * 0.5, period) - period * 0.5
			if absf(distance) < 3.0:
				score += envelope[i] * exp(-distance * distance / 2.0)
		if score > phase_score:
			phase_score = score
			phase = float(offset)
	# 以整段拍點做加權直線擬合，避免 0.1 BPM 的量化誤差累積成漂拍。
	var weight := 0.0
	var sum_k := 0.0
	var sum_i := 0.0
	var sum_kk := 0.0
	var sum_ki := 0.0
	for i in peaks:
		var k := roundf((i - phase) / period)
		if absf(i - phase - k * period) > 2.5 or envelope[i] < 0.18:
			continue
		var w := float(envelope[i] * envelope[i])
		weight += w
		sum_k += w * k
		sum_i += w * i
		sum_kk += w * k * k
		sum_ki += w * k * i
	var denominator := weight * sum_kk - sum_k * sum_k
	if denominator > 0.001:
		var fitted := (weight * sum_ki - sum_k * sum_i) / denominator
		if absf(fitted / period - 1.0) < 0.01:
			period = fitted
			phase = fposmod((sum_i - period * sum_k) / weight, period)
			bpm = snappedf(hz * 60.0 / period, 0.1)
	var first := phase / hz
	for i in peaks:
		var distance := absf(fposmod(i - phase + period * 0.5, period) - period * 0.5)
		if envelope[i] >= 0.18 and distance < 2.0:
			first = i / hz
			break
	var candidates: Array[float] = []
	for item: Dictionary in scores:
		var candidate := float(item["bpm"])
		var separate := true
		for existing in candidates:
			if absf(existing - candidate) < 5.0:
				separate = false
		if separate:
			candidates.append(snappedf(candidate, 0.1))
		if candidates.size() == 4:
			break
	return {"bpm": bpm, "offset": first, "confidence": clampf(float(best["raw"]) / 1.5, 0.0, 1.0),
		"candidates": candidates, "envelope": envelope, "envelope_hz": hz}


## 依主 BPM 把整首歌切成多段，標出疏／穩／密／爆與半拍感，方便對拍理解曲式。
static func _section_map(envelope: PackedFloat32Array, hz: float, bpm: float, offset_sec: float) -> Array:
	var sections: Array = []
	if envelope.is_empty() or bpm < 40.0:
		return sections
	var sec_per_beat := 60.0 / bpm
	var window_beats := float(SECTION_MEASURES * 4)
	var window := maxi(1, roundi(hz * sec_per_beat * window_beats))
	var offset_i := clampi(roundi(offset_sec * hz), 0, maxi(0, envelope.size() - 1))
	var idx := offset_i
	var index := 0
	while idx < envelope.size():
		var end := mini(idx + window, envelope.size())
		var sum := 0.0
		var peak_n := 0
		var downbeat := 0.0
		var offbeat := 0.0
		var samples := maxi(1, end - idx)
		for i in range(idx, end):
			var v := float(envelope[i])
			sum += v
			if v > 0.18:
				peak_n += 1
			var beat_pos := fposmod((i - offset_i) / (hz * sec_per_beat), 1.0)
			if beat_pos < 0.2 or beat_pos > 0.8:
				downbeat += v
			elif beat_pos > 0.35 and beat_pos < 0.65:
				offbeat += v
		var beats := float(samples) / maxf(hz * sec_per_beat, 0.001)
		var density := float(peak_n) / maxf(beats, 0.001)
		var energy := sum / float(samples)
		var sync := offbeat / maxf(downbeat + offbeat, 0.0001)
		var feel := "穩"
		if density < 0.55 and energy < 0.08:
			feel = "疏"
		elif density >= 2.2 or energy >= 0.22:
			feel = "爆"
		elif density >= 1.25 or energy >= 0.14:
			feel = "密"
		elif sync > 0.55:
			feel = "切分"
		elif downbeat > offbeat * 2.2 and density < 0.9:
			feel = "半拍感"
		var start_sec := idx / hz
		var end_sec := end / hz
		sections.append({
			"index": index,
			"start": snappedf(start_sec, 0.01),
			"end": snappedf(end_sec, 0.01),
			"start_beat": snappedf((start_sec - offset_sec) / sec_per_beat, 0.1),
			"end_beat": snappedf((end_sec - offset_sec) / sec_per_beat, 0.1),
			"density": snappedf(density, 0.01),
			"energy": snappedf(energy, 0.001),
			"syncopation": snappedf(sync, 0.01),
			"feel": feel,
		})
		index += 1
		idx = end
		if index > 64:
			break
	## 合併相鄰同 feel，避免 UI 過碎
	return _merge_sections(sections)


static func _merge_sections(raw: Array) -> Array:
	if raw.is_empty():
		return raw
	var out: Array = []
	var cur: Dictionary = (raw[0] as Dictionary).duplicate()
	for i in range(1, raw.size()):
		var nxt: Dictionary = raw[i]
		if String(nxt["feel"]) == String(cur["feel"]):
			cur["end"] = nxt["end"]
			cur["end_beat"] = nxt["end_beat"]
			cur["density"] = snappedf((float(cur["density"]) + float(nxt["density"])) * 0.5, 0.01)
			cur["energy"] = snappedf((float(cur["energy"]) + float(nxt["energy"])) * 0.5, 0.001)
			cur["syncopation"] = snappedf((float(cur["syncopation"]) + float(nxt["syncopation"])) * 0.5, 0.01)
		else:
			out.append(cur)
			cur = nxt.duplicate()
	out.append(cur)
	for i in out.size():
		out[i]["index"] = i
	return out


static func _correlation(values: PackedFloat32Array, lag: float) -> float:
	var index := floori(lag)
	if index < 1 or index + 1 >= values.size():
		return 0.0
	var a := 0.25 * values[index - 1] + 0.5 * values[index] + 0.25 * values[index + 1]
	var b := 0.25 * values[index] + 0.5 * values[index + 1] + 0.25 * values[mini(index + 2, values.size() - 1)]
	return lerpf(a, b, lag - index)


static func format_sections(sections: Array) -> String:
	if sections.is_empty():
		return "尚未切出節奏段落"
	var parts: PackedStringArray = []
	for s in sections:
		var d: Dictionary = s
		var a := int(float(d["start"]))
		var b := maxi(a, int(ceilf(float(d["end"]))) - 1)
		parts.append("%d:%02d–%d:%02d %s" % [a / 60, a % 60, b / 60, b % 60, String(d["feel"])])
	return "整首歌節奏：" + " ｜ ".join(parts)
