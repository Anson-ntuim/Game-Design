"""正式版關卡（重新設計）：每一關加入一樣新東西，再和學過的混在一起。

用法：python3 tools/campaign.py [關卡編號 ...] [--write]
輸出 scripts/level/campaign_<n>_data.gd（class CampaignNData）。

規則（配合自動前進＋固定高度跳躍）：
  - 每段開頭都有起跳旗：角色停在旗子旁倒數，GO 後先走一拍，連招第 0 拍才是第一個動作。
  - 跳躍固定一拍落地、半拍在最高點：空中衝刺／穿環／在最高點碰音符都放在半拍。
  - 地形由 tools/course_kit.py 照標準節奏模擬算出，並驗證按錯會失敗。
"""

import sys
from pathlib import Path

from design import FULL
from gen_level3 import Chunk, Patterns, Gate, solid_rect, simulate
from sim_player import SPB, TILE
from course_kit import section, intro as _intro
## 關卡開頭不跳說明卡：只留標題（提示卡只給機關第一次出現的教學）
intro = lambda hint, bpm=None: _intro(hint.split("\n")[0], bpm)
from level_kit import render_level

J = lambda b: (b, "jump", FULL)
O = lambda b: (b, "orb", FULL)
D = lambda b: (b, "dash", 0)
R = lambda b: (b, "ring", 0)
## 第五關起：高音符（跳得高、兩拍才落回原高度）、低音符（跳很矮、半拍就落回原高度）
from gen_level3 import HIGH_HOLD, LOW_HOLD
OH = lambda b: (b, "orb", HIGH_HOLD)
OL = lambda b: (b, "orb", LOW_HOLD)
## 教學關：落腳處不長刺（尖刺留到「彈出尖刺」那段才教）
F = dict(flag=True, island_spikes=False)
## 長段落跑酷：音符底下不鋪地板、引導環不必非用不可
FX = dict(F, orb_footholds=True, require_ring_use=False)
## 引導環：環標出該衝刺的那一拍和位置，穿過去就好，不一定要接第二下（拿掉環衝刺一樣過得去，所以不檢查「非用環不可」）
FR = dict(F, require_ring_use=False)
## 有黃色音符的段落：跳和碰音符都在正拍，音符底下不鋪地板（orb_footholds），靠踩音符前進
FO = dict(F, orb_footholds=True)
## 教學文字只在機關第一次出現時顯示（整個遊戲算一次，main() 依序產生每一關，所以跨關也記得）；
## 之後同一種段落只留標題（標題不會跳出提示卡，只顯示在左上角的段落名）
SEEN = set()


def tut(key, title, body):
    if key in SEEN:
        return title
    SEEN.add(key)
    return f"{title}\n{body}"


BENCH = "長椅"
BENCH_TEXT = "碰到就存檔，倒下會回到這裡"


# ---------------------------------------------------------------- 無縫接軌
# 照標準節奏跑完一段後，角色要剛好在「下一個小節頭的前一拍」（GO 拍）跑到下一段的起跑點，
# 起跳旗才會讓他直接通過、不用停下倒數。段落之間的長椅平地寬度由這裡算出來。
# 起跑點在段落左端 START_X（cue_flag.gd），自動跑一拍 RUN 像素；衝刺 0.2 秒衝 DASH_PX。
TILE_PX = 40.0
RUN = 155.0
START_X = 62.5
DASH_PX = 170.0
DASH_BEATS = 0.4
## 起跳旗一律每 CYCLE（4）拍放行一次，機關節奏型都折成 4 拍一輪（見 fold_cycle）。
## 會出現的平台、音符、光柱、衝刺環折了只會多出現幾次（無害）；危險機關（尖刺等）必須本來就 4 拍重複，否則產生時報錯。
CYCLE = 4.0
LONG_CYCLE = 4.0
## 折成 4 拍會多出傷害的機關種類：節奏型必須本來就每 4 拍重複
HAZARD_KINDS = ("spike", "ceiling", "piston", "laser")
LEAD = 1.0
## 長椅平地最少幾格：重生點放在長椅左邊，離下一面旗子至少約 3 拍的路，來得及反應
BENCH_MIN = 8
## 平地寬度只能一格一格調（一格約 0.26 拍）：寧可早到一點點（旗子前停不到 EARLY_OK 拍就 GO），不要晚到（晚了要等一整輪）
EARLY_OK = 0.27


def bench(hint=BENCH):
    """先放一個佔位，seamless() 再決定寬度；長椅說明只在第一次出現時顯示"""
    if hint == BENCH:
        hint = tut("bench", BENCH, BENCH_TEXT)
    return {"_bench": hint}


## 平地超過 HOP_MIN_TILES 格就在前半段挖小坑（每 HOP_EVERY 拍跳一次，起跳點落在整首歌的正拍），
## 後面留 HOP_TAIL 格平地放長椅（重生時在這段出現，接下一面旗子）
HOP_MIN_TILES = 14
HOP_TAIL = 8
HOP_EVERY = 2


def _bench_chunk(hint, width, t_in=None):
    """t_in：照節奏跑時角色中心經過這塊平地左端的整首拍數（None = 不知道，不挖坑）"""
    c = Chunk(width)
    c.fill(0, width - 1, 16, 19, "#")
    hops = []
    if t_in is not None and width >= HOP_MIN_TILES:
        limit = (width - HOP_TAIL) * TILE_PX
        T = float(int(t_in + 1.0) + 1)
        while True:
            x = (T - t_in) * RUN
            if x + RUN + TILE_PX > limit:
                break
            ## 前面幾格不挖：上一段可能是高台，掉下來會往前飄一段
            if x >= 240:
                c0 = int(-(-(x + 26) // TILE_PX))
                c1 = int((x + 129) // TILE_PX) - 1
                if c1 >= c0:
                    c.fill(c0, c1, 16, 19, " ")
                    hops.append(round(x))
            T += HOP_EVERY
    ## 重生點離下一面旗子遠一點（跑一段才到旗子，來得及反應）：有小坑放在最後那段平地的開頭，沒有就放在最左邊
    cp = width - HOP_TAIL + 1 if hops else 1
    c.fill(cp, cp, 15, 15, "C")
    out = {"hint": hint, "rows": c.lines()}
    if hops:
        out["hint"] = tut("hops", "間奏", "平地上有小坑：每兩拍按一下空白鍵跳過去，跟著節奏跑到下一段")
        out["hops"] = hops
    return out


def _exit_beat(chunk):
    """標準節奏跑到這一段右端時是第幾拍（以這一段連招第 0 拍為 0）"""
    width_px = max(len(r) for r in chunk["rows"]) * TILE_PX
    b, act, x = (chunk.get("plan") or chunk["sync_plan"])[-1]
    b, x = float(b), float(x)
    if act in ("D", "R"):
        b, x = b + DASH_BEATS, x + DASH_PX
    return b + (width_px - x) / RUN


def _periodic(notes, slots):
    return all(notes[i] == notes[(i + slots) % len(notes)] for i in range(len(notes)))


def cycle_of(chunk, pat):
    """這一段的起跳旗幾拍放行一次：連招 4 拍內做完，或段落裡的機關本來就每 4 拍重複 → 4 拍；否則 8 拍"""
    if chunk.get("_cycle"):
        return chunk["_cycle"]
    if chunk.get("sync_plan"):
        return CYCLE
    plan = chunk.get("plan")
    if not plan:
        return CYCLE
    end = max(float(b) + (DASH_BEATS if a in ("D", "R") else 0.0) for b, a, _ in plan) + 1.0
    if end <= CYCLE:
        return CYCLE
    slots = int(CYCLE * 2)
    notes = [item[2] for key in ("orbs", "rings") for item in chunk.get(key, [])]
    used = {c for row in chunk.get("rows", []) for c in row} & set(pat.items)
    notes += [pat.items[c]["notes"] for c in used if pat.items[c].get("kind") != "flag" and pat.items[c].get("notes")]
    return CYCLE if all(_periodic(n, slots) for n in notes) else LONG_CYCLE


## 段落最後落地後只留這幾格平地，其餘交給長椅那塊（有小坑可跳），不要一大片空跑
TAIL_KEEP = 4


def trim_tail(chunk):
    """把段落右端多餘的平地切掉：最後一個動作落地後留 TAIL_KEEP 格（終點段、有長椅或終點的不切）"""
    rows = chunk["rows"]
    if any(ch in row for row in rows for ch in "GC"):
        return chunk
    b, act, x = chunk["plan"][-1]
    land = float(x) + (260.0 if act in ("D", "R") else 0.0 if act == "-" else 170.0)
    cut = int(land // TILE_PX) + 1 + TAIL_KEEP
    width = max(len(r) for r in rows)
    if cut >= width:
        return chunk
    ## 切掉的部分只能是單純的地面（每一列都和切點那一欄相同）
    for r in rows:
        tail = r[cut:]
        if tail and len(set(tail)) > 1:
            return chunk
    chunk["rows"] = [r[:cut] for r in rows]
    return chunk


def seamless(pat, chunks, hops=True):
    """依序推算每一段連招第 0 拍是整首歌的第幾拍（以第一面旗子的 GO 為準），
    再決定段落間長椅平地的寬度，讓照節奏跑的人剛好在下一段的放行拍（或略早）到。
    第一段固定 8 拍一輪，整關的小節位置才確定（4 拍段落可能從小節頭或小節中間出發）。"""
    timed = lambda c: c and (c.get("plan") or c.get("sync_plan"))
    for i, c in enumerate(chunks):
        if c.get("plan") and i + 1 < len(chunks) and "_bench" in chunks[i + 1]:
            trim_tail(c)
    first = next((c for c in chunks if timed(c)), None)
    if first is not None and first.get("plan"):
        first["_cycle"] = LONG_CYCLE
    start_abs = {}
    if first is not None:
        start_abs[id(first)] = 0.0
        first["_phase"] = 0.0
    out = []
    for i, ch in enumerate(chunks):
        if "_bench" not in ch:
            out.append(ch)
            continue
        prev = chunks[i - 1] if i > 0 else None
        nxt = chunks[i + 1] if i + 1 < len(chunks) else None
        width = BENCH_MIN
        t_in = None
        if timed(prev) and timed(nxt) and id(prev) in start_abs:
            t_in = start_abs[id(prev)] + _exit_beat(prev)
            ## 下一段要在哪一拍到哪裡：有旗子的段落 = GO 拍到起跑點；光柱 = 打開那拍到柱子前
            if nxt.get("plan"):
                target_x, target_beat = START_X, -LEAD
            else:
                target_beat, _, target_x = nxt["sync_plan"][0]
            base = start_abs[id(prev)] + _exit_beat(prev) + target_x / RUN
            cyc = cycle_of(nxt, pat)
            for w in range(BENCH_MIN, BENCH_MIN + 40):
                early = (target_beat - (base + w * TILE_PX / RUN)) % cyc
                if early < EARLY_OK:
                    width = w
                    break
            arrive = base + width * TILE_PX / RUN
            early = (target_beat - arrive) % cyc
            start_abs[id(nxt)] = arrive + early - target_beat
            nxt["_phase"] = start_abs[id(nxt)] % CYCLE
            print(f"  長椅寬 {width} 格：整首第 {arrive:.2f} 拍到下一段（{cyc:g} 拍一輪），提早 {early:.2f} 拍")
        out.append(_bench_chunk(ch["_bench"], width, t_in if hops else None))
    return out


def _fold(notes, cycle_slots):
    """16 格（8 拍）節奏型折成 cycle_slots 格一輪：任何一輪有 x 的位置，每一輪都 x"""
    if not notes or len(notes) % cycle_slots:
        return notes
    out = list(notes)
    for i, ch in enumerate(notes):
        if ch == "x":
            for k in range(i % cycle_slots, len(notes), cycle_slots):
                out[k] = "x"
    return "".join(out)


def fold_cycle(pat, chunks):
    """4 拍段落的機關節奏型折成 4 拍一輪，起跳旗每 4 拍放行；8 拍段落維持原樣、每 8 拍放行。
    節奏型字元可能被好幾段共用：只要有一段是 8 拍就不折。"""
    users = {}
    for ch in chunks:
        cyc = cycle_of(ch, pat)
        used = {c for row in ch.get("rows", []) for c in row} & set(pat.items)
        for c in used:
            users.setdefault(c, set()).add(cyc)
        if cyc == CYCLE:
            for key in ("orbs", "rings"):
                for item in ch.get(key, []):
                    sub = item[4] if key == "orbs" and len(item) > 4 else 2
                    item[2] = _fold(item[2], int(CYCLE * sub))
    for c, spec in list(pat.items.items()):
        cyc = max(users.get(c, {CYCLE}))
        if spec.get("kind") == "flag":
            spec["cycle"] = cyc
        elif spec.get("kind") == "lift":
            ## 終點升降舞台是 8 拍「升三階、再降回」的循環，折了會亂；晚到只是在舞台上多站一下，不影響
            continue
        elif spec.get("notes") and cyc == CYCLE:
            if spec.get("kind") in HAZARD_KINDS:
                assert _periodic(spec["notes"], int(CYCLE * 2)), ("危險機關不是 4 拍重複，折了會在沒預期的拍子傷人", spec)
            spec["notes"] = _fold(spec["notes"], int(CYCLE * 2))
    ## 每面旗子記下設計時連招第 0 拍在 8 拍小節裡的位置（重生對拍用）；共用字元的旗子各自複製一份
    for ch in chunks:
        if "_phase" not in ch:
            continue
        for c in {x for row in ch["rows"] for x in row} & set(pat.items):
            spec = pat.items[c]
            if spec.get("kind") != "flag":
                continue
            new = pat.add(dict(spec, phase=ch["_phase"]))
            ch["rows"] = [row.replace(c, new) for row in ch["rows"]]
    return chunks


## 光柱每拍都開（走廊檢查用）
EVERY_BEAT_GATE = "x.x.x.x.x.x.x.x."


def check_gate_hall(width, gate_cols, ceil_row):
    """光柱走廊：一路往右走，被光柱擋住後在下一拍衝刺。
    回傳標準節奏的衝刺拍；並確認每一下不衝、早半拍、晚半拍都會卡在光柱前"""
    solids = [solid_rect(0, width + 40, 16, 19), solid_rect(4, width - 1, 0, ceil_row)]
    gates = [Gate(c, ceil_row + 1, 15, EVERY_BEAT_GATE) for c in gate_cols]
    goal_x = width * TILE

    def run(dashes, end=40.0):
        return simulate(solids, [], [D(b) for b in dashes], end, gates=gates)

    dashes = []
    for _ in gate_cols:
        sim = run(dashes)
        stall = None
        for i in range(10, len(sim.log)):
            b, x, _ = sim.log[i]
            if abs(x - sim.log[i - 10][1]) < 0.01 and x < goal_x and (not dashes or b > dashes[-1] + 0.5):
                stall = b
                break
        assert stall is not None, ("光柱走廊：沒有被擋住", dashes)
        cooled = dashes[-1] + 0.55 / SPB if dashes else stall
        dashes.append(float(int(max(stall, cooled)) + 1))
    sim = run(dashes)
    assert sim.x >= goal_x, ("光柱走廊：標準節奏沒過", dashes, sim.x)
    print(f"[光柱走廊] 光柱 {gate_cols}  衝刺拍 {dashes}")
    print("  標準節奏：通過")
    for i, b in enumerate(dashes):
        good = []
        for d in (-0.5, -0.3, -0.24, -0.12, 0.12, 0.24, 0.3, 0.5):
            sc = list(dashes)
            sc[i] = b + d
            if run(sc).x >= goal_x:
                good.append(d)
        out = ""
        for sc, what in ((dashes[:i] + dashes[i + 1:], "不衝"),
                         (dashes[:i] + [b - 0.5] + dashes[i + 1:], "早半拍"),
                         (dashes[:i] + [b + 0.5] + dashes[i + 1:], "晚半拍")):
            s = run(sc)
            out += f"  {what} → {'竟然過了！' if s.x >= goal_x else ('卡在光柱前', round(s.x))}"
            assert s.x < goal_x, (what, b)
        print(f"  #{i} 第{b}拍 衝：偏移幾拍還過 {good}{out}")
    return dashes


def pillar(pat, hint, col=12, width=20, open_beat=0.0):
    """單獨的光柱：天花板壓低不能跳過，跑到柱子前被擋住，柱子每 CYCLE 拍在 open_beat 打開一次（出現箭頭），
    那一拍按衝刺穿過。前面的平地會算成剛好在打開前一點點跑到柱子前（seamless 用 sync_plan）。
    幾何經 check_gate_hall 檢查：不衝、早半拍、晚半拍都過不去。"""
    ceil_row = 12
    check_gate_hall(width, [col], ceil_row)
    notes = ["."] * 16
    for k in range(0, 16, int(CYCLE * 2)):
        notes[(k + round(open_beat * 2)) % 16] = "x"
    gate = pat.add({"kind": "gate", "notes": "".join(notes)})
    c = Chunk(width)
    c.fill(0, width - 1, 16, 19, "#")
    c.fill(4, width - 1, 0, ceil_row, "%")
    c.fill(col, col, ceil_row + 1, 15, gate)
    ## 被擋住時角色中心：柱子左緣（col*40+10）往左半個身寬
    block_x = col * TILE_PX + 10 - 12
    return {"hint": hint, "rows": c.lines(), "sync_plan": [[open_beat, "D", block_x]]}


def far_landing(chunk, tiles=1):
    """音符段的終點平台再往右退 tiles 格：只跳一下再空中衝刺（約 9 格遠）一定到不了，非踩音符不可。
    只改畫面上的地形（產生器驗證用的是原本位置；踩完音符的落點離平台邊緣還有好幾格，實機由 check_all_levels 驗證）"""
    rows = [list(r) for r in chunk["rows"]]
    ground = rows[16]
    end = len(ground) - 1
    while end > 0 and ground[end] == " ":
        end -= 1
    start = end
    while start > 0 and ground[start - 1] != " ":
        start -= 1
    for r in range(16, 20):
        if r < len(rows):
            for c in range(start, min(start + tiles, len(rows[r]))):
                rows[r][c] = " "
            if start + tiles < len(rows[r]) and rows[r][start + tiles] == "#":
                rows[r][start + tiles] = rows[r][start] if rows[r][start] != " " else "%"
    chunk["rows"] = ["".join(r) for r in rows]
    return chunk


# ---------------------------------------------------------------- 彈簧床（連段模式）
# scripts/level/trampoline.gd 的 TIERS：按第 k 下升到第 k 段，各段高度（px）與一次彈跳幾拍
TRAMP_H = [60.0, 140.0, 280.0, 400.0]
TRAMP_BEATS = [1.0, 1.0, 2.0, 2.0]
GRAVITY_PX = 4480.0


NORMAL_G = 4480.0
JUMP_V = 1120.0
DT = 1.0 / 120.0
SPB_S = 0.5


def _notes_at(beat):
    n = ["."] * 16
    n[round(beat * 2) % 16] = "x"
    return "".join(n)


EVERY_BEAT_NOTES = "x.x.x.x.x.x.x.x."


def _launch_path(x0, h, beats, actions, y0=0.0, v0=None):
    """彈出後的軌跡（和 player.gd 一樣）：先走彈簧床的拋物線（h 高、beats 拍，正中間是最高點），
    actions = [(動作, 彈出後第幾拍), …] 依序：R 穿環／D 衝刺（0.2 秒 850px/s 水平；R 結束往上彈 360）、
    O 踩音符（重新起跳，一般重力）。回傳 [(t 秒, x, 腳離床面高度)] 和每個動作那一刻的位置。"""
    if v0 is None:
        air = beats * SPB_S
        g = 8 * h / (air * air)
        vy = 4 * h / air
        vx = 310.0
    else:
        ## 盪鞦韆放手：固定初速、一般重力，水平速度一路保持到下一個動作
        vx, vy = v0
        g = NORMAL_G
    x, y = x0, y0
    t = 0.0
    pts = []
    acts = []
    pending = list(actions)
    dash_left = 0.0
    pop = False
    while t < 5.0 and y > -400:
        if pending and t >= pending[0][1] * SPB_S - 1e-6:
            kind = pending.pop(0)[0]
            acts.append((x, y))
            vx = 310.0
            if kind in ("R", "D"):
                dash_left = 0.2
                pop = kind == "R"
                g = NORMAL_G
            elif kind in ("O", "OH", "OL"):
                ## OH 大音符：重力減半（兩拍回原高度）；OL 小音符：初速減半（半拍回原高度）
                vy = JUMP_V * (0.5 if kind == "OL" else 1.0)
                g = NORMAL_G * (0.5 if kind == "OH" else 1.0)
        if dash_left > 0:
            x += 850.0 * DT
            dash_left -= DT
            if dash_left <= 0:
                vy = 360.0 if pop else 0.0
        else:
            vy -= g * DT
            ## 遊戲裡下落速度上限 1120（player.gd），一拍半的音符靠這個才算得準
            vy = max(vy, -JUMP_V)
            x += vx * DT
            y += vy * DT
        t += DT
        pts.append((t, x, y))
    return pts, acts


def trampoline(pat, hint, need=2, approach=7, mat=3, mechanic="", pre_jump=False, after=None, rise=None):
    """彈簧床（連段模式）段落。pre_jump：先跳過一個小坑、直接落在床上。
    after = [(R|O|D, 彈出後第幾拍), …]：飛出去之後在空中依序穿環／踩音符／衝刺（這些東西每一拍都亮，
    晚幾拍飛出去也接得上），落到更遠或更高的高台。rise：高台比床面高幾格（None = 自動）。"""
    if after and isinstance(after[0], str):
        after = [after]
    after = after or []
    if pre_jump:
        approach = 8
        board = 1.0
    else:
        board = -LEAD + (approach * TILE_PX - START_X) / RUN
    land = float(int(board) + 1) if board != int(board) else board + 1.0
    if land - board < 0.35:
        land += 1.0
    presses = [land]
    for k in range(1, need):
        presses.append(presses[-1] + TRAMP_BEATS[k])
    h = TRAMP_H[need]
    x_c = (approach + mat / 2) * TILE_PX
    pts, acts = _launch_path(x_c, h, TRAMP_BEATS[need], after)
    last = after[-1][0] if after else None
    if rise is None:
        rise = {None: int((h - 80) // TILE_PX), "O": int((h + 60) // TILE_PX)}.get(last, int((h - 120) // TILE_PX))
    top = rise * TILE_PX
    ## 最後一個動作之後、腳高過台面 8px 的那段時間：牆放在這段中間，落點是之後第一次降到台面的地方
    t_act = after[-1][1] * SPB_S if after else 0.0
    above = [(t, x) for (t, x, y) in pts if t >= t_act + 0.05 and y >= top + 8]
    assert above, ("彈簧床：到不了這個高度", need, after, rise)
    seg = []
    for t, x in above:
        if seg and t - seg[-1][0] > DT * 1.5:
            break
        seg.append((t, x))
    wall_x = seg[len(seg) // 2][1] + 12
    wall_col = int(-(-wall_x // TILE_PX))
    t_land = next(t for (t, x, y) in pts if t > seg[-1][0] and y <= top)
    x_land = next(x for (t, x, y) in pts if t >= t_land)
    assert wall_col >= approach + mat + 1, ("彈簧床和高台之間要留坑", wall_col)
    ## 空中的音符／環不能在牆裡
    for (ax, ay), (kind, _) in zip(acts, after):
        assert ax < wall_col * TILE_PX - 20 or ay > top + 30, ("空中機關撞到高台", kind)
    width = max(wall_col + 6, int(x_land // TILE_PX) + 5)
    c = Chunk(width)
    if pre_jump:
        c.fill(0, 4, 16, 19, "#")
    else:
        c.fill(0, approach - 1, 16, 19, "#")
    c.fill(wall_col, width - 1, 16 - rise, 19, "#")
    c.fill(wall_col, wall_col, 16 - rise, 19, "%")
    demo = ["."] * 16
    plan = []
    if pre_jump:
        demo[0] = "L"
        plan.append([0.0, "L", round(START_X + RUN)])
    for b in presses:
        demo[round(b * 2) % 16] = "L"
        plan.append([b, "L", round(x_c)])
    out = {"hint": hint, "rows": None, "trampolines": [[approach, 16, mat, need]]}
    for (ax, ay), (kind, off) in zip(acts, after):
        b = presses[-1] + off
        center = [round(ax / TILE_PX, 2), round((16 * TILE_PX - 22 - ay) / TILE_PX, 2)]
        if kind == "R":
            ## 最後一個 true：安靜模式，站上彈簧床才開始閃
            out.setdefault("rings", []).append(center + [EVERY_BEAT_NOTES, 19, True])
        elif kind == "O":
            out.setdefault("orbs", []).append(center + [EVERY_BEAT_NOTES, 12 + 3 * len(out.get("orbs", [])), 2, True])
        demo[round(b * 2) % 16] = kind
        plan.append([b, kind, round(ax)])
    c.fill(5 if not pre_jump else 2, 5 if not pre_jump else 2, 15, 15, pat.add({"kind": "flag", "notes": "", "demo": "".join(demo)}))
    out["rows"] = c.lines()
    out["plan"] = plan
    if mechanic:
        out["mechanic"] = mechanic
    tag = "、".join(f"{k}@+{o}" for k, o in after)
    print(f"[彈簧床] 按 {presses}，彈 {h:.0f}px{('、' + tag) if tag else ''}，上 {rise} 格高台（牆 {wall_col} 格、落在 x≈{x_land:.0f}）")
    return out


# ---------------------------------------------------------------- 盪鞦韆
# scripts/level/swing_rope.gd：座椅角度只看整首拍數，4 拍來回一趟、offset 拍往前擺到最高。
# 段落第 0 拍一定是整首的 4 的倍數（起跳旗每 4 拍放行），所以 offset 直接寫段落拍數。
# 幾何來自早期的鞦韆試作關（地面第 12 列 → 這裡第 16 列）：
# 第 1 拍在高台邊起跳、空中抓住座椅，往前到頂那一拍放手 → 初速 (574, -1120)，一拍後回到放手的高度。
SWING_AMP = 55.0
SWING_V = (574.0, 1120.0)
RIDER_UP = 18.0  ## 角色中心在座椅上方幾 px（BODY 44 / 2 - 4）


def _swing_release(ax, ay, length):
    """往前到頂時角色腳的位置：x（px），腳離地面（第 16 列頂）多高"""
    import math
    a = math.radians(SWING_AMP)
    sx = ax * TILE_PX + math.sin(a) * length * TILE_PX
    sy = ay * TILE_PX + math.cos(a) * length * TILE_PX
    foot = sy - RIDER_UP + 22.0
    return sx, 16 * TILE_PX - foot


def swing(pat, hint, relay=False, after=None, rise=0, mechanic=""):
    """盪鞦韆段落。relay：第一座放手後在空中抓住第二座（第二座晚三拍到頂）。
    after = [(R|O|D, 最後一次放手後第幾拍), …]：放手後在空中穿環／踩音符／衝刺。rise：落地高台比地面高幾格。"""
    after = after or []
    swings = [[12.5, 9, 4, 4, 1, 0]]
    releases = [4.0]
    if relay:
        swings.append([25.5, 9.5, 3.5, 4, 1, 3])
        releases.append(7.0)
    sx, sy, sl = swings[-1][0], swings[-1][1], swings[-1][2]
    rx, ry = _swing_release(sx, sy, sl)
    pts, acts = _launch_path(rx, 0, 0, after, y0=ry, v0=SWING_V)
    top = rise * TILE_PX
    t_act = after[-1][1] * SPB_S if after else 0.0
    ## 落點：最後一個動作之後第一次往下穿過台面的地方；牆放在落點前、腳還高過台面的位置
    t_land = x_land = None
    prev = None
    for t, x, y in pts:
        if t >= t_act and prev is not None and prev[2] > top >= y:
            t_land, x_land = t, x
            break
        prev = (t, x, y)
    assert t_land is not None, ("盪鞦韆：落不到這個高度", after, rise)
    wall_col = int(x_land // TILE_PX) - 2
    assert wall_col * TILE_PX > rx + 60, ("落地高台離鞦韆太近", wall_col)
    for (ax, ay), (kind, _) in zip(acts, after):
        assert ax < wall_col * TILE_PX - 20 or ay > top + 30, ("空中機關撞到高台", kind)
    width = int(x_land // TILE_PX) + 8
    c = Chunk(width)
    c.fill(0, 8, 16, 19, "#")
    c.fill(wall_col, width - 1, 16 - rise, 19, "#")
    if rise:
        c.fill(wall_col, wall_col, 16 - rise, 19, "%")
    demo = ["."] * 16
    plan = [[1.0, "L", round(START_X + RUN * 2)]]
    for b in [1.0] + releases:
        demo[round(b * 2) % 16] = "L"
    for b in releases:
        plan.append([b, "S", round(rx)])
    out = {"hint": hint, "rows": None, "swings": swings}
    base = releases[-1]
    for (ax, ay), (kind, off) in zip(acts, after):
        b = base + off
        center = [round(ax / TILE_PX, 2), round((16 * TILE_PX - 22 - ay) / TILE_PX, 2)]
        if kind == "R":
            out.setdefault("rings", []).append(center + [_notes_at(b), 19, True])
        elif kind in ("O", "OH", "OL"):
            out.setdefault("orbs", []).append(center + [_notes_at(b), 12 + 3 * len(out.get("orbs", [])), 2, True]
                                              + ([{"OH": "high", "OL": "low"}[kind]] if kind != "O" else []))
        demo[round(b * 2) % 16] = kind[0]
        plan.append([b, kind[0], round(ax)])
    ## 落地那一刻（只給長椅寬度、機器人參考，不按鍵）
    plan.append([round(base + t_land / SPB_S, 3), "-", round(x_land)])
    c.fill(5, 5, 15, 15, pat.add({"kind": "flag", "notes": "", "demo": "".join(demo)}))
    out["rows"] = c.lines()
    out["plan"] = plan
    if mechanic:
        out["mechanic"] = mechanic
    tag = "、".join(f"{k}@+{o}" for k, o in after)
    print(f"[盪鞦韆] 放手 {releases}{('、' + tag) if tag else ''}，放手點 x≈{rx:.0f} 高 {ry:.0f}，落在 x≈{x_land:.0f}（第 {base + t_land / SPB_S:.2f} 拍）")
    return out


def sec(pat, name, script, hint, **kw):
    """course_kit.section 再記下光柱的拍子"""
    ch = section(pat, name, script, hint, **kw)
    ch["_gates"] = [float(g) for g in kw.get("gates", ())]
    return ch


def goal(hint):
    c = Chunk(14)
    c.fill(0, 13, 16, 19, "#")
    c.fill(9, 9, 15, 15, "G")
    return {"hint": hint, "rows": c.lines()}


def level1(pat):
    """第一關・教學：跳 → 連跳 → 上高台 → 彈出尖刺 → 空中衝刺 → 黃色音符 → 小複習"""
    return seamless(pat, [
        intro("第一關・跟著拍子跑\n角色會自己往前跑，你只要按空白鍵跳、Shift 衝刺。"
              "跑到旗子旁會停下倒數，數到 0（GO）就出發；先走一拍，再跳"),
        sec(pat, "跳過小坑", [J(0), J(2), J(3), J(4)],
                tut("jump", "跳過小坑", "GO 後走一拍就按空白鍵跳。跳一下剛好一拍落地：跳、空一拍，再連跳三下"), **F),
        bench(),
        sec(pat, "跳上高台", [J(0), J(2), J(4)],
                tut("rise", "跳上高台", "一樣是一拍一跳，只是落在更高的地方；中間落地後空一拍再跳"),
                floor=[("pit", 1, 1), ("pit", 2, 1)], final_rise=3, **F),
        bench(),
        sec(pat, "彈出尖刺", [J(1), J(3), J(5), J(7)],
                tut("spike", "彈出尖刺", "地上的尖刺會在第 1、3、5、7 拍彈出。前半拍尖端會先冒出來閃：看到它冒出來就按空白鍵跳"),
                floor="ground", spikes=[1, 3, 5, 7], flow=True, **F),
        bench(),
        sec(pat, "空中衝刺", [J(0), D(0.5)],
                tut("dash", "空中衝刺", "坑太寬跳不過：起跳後半拍（跳到最高點）按 Shift，往前衝一大段"), **F),
        bench(),
        pillar(pat, tut("pillar", "光柱", "光柱擋住路、頭上也過不去：跑到柱子前會被擋住。出現往右的箭頭那一拍按 Shift 衝刺穿過去")),
        bench(),
        sec(pat, "跳起來衝光柱", [J(0), D(0.5)],
                tut("pillar_air", "跳起來衝光柱", "這根光柱在坑上方：正拍起跳，跳到最高點（半拍）光柱打開，在空中按 Shift 穿過去"),
                gates=[0.5], **F),
        bench(),
        far_landing(sec(pat, "黃色音符", [J(0), O(1), O(2)],
                tut("orb", "黃色音符", "音符浮在坑上：正拍起跳，下一拍外圈縮到音符上時再按一次空白鍵；兩顆都踩才到得了對岸"), **FO)),
        bench(),
        far_landing(sec(pat, "連續音符", [J(0), O(1), O(2), O(3), O(4)], "連續音符", **FO)),
        bench(),
        far_landing(sec(pat, "小複習", [J(0), J(1), D(1.5), J(3), O(4), O(5)], "小複習", gates=[1.5], **FO)),
        goal("終點"),
    ])


def level2(pat):
    """第二關：衝刺環 → 節拍平台 → 旋律平台，後半段和第一關的音符、光柱、衝刺混在一起"""
    return seamless(pat, [
        intro("第二關・環與平台\n新東西：衝刺環、節拍平台、旋律平台"),
        sec(pat, "衝刺環", [J(0), R(0.5)],
                tut("ring", "衝刺環", "衝刺環標出要衝刺的位置和拍子：外圈縮到環上那一拍按 Shift 穿過去"), **FR),
        bench(),
        sec(pat, "連穿衝刺環", [J(0), R(0.5), R(1.5)],
                tut("ring2", "連穿衝刺環", "穿過環會補回空中衝刺：穿第一環，下一拍再按 Shift 穿第二環"), **F),
        bench(),
        sec(pat, "節拍平台", [J(0), J(2), J(4), J(6)],
                tut("beat", "節拍平台", "黃、藍平台每兩拍輪流出現，交接的那一拍兩色都在：在那一拍跳到另一色"),
                floor="beat", flow=True, final_rise=2, **F),
        bench(),
        sec(pat, "旋律平台", [J(0), J(2), J(4), J(6)],
                tut("melody", "旋律平台", "綠色平台照旋律一塊接一塊亮起，只亮一下：每兩拍跳到下一塊，停下來就會掉下去"),
                floor="melody", flow=True, final_rise=2, **F),
        bench(),
        sec(pat, "平台衝刺", [J(0), D(0.5), J(2), D(2.5), J(4), J(6)], "平台衝刺",
                floor="beat", flow=True, final_rise=2, **F),
        bench(),
        far_landing(sec(pat, "音符接環", [J(0), O(1), O(2), R(2.5)], "音符接環", **dict(FO, require_ring_use=False))),
        bench(),
        sec(pat, "坑與平台", [J(0), J(2), J(3), J(5), J(7)], "坑與平台",
                floor=["pit", "melody", "beat"], flow=True, final_rise=2, **F),
        bench(),
        sec(pat, "環與光柱", [J(0), R(0.5), D(1.5), J(4), J(5), R(5.5), D(6.5)], "環與光柱",
                floor="melody", flow=True, gates=[1.5, 6.5], **F),
        bench(),
        sec(pat, "安可", [J(0), R(0.5), D(1.5), J(4), R(4.5), D(5.5)], "安可",
                floor="melody", flow=True, finale=True, gates=[1.5, 5.5], **F),
    ])


def level3(pat):
    """第三關：新東西是彈簧床（和音符、衝刺環、衝刺接在同一段）。跑酷段落變長（8～12 拍一段），
    正拍、反拍、半拍連踩混在一起，不是固定的節奏"""
    return seamless(pat, [
        intro("第三關・彈簧床與長段跑酷\n新東西：彈簧床。這關的跑酷一段比較長，正拍、反拍混在一起"),
        trampoline(pat, tut("tramp", "彈簧床", "站上去會一直彈。任何一次落床那一拍按空白鍵都會升一段，升兩段就飛上高台；沒按到就再彈一次"), need=2),
        bench(),
        far_landing(sec(pat, "反拍音符串", [J(0.5), O(1.5), O(2.5), O(3.5), O(4.5)],
            tut("offbeat", "反拍", "這段在兩拍中間（反拍）按：半拍起跳，接著四顆音符都在反拍，噠、噠、噠、噠"), **FO)),
        bench(),
        sec(pat, "音符跑酷", [J(0), O(1), J(2.5), J(3.5), O(4.5), O(5), J(6.5), D(7)], "音符跑酷（8 拍）", **FX),
        bench(),
        trampoline(pat, tut("tramp_air", "彈簧床接音符", "飛出去之後音符才會亮：空中一拍踩一顆"), need=2, pre_jump=True,
                   after=[("O", 1), ("O", 2)]),
        bench(),
        sec(pat, "反拍跑酷", [J(0.5), O(1.5), J(3), O(3.5), O(4.5), J(6), J(7), D(7.5)], "反拍跑酷（8 拍）", **FX),
        bench(),
        trampoline(pat, "彈到最高接音符", need=3, after=[("O", 1)]),
        bench(),
        sec(pat, "旋律長段", [J(0), J(1.5), J(3), J(4.5), J(5.5), J(7)], "旋律長段（8 拍）",
            floor="melody", flow=True, final_rise=2, **F),
        bench(),
        trampoline(pat, "彈簧床接衝刺環", need=2, after=[("R", 1)]),
        bench(),
        sec(pat, "混合跑酷", [J(0), J(1), O(2), O(2.5), J(4), R(4.5), J(6), O(7), J(8.5), D(9)], "混合跑酷（10 拍）", **FX),
        bench(),
        sec(pat, "音符高低", [J(0), O(0.5), O(1), J(2.5), O(3.5), J(5), R(5.5), J(7), O(8)], "音符高低（9 拍）",
            final_rise=3, **FX),
        bench(),
        sec(pat, "節拍長段", [J(0), D(0.5), J(2), J(4), D(4.5), J(6), J(8), D(8.5)], "節拍長段（10 拍）",
            floor="beat", flow=True, final_rise=2, **F),
        bench(),
        trampoline(pat, "彈簧床接連續音符", need=2, after=[("O", 1), ("O", 2), ("O", 3)]),
        bench(),
        sec(pat, "總複習", [J(0), O(1), J(2.5), D(3), J(4.5), O(5.5), O(6), J(7.5), R(8), J(9.5), J(10.5), D(11)],
            "總複習（12 拍）", gates=[3, 11], **FX),
        bench(),
        trampoline(pat, "最後一跳", need=3, pre_jump=True, after=[("D", 1)]),
        bench(),
        goal("終點"),
    ])


SWING_LEN = 4.0
GRAB_RADIUS = 44.0
ROPE_GRAB = 30.0


def chain_swing(pat, hint, before, after, grab=1.0, mechanic=""):
    """音符串中間的鞦韆：第 1 拍從高台跳出去，空中踩 before 的音符，
    最後一個音符後 grab 拍在空中碰到座椅（座椅剛好盪到後面最高、停住的那一刻），
    再兩拍盪到前面最高放手，飛出去接 after 的音符／衝刺，最後落在對岸。
    座椅前後最高點一樣高，所以放手高度 = 抓住的高度，不會越爬越高。
    before／after = [(O|OH|OL|D|R, 第幾拍)]：before 從起跳算，after 從放手算。"""
    import math
    jump_b = 1.0
    x0 = START_X + RUN * 2
    t_grab = (before[-1][1] if before else 0.0) + grab
    pre, pre_acts = _launch_path(x0, 0, 0, before, y0=0.0, v0=(310.0, JUMP_V))
    hit = min(pre, key=lambda p: abs(p[0] - t_grab * SPB_S))
    _, gx, gy = hit
    assert gy > 70, ("鞦韆：抓的位置太低", gy)
    a = math.radians(SWING_AMP)
    L = SWING_LEN * TILE_PX
    ## 角色中心（畫面座標）→ 座椅在中心下方 12 px
    cy = 16 * TILE_PX - 22 - gy
    seat_b = (gx, cy + 12)
    anchor = (seat_b[0] + L * math.sin(a), seat_b[1] - L * math.cos(a))
    b_grab = jump_b + t_grab
    b_rel = b_grab + 2.0
    offset = b_rel % 4.0
    def seat(beat):
        ang = SWING_AMP * math.cos(2 * math.pi * (beat - offset) / 4.0)
        r = math.radians(ang)
        return anchor[0] + math.sin(r) * L, anchor[1] + math.cos(r) * L
    ## 太早碰到繩子／座椅會提早被抓走（後面的音符就按不到）
    for t, x, y in pre:
        if t > t_grab * SPB_S - 0.07:
            break
        if t < 0.05:
            continue
        b = jump_b + t / SPB_S
        sx, sy = seat(b)
        px, py = x, 16 * TILE_PX - 22 - y
        d_seat = math.hypot(px - sx, py - (sy - 8))
        r0 = (anchor[0] + (sx - anchor[0]) * 0.35, anchor[1] + (sy - anchor[1]) * 0.35)
        vx_, vy_ = sx - r0[0], sy - r0[1]
        u = max(0.0, min(1.0, ((px - r0[0]) * vx_ + (py - r0[1]) * vy_) / (vx_ * vx_ + vy_ * vy_)))
        d_rope = math.hypot(px - (r0[0] + u * vx_), py - (r0[1] + u * vy_))
        assert d_seat > GRAB_RADIUS + 10 and d_rope > ROPE_GRAB + 10, ("鞦韆：太早碰到", round(b, 2), round(d_seat), round(d_rope))
    sf = seat(b_rel)
    rx = sf[0]
    ry = 16 * TILE_PX - (sf[1] - RIDER_UP + 22)
    pts, acts = _launch_path(rx, 0, 0, after, y0=ry, v0=SWING_V)
    t_act = after[-1][1] * SPB_S if after else 0.0
    t_land = x_land = None
    prev = None
    for t, x, y in pts:
        if t >= t_act and prev is not None and prev[2] > 0 >= y:
            t_land, x_land = t, x
            break
        prev = (t, x, y)
    assert t_land is not None, ("鞦韆：落不了地", after)
    for (ax, ay), (k, o) in zip(pre_acts + acts, before + after):
        assert ay > 40, ("音符太低（會變成地面跳）", k, o, round(ay))
    wall_col = int(x_land // TILE_PX) - 2
    assert wall_col * TILE_PX > rx + 60, ("落地高台離鞦韆太近", wall_col)
    width = int(x_land // TILE_PX) + 8
    c = Chunk(width)
    c.fill(0, 8, 16, 19, "#")
    c.fill(wall_col, width - 1, 16, 19, "#")
    end_b = b_rel + t_land / SPB_S
    slots = max(16, int(math.ceil((end_b + 1) / 4.0)) * 8)
    demo = ["."] * slots
    demo[round(jump_b * 2)] = "L"
    demo[round(b_rel * 2)] = "L"
    plan = [[jump_b, "L", round(x0)]]
    out = {"hint": hint, "rows": None,
           "swings": [[round(anchor[0] / TILE_PX, 3), round(anchor[1] / TILE_PX, 3), SWING_LEN, 4, 1, round(offset, 3)]]}
    def add(kind, b, ax, ay):
        center = [round(ax / TILE_PX, 2), round((16 * TILE_PX - 22 - ay) / TILE_PX, 2)]
        if kind == "R":
            out.setdefault("rings", []).append(center + [_notes_at(b), 19, True])
        elif kind in ("O", "OH", "OL"):
            out.setdefault("orbs", []).append(center + [_notes_at(b), 12 + 3 * len(out.get("orbs", [])), 2, True]
                                              + ([{"OH": "high", "OL": "low"}[kind]] if kind != "O" else []))
        demo[round(b * 2)] = kind[0]
        plan.append([b, kind[0], round(ax)])
    for (ax, ay), (k, o) in zip(pre_acts, before):
        add(k, jump_b + o, ax, ay)
    plan.append([b_rel, "S", round(rx)])
    for (ax, ay), (k, o) in zip(acts, after):
        add(k, b_rel + o, ax, ay)
    plan.append([round(end_b, 3), "-", round(x_land)])
    c.fill(5, 5, 15, 15, pat.add({"kind": "flag", "notes": "", "demo": "".join(demo)}))
    out["rows"] = c.lines()
    out["plan"] = plan
    if mechanic:
        out["mechanic"] = mechanic
    hs = [round(ay) for (_, ay) in pre_acts + acts]
    print(f"[音符鞦韆] 抓 第{b_grab:.2f}拍 高{gy:.0f}  放手 第{b_rel:.2f}拍 x≈{rx:.0f} 高{ry:.0f}  動作高度 {hs}  落在第 {end_b:.2f} 拍")
    return out


def strict(chunk):
    """第四關起：音符段一律嚴格（衝刺不能取代任何一下跳），終點平台退後一格，只有一種過法"""
    return far_landing(chunk)


def level4(pat):
    """第四關（雨夜街道）：新東西是盪鞦韆。沒有平地小坑：音符串中間夾旋律平台（亮一下就消失）。
    音符有上有下但每次只爬兩階就下來，不會一路爬很高再一口氣掉下去。每段都只有一種過法"""
    import gen_level3
    gen_level3.DASH_IGNORE_TAIL = True
    M = dict(FO, flow=True, floor="melody")
    try:
        return seamless(pat, [
            intro("第四關・雨夜鞦韆\n新東西：盪鞦韆。這關沒有平地小坑：音符中間夾著會消失的旋律平台"),
            swing(pat, tut("swing", "盪鞦韆", "GO 後一拍按空白鍵跳上鞦韆，會自動抓住。盪到最前面最高、光圈縮到座椅那一拍再按空白鍵放手，才飛得過去")),
            bench(),
            strict(sec(pat, "音符往下", [J(0), O(1), O(2), J(3), O(3.5), O(4), O(5.5), J(6.5), O(7.5), O(8)],
                tut("orb_down", "音符往下", "音符也會往下排：隔半拍的比較高、隔一拍一樣高、隔一拍半的在下面（多等半拍）。中間的綠色平台只亮一下"), **M)),
            bench(),
            swing(pat, tut("swing2", "鞦韆接力", "放手後在空中會抓住第二座；第二座晚三拍到頂：放手、數三拍、再放手"), relay=True),
            bench(),
            swing(pat, "鞦韆接音符", after=[("O", 1), ("O", 2)]),
            bench(),
            strict(sec(pat, "旋律音符串", [J(0), O(1), J(2), O(3), O(3.5), O(4), O(5.5), J(6.5), O(7.5), J(8.5)],
                "旋律音符串（9 拍）", **M)),
            bench(),
            swing(pat, tut("swing_dash", "鞦韆接衝刺", "這次沒有衝刺環：放手飛出去後，自己抓時間按 Shift 衝刺補距離"), after=[("D", 0.5)]),
            bench(),
            strict(sec(pat, "連續衝刺", [J(0), D(0.5), O(1), D(2), O(2.5), D(3.5), O(4)],
                tut("dash_chain", "連續衝刺", "沒有環提示：跳起來衝刺、踩音符補回衝刺、再衝刺，自己抓時間"), **M)),
            bench(),
            strict(sec(pat, "反拍音符串", [J(0.5), O(1.5), J(2.5), O(3), O(3.5), O(5), J(6), O(7), O(8), J(9), O(9.5), O(10)],
                "反拍音符串（10 拍）", **M)),
            bench(),
            strict(sec(pat, "雨夜長段", [J(0), O(1), J(2), O(3), O(3.5), O(4), O(5.5), J(6.5), O(7.5), O(8.5), J(9.5), O(10), O(10.5)],
                "雨夜長段（11 拍）", **M)),
            bench(),
            swing(pat, "最後的鞦韆", relay=True, after=[("O", 1), ("O", 2)]),
            bench(),
            goal("終點"),
        ], hops=False)
    finally:
        gen_level3.DASH_IGNORE_TAIL = False


def level5(pat):
    """第五關（破碎回憶）：新東西是大音符（跳得高、兩拍落回）和小音符（跳得矮、半拍落回），開頭先展示三種音符的差別。
    鞦韆不再單獨一小段：每座鞦韆都夾在音符串中間（空中踩音符 → 碰到鞦韆抓住 → 放手 → 再接音符）。每段都只有一種過法"""
    import gen_level3
    gen_level3.DASH_IGNORE_TAIL = True
    S = dict(FO, flow=True)
    show = Chunk(26)
    show.fill(0, 25, 16, 19, "#")
    show.fill(3, 3, 15, 15, "P")
    opening = {"hint": "第五關・破碎回憶",
               "rows": show.lines(), "showcases": [[6, 11]]}
    try:
        return seamless(pat, [
            opening,
            strict(sec(pat, "大小音符", [J(0), O(0.5), OH(1.5), O(3.5), OL(4.5), O(5)],
                tut("orb_size", "大小音符", "大顆的音符跳得很高，兩拍才落回原本的高度；小顆的跳很矮，半拍就落回來"), **S)),
            bench(),
            chain_swing(pat, tut("swing_mid", "音符接鞦韆", "在空中碰到鞦韆也會抓住：踩完音符飛過去，盪兩拍到最前面再放手"),
                        [("O", 0.5), ("O", 1.5)], [("O", 1), ("OH", 2), ("O", 4)]),
            bench(),
            strict(sec(pat, "音符往下", [J(0), O(0.5), O(1), O(2.5), O(3), O(4), O(4.5)], "音符往下", **S)),
            bench(),
            chain_swing(pat, "鞦韆夾大小音符", [("O", 0.5), ("OH", 1.5)], [("O", 1), ("OL", 2), ("O", 2.5), ("O", 3.5)], grab=2.0),
            bench(),
            strict(sec(pat, "半拍連踩", [J(0), O(1), O(1.5), O(2), O(2.5), O(4), O(4.5)],
                tut("half", "半拍連踩", "音符排得很密：一拍裡按兩下空白鍵往上爬，最高點再等一拍半落下來"), **S)),
            bench(),
            strict(sec(pat, "大音符接衝刺", [J(0), O(0.5), OH(1.5), D(2.5), O(3.5), D(4), O(4.5), O(5.5)],
                "大音符接衝刺", **S)),
            bench(),
            chain_swing(pat, "鞦韆長串", [("O", 0.5), ("O", 1), ("OL", 2), ("O", 2.5)],
                        [("O", 1), ("D", 1.5), ("O", 2.5), ("OH", 3.5), ("O", 5.5)]),
            bench(),
            strict(sec(pat, "反拍長段", [J(0.5), O(1), O(1.5), O(3), R(3.5), O(4.5), O(5), O(5.5), O(7), O(8), O(8.5)],
                "反拍長段（9 拍）", **S)),
            bench(),
            strict(sec(pat, "連續衝刺", [J(0), D(0.5), O(1), D(2), OH(2.5), D(4.5), O(5)],
                "連續衝刺（大音符）", **S)),
            bench(),
            chain_swing(pat, "鞦韆接衝刺環", [("O", 0.5), ("O", 1), ("O", 2)],
                        [("R", 0.5), ("O", 1.5), ("OH", 2.5), ("O", 4.5), ("O", 5.5)]),
            bench(),
            strict(sec(pat, "雨夜長段", [J(0.5), O(1), O(1.5), O(3), R(3.5), O(4.5), O(5), O(5.5), O(7), O(8), O(8.5),
                                         O(9), O(10.5), O(11)], "雨夜長段（12 拍）", **S)),
            bench(),
            chain_swing(pat, "最後的鞦韆", [("O", 0.5), ("O", 1.5), ("OH", 2.5)],
                        [("O", 1), ("O", 1.5), ("OL", 2.5), ("O", 3), ("D", 3.5), ("O", 4.5)], grab=2.0),
            bench(),
            goal("終點"),
        ], hops=False)
    finally:
        gen_level3.DASH_IGNORE_TAIL = False


T = lambda n: n / 3.0  ## 三連音拍子：T(10) = 第 3⅓ 拍


def level6(pat):
    """第六關（隱藏關，第五關過關才出現）：新東西是三連音（一拍平均三下）。每段都很長（14～17 拍），
    小／一般／大音符混著上上下下，夾連續衝刺和音符串中間的鞦韆。段落由隨機搜尋產生、再經產生器嚴格驗證（只有一種過法）"""
    import gen_level3
    gen_level3.DASH_IGNORE_TAIL = True
    S = dict(FO, flow=True)
    try:
        return seamless(pat, [
            intro("第六關・終極節奏\n新東西：三連音（快的一拍三下、慢的兩拍三下）。每一段都很長，小、中、大音符上上下下"),
            strict(sec(pat, "三連音", [J(0), O(0.5), OL(1.5), OH(2), O(4), OL(T(14)), OL(T(16)), O(6), O(T(19)), O(T(20)), OH(8), O(10)],
                tut("triplet", "三連音", "外圈偏橘、上面標 3 的是三連音：快的一拍按三下（往上爬），慢的兩拍按三下（小音符，往下走）"), **S)),
            bench(),
            chain_swing(pat, "鞦韆長串", [("O", 0.5), ("O", 1), ("OL", 2), ("O", 2.5), ("D", 3)],
                        [("OH", 1), ("O", 3), ("D", 3.5), ("O", 4.5), ("OL", 5.5), ("O", 6), ("O", 7)]),
            bench(),
            strict(sec(pat, "快慢三連音", [J(0), O(0.5), OL(1.5), O(2), OL(T(8)), OL(T(10)), O(4), O(T(13)), O(T(14)), O(6), OL(T(20)), OL(T(22)), O(8), O(T(25)), O(T(26)), OH(10)], "快慢三連音（10 拍）", **S)),
            bench(),
            strict(sec(pat, "衝刺長段", [J(0), O(0.5), OL(1.5), OH(2), OL(3), OH(3.5), O(5.5), OL(7), OL(7.5), OL(8), O(8.5), D(9), O(10), OH(11), O(12.5), O(13.5), D(14), O(14.5), O(16)], "衝刺長段（16 拍）", **S)),
            bench(),
            chain_swing(pat, "鞦韆大長串", [("O", 0.5), ("OL", 1.5), ("O", 2), ("OH", 3)],
                        [("O", 1), ("O", 1.5), ("OL", 2.5), ("O", 3), ("D", 3.5), ("O", 4.5), ("OH", 5.5), ("O", 7.5)], grab=2.0),
            bench(),
            strict(sec(pat, "三連音長段", [J(0), O(0.5), O(1.5), OH(2.5), O(3.5), OH(5), O(7), OL(T(23)), OL(T(25)), O(9), O(T(28)), O(T(29)), O(11), O(T(34)), O(T(35)), O(13), OH(14), O(16)], "三連音長段（16 拍）", **S)),
            bench(),
            strict(sec(pat, "混合長段", [J(0), O(0.5), D(1), O(1.5), D(2), O(2.5), O(4), D(4.5), OL(5), OH(5.5), OL(7.5), O(8), OL(T(26)), OL(T(28)), O(10), O(11), OL(T(35)), OL(T(37)), O(13), O(14)], "混合長段（14 拍）", **S)),
            bench(),
            strict(sec(pat, "終極長段", [J(0), O(0.5), OL(1.5), O(2), O(T(7)), O(T(8)), OH(4), O(5.5), O(7), O(8), O(T(25)), O(T(26)), O(10), O(T(31)), O(T(32)), O(12), O(T(37)), O(T(38)), O(14), D(14.5), O(15), O(16)], "終極長段（16 拍）", **S)),
            bench(),
            goal("終點"),
        ], hops=False)
    finally:
        gen_level3.DASH_IGNORE_TAIL = False


LEVELS = {
    1: (level1, "Campaign1Data", "正式版第一關・教學：自動前進、固定跳躍、尖刺預告、空中衝刺、光柱、黃色音符。"),
    2: (level2, "Campaign2Data", "正式版第二關：衝刺環、節拍平台、旋律平台，後半和第一關的東西混合。"),
    3: (level3, "Campaign3Data", "正式版第三關：彈簧床（和音符、衝刺環接在一起）、大量黃色音符與反拍、高低地形。"),
    4: (level4, "Campaign4Data", "正式版第四關（雨夜街道）：盪鞦韆、音符上下、音符串夾旋律平台。"),
    5: (level5, "Campaign5Data", "正式版第五關（破碎回憶）：大音符、小音符，鞦韆夾在音符串中間。"),
    6: (level6, "Campaign6Data", "正式版第六關（隱藏關）：三連音、大中小音符上下、超長段落。"),
}


def main():
    wanted = [int(a) for a in sys.argv[1:] if a.isdigit()] or list(LEVELS)
    ## 每一關都依序產生（教學文字「第一次出現」是跨關算的），只寫出指定的關
    for n in sorted(LEVELS):
        build, cls, desc = LEVELS[n]
        if n not in wanted:
            build(Patterns())
            continue
        print(f"═════ 正式版第 {n} 關 ═════")
        pat = Patterns()
        chunks = fold_cycle(pat, build(pat))
        text = render_level(cls, [desc, "地形由 tools/campaign.py（tools/course_kit.py）的物理模擬算出。"],
                            pat.items, chunks)
        if "--write" in sys.argv:
            out = Path(__file__).resolve().parent.parent / f"scripts/level/campaign_{n}_data.gd"
            out.write_text(text, encoding="utf-8")
            print("written", out.name)


if __name__ == "__main__":
    main()
