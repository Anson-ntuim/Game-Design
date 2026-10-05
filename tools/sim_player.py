"""逐幀重現 player.gd 的移動物理，用來設計第二關：
給定一串「在第幾拍按跳／衝刺、按住幾幀」的輸入，算出角色在每個音符時間點的位置，
把節奏音符放在那裡，就能保證「照節奏按」剛好碰得到。

座標單位是 px，角色位置是身體中心（和 Godot 一樣）。拍子從 0 開始，BPM 120。
"""

from dataclasses import dataclass, field

DT = 1.0 / 120.0
SPB = 0.5
TILE = 40
BODY = (24.0, 44.0)
HURT = (18.0, 38.0)

RUN = 310.0
JUMP_SPEED = 560.0
JUMP_MIN = 0.08
JUMP_MAX = 0.2
GRAVITY = 2400.0
MAX_FALL = 760.0
COYOTE = 0.08
BUFFER = 0.1
ORB_SPEED = 560.0
ORB_MAX = 0.18
DASH_SPEED = 850.0
DASH_TIME = 0.2
DASH_COOLDOWN = 0.55
ORB_RADIUS = 22.0
ORB_EARLY = 0.12
ORB_LATE = 0.13


@dataclass
class Orb:
    x: float
    y: float
    slots: set  # 絕對半拍編號（非循環），設計用
    used: set = field(default_factory=set)

    def active_slot(self, beat):
        s0 = int(beat * 2 // 1)
        for s in (s0, s0 + 1, s0 - 1):
            if s in self.slots:
                dt = (beat - s * 0.5) * SPB
                if -ORB_EARLY <= dt <= ORB_LATE:
                    return s
        return None


class Sim:
    def __init__(self, x, y, solids, orbs=(), start_beat=0.0):
        self.x, self.y = x, y
        self.vx = self.vy = 0.0
        self.solids = list(solids)  # (left, top, right, bottom)
        self.orbs = list(orbs)
        self.beat = start_beat
        self.on_floor = False
        self.coyote = 0.0
        self.buffer = 0.0
        self.jumping = False
        self.elapsed = 0.0
        self.jspeed = 0.0
        self.jmax = 0.0
        self.cancelable = False
        self.air_dash = True
        self.dash_t = 0.0
        self.dash_cd = 0.0
        self.dash_dir = 1
        self.log = []
        self.events = []
        # 會出現／消失的單向平台：要有 left、right、top 與 solid(beat)
        self.platforms = []

    def _land_on(self, ny):
        """往下（或站著）時腳底跨過實體單向平台的頂面 → 回傳頂面 y"""
        if self.vy < 0:
            return None
        hw, hh = BODY[0] / 2, BODY[1] / 2
        for p in self.platforms:
            if self.x + hw > p.left and self.x - hw < p.right and self.y + hh <= p.top + 0.02 \
                    and ny + hh + 1.0 >= p.top and p.solid(self.beat):
                return p.top
        return None

    def _collide(self, nx, ny):
        hw, hh = BODY[0] / 2, BODY[1] / 2
        for (l, t, r, b) in self.solids:
            if nx + hw > l and nx - hw < r and ny + hh > t and ny - hh < b:
                return (l, t, r, b)
        return None

    def _move(self):
        hw, hh = BODY[0] / 2, BODY[1] / 2
        nx = self.x + self.vx * DT
        s = self._collide(nx, self.y)
        if s:
            nx = s[0] - hw - 0.01 if self.vx > 0 else s[2] + hw + 0.01
            self.vx = 0.0
        self.x = nx
        ny = self.y + self.vy * DT
        s = self._collide(self.x, ny)
        self.on_floor = False
        hit_ceiling = False
        if s:
            if self.vy > 0:
                ny = s[1] - hh - 0.01
                self.on_floor = True
            else:
                ny = s[3] + hh + 0.01
                hit_ceiling = True
            self.vy = 0.0
        else:
            top = self._land_on(ny)
            if top is not None:
                ny = top - hh - 0.01
                self.vy = 0.0
                self.on_floor = True
            # floor snap / 站著時檢查腳下
            elif self.vy >= 0 and self._collide(self.x, ny + 1.0):
                self.on_floor = True
        self.y = ny
        if hit_ceiling:
            self.jumping = False
            self.cancelable = False

    def _orb_overlap(self):
        hw, hh = HURT[0] / 2, HURT[1] / 2
        for o in self.orbs:
            cx = min(max(o.x, self.x - hw), self.x + hw)
            cy = min(max(o.y, self.y - hh), self.y + hh)
            if (cx - o.x) ** 2 + (cy - o.y) ** 2 <= ORB_RADIUS ** 2:
                s = o.active_slot(self.beat)
                if s is not None and s not in o.used:
                    return o, s
        return None, None

    def begin_jump(self, speed, max_time):
        self.jumping = True
        self.elapsed = 0.0
        self.jspeed = speed
        self.jmax = max_time
        self.cancelable = True
        self.vy = -speed
        self.buffer = 0.0
        self.coyote = 0.0

    def on_dash_end(self):
        pass

    def step(self, right=0, jump_pressed=False, jump_held=False, dash_pressed=False):
        self.coyote = max(0.0, self.coyote - DT)
        self.buffer = max(0.0, self.buffer - DT)
        self.dash_cd = max(0.0, self.dash_cd - DT)
        if self.dash_t > 0:
            self.dash_t -= DT
            if self.dash_t <= 0:
                self.dash_t = 0
                self.vx = self.vy = 0.0
                self.on_dash_end()
        on_floor = self.on_floor
        if on_floor:
            self.coyote = COYOTE
            self.air_dash = True
        if jump_pressed:
            self.buffer = BUFFER
        if dash_pressed and self.dash_cd <= 0 and (on_floor or self.air_dash):
            self.dash_t = DASH_TIME
            self.dash_cd = DASH_COOLDOWN
            self.dash_dir = 1 if right >= 0 else -1
            if not on_floor:
                self.air_dash = False
            self.jumping = False
            self.cancelable = False
            self.events.append(("dash", round(self.beat, 3), round(self.x), round(self.y)))
        if self.dash_t > 0:
            self.vx, self.vy = self.dash_dir * DASH_SPEED, 0.0
            self._move()
            self._advance()
            return
        self.vx = right * RUN
        if self.buffer > 0:
            if on_floor or self.coyote > 0:
                self.begin_jump(JUMP_SPEED, JUMP_MAX)
                self.events.append(("jump", round(self.beat, 3), round(self.x), round(self.y)))
            else:
                o, s = self._orb_overlap()
                if o:
                    o.used.add(s)
                    self.air_dash = True
                    self.begin_jump(ORB_SPEED, ORB_MAX)
                    self.events.append(("orb", round(self.beat, 3), round(self.x), round(self.y)))
        if self.jumping:
            self.elapsed += DT
            holding = jump_held or not self.cancelable
            if self.elapsed < JUMP_MIN or (holding and self.elapsed < self.jmax):
                self.vy = -self.jspeed
            else:
                self.jumping = False
                if not holding:
                    self.vy = 0.0
        else:
            self.vy = min(self.vy + GRAVITY * DT, MAX_FALL)
            if self.cancelable and self.vy < 0 and not jump_held:
                self.vy = 0.0
            if self.vy >= 0:
                self.cancelable = False
        self._move()
        self._advance()

    def _advance(self):
        self.beat += DT / SPB
        self.log.append((self.beat, self.x, self.y))


def run(sim, script, end_beat, right=1):
    """script: [(beat, 'jump', hold_frames) | (beat, 'dash', 0)]，right 可為函式 beat -> -1/0/1"""
    presses = cap_holds([(round(b * SPB / DT), kind, hold) for (b, kind, hold) in script])
    frame = round(sim.beat * SPB / DT)
    end = round(end_beat * SPB / DT)
    while frame < end:
        jp = dp = False
        held = False
        for (f0, kind, hold) in presses:
            if kind == "jump":
                if frame == f0:
                    jp = True
                if f0 <= frame < f0 + max(hold, 1):
                    held = True
            elif kind == "dash" and frame == f0:
                dp = True
        r = right(sim.beat) if callable(right) else right
        sim.step(r, jp, held, dp)
        frame += 1
    return sim


def cap_holds(presses):
    """真人按下一次跳之前一定先放開：每次按住最多到下一次按跳的前一幀"""
    presses = sorted(presses)
    jumps = [f for (f, k, _) in presses if k in ("jump", "orb")]
    out = []
    for (f0, kind, hold) in presses:
        nxt = [f for f in jumps if f > f0]
        if kind in ("jump", "orb") and nxt:
            hold = min(hold, nxt[0] - f0 - 1)
        out.append((f0, kind, hold))
    return out


def pos_at(sim, beat):
    best = min(sim.log, key=lambda e: abs(e[0] - beat))
    return best[1], best[2]


def ground(l_tile, r_tile, top_row=16, bottom_row=20):
    return (l_tile * TILE, top_row * TILE, r_tile * TILE, bottom_row * TILE)
