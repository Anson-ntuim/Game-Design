"""選單第四／七關：每段有不同任務，落點、長椅、下一段一起升高。

沿用模擬過的角色數值與旗子節奏；audit_air 會拒絕未消耗的音符、
球底下的地板、可以用地面跳替代的球，以及不提供實際補能的環。
"""

from course_kit import section, intro, bench
from design import FULL, TAP
from gen_level3 import Chunk

NORMAL, LIGHT = 2400, 1000
J = lambda b: (b, "jump", FULL)
O = lambda b: (b, "orb", FULL)
T = lambda b: (b, "orb", TAP)
D = lambda b: (b, "dash", 0)
R = lambda b: (b, "ring", 0)


class Climb:
    def __init__(self, patterns, start_row_offset, hint):
        self.patterns = patterns
        self.row = start_row_offset
        self.chunks = []
        self.add(intro(hint))

    def add(self, chunk):
        chunk["row_offset"] = self.row
        self.chunks.append(chunk)

    def course(self, name, script, hint, gravity, rise, **kwargs):
        self.add(section(
            self.patterns, name, script, hint, gravity=gravity, final_rise=rise,
            island_spikes=False, lasers=False, audit_air=True, flag=True, **kwargs))
        self.row -= rise
        assert self.row >= 0, "要為最高的落點保留鏡頭上方空間"

    def rest(self, hint, gravity=NORMAL):
        chunk = bench(hint)
        chunk["gravity"] = gravity
        self.add(chunk)

    def finish(self, hint):
        c = Chunk(12)
        c.fill(0, 11, 16, 19, "#")
        c.fill(7, 7, 15, 15, "G")
        self.add({"hint": hint, "rows": c.lines()})
        return self.chunks


def low_gravity(pat):
    c = Climb(pat, 28, "輕重力・向上旅行\n先用普通跳躍爬階，再借音符登高；站旗子旁按 ↑ 可看路線")
    c.course("浮空階梯", [J(0), J(3), J(6)],
             "浮空階梯\n按住跳躍，落穩再跳；三座平台逐步升高，這裡不用音符",
             LIGHT, 6, floor=[("pit", 2, 1), ("pit", 4, 1)])
    c.rest("高台長椅\n接下來的落點更高，需要空中借力", LIGHT)
    c.course("借力上升", [J(0), O(1)],
             "借力上升\n起跳後下一拍碰黃音符再長按，登上普通跳躍到不了的高台",
             LIGHT, 7)
    c.rest("觀景長椅\n下一段換成向前的寬坑", LIGHT)
    c.course("橫越風廊", [J(0), D(1)],
             "橫越風廊\n這次不爬高：起跳後下一拍按 C／Shift，越過寬坑；沒有黃音符",
             LIGHT, 0)
    c.rest("重力恢復\n先在長椅站穩，接下來滯空時間較短")
    c.course("穩重落點", [J(0), O(1)],
             "穩重落點\n正常重力下黃音符仍能接跳；跳起、下一拍借力，落在較近的高台",
             NORMAL, 4)
    c.rest("登頂前休息\n最後把向上借力與空中衝刺接起來", LIGHT)
    c.course("登頂", [J(0), O(1), D(2)],
             "登頂\n長按起跳、下一拍黃音符、再下一拍按 C／Shift；先升高，再向前飛到終點平台",
             LIGHT, 4)
    return c.finish("抵達山頂\n一路爬升完成，走進終點之門")


def variations(pat):
    ## 草圖終章：上排／下排後接 8 拍循環×3（原速→1.5×→2×）
    return finale_sketch(pat)


def _cycle8(off: float):
    """八拍一句（刻意單調）：跳→球→穿柱，其餘拍落地換氣。變速靠 tempo_pads。"""
    return [
        J(off + 0), O(off + 1), D(off + 2),
    ]


def finale_sketch(pat):
    """依手繪草圖。
    上排：旗→1.5 連球→0.8/0.5 密拍→|光柱。
    下排一連到底（無長椅）：旗→1·2→|光柱→輕重力 3（落地）1·2→|光柱。
    再接 8 拍循環三次：原速 → 1.5 倍 → 2 倍（tempo_pads；距離不變）。
    | 是光柱不是分段；黃球底下不鋪站台，靠踩球前進。"""
    from gen_level3 import Chunk
    S = dict(island_spikes=False, lasers=False, flow=False, flag=True, audit_air=False)
    chunks = [
        intro("草圖終章\n站旗子旁對拍出發。上排拉開再收緊後穿光柱；下排一連到底，再進八拍變速"),
        section(pat, "拉開再收緊", [
            J(0),
            O(1.5), O(3.0), O(4.5), O(6.0),
            T(6.8), T(7.3), T(7.8),
            D(8.5),
        ], "拉開再收緊\n四顆長按黃球各隔 1.5 拍；再接 0.8、0.5、0.5 密拍輕點；最後一拍按 C／Shift 穿光柱",
           floor="pit", gravity=NORMAL, score_beats=11, gates=[8.5],
           orb_footholds=True, **S),
        bench("長椅\n接下來下排一連到底：黃球直接踩、光柱用 C／Shift 穿，中間沒有休息"),
        ## 下排一整段：起點、光柱後起跳台、4 拍距落地再起跳、終點有地面；黃球底下不鋪站台
        section(pat, "下排連段", [
            J(0), O(1), O(3), D(4),
            J(8), O(9), O(12), J(16), O(17), T(18), O(20), D(21),
        ], "下排連段\n先隔 1 拍、再隔 2 拍踩黃球，C／Shift 穿光柱；再起跳接球距 3，落地後接 1、2——中間不停、球下沒站台，最後再穿光柱",
           floor="pit", gravity=LIGHT, score_beats=24,
           gates=[4, 21], orb_footholds=True, **S),
        bench("長椅　八拍變速前\n接下來句型很單純，只是愈跑愈快：原速 → 1.5 倍 → 2 倍"),
        _speed_cycle(pat, S),
    ]
    c = Chunk(14)
    c.fill(0, 13, 16, 19, "#")
    c.fill(6, 6, 15, 15, "C")
    c.fill(9, 9, 15, 15, "G")
    chunks.append({
        "hint": "終點\n草圖路線跑完了；穿過最後綠線可回到原速",
        "rows": c.lines(), "gravity": NORMAL,
        "tempo_pads": [[3.5, 16, 120]],
    })
    return chunks


def _speed_cycle(pat, base_opts):
    """8 拍一句 ×3（句型簡單）；第 2／3 次開頭放 180／240 BPM 變速線（1.5×／2×）。"""
    script = _cycle8(0) + _cycle8(8) + _cycle8(16)
    opts = dict(base_opts)
    opts["flow"] = False
    chunk = section(
        pat, "八拍變速", script,
        "八拍變速\n同一句很單純：跳、球、穿柱，其餘拍換氣；跑三次只是愈來愈快——原速 → 1.5 倍 → 2 倍",
        floor="pit", gravity=NORMAL, finale=True, score_beats=24,
        gates=[2, 10, 18], orb_footholds=True, **opts)
    points = chunk.get("ghost", [])
    pads = []
    for beat, bpm in ((8.0, 180), (16.0, 240)):
        idx = round(beat / 0.125) * 2
        if idx < len(points):
            pads.append([round(float(points[idx]) / 40.0, 2), 16, bpm, 2.0])
    if pads:
        chunk["tempo_pads"] = pads
    return chunk

