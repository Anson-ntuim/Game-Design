"""產生 Demo 關卡：scripts/level/demo_1_data.gd ～ demo_6_data.gd。

注意：資料編號沿用原專案，選單第 4 關 = 資料 6，選單第 7 關 = 資料 5。
重建這兩關：python3 tools/gen_demo.py 5 6 --write；設計來源為 climbing_courses.py。

第一關一段教一個東西（音符、長按、輕點、光柱、空中衝刺、衝刺環），每段之後放長椅；
第二關把學過的東西兩兩組合；第三關先各介紹旋律平台、節拍平台、尖刺，後段混在一起，
落腳處都會消失或長刺（section 的 flow），不能停在原地等下一小節；
第四關每段都是第三關安可的難度，6～8 下輸入混合所有機制，最後的安可是 48 拍、有高低差的長段落。
節奏型段落由 course_kit.section 照標準節奏模擬算出地形，並驗證按錯會失敗。
光柱走廊是手工地形，用 check_gate_hall 模擬「在拍子上衝刺」能過、「晚半拍衝刺」會被擋住。
--judge 換成選關畫面的其他判定難度來驗證（地形不變，寫檔一律用普通）。

用法：python3 tools/gen_demo.py [關卡編號 ...] [--judge easy|normal|hard] [--write]
"""

import sys
from pathlib import Path

import sim_player
from sim_player import SPB, DT, TILE
from design import TAP, FULL
from gen_level3 import Patterns, Chunk, Gate, solid_rect, simulate
from course_kit import section, bench, intro
from level_kit import render_level

J = lambda b, h=FULL: (b, "jump", h)
O = lambda b, h=FULL: (b, "orb", h)
D = lambda b: (b, "dash", 0)
R = lambda b: (b, "ring", 0)
T = TAP

SECOND_HALF = "......xxxxxxxxxx"
## 模擬器的光牆固定 16 格循環；地圖上的 | 是 8 格 "x.x.x.x."，一樣每拍打開
EVERY_BEAT = "x.x.x.x.x.x.x.x."
BENCH = "長椅\n坐下就存檔：倒下後會回到最後坐過的長椅"
## 和 GameState.DIFFICULTIES 相同：x 拍前／後幾幀（60 fps）內按下算準
JUDGES = {"easy": (20, 20), "normal": (7, 8), "hard": (4, 5)}


def set_judge(name):
    early, late = (f / 60.0 for f in JUDGES[name])
    sim_player.ORB_EARLY, sim_player.ORB_LATE = early, late
    Gate.EARLY, Gate.LATE = early, late


def check_gate_hall(width, gate_cols, ceil_row):
    """光柱走廊：一路往右走，被光柱擋住後在下一拍衝刺。
    回傳標準節奏的衝刺拍；並確認每一下不衝、早半拍、晚半拍都會卡在光柱前"""
    solids = [solid_rect(0, width + 40, 16, 19), solid_rect(4, width - 1, 0, ceil_row)]
    gates = [Gate(c, ceil_row + 1, 15, EVERY_BEAT) for c in gate_cols]
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


def gate_hall(hint):
    width, gate_cols, ceil_row = 26, [10, 16, 22], 12
    check_gate_hall(width, gate_cols, ceil_row)
    c = Chunk(width)
    c.fill(0, width - 1, 16, 19, "#")
    c.fill(4, width - 1, 0, ceil_row, "%")
    for col in gate_cols:
        c.fill(col, col, ceil_row + 1, 15, "|")
    return {"hint": hint, "rows": c.lines()}


def goal(hint):
    c = Chunk(14)
    c.fill(0, 13, 16, 19, "#")
    c.fill(9, 9, 15, 15, "G")
    return {"hint": hint, "rows": c.lines()}


def demo1(pat):
    ## 教學關保留旗子示範
    F = dict(flag=True)
    return [
        intro("移動與跳躍\n方向鍵／WASD 移動，空白鍵跳：輕點小跳，按住一下聽到延音就是大跳。每段開頭站在旗子旁按 ↑ 看示範"),
        section(pat, "黃色音符", [J(0), O(1)],
                "黃色音符：遊戲核心\n音符只在拍子上亮起。先起跳，外圈縮到音符上時，在空中碰著它再按一次跳", **F),
        bench(BENCH),
        section(pat, "連續長按", [J(0), O(1), O(2), O(3)],
                "連續音符：長按\n每拍碰一顆音符，每顆都按住跳鍵，就會一路往上爬過大坑", **F),
        bench(BENCH),
        section(pat, "輕點", [J(0), O(1, T), O(1.5, T), O(2, T), O(2.5, T)],
                "輕點：跳得比較低\n音符排成一排時每半拍輕點空白鍵一下，平平地飛過去。頭上有雷射，按住就會撞上", **F),
        bench(BENCH),
        gate_hall("藍色光柱\n兩側光條收到柱子上、出現 >> 的那一拍按 C／Shift 衝刺穿過去，按早按晚都會被擋住"),
        bench(BENCH),
        section(pat, "空中衝刺", [J(0), D(1)],
                "跳起來衝刺\n坑太寬跳不過：起跳後下一拍按 C／Shift 在空中衝刺。空中只能衝一次，落地才補回", **F),
        bench(BENCH),
        section(pat, "衝刺環", [J(0), R(1), R(2), D(3)],
                "衝刺環：連著穿\n起跳後衝進亮著的環會補回空中衝刺；"
                "下一拍再穿第二環，最後再衝一下飛過寬坑", **F),
        goal("終點\n走到終點的旗子就過關！"),
    ]


def demo2(pat):
    return [
        intro(""),
        section(pat, "音符補衝刺", [J(0), D(1), O(2), D(3)], ""),
        bench(""),
        section(pat, "長短交替", [J(0), O(1), O(2, T), O(2.5, T), O(3, T)], ""),
        bench(""),
        section(pat, "光牆衝刺", [J(0), O(1, T), O(1.5, T), D(2)], "", gates=[2]),
        bench(""),
        section(pat, "安可", [J(0), R(1), O(2), R(3), O(4, T), O(4.5, T)], "", finale=True),
    ]


def demo3(pat):
    return [
        intro(""),
        section(pat, "旋律平台", [J(0), J(2), J(4), J(6)],
                "旋律平台\n綠色平台照旋律一塊接一塊亮起，只亮一下：每兩拍長按跳到下一塊，停下來就會掉下去",
                floor="melody", flow=True, final_rise=2),
        bench(""),
        section(pat, "節拍平台", [J(0), J(2), J(4), J(6)],
                "節拍平台\n黃、藍平台每兩拍輪流出現，交接的那一拍兩色都在：在拍點上長按跳到另一色",
                floor="beat", flow=True, final_rise=2),
        bench(""),
        section(pat, "尖刺", [J(1), J(3), J(5), J(7)],
                "尖刺\n整排地刺在第 1、3、5、7 拍一起彈出：在那一拍按住跳，刺冒出來時人在空中就躲得掉",
                floor="ground", spikes=[1, 3, 5, 7], flow=True),
        bench(""),
        section(pat, "旋律接音符", [J(0), O(1), J(3.5), O(4.5), J(7)], "", floor="melody", flow=True, final_rise=2),
        bench(""),
        section(pat, "節拍衝刺", [J(0), D(1), J(3), D(4), J(6)], "", floor="beat", flow=True, final_rise=2),
        bench(""),
        section(pat, "尖刺接平台", [J(0), O(1, T), O(1.5, T), J(3), J(5), J(7)], "",
                floor=["pit", "melody", "beat"], flow=True, final_rise=2),
        bench(""),
        section(pat, "安可", [J(0), R(1), D(2), J(4), O(5), R(6), D(7)], "",
                floor="melody", flow=True, finale=True, gates=[2, 7]),
    ]


def demo4(pat):
    return [
        intro(""),
        section(pat, "音符衝刺鏈", [J(0), D(1), O(2), D(3), O(4), D(5)], "", flow=True, gates=[1, 3, 5], final_rise=2),
        bench(""),
        section(pat, "尖刺音符", [J(1), O(2), J(5), J(7)], "", floor="ground", spikes=[1, 3, 5, 7], flow=True),
        bench(""),
        section(pat, "節拍環", [J(0), R(1), D(2), J(4), R(5), D(6)], "",
                floor="beat", flow=True, gates=[2, 6], final_rise=2),
        bench(""),
        section(pat, "旋律輕點", [J(0), O(1, T), O(1.5, T), O(2, T), J(4), O(5), R(6), D(7)], "",
                floor="melody", flow=True, gates=[7], final_rise=2),
        bench(""),
        section(pat, "尖刺衝刺", [J(1), J(3), O(4), D(5), J(7)], "", floor="ground", spikes=[1, 3, 7], flow=True),
        bench(""),
        section(pat, "混合地形", [J(0), O(1), J(3.5), D(4.5), J(6)], "",
                floor=["melody", "beat"], flow=True, final_rise=2),
        bench(""),
        section(pat, "環與光柱", [J(0), R(1), D(2), J(4), O(5), R(6), D(7)], "",
                floor="melody", flow=True, gates=[2, 7], final_rise=2),
        bench(""),
        section(pat, "安可", FINALE4, "", floor=FINALE4_FLOOR, flow=True, finale=True,
                gates=[5, 11, 19, 24, 32, 39, 48]),
    ]


## 檔案編號沿用舊資料：Demo6Data 是選單第四關，Demo5Data 是選單第七關。
NORMAL = 2400
LIGHT = 1000


def demo5(pat):
    from climbing_courses import variations
    return variations(pat)


## 第四關的安可：6 小節不停的長段落，起跳、衝刺、光柱都在正拍（只有輕點音符排在半拍）。
## floor 每項是（種類, 比地面高幾格, 在上面起跳幾次）
FINALE4 = [
    J(0), O(1), J(3), R(4), D(5), J(7),
    O(8, T), O(8.5, T), J(10), D(11), J(13), J(15),
    O(16), J(18), D(19), J(21), O(22), R(23), D(24),
    J(26), O(27, T), O(27.5, T), O(28, T), J(30), R(31), D(32),
    J(34), O(35), O(36), J(38), D(39), J(41),
    J(43), O(44, T), O(44.5, T), J(46), R(47), D(48),
]
## 第 36 拍長按音符後要在第 38 拍起跳，坑要墊高 6 格才落得夠早
FINALE4_FLOOR = [
    ("pit", 3, 1), ("beat", 0, 1), ("melody", 2, 1), ("row", 1, 2),
    ("pit", 4, 1), ("melody", 1, 1), ("beat", 2, 1), ("pit", 1, 1),
    ("melody", 0, 1), ("pit", 6, 1), ("row", 2, 2), ("beat", 2, 1),
]


def demo6(pat):
    from climbing_courses import low_gravity
    return low_gravity(pat)


LEVELS = {
    1: (demo1, "Demo1Data", "Demo 第一關・基礎教學：音符、長按、輕點、光柱、空中衝刺、衝刺環，一段教一樣。"),
    2: (demo2, "Demo2Data", "Demo 第二關・組合：音符補衝刺、長短交替、音符接光牆、衝刺環接音符。"),
    3: (demo3, "Demo3Data", "Demo 第三關・節奏地形：旋律平台、節拍平台、尖刺，後段一路跑到底不能停。"),
    4: (demo4, "Demo4Data", "Demo 第四關・挑戰：每段都混合音符、衝刺環、光柱和節奏地形，最後 48 拍高高低低一路跑到底。"),
    5: (demo5, "Demo5Data",
        "選單第七關・草圖終章：上排／下排後接八拍循環×3（原速→1.5×→2×）。"),
    6: (demo6, "Demo6Data",
        "選單第四關・輕重力：浮空階梯、借力上升、橫越風廊、常規重力落點與登頂。"),
}


def main():
    wanted = [int(a) for a in sys.argv[1:] if a.isdigit()] or list(LEVELS)
    judge = sys.argv[sys.argv.index("--judge") + 1] if "--judge" in sys.argv else "normal"
    assert judge == "normal" or "--write" not in sys.argv, "寫檔只用普通判定"
    set_judge(judge)
    print(f"判定：{judge}  早 {JUDGES[judge][0]} 幀／晚 {JUDGES[judge][1]} 幀")
    for n in wanted:
        build, cls, desc = LEVELS[n]
        print(f"═════ Demo 第 {n} 關 ═════")
        pat = Patterns()
        chunks = build(pat)
        text = render_level(cls, [desc, "地形由 tools/gen_demo.py（tools/course_kit.py）的物理模擬算出。"],
                            pat.items, chunks)
        if "--write" in sys.argv:
            out = Path(__file__).resolve().parent.parent / f"scripts/level/demo_{n}_data.gd"
            out.write_text(text, encoding="utf-8")
            print("written", out.name)


if __name__ == "__main__":
    main()
