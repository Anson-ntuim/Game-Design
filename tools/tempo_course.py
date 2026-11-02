"""產生新第五關：穿線強制切換全局速度，音樂／物理／機關共用同一時間倍率。"""
from pathlib import Path
import sys

from climbing_courses import Climb, J, O, D, R, NORMAL
from design import TAP
from gen_level3 import Chunk, Patterns
from level_kit import render_level


def build(patterns):
    c = Climb(patterns, 20, "強制變速線\n穿藍線放慢、橘線加速。音樂、跳躍與機關一起變速，跳躍距離不變")

    def entry(bpm, hint):
        tile = Chunk(12)
        tile.fill(0, 11, 16, 19, "#")
        tile.fill(6, 6, 15, 15, "C")
        c.add({"hint": hint, "rows": tile.lines(), "tempo_pads": [[4.5, 16, bpm]]})

    entry(90, "慢拍入口・90 BPM\n先穿過藍線，音樂與世界一起放慢；在長椅存下這個速度")
    c.course("慢拍階梯", [J(0), J(2), J(4)],
             "慢拍階梯\n慢速先學會落地接跳，三座平台逐步升高；旗子可看示範", NORMAL, 3,
             floor=[("pit", 1, 1), ("pit", 2, 1)])
    entry(150, "加速入口・150 BPM\n穿過橘線後整個世界加快；先在安全地面適應再出發")
    c.course("快拍光門", [J(0), O(1), D(2)],
             "快拍光門\n長按起跳、下一拍黃音符、再下一拍 C 穿柱；節奏更緊，距離不變", NORMAL, 2,
             gates=[2])
    entry(96, "減速入口・96 BPM\n快段後穿藍線換氣，聽清楚輕點與長按的差別")
    c.course("慢拍短句", [(0, "jump", TAP), (1, "jump", TAP), J(2), (4, "jump", TAP), J(5)],
             "慢拍短句\n兩次輕點、一次長按，落地後再點再長；減速後也要控制長短", NORMAL, 0,
             compact_islands=True, score_beats=8)
    entry(168, "極速入口・168 BPM\n先穿線聽四拍，準備好再進入連環段")
    c.course("極速環橋", [J(0), R(1), R(1.5), D(2.5)],
             "極速環橋\n穿第一環、半拍後穿第二環、再衝一次；補能讓空中連招接得上", NORMAL, 1)
    entry(120, "回到原拍・120 BPM\n回到熟悉速度，在交替平台上整理節奏")
    c.course("原拍階梯", [J(0), J(2), J(4)],
             "原拍階梯\n黃藍平台每兩拍交接；用原速重整呼吸，接下來同一段裡會變速", NORMAL, 3,
             floor=[("beat", 1, 1), ("beat", 2, 1)])
    entry(120, "混速終章入口\n起跑先維持原速；中途穿橘線加速，再穿藍線減速，最後恢復")
    c.course("混速接力", [J(0), O(1), D(2), J(5), R(6), D(7), J(10), O(11), D(12)],
             "混速接力\n穿線立即切速，空中也生效：120 → 156 → 90；連招、落地與變速交替", NORMAL, 2,
             gates=[2, 12], score_beats=16)
    finale = c.chunks[-1]
    points = finale["ghost"]
    finale["tempo_pads"] = [[round(points[round(beat / 0.125) * 2] / 40, 2), 16, bpm, 2.0]
                           for beat, bpm in [(4, 156), (9, 90)]]
    chunks = c.finish("尾奏・回到原速\n穿最後一條線恢復 120 BPM，再走進終點")
    chunks[-1]["tempo_pads"] = [[3.5, 16, 120]]
    return chunks


if __name__ == "__main__":
    patterns = Patterns()
    chunks = build(patterns)
    text = render_level("TempoCourseData", ["新第五關：慢、快、慢、極速、原速與段內混速接力。",
                                            "由 tools/tempo_course.py 產生。"], patterns.items, chunks)
    if "--write" in sys.argv:
        Path(__file__).resolve().parent.parent.joinpath("scripts/level/tempo_course_data.gd").write_text(text)
