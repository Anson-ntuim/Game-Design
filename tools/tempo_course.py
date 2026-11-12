"""產生新第五關：穿線強制切換全局速度，音樂／物理／機關共用同一時間倍率。"""
from pathlib import Path
import sys

from climbing_courses import Climb, J, O, D, R, NORMAL
from design import TAP
from gen_level3 import Chunk, Patterns
from level_kit import render_level

# 變速後平地：run_speed 310、REFERENCE_BPM 下每拍約 0.5s → ~3.875 tile／拍；兩拍取 8。
WALK_AFTER_TEMPO = 8


def build(patterns):
    c = Climb(patterns, 20, "強制變速線\n穿藍線放慢、橘線加速。音樂、跳躍與機關一起變速，跳躍距離不變")

    def entry(bpm, hint):
        pad_x = 3.5
        width = int(pad_x + WALK_AFTER_TEMPO + 1.5)
        tile = Chunk(width)
        tile.fill(0, width - 1, 16, 19, "#")
        bench = int(pad_x + 2)
        tile.fill(bench, bench, 15, 15, "C")
        c.add({"hint": hint, "rows": tile.lines(), "tempo_pads": [[pad_x, 16, bpm]]})

    entry(90, "慢拍入口・90 BPM\n先穿過藍線，音樂與世界一起放慢；走兩拍感受速度後再存檔出發")
    c.course("慢拍階梯", [J(0), J(2), J(4)],
             "慢拍階梯\n慢速先學會落地接跳，三座平台逐步升高；旗子可看示範", NORMAL, 3,
             floor=[("pit", 1, 1), ("pit", 2, 1)])
    entry(150, "加速入口・150 BPM\n穿過橘線後整個世界加快；走兩拍適應再出發")
    c.course("快拍光門", [J(0), O(1), D(2)],
             "快拍光門\n長按起跳、下一拍黃音符、再下一拍按 C／Shift 穿柱；節奏更緊，距離不變", NORMAL, 2,
             gates=[2])
    entry(96, "減速入口・96 BPM\n快段後穿藍線換氣，走兩拍聽清楚輕點與長按的差別")
    c.course("慢拍短句", [(0, "jump", TAP), (1, "jump", TAP), J(2), (4, "jump", TAP), J(5)],
             "慢拍短句\n兩次輕點、一次長按，落地後再點再長；減速後也要控制長短", NORMAL, 0,
             compact_islands=True, score_beats=8)
    entry(168, "極速入口・168 BPM\n先穿線走兩拍感受極速，準備好再進入連環段")
    c.course("極速環橋", [J(0), R(1), R(1.5), D(2.5)],
             "極速環橋\n穿第一環、半拍後穿第二環、再衝一次；三下都按到就能飛到對岸", NORMAL, 1)
    entry(120, "回到原拍・120 BPM\n回到熟悉速度，走兩拍後在交替平台上整理節奏")
    c.course("原拍階梯", [J(0), J(2), J(4)],
             "原拍階梯\n黃藍平台每兩拍交接；用原速重整呼吸，接下來同一段裡會變速", NORMAL, 3,
             floor=[("beat", 1, 1), ("beat", 2, 1)])
    entry(120, "混速終章入口\n起跑先維持原速；中途穿橘線加速，再穿藍線減速，每次變速後都有兩拍落地緩衝")
    # 變速線後各空出兩拍走路／落地，再接下一段連招
    c.course("混速接力",
             [J(0), O(1), D(2), J(6), R(7), D(8), J(12), O(13), D(14)],
             "混速接力\n穿線立即切速，空中也生效：120 → 156 → 90；每次變速後先落地走兩拍再連招", NORMAL, 2,
             gates=[2, 14], score_beats=18)
    finale = c.chunks[-1]
    points = finale["ghost"]
    finale["tempo_pads"] = [[round(points[round(beat / 0.125) * 2] / 40, 2), 16, bpm, 2.0]
                           for beat, bpm in [(4, 156), (10, 90)]]

    pad_x = 3.5
    width = int(pad_x + WALK_AFTER_TEMPO + 1.5)
    goal = Chunk(width)
    goal.fill(0, width - 1, 16, 19, "#")
    goal.fill(int(pad_x + WALK_AFTER_TEMPO - 1), int(pad_x + WALK_AFTER_TEMPO - 1), 15, 15, "G")
    c.add({"hint": "尾奏・回到原速\n穿最後一條線恢復 120 BPM，走兩拍感受原速後走進終點",
           "rows": goal.lines(), "tempo_pads": [[pad_x, 16, 120]]})
    return c.chunks


if __name__ == "__main__":
    patterns = Patterns()
    chunks = build(patterns)
    text = render_level("TempoCourseData", ["新第五關：慢、快、慢、極速、原速與段內混速接力。",
                                            "由 tools/tempo_course.py 產生。"], patterns.items, chunks)
    if "--write" in sys.argv:
        Path(__file__).resolve().parent.parent.joinpath("scripts/level/tempo_course_data.gd").write_text(text)
