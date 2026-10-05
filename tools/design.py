"""關卡設計輔助：依照一段節奏自動放置音符，並測試按鍵誤差的容忍度。"""

from sim_player import Sim, Orb, run, cap_holds, DT, SPB, TILE

TAP = 4
FULL = 60


def place_orbs(start, solids, script, end_beat, right=1, start_beat=-0.5):
    """script: [(beat, kind, hold)]；kind = 'jump'（地面起跳）、'orb'（在這拍放音符並按跳）、'dash'。
    回傳 (orbs, sim)。音符放在角色在該拍的位置。"""
    orbs = []
    presses = [(f0 * DT / SPB, k, h) for (f0, k, h) in cap_holds([(round(b * SPB / DT), k, h) for (b, k, h) in script])]
    sim = Sim(start[0], start[1], solids, orbs, start_beat=start_beat)
    frame = round(start_beat * SPB / DT)
    end = round(end_beat * SPB / DT)
    while frame < end:
        jp = dp = held = False
        for (b, kind, hold) in presses:
            f0 = round(b * SPB / DT)
            if kind in ("jump", "orb"):
                if frame == f0:
                    jp = True
                    if kind == "orb":
                        orbs.append(Orb(sim.x, sim.y, {round(b * 2)}))
                        sim.orbs.append(orbs[-1])
                if f0 <= frame < f0 + max(hold, 1):
                    held = True
            elif kind == "dash" and frame == f0:
                dp = True
        r = right(sim.beat) if callable(right) else right
        sim.step(r, jp, held, dp)
        frame += 1
    return orbs, sim


def replay(start, solids, orbs, script, end_beat, right=1, start_beat=-0.5):
    fresh = [Orb(o.x, o.y, set(o.slots)) for o in orbs]
    sim = Sim(start[0], start[1], solids, fresh, start_beat=start_beat)
    sc = [(b, "jump" if k in ("jump", "orb") else k, h) for (b, k, h) in script]
    run(sim, sc, end_beat, right)
    return sim


def tolerance(start, solids, orbs, script, end_beat, goal, right=1):
    """每個按鍵單獨提早／延後、按住長短改變時，是否還能到達 goal(x_min, y_max)。"""
    ok = lambda s: s.x >= goal[0] and s.y <= goal[1] and s.on_floor
    base = replay(start, solids, orbs, script, end_beat, right)
    print("  nominal:", "OK" if ok(base) else "FAIL", round(base.x), round(base.y))
    for i, (b, k, h) in enumerate(script):
        good = []
        for d in (-0.16, -0.12, -0.08, -0.04, 0.04, 0.08, 0.12, 0.16):
            sc = list(script)
            sc[i] = (b + d / SPB, k, h)
            if ok(replay(start, solids, orbs, sc, end_beat, right)):
                good.append(d)
        holds = []
        for hh in (TAP, 10, 16, 20, 24, 30, 40, FULL):
            sc = list(script)
            sc[i] = (b, k, hh)
            if ok(replay(start, solids, orbs, sc, end_beat, right)):
                holds.append(hh)
        print(f"  #{i} {k}@{b}: 時間容許 {good}  按住幀數可行 {holds}")


def show(orbs, x0_tiles):
    out = []
    for o in orbs:
        s = sorted(o.slots)[0]
        out.append((round(o.x / TILE - x0_tiles, 2), round(o.y / TILE, 2), s))
    return out


def notes_for(slot, length=16):
    n = ["."] * length
    n[slot % length] = "x"
    return "".join(n)
