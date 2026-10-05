"""各關產生器共用：把一段連招的標準節奏轉成起跳旗的示範資料。

玩家走到旗子旁停下，下一個 8 拍循環開頭開始示範（旗子彈旋律、鏡頭跟著示範角色跑一趟），
示範開始後第 16 拍響鈴換玩家（見 cue_flag.gd）。機關都是 8 拍循環，所以響鈴時剛好對得上。
"""

import json

from design import FULL

DEMO_SLOTS = 16
GHOST_STEP = 0.125


def demo_char(kind, hold):
    if kind == "jump":
        return "L" if hold >= FULL else "T"
    if kind == "orb":
        return "O" if hold >= FULL else "o"
    return {"dash": "D", "ring": "R", "gdash": "D", "pdash": "D"}[kind]


def flag_spec(script, rests=()):
    """script: [(beat, kind, hold)] → 旗子的示範連招（demo），連招必須在 8 拍內；
    rests: [(起拍, 迄拍)] 休止，開頭那格寫 '-'（示範時響收音）"""
    demo = ["."] * DEMO_SLOTS
    for (b, k, h) in script:
        s = round(b * 2)
        assert 0 <= s < DEMO_SLOTS, ("連招超過 8 拍", script)
        demo[s] = demo_char(k, h)
    for (r0, _) in rests:
        s = round(r0 * 2) % DEMO_SLOTS
        assert demo[s] == ".", ("休止開頭和動作撞在一起", r0)
        demo[s] = "-"
    return {"kind": "flag", "notes": "", "demo": "".join(demo)}


def ghost_points(sim, until_beat):
    """示範角色路徑：從第 0 拍起每 1/8 拍取一點（區塊內 px 座標，攤平成 [x0, y0, x1, y1, …]）"""
    out = []
    log = sim.log
    i = 0
    t = 0.0
    while t <= until_beat:
        while i + 1 < len(log) and log[i + 1][0] <= t:
            i += 1
        out += [round(log[i][1]), round(log[i][2])]
        t += GHOST_STEP
    return out


def landed_beat(sim, after):
    """after 拍（最後一個動作；若是衝刺要等衝完）之後，高度連續幾幀不變 = 站上地面的拍子"""
    log = sim.log
    for i in range(len(log) - 4):
        b, _, y = log[i]
        if b <= after + 0.45:
            continue
        if y > 800 or all(abs(log[i + k][2] - y) < 0.01 for k in range(1, 4)):
            return b
    return log[-1][0]


def ghost_for(sim, script):
    last = max(b for (b, _, _) in script)
    return ghost_points(sim, min(landed_beat(sim, last) + 0.5, last + 3.0))


def spec_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    return json.dumps(v, ensure_ascii=False) if isinstance(v, str) else str(v)


def render_patterns(patterns):
    out = []
    for ch, spec in patterns.items():
        extra = "".join(f', "{k}": {spec_value(v)}' for k, v in spec.items() if k not in ("kind", "notes"))
        out.append(f'\t"{ch}": {{"kind": "{spec["kind"]}", "notes": "{spec["notes"]}"{extra}}},')
    return out


def render_chunk(chunk):
    hint = chunk["hint"].replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    out = ["\t{", f'\t\t"hint": "{hint}",']
    if "bpm" in chunk:
        out.append(f'\t\t"bpm": {chunk["bpm"]},')
    for key in ("orbs", "rings"):
        if chunk.get(key):
            out.append(f'\t\t"{key}": [')
            for (x, y, n, t) in chunk[key]:
                out.append(f'\t\t\t[{x}, {y}, "{n}", {t}],')
            out.append("\t\t],")
    if chunk.get("plan"):
        p = chunk["plan"]
        out.append('\t\t"plan": [')
        for i in range(0, len(p), 8):
            out.append("\t\t\t" + ", ".join(f'[{b}, "{c}", {x}]' for (b, c, x) in p[i:i + 8]) + ",")
        out.append("\t\t],")
    if chunk.get("ghost"):
        g = chunk["ghost"]
        out.append('\t\t"ghost": [')
        for i in range(0, len(g), 16):
            out.append("\t\t\t" + ", ".join(str(v) for v in g[i:i + 16]) + ",")
        out.append("\t\t],")
    out.append('\t\t"rows": [')
    for r in chunk["rows"]:
        out.append(f'\t\t\t"{r}",')
    out += ["\t\t],", "\t},"]
    return out


def render_level(class_name, doc_lines, patterns, chunks):
    out = [f"class_name {class_name}", "extends RefCounted"]
    out += [f"## {line}" for line in doc_lines]
    out += ["", "const PATTERNS: Dictionary = {"]
    out += render_patterns(patterns)
    out += ["}", "", "const CHUNKS: Array[Dictionary] = ["]
    for chunk in chunks:
        out += render_chunk(chunk)
    out.append("]")
    return "\n".join(out) + "\n"
