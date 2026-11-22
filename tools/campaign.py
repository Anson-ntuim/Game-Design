"""正式版關卡（重新設計）：每一關加入一樣新東西，再和學過的混在一起。

用法：python3 tools/campaign.py [關卡編號 ...] [--write]
輸出 scripts/level/campaign_<n>_data.gd（class CampaignNData）。

規則（配合自動前進＋固定高度跳躍）：
  - 每段開頭都有起跳旗：角色停在旗子旁倒數，GO 後先走一拍，連招第 0 拍才是第一個動作。
  - 跳躍固定一拍落地、半拍在最高點：空中衝刺／穿環／在最高點碰音符都放在半拍。
  - 地形由 tools/course_kit.py 照標準節奏模擬算出，並驗證按錯會失敗。
舊關卡在 scripts/level/archive/（tools/gen_demo.py、tools/ride_levels.py）。
"""

import sys
from pathlib import Path

from design import FULL
from gen_level3 import Chunk, Patterns
from course_kit import section, intro
from level_kit import render_level

J = lambda b: (b, "jump", FULL)
O = lambda b: (b, "orb", FULL)
D = lambda b: (b, "dash", 0)
R = lambda b: (b, "ring", 0)
## 教學關：落腳處不長刺（尖刺留到「彈出尖刺」那段才教）
F = dict(flag=True, island_spikes=False)
## 引導環：環標出該衝刺的那一拍和位置，穿過去就好，不一定要接第二下（拿掉環衝刺一樣過得去，所以不檢查「非用環不可」）
FR = dict(F, require_ring_use=False)
## 有黃色音符的段落：跳和碰音符都在正拍，音符底下不鋪地板（orb_footholds），靠踩音符前進
FO = dict(F, orb_footholds=True)
BENCH = "長椅\n碰到就存檔，倒下會回到這裡"


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
BENCH_MIN = 6
## 平地寬度只能一格一格調（一格約 0.26 拍）：寧可早到一點點（旗子前停不到 EARLY_OK 拍就 GO），不要晚到（晚了要等一整輪）
EARLY_OK = 0.27


def bench(hint=BENCH):
    """先放一個佔位，seamless() 再決定寬度"""
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
    cp = width - 6 if hops else min(4, width - 2)
    c.fill(cp, cp, 15, 15, "C")
    out = {"hint": hint, "rows": c.lines()}
    if hops:
        out["hint"] = "間奏\n平地上有小坑：每兩拍跳一下，跟著節奏跑到下一段"
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
    land = float(x) + (260.0 if act in ("D", "R") else 170.0)
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


def seamless(pat, chunks):
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
        out.append(_bench_chunk(ch["_bench"], width, t_in))
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
                    item[2] = _fold(item[2], int(CYCLE * 2))
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


def pillar(pat, hint, col=12, width=20, open_beat=0.0):
    """單獨的光柱：天花板壓低不能跳過，跑到柱子前被擋住，柱子每 CYCLE 拍在 open_beat 打開一次（出現箭頭），
    那一拍按衝刺穿過。前面的平地會算成剛好在打開前一點點跑到柱子前（seamless 用 sync_plan）。
    幾何沿用舊第一關的光柱走廊檢查（tools/gen_demo.py：不衝、早半拍、晚半拍都過不去）。"""
    from gen_demo import check_gate_hall
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


def trampoline(pat, hint, need=2, approach=7, mat=3, mechanic=""):
    """自動跑走上彈簧床 → 停在床中間 → 每次落床那拍按跳，按滿 need 下就往前彈上高台。
    落床沒按：穿過床掉進下面的坑。回傳的 plan 就是每一下要按的拍（相對 GO 後的第 0 拍）。"""
    ## 走上床面的時間：GO（第 -1 拍）時在起跑點 START_X，一拍跑 RUN
    board = -LEAD + (approach * TILE_PX - START_X) / RUN
    land = float(int(board) + 1)
    if land - board < 0.35:
        land += 1.0
    presses = [land]
    for k in range(1, need):
        presses.append(presses[-1] + TRAMP_BEATS[k])
    h = TRAMP_H[need]
    ## 高台比彈出高度低 80px；牆放在「腳高過台面」那段時間的中間經過的位置
    rows = int((h - 80) // TILE_PX)
    top_px = rows * TILE_PX
    vy = (2 * GRAVITY_PX * h) ** 0.5
    disc = (vy * vy - 2 * GRAVITY_PX * top_px) ** 0.5
    t1, t2 = (vy - disc) / GRAVITY_PX, (vy + disc) / GRAVITY_PX
    x_c = (approach + mat / 2) * TILE_PX
    vx = 310.0
    wall_x = x_c + 12 + vx * (t1 + t2) / 2
    wall_col = int(-(-wall_x // TILE_PX))
    assert wall_col >= approach + mat + 1, ("彈簧床和高台之間要留坑", wall_col)
    land_col = int((x_c + vx * t2) // TILE_PX)
    width = max(wall_col + 6, land_col + 5)
    c = Chunk(width)
    c.fill(0, approach - 1, 16, 19, "#")
    c.fill(wall_col, width - 1, 16 - rows, 19, "#")
    c.fill(wall_col, wall_col, 16 - rows, 19, "%")
    demo = ["."] * 16
    for b in presses:
        demo[round(b * 2) % 16] = "L"
    c.fill(5, 5, 15, 15, pat.add({"kind": "flag", "notes": "", "demo": "".join(demo)}))
    plan = [[b, "L", round(x_c)] for b in presses]
    out = {"hint": hint, "rows": c.lines(), "plan": plan, "trampolines": [[approach, 16, mat, need]]}
    if mechanic:
        out["mechanic"] = mechanic
    print(f"[彈簧床] 按 {presses} 拍、彈到 {h:.0f}px 上 {rows} 格高台（牆在第 {wall_col} 格）")
    return out


def sec(pat, name, script, hint, **kw):
    """course_kit.section 再記下光柱的拍子（穿光柱的衝刺不另外放「>>」提示）"""
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
        intro("第一關・跟著拍子跑\n角色會自己往前跑，你只要按空白鍵跳。"
              "跑到旗子旁會停下倒數，數到 0（GO）就出發；先走一拍，再跳"),
        sec(pat, "跳過小坑", [J(0), J(2), J(3), J(4)],
                "跳過小坑\nGO 後走一拍就跳。跳一下剛好一拍落地：跳、空一拍，再連跳三下", **F),
        bench(BENCH),
        sec(pat, "跳上高台", [J(0), J(2), J(4)],
                "跳上高台\n一樣是一拍一跳，只是落在更高的地方；中間落地後空一拍再跳",
                floor=[("pit", 1, 1), ("pit", 2, 1)], final_rise=3, **F),
        bench(BENCH),
        sec(pat, "彈出尖刺", [J(1), J(3), J(5), J(7)],
                "彈出尖刺\n地上的尖刺會在第 1、3、5、7 拍彈出。前半拍尖端會先冒出來閃：看到它冒出來就跳",
                floor="ground", spikes=[1, 3, 5, 7], flow=True, **F),
        bench(BENCH),
        sec(pat, "空中衝刺", [J(0), R(0.5)],
                "空中衝刺\n坑太寬跳不過：起跳後半拍（跳到最高點）會碰到衝刺環，那一拍按 C／Shift 穿過去，往前衝一大段", **FR),
        bench(BENCH),
        pillar(pat, "光柱\n光柱擋住路、頭上也過不去：跑到柱子前會被擋住。兩側光條收到柱子上、出現往右的箭頭那一拍，按 C／Shift 衝刺穿過去"),
        bench(BENCH),
        sec(pat, "跳起來衝光柱", [J(0), D(0.5)],
                "跳起來衝光柱\n這根光柱在坑上方：正拍起跳，跳到最高點（半拍）光柱打開，在空中衝刺穿過去",
                gates=[0.5], **F),
        bench(BENCH),
        far_landing(sec(pat, "黃色音符", [J(0), O(1), O(2)],
                "黃色音符\n音符浮在坑上，只在正拍亮。正拍起跳，下一拍外圈縮到音符上時再按一次跳；兩顆都踩才到得了對岸", **FO)),
        bench(BENCH),
        far_landing(sec(pat, "連續音符", [J(0), O(1), O(2), O(3), O(4)],
                "連續音符\n一排音符浮在坑上：起跳後每一拍碰一顆、按一次跳，一顆接一顆踩過去，全部在正拍", **FO)),
        bench(BENCH),
        far_landing(sec(pat, "小複習", [J(0), J(1), D(1.5), J(3), O(4), O(5)],
                "小複習\n跳、再跳起來衝過光柱，落地後跳一次、接著兩拍都踩音符", gates=[1.5], **FO)),
        goal("終點\n第一關完成！下一關會加入新的東西，再和這關學的混在一起"),
    ])


def level2(pat):
    """第二關：衝刺環 → 節拍平台 → 旋律平台，後半段和第一關的音符、光柱、衝刺混在一起"""
    return seamless(pat, [
        intro("第二關・環與平台\n新東西：衝刺環、節拍平台、旋律平台。後半段會和第一關學的音符、光柱、衝刺混在一起"),
        sec(pat, "衝刺環", [J(0), R(0.5)],
                "衝刺環\n衝刺環標出要衝刺的位置和拍子：外圈縮到環上那一拍按衝刺穿過去", **FR),
        bench(BENCH),
        sec(pat, "連穿衝刺環", [J(0), R(0.5), R(1.5)],
                "連穿衝刺環\n穿過環會補回空中衝刺：穿第一環，下一拍再穿第二環，一路飛過大坑", **F),
        bench(BENCH),
        sec(pat, "節拍平台", [J(0), J(2), J(4), J(6)],
                "節拍平台\n黃、藍平台每兩拍輪流出現，交接的那一拍兩色都在：在那一拍跳到另一色",
                floor="beat", flow=True, final_rise=2, **F),
        bench(BENCH),
        sec(pat, "旋律平台", [J(0), J(2), J(4), J(6)],
                "旋律平台\n綠色平台照旋律一塊接一塊亮起，只亮一下：每兩拍跳到下一塊，停下來就會掉下去",
                floor="melody", flow=True, final_rise=2, **F),
        bench(BENCH),
        sec(pat, "平台衝刺", [J(0), R(0.5), J(2), R(2.5), J(4), J(6)],
                "平台衝刺\n節拍平台離得更遠：跳起來在最高點穿過衝刺環，才搆得到下一色",
                floor="beat", flow=True, final_rise=2, **FR),
        bench(BENCH),
        far_landing(sec(pat, "音符接環", [J(0), O(1), O(2), R(2.5)],
                "音符接環\n踩兩顆音符，第二顆跳起來後在最高點穿過衝刺環過坑", **dict(FO, require_ring_use=False))),
        bench(BENCH),
        sec(pat, "坑與平台", [J(0), J(2), J(3), J(5), J(7)],
                "坑與平台\n地面、旋律平台、節拍平台接在一起，一路跳到底不能停",
                floor=["pit", "melody", "beat"], flow=True, final_rise=2, **F),
        bench(BENCH),
        sec(pat, "環與光柱", [J(0), R(0.5), D(1.5), J(4), J(5), R(5.5), D(6.5)],
                "環與光柱\n旋律平台上穿環、衝過光柱，落地後連跳兩下再來一次",
                floor="melody", flow=True, gates=[1.5, 6.5], **F),
        bench(BENCH),
        sec(pat, "安可", [J(0), R(0.5), D(1.5), J(4), R(4.5), D(5.5)],
                "安可\n最後一段：環、光柱、旋律平台全部一起，跑到終點",
                floor="melody", flow=True, finale=True, gates=[1.5, 5.5], **F),
    ])


def level3(pat):
    """第三關：新東西是彈簧床；開始用反拍（半拍起跳），並把前兩關的尖刺、音符、光柱、衝刺環、平台混進來"""
    return seamless(pat, [
        intro("第三關・彈簧床與反拍\n新東西：彈簧床。這關也開始有「反拍」：在兩拍中間（喀、噠的噠）起跳"),
        trampoline(pat, "彈簧床\n站上去會停在床中間一直彈。落床那一拍按跳就升一段，升兩段就飛上前面的高台；沒按到就再彈一次、下次再按", need=2),
        bench(BENCH),
        sec(pat, "反拍跳", [J(0.5), J(1.5), J(2.5), J(3.5)],
            "反拍跳\n這次在兩拍中間起跳：跟著「一、噠、二、噠」的噠按", **F),
        bench(BENCH),
        sec(pat, "反拍尖刺", [J(0.5), J(2.5), J(4.5), J(6.5)],
            "反拍尖刺\n尖刺在正拍彈出：提早半拍起跳，彈出時剛好在空中",
            floor="ground", spikes=[1, 3, 5, 7], flow=True, **F),
        bench(BENCH),
        trampoline(pat, "彈到最高\n要升三段：一拍、一拍、兩拍。沒按到不會掉，下一次落床再按", need=3),
        bench(BENCH),
        far_landing(sec(pat, "反拍音符", [J(0.5), O(1.5), O(2.5)],
            "反拍音符\n半拍起跳，音符也在反拍亮：一、噠（跳）、二、噠（踩）、三、噠（踩）", **FO)),
        bench(BENCH),
        sec(pat, "環與光柱", [J(0), R(0.5), J(2), D(2.5)],
            "環與光柱\n先跳起來穿環，落地後再跳一次，最高點衝過光柱", gates=[2.5], **FR),
        bench(BENCH),
        sec(pat, "反拍環", [J(0.5), R(1), J(2.5), R(3)],
            "反拍環\n反拍起跳，正拍在最高點穿環：噠（跳）、一（衝）、噠（跳）、二（衝）", **FR),
        bench(BENCH),
        trampoline(pat, "彈簧床・再一次\n三段：一拍、一拍、兩拍", need=3),
        bench(BENCH),
        sec(pat, "反拍光柱", [J(0.5), J(1.5), D(2)], "反拍光柱\n反拍連跳兩下，第二下的最高點剛好是正拍，衝過光柱",
            gates=[2], **F),
        bench(BENCH),
        sec(pat, "旋律切分", [J(0), J(1.5), J(3.5), J(5), J(7)],
            "旋律切分\n旋律平台換成切分節奏：正拍、反拍、反拍、正拍、正拍",
            floor="melody", flow=True, final_rise=2, **F),
        bench(BENCH),
        far_landing(sec(pat, "反拍音符接環", [J(0.5), O(1.5), O(2.5), R(3)],
            "反拍音符接環\n反拍踩兩顆音符，正拍穿環過坑", **dict(FO, require_ring_use=False))),
        bench(BENCH),
        sec(pat, "總複習", [J(0), J(1), R(1.5), J(3), J(3.5), J(4.5), D(5)],
            "總複習\n正拍連跳穿環，落地後切換成反拍連跳，最後衝過光柱",
            gates=[5], **FR),
        bench(BENCH),
        trampoline(pat, "最後一跳\n彈簧床升三段，飛上終點前的高台", need=3),
        bench(BENCH),
        goal("終點\n第三關完成！"),
    ])


LEVELS = {
    1: (level1, "Campaign1Data", "正式版第一關・教學：自動前進、固定跳躍、尖刺預告、空中衝刺、光柱、黃色音符。"),
    2: (level2, "Campaign2Data", "正式版第二關：衝刺環、節拍平台、旋律平台，後半和第一關的東西混合。"),
    3: (level3, "Campaign3Data", "正式版第三關：彈簧床、反拍，和前兩關的機關混合。"),
}


def main():
    wanted = [int(a) for a in sys.argv[1:] if a.isdigit()] or list(LEVELS)
    for n in wanted:
        build, cls, desc = LEVELS[n]
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
