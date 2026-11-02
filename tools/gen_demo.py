"""產生 Demo 關卡：scripts/level/demo_1_data.gd ～ demo_4_data.gd。

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


## 第五關：黃音符主導的節奏變奏（主題 T·T·L R 升級）
## L/T 多半用黃音符實現；尖刺極少；坑島不鋪防站樁刺；路線緩升不驟降
## 譜面：L 長按／T 輕點／R 穿環／D 穿柱／C 一般衝刺；. 半拍
NORMAL = 2400
LIGHT = 1000
## island_spikes=False：不要滿地尖刺；lasers=False：輕點黃音符往上爬時不蓋雷射頂
S5 = dict(final_rise=0, island_spikes=False, flow=False, lasers=False)


def Tap(b):
    return J(b, T)


def oT(b):
    return O(b, T)


def demo5(pat):
    ## ①→⑧ 對齊節奏草稿；黃音符底下不留多餘島；多段輕重切換
    return [
        intro("節奏變奏挑戰\n黃音符為主：有球就走球，底下不一定有平台。"
              "主題句會升級；路上會多次切換輕／重重力"),
        ## ① 開場
        section(pat, "開場Ⅰ", [
            J(0), oT(1), O(2), D(3), oT(4), O(5),
            J(7), R(8), oT(9), oT(9.5), O(10),
        ], "開場Ⅰ\n黃音符串起來；穿環後接二連點——球底下是坑",
           floor="pit", gravity=NORMAL, **S5),
        section(pat, "開場Ⅱ", [
            J(0), oT(1), oT(1.5), O(2), D(3),
            J(5), R(6), oT(7), oT(7.5), O(8),
        ], "開場Ⅱ\n二連點 + 穿柱；引導環後繼續輕點",
           floor="pit", gates=[3], gravity=NORMAL, **S5),
        bench("長椅"),
        ## 變輕一次
        section(pat, "空中變輕", [
            J(0), O(1), O(2), J(4), oT(5), O(6),
        ], "空中變輕\n穿過邊界後半變飄；黃音符會飛得更久",
           floor="pit", gravity=NORMAL, gravity_flip=(3.0, LIGHT), **S5),
        ## ② 流動（輕重力）
        section(pat, "流動Ａ", [
            J(0), R(1), oT(2), O(3),
            J(4), oT(5), oT(5.5), O(6), D(7),
            J(8), R(9), R(9.5), oT(10), O(11), D(12),
            J(13), oT(14), O(15), D(16),
        ], "流動Ａ・輕\n引導環、黃音符、半拍補能、穿柱",
           floor="pit", gates=[7, 12, 16], gravity=LIGHT, **S5),
        bench("長椅　重力恢復"),
        ## ③ 切分
        section(pat, "切分Ｂ", [
            J(0), R(1), R(1.5), D(2), oT(3), O(4),
            J(6), oT(7), O(8),
            J(10), R(11), R(11.5), D(12),
            J(13), oT(14), O(15), D(16),
        ], "切分Ｂ\n半拍補能後接黃音符",
           floor="pit", gates=[16], gravity=NORMAL, **S5),
        ## 再變輕
        section(pat, "再變輕", [
            J(0), R(1), oT(2), O(3), J(5), O(6),
        ], "再變輕\n中段邊界又變飄",
           floor="pit", gravity=NORMAL, gravity_flip=(2.5, LIGHT), **S5),
        bench("長椅　喘口氣"),
        ## ④ 緩衝
        section(pat, "緩衝", [
            J(0), O(1),
            J(2), oT(3), O(4),
            J(5), oT(6), O(7),
            J(8), O(9),
        ], "緩衝\n黃音符放慢——球路為主；下一段再變輕",
           floor="pit", gravity=NORMAL, **S5),
        bench("長椅"),
        ## ⑤ 空中Ｃ + 變重
        section(pat, "空中Ｃ", [
            J(0), R(1), R(1.5), D(2),
            J(4), R(5), R(5.5), D(6),
            J(8), R(9), R(9.5), D(10), oT(11), O(12),
            J(13), R(14), oT(15), O(16),
        ], "空中Ｃ\n輕重力連環；過邊界變重",
           floor="pit", gates=[6, 10], gravity=LIGHT, gravity_flip=(11.0, NORMAL), **S5),
        bench("長椅　最後存檔"),
        section(pat, "安可Ⅰ", FINALE5_A,
                "安可Ⅰ・主題回歸\n引導環 + 黃音符",
                floor="pit", gates=[12], gravity=NORMAL, **S5),
        ## 安可中再切一次輕
        section(pat, "安可Ⅱ上", FINALE5_B1,
                "安可Ⅱ・高潮上\n先半拍補能再接黃音符；中段變輕",
                floor="pit", gates=[8, 17], gravity=NORMAL, gravity_flip=(9.0, LIGHT), **S5),
        section(pat, "安可Ⅱ下", FINALE5_B2,
                "安可Ⅱ・高潮下\n輕重力收尾串接",
                floor="pit", gates=[10], gravity=LIGHT, **S5),
        section(pat, "終章", FINALE5_C,
                "終章\n常規重力爆發收束",
                floor="pit", finale=True, gates=[3], gravity=NORMAL, **S5),
    ]


## 安可：地面跳數−1 = stepped 站次加總
## 黃音符句與穿環句錯開，中間留落地空拍（避免環貼地／飛頂）
FINALE5_A = [
    J(0), R(1), oT(2), O(3),
    J(5), oT(6), oT(6.5), O(7),
    J(9), R(10), O(11), D(12),
    J(13), oT(14), O(15),
]
FINALE5_B1 = [
    J(0), R(1), R(1.5), D(2), oT(3), O(4),
    J(6), R(7), R(7.5), D(8),
    J(9), oT(10), oT(10.5), O(11),
    J(13), R(14), oT(15), O(16), D(17),
]
FINALE5_B2 = [
    J(0), R(1), R(1.5), D(2),
    J(4), oT(5), O(6),
    J(8), R(9), R(9.5), D(10),
    J(13), R(14), R(14.5), D(15),
]
FINALE5_C = [
    J(0), R(1), O(2), D(3),
    J(5), R(6), R(6.5), D(7),
    J(9), oT(10), oT(10.5), O(11),
    J(14), R(15), R(15.5), D(16),
]


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
    ## 輕重力展示：短、好過；有對拍音符的段落會自動放旗，純跳躍段不放
    S6 = dict(final_rise=0, island_spikes=False, flow=False, lasers=False)
    return [
        intro("輕重力體驗\n這關重點：重力變輕，跳起來會飄比較久。有黃音符的段落，先站旗子旁對拍出發"),
        section(pat, "先感受飄", [
            J(0), J(2), J(4), J(6),
        ], "先感受飄\n小島之間只跳——同樣按住空白鍵，人會在空中多停一會兒",
           floor="pit", gravity=LIGHT, **S6),
        bench("長椅"),
        section(pat, "黃音符・輕", [
            J(0), O(1), O(2),
        ], "黃音符・輕\n長按兩顆黃球過坑；球底下是空的",
           floor="pit", gravity=LIGHT, **S6),
        bench("長椅"),
        section(pat, "空中衝刺・輕", [
            J(0), D(1), J(3), D(4),
        ], "空中衝刺・輕\n飄起來後按 C 衝過寬一點的坑",
           floor="pit", gravity=LIGHT, **S6),
        bench("長椅"),
        section(pat, "輕重對照", [
            J(0), O(1), J(3), O(4),
        ], "輕重對照\n前半常規重力，過邊界變飄——同一動作手感會變",
           floor="pit", gravity=NORMAL, gravity_flip=(2.0, LIGHT), **S6),
        bench("長椅　最後存檔"),
        section(pat, "小結", [
            J(0), O(1), D(2), J(4), O(5),
        ], "小結\n黃音符接一下衝刺，感受輕重力就過關",
           floor="pit", finale=True, gravity=LIGHT, **S6),
    ]


LEVELS = {
    1: (demo1, "Demo1Data", "Demo 第一關・基礎教學：音符、長按、輕點、光柱、空中衝刺、衝刺環，一段教一樣。"),
    2: (demo2, "Demo2Data", "Demo 第二關・組合：音符補衝刺、長短交替、音符接光牆、衝刺環接音符。"),
    3: (demo3, "Demo3Data", "Demo 第三關・節奏地形：旋律平台、節拍平台、尖刺，後段一路跑到底不能停。"),
    4: (demo4, "Demo4Data", "Demo 第四關・挑戰：每段都混合音符、衝刺環、光柱和節奏地形，最後 48 拍高高低低一路跑到底。"),
    5: (demo5, "Demo5Data",
        "Demo 第五關・黃音符節奏變奏：T·T·L R 升級；多次輕重切換；球底下少留平台。"),
    6: (demo6, "Demo6Data",
        "Demo 輕重力展示：感受飄、黃音符、空中衝刺、輕重對照；有黃音符的段落先對旗出發。"),
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
