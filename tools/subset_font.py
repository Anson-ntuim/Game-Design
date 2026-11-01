"""把 Noto Sans TC 縮成只含遊戲用到的字，網頁版讀不到系統字型，中文全靠這個檔。

用法：python3 tools/subset_font.py（改過介面或關卡文字後要重跑，不然新字會變方框）
輸入：tools/fonts/NotoSansTC.ttf（可變字重原檔，資料夾有 .gdignore，不會被匯出）
輸出：assets/fonts/NotoSansTC-Game.ttf（固定 600 字重，ui_kit.gd 讀這個）
"""

from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "tools" / "fonts" / "NotoSansTC.ttf"
OUT = ROOT / "assets" / "fonts" / "NotoSansTC-Game.ttf"
WEIGHT = 600
# 程式組字串時可能出現、但原始碼裡不一定寫得到的字
EXTRA = "0123456789０１２３４５６７８９：；，。、！？（）「」『』《》【】～…—─·・→←↑↓×÷％＋－／"


def used_chars() -> set[str]:
    chars = {chr(c) for c in range(0x20, 0x7F)}
    chars.update(EXTRA)
    for folder in ("scripts", "scenes"):
        for path in (ROOT / folder).rglob("*"):
            if path.suffix in (".gd", ".tscn"):
                chars.update(path.read_text(encoding="utf-8"))
    return {c for c in chars if c.isprintable()}


def main() -> None:
    font = TTFont(SRC)
    font = instancer.instantiateVariableFont(font, {"wght": WEIGHT})
    chars = used_chars()
    options = subset.Options()
    options.layout_features = ["*"]
    options.name_IDs = ["*"]
    options.notdef_outline = True
    sub = subset.Subsetter(options)
    sub.populate(text="".join(sorted(chars)))
    sub.subset(font)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    font.save(OUT)
    missing = sorted(c for c in chars if ord(c) not in font.getBestCmap() and not c.isspace())
    print(f"{len(chars)} 字 → {OUT.relative_to(ROOT)}（{OUT.stat().st_size // 1024} KB）")
    if missing:
        print("字型裡沒有：", "".join(missing))


if __name__ == "__main__":
    main()
