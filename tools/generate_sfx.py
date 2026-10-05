"""產生玩家動作與譜面橋用的音效（與配樂同為 A 小調）。

用法：python3 tools/generate_sfx.py
輸出：assets/sfx/*.wav

pluck 以 A4 為基準音，遊戲中用 pitch_scale 移到當下和弦的琶音音高，
所以玩家連續對拍跳躍時會彈出跟和弦合拍的上行旋律。
"""

import math
import random
import struct
import wave
from pathlib import Path

SR = 22050
OUT = Path(__file__).resolve().parent.parent / "assets" / "sfx"
random.seed(11)


def midi(n):
    return 440.0 * 2.0 ** ((n - 69) / 12.0)


def render(dur, fn):
    return [fn(i / SR) for i in range(int(dur * SR))]


def mix(*tracks):
    n = max(len(t) for t in tracks)
    return [sum(t[i] for t in tracks if i < len(t)) for i in range(n)]


def delay(track, seconds):
    return [0.0] * int(seconds * SR) + track


def pluck_fn(freq, decay=7.0):
    def fn(t):
        env = min(1.0, t * 400) * math.exp(-t * decay)
        x = 2 * math.pi * freq * t
        tone = math.sin(x) + 0.5 * math.sin(2 * x) * math.exp(-t * 12) + 0.25 * math.sin(3 * x) * math.exp(-t * 18)
        return tone * env
    return fn


def pluck(t):
    return pluck_fn(midi(69))(t)


def clap(t):
    noise = random.uniform(-1, 1)
    bursts = sum(math.exp(-max(0.0, t - k * 0.012) * 60) * (t >= k * 0.012) for k in range(3))
    body = math.sin(2 * math.pi * (220 - 80 * t) * t) * math.exp(-t * 25) * 0.5
    return noise * bursts * 0.35 * math.exp(-t * 14) + body


def block(t):
    a = math.sin(2 * math.pi * 1250 * t) * math.exp(-t * 55)
    b = math.sin(2 * math.pi * 1870 * t) * math.exp(-t * 70) * 0.5
    click = random.uniform(-1, 1) * math.exp(-t * 400) * 0.4
    return a + b + click


def miss(t):
    thud = (math.sin(2 * math.pi * 98 * t) + math.sin(2 * math.pi * 104 * t)) * math.exp(-t * 9)
    buzz = math.sin(2 * math.pi * 147 * t + 3 * math.sin(2 * math.pi * 31 * t)) * math.exp(-t * 12) * 0.4
    return (thud + buzz) * min(1.0, t * 300)


def cue(t):
    f = midi(88)
    partials = [(1.0, 1.0), (2.76, 0.5), (5.4, 0.25)]
    return sum(math.sin(2 * math.pi * f * r * t) * a * math.exp(-t * (4 + r * 2)) for r, a in partials) * min(1.0, t * 500)


def chart_ok():
    notes = [72, 76, 79, 84]
    return mix(*[delay(render(0.7, pluck_fn(midi(n), 5.0)), i * 0.07) for i, n in enumerate(notes)])


def chart_fail(t):
    f = 520 * math.exp(-t * 4) + 70
    saw = sum(math.sin(2 * math.pi * f * k * t) / k for k in range(1, 6))
    crackle = random.uniform(-1, 1) * math.exp(-t * 6) * 0.5
    return (saw * 0.6 + crackle) * math.exp(-t * 3.5) * min(1.0, t * 200)


def write(name, samples):
    peak = max(abs(x) for x in samples) or 1.0
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{name}.wav"
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(x / peak * 0.8 * 32767)) for x in samples))
    print(f"wrote {path} ({len(samples) / SR:.2f}s)")


write("pluck", render(0.5, pluck))
write("clap", render(0.3, clap))
write("block", render(0.15, block))
write("miss", render(0.35, miss))
write("cue", render(0.6, cue))
write("chart_ok", chart_ok())
write("chart_fail", render(0.6, chart_fail))


def slam(t):
    f = 55 + 140 * math.exp(-t * 30)
    kick = math.sin(2 * math.pi * f * t) * math.exp(-t * 7)
    metal = (math.sin(2 * math.pi * 410 * t) + 0.6 * math.sin(2 * math.pi * 667 * t)) * math.exp(-t * 18) * 0.35
    grit = random.uniform(-1, 1) * math.exp(-t * 25) * 0.5
    return (kick + metal + grit) * min(1.0, t * 800)


def zap(t):
    f = 2400 * math.exp(-t * 14) + 300
    phase = 2 * math.pi * (2400 / 14 * (1 - math.exp(-t * 14)) + 300 * t)
    buzz = math.sin(phase) + 0.4 * math.sin(2 * phase + math.sin(2 * math.pi * 60 * t))
    return buzz * math.exp(-t * 9) * min(1.0, t * 1000) * (0.8 + 0.2 * math.sin(2 * math.pi * f * 0.01 * t))


def rumble(t):
    swell = min(1.0, t * 3.0) * math.exp(-max(0.0, t - 0.6) * 4)
    low = math.sin(2 * math.pi * 49 * t) + 0.6 * math.sin(2 * math.pi * 73.5 * t + math.sin(2 * math.pi * 3 * t))
    noise = random.uniform(-1, 1) * 0.35
    return (low + noise) * swell


write("slam", render(0.5, slam))
write("zap", render(0.35, zap))
write("rumble", render(1.2, rumble))


def hold(t):
    """「長」的延音：和 pluck 同樣以 A4 為基準，按住跳躍時接在 pluck 後面拉長聲音"""
    f = midi(69)
    vib = 0.004 * math.sin(2 * math.pi * 5.5 * t) * min(1.0, t * 4)
    x = 2 * math.pi * f * t * (1 + vib)
    tone = math.sin(x) + 0.3 * math.sin(2 * x) + 0.12 * math.sin(3 * x)
    env = min(1.0, t * 30) * math.exp(-t * 3.2)
    return tone * env


write("hold", render(0.6, hold))


def hush(t):
    """休止開始：收住的 hi-hat 加一聲悶響，像樂手把聲音按掉"""
    choke = random.uniform(-1, 1) * math.exp(-t * 28) * 0.55
    thump = math.sin(2 * math.pi * (95 - 40 * t) * t) * math.exp(-t * 22) * 0.7
    return (choke + thump) * min(1.0, t * 600)


write("hush", render(0.25, hush))


