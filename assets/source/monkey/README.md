# 開心小猴角色素材來源

- 角色概念參考：`reference.png`，由專案成員提供。
- 動作來源圖：2026-11-11 使用 Codex 內建 image generation，依角色參考圖產生。
- 動作圖經 `tools/make_monkey_frames.py` 自動切割、縮放並統一錨點。
- 正式遊戲幀位於 `assets/characters/monkey/`；靜態備援圖為
  `assets/characters/monkey_side.png`。
- 人工審核狀態：已檢查透明背景、幀數、畫布尺寸與裁切；仍應在 Godot
  實際動畫中檢查腳底滑動、動作節奏與 60 px 顯示尺寸的辨識度。

動作來源圖與輸出對應：

| 來源圖 | 輸出 |
|---|---|
| `idle_strip.png` | `idle_0`～`idle_5` |
| `run_strip.png` | `run_0`～`run_5` |
| `air_strip.png` | `jump_0`、`apex_0`、`fall_0` |
| `orb_strip.png` | `orb_0`、`orb_1` |
| `wall_land_hurt_strip.png` | `wall_0`、`land_0`、`hurt_0` |
| `stop_start_strip.png` | `stop_0`、`stop_1`、`start_0` |
| `landing_recovery_strip.png` | `land_1`、`land_2` |
| `dash_strip.png` | `dash_0`～`dash_2` |
