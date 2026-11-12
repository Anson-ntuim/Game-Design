"""選單第七關：完整保存使用者的八段原稿，轉譯成 120 BPM 可玩的動作。
L/T 依起跳時是否在空中，決定使用地面跳或必要音符；長休止留安全步道。
R 是穿環、D 附光柱、C 不附光柱。R. 的下一動作隔半拍。
"""

import math
import sys
import sim_player
from gen_level3 import place_notes, START
from sim_player import ground
from course_kit import section, intro, bench
from design import FULL, TAP
SCORES=[
('① 開場',2400,['T · L C · T · L','L R ··· T T L','T · T · L D ·','L · R · T T L']),
('② A段',1000,['L R · T L R','T T · L D ·','L R R · T L','T · L · R · L C']),
('③ B段',2400,['T T L R. R C','L · R · T T','L R · R. C ·','T L · D T · L']),
('④ 緩衝',2400,['L ··· T ···','T · L ····','L R ···· T','L ·······']),
('⑤ C段',1000,['L R R C · T','L · R. R D ·','T T L R R C','L D · T L R']),
('⑥ 安可Ⅰ',2400,['L R ··· T T','L R · T L R','L · R · L D','T T L R ···']),
('⑦ 安可Ⅱ',1000,['T T L R. R C','L R R C · L D','T L R. R C ·','L · R T T L D','L R R. R C','T T L D · R','L · R. R C','L R R C']),
('⑧ 終章',2400,['L R ··· L D','T T L R. R C','L · R · T L','L R R C ···'])]

def plan(lines, gravity):
    previous_gravity = sim_player.GRAVITY
    sim_player.GRAVITY = gravity
    try:
        return _compile_plan(lines)
    finally:
        sim_player.GRAVITY = previous_gravity


def _compile_plan(lines):
    script, changes, gates = [], [], []
    cursor = 0.0

    def state(at):
        return place_notes(START, [ground(0, 4000)], script, at)[2]

    def can_dash(at):
        sample = state(at)
        return (not sample.on_floor and sample.y < 578
                and sample.air_dash and sample.dash_cd <= 0.001)

    for line in lines:
        tokens = line.split()
        for token_index, token in enumerate(tokens):
            if set(token) == {"·"}:
                cursor += len(token)
                continue
            action = token[0]
            beat = cursor
            sample = state(beat)
            if action in "RDC" and not can_dash(beat):
                previous = script[-1][0]
                candidates = [previous + k * 0.5 for k in range(1, int((beat - previous) * 2) + 1)]
                valid = [at for at in candidates if can_dash(at)]
                if valid:
                    beat = valid[-1]
                    changes.append((action, cursor, beat))
                else:
                    # 衝刺已用完卻沒有補能：先落地起跳，保留原稿的下一顆環。
                    land = next((previous + k * 0.5 for k in range(1, 10)
                                 if state(previous + k * 0.5).on_floor), None)
                    assert land is not None, ("cannot relaunch", action, beat)
                    script.append((land, "jump", FULL))
                    beat = max(beat, land + 1)
                    changes.append(("insert L then " + action, land, beat))
            next_is_rest = token_index + 1 < len(tokens) and "·" in tokens[token_index + 1]
            if action == "T" and not sample.on_floor and next_is_rest:
                land = next((beat + delay for delay in (0.5, 1.0) if state(beat + delay).on_floor), None)
                if land is not None:
                    changes.append(("T land", beat, land))
                    beat, sample = land, state(land)
            if action in "LT":
                kind = "jump" if sample.on_floor or sample.coyote > 0 else "orb"
                script.append((beat, kind, FULL if action == "L" else TAP))
            else:
                script.append((beat, "ring" if action == "R" else "dash", 0))
                if action == "D":
                    gates.append(beat)
            cursor += 0.5 if token.endswith(".") else 1.0
        cursor = math.ceil(cursor / 8) * 8
    return script, gates, changes, cursor



def build(pat):
    chunks = []
    row = 30
    changes = []
    start = intro("第七關・節奏變奏\n八段完整譜面，120 BPM；旗子按 ↑ 看整段示範。空白鍵長／短跳，C／Shift 穿環或衝刺")
    start["row_offset"] = row
    chunks.append(start)
    rises = [2, 2, 2, 0, 2, 2, 3, 2]
    descriptions = [
        "短跳、長跳交錯；三拍休止留安全路面，二連點建立主題",
        "輕重力讓環與音符串起來；這段一路流動，落地再起跳",
        "正常重力的半拍切分；聽清楚細拍，R 點後下一環隔半拍",
        "配樂降低，三到七拍不必按動作；在安全步道調整節奏",
        "輕重力空中連環；穿環補能，接普通衝刺或藍色光柱",
        "開場旋律回歸；短跳句結合穿環，正常重力落地銜接",
        "輕重力高潮，八句連續變奏；半拍補能、落地重起與光柱交替",
        "恢復正常重力，最後四句爆發；最後三拍沿安全步道走向終點",
    ]
    for i, (name, gravity, lines) in enumerate(SCORES):
        script, gates, adapted, beats = plan(lines, gravity)
        changes.append((name, lines, script, adapted, beats, gravity))
        chunk = section(pat, name, script, name + "\n" + descriptions[i],
                        gravity=gravity, final_rise=rises[i], gates=gates,
                        lasers=True, island_spikes=i in (1, 6), audit_air=True,
                        require_ring_use=False, compact_islands=True,
                        score_beats=beats, flag=True)
        chunk.update(row_offset=row, score_beats=beats,
                     subdivision_cue=i in (2, 6), music_duck=0.65 if i == 3 else 0.0)
        chunks.append(chunk)
        row -= rises[i]
        if i < 7:
            next_gravity = SCORES[i + 1][1]
            rest = bench("長椅・下一段「%s」\n%s，準備好再跟旗子出發" %
                         (SCORES[i + 1][0], "輕重力" if next_gravity == 1000 else "正常重力"))
            rest.update(row_offset=row, gravity=next_gravity)
            chunks.append(rest)
    from gen_level3 import Chunk
    goal = Chunk(12)
    goal.fill(0, 11, 16, 19, "#")
    goal.fill(7, 7, 15, 15, "G")
    chunks.append({"hint": "尾奏・變奏完成\n最後一組動作完成，沿平台走進終點", "rows": goal.lines(), "row_offset": row})
    if "--write" in sys.argv:
        write_design(changes)
    return chunks


def write_design(changes):
    from pathlib import Path
    out = ["# 節奏變奏新版譜面（現為第七關）", "", "改版前版本：`9474a0c`。選單第七關對應 `Demo5Data`，第五關不變。", "",
           "全關以 120 BPM 製作，每句補齊為 8 拍。R. 後接半拍；長休止是不用按動作的安全步道，可以繼續走，不要求突然煞停。", "",
           "A 段、C 段、安可Ⅱ使用 1000 輕重力，其他為 2400 正常重力；在長椅進入下一段前切換。", "",
           "L/T 在空中才放必要黃音符，地面短跳用缺口，不在音符下墊地板。單顆環可當節奏引導，連環段提供衝刺補能；A 段與安可Ⅱ的落腳島加入少量節奏尖刺。", "",
           "每段有完整示範與長椅。B 段和安可Ⅱ加入較輕的半拍提示音；緩衝段降低配樂音量。", ""]
    for name, lines, script, adapted, beats, gravity in changes:
        out += ["## " + name, "", f"{beats} 拍，{'輕' if gravity == 1000 else '正常'}重力。原稿：", "", "```text", *lines, "```", ""]
        if adapted:
            out += ["依物理調整（拍數由本段第 0 拍起）：", ""]
            for kind, old, new in adapted:
                if kind.startswith("insert"):
                    out += [f"- 原稿有 D 後直接接 R，空中衝刺已用掉；第 {old:g} 拍增加一次落地長跳，再於第 {new:g} 拍穿環。"]
                else:
                    out += [f"- {kind}：第 {old:g} 拍調整為第 {new:g} 拍，確保落地或空中衝刺條件成立。"]
        out += ["實作事件（J＝地面長跳、t＝地面輕點、O/o＝空中音符長／短、R＝穿環、D/C＝衝刺；D 的拍另放光柱）：", ""]
        events=[]
        for b,k,h in script:
            key=("J" if h==FULL else "t") if k=='jump' else (("O" if h==FULL else "o") if k=='orb' else ("R" if k=='ring' else "衝"))
            events.append(f"{b:g}:{key}")
        out += ["`" + "  ".join(events) + "`", ""]
    out += ["## 重建與驗證", "", "`python3 tools/gen_demo.py 5 --write`", "", "`Godot --headless --path . --fixed-fps 120 --script res://tools/check_climbing_levels.gd`", ""]
    Path(__file__).resolve().parent.parent.joinpath("docs/第六關新版譜面.md").write_text("\n".join(out))
