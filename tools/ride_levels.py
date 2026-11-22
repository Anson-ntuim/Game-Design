#!/usr/bin/env python3
"""產生三個「搭乘機關」試作關：彈簧床、盪鞦韆、礦車軌道。

用法：python3 tools/ride_levels.py --write
輸出（已封存）scripts/level/archive/ride_trampoline_data.gd、ride_swing_data.gd、ride_minecart_data.gd、ride_mixed_data.gd。

座標：1 格 = 40 px，每段 20 列。機關參數格式見 scripts/level/level_data.gd。
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "scripts" / "level" / "archive"
ROWS = 20


class Canvas:
    def __init__(self, width: int):
        self.w = width
        self.g = [[" "] * width for _ in range(ROWS)]

    def fill(self, x0: int, x1: int, y0: int, y1: int, ch: str = "#") -> "Canvas":
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.g[y][x] = ch
        return self

    def put(self, x: int, y: int, ch: str) -> "Canvas":
        self.g[y][x] = ch
        return self

    def rows(self) -> list[str]:
        return ["".join(r) for r in self.g]


# 每關的節奏型（目前只有起跳旗）；render 時寫進 PATTERNS
PATTERNS: dict = {}
FLAG_CHARS = "fghijklmn"
## 自動前進時，旗子讓玩家在段落左端 +3.5 格停下，GO 前半拍出發（同 tools/gen_level3.py 的 START）
SWING_JUMP_BEAT = 1.0


def add_flag(canvas: Canvas, ground_row: int, jumps: list[float]) -> list:
    """在第 5 欄放起跳旗；jumps = GO 後第幾拍起跳（示範與機器人照這個按）。回傳 plan。"""
    demo = ["."] * 16
    for b in jumps:
        demo[round(b * 2)] = "L"
    ch = FLAG_CHARS[len(PATTERNS)]
    PATTERNS[ch] = {"kind": "flag", "notes": "", "demo": "".join(demo)}
    canvas.put(5, ground_row - 1, ch)
    return [[b, "L", round(140 + 155 * (b + 0.5))] for b in jumps]


def chunk(hint: str, canvas: Canvas, mechanic: str = "", **extra) -> dict:
    out = {"hint": hint, "rows": canvas.rows()}
    if mechanic:
        out["mechanic"] = mechanic
    out.update(extra)
    return out


# ---------------------------------------------------------------- 彈簧床
# 床面和地板齊平（第 16 列頂端，y = 640）。四段可達高度：60／140／280／400 px。
# 高台頂端：第 13 列（高 120，按 1 次）、第 10 列（高 240，按 2 次）、第 7 列（高 360，按 3 次）。
FLOOR = 16


def trampoline_level() -> list[dict]:
    chunks = []

    c = Canvas(14).fill(0, 13, FLOOR, 19)
    c.put(3, FLOOR - 1, "P")
    chunks.append(chunk(
        "彈簧床\n床面一直跟著拍子彈，碰到就會被彈起來。落回床面那一拍按跳，就升一段彈得更高；不按就維持高度",
        c, "trampoline_intro"))

    # 按一次：高台第 13 列
    c = Canvas(26).fill(0, 7, FLOOR, 19).fill(8, 12, 17, 19).fill(13, 25, 13, 19)
    c.put(3, FLOOR - 1, "C")
    chunks.append(chunk(
        "彈一段\n走上彈簧床，彈第一下落回床面時按跳，彈高後按住右鍵上高台",
        c, "trampoline_1", trampolines=[[8, FLOOR, 5]]))

    # 按兩次：高台第 10 列；先下到地面再上床
    c = Canvas(28).fill(0, 7, 13, 19).fill(8, 11, FLOOR, 19).fill(12, 16, 17, 19).fill(17, 27, 10, 19)
    c.put(2, 12, "C")
    chunks.append(chunk(
        "彈兩段\n連續兩次在落床那一拍按跳：1、1、2 拍，越高越慢",
        c, "trampoline_2", trampolines=[[12, FLOOR, 5]]))

    # 按三次：高台第 7 列
    c = Canvas(28).fill(0, 7, 10, 19).fill(8, 11, FLOOR, 19).fill(12, 16, 17, 19).fill(17, 27, 7, 19)
    c.put(2, 9, "C")
    chunks.append(chunk(
        "彈到最高\n三次都按準才彈得到第四段；節奏是 1、1、2、2 拍",
        c, "trampoline_3", trampolines=[[12, FLOOR, 5]]))

    # 接力：兩張床中間是尖刺坑
    c = Canvas(40)
    c.fill(0, 5, 7, 19)              # 起點高台（接上一段第 7 列）
    c.fill(6, 9, FLOOR, 19)          # 落地
    c.fill(10, 13, 17, 19)           # 床 A 底座
    c.fill(14, 17, 10, 19)           # 中間平台（第 10 列，按兩次）
    c.fill(18, 19, FLOOR, 19)        # 尖刺坑
    for x in range(18, 20):
        c.put(x, FLOOR - 1, "^")
    c.fill(20, 24, 17, 19)           # 床 B 底座
    c.fill(25, 39, 7, 19)            # 終點高台（第 7 列，按三次）
    c.put(2, 6, "C")
    chunks.append(chunk(
        "床接床\n先彈兩段上中間平台，跳過尖刺落到第二張床，再彈到最高",
        c, "trampoline_4", trampolines=[[10, FLOOR, 4], [20, FLOOR, 5]]))

    c = Canvas(14).fill(0, 13, 7, 19)
    c.put(6, 6, "G")
    chunks.append(chunk("終點", c, "goal"))
    return chunks


# ---------------------------------------------------------------- 盪鞦韆
# 地面在第 12 列頂端（y = 480），中間是坑。鞦韆一般 4 拍來回、慢鞦韆 8 拍。完美放手：vx 420、vy 820（px/s）。
# 位置由 tools 內試算：完美放手約飛 9 格才落回第 12 列。
GROUND = 12


def swing_level() -> list[dict]:
    chunks = []

    c = Canvas(14).fill(0, 13, GROUND, 19)
    c.put(3, GROUND - 1, "P")
    chunks.append(chunk(
        "盪鞦韆\n跳起來碰到座椅就會抓住，座椅一直跟著拍子擺盪",
        c, "swing_intro"))

    c = Canvas(34).fill(0, 8, GROUND, 19).fill(21, 33, GROUND, 19)
    c.put(0, GROUND - 1, "C")
    plan = add_flag(c, GROUND, [SWING_JUMP_BEAT])
    chunks.append(chunk(
        "盪到最高再放手\n旗子前會停下，GO 後一拍在高台邊起跳抓鞦韆。星星是往前最高的位置，盪到最高那一拍按跳才飛得過去",
        c, "swing_1", swings=[[12.5, 5, 4, 4, 1, 0]], plan=plan))

    # 第二座比第一座晚 3 拍到頂：第 0 拍放手、飛行中抓住、第 3 拍再放手
    c = Canvas(46).fill(0, 8, GROUND, 19).fill(34, 45, GROUND, 19)
    c.put(0, GROUND - 1, "C")
    plan = add_flag(c, GROUND, [SWING_JUMP_BEAT])
    chunks.append(chunk(
        "鞦韆接力\n第一座放手後在空中抓住第二座，第二座晚三拍到頂：按、（三拍）、按",
        c, "swing_2", swings=[[12.5, 5, 4, 4, 1, 0], [25.5, 5.5, 3.5, 4, 1, 3]], plan=plan))

    c = Canvas(33).fill(0, 8, GROUND, 19).fill(21, 32, 10, 19)
    c.put(0, GROUND - 1, "C")
    plan = add_flag(c, GROUND, [SWING_JUMP_BEAT])
    chunks.append(chunk(
        "慢鞦韆\n這座來回要兩小節（8 拍），抓住後慢慢數，到最高那一拍再放手，目標比較高",
        c, "swing_3", swings=[[12.5, 4, 5, 8, 1, 0]], plan=plan))

    c = Canvas(14).fill(0, 13, 10, 19)
    c.put(6, 9, "G")
    chunks.append(chunk("終點", c, "goal"))
    return chunks


# ---------------------------------------------------------------- 礦車
# 地面在第 16 列頂端；軌面同高。速度 4 格／拍，所以第 k 拍在起點右邊 4k 格。
SPEED = 4.0


def rail_x(start: float, beat: float) -> float:
    return start + beat * SPEED


def minecart_level() -> list[dict]:
    chunks = []

    c = Canvas(14).fill(0, 13, FLOOR, 19)
    c.put(3, FLOOR - 1, "P")
    chunks.append(chunk(
        "礦車\n走進礦車就會上車，下一拍發車。軌道上每拍一道刻痕，黃色箭頭是按跳的位置",
        c, "minecart_intro"))

    # 只跳尖刺
    start, beats = 6.0, 11
    end = rail_x(start, beats)
    width = int(end) + 12
    c = Canvas(width).fill(0, width - 1, FLOOR, 19)
    c.put(2, FLOOR - 1, "C")
    chunks.append(chunk(
        "跳過尖刺\n按跳時礦車連人一起跳一拍；在尖刺前半拍起跳",
        c, "minecart_1",
        rails=[{"points": [start, FLOOR, end, FLOOR], "speed": SPEED, "spikes": [3, 6, 8, 9]}]))

    # 斷軌：連續兩拍都要在空中
    start, beats = 6.0, 12
    end = rail_x(start, beats)
    width = int(end) + 12
    gaps = [[2.3, 2.7], [5.3, 5.7], [6.3, 6.7], [9.3, 9.7]]
    c = Canvas(width).fill(0, width - 1, FLOOR, 19)
    for g0, g1 in gaps:
        x0 = int(rail_x(start, g0)) - 1
        x1 = int(rail_x(start, g1)) + 1
        c.fill(x0, x1, FLOOR, 19, " ")
    c.put(2, FLOOR - 1, "C")
    chunks.append(chunk(
        "斷軌\n軌道斷掉的地方要在空中通過；第 5、6 拍連跳兩下",
        c, "minecart_2",
        rails=[{"points": [start, FLOOR, end, FLOOR], "speed": SPEED, "gaps": gaps}]))

    # 攻擊：木箱要打碎；第 7.9 拍的木箱在跳過斷軌的空中，要在空中打
    start, beats = 6.0, 13
    end = rail_x(start, beats)
    width = int(end) + 12
    gaps = [[7.3, 7.7]]
    c = Canvas(width).fill(0, width - 1, FLOOR, 19)
    for g0, g1 in gaps:
        c.fill(int(rail_x(start, g0)) - 1, int(rail_x(start, g1)) + 1, FLOOR, 19, " ")
    c.put(2, FLOOR - 1, "C")
    chunks.append(chunk(
        "攻擊木箱\n在車上按衝刺鍵會用鼓棒往前敲。木箱比跳得還高，看到橘色星星就敲碎它；空中也能敲，但揮空要等一拍",
        c, "minecart_attack",
        rails=[{"points": [start, FLOOR, end, FLOOR], "speed": SPEED, "crates": [2, 4, 5, 7.9, 11],
                "spikes": [10], "gaps": gaps}]))

    # 低樑：不能跳；跳、停交替。中段有一座小丘
    start = 6.0
    pts = [start, FLOOR, start + 14, FLOOR, start + 22, FLOOR - 3, start + 34, FLOOR - 3, start + 42, FLOOR,
           start + 58, FLOOR]
    c = Canvas(int(start + 58) + 12).fill(0, int(start + 58) + 11, FLOOR, 19)
    c.fill(int(start + 22), int(start + 34), FLOOR - 3, FLOOR - 1)
    c.fill(int(start + 15), int(start + 21), FLOOR - 1, FLOOR - 1)
    c.fill(int(start + 18), int(start + 21), FLOOR - 2, FLOOR - 2)
    c.fill(int(start + 35), int(start + 41), FLOOR - 1, FLOOR - 1)
    c.fill(int(start + 35), int(start + 38), FLOOR - 2, FLOOR - 2)
    c.put(2, FLOOR - 1, "C")
    chunks.append(chunk(
        "低樑\n紅條紋的低樑經過時不能在空中：跳、停、跳、停、跳，下坡後連跳兩下再停",
        c, "minecart_3",
        rails=[{"points": pts, "speed": SPEED, "spikes": [2, 6, 8, 11.5, 12.5], "beams": [3, 7, 13.5]}]))

    c = Canvas(14).fill(0, 13, FLOOR, 19)
    c.put(6, FLOOR - 1, "G")
    chunks.append(chunk("終點", c, "goal"))
    return chunks


# ---------------------------------------------------------------- 混合
# 三種機關串在一起：彈簧床 → 盪鞦韆 → 礦車 → 從高處落到彈簧床。
# 高台在第 10 列（比地面高 6 格）；鞦韆參數照盪鞦韆關，整體往上移 2 列。
LEDGE = 10


def mixed_level() -> list[dict]:
    chunks = []

    c = Canvas(14).fill(0, 13, FLOOR, 19)
    c.put(3, FLOOR - 1, "P")
    chunks.append(chunk(
        "機關大集合\n彈簧床、盪鞦韆、礦車串在一起，每換一種機關都要重新抓節奏",
        c, "mix_intro"))

    # 彈兩段上高台
    c = Canvas(22).fill(0, 7, FLOOR, 19).fill(8, 12, 17, 19).fill(13, 21, LEDGE, 19)
    c.put(3, FLOOR - 1, "C")
    chunks.append(chunk(
        "彈上去再盪過去\n彈簧床按兩次上高台，高台上的旗子停一下，GO 後一拍起跳抓鞦韆，盪到最高那一拍放手",
        c, "mix_1", trampolines=[[8, FLOOR, 5]]))
    # 高台上接鞦韆飛過坑（跟盪鞦韆關第一段同一個形狀，整體高 2 列）
    c = Canvas(34).fill(0, 8, LEDGE, 19).fill(21, 33, LEDGE, 19)
    c.put(0, LEDGE - 1, "C")
    plan = add_flag(c, LEDGE, [SWING_JUMP_BEAT])
    chunks.append(chunk("", c, "mix_1b", swings=[[12.5, LEDGE - 7, 4, 4, 1, 0]], plan=plan))

    # 鞦韆飛到對岸直接進礦車：尖刺、木箱、斷軌、空中木箱
    start, beats = 25.0, 11
    end = rail_x(start, beats)
    width = int(end) + 8
    gaps = [[6.3, 6.7]]
    c = Canvas(width).fill(0, 8, LEDGE, 19).fill(21, width - 1, LEDGE, 19)
    for g0, g1 in gaps:
        c.fill(int(rail_x(start, g0)) - 1, int(rail_x(start, g1)) + 1, LEDGE, 19, " ")
    c.put(0, LEDGE - 1, "C")
    plan = add_flag(c, LEDGE, [SWING_JUMP_BEAT])
    chunks.append(chunk(
        "盪進礦車\n落地後走進礦車。黃色跳、橘色敲：斷軌跳起來後，空中還有一個木箱要敲",
        c, "mix_2", swings=[[12.5, LEDGE - 7, 4, 4, 1, 0]], plan=plan,
        rails=[{"points": [start, LEDGE, end, LEDGE], "speed": SPEED, "spikes": [3, 9],
                "crates": [2, 5, 6.9], "gaps": gaps}]))

    # 從高台跳下去落在彈簧床上，一碰到就開始彈；按三次彈到最高的第 7 列
    c = Canvas(30).fill(0, 5, LEDGE, 19).fill(6, 7, FLOOR, 19).fill(8, 14, 17, 19).fill(15, 29, 7, 19)
    c.put(0, LEDGE - 1, "C")
    chunks.append(chunk(
        "跳下彈簧床\n從高台直接跳到床上，床會馬上把你彈起來；連按三次彈到最高",
        c, "mix_3", trampolines=[[8, FLOOR, 7]]))

    c = Canvas(14).fill(0, 13, 7, 19)
    c.put(6, 6, "G")
    chunks.append(chunk("終點", c, "goal"))
    return chunks


# ---------------------------------------------------------------- 輸出
def gd_value(v, indent: int) -> str:
    pad = "\t" * indent
    if isinstance(v, dict):
        if not v:
            return "{}"
        items = [f'{pad}\t{json.dumps(k, ensure_ascii=False)}: {gd_value(val, indent + 1)},' for k, val in v.items()]
        return "{\n" + "\n".join(items) + f"\n{pad}}}"
    if isinstance(v, list):
        if v and all(isinstance(x, str) for x in v):
            items = [f"{pad}\t{json.dumps(x, ensure_ascii=False)}," for x in v]
            return "[\n" + "\n".join(items) + f"\n{pad}]"
        return "[" + ", ".join(gd_value(x, indent) for x in v) + "]"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        return repr(v)
    return json.dumps(v, ensure_ascii=False)


def render(class_name: str, doc: str, chunks: list[dict], patterns: dict) -> str:
    lines = [f"class_name {class_name}", "extends RefCounted", f"## {doc}",
             "## 由 tools/ride_levels.py 產生。", "", "const PATTERNS: Dictionary = " + gd_value(patterns, 0), "",
             "const CHUNKS: Array[Dictionary] = ["]
    for ch in chunks:
        lines.append("\t" + gd_value(ch, 1) + ",")
    lines.append("]")
    return "\n".join(lines) + "\n"


LEVELS = [
    ("RideTrampolineData", "ride_trampoline_data.gd", "試作關：彈簧床（跟拍彈跳、落床按跳升段）。", trampoline_level),
    ("RideSwingData", "ride_swing_data.gd", "試作關：盪鞦韆（盪到最高那一拍放手）。", swing_level),
    ("RideMinecartData", "ride_minecart_data.gd", "試作關：礦車軌道（障礙依拍擺放）。", minecart_level),
    ("RideMixedData", "ride_mixed_data.gd", "試作關：彈簧床、盪鞦韆、礦車混合。", mixed_level),
]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()
    for cls, fname, doc, fn in LEVELS:
        PATTERNS.clear()
        chunks = fn()
        text = render(cls, doc, chunks, dict(PATTERNS))
        if args.write:
            (OUT / fname).write_text(text, encoding="utf-8")
            print("wrote", fname)
        else:
            print(text[:400])


if __name__ == "__main__":
    main()
