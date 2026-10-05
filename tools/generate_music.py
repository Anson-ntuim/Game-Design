"""產生遊戲用的 120 BPM 循環配樂（16 小節、4 個段落，每段 4 小節）。

用法：python3 tools/generate_music.py
輸出：assets/music/beat_loop.wav

段落與 Conductor.measures_per_section = 4 對齊，畫面配色會在每段開頭切換。
大鼓每一拍都有，作為玩家跟拍的主要依據。
"""

import math
import random
import struct
import wave
from pathlib import Path

SR = 22050
BPM = 120
BEAT = 60.0 / BPM
MEASURES = 16
LENGTH = int(round(SR * BEAT * 4 * MEASURES))

random.seed(7)
buf = [0.0] * LENGTH


def midi(n):
    return 440.0 * 2.0 ** ((n - 69) / 12.0)


def add(start, dur, fn):
    s0 = int(round(start * SR))
    n = int(dur * SR)
    for i in range(n):
        j = (s0 + i) % LENGTH
        buf[j] += fn(i / SR)


def kick(t):
    phase = 2 * math.pi * (45 * t + (110 / 30.0) * (1 - math.exp(-30 * t)))
    return math.sin(phase) * math.exp(-t * 8) * 0.9


def snare(t):
    noise = random.uniform(-1, 1) * math.exp(-t * 20) * 0.32
    tone = math.sin(2 * math.pi * 185 * t) * math.exp(-t * 28) * 0.28
    return noise + tone


def hat(t):
    return random.uniform(-1, 1) * math.exp(-t * 90) * 0.10


def crash(t):
    return random.uniform(-1, 1) * math.exp(-t * 3.5) * 0.12


def make_bass(freq):
    def fn(t):
        env = min(1.0, t * 200) * math.exp(-t * 5)
        s = sum(math.sin(2 * math.pi * k * freq * t) / k for k in range(1, 5))
        return s * env * 0.22
    return fn


def make_lead(freq, decay=6.0, amp=0.16):
    def fn(t):
        env = min(1.0, t * 300) * math.exp(-t * decay)
        x = 2 * math.pi * freq * t
        return (math.sin(x) + math.sin(3 * x) / 3 + math.sin(5 * x) / 8) * env * amp
    return fn


def make_pad(freqs):
    def fn(t):
        env = min(1.0, t * 2.5) * min(1.0, (BEAT * 4 - t) * 4)
        return sum(math.sin(2 * math.pi * f * t) + 0.3 * math.sin(4 * math.pi * f * t) for f in freqs) * env * 0.035
    return fn


# Am - F - C - G
ROOTS = [45, 41, 48, 43]
PADS = [[57, 60, 64], [53, 57, 60], [55, 60, 64], [55, 59, 62]]
MELODY = [
    [76, None, 74, 72, None, 69, 72, 74],
    [72, None, 69, None, 65, 69, 72, None],
    [67, 72, 76, None, 74, 72, 67, None],
    [74, None, 71, 67, None, 71, 74, 79],
]
ARP = [[69, 72, 76, 81], [65, 69, 72, 77], [67, 72, 76, 79], [67, 71, 74, 79]]

for m in range(MEASURES):
    section = m // 4
    chord = m % 4
    t0 = m * BEAT * 4
    root = ROOTS[chord]

    if m % 4 == 0:
        add(t0, 1.5, crash)

    for b in range(4):
        tb = t0 + b * BEAT
        add(tb, 0.35, kick)
        if section >= 1 and b in (1, 3):
            add(tb, 0.25, snare)
        if section == 3 and b == 3:
            add(tb + BEAT * 0.5, 0.2, snare)

    hat_steps = 16 if section == 2 else 8
    for s in range(hat_steps):
        if hat_steps == 8 and s % 2 == 0 and section == 0:
            continue
        add(t0 + s * (BEAT * 4 / hat_steps), 0.06, hat)

    for s in range(8):
        note = root + (12 if section == 3 and s % 2 == 1 else 0)
        add(t0 + s * BEAT * 0.5, BEAT * 0.5, make_bass(midi(note)))

    if section in (1, 3):
        for s, n in enumerate(MELODY[chord]):
            if n is not None:
                shift = 12 if section == 3 else 0
                add(t0 + s * BEAT * 0.5, BEAT * 0.9, make_lead(midi(n + shift)))

    if section >= 2:
        add(t0, BEAT * 4, make_pad([midi(n) for n in PADS[chord]]))

    if section == 2:
        for s in range(16):
            n = ARP[chord][s % 4] + (12 if s >= 8 else 0)
            add(t0 + s * BEAT * 0.25, BEAT * 0.4, make_lead(midi(n), decay=14.0, amp=0.09))

peak = max(abs(x) for x in buf) or 1.0
out = Path(__file__).resolve().parent.parent / "assets" / "music" / "beat_loop.wav"
out.parent.mkdir(parents=True, exist_ok=True)
with wave.open(str(out), "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    frames = bytearray()
    for x in buf:
        v = math.tanh(x / peak * 1.4) * 0.88
        frames += struct.pack("<h", int(v * 32767))
    w.writeframes(bytes(frames))

print(f"wrote {out} ({LENGTH / SR:.1f}s)")
