# 心動之城｜平台套件規格（可直接餵圖生／切圖）

這份規格對齊目前遊戲的真實拼法，不是「好看的概念圖」。

## 遊戲怎麼畫平台（必讀）

| 項目 | 值 |
|------|----|
| 世界格子 | `TILE = 40` px |
| 碰撞／繪製 | 相鄰實心格會**合併成大矩形** `fill_rects` |
| 長地板 | `floor_left` + 重複 `floor_mid` + `floor_right`，下方用 `fill` 鋪實 |
| 細高柱 | `寬 < 56` 或 `高 > 寬×1.35` → `pillar_top` + 重複 `pillar_mid` + `pillar_base` |
| 短浮台 | `ledge` 整塊拉伸 |
| 單向 | `one_way` 整塊貼在薄矩形上（高 ≤ 22） |

常見合併後尺寸（世界座標）：

- 長地板：寬 `≥ 100`（常 200～2000+），高 `40 / 80 / 120 / 160…`（40 的倍數）
- 「看起來像柱子」：寬 `40`（1 格）或 `80`，高 `120+`——多半是關卡格子合併出來的**細長牆**，不是裝飾道具
- 浮台：寬 `40～80`，高 `40～80`

因此素材必須支援：**任意寬度橫向無縫重複**、**任意深度向下無縫填充**、**只有真正懸空的那一側才用斷崖端蓋**。

---

## 你現在看到的兩個問題＝規格缺口

1. **磚縫對不齊／粉光斷線**  
   `floor_mid` 左右邊緣不是無縫（左右像素、砂漿縫、粉紅霓虹邊必須可對接）。圖生若在左右加陰影／ vignette，遊戲一重複就會出現垂直接縫。

2. **柱子很沒意義**  
   細長矩形被畫成「獨立石柱」，旁邊地板又用「鋸齒斷崖端蓋」，中間露背景縫。  
   正確語意：細長塊是**承重牆／墩**，要與地板**平接**；斷崖端蓋只給「旁邊是空氣」的邊緣。

---

## 完整素材庫清單（檔名＝程式 `platform_kit` key）

全部輸出：**PNG、透明背景、正交側視、同一光源（左上）、同一紫石＋粉霓虹語彙**。  
建議源解析度：**256×256**（或 128×128），遊戲會依比例縮到約 `cap_h ≈ 48～120`。

### A. 地板橫向套件（最重要）

| 檔名 | 尺寸 | 用途 | 硬性接縫規則 |
|------|------|------|----------------|
| `floor_mid.png` | **256×256** | 中段無限橫向重複 | **左右邊緣必須無縫**。粉紅霓虹線 Y 座標全圖一致；砂漿縫左右可對上。禁止左右變暗、禁止單邊高光 |
| `floor_left.png` | 256×256 | **僅**左側臨空（斷崖） | 左側可鋸齒／碎石；**右側必須與 `floor_mid` 左緣像素對得上** |
| `floor_right.png` | 256×256 | **僅**右側臨空 | 右側可鋸齒；**左側必須與 `floor_mid` 右緣對得上** |
| `floor_flat_left.png` | 256×256 | 左側貼牆／貼柱（平接） | 左右皆**直邊**；右側對 `floor_mid`；左側是乾淨垂直裁切（可微圓角，不可大鋸齒） |
| `floor_flat_right.png` | 256×256 | 右側貼牆／貼柱 | 同上鏡像 |

頂面結構（全部地板片共用，單位相對 256 高）：

1. `y=0～18`：可行走頂面石（略亮）
2. `y=18～28`：**連續粉紅／洋紅霓虹線**（全寬同亮度，左右不斷）
3. `y=28～256`：錯縫磚牆（running bond）

### B. 實體填充（四向無縫）

| 檔名 | 尺寸 | 規則 |
|------|------|------|
| `fill.png` | 256×256 | **上下左右皆無縫**磚紋，**沒有**頂面、**沒有**霓虹線 |
| `wall_fill.png` | 256×256 | 可與 `fill` 同圖或略深；四向無縫；給柱身／深牆 |

### C. 結構墩／柱（貼地板，不是孤島裝飾）

| 檔名 | 尺寸 | 規則 |
|------|------|------|
| `pillar_top.png` | 160×256 | 頂部與地板同高的壓簷；**左右直邊**可與 `floor_flat_*` 平接；寬度視覺落在內容區中央 |
| `pillar_mid.png` | 128×256 | **上下無縫**重複；左右直邊；無霓虹頂線 |
| `pillar_base.png` | 160×256 | 基座；左右直邊；可略寬於 mid |

> 柱寬在遊戲裡常被拉成 40～80px。內容主體左右留 8～12% 透明亦可，但**不要**做出與地板分離的「獨立圓柱」剪影。

### D. 其他

| 檔名 | 尺寸 | 規則 |
|------|------|------|
| `ledge.png` | 256×96 | 短浮台整塊（含兩端）；頂面＋霓虹；底部可碎石；左右可輕微懸空 |
| `one_way.png` | 256×32 | 極薄單向板；全寬霓虹；可左右無縫更佳 |

---

## 驗收（生成後必做，不過就重產）

1. 把三張 `floor_mid` 橫向拼成一條：接縫處**肉眼找不到**垂直線，霓虹是一條直線。  
2. `floor_left | floor_mid | floor_mid | floor_right` 拼一條：只有最外兩側是斷崖，中間無縫。  
3. `floor_flat_left | floor_mid | floor_flat_right` 夾在兩根 `pillar_mid` 之間：柱與地板**無背景漏縫**。  
4. `fill` 做 3×3 九宮格：看不出格子邊界。  
5. 縮到遊戲尺度（約高 72～88px）仍能看清頂面與霓虹，磚縫不要糊成一團。

---

## 圖生 Prompt（複製即用）

### Prompt 0｜總規範（每張都加在最前面）

```text
Production game tileset module for a 2D side-view rhythm platformer (Godot).
Orthographic pure side view, no perspective, no three-quarter angle.
Style: painterly purple dusk masonry, soft stone grain, muted violet bricks, thin continuous magenta-pink neon rim under the walkable top lip.
Identical lighting: soft key from upper-left, no vignette, no drop shadow under the tile, no outer glow halo.
PNG with true transparent background. No text, no UI, no character, no city skyline, no mockup frame, no watermark.
Single module only, centered, full tile content must reach the LEFT and RIGHT bitmap edges where seamless is required.
```

### Prompt 1｜`floor_mid`（成敗關鍵）

```text
[Prompt 0]
Asset role: HORIZONTALLY SEAMLESS floor middle module, 256x256.
Square masonry block with walkable top lip + continuous magenta neon line at the same Y across the ENTIRE width + running-bond purple brick body below.
CRITICAL SEAMLESS: left edge pixels must tile perfectly with right edge pixels (mortar joints and neon line align).
Do NOT darken left/right borders. Do NOT add unique rocks on only one side. Do NOT put empty transparent margins on left/right.
Output exactly one tile filling the frame edge-to-edge horizontally.
```

### Prompt 2｜`floor_left` / `floor_right`

```text
[Prompt 0]
Asset role: LEFT cliff end-cap for floor, 256x256. (For right: mirror instructions.)
Left outer side: broken rocky cliff silhouette with transparency outside the rock.
Right inner side: CLEAN vertical cut that matches the seamless floor_mid left edge (same neon Y, same mortar row heights).
Top lip + magenta neon continuous until the cliff break. No city, no pillar.
```

```text
[Prompt 0]
Asset role: RIGHT cliff end-cap for floor, 256x256.
Right outer side: broken rocky cliff. Left inner side: clean vertical cut matching floor_mid right edge.
```

### Prompt 3｜`floor_flat_left` / `floor_flat_right`

```text
[Prompt 0]
Asset role: LEFT FLUSH end for floor that abuts a wall/pillar, 256x256.
BOTH left and right edges are clean straight vertical masonry cuts (no jagged cliff).
Right edge must match floor_mid. Left edge is a flat finished wall joint.
Same top lip + continuous neon. This piece exists so floors can meet pillars with ZERO background gap.
```

### Prompt 4｜`fill` / `wall_fill`

```text
[Prompt 0]
Asset role: FOUR-WAY seamless purple brick FILL, 256x256.
No top lip, no neon line, no cliff edges. Pure repeating running-bond masonry.
Top/bottom/left/right edges all seamless. Flat even lighting, no vignette.
```

### Prompt 5｜柱三段

```text
[Prompt 0]
Asset role: structural pier TOP capital, 160x256 (portrait).
Straight vertical sides. Cap molding on top that can sit under a floor lip. Not a freestanding Greek column — a square stone pier flushable to walls.
```

```text
[Prompt 0]
Asset role: structural pier MID, 128x256, VERTICALLY seamless top/bottom, straight left/right sides, purple bricks, no neon.
```

```text
[Prompt 0]
Asset role: structural pier BASE, 160x256, wider footing, straight sides, purple stone.
```

### Prompt 6｜`ledge` / `one_way`

```text
[Prompt 0]
Asset role: short floating ledge, 256x96, self-contained left-to-right piece with top lip + neon + thin brick body + slight rocky underside. Transparent around.
```

```text
[Prompt 0]
Asset role: one-way thin platform slab, 256x32, mostly the top lip + magenta neon, minimal underside, preferably horizontally seamless.
```

---

## 建議產線順序

1. 先只產 `floor_mid` → 做橫向×3 驗收，不過關就重產（不要先產一整包）。  
2. 鎖定通過的 mid 當 reference，再產 left/right/flat（寫明「match this mid’s neon Y and mortar」）。  
3. 產 `fill` 並做 3×3。  
4. 產 pillar 三段與 ledge／one_way。  
5. 丟進 `assets/themes/heartbeat_city/platforms/`，檔名與上表一致；遊戲已接 `platform_kit`。

## 一次出圖集也可以，但必須守格線

若模型只吃「一張大圖集」：用 **4×4 格子、每格 256×256、格線對齊、每格獨立透明、禁止跨格物體**，格子內容順序建議：

`floor_mid | floor_mid | floor_left | floor_right`  
`floor_flat_left | floor_flat_right | fill | wall_fill`  
`pillar_top | pillar_mid | pillar_base | ledge`  
`one_way | (空) | (空) | (空)`

切圖後仍要做「mid×3 無縫」驗收；圖集無法保證無縫時，以單張 `floor_mid` 為準重產。
