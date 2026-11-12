"""共用的段落產生器（tools/gen_demo.py 用）：給一串標準節奏（超過 8 拍時旗子只示範第一小節），自動算出地形與機關。

  1. 在無限地面上照標準節奏跑一次，音符放在按跳那一幀、衝刺環放在按衝刺那一幀
  2. 角色踩到地面的地方變成小島，其餘挖空成坑
  3. 輕點音符上方加橫向雷射（長按會撞上，平行音符合成一條）；指定的衝刺拍加光牆、地面衝刺加活塞、地面長跳加木箱
  4. 用 gen_level3 的驗證逐一測試提早／延後／按錯
  5. 休止（rests）：從正拍開始、剛好一拍或兩拍；標準節奏在休止拍放開方向鍵站著不動，
     站住的地方往前多鋪一格地面，晚一點停也不會掉坑
  6. 休止區／盲拍區從旗子後兩格鋪到終點小島前（rest_zone.gd、blind_zone.gd）
  7. floor 決定段落中間的落腳處：pit 實心小島、melody 只在踩到時亮起的旋律平台、beat 黃藍輪流的節拍平台、
     ground 整段地面（搭配 spikes 這幾拍整排一起彈出的尖刺、fixed_spikes 要長按才跳得過的固定尖刺；
     空中有音符、衝刺或衝刺環的那一跳底下挖空）。
     floor 也可以給 [(種類, 比地面高幾格, 起跳幾次)]：有高低差的落腳處（stepped_islands），種類多一個 row
     （整座島鋪滿尖刺，在島上的每一下起跳那拍彈出）
  8. 檢查在中間落腳處停下來等一兩小節、把跳改成衝刺、不碰音符改從地面跳、拿掉衝刺環都會失敗；
     flow = True 時不允許例外
"""

from sim_player import TILE, SPB, DASH_TIME, ground
from design import show, TAP, FULL
from gen_level3 import (
    START, Chunk, Course, Gate, Laser, LASER_HALF, place_notes, place_pump_piston, place_crate,
    feet_cross, x_at, solid_rect, beats_notes, notes_for, first_hit,
    MelodyPlatform, BeatPlatform, PatternSpike, FixedSpike,
)
from level_kit import flag_spec, ghost_for, ghost_points, demo_char

GROUND_Y = 617.5
## 和 rest_zone.gd 相同：休止開始後多久開始判定
REST_GRACE = 0.2
REST_END_GRACE = 0.25
ZONE_FROM = 7


def rest_notes(rests):
    n = ["."] * 16
    for (r0, r1) in rests:
        for s in range(round(r0 * 2), round(r1 * 2)):
            n[s % 16] = "x"
    return "".join(n)


def rest_right(rests, script=()):
    """休止拍放開方向鍵；休止尾巴（最後半拍內）提早按了動作，就從按的那一刻開始跑（真人會一起按）"""
    if not rests:
        return 1
    spans = []
    for (r0, r1) in rests:
        early = [b for (b, _, _) in script if r1 - 0.5 <= b < r1]
        spans.append((r0, min([r1] + early)))
    return lambda b: 0 if any(r0 <= b < r1 for (r0, r1) in spans) else 1


def rest_violation(sim, rests, zone_x0, zone_x1):
    """休止區內的休止拍（寬限後）還在空中或還在走 → ("搶拍", 拍)；和 rest_zone.gd 相同"""
    notes = rest_notes(rests)
    prev = None
    for (b, x, y) in sim.log:
        judged = all(notes[int((b + d) * 2) % 16] == "x" for d in (0.0, -REST_GRACE, REST_END_GRACE))
        if judged and zone_x0 <= x <= zone_x1 and prev is not None:
            if y < GROUND_Y or abs(x - prev[1]) > 0.01:
                return ("搶拍", round(b, 2))
        prev = (b, x, y)
    return None


def contacts(sim):
    """角色站在地面（y = 617.99）的連續區間：[(x 起, x 迄, 拍起, 拍迄)]"""
    out = []
    cur = None
    for (b, x, y) in sim.log:
        if y >= GROUND_Y:
            if cur is None:
                cur = [x, x, b, b]
            cur[1], cur[3] = x, b
        elif cur is not None:
            out.append(tuple(cur))
            cur = None
    if cur is not None:
        out.append(tuple(cur))
    return out


def landing_contacts(sim, script):
    """只留「真的要落地起跳／起點／終點」的站立區間。
    黃音符／衝刺空中鏈途中擦到地面的短接觸不蓋島，避免「球底下還有一塊多餘平台」。"""
    spans = contacts(sim)
    if len(spans) <= 2:
        return spans
    jumps = [b for (b, k, _) in script if k == "jump"]
    kept = [spans[0]]
    for sp in spans[1:-1]:
        _x0, _x1, b0, b1 = sp
        ## 這段站立上有譜面起跳 → 需要平台
        if any(b0 - 0.02 <= jb <= b1 + 0.12 for jb in jumps):
            kept.append(sp)
            continue
        ## 明顯站住（超過大半拍）也可能是緩衝落點，保留
        if b1 - b0 >= 0.55:
            kept.append(sp)
    kept.append(spans[-1])
    ## 去重並維持左到右
    out = []
    for sp in kept:
        if not out or sp[2] > out[-1][3] + 0.01:
            out.append(sp)
        else:
            x0, x1, b0, b1 = out[-1]
            out[-1] = (x0, max(x1, sp[1]), b0, max(b1, sp[3]))
    return out


def place_row_lasers(course, chunk, pat, taps, script):
    """輕點音符上方的橫向雷射。同一列上相鄰的輕點（平行音符）合成一條，
    每個音符那拍和後半拍都發射，長按不管在哪一顆都會撞上。
    最後一顆之後半拍內接著長按的話，不發最後那一下（不然會打到往上衝的自己）"""
    holds = [b for (b, k, h) in script if k in ("orb", "jump") and h >= FULL]
    def row_in(lo, hi):
        row = -(-(lo - 20) // TILE)
        return row if row * TILE + 20 <= hi else None

    groups = []
    for (b, o) in sorted(taps, key=lambda t: t[0]):
        lo, hi = int(o.y) - 160, int(o.y) - 120
        c0, c1 = int((o.x - 14) // TILE), int((o.x + 150) // TILE)
        g = groups[-1] if groups else None
        if g and c0 <= g["c1"] + 1 and row_in(max(lo, g["lo"]), min(hi, g["hi"])) is not None:
            g["lo"], g["hi"] = max(lo, g["lo"]), min(hi, g["hi"])
            g["c1"] = c1
            g["beats"] += [b, b + 0.5]
        else:
            groups.append({"lo": lo, "hi": hi, "c0": c0, "c1": c1, "beats": [b, b + 0.5]})
    for g in groups:
        last = g["beats"][-1]
        if any(last - 0.5 < h <= last + 0.25 for h in holds):
            g["beats"].pop()
        row = row_in(g["lo"], g["hi"])
        assert row is not None and row >= 1, ("laser row", g)
        y = row * TILE + 20
        notes = beats_notes(g["beats"])
        course.lasers.append(Laser((g["c0"] * TILE, y - LASER_HALF, (g["c1"] + 1) * TILE, y + LASER_HALF), notes))
        chunk.fill(g["c0"], g["c1"], row, row, pat.add({"kind": "laser", "notes": notes}))


def gate_column(sim, beat):
    """光牆放在衝刺開始後約 0.05 秒碰到的位置，並確認整段重疊都在這次衝刺途中（衝刺 0.2 秒）"""
    x_hit = x_at(sim, beat + 0.1) + 12
    col = int((x_hit - 10) // TILE)
    left, right = col * TILE + 10, col * TILE + 30
    touching = [b for (b, x, y) in sim.log if x + 12 > left and x - 12 < right]
    lo, hi = (min(touching) - beat) * SPB, (max(touching) - beat) * SPB
    assert 0.0 <= lo and hi <= 0.2, ("gate", beat, col, lo, hi)
    return col


def melody_notes(b0, b1):
    """旋律平台在角色落地前一點亮起、起跳後一點熄滅（16 格循環）"""
    s0, s1 = int((b0 - 0.3) * 2 // 1), -int(-(b1 + 0.25) * 2 // 1)
    assert s1 - s0 < 12, ("旋律平台亮太久", b0, b1)
    n = ["."] * 16
    for s in range(s0, s1):
        n[s % 16] = "x"
    return "".join(n)


def place_fixed_spikes(course, chunk, sim, beat, most=3):
    """長按跳過的固定尖刺：放在跳躍弧線夠高的範圍正中間，最多 most 格"""
    top = 16 * TILE - 22
    xs = [x for (b, x, y) in sim.log if beat < b < beat + 2 and y + 19 < top - 4]
    lo, hi = min(xs) + 9, max(xs) - 9
    c0, c1 = -int(-(lo - 4) // TILE), int((hi - 36) // TILE)
    assert c1 - c0 >= 1, ("fixed spikes", beat)
    while c1 - c0 + 1 > most:
        c0, c1 = (c0 + 1, c1) if (c1 - c0) % 2 else (c0, c1 - 1)
    for c in range(c0, c1 + 1):
        course.hazards.append(FixedSpike(c, 15))
        chunk.fill(c, c, 15, 15, "^")


def contacts_on(sim, top, x_from):
    """站在頂面為 top 列的地面上、x_from 右邊的連續區間：[(x 起, x 迄, 拍起, 拍迄)]"""
    y_stand = top * TILE - 22.01
    out = []
    cur = None
    for (b, x, y) in sim.log:
        if abs(y - y_stand) < 0.5 and x >= x_from:
            if cur is None:
                cur = [x, x, b, b]
            cur[1], cur[3] = x, b
        elif cur is not None:
            out.append(tuple(cur))
            cur = None
    if cur is not None:
        out.append(tuple(cur))
    return out


def island_rect(c0, c1, top, kind):
    """蓋地形時的實體：實心小島整根到底；旋律／節拍平台只有一格厚"""
    return solid_rect(c0, c1, top, 19 if kind in ("pit", "row", "final") else top)


def stepped_islands(script, steps, end_beat, right, final_top):
    """有高低差的落腳處，從左到右一個一個蓋：先讓角色從上一個島往下掉，
    腳底往下穿過這個島面高度的地方當左緣，再讓島往右無限延伸跑到起跳，最後一次起跳決定右緣。
    steps: 每個中間落腳處 (種類, 比地面高幾格, 在上面站幾次)，站幾次 = 用掉幾下地面跳。
    回傳 islands [c0, c1, 拍起, x 起, 拍迄, 頂面列, 種類, [站的區間]]（第一個是起點、最後一個是終點）"""
    jumps = [b for (b, k, _) in script if k == "jump"]
    assert sum(n for (_, _, n) in steps) == len(jumps) - 1, ("steps 站的次數和地面跳對不上", len(jumps) - 1)
    _, _, sim = place_notes(START, [ground(0, 400)], script, end_beat, right)
    x0, x1, b0, b1 = contacts(sim)[0]
    c1 = int((x1 + 12) // TILE)
    islands = [[0, c1, b0, x0, b1, 16, "pit", []]]
    solids = [solid_rect(0, c1, 16, 19)]
    j = 1
    for (kind, rise, n) in list(steps) + [("final", 16 - final_top, 0)]:
        top = 16 - rise
        nxt = jumps[j] if kind != "final" else None
        air = [(b, k) for (b, k, _) in script if k != "jump" and jumps[j - 1] < b and (nxt is None or b < nxt)]
        after = jumps[j - 1]
        if air:
            b, k = air[-1]
            after = b + (0.45 if k in ("dash", "ring") else 0.0)
        _, _, fall = place_notes(START, solids, script, end_beat, right)
        x_cross = feet_cross(fall, top * TILE, after)
        assert x_cross is not None, ("掉不到這個高度", kind, rise, after)
        found = None
        for c0 in (int((x_cross - 12) // TILE) - 1, int((x_cross - 12) // TILE)):
            if c0 * TILE <= islands[-1][1] * TILE + 2 * TILE:
                continue
            catch = island_rect(c0, c0 + 400, top, kind)
            orbs, rings, s = place_notes(START, solids + [catch], script, end_beat, right)
            spans = contacts_on(s, top, c0 * TILE - 12)
            # 左緣太前面會擋到上升的弧線（撞到牆或頭頂），落地點就會跑掉
            if spans and abs(spans[0][0] - x_cross) < 6 and len(spans) >= n:
                found = (c0, spans)
                break
        assert found, ("落腳處擺不下（離上一個島太近或擋到跳躍弧線）", kind, rise, round(x_cross))
        c0, spans = found
        if nxt is not None:
            assert spans[0][2] < nxt - 0.1, ("落地太晚，來不及在拍子上起跳", kind, rise, round(spans[0][2], 2), nxt)
        if kind == "final":
            islands.append([c0, c0 + 60, spans[0][2], spans[0][0], spans[0][3], top, kind, []])
            break
        mine = spans[:n]
        c1 = int((mine[-1][1] + 12) // TILE)
        islands.append([c0, c1, mine[0][2], mine[0][0], mine[-1][3], top, kind, [(s[2], s[3]) for s in mine]])
        solids.append(island_rect(c0, c1, top, kind))
        j += n
    return islands, orbs, rings, s


def _floor_kinds(floor):
    if isinstance(floor, str):
        return {floor}
    if isinstance(floor, (list, tuple)) and floor:
        if isinstance(floor[0], tuple):
            return {step[0] for step in floor}
        return set(floor)
    return set()


def section(pat, name, script, hint, *, gates=(), pistons=(), crates=(), lasers=True,
            orb_tones=(12, 15, 19, 17, 22, 24, 27), ring_tones=(19, 24, 27), finale=False, wave=False,
            rests=(), strict=True, blind=None, bpm=None, floor="pit", spikes=(), fixed_spikes=(),
            melody_tones=(0, 3, 7, 10, 12, 15, 19, 22), flow=False, final_rise=0, gravity=None,
            gravity_flip=None, island_spikes=True, flag=None, audit_air=False, require_ring_use=True,
            compact_islands=False, score_beats=None, orb_footholds=False):
    """rests: [(起拍, 迄拍)] 休止；strict = False 搶拍只發出錯音。
    blind: {"notes": 16 格, "strobe": bool} 盲拍區。bpm: 走進這段時換成的速度。
    floor: pit／melody／beat／ground，或有高低差的 [(種類, 高幾格, 起跳幾次)]（見檔頭）。spikes: ground 整排地板尖刺彈出的拍子（要在這幾拍跳起來）；
    fixed_spikes: 在這些拍長按跳過的固定尖刺（ground 才有地面可以放）。
    final_rise: 終點小島墊高幾格、靠坑那面是光滑牆，最後一跳不能用地面衝刺代替
    gravity: 模擬／寫入區塊的重力（px/s²）；None = 用 sim_player 預設 2400
    gravity_flip: (拍, 另一重力) — 以該拍的 x 為界，後半改成另一重力（給空中穿越切換）
    island_spikes: False 時坑島不鋪「落地後彈出」的防站樁尖刺（第五關用黃音符主導時關掉）
    flag: 是否放起跳旗。None = 自動：只要段落裡有要對拍的音符／環／光柱，或 flow／休止／尖刺／消失平台，就放旗
    orb_footholds: True 時黃球附近不鋪站台（含近地擦觸），靠踩球前進；有地面起跳的落點仍保留"""
    import sim_player
    _old_g = sim_player.GRAVITY
    if gravity is not None:
        sim_player.GRAVITY = float(gravity)
    try:
        return _section_body(
            pat, name, script, hint, gates=gates, pistons=pistons, crates=crates, lasers=lasers,
            orb_tones=orb_tones, ring_tones=ring_tones, finale=finale, wave=wave, rests=rests,
            strict=strict, blind=blind, bpm=bpm, floor=floor, spikes=spikes, fixed_spikes=fixed_spikes,
            melody_tones=melody_tones, flow=flow, final_rise=final_rise, gravity=gravity,
            gravity_flip=gravity_flip, island_spikes=island_spikes, flag=flag, audit_air=audit_air,
            require_ring_use=require_ring_use, compact_islands=compact_islands, score_beats=score_beats,
            orb_footholds=orb_footholds)
    finally:
        sim_player.GRAVITY = _old_g


def _section_body(pat, name, script, hint, *, gates=(), pistons=(), crates=(), lasers=True,
            orb_tones=(12, 15, 19, 17, 22, 24, 27), ring_tones=(19, 24, 27), finale=False, wave=False,
            rests=(), strict=True, blind=None, bpm=None, floor="pit", spikes=(), fixed_spikes=(),
            melody_tones=(0, 3, 7, 10, 12, 15, 19, 22), flow=False, final_rise=0, gravity=None,
            gravity_flip=None, island_spikes=True, flag=None, audit_air=False, require_ring_use=True,
            compact_islands=False, score_beats=None, orb_footholds=False):
    kinds = _floor_kinds(floor)
    if kinds & {"melody", "beat"}:
        assert not any(k == "orb" for (_, k, _) in script), (
            name, "消失平台（旋律／節拍）上不要再放音符，意義重疊")
    if "ground" in kinds:
        assert not any(k == "orb" for (_, k, _) in script), (
            name, "平面地面可直接跳，不要再放黃色音符")
        assert not any(k in ("dash", "ring") for (_, k, _) in script), (
            name, "平面段落不要放地面衝刺／穿環，衝刺只留在空中")
    for (r0, r1) in rests:
        assert r0 == int(r0) and r1 - r0 in (1, 2), ("休止要從正拍開始、剛好一拍或兩拍", r0, r1)
    last = max(b for (b, _, _) in script)
    end_beat = max(last + 6, float(score_beats or 0) + 1)
    right = rest_right(rests, script)
    course = Course(name, script, end_beat, right=right)
    if rests:
        plain_sim = course.sim

        def sim_with_rests(sc=None, end=None, extra=(), gates=None):
            course.right = rest_right(rests, sc or script)
            return plain_sim(sc, end, extra, gates)
        course.sim = sim_with_rests
    ch = Chunk(10)
    stepped = isinstance(floor, (list, tuple)) and floor and isinstance(floor[0], tuple)
    if stepped:
        islands, course.orbs, course.rings, sim = stepped_islands(script, floor, end_beat, right, 16 - final_rise)
        *mid, final = islands
        course.stands = [st for isl in mid for st in isl[7]]
        kinds = [isl[6] for isl in mid[1:]]
    else:
        course.orbs, course.rings, sim = place_notes(START, [ground(0, 400)], script, end_beat, right)
        # 踩到地面的區間 → 小島（第一個是起點地面）
        spans = contacts(sim)
        jumps = [b for (b, k, _) in script if k == "jump"]
        islands = []
        for i, (x0, x1, b0, b1) in enumerate(spans):
            c0 = 0 if i == 0 else (int((x0 + 8) // TILE) if compact_islands else int((x0 - 12) // TILE) - 1)
            c1 = max(c0, int((x1 - 8 if compact_islands else x1 + 12) // TILE))
            if compact_islands and i > 0:
                previous = [k for b, k, h in script if b < b0]
                if previous and previous[-1] in ("orb", "ring", "dash"):
                    # 空中連招的落點多留一格接住實際碰撞／幀邊界誤差；短跳缺口仍維持窄邊。
                    c0 -= 1
            ## 正上方有黃音符、且這裡不起跳 → 不蓋島（有球走球）
            ## 預設近地擦觸仍保留；orb_footholds 連近地也不鋪，靠踩球前進
            if i > 0 and i < len(spans) - 1:
                has_jump = any(b0 - 0.02 <= jb <= b1 + 0.12 for jb in jumps)
                near_orbs = any(
                    c0 * TILE - 24 <= o.x <= (c1 + 1) * TILE + 24
                    for o in course.orbs)
                high_orbs = any(
                    c0 * TILE - 24 <= o.x <= (c1 + 1) * TILE + 24 and o.y < 16 * TILE - 100
                    for o in course.orbs)
                if not has_jump and (high_orbs or (orb_footholds and near_orbs)):
                    continue
            if not compact_islands and islands and c0 <= islands[-1][1] + 2:
                ## 中間若跳過球路假島，兩端不要併成一條大道
                if islands[-1][4] < b0 - 0.4:
                    islands.append([c0, c1, b0, x0, b1, 16])
                else:
                    islands[-1][1] = max(islands[-1][1], c1)
                    islands[-1][4] = b1
            else:
                islands.append([c0, c1, b0, x0, b1, 16])
        for (r0, _) in rests:
            xs = x_at(sim, r0 + 0.3)
            for isl in islands:
                if isl[0] * TILE <= xs + 12 and xs - 12 <= (isl[1] + 1) * TILE:
                    isl[1] = max(isl[1], int((xs + 12 + TILE) // TILE))
        *mid, final = islands
        course.stands = [(b0, b1) for (_, _, b0, b1) in spans[1:-1]
                         if any(b0 - 0.02 <= jb <= b1 + 0.12 for jb in jumps) or b1 - b0 >= 0.55]
        n_kind = max(1, len(mid) - 1)
        if isinstance(floor, str):
            kinds = [floor] * n_kind
        elif isinstance(floor, (list, tuple)) and floor and not isinstance(floor[0], tuple):
            kinds = (list(floor) + [floor[-1]] * n_kind)[:n_kind]
        else:
            kinds = [floor] * n_kind
    course.solids = []
    # 站在實心地面上的時間和島面列（之後在腳下放離開後才彈出的尖刺）
    ground_stands = [(b0, b1, 16) for (b0, b1) in course.stands] if floor == "ground" else []
    spike_beats = {}
    if floor == "ground":
        mid = mid[:1]
    for i, (c0, c1, b0, _, b1, top, *_) in enumerate(mid):
        kind = "pit" if i == 0 else kinds[i - 1]
        if kind in ("pit", "row"):
            course.solids.append(solid_rect(c0, c1, top, 19))
            ch.fill(c0, c1, top, 19, "#")
            if c0 > 0:
                ch.fill(c0, c0, top, 19, "%")
            if c0 > 0 and kind == "pit" and island_spikes:
                ground_stands += [(s0, s1, top) for (s0, s1) in course.stands
                                  if c0 * TILE <= x_at(sim, s0) <= (c1 + 1) * TILE]
            elif kind == "row":
                # 整排尖刺：在島上的每一下起跳那拍彈出（人要在空中），最後一下起跳後半拍再彈一次，停下來會被刺到
                js = [b for (b, k, _) in script if k == "jump" and b0 - 0.01 <= b <= b1 + 0.05]
                for c in range(c0 + 1, c1 + 1):
                    spike_beats.setdefault((c, top - 1), set()).update(js[:-1] + [js[-1] + 0.5])
        elif kind == "melody":
            notes = melody_notes(b0, b1)
            course.platforms.append(MelodyPlatform(c0, c1, top, notes))
            tone = melody_tones[(i - 1) % len(melody_tones)]
            ch.fill(c0, c1, top, top, pat.add({"kind": "platform", "notes": notes, "tone": tone}))
        elif kind == "beat":
            groups = [g for g in (0, 1) if BeatPlatform.window_has(g, b0 - 0.1, b1 + 0.15)]
            assert groups, ("節拍平台：落地到起跳跨過了交接", name, round(b0, 2), round(b1, 2))
            course.platforms.append(BeatPlatform(c0, c1, top, groups[0]))
            ch.fill(c0, c1, top, top, "AB"[groups[0]])
    if finale:
        assert final[5] == 16, ("安可舞台前的終點島要在地面高度", name)
        t_land, land = final[2], final[3]
        lc = int((land - 12) // TILE)
        first = int(t_land) + 1
        lift_notes = ["."] * 16
        for i in range(3):
            lift_notes[((first + i) % 8) * 2] = "x"
        lift_notes[((first - 4) % 8) * 2] = "v"
        ch.fill(lc, lc + 2, 10, 15, pat.add({"kind": "lift", "notes": "".join(lift_notes), "tone": 7}))
        ch.fill(lc - 1, lc - 1, 16, 19, "%")
        ch.fill(lc, lc + 2, 16, 19, "#")
        ch.fill(lc + 3, lc + 12, 10, 19, "%")
        ch.fill(lc + 8, lc + 8, 9, 9, "G")
        if wave:
            ch.fill(lc - 1, lc - 1, 15, 15, "Y")
            ch.fill(7, 7, 15, 15, "W")
        course.solids += [solid_rect(lc - 1, lc + 2, 16, 19), solid_rect(lc + 3, lc + 12, 10, 19)]
        course.goal = (lc * TILE + 12, 16 * TILE)
        zone_end = lc - 1
    else:
        lc = final[0]
        top = 16 - final_rise
        if final_rise and not stepped:
            # 牆面要在角色往下掉、腳還高過島面的範圍內，跳過去才落得上島；提早 0.12 秒起跳整條弧線前移約 37px
            x_down = max(x for (b, x, y) in sim.log if last < b < last + 2.5 and y + 22 <= top * TILE - 2)
            lc = int((x_down - 28) // TILE)
            # 空中連衝結尾：落點對齊最後一下衝刺末端，避免衝完還要再滑一大段才踩得到
            if script and script[-1][1] in ("dash", "ring"):
                b_dash = float(script[-1][0])
                dash_end = b_dash + DASH_TIME / SPB
                xs = [x for (b, x, y) in sim.log if b_dash - 0.02 <= b <= dash_end + 0.04]
                if xs:
                    # 島面伸進衝刺後段約 1.5 格，三下都按到時人已經在島上
                    lc = min(lc, int((xs[-1] - 60) // TILE))
            assert not mid or lc > mid[-1][1] + 1, ("墊高的終點島和前一個落腳處重疊", name)
        ch.fill(lc, lc, top, 19, "%")
        tail_col = max(lc + 7, int(x_at(sim, score_beats) // TILE) + 3) if score_beats else lc + 7
        ch.fill(lc + 1, tail_col, top, 19, "#")
        course.solids.append((lc * TILE, top * TILE, (lc + 60) * TILE, 20 * TILE))
        course.goal = (lc * TILE + 12, 16 * TILE)
        zone_end = lc
    if floor == "ground":
        # 空中有音符、衝刺或衝刺環的那一跳底下挖空：只靠地面跳就會掉下去，音符和衝刺一定要用
        holes = [(a[1] + 1, b[0] - 1) for a, b in zip(islands, islands[1:])
                 if any(k != "jump" and a[4] < bb < b[2] for (bb, k, _) in script)]
        edges = [0] + [h1 + 1 for (_, h1) in holes]
        for c0, c1 in zip(edges, [h0 - 1 for (h0, _) in holes] + [lc - 1]):
            if c1 < c0:
                continue
            course.solids.append(solid_rect(c0, c1, 16, 19))
            ch.fill(c0, c1, 16, 19, "#")
            if c0 > 0:
                ch.fill(c0, c0, 16, 19, "%")
    kinds_now = _floor_kinds(floor)
    if flag is None:
        ## 有要對拍的黃音符／衝刺環／光柱，或必須卡拍出發的地形 → 一定放旗
        timed_notes = any(k in ("orb", "ring") for (_, k, _) in script)
        flag = bool(
            timed_notes or gates or flow or rests or spikes or fixed_spikes
            or (kinds_now & {"melody", "beat"}))
    if flag:
        demo = script if score_beats else [s for s in script if s[0] < 8]
        slots = round(score_beats * 2) if score_beats else 16
        ch.fill(5, 5, 15, 15, pat.add(flag_spec(demo, rests, slots=slots)))

    sim = course.sim()
    if spikes:
        # 整排尖刺一起在 spikes 這幾拍彈出：從第一拍前半拍跑到的地方鋪到最後一拍之後，那幾拍人一定要在空中
        for c in range(int(x_at(sim, min(spikes) - 0.5) // TILE), int(x_at(sim, max(spikes) + 1.25) // TILE) + 1):
            if ch.rows[16][c] != " ":
                spike_beats[(c, 15)] = set(spikes)
        ground_stands = []
    # 實心地面上的落腳處：起跳後半拍整片彈出尖刺，停下來等就會被刺到
    for (b0, b1, top) in ground_stands:
        for c in range(int((x_at(sim, b0) - 16) // TILE), int((x_at(sim, b1) - 4) // TILE) + 1):
            spike_beats.setdefault((c, top - 1), set()).add(b1 + 0.5)
    for (col, row), beats in sorted(spike_beats.items()):
        notes = beats_notes(beats)
        course.hazards.append(PatternSpike(col, row, notes))
        ch.fill(col, col, row, row, pat.add({"kind": "spike", "notes": notes}))
    for b in fixed_spikes:
        place_fixed_spikes(course, ch, sim, b)
    for b in pistons:
        place_pump_piston(course, ch, pat, sim, b)
        sim = course.sim()
    for b in crates:
        place_crate(course, ch, sim, b)
        sim = course.sim()
    if lasers:
        by_beat = {b: o for (b, k, h), o in zip([s for s in script if s[1] == "orb"], course.orbs)}
        taps = [(b, by_beat[b]) for (b, k, h) in script
                if k == "orb" and h == TAP and (lasers is True or b in lasers)]
        place_row_lasers(course, ch, pat, taps, script)
    for b in gates:
        col = gate_column(sim, b)
        notes = beats_notes([b])
        g = Gate(col, 0, 19, notes)
        course.gates.append(g)
        for r in range(20):
            cell = ch.rows[r][col]
            terrain = cell in "#%AB" or pat.items.get(cell, {}).get("kind") in ("platform", "spike")
            if cell == " " or (r < 16 and not terrain):
                ch.rows[r][col] = pat.add({"kind": "gate", "notes": notes})
    sim = course.sim()

    zc = ZONE_FROM
    while ch.rows[0][zc] != " ":
        zc += 1
    if rests:
        plain = course.outcome

        def outcome(sc):
            return plain(sc) or rest_violation(course.sim(sc), rests, zc * TILE, zone_end * TILE)
        course.outcome = outcome

    print(f"[{name}] 島 {[(i[0], i[1]) for i in islands]}  音符 {show(course.orbs, 0)}  環 {show(course.rings, 0)}"
          f"  光牆 {[(g.col, g.notes) for g in course.gates]}")
    ## 往上爬時鏡頭會跟著抬；只擋「貼出地圖頂」的極端高度。
    for kind, items in (("環", course.rings), ("音符", course.orbs)):
        for it in items:
            assert it.y >= 1.5 * TILE, (name, f"{kind}太高會超出螢幕", round(it.y / TILE, 2))
    ## 站立約 y=618；衝刺／環若太靠近地面＝地面衝刺設計，第五關起一律禁止
    stand_y = 16 * TILE - 22.0
    for kind, items in (("環", course.rings),):
        for it in items:
            assert it.y < stand_y - 40.0, (
                name, "衝刺環太靠近地面（應在空中穿環）", round(it.y / TILE, 2))
    for ev in sim.events:
        if ev[0] == "dash" and ev[3] >= stand_y - 40.0:
            assert False, (name, "衝刺時還站在／貼近地面", round(ev[1], 2), round(ev[3] / TILE, 2))
    course.verify()
    if audit_air:
        # 不能只看「最後有抵達」：每個譜面動作都必須真的觸發，尤其不能把音符按成地面跳。
        for b, kind, _hold in script:
            expected = "dash" if kind == "ring" else kind
            assert any(e[0] == expected and abs(e[1] - b) < 0.05 for e in sim.events), (
                name, "譜面動作未觸發", b, kind, sim.events)
        saved = list(course.orbs)
        for i, orb in enumerate(saved):
            assert not any(l - 22 <= orb.x <= r + 22 and top > orb.y
                           for l, top, r, bottom in course.solids), (name, "音符底下有多餘地板", i)
            course.orbs = saved[:i] + saved[i + 1:]
            assert course.outcome(script) is not None, (name, "音符拿掉仍可通過", i)
        course.orbs = saved
        course.orb_check(True)
        course.ring_check(require_ring_use)
    if not rests:
        course.wait_check(flow)
    course.dash_check(flow)
    course.orb_check(flow)
    course.ring_check(flow)
    if course.gates:
        no_gate = course.sim(gates=[])
        print(f"  沒有光牆時標準節奏：{first_hit(no_gate) or '也能過'}")

    if rests or blind:
        cols = zone_end - zc
        if rests:
            spec = {"kind": "rest", "notes": rest_notes(rests), "strict": strict, "cols": cols}
        else:
            spec = {"kind": "blind", "notes": blind.get("notes", "x" * 16), "strobe": blind.get("strobe", False),
                    "cols": cols}
        ch.rows[0][zc] = pat.add(spec)
        print(f"  {spec['kind']} 區：第 {zc}～{zone_end} 格  {spec['notes']}")

    # 旗子的示範只有 8 拍，超過 8 拍的長段落只示範開頭一小節
    ghost = ghost_points(sim, score_beats) if score_beats else (ghost_for(sim, script) if last < 8 else ghost_points(sim, 8.0))
    plan = [[b, demo_char(k, h), round(x_at(sim, b))] for (b, k, h) in script]
    out = {"hint": hint, "ghost": ghost, "plan": plan, "rows": ch.lines()}
    if score_beats is not None:
        out["score_beats"] = score_beats
    if bpm:
        out["bpm"] = bpm
    if gravity is not None:
        out["gravity"] = float(gravity)
    if gravity_flip is not None:
        flip_beat, g_other = gravity_flip
        flip_x = round(x_at(sim, float(flip_beat)) / TILE, 2)
        width = float(len(ch.rows[0]))
        g_a = float(gravity) if gravity is not None else 2400.0
        assert 2.0 < flip_x < width - 2.0, (name, "重力切換邊界太靠邊緣", flip_x, width)
        out["gravity_zones"] = [
            {"from": 0.0, "to": flip_x, "gravity": g_a},
            {"from": flip_x, "to": width, "gravity": float(g_other)},
        ]
        print(f"  重力切換：x={flip_x}格  {g_a:g} → {float(g_other):g}")
    if course.orbs:
        out["orbs"] = [[x, y, notes_for(s), orb_tones[i % len(orb_tones)]]
                       for i, (x, y, s) in enumerate(show(course.orbs, 0))]
    if course.rings:
        out["rings"] = [[x, y, notes_for(s), ring_tones[i % len(ring_tones)]]
                        for i, (x, y, s) in enumerate(show(course.rings, 0))]
    return out


def bench(hint="長椅是存檔點：碰到機關會直接倒下，回到最後坐過的長椅", bpm=None):
    c = Chunk(12)
    c.fill(0, 11, 16, 19, "#")
    c.fill(6, 6, 15, 15, "C")
    out = {"hint": hint, "rows": c.lines()}
    if bpm:
        out["bpm"] = bpm
    return out


def intro(hint, bpm=None):
    c = Chunk(10)
    c.fill(0, 9, 16, 19, "#")
    c.fill(3, 3, 15, 15, "P")
    out = {"hint": hint, "rows": c.lines()}
    if bpm:
        out["bpm"] = bpm
    return out
