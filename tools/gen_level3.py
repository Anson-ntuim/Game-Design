"""共用的模擬與機關（tools/course_kit.py、tools/gen_demo.py 用）。

主軸是玩家的按鍵：每一拍都要按對「點（輕點跳）／長（按住跳）／衝（衝刺）」。
機關負責檢查按得對不對：
  活塞在反拍砸下、每拍都砸  → 只有正拍衝刺穿得過去（走路太慢）
  木箱 2 格高               → 要長按才跳得過
  音符上方的橫向雷射        → 在那一拍發射，長按會撞上，只能輕點
  衝刺環                    → 在亮起的那一拍衝刺穿過，冷卻清零、空中衝刺補回，下一拍能再衝
  寬坑                      → 要靠衝刺環連續每拍衝刺才過得去
每段用標準節奏跑一次物理模擬（tools/sim_player.py），把機關放在對應位置，
再逐一測試「提早／延後」「按錯長短」「少按衝刺」是否會失敗。
"""

from sim_player import Sim, Orb, SPB, TILE, DT, HURT, DASH_TIME, run, ground, cap_holds
from design import show, notes_for, TAP, FULL

HEIGHT = 20
START = (140.0, 617.99)
HURT_HW, HURT_HH = 9.0, 19.0
LASER_HALF = 5.0
LASER_HARM = (0.03 / SPB, 0.23 / SPB)
TONES = [12, 15, 19, 17, 22, 24, 27]


# ───────────────────────── 機關模型（和 GDScript 相同的時間軸） ─────────────────────────

def since_hit(slots, beat, cycle=16):
    """slots 是 16 格（半拍）循環裡的觸發格；回傳距離上一次觸發幾拍"""
    p = beat * 2
    best = 1e9
    for s in slots:
        d = (p - s) % cycle
        best = min(best, d)
    return best * 0.5


def until_hit(slots, beat, cycle=16):
    p = beat * 2
    best = 1e9
    for s in slots:
        d = (s - p) % cycle
        best = min(best, d if d > 0 else cycle)
    return best * 0.5


def slots_of(notes, ch="x"):
    return {i for i, c in enumerate(notes) if c == ch}


class Laser:
    def __init__(self, rect, notes):
        self.rect = rect  # (l, t, r, b) 傷害範圍
        self.slots = slots_of(notes)

    def harmful(self, beat):
        s = since_hit(self.slots, beat)
        return LASER_HARM[0] <= s < LASER_HARM[1]


class Piston:
    RETRACTED, SLAM, HOLD, RISE = 28.0, 0.1, 0.3, 0.9

    def __init__(self, left, top, w, h, notes):
        self.left, self.top, self.w, self.h = left, top, w, h
        self.slots = slots_of(notes)

    def bottom(self, beat):
        s = since_hit(self.slots, beat)
        R = self.RETRACTED
        if s < self.SLAM:
            return R + (self.h - R) * (s / self.SLAM) ** 2
        if s < self.HOLD:
            return self.h
        if s < self.RISE:
            return self.h + (R - self.h) * (s - self.HOLD) / (self.RISE - self.HOLD)
        u = until_hit(self.slots, beat)
        return R + 10.0 * min(max(1.0 - u / 0.5, 0.0), 1.0)

    def rect_at(self, beat):
        b = self.bottom(beat)
        if b <= self.RETRACTED + 12:
            return None
        return (self.left + 3, self.top + self.RETRACTED, self.left + self.w - 3, self.top + b)


class MelodyPlatform:
    """旋律平台（和 pattern_platform.gd 相同）：x 格期間和之後 GRACE 秒是實體的單向平台"""
    GRACE = 0.12

    def __init__(self, c0, c1, row, notes):
        self.left, self.right, self.top = c0 * TILE, (c1 + 1) * TILE, row * TILE
        self.notes = notes

    def _on(self, beat):
        return self.notes[int((beat % (len(self.notes) * 0.5)) * 2)] == "x"

    def solid(self, beat):
        return self._on(beat) or self._on(beat - self.GRACE / SPB)


class BeatPlatform:
    """節拍平台（和 beat_platform.gd 相同）：A 組在每 4 拍的 -0.25～2.25 拍、B 組在 1.75～4.25 拍是實體"""
    PERIOD, GRACE = 2.0, 0.25

    def __init__(self, c0, c1, row, group):
        self.left, self.right, self.top = c0 * TILE, (c1 + 1) * TILE, row * TILE
        self.group = group

    @classmethod
    def window_has(cls, group, b0, b1):
        """b0～b1 整段都是實體"""
        p0 = (b0 - group * cls.PERIOD + cls.GRACE) % (cls.PERIOD * 2)
        return p0 + (b1 - b0) < cls.PERIOD + cls.GRACE * 2

    def solid(self, beat):
        return self.window_has(self.group, beat, beat)


class PatternSpike:
    """地板節奏尖刺（和 pattern_spike.gd 相同）：x 拍後 0.08～0.23 秒有傷害，判定框在格子底部 14 px"""
    name = "尖刺"
    POP, ACTIVE = 0.08, 0.15

    def __init__(self, col, row, notes):
        self.rect = (col * TILE + 4, (row + 1) * TILE - 14, col * TILE + 36, (row + 1) * TILE)
        self.col, self.row, self.notes = col, row, notes
        self.slots = slots_of(notes)

    def harmful(self, beat):
        s = since_hit(self.slots, beat, len(self.notes)) * SPB
        return self.POP <= s < self.POP + self.ACTIVE


class FixedSpike:
    """固定尖刺（和 spike.gd 相同）：判定框是格子底部 0.55 格"""
    name = "尖刺"

    def __init__(self, col, row):
        self.rect = (col * TILE + 4, (row + 1) * TILE - 22, col * TILE + 36, (row + 1) * TILE)

    def harmful(self, beat):
        return True


def overlaps(x, y, rect):
    l, t, r, b = rect
    return x + HURT_HW > l and x - HURT_HW < r and y + HURT_HH > t and y - HURT_HH < b


def first_hit(sim, lasers=(), pistons=(), spikes=(), after=-1.0, hazards=()):
    for (b, x, y) in sim.log:
        if b < after:
            continue
        if y > 800:
            return ("掉坑", round(b, 2))
        for L in lasers:
            if L.harmful(b) and overlaps(x, y, L.rect):
                return ("雷射", round(b, 2))
        for h in hazards:
            if h.harmful(b) and overlaps(x, y, h.rect):
                return (h.name, round(b, 2))
        for P in pistons:
            r = P.rect_at(b)
            if r and overlaps(x, y, r):
                return ("活塞", round(b, 2))
        for s in spikes:
            if overlaps(x, y, s):
                return ("尖刺", round(b, 2))
    return None


# ───────────────────────── 區塊與節奏型 ─────────────────────────

class Chunk:
    def __init__(self, width):
        self.w = width
        self.rows = [[" "] * width for _ in range(HEIGHT)]

    def fill(self, c0, c1, r0, r1, ch):
        if c1 >= self.w:
            for row in self.rows:
                row.extend([" "] * (c1 + 1 - self.w))
            self.w = c1 + 1
        for r in range(r0, r1 + 1):
            for c in range(c0, c1 + 1):
                self.rows[r][c] = ch

    def lines(self):
        return ["".join(r).rstrip() for r in self.rows]


class Patterns:
    def __init__(self):
        self.items = {}
        # 不能用 level_data.gd 圖例裡的固定字元（# % = A B M m J | ^ ! ? E C G P W Y）
        self.free = list("abcdefhiklnopqrstuvwxz0123456789gjyDFHIKLNOQRSTUVXZ")

    def add(self, spec):
        for k, v in self.items.items():
            if v == spec:
                return k
        ch = self.free.pop(0)
        self.items[ch] = spec
        return ch


def beats_notes(beats, ch="x"):
    n = ["."] * 16
    for b in beats:
        n[int(round(b * 2)) % 16] = ch
    return "".join(n)


FLAG = {"kind": "flag", "notes": "x..............."}
PUMP = {"kind": "piston", "notes": ".x.x.x.x.x.x.x.x"}


def solid_rect(c0, c1, r0, r1):
    return (c0 * TILE, r0 * TILE, (c1 + 1) * TILE, (r1 + 1) * TILE)


# ───────────────────────── 模擬與驗證 ─────────────────────────

RING_RADIUS = 26.0
RING_AHEAD = 14.0
RING_POP = 360.0


class Ring(Orb):
    """衝刺環：按下衝刺的時間要落在環的判定窗內（和音符相同），而且這次衝刺碰到環（和 dash_ring.gd 相同）"""


class Gate:
    """節拍光牆（和 beat_gate.gd 相同）：一律實心，只有在 x 那拍前 EARLY 秒到後 LATE 秒內按下的衝刺能穿過（預設約等於普通難度）"""
    EARLY, LATE = 0.12, 0.13

    def __init__(self, col, r0, r1, notes):
        self.rect = (col * TILE + 10, r0 * TILE, col * TILE + 30, (r1 + 1) * TILE)
        self.col, self.r0, self.r1, self.notes = col, r0, r1, notes
        self.slots = slots_of(notes)

    def accepts(self, dash_beat):
        return (since_hit(self.slots, dash_beat) * SPB <= self.LATE
                or until_hit(self.slots, dash_beat) * SPB <= self.EARLY)


class RingSim(Sim):
    """加上衝刺環：衝刺中碰到亮著的環 → 冷卻清零、補回空中衝刺，衝刺結束時往上彈 RING_POP"""

    def __init__(self, x, y, solids, orbs, rings, start_beat, gates=(), platforms=()):
        super().__init__(x, y, solids, orbs, start_beat=start_beat)
        self.platforms = list(platforms)
        self.rings = list(rings)
        self.gates = [Gate(g.col, g.r0, g.r1, g.notes) for g in gates]
        self.pop = False
        self.dash_beat = -99.0

    def _collide(self, nx, ny):
        s = super()._collide(nx, ny)
        if s:
            return s
        hw, hh = 12.0, 22.0
        for g in self.gates:
            if self.dash_t > 0 and g.accepts(self.dash_beat):
                continue
            l, t, r, b = g.rect
            # 已經在光牆裡（衝刺穿到一半）不會被卡住，和 player.gd 衝刺穿牆時延長衝刺相同
            if self.x + hw > l and self.x - hw < r and self.y + hh > t and self.y - hh < b:
                continue
            if nx + hw > l and nx - hw < r and ny + hh > t and ny - hh < b:
                return g.rect
        return None

    def _ring_hit(self):
        hw, hh = HURT[0] / 2, HURT[1] / 2
        for r in self.rings:
            cx = min(max(r.x, self.x - hw), self.x + hw)
            cy = min(max(r.y, self.y - hh), self.y + hh)
            if (cx - r.x) ** 2 + (cy - r.y) ** 2 <= RING_RADIUS ** 2:
                s = r.active_slot(self.dash_beat)
                if s is not None and s not in r.used:
                    return r, s
        return None, None

    def on_dash_end(self):
        if self.pop:
            self.pop = False
            self.vy = -RING_POP

    def _move(self):
        if self.dash_t == DASH_TIME:
            self.dash_beat = self.beat
        if self.dash_t > 0:
            r, s = self._ring_hit()
            if r:
                r.used.add(s)
                self.dash_cd = 0.0
                self.air_dash = True
                self.pop = True
                self.events.append(("ring", round(self.beat, 3), round(self.x), round(self.y)))
        super()._move()


def _fresh(items, cls):
    return [cls(o.x, o.y, set(o.slots)) for o in items]


def to_presses(script):
    return [(b, {"orb": "jump", "ring": "dash"}.get(k, k), h) for (b, k, h) in script]


def simulate(solids, orbs, script, end_beat, start=START, right=1, rings=(), gates=(), platforms=()):
    sim = RingSim(start[0], start[1], solids, _fresh(orbs, Orb), _fresh(rings, Ring), start_beat=-0.5, gates=gates,
                  platforms=platforms)
    run(sim, to_presses(script), end_beat, right)
    return sim


def place_notes(start, solids, script, end_beat, right=1):
    """依標準節奏跑一次：'orb' 在按跳那一幀放音符，'ring' 在按衝刺那一幀放衝刺環（稍微偏前）"""
    orbs, rings = [], []
    sim = RingSim(start[0], start[1], solids, orbs, rings, start_beat=-0.5)
    presses = cap_holds([(round(b * SPB / DT), k, h) for (b, k, h) in script])
    frame = round(sim.beat * SPB / DT)
    end = round(end_beat * SPB / DT)
    while frame < end:
        jp = dp = held = False
        for (f0, kind, hold) in presses:
            if kind in ("jump", "orb"):
                if frame == f0:
                    jp = True
                    if kind == "orb":
                        orbs.append(Orb(sim.x, sim.y, {round(f0 * DT / SPB * 2)}))
                        sim.orbs.append(orbs[-1])
                if f0 <= frame < f0 + max(hold, 1):
                    held = True
            elif kind in ("dash", "ring") and frame == f0:
                dp = True
                if kind == "ring":
                    rings.append(Ring(sim.x + RING_AHEAD, sim.y, {round(f0 * DT / SPB * 2)}))
                    sim.rings.append(rings[-1])
        sim.step(right(sim.beat) if callable(right) else right, jp, held, dp)
        frame += 1
    return orbs, rings, sim


class Course:
    """一段關卡的完整描述：地形、音符、機關、終點"""

    def __init__(self, name, script, end_beat, start=START, right=1):
        self.name, self.script, self.end_beat = name, script, end_beat
        self.start, self.right = start, right
        self.solids, self.orbs, self.rings, self.lasers, self.pistons = [], [], [], [], []
        self.gates = []
        self.platforms, self.hazards = [], []
        self.goal = None  # (x_min, y_max)
        # 段落中間站過地面的時間 [(拍起, 拍迄)]，wait_check 用
        self.stands = []

    def sim(self, script=None, end_beat=None, extra=(), gates=None):
        return simulate(self.solids + list(extra), self.orbs, script or self.script,
                        end_beat or self.end_beat, self.start, self.right, self.rings,
                        self.gates if gates is None else gates, self.platforms)

    def outcome(self, script):
        sim = self.sim(script)
        hit = first_hit(sim, self.lasers, self.pistons, hazards=self.hazards)
        if hit:
            return hit
        if sim.x >= self.goal[0] and sim.y <= self.goal[1] and sim.on_floor:
            return None
        return ("沒到終點", round(sim.x), round(sim.y))

    def wait_check(self, strict):
        """在段落中間每個落腳處停下來等 4 拍或 8 拍（一或兩小節，音符和地形都回到同一個樣子）再照節奏接下去，
        都必須失敗：一路跑到底不能停"""
        plain_right = self.right
        bad = []
        for (b0, b1) in self.stands:
            stop = b0 + 0.1
            for w in (4.0, 8.0):
                sc = [(b + (w if b > stop else 0.0), k, h) for (b, k, h) in self.script]
                self.right = lambda b, s=stop, w=w: 0 if s <= b < s + w else 1
                res = self.outcome(sc)
                if res is None:
                    bad.append((round(b0, 2), w))
        self.right = plain_right
        print(f"  停下來等：{'每個落腳處都會失敗' if not bad else f'這些地方可以等 {bad}'}")
        assert not (strict and bad), (self.name, "可以停下來等", bad)

    def dash_check(self, strict):
        """把任何一下跳（含音符）改成在同一拍或前後半拍衝刺，都必須失敗：不能用衝刺取代音符"""
        bad = []
        for i, (b, k, h) in enumerate(self.script):
            if k not in ("jump", "orb"):
                continue
            for d in (-0.5, 0.0, 0.5):
                sc = list(self.script)
                sc[i] = (b + d, "dash", 0)
                if self.outcome(sc) is None:
                    bad.append((b, d))
        print(f"  跳改衝刺：{'都會失敗' if not bad else f'竟然過了！ {bad}'}")
        assert not (strict and bad), (self.name, "衝刺可以取代跳", bad)

    def orb_check(self, strict):
        """不碰某顆音符、改在前後動作之間任何一個半拍從地面跳（長按或輕點），都必須失敗：音符要真的有用"""
        bad = []
        beats = [b for (b, _, _) in self.script]
        for i, (b, k, h) in enumerate(self.script):
            if k != "orb":
                continue
            rest = self.script[:i] + self.script[i + 1:]
            lo = beats[i - 1] if i else -0.5
            hi = beats[i + 1] if i + 1 < len(beats) else b + 3.0
            c = lo + 0.5
            while c < hi:
                if c != b and any(self.outcome(sorted(rest + [(c, "jump", hh)])) is None for hh in (FULL, TAP)):
                    bad.append((b, c))
                c += 0.5
        if any(k == "orb" for (_, k, _) in self.script):
            print(f"  不碰音符改從地面跳：{'都會失敗' if not bad else f'竟然過了！ {bad}'}")
        assert not (strict and bad), (self.name, "音符可以不碰", bad)

    def ring_check(self, strict):
        """照樣在那拍衝刺、但拿掉衝刺環，必須失敗：環要真的有用（補回衝刺再衝一次，或靠環的上彈才到得了）"""
        rings = list(self.rings)
        bad = []
        for i, r in enumerate(rings):
            self.rings = rings[:i] + rings[i + 1:]
            if self.outcome(self.script) is None:
                bad.append(min(r.slots) / 2)
        self.rings = rings
        if rings:
            print(f"  拿掉衝刺環：{'都會失敗' if not bad else f'竟然過了！ {bad}'}")
        assert not (strict and bad), (self.name, "衝刺環沒有用", bad)

    def verify(self):
        base = self.outcome(self.script)
        print(f"  標準節奏：{'通過' if base is None else base}")
        assert base is None, self.name
        for i, (b, k, h) in enumerate(self.script):
            good = []
            chain = []
            for d in (-0.12, -0.08, -0.04, 0.04, 0.08, 0.12):
                sc = list(self.script)
                sc[i] = (b + d / SPB, k, h)
                if self.outcome(sc) is None:
                    good.append(d)
                sc = [(bb + (d / SPB if j >= i else 0.0), kk, hh) for j, (bb, kk, hh) in enumerate(self.script)]
                if self.outcome(sc) is None:
                    chain.append(d)
            label = {"jump": "長" if h >= FULL else "點", "orb": "音符長" if h >= FULL else "音符點",
                     "dash": "衝", "ring": "環衝"}[k]
            wrong = list(self.script)
            if k in ("dash", "ring"):
                del wrong[i]
                what = "不衝"
            else:
                wrong[i] = (b, k, TAP if h >= FULL else FULL)
                what = "改點" if h >= FULL else "改長"
            res = self.outcome(wrong)
            extra = ""
            if k in ("jump", "orb"):
                r2 = self.outcome(self.script[:i] + self.script[i + 1:])
                extra += f"  不跳 → {'竟然過了！' if r2 is None else r2}"
            if k == "ring" or (k == "dash" and self.gates):
                for d, name in ((-0.5, "早半拍"), (0.5, "晚半拍")):
                    sc = list(self.script)
                    sc[i] = (b + d, k, h)
                    r2 = self.outcome(sc)
                    extra += f"  {name} → {'竟然過了！' if r2 is None else r2}"
            print(f"  #{i} 第{b}拍 {label}：單鍵容許 {good}  之後一起偏 {chain}  {what} → {'竟然過了！' if res is None else res}{extra}")


def feet_cross(sim, y_feet, after_beat):
    prev = None
    for (b, x, y) in sim.log:
        if b >= after_beat and prev and prev[2] + 22 <= y_feet < y + 22:
            return x
        prev = (b, x, y)
    return None


def x_at(sim, beat):
    return min(sim.log, key=lambda e: abs(e[0] - beat))[1]


def place_pump_piston(course, chunk, pat, sim, beat, width_tiles=3):
    """衝刺從 beat 開始，活塞放在衝刺中段經過的位置；上方用光滑牆封住不能跳過。
    挑「衝刺提早／延後都還安全」範圍最大的位置"""
    x_mid = x_at(sim, beat + 0.2)
    best = None
    for col in range(int(x_mid // TILE) - 4, int(x_mid // TILE) + 2):
        P = Piston(col * TILE, 12 * TILE, width_tiles * TILE, 4 * TILE, PUMP["notes"])
        ceil = solid_rect(col, col + width_tiles - 1, 0, 11)
        passed = []
        for d in (0.0, -0.04, 0.04, -0.08, 0.08, -0.12, 0.12):
            sc = [(b + (d / SPB if b == beat and k == "dash" else 0.0), k, h) for (b, k, h) in course.script]
            s = course.sim(sc, beat + 1.5, [ceil])
            if first_hit(s, course.lasers, course.pistons + [P]) is None:
                passed.append(d)
            elif d == 0.0:
                break
        early = sum(1 for d in passed if d < 0)
        late = sum(1 for d in passed if d > 0)
        score = (len(passed), min(early, late)) if passed else 0
        if score and (best is None or score > best[0]):
            best = (score, col, P)
    assert best, ("piston", beat)
    _, col, P = best
    course.pistons.append(P)
    course.solids.append(solid_rect(col, col + width_tiles - 1, 0, 11))
    chunk.fill(col, col + width_tiles - 1, 0, 11, "%")
    chunk.fill(col, col + width_tiles - 1, 12, 15, pat.add(PUMP))
    return col


def place_crate(course, chunk, sim, beat, height_tiles=2):
    """長按跳過的木箱：放在跳躍弧線最高的地方"""
    top = 16 * TILE - height_tiles * TILE
    xs = [x for (b, x, y) in sim.log if beat < b < beat + 2 and y + 22 < top - 6]
    lo, hi = min(xs) + 12, max(xs) - 12
    c0 = int(-(-lo // TILE))
    c1 = int(hi // TILE) - 1
    mid = (c0 + c1) // 2
    c0, c1 = mid, min(mid + 1, c1)
    assert c1 >= c0, ("crate", beat)
    course.solids.append(solid_rect(c0, c1, 16 - height_tiles, 15))
    chunk.fill(c0, c1, 16 - height_tiles, 15, "%")
    return c0, c1
