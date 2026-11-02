"""選單第四／六關：每段有不同任務，落點、長椅、下一段一起升高。

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
             "橫越風廊\n這次不爬高：起跳後下一拍按 C，越過寬坑；沒有黃音符",
             LIGHT, 0)
    c.rest("重力恢復\n先在長椅站穩，接下來滯空時間較短")
    c.course("穩重落點", [J(0), O(1)],
             "穩重落點\n正常重力下黃音符仍能接跳；跳起、下一拍借力，落在較近的高台",
             NORMAL, 4)
    c.rest("登頂前休息\n最後把向上借力與空中衝刺接起來", LIGHT)
    c.course("登頂", [J(0), O(1), D(2)],
             "登頂\n長按起跳、下一拍黃音符、再下一拍 C；先升高，再向前飛到終點平台",
             LIGHT, 4)
    return c.finish("抵達山頂\n一路爬升完成，走進終點之門")


def variations(pat):
    c = Climb(pat, 34, "節奏變奏・六種路線\n短點、穿環、階梯、光門輪流登場；每段都有長椅，先看清下一個落點")
    c.course("短點旋律", [J(0), T(1), T(1.5), O(2)],
             "短點旋律\n起跳後兩次輕點接黃音符，最後一顆長按抬高；球底下全是空的",
             NORMAL, 5)
    c.rest("環橋前長椅\n下一段改用衝刺，不再連按跳躍")
    c.course("補能環橋", [J(0), R(1), D(2)],
             "補能環橋\n起跳、C 穿亮環補回衝刺、下一拍再 C；少了補能就過不了寬坑",
             NORMAL, 1)
    c.rest("階梯前長椅\n接下來只看平台的交接，不用找黃音符")
    c.course("交替階梯", [J(0), J(2), J(4)],
             "交替階梯\n黃藍平台每兩拍交接，落地後再長按跳；落點一路抬升",
             NORMAL, 3, floor=[("beat", 1, 1), ("beat", 2, 1)])
    c.rest("光門前長椅\n下一段只有一道空中光門，先借力再穿門")
    c.course("空中光門", [J(0), O(1), D(2)],
             "空中光門\n起跳、黃音符接跳、第三下按 C 穿藍柱；整串在空中完成",
             NORMAL, 2, gates=[2])
    c.rest("風井入口\n輕重力讓接跳爬得更高，鏡頭會跟著往上", LIGHT)
    c.course("雙音風井", [J(0), O(1), O(2)],
             "雙音風井\n每拍長按一顆黃音符，連續爬升十格；上層平台接住你",
             LIGHT, 10)
    c.rest("頂層長椅\n最後一次綜合：環、音符、衝刺，沒有新機關")
    c.course("頂層收束", [J(0), R(1), O(2), D(3)],
             "頂層收束\n起跳、穿環、黃音符長按、最後 C；四下接力飛到終點高台",
             NORMAL, 4)
    return c.finish("變奏完成\n在高台上走向終點，不用再重複一輪機關")
