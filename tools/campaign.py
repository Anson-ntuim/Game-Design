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
## 起跳旗每 CYCLE 拍放行一次（機關都折成 4 拍一輪，見 fold_cycle）
CYCLE = 4.0
LEAD = 1.0
BENCH_MIN = 6
## 平地寬度只能一格一格調（一格約 0.26 拍）：寧可早到一點點（旗子前停不到 EARLY_OK 拍就 GO），不要晚到（晚了要等一整輪）
EARLY_OK = 0.27


def bench(hint=BENCH):
    """先放一個佔位，seamless() 再決定寬度"""
    return {"_bench": hint}


def _bench_chunk(hint, width):
    c = Chunk(width)
    c.fill(0, width - 1, 16, 19, "#")
    c.fill(min(4, width - 2), min(4, width - 2), 15, 15, "C")
    return {"hint": hint, "rows": c.lines()}


def _exit_beat(chunk):
    """標準節奏跑到這一段右端時是第幾拍（以這一段連招第 0 拍為 0）"""
    width_px = max(len(r) for r in chunk["rows"]) * TILE_PX
    b, act, x = (chunk.get("plan") or chunk["sync_plan"])[-1]
    b, x = float(b), float(x)
    if act in ("D", "R"):
        b, x = b + DASH_BEATS, x + DASH_PX
    return b + (width_px - x) / RUN


def seamless(chunks):
    out = []
    for i, ch in enumerate(chunks):
        if "_bench" not in ch:
            out.append(ch)
            continue
        prev = chunks[i - 1] if i > 0 else None
        nxt = chunks[i + 1] if i + 1 < len(chunks) else None
        width = BENCH_MIN
        timed = lambda c: c and (c.get("plan") or c.get("sync_plan"))
        if timed(prev) and timed(nxt):
            ## 下一段要在哪一拍到哪裡：有旗子的段落 = GO 拍到起跑點；光柱 = 打開那拍到柱子前
            if nxt.get("plan"):
                target_x, target_beat = START_X, -LEAD
            else:
                target_beat, _, target_x = nxt["sync_plan"][0]
            base = _exit_beat(prev) + target_x / RUN
            for w in range(BENCH_MIN, BENCH_MIN + 40):
                early = (target_beat - (base + w * TILE_PX / RUN)) % CYCLE
                if early < EARLY_OK:
                    width = w
                    break
            arrive = base + width * TILE_PX / RUN
            print(f"  長椅寬 {width} 格：第 {arrive:.2f} 拍到下一段，提早 {(target_beat - arrive) % CYCLE:.2f} 拍")
        out.append(_bench_chunk(ch["_bench"], width))
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
    """把機關的節奏型都變成 CYCLE 拍一輪，起跳旗才能每 CYCLE 拍放行（等待最多 CYCLE 拍）"""
    slots = int(CYCLE * 2)
    for spec in pat.items.values():
        if spec.get("kind") == "flag":
            spec["cycle"] = CYCLE
        elif spec.get("notes"):
            spec["notes"] = _fold(spec["notes"], slots)
    for ch in chunks:
        for key in ("orbs", "rings"):
            for item in ch.get(key, []):
                item[2] = _fold(item[2], slots)
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


def goal(hint):
    c = Chunk(14)
    c.fill(0, 13, 16, 19, "#")
    c.fill(9, 9, 15, 15, "G")
    return {"hint": hint, "rows": c.lines()}


def level1(pat):
    """第一關・教學：跳 → 連跳 → 上高台 → 彈出尖刺 → 空中衝刺 → 黃色音符 → 小複習"""
    return seamless([
        intro("第一關・跟著拍子跑\n角色會自己往前跑，你只要按空白鍵跳。"
              "跑到旗子旁會停下倒數，數到 0（GO）就出發；先走一拍，再跳"),
        section(pat, "跳過小坑", [J(0), J(2), J(3), J(4)],
                "跳過小坑\nGO 後走一拍就跳。跳一下剛好一拍落地：跳、空一拍，再連跳三下", **F),
        bench(BENCH),
        section(pat, "跳上高台", [J(0), J(2), J(4)],
                "跳上高台\n一樣是一拍一跳，只是落在更高的地方；中間落地後空一拍再跳",
                floor=[("pit", 1, 1), ("pit", 2, 1)], final_rise=3, **F),
        bench(BENCH),
        section(pat, "彈出尖刺", [J(1), J(3), J(5), J(7)],
                "彈出尖刺\n地上的尖刺會在第 1、3、5、7 拍彈出。前一拍尖端會先冒出來閃：看到它冒出來，下一拍就跳",
                floor="ground", spikes=[1, 3, 5, 7], flow=True, **F),
        bench(BENCH),
        section(pat, "空中衝刺", [J(0), D(0.5)],
                "空中衝刺\n坑太寬跳不過：起跳後半拍（跳到最高點）按 C／Shift，往前衝一大段", **F),
        bench(BENCH),
        pillar(pat, "光柱\n光柱擋住路、頭上也過不去：跑到柱子前會被擋住。兩側光條收到柱子上、出現往右的箭頭那一拍，按 C／Shift 衝刺穿過去"),
        bench(BENCH),
        section(pat, "跳起來衝光柱", [J(0), D(0.5)],
                "跳起來衝光柱\n這根光柱在坑上方：正拍起跳，跳到最高點（半拍）光柱打開，在空中衝刺穿過去",
                gates=[0.5], **F),
        bench(BENCH),
        far_landing(section(pat, "黃色音符", [J(0), O(1), O(2)],
                "黃色音符\n音符浮在坑上，只在正拍亮。正拍起跳，下一拍外圈縮到音符上時再按一次跳；兩顆都踩才到得了對岸", **FO)),
        bench(BENCH),
        far_landing(section(pat, "連續音符", [J(0), O(1), O(2), O(3), O(4)],
                "連續音符\n一排音符浮在坑上：起跳後每一拍碰一顆、按一次跳，一顆接一顆踩過去，全部在正拍", **FO)),
        bench(BENCH),
        far_landing(section(pat, "小複習", [J(0), J(1), D(1.5), J(3), O(4), O(5)],
                "小複習\n跳、再跳起來衝過光柱，落地後跳一次、接著兩拍都踩音符", gates=[1.5], **FO)),
        goal("終點\n第一關完成！下一關會加入新的東西，再和這關學的混在一起"),
    ])


LEVELS = {
    1: (level1, "Campaign1Data", "正式版第一關・教學：自動前進、固定跳躍、尖刺預告、空中衝刺、光柱、黃色音符。"),
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
