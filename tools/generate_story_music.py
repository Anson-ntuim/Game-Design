"""依《故事規劃》產生 10 首關卡配樂，每首對應一段感情時期。

用法：
    python3 tools/generate_story_music.py            # 產生全部
    python3 tools/generate_story_music.py 4 9        # 只產生第 4、9 關
輸出：assets/music/story/levelXX_<名稱>.wav（22050 Hz、單聲道、16-bit）

所有曲子共用遊戲的節奏規格，可以直接塞進 Conductor：
- 120 BPM，16 小節剛好 32.0 秒，第一拍在 0 秒（first_beat_offset = 0）。
- 4 小節一段、共 4 段，對齊 Conductor.measures_per_section = 4：
  第 1 段前奏 → 第 2 段主旋律 → 第 3 段堆疊／間奏 → 第 4 段高潮變奏。
- 每一拍都有大鼓，作為玩家跟拍的主要依據（情緒再低落也不拿掉）。
- 音尾與殘響都繞回開頭，循環播放沒有接縫。
- 第 4 關的 12/8 拍以「附點四分音符 = 120」寫成：每小節仍是 4 拍，
  每拍細分成三連音，所以不必改節奏系統也能跟拍。

需要 numpy。
"""

import sys
import wave
from pathlib import Path

import numpy as np

SR = 22050
BPM = 120
B = 60.0 / BPM  # 一拍秒數
BAR = B * 4
MEASURES = 16
L = int(round(SR * BAR * MEASURES))
NYQ_SAFE = 9500.0
OUT_DIR = Path(__file__).resolve().parent.parent / "assets" / "music" / "story"


def midi(n):
    return 440.0 * 2.0 ** ((n - 69) / 12.0)


def _t(n):
    return np.arange(n) / SR


def _smooth(x, k):
    if k <= 1:
        return x
    return np.convolve(x, np.ones(k) / k, mode="same")


# ---------------------------------------------------------------- 音色

def tone(freq, dur, partials, attack=0.005, decay=0.0, release=0.08,
         vib=0.0, vib_rate=5.0, vib_delay=0.2, detunes=(0.0,)):
    """加法合成：partials = [(頻率倍數, 振幅, 衰減倍數)]。"""
    n = int((dur + release) * SR)
    t = _t(n)
    vib_env = np.clip((t - vib_delay) / 0.3, 0.0, 1.0)
    out = np.zeros(n)
    for cents in detunes:
        f = freq * 2.0 ** (cents / 1200.0)
        finst = f * (1.0 + vib * vib_env * np.sin(2 * np.pi * vib_rate * t))
        ph = 2 * np.pi * np.cumsum(finst) / SR
        for ratio, amp, dmul in partials:
            if ratio * f >= NYQ_SAFE:
                continue
            out += amp * np.exp(-t * decay * dmul) * np.sin(ratio * ph)
    out /= len(detunes)
    gate = np.where(t < dur, 1.0, np.exp(-(t - dur) / max(release / 5.0, 1e-3)))
    return out * np.clip(t / attack, 0.0, 1.0) * gate


def saw(n, bright=0.25):
    return [(k, 1.0 / k, 1.0 + bright * (k - 1)) for k in range(1, n + 1)]


def square(n):
    return [(k, 1.0 / k, 1.0) for k in range(1, n + 1, 2)]


def inst_glock(f, dur, vel):
    p = [(1, 1.0, 1.0), (2.76, 0.32, 1.8), (5.4, 0.12, 3.0), (8.93, 0.04, 5.0)]
    return tone(f, max(dur, 0.6), p, attack=0.002, decay=3.2, release=0.3) * vel * 0.20


def inst_bell(f, dur, vel):
    n = int((max(dur, 0.8) + 0.4) * SR)
    t = _t(n)
    idx = 2.2 * np.exp(-t * 3.0)
    x = np.sin(2 * np.pi * f * t + idx * np.sin(2 * np.pi * 3.5 * f * t))
    return x * np.exp(-t * 2.0) * np.clip(t / 0.002, 0, 1) * vel * 0.13


def inst_epiano(f, dur, vel):
    n = int((dur + 0.25) * SR)
    t = _t(n)
    idx = 1.6 * np.exp(-t * 7.0) * (0.5 + vel)
    x = np.sin(2 * np.pi * f * t + idx * np.sin(2 * np.pi * f * t))
    x += 0.25 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t * 6)
    gate = np.where(t < dur, 1.0, np.exp(-(t - dur) / 0.05))
    return x * np.exp(-t * 1.8) * np.clip(t / 0.003, 0, 1) * gate * vel * 0.11


def inst_piano(f, dur, vel):
    p = [(k * (1 + 0.0004 * k * k), 1.0 / k ** 1.3, 1.0 + 0.35 * (k - 1)) for k in range(1, 9)]
    return tone(f, dur, p, attack=0.002, decay=1.6, release=0.35) * vel * 0.16


def inst_pluck(f, dur, vel):
    p = [(k, 1.0 / k, 1.0 + 0.7 * (k - 1)) for k in range(1, 11)]
    return tone(f, dur, p, attack=0.002, decay=4.5, release=0.05) * vel * 0.17


def inst_uke(f, dur, vel):
    p = [(k, 1.0 / k ** 0.8, 1.0 + 0.9 * (k - 1)) for k in range(1, 9)]
    return tone(f, dur, p, attack=0.001, decay=7.0, release=0.03) * vel * 0.12


def inst_square(f, dur, vel):
    return tone(f, dur, square(9), attack=0.004, decay=1.2, release=0.06,
                vib=0.004, vib_rate=5.5, vib_delay=0.18) * vel * 0.10


def inst_flute(f, dur, vel):
    p = [(1, 1.0, 1.0), (2, 0.12, 1.0), (3, 0.05, 1.0)]
    x = tone(f, dur, p, attack=0.05, decay=0.25, release=0.12,
             vib=0.005, vib_rate=5.2, vib_delay=0.15)
    x += _breath(len(x), 0.05)
    return x * vel * 0.14


def inst_whistle(f, dur, vel):
    x = tone(f, dur, [(1, 1.0, 1.0), (2, 0.05, 1.0)], attack=0.02, decay=0.6, release=0.05,
             vib=0.006, vib_rate=6.0, vib_delay=0.1)
    return x * vel * 0.12


def inst_strings(f, dur, vel):
    return tone(f, dur, saw(8, 0.0), attack=0.18, decay=0.0, release=0.35,
                vib=0.004, vib_rate=5.0, vib_delay=0.25, detunes=(-6, 0, 6)) * vel * 0.07


def inst_cello(f, dur, vel):
    return tone(f, dur, saw(10, 0.05), attack=0.12, decay=0.15, release=0.3,
                vib=0.005, vib_rate=4.8, vib_delay=0.3, detunes=(-4, 4)) * vel * 0.09


def inst_dist(f, dur, vel):
    x = tone(f, dur, saw(7, 0.1), attack=0.006, decay=0.35, release=0.08,
             vib=0.007, vib_rate=5.8, vib_delay=0.2, detunes=(-8, 8))
    return np.tanh(x * 2.2) * vel * 0.09


def inst_pad(f, dur, vel):
    return tone(f, dur, saw(6, 0.0), attack=0.45, decay=0.0, release=0.6,
                detunes=(-9, 0, 9)) * vel * 0.035


def inst_dark_pad(f, dur, vel):
    # 兩組音偏得比較開，聽起來會微微晃動、不安定
    return tone(f, dur, saw(5, 0.0), attack=0.7, decay=0.0, release=0.8,
                vib=0.003, vib_rate=0.7, vib_delay=0.0, detunes=(-18, 0, 14)) * vel * 0.035


def inst_bass(f, dur, vel):
    p = [(1, 1.0, 1.0), (2, 0.35, 1.3), (3, 0.12, 1.6)]
    return tone(f, dur, p, attack=0.004, decay=2.2, release=0.05) * vel * 0.30


def inst_synth_bass(f, dur, vel):
    return tone(f, dur, saw(10, 0.9), attack=0.003, decay=3.5, release=0.04) * vel * 0.26


def inst_sub(f, dur, vel):
    return tone(f, dur, [(1, 1.0, 1.0), (2, 0.15, 1.0)], attack=0.08, decay=0.0,
                release=0.3) * vel * 0.30


def _breath(n, amp):
    noise = np.random.default_rng(n).standard_normal(n)
    hp = noise - _smooth(noise, 6)
    return hp * amp * np.clip(_t(n) / 0.05, 0, 1)


# ---------------------------------------------------------------- 鼓組

class Kit:
    def __init__(self, rng):
        self.rng = rng

    def noise(self, n):
        return self.rng.standard_normal(n)

    def hp(self, n, k=4):
        x = self.noise(n)
        return x - _smooth(x, k)

    def kick(self, kind):
        n = int(0.45 * SR)
        t = _t(n)
        if kind == "punch":
            f = 50 + 125 * np.exp(-t * 35)
            amp, click = np.exp(-t * 7.5), 0.25
        elif kind == "heavy":
            f = 41 + 135 * np.exp(-t * 28)
            amp, click = np.exp(-t * 5.0), 0.18
        elif kind == "muffled":
            f = 46 + 70 * np.exp(-t * 22)
            amp, click = np.exp(-t * 10.0), 0.0
        else:  # soft
            f = 48 + 85 * np.exp(-t * 26)
            amp, click = np.exp(-t * 8.5), 0.08
        x = np.sin(2 * np.pi * np.cumsum(f) / SR) * amp
        if click:
            x += self.hp(n, 3) * np.exp(-t * 320) * click
        if kind == "heavy":
            x = np.tanh(x * 1.6) / np.tanh(1.6)
        return x * 0.9

    def snare(self):
        n = int(0.3 * SR)
        t = _t(n)
        body = (np.sin(2 * np.pi * 185 * t) + 0.5 * np.sin(2 * np.pi * 330 * t)) * np.exp(-t * 30)
        return (body * 0.28 + self.hp(n, 3) * np.exp(-t * 18) * 0.30)

    def clap(self):
        n = int(0.32 * SR)
        t = _t(n)
        x = self.hp(n, 3)
        x = x - _smooth(x, 12) * 0.5
        env = np.exp(-t * 16) * 0.8
        for d in (0.0, 0.011, 0.022):
            env += np.where(t >= d, np.exp(-(t - d) * 180), 0)
        return x * env * 0.12

    def snap(self):
        n = int(0.12 * SR)
        t = _t(n)
        return (self.hp(n, 2) * 0.6 + np.sin(2 * np.pi * 2100 * t)) * np.exp(-t * 70) * 0.13

    def rim(self):
        n = int(0.1 * SR)
        t = _t(n)
        x = np.sin(2 * np.pi * 1750 * t) + 0.6 * np.sin(2 * np.pi * 520 * t)
        return x * np.exp(-t * 90) * 0.14

    def hat(self, open_=False):
        n = int((0.4 if open_ else 0.08) * SR)
        t = _t(n)
        return self.hp(n, 2) * np.exp(-t * (11 if open_ else 85)) * 0.08

    def shaker(self):
        n = int(0.1 * SR)
        t = _t(n)
        return self.hp(n, 2) * (1 - np.exp(-t * 250)) * np.exp(-t * 35) * 0.07

    def brush(self):
        n = int(0.35 * SR)
        t = _t(n)
        x = self.hp(n, 5)
        return x * (1 - np.exp(-t * 60)) * np.exp(-t * 9) * 0.12

    def ride(self):
        n = int(0.9 * SR)
        t = _t(n)
        bell = sum(np.sin(2 * np.pi * 620 * r * t) for r in (1.0, 2.43, 3.71)) / 3
        return (self.hp(n, 2) * 0.5 + bell * 0.3) * np.exp(-t * 6) * 0.06

    def crash(self):
        n = int(2.2 * SR)
        t = _t(n)
        return self.hp(n, 2) * np.exp(-t * 2.4) * 0.11

    def swell(self, dur):
        """反向鈸：dur 秒內漸強，在下一段開頭剛好結束。"""
        n = int(dur * SR)
        t = _t(n)
        return self.hp(n, 2) * np.exp((t - dur) * 3.5) * 0.08

    def tom(self, f0):
        n = int(0.4 * SR)
        t = _t(n)
        f = f0 * (1 + 0.5 * np.exp(-t * 25))
        return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9) * 0.35

    def timpani(self, f0):
        n = int(1.4 * SR)
        t = _t(n)
        x = np.sin(2 * np.pi * f0 * t) + 0.4 * np.sin(2 * np.pi * f0 * 1.5 * t) * np.exp(-t * 3)
        return x * np.exp(-t * 2.2) * np.clip(t / 0.004, 0, 1) * 0.32

    def crackle(self):
        """黑膠底噪（整首長度），給第 9 關的回憶感。"""
        x = np.zeros(L)
        pos = self.rng.integers(0, L, size=220)
        x[pos] = self.rng.uniform(-1, 1, size=220)
        return _smooth(x, 2) * 0.10 + _smooth(self.noise(L), 40) * 0.010


# ---------------------------------------------------------------- 曲子

class Song:
    def __init__(self, seed, steps_per_bar=8, reverb=0.22, pump=0.0):
        self.rng = np.random.default_rng(seed)
        self.kit = Kit(self.rng)
        self.drums = np.zeros(L)
        self.music = np.zeros(L)
        self.steps = steps_per_bar
        self.step = BAR / steps_per_bar
        self.reverb = reverb
        self.pump = pump

    @staticmethod
    def bar(m):
        return m * BAR

    def _add(self, bus, start, sig):
        s0 = int(round(start * SR)) % L
        sig = sig[:L]
        end = s0 + len(sig)
        if end <= L:
            bus[s0:end] += sig
        else:
            k = L - s0
            bus[s0:] += sig[:k]
            bus[:end - L] += sig[k:]

    def drum(self, sig, start, vel=1.0):
        self._add(self.drums, start, sig * vel)

    def note(self, inst, n, start, dur, vel=0.8):
        self._add(self.music, start, inst(midi(n), dur, vel))

    def chord(self, inst, notes, start, dur, vel=0.6):
        for i, n in enumerate(notes):
            # 稍微錯開，聽起來像真人按和弦
            self.note(inst, n, start + i * 0.006, dur, vel)

    def kicks(self, m, kind, vel=1.0):
        for b in range(4):
            self.drum(self.kit.kick(kind), self.bar(m) + b * B, vel)

    def backbeat(self, m, kind, beats=(1, 3), vel=1.0):
        for b in beats:
            self.drum(getattr(self.kit, kind)(), self.bar(m) + b * B, vel)

    def hats(self, m, per_bar=8, vel=1.0, offbeat_only=False, open_offbeat=False, kind="hat"):
        for s in range(per_bar):
            is_off = (s * 4 / per_bar) % 1 != 0
            if offbeat_only and not is_off:
                continue
            if kind == "hat":
                sig = self.kit.hat(open_=open_offbeat and is_off and per_bar == 8)
            else:
                sig = getattr(self.kit, kind)()
            accent = 1.0 if is_off else 0.7
            self.drum(sig, self.bar(m) + s * BAR / per_bar, vel * accent)

    def melody(self, bars, inst, start_bar, transpose=0, vel=0.8, legato=0.92, steps=None):
        """bars：每小節一串字，數字＝MIDI 音高，- ＝延長，. ＝休止。"""
        steps = steps or self.steps
        step = BAR / steps
        events = []
        for i, line in enumerate(bars):
            for j, tok in enumerate(line.split()):
                pos = i * steps + j
                if tok == "-":
                    if events and events[-1][2] is not None:
                        events[-1][1] += 1
                    continue
                events.append([pos, 1, None if tok == "." else int(tok)])
        for pos, length, n in events:
            if n is None:
                continue
            accent = 1.0 if pos % (steps // 4) == 0 else 0.85
            self.note(inst, n + transpose, self.bar(start_bar) + pos * step,
                      length * step * legato, vel * accent)

    def arp(self, inst, notes, m, pattern, vel=0.5, length=0.9, steps=None):
        steps = steps or self.steps
        step = BAR / steps
        for s, idx in enumerate(pattern):
            if idx is None:
                continue
            self.note(inst, notes[idx % len(notes)] + 12 * (idx // len(notes)),
                      self.bar(m) + s * step, step * length, vel)

    def render(self):
        music = self.music
        if self.pump:
            # 側鏈壓縮：每拍大鼓時把旋律稍微壓下去，製造律動感
            t = _t(L) % B
            music = music * (1 - self.pump * np.exp(-t * 14))
        wet_in = music + self.drums * 0.12
        ir_n = int(2.4 * SR)
        ir_t = _t(ir_n)
        ir = _smooth(self.rng.standard_normal(ir_n), 5) * np.exp(-ir_t * 2.6)
        ir[: int(0.018 * SR)] = 0  # pre-delay
        ir /= np.sqrt(np.sum(ir ** 2))
        # 循環卷積：殘響尾巴自然繞回開頭，loop 沒有接縫
        wet = np.fft.irfft(np.fft.rfft(wet_in) * np.fft.rfft(ir, L), L)
        mix = self.drums + music + wet * self.reverb
        mix -= mix.mean()
        peak = np.max(np.abs(mix)) or 1.0
        return np.tanh(mix / peak * 1.3) / np.tanh(1.3) * 0.89


# 每段用法：sec = m // 4，0 前奏、1 主旋律、2 堆疊、3 高潮


def level01(s):
    """開始喜歡上女孩：甜甜的、心動。C 大調，Cmaj7–Am7–Dm7–G7，鐘琴旋律＋電鋼琴。"""
    ch = [(48, [60, 64, 67, 71]), (45, [57, 60, 64, 67]), (50, [62, 65, 69, 72]), (43, [59, 62, 65, 67])]
    for m in range(16):
        sec, (root, v) = m // 4, ch[m % 4]
        t0 = s.bar(m)
        s.kicks(m, "soft")
        if m % 4 == 0 and sec > 0:
            s.drum(s.kit.crash(), t0, 0.6)
        if sec == 0:
            s.chord(inst_epiano, v, t0, B * 1.9, 0.55)
            s.chord(inst_epiano, v, t0 + 2 * B, B * 1.9, 0.5)
            s.note(inst_bass, root, t0, BAR * 0.9, 0.5)
        else:
            for b in range(4):
                s.chord(inst_epiano, v, t0 + b * B + B / 2, B * 0.4, 0.5)
            s.note(inst_bass, root, t0, B * 1.4, 0.8)
            s.note(inst_bass, root + 7, t0 + 2.5 * B, B * 0.45, 0.6)
            s.note(inst_bass, root + 12, t0 + 3 * B, B * 0.9, 0.6)
            s.backbeat(m, "snap", vel=1.0)
        if sec >= 2:
            s.hats(m, 16, 0.9, kind="shaker")
            s.chord(inst_pad, v, t0, BAR, 0.8)
        if sec == 2:
            s.arp(inst_glock, [n + 12 for n in v], m, [0, 1, 2, 3, 4, 3, 2, 1], vel=0.55)
        if sec == 0:
            s.arp(inst_glock, [n + 12 for n in v], m, [None, None, 2, None, None, None, 3, None], vel=0.4)
    a = ["76 79 . 76 74 72 74 76", "72 - 69 . 72 76 - .", "77 76 74 . 69 72 74 77", "76 - 74 - 71 - 67 ."]
    b = ["79 - 76 79 81 79 76 74", "76 - 72 . 69 72 76 79", "77 - 74 77 81 - 79 77", "76 - 74 72 74 - 72 ."]
    s.melody(a, inst_glock, 4)
    s.melody(b, inst_glock, 12)
    s.melody(b, inst_flute, 12, transpose=-12, vel=0.55)


def level02(s):
    """追求：苦澀。D 小調，Dm9–B♭maj7–Gm7–A7，撥弦琶音＋大提琴般的嘆息旋律。"""
    ch = [(38, [62, 65, 69, 72, 76]), (34, [58, 62, 65, 69]), (43, [55, 58, 62, 65]), (45, [57, 61, 64, 67])]
    for m in range(16):
        sec, (root, v) = m // 4, ch[m % 4]
        t0 = s.bar(m)
        s.kicks(m, "soft", 0.95)
        if m % 4 == 0 and sec >= 2:
            s.drum(s.kit.crash(), t0, 0.45)
        s.arp(inst_pluck, v, m, [0, 2, 1, 3, 2, 4, 3, 2], vel=0.55 if sec else 0.45)
        s.note(inst_bass, root, t0, B * 2.8, 0.7)
        s.note(inst_bass, root + (7 if m % 4 != 3 else 4), t0 + 3 * B, B * 0.9, 0.55)
        if sec >= 1:
            s.backbeat(m, "rim", vel=0.9)
            s.hats(m, 8, 0.6, offbeat_only=True)
        if sec >= 2:
            s.chord(inst_strings, [n - 12 for n in v[:3]], t0, BAR, 0.55)
        if sec == 2:
            s.melody(["74 - - - 72 - - -", "70 - - - 69 - - -", "67 - - - 65 - - -", "64 - - - 61 - - -"][m % 4:m % 4 + 1],
                     inst_cello, m, transpose=-12, vel=0.6)
    a = ["77 - - 76 74 - 72 74", "74 - - . 69 70 72 74", "70 - 69 67 65 - 67 69", "69 - - - 73 - 76 -"]
    b = ["81 - - 79 77 - 76 77", "77 - 74 . 74 77 79 81", "82 - 81 79 77 - 74 77", "76 - - - 73 - 69 -"]
    s.melody(a, inst_cello, 4, vel=0.75)
    s.melody(b, inst_cello, 12, vel=0.75)
    s.melody(b, inst_glock, 12, vel=0.3)


def level03(s):
    """告白成功：雀躍。G 大調，G–D–Em–C，方波主旋律、拍手、八度跳動貝斯、側鏈律動。"""
    ch = [(43, [62, 67, 71, 74]), (38, [62, 66, 69, 74]), (40, [64, 67, 71, 76]), (36, [60, 64, 67, 72])]
    for m in range(16):
        sec, (root, v) = m // 4, ch[m % 4]
        t0 = s.bar(m)
        s.kicks(m, "punch")
        if m % 4 == 0:
            s.drum(s.kit.crash(), t0, 0.7 if sec else 0.4)
        if m % 4 == 3 and sec < 3:
            s.drum(s.kit.swell(BAR), t0, 0.7)
        for k in range(8):
            octave = 12 if k % 2 else 0
            s.note(inst_synth_bass, root + octave, t0 + k * B / 2, B * 0.4, 0.7)
        if sec >= 1:
            s.backbeat(m, "clap", vel=1.1)
            s.backbeat(m, "snare", vel=0.5)
            s.hats(m, 8, 1.0, open_offbeat=True)
        else:
            s.hats(m, 8, 0.7, offbeat_only=True)
        for b in range(4):
            s.chord(inst_uke, v, t0 + b * B + B / 2, B * 0.3, 0.6)
        if sec >= 2:
            s.chord(inst_pad, v, t0, BAR, 0.9)
            s.hats(m, 16, 0.5, kind="shaker")
        if sec == 2:
            s.arp(inst_bell, [n + 12 for n in v], m, [0, 1, 2, 3, 2, 1, 2, 3], vel=0.5)
    a = ["74 79 . 79 78 79 81 79", "78 - 74 . 74 78 81 -", "79 - 76 79 83 - 81 79", "76 79 . 76 74 72 74 -"]
    b = ["86 - 83 86 88 86 83 81", "81 - 78 81 86 - 85 -", "83 - 79 83 88 - 86 83", "84 - 83 81 79 - 78 -"]
    s.melody(a, inst_square, 4)
    s.melody(b, inst_square, 12)
    s.melody(b, inst_square, 12, transpose=-12, vel=0.5)


def level04(s):
    """熱戀：12/8 拍浪漫旋律。F 大調，Fmaj7–Dm7–B♭maj7–C7；附點四分＝120，每拍三連音。"""
    ch = [(41, [57, 60, 64, 65]), (38, [57, 60, 62, 65]), (46, [57, 62, 65, 70]), (36, [58, 60, 64, 67])]
    for m in range(16):
        sec, (root, v) = m // 4, ch[m % 4]
        t0 = s.bar(m)
        s.kicks(m, "soft")
        if m % 4 == 0 and sec > 0:
            s.drum(s.kit.ride(), t0, 1.2)
        # 三連音分割：12 格一小節，鼓刷落在第 2、4 拍
        if sec >= 1:
            s.backbeat(m, "brush", vel=1.0)
            for k in range(12):
                if k % 3:
                    s.drum(s.kit.shaker(), t0 + k * B / 3, 0.8 if k % 3 == 2 else 0.5)
        if sec >= 2:
            for b in range(4):
                s.drum(s.kit.ride(), t0 + b * B, 0.6)
        # 電鋼琴三連音琶音：根、三、五 上行再回來
        pat = [0, 1, 2, 3, 2, 1, 0, 1, 2, 3, 4, 3] if sec >= 1 else [0, None, None, 2, None, None, 1, None, None, 3, None, None]
        s.arp(inst_epiano, v, m, pat, vel=0.5, length=1.6, steps=12)
        # 貝斯：第 1、3 拍根音，第 4 拍最後一個三連音接下一個和弦
        s.note(inst_bass, root, t0, B * 1.9, 0.8)
        s.note(inst_bass, root + 7, t0 + 2 * B, B * 1.4, 0.65)
        s.note(inst_bass, root + 12, t0 + 3 * B + 2 * B / 3, B * 0.3, 0.5)
        if sec >= 2:
            s.chord(inst_strings, v, t0, BAR, 0.5)
    a = ["72 - 74 76 - - 77 - 76 72 - -", "74 - - 69 - 72 74 - 77 76 - -",
         "74 - 72 70 - - 69 - 70 72 - -", "67 - - - - - 76 - 74 72 - 70"]
    b = ["81 - - 79 - 77 76 - 77 79 - -", "81 - - 77 - 74 72 - 74 77 - -",
         "82 - - 81 - 79 77 - 74 77 - -", "79 - - - - - 76 - 77 79 - 76"]
    s.melody(a, inst_flute, 4, steps=12)
    s.melody(b, inst_flute, 12, steps=12)
    s.melody(b, inst_glock, 12, steps=12, vel=0.35)


def level05(s):
    """日常：輕快。D 大調，D–Bm7–Em7–A7，烏克麗麗刷弦、口哨旋律、跳音貝斯。"""
    ch = [(38, [62, 66, 69, 74]), (35, [62, 66, 69, 71]), (40, [62, 64, 67, 71]), (33, [61, 64, 67, 69])]
    strum = [0, None, 1, 1, None, 1, 0, 1]  # 0 下刷重、1 上刷輕
    for m in range(16):
        sec, (root, v) = m // 4, ch[m % 4]
        t0 = s.bar(m)
        s.kicks(m, "punch", 0.9)
        if m % 4 == 0 and sec > 0:
            s.drum(s.kit.crash(), t0, 0.45)
        for k, st in enumerate(strum):
            if st is not None:
                s.chord(inst_uke, [n + 12 for n in v], t0 + k * B / 2, B * 0.3, 0.6 if st == 0 else 0.4)
        bass = [(0, 0), (1.5, 12), (2, 7), (3, 0), (3.5, 12)] if sec else [(0, 0), (2, 7)]
        for beat, iv in bass:
            s.note(inst_bass, root + iv, t0 + beat * B, B * 0.4, 0.75)
        s.hats(m, 16 if sec >= 2 else 8, 0.8, kind="shaker")
        if sec >= 1:
            s.backbeat(m, "clap", vel=0.9)
        if sec == 2:
            s.arp(inst_glock, [n + 12 for n in v], m, [0, None, 2, 1, None, 3, 2, None], vel=0.5)
            s.chord(inst_pad, v, t0, BAR, 0.6)
    a = ["78 - 76 74 . 74 76 78", "81 - 78 . 74 . 76 78", "79 - 78 76 . 71 74 76", "73 - 74 76 . 79 78 76"]
    b = ["81 81 . 78 81 83 81 78", "78 - 74 76 78 - 81 -", "79 79 . 76 79 81 79 76", "76 - 73 74 76 - 69 ."]
    s.melody(a, inst_whistle, 4, legato=0.75)
    s.melody(b, inst_whistle, 12, legato=0.75)
    s.melody(b, inst_pluck, 12, transpose=-12, vel=0.5, legato=0.6)


def level06(s):
    """感情逐漸變得不一樣：微妙、不安。E 小調，Em–Cmaj7–Am6–B7(♭9)，晃動的長音、半音旋律、時鐘般的滴答。"""
    ch = [(40, [55, 59, 64, 67]), (36, [55, 59, 64, 67]), (45, [57, 60, 64, 66]), (35, [57, 60, 63, 66])]
    for m in range(16):
        sec, (root, v) = m // 4, ch[m % 4]
        t0 = s.bar(m)
        s.kicks(m, "muffled", 1.05)
        if m % 4 == 3:
            s.drum(s.kit.swell(BAR), t0, 0.8)
        s.chord(inst_dark_pad, v, t0, BAR, 0.9)
        # 時鐘：每個八分音符一聲滴答，第 3 段起加快成十六分音符
        for k in range(16 if sec >= 2 else 8):
            s.drum(s.kit.rim(), t0 + k * BAR / (16 if sec >= 2 else 8), 0.35 if k % 2 else 0.5)
        pulse = [0, 0, 0, 0, 0, 0, 0, 0] if sec < 2 else [0, None, 0, 12, None, 0, 0, 12]
        for k, iv in enumerate(pulse):
            if iv is not None:
                s.note(inst_synth_bass, root + iv, t0 + k * B / 2, B * 0.35, 0.45 if sec < 2 else 0.6)
        if sec >= 1:
            s.backbeat(m, "snare", beats=(3,), vel=0.55)
        if sec == 2:
            s.arp(inst_bell, [n + 12 for n in v], m, [3, None, None, 2, None, None, 1, None], vel=0.45)
    a = ["71 - - 72 71 - - .", "76 - - 75 76 - 79 -", "78 - - 77 76 - 72 -", "75 - - - 74 - 71 -"]
    b = ["83 - - 84 83 - 79 -", "76 - 79 - 82 - - -", "81 - 78 - 77 - 76 -", "75 - 78 - 81 - 84 -"]
    s.melody(a, inst_bell, 4, vel=0.8)
    s.melody(a, inst_strings, 4, transpose=-12, vel=0.4)
    s.melody(b, inst_bell, 12, vel=0.85)
    s.melody(b, inst_cello, 12, transpose=-12, vel=0.5)


def level07(s):
    """因現實考量而改變的關係：沉重。C 小調，Cm–A♭–Fm–G，半拍感（小鼓只在第 3 拍）、低音持續音、定音鼓。"""
    ch = [(36, [55, 60, 63]), (32, [56, 60, 63]), (29, [56, 60, 65]), (31, [55, 59, 62])]
    for m in range(16):
        sec, (root, v) = m // 4, ch[m % 4]
        t0 = s.bar(m)
        s.kicks(m, "heavy")
        s.note(inst_sub, root - 12 if root > 30 else root, t0, BAR, 0.8)
        s.chord(inst_piano, [n - 12 for n in v], t0, BAR * 0.9, 0.7)
        if sec >= 1:
            s.backbeat(m, "snare", beats=(2,), vel=1.2)
            s.hats(m, 4, 0.7, kind="hat")
        if m % 4 == 0:
            s.drum(s.kit.timpani(midi(root)), t0, 1.0)
            if sec >= 1:
                s.drum(s.kit.crash(), t0, 0.7)
        if sec >= 2:
            s.chord(inst_strings, v, t0, BAR, 0.7)
            s.chord(inst_piano, [n + 12 for n in v], t0 + 2 * B, B * 1.5, 0.45)
        if m % 4 == 3 and sec >= 1:
            for i, f in enumerate((140, 120, 100, 85)):
                s.drum(s.kit.tom(f), t0 + 3 * B + i * B / 4, 0.8)
    a = ["67 - - - - - 63 -", "68 - - - 67 - 65 -", "65 - - - 63 - 60 -", "62 - - - - - 59 -"]
    b = ["75 - - - 74 - 72 -", "72 - - - 70 - 68 -", "68 - - - 67 - 65 63", "62 - - - 67 - 71 -"]
    s.melody(a, inst_cello, 4, vel=0.9)
    s.melody(b, inst_cello, 12, vel=0.9)
    s.melody(b, inst_cello, 12, transpose=-12, vel=0.55)


def level08(s):
    """分手：痛苦。B 小調，Bm–G–Em–F#，失真主旋律、重擊小鼓、第 4 段十六分音符的急促。"""
    ch = [(35, [59, 62, 66]), (31, [59, 62, 67]), (40, [59, 64, 67]), (42, [58, 61, 66])]
    for m in range(16):
        sec, (root, v) = m // 4, ch[m % 4]
        t0 = s.bar(m)
        s.kicks(m, "heavy" if sec >= 1 else "punch")
        if m % 4 == 0:
            s.drum(s.kit.crash(), t0, 0.8 if sec else 0.5)
        if m % 4 == 3:
            s.drum(s.kit.swell(BAR * 0.75), t0 + BAR * 0.25, 0.9)
        steps = 16 if sec >= 2 else 8
        for k in range(steps):
            s.note(inst_synth_bass, root, t0 + k * BAR / steps, BAR / steps * 0.7, 0.75 if k % 2 == 0 else 0.55)
        s.chord(inst_strings, v, t0, BAR, 0.6 if sec else 0.8)
        if sec >= 1:
            s.backbeat(m, "snare", vel=1.3)
            s.backbeat(m, "clap", vel=0.6)
            s.hats(m, 16 if sec == 3 else 8, 0.9)
        if sec == 2:
            s.arp(inst_piano, [n + 12 for n in v], m, [0, 1, 2, 3, 2, 1, 0, 1, 2, 3, 2, 1, 2, 3, 4, 3], vel=0.5, steps=16)
        if m % 4 == 3 and sec >= 2:
            for i, f in enumerate((160, 140, 120, 100, 160, 140, 120, 100)):
                s.drum(s.kit.tom(f), t0 + 2 * B + i * B / 4, 0.7)
    a = ["78 - - 79 78 - 74 -", "83 - - - 81 79 78 -", "79 - - 78 76 - 71 -", "73 - - 70 73 - 78 -"]
    b = ["86 - - 85 83 - 78 -", "86 - 83 - 79 - 83 -", "88 - - 86 83 - 79 76", "85 - - 82 78 - 73 -"]
    s.melody(a, inst_dist, 4)
    s.melody(b, inst_dist, 12)
    s.melody(b, inst_dist, 12, transpose=-12, vel=0.55)


def level09(s):
    """分手之後：感傷。A 小調的 Fmaj7–G6–Em7–Am7，鋼琴、黑膠底噪、輕柔邊擊。"""
    ch = [(41, [57, 60, 64, 65]), (43, [59, 62, 64, 67]), (40, [55, 59, 62, 64]), (45, [55, 60, 64, 67])]
    s.drums += s.kit.crackle()
    for m in range(16):
        sec, (root, v) = m // 4, ch[m % 4]
        t0 = s.bar(m)
        s.kicks(m, "soft", 0.9)
        # 鋼琴左手：根音＋五度＋十度，像分解和弦
        s.arp(inst_piano, [root, root + 7, root + 12, root + 16 if m % 4 in (0, 1) else root + 15],
              m, [0, 1, 2, 3, 2, 1, 2, 1], vel=0.45, length=1.8)
        if sec >= 1:
            s.backbeat(m, "rim", vel=0.8)
            s.hats(m, 8, 0.5, offbeat_only=True)
        if sec >= 2:
            s.chord(inst_strings, v, t0, BAR, 0.45)
            s.note(inst_bass, root, t0, B * 2.5, 0.6)
            s.note(inst_bass, root + 7, t0 + 2.5 * B, B * 1.4, 0.5)
        if sec == 2:
            s.melody([["76 - - - 74 - 72 -", "74 - - - 72 - 71 -", "71 - - - 67 - 64 -", "64 - - - - - - -"][m % 4]],
                     inst_piano, m, transpose=12, vel=0.35)
    a = ["76 - 74 76 - 79 76 74", "74 - 72 74 - 76 79 -", "79 - 76 - 74 72 71 -", "72 - - - 69 - - ."]
    b = ["81 - 79 81 - 84 81 79", "79 - 76 79 - 81 83 -", "83 - 79 - 76 74 71 -", "72 - 71 69 - - - ."]
    s.melody(a, inst_piano, 4, vel=0.9)
    s.melody(b, inst_piano, 12, vel=0.9)
    s.melody(b, inst_piano, 12, transpose=-12, vel=0.5)


def level10(s):
    """找到自己：釋懷。D 大調，D–A/C#–Bm–G，從單純鋼琴一路疊到弦樂、鐘聲與完整鼓組。"""
    ch = [(38, [62, 66, 69]), (37, [61, 64, 69]), (35, [62, 66, 71]), (31, [62, 67, 71])]
    for m in range(16):
        sec, (root, v) = m // 4, ch[m % 4]
        t0 = s.bar(m)
        s.kicks(m, "soft" if sec < 2 else "punch", 0.85 if sec == 0 else 1.0)
        if m % 4 == 0 and sec >= 1:
            s.drum(s.kit.crash(), t0, 0.5 + 0.15 * sec)
        if m == 11:
            s.drum(s.kit.swell(BAR), t0, 1.0)
        s.chord(inst_piano, v, t0, B * 1.8, 0.55)
        s.chord(inst_piano, v, t0 + 2 * B, B * 1.8, 0.45)
        s.note(inst_piano, root + 12, t0, BAR * 0.9, 0.5)
        if sec >= 1:
            s.chord(inst_strings, v, t0, BAR, 0.55 + 0.1 * sec)
            s.hats(m, 8, 0.5, offbeat_only=sec == 1)
        if sec >= 2:
            s.note(inst_bass, root, t0, B * 1.4, 0.8)
            s.note(inst_bass, root, t0 + 1.5 * B, B * 0.45, 0.6)
            s.note(inst_bass, root + 7, t0 + 2 * B, B * 1.9, 0.7)
            s.backbeat(m, "clap", vel=0.9)
            s.backbeat(m, "snare", vel=0.4)
            s.arp(inst_bell, [n + 24 for n in v], m, [0, 1, 2, 1, 0, 1, 2, 3], vel=0.4)
        if sec == 3:
            s.hats(m, 16, 0.5, kind="shaker")
    a = ["74 - 76 78 - - 81 -", "76 - - - 73 76 78 -", "78 - 79 81 - - 86 -", "83 - 81 79 - 78 76 -"]
    b = ["86 - 85 86 - 88 90 -", "88 - - - 85 - 81 -", "83 - 85 86 - 88 90 -", "91 - 90 88 - 86 85 -"]
    s.melody(a, inst_flute, 4)
    s.melody(a, inst_strings, 8, vel=0.75)
    s.melody(["78 - 79 81 - - 76 -", "73 - - - 69 73 76 -", "74 - 76 78 - - 81 -", "79 - 78 76 - 74 73 -"],
             inst_cello, 8, transpose=-12, vel=0.55)
    s.melody(b, inst_flute, 12)
    s.melody(a, inst_strings, 12, vel=0.7)


TRACKS = [
    # (編號, 檔名, 時期, 函式, 種子, 每小節格數, 殘響, 側鏈)
    (1, "level01_crush", "開始喜歡上女孩・甜甜的、心動", level01, 101, 8, 0.25, 0.10),
    (2, "level02_pursuit", "追求・苦澀", level02, 202, 8, 0.30, 0.0),
    (3, "level03_confession", "告白成功・雀躍", level03, 303, 8, 0.16, 0.30),
    (4, "level04_in_love_12-8", "熱戀・12/8 拍浪漫", level04, 404, 12, 0.32, 0.0),
    (5, "level05_everyday", "日常・輕快", level05, 505, 8, 0.15, 0.15),
    (6, "level06_drifting", "感情逐漸變得不一樣・微妙、不安", level06, 606, 8, 0.35, 0.0),
    (7, "level07_reality", "因現實考量而改變的關係・沉重", level07, 707, 8, 0.30, 0.35),
    (8, "level08_breakup", "分手・痛苦", level08, 808, 8, 0.22, 0.40),
    (9, "level09_after", "分手之後・感傷", level09, 909, 8, 0.36, 0.0),
    (10, "level10_myself", "找到自己・釋懷", level10, 1010, 8, 0.32, 0.08),
]


def write_wav(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = np.clip(data * 32767, -32768, 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main(argv):
    wanted = {int(a) for a in argv} if argv else None
    for num, slug, label, fn, seed, steps, reverb, pump in TRACKS:
        if wanted and num not in wanted:
            continue
        song = Song(seed, steps_per_bar=steps, reverb=reverb, pump=pump)
        fn(song)
        out = OUT_DIR / f"{slug}.wav"
        write_wav(out, song.render())
        print(f"第 {num:>2} 關 {label:<24} → {out.relative_to(OUT_DIR.parent.parent.parent)} ({L / SR:.1f}s)")


if __name__ == "__main__":
    main(sys.argv[1:])
